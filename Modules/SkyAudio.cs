using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

// SkyAudio — воспроизведение коротких сэмплов и фонового гула.
//
// Почему WinMM, а не запуск процесса (SNDVOL) или WPF MediaPlayer:
//   * SoundPlayer/SNDVOL на каждый звук поднимают процесс — это 80…150 мс
//     лага. При выводе ТТХ по 2 мс на символ звук отставал бы на пол-экрана.
//   * WPF MediaPlayer требует STA и Dispatcher: из консольного потока
//     PowerShell он ведёт себя непредсказуемо.
//   * waveOut держит сэмпл в неуправляемой памяти и отдаёт его устройству
//     сразу: задержка измеряется миллисекундами.
//
// Каждой фразе достаётся собственное устройство waveOut, открытое с её же
// форматом, — тогда сэмплы с разной частотой и числом каналов не мешают
// друг другу, а переигрывание просто перезаписывает буфер.
public static class SkyAudio
{
    private const int WAVE_MAPPER = -1;
    private const int WAVE_FORMAT_PCM = 1;
    private const uint WHDR_DONE = 0x00000001;

    [StructLayout(LayoutKind.Sequential)]
    private struct WAVEFORMATEX
    {
        public short wFormatTag;
        public short nChannels;
        public int nSamplesPerSec;
        public int nAvgBytesPerSec;
        public short nBlockAlign;
        public short wBitsPerSample;
        public short cbSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WAVEHDR
    {
        public IntPtr lpData;
        public int dwBufferLength;
        public int dwBytesRecorded;
        public IntPtr dwUser;
        public int dwFlags;
        public int dwLoops;
        public IntPtr lpNext;
        public IntPtr reserved;
    }

    [DllImport("winmm.dll")] private static extern int waveOutGetNumDevs();
    [DllImport("winmm.dll")] private static extern int waveOutOpen(out IntPtr h, int dev, IntPtr fmt, IntPtr cb, IntPtr inst, int flags);
    [DllImport("winmm.dll")] private static extern int waveOutClose(IntPtr h);
    [DllImport("winmm.dll")] private static extern int waveOutPrepareHeader(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] private static extern int waveOutUnprepareHeader(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] private static extern int waveOutWrite(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] private static extern int waveOutReset(IntPtr h);

    private class Voice
    {
        public string Name = "";
        public IntPtr Handle = IntPtr.Zero;
        public WAVEHDR Header;
        public IntPtr HeaderPtr;
        public IntPtr DataPtr;
        public int DataLength;
        public short[] Source;
        public int Volume = 100;
        public bool Loop;
        public int Rate = 0;        // частота сэмпла, Гц
        public int Channels = 1;    // число каналов
    }

    private static readonly Dictionary<string, Voice> voices = new Dictionary<string, Voice>(StringComparer.OrdinalIgnoreCase);
    private static readonly object gate = new object();
    private static readonly int flagsOffset = Marshal.OffsetOf(typeof(WAVEHDR), "dwFlags").ToInt32();
    private static readonly int headerSize = Marshal.SizeOf(typeof(WAVEHDR));
    private static Thread loopThread;
    private static volatile bool loopRunning;

    /// <summary>Последняя ошибка загрузки/воспроизведения — для записи в лог.</summary>
    public static string LastError = "";

    public static int LoadedCount { get { lock (gate) { return voices.Count; } } }
    public static bool HasDevice { get { try { return waveOutGetNumDevs() > 0; } catch { return false; } } }
    /// <summary>Сколько устройств вывода видит WinMM (0 — аудиослужба
    /// недоступна или все устройства заняты). Для диагностики в лог.</summary>
    public static int DeviceCount { get { try { return waveOutGetNumDevs(); } catch { return -1; } } }
    public static bool Has(string name) { lock (gate) { return voices.ContainsKey(name ?? ""); } }

    /// <summary>Длительность фразы в мс (0 — неизвестно). Нужна слою PowerShell,
    /// чтобы не перезапускать длинный сэмпл, пока он ещё играет.</summary>
    public static int LengthMs(string name)
    {
        lock (gate)
        {
            Voice v;
            if (!voices.TryGetValue(name ?? "", out v)) return 0;
            if (v.Rate <= 0) return 0;
            return (int)(v.DataLength / 2 / v.Channels * 1000L / v.Rate);
        }
    }

    /// <summary>Играет ли фраза прямо сейчас (буфер не отыгран).</summary>
    public static bool IsPlaying(string name)
    {
        lock (gate)
        {
            Voice v;
            if (!voices.TryGetValue(name ?? "", out v) || v.Handle == IntPtr.Zero) return false;
            try { return !IsDone(v); } catch { return false; }
        }
    }

    /// <summary>
    /// Убрать фразу и освободить её устройство. Нужно пробе формата: сэмпл
    /// грузится, проверяется и сразу выгружается, чтобы не держать лишний
    /// канал waveOut открытым до конца шоу.
    /// </summary>
    public static bool Unload(string name)
    {
        lock (gate)
        {
            Voice v;
            if (!voices.TryGetValue(name ?? "", out v)) return false;
            Cleanup(v);
            voices.Remove(name ?? "");
            return true;
        }
    }

    /// <summary>Распаковка WAV: ищем блоки fmt и data, обрезаем хвост по границе сэмпла.</summary>
    private static bool TryReadWav(string path, out WAVEFORMATEX fmt, out short[] pcm)
    {
        fmt = new WAVEFORMATEX();
        pcm = null;
        byte[] bytes;
        try { bytes = File.ReadAllBytes(path); }
        catch (Exception ex) { LastError = ex.Message; return false; }

        if (bytes.Length < 44) { LastError = "файл меньше заголовка WAV"; return false; }
        if (bytes[0] != 'R' || bytes[1] != 'I' || bytes[2] != 'F' || bytes[3] != 'F') { LastError = "нет сигнатуры RIFF"; return false; }
        if (bytes[8] != 'W' || bytes[9] != 'A' || bytes[10] != 'V' || bytes[11] != 'E') { LastError = "не формат WAVE"; return false; }

        int fmtPos = -1, fmtSize = 0, dataPos = -1, dataSize = 0;
        int pos = 12;
        while (pos + 8 <= bytes.Length)
        {
            string id = "" + (char)bytes[pos] + (char)bytes[pos + 1] + (char)bytes[pos + 2] + (char)bytes[pos + 3];
            int size = BitConverter.ToInt32(bytes, pos + 4);
            if (size < 0) break;
            if (id == "fmt " && pos + 8 + 16 <= bytes.Length) { fmtPos = pos + 8; fmtSize = size; }
            else if (id == "data") { dataPos = pos + 8; dataSize = size; }
            pos += 8 + size + (size & 1);
        }
        if (fmtPos < 0 || dataPos < 0) { LastError = "нет блоков fmt/data"; return false; }
        if (dataPos + dataSize > bytes.Length) dataSize = bytes.Length - dataPos;
        if (fmtSize < 16 || dataSize < 2) { LastError = "пустой звук"; return false; }

        fmt.wFormatTag = BitConverter.ToInt16(bytes, fmtPos);
        fmt.nChannels = BitConverter.ToInt16(bytes, fmtPos + 2);
        fmt.nSamplesPerSec = BitConverter.ToInt32(bytes, fmtPos + 4);
        fmt.nAvgBytesPerSec = BitConverter.ToInt32(bytes, fmtPos + 8);
        fmt.nBlockAlign = BitConverter.ToInt16(bytes, fmtPos + 12);
        fmt.wBitsPerSample = BitConverter.ToInt16(bytes, fmtPos + 14);
        fmt.cbSize = 0;

        if (fmt.wFormatTag != WAVE_FORMAT_PCM) { LastError = "только PCM (в ffmpeg: -c:a pcm_s16le)"; return false; }
        if (fmt.wBitsPerSample != 16) { LastError = "только 16 бит"; return false; }
        if (fmt.nBlockAlign < 1) { LastError = "неверный nBlockAlign"; return false; }

        int frames = dataSize / fmt.nBlockAlign;
        pcm = new short[frames * fmt.nChannels];
        Buffer.BlockCopy(bytes, dataPos, pcm, 0, pcm.Length * 2);
        return true;
    }

    /// <summary>Скопировать сэмпл в неуправляемую память с учётом громкости.</summary>
    private static void Upload(Voice v)
    {
        short[] src = v.Source;
        byte[] bytes = new byte[src.Length * 2];
        Buffer.BlockCopy(src, 0, bytes, 0, bytes.Length);
        if (v.Volume != 100)
        {
            double k = v.Volume / 100.0;
            for (int i = 0; i < src.Length; i++)
            {
                double s = src[i] * k;
                int c = (int)Math.Max(short.MinValue, Math.Min(short.MaxValue, s));
                bytes[i * 2] = (byte)(c & 0xFF);
                bytes[i * 2 + 1] = (byte)((c >> 8) & 0xFF);
            }
        }
        Marshal.Copy(bytes, 0, v.DataPtr, bytes.Length);
    }

    private static void Cleanup(Voice v)
    {
        if (v.Handle != IntPtr.Zero) { try { waveOutReset(v.Handle); waveOutClose(v.Handle); } catch { } v.Handle = IntPtr.Zero; }
        if (v.DataPtr != IntPtr.Zero) { Marshal.FreeHGlobal(v.DataPtr); v.DataPtr = IntPtr.Zero; }
        if (v.HeaderPtr != IntPtr.Zero) { Marshal.FreeHGlobal(v.HeaderPtr); v.HeaderPtr = IntPtr.Zero; }
    }

    /// <summary>Загрузить фразу. volume — 0..100, применяется сразу к данным.</summary>
    public static bool Load(string name, string path, int volume, bool loop, double gainDb)
    {
        lock (gate)
        {
            WAVEFORMATEX fmt; short[] pcm;
            if (!TryReadWav(path, out fmt, out pcm)) return false;
            if (gainDb != 0.0) ApplyGain(pcm, gainDb);

            var v = new Voice
            {
                Name = name,
                Source = pcm,
                Volume = Math.Max(0, Math.Min(100, volume)),
                Loop = loop,
                Rate = fmt.nSamplesPerSec,
                Channels = fmt.nChannels
            };
            v.DataLength = pcm.Length * 2;
            v.DataPtr = Marshal.AllocHGlobal(v.DataLength);
            v.HeaderPtr = Marshal.AllocHGlobal(headerSize);
            // AllocHGlobal НЕ обнуляет память, а IsDone() читает dwFlags именно
            // отсюда. Без явной инициализации IsPlaying() для ещё ни разу не
            // сыгранного файла возвращает мусор из кучи, и длинная фраза от
            // запуска к запуску то звучит, то молча выпадает из цепочки.
            //
            // ВАЖНО: «не сыгран» — это dwFlags С УСТАНОВЛЕННЫМ WHDR_DONE,
            // потому что IsPlaying() = !IsDone(v). Обнуление дало бы обратное:
            // файл считался бы занятым до первого Play и длинные фразы не
            // проигрывались бы никогда.
            for (int i = 0; i < headerSize; i++) Marshal.WriteByte(v.HeaderPtr, i, 0);
            Marshal.WriteInt32(v.HeaderPtr + flagsOffset, unchecked((int)WHDR_DONE));

            IntPtr fmtPtr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WAVEFORMATEX)));
            Marshal.StructureToPtr(fmt, fmtPtr, false);
            int rc = waveOutOpen(out v.Handle, WAVE_MAPPER, fmtPtr, IntPtr.Zero, IntPtr.Zero, 0);
            Marshal.FreeHGlobal(fmtPtr);
            if (rc != 0) { LastError = "waveOutOpen вернул " + rc; Cleanup(v); return false; }

            Upload(v);
            voices[name] = v;
            return true;
        }
    }


    /// <summary>
    /// Усиление сэмпла на фиксированное число децибел прямо в PCM, до загрузки
    /// в waveOut. Зачем: громкость микшера WinMM живёт в диапазоне 0..100, и
    /// при общей громкости 70 подъём ограничен 100/70 = 1.43 (это +3.1 дБ).
    /// Этого категорически мало для тихих фрагментов: у radar_sweep1 RMS
    /// −32.5 дБFS против −15..−18 дБFS у остальных, и подъём на 12 дБ через
    /// микшер невозможен в принципе.
    /// Сигнал не срезается «в лоб»: выше колена (0.85 ≈ −1.4 дБFS) пики
    /// плавно сжимаются через tanh, поэтому уровень растёт без щелчков и без
    /// прямоугольных искажений, а выход никогда не превышает полную шкалу.
    /// </summary>
    private static void ApplyGain(short[] pcm, double gainDb)
    {
        double g = Math.Pow(10.0, gainDb / 20.0);
        const double knee = 0.85;
        for (int i = 0; i < pcm.Length; i++)
        {
            double x = pcm[i] / 32768.0 * g;
            if (x > knee) x = knee + (1.0 - knee) * Math.Tanh((x - knee) / (1.0 - knee));
            else if (x < -knee) x = -knee + (1.0 - knee) * Math.Tanh((x + knee) / (1.0 - knee));
            pcm[i] = (short)Math.Round(x * 32767.0);
        }
    }

    /// <summary>Отыграл ли буфер (флаг WHDR_DONE лежит в неуправляемой памяти).</summary>
    private static bool IsDone(Voice v)
    {
        return (Marshal.ReadInt32(v.HeaderPtr + flagsOffset) & (int)WHDR_DONE) != 0;
    }

    /// <summary>Одноразовый запуск; если фраза ещё звучит — она перезаписывается.</summary>
    public static bool Play(string name)
    {
        lock (gate)
        {
            Voice v;
            if (!voices.TryGetValue(name ?? "", out v)) return false;
            if (v.Handle == IntPtr.Zero) return false;
            try
            {
                // Сбрасывать устройство нужно ТОЛЬКО когда предыдущая фраза ещё не
                // доиграла: только тогда unprepare запрещён, и waveOutReset — это
                // способ корректно прервать буфер.
                //
                // Раньше reset вызывался БЕЗУСЛОВНО, перед каждой игрой. Это и было
                // причиной систематической задержки звука: reset останавливает поток,
                // и драйвер тратит один-два буфера на перезапуск, из-за чего щелчок
                // уходил на десятки миллисекунд позже напечатанной строки. Когда
                // буфер уже отыгран (WHDR_DONE), достаточно unprepare — он поток не
                // трогает, и звук стартует сразу.
                if (!IsDone(v)) { waveOutReset(v.Handle); }
                waveOutUnprepareHeader(v.Handle, v.HeaderPtr, headerSize);
                v.Header.lpData = v.DataPtr;
                v.Header.dwBufferLength = v.DataLength;
                v.Header.dwBytesRecorded = 0;
                v.Header.dwFlags = 0;
                v.Header.dwLoops = 0;
                Marshal.StructureToPtr(v.Header, v.HeaderPtr, false);
                waveOutPrepareHeader(v.Handle, v.HeaderPtr, headerSize);
                return waveOutWrite(v.Handle, v.HeaderPtr, headerSize) == 0;
            }
            catch (Exception ex) { LastError = ex.Message; return false; }
        }
    }

    /// <summary>Остановить фразу.</summary>
    public static bool Stop(string name)
    {
        lock (gate)
        {
            Voice v;
            if (!voices.TryGetValue(name ?? "", out v) || v.Handle == IntPtr.Zero) return false;
            try { waveOutReset(v.Handle); return true; } catch { return false; }
        }
    }

    /// <summary>Громкость фразы 0..100 с перезаливкой буфера.</summary>
    public static bool SetVolume(string name, int volume)
    {
        lock (gate)
        {
            Voice v;
            if (!voices.TryGetValue(name ?? "", out v)) return false;
            v.Volume = Math.Max(0, Math.Min(100, volume));
            Upload(v);
            return true;
        }
    }

    /// <summary>Запустить фоновый гул (фразы, помеченные как loop).</summary>
    public static void StartAmbience()
    {
        lock (gate)
        {
            foreach (var v in voices.Values)
            {
                if (!v.Loop || v.Handle == IntPtr.Zero) continue;
                try
                {
                    waveOutReset(v.Handle);
                    waveOutUnprepareHeader(v.Handle, v.HeaderPtr, headerSize);
                    v.Header.lpData = v.DataPtr;
                    v.Header.dwBufferLength = v.DataLength;
                    v.Header.dwFlags = 0;
                    Marshal.StructureToPtr(v.Header, v.HeaderPtr, false);
                    waveOutPrepareHeader(v.Handle, v.HeaderPtr, headerSize);
                    waveOutWrite(v.Handle, v.HeaderPtr, headerSize);
                }
                catch { }
            }
            if (loopThread != null) return;
            loopRunning = true;
            loopThread = new Thread(AmbienceLoop);
            loopThread.IsBackground = true;   // не должен мешать завершению шоу
            loopThread.Start();
        }
    }

    /// <summary>Остановить фоновый гул.</summary>
    public static void StopAmbience()
    {
        lock (gate)
        {
            loopRunning = false;
            foreach (var v in voices.Values)
            {
                if (!v.Loop || v.Handle == IntPtr.Zero) continue;
                try { waveOutReset(v.Handle); } catch { }
            }
        }
    }

    /// <summary>Перезаписывать зацикленные фразы по мере их окончания.</summary>
    private static void AmbienceLoop()
    {
        while (loopRunning)
        {
            Thread.Sleep(80);
            lock (gate)
            {
                if (!loopRunning) return;
                foreach (var v in voices.Values)
                {
                    if (!v.Loop || v.Handle == IntPtr.Zero) continue;
                    if (!IsDone(v)) continue;
                    try
                    {
                        waveOutUnprepareHeader(v.Handle, v.HeaderPtr, headerSize);
                        v.Header.dwFlags = 0;
                        Marshal.StructureToPtr(v.Header, v.HeaderPtr, false);
                        waveOutPrepareHeader(v.Handle, v.HeaderPtr, headerSize);
                        waveOutWrite(v.Handle, v.HeaderPtr, headerSize);
                    }
                    catch { }
                }
            }
        }
    }

    /// <summary>Освободить все устройства и память.</summary>
    public static void Shutdown()
    {
        lock (gate)
        {
            loopRunning = false;
            foreach (var v in voices.Values) Cleanup(v);
            voices.Clear();
            loopThread = null;
        }
    }
}

