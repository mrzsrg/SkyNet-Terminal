<#
.SYNOPSIS
    Звуковое сопровождение шоу SkyNet: короткие сэмплы на событиях.

.DESCRIPTION
    Ключевая идея — звук вешается на СОБЫТИЯ, а не на общую аудиодорожку.
    Шоу управляется состояниями, а не временем: кадры Sixel выводятся с той
    скоростью, с какой их успевает обработать chafa, а глитчи бросаются через
    Get-Random. Аудиодорожка фиксированной длины разъехалась бы на десятки
    секунд, поэтому здесь только короткие фразы в конкретных точках кода.

    Воспроизведение — через SkyAudio.cs (winmm). Запуск процесса на каждый звук
    давал бы 80…150 мс лага, что при выводе ТТХ по 2 мс на символ означало бы
    отставание звука на пол-экрана.

    Модуль полностью необязателен: если SkyAudio.cs не скомпилировался, нет
    звукового устройства или папки с сэмплами — все функции становятся no-op,
    шоу идёт как обычно.

.EXAMPLE
    Initialize-SkynetAudio
    Play-SkynetSound -Name 'zone_done'
    Close-SkynetAudio
#>
Set-StrictMode -Version Latest

$script:Ready = $false
$script:Volume = 70
$script:KeyThrottleMs = 45
$script:LastPlayedAt = @{}
$script:Played = 0
# Фразы длиннее этого порога не перезапускаются, пока ещё играют: иначе
# длинный пользовательский сэмпл под плотной сценой сливается в треск.
$script:RetriggerFloorMs = 900
# Курки, для которых в пакете не нашлось ни одного файла. Пишутся в лог в
# конце прогона — это единственный способ отличить «сцена звучит молча из-за
# отсутствующего файла» от «сцена не вызывает звук вовсе».
$script:MissingCues = @{}

# Фразы фонового гула: зацикливаются и всегда играют тише акцентов.
$script:AmbienceNames = @('ambient_radar')
# Громкость фона относительно общей. Было 0.5 — фон был вдвое тише акцентов,
# потом 0.625, потом 1.0. Значение 1.3 пробовалось 28.09.2026 и отменено:
# у ambient_radar пик −1.0 дБFS, то есть файл уже у полной шкалы, и +30%
# микшера уводило его пики за 0 dBFS — заведомый клиппинг. Фон громче сделать
# можно только предварительно нормализовав сам файл.
# Значение одно на оба места применения (загрузка пакета и Set-SkynetAudioVolume),
# иначе «фон на лету» и «фон при старте» разъезжались бы.
$script:AmbienceVolumeFactor = 1.0

# Индивидуальные множители громкости отдельных файлов пакета (1.0 — без
# изменений). Считаются в том же Get-SkynetFileVolume, что и фон, поэтому оба
# места применения (загрузка пакета и Set-SkynetAudioVolume) идут через одну
# функцию и не разъезжаются.
$script:TrackVolumeFactors = @{}

# Усиление отдельных файлов В САМИХ сэмплах, в децибелах, до загрузки в waveOut.
# Нужно там, где файл объективно тише остальных: громкость микшера ограничена
# диапазоном 0..100, и при общей громкости 70 её максимум — это +3.1 дБ, то
# есть через микшер такой фрагмент не вытянуть физически. Усиление применяется
# один раз при загрузке пакета, поэтому кэш в cache\audio остаётся нетронутым
# и общий уровень Audio.Volume по-прежнему управляет всеми сэмплами сразу.
$script:TrackGainsDb = @{
    'radar_sweep1' = 12.0   # RMS −32.5 дБFS против −15..−18 у остальных: с 28.09.2026 +12 дБ
}

# ---------------------------------------------------------------------------
#  ЗВУКОВЫЕ КУРКИ (cues)
#
#  Сцена не знает имён файлов — она просит «смысл»: step, glitch, blocked.
#  Слой звука сам выбирает файл из цепочки этого курка.
#
#  КАК ЧИТАТЬ ЦЕПОЧКУ
#
#  Это НЕ список вариантов «звук на выбор». Правило простое:
#
#    ПЕРВЫЙ элемент — ОСНОВНОЙ звук. Он играет всегда.
#
#    Всё, что правее — РЕЗЕРВ. Он срабатывает только в двух случаях:
#      1) основной файл удалён из assets\audio — берётся следующий;
#      2) основной длиннее $RetriggerFloorMs (900 мс) и ещё играет.
#
#  ПОЧЕМУ РЕЗЕРВ ОБЫЧНО МОЛЧИТ
#
#  Условие 2 применяется ТОЛЬКО к длинным файлам. Короткий файл (короче
#  900 мс) не может быть «занятым»: он всегда побеждает, и обход цепочки
#  на нём останавливается. Значит всё, что стоит правее короткого файла,
#  не звучит, пока этот файл лежит в пакете. Убирать такой резерв нельзя —
#  он оживает в тот же момент, когда основной файл исчезнет.
#
#  Практический вывод: длина ОСНОВНОГО файла — это и есть «сколько сцена
#  может молчать». Короткий основной (щелчок key_*) перекрывает всю
#  цепочку целиком. Длинный (boot_step 3,2 с) держит резерв включённым на
#  всё время своей фразы, и сцена в это время звучит следующим звеном.
#
#  ЗАЧЕМ ЦЕПОЧКИ: раньше сцена называла файл напрямую ('boot_step',
#  'glitch*'), и удаление одного файла молча выключало звук целой сцены —
#  по логу это было невозможно отличить от «устройства нет».
# ---------------------------------------------------------------------------
$script:Cues = [ordered]@{
    # --- Загрузка / терминал -------------------------------------------------
    # ВАЖНО: в цепочке каждого ПЛОТНОГО курка (boot/step/mem/scan) короткий
    # щелчок стоит РЯДОМ с длинным пользовательским сэмплом, а не только в
    # самом конце. Иначе при boot_step = 3.2 с и шаге 250 мс все варианты
    # оказываются заняты, и сцена замолкает совсем: длинный сэмпл нельзя
    # перезапускать чаще его длительности, а следующий тоже длинный.
    # Схема «сначала узнаваемый долгий звук, затем короткие щелчки» даёт и
    # характерный акцент, и непрерывный фоновый отчёт.
    'boot'       = @('boot_step', 'key_02', 'key_01', 'boot_step1', 'zone_scan')  # [INIT]/[OK]
    'step'       = @('key_02', 'key_01', 'key_03', 'key_04')  # напечатана строка (плотный поток)
    'mem'        = @('key_03', 'key_02', 'key_04', 'key_01')  # строка «дампа памяти»
    # Посимвольный набор [INIT]/[OK]: каждой строке — своя «голос» клавиши.
    # ТАК НЕЛЬЗЯ: '@('key_03','key_02','key_04','key_01')' одним курком.
    # По правилу цепочки первый файл играет всегда, а key_0X короче
    # $RetriggerFloorMs, поэтому справа всё молчало бы — четыре строки звучали
    # бы одинаково. Поэтому здесь ЧЕТЫРЕ курка по одному файлу, а порядок
    # строк задаёт вызывающий код (SkyNet.Boot).
    'type1'      = @('key_03', 'key_02', 'key_01', 'key_04')  # [INIT] Cyberdyne Systems...
    'type2'      = @('key_02', 'key_01', 'key_04', 'key_03')  # [OK] Loading...
    'type3'      = @('key_04', 'key_01', 'key_03', 'key_02')  # [OK] Establishing...
    'type4'      = @('key_01', 'key_04', 'key_02', 'key_03')  # [OK] Bypassing...
    'scan'       = @('key_02', 'key_01', 'key_03')            # символ прокрутки ТТХ
    'prompt'     = @('key_01', 'key_02')                      # пустая строка PS-промпта
    'hijack'     = @('1', 'glitch2', 'zone_done')             # терминал перехвачен
    'override'   = @('optical_ok1', 'optical_ok')             # CONNECTION OVERRIDE
    'status'     = @('optical_ok', 'online')                  # финальные статусы загрузки
    'online'     = @('online', 'optical_ok')                  # SYSTEM ONLINE
    # --- Сбои сигнала --------------------------------------------------------
    'glitch'     = @('glitch', 'glitch2', 'key_04')           # короткий фриз/разрыв кадра
    'glitch_hard'= @('glitch2', 'glitch')                     # длинный «провал сигнала»
    'alert'      = @('glitch2', '1', 'glitch')                # тревожный акцент
    # --- Пролог --------------------------------------------------------------
    # radar/zone/connect ведут на длинные сэмплы (радар 14 с, свип 3.2 с).
    # Короткий щелчок в конце цепочки — страховка: если длинный файл ещё
    # играет, сцена всё равно что-то издаёт, а не проваливается в тишину.
    'radar'      = @('radar_sweep', 'zone_scan', 'key_02')  # GLOBAL DEFENSE NETWORK
    # Строки "> SEARCHING FOR UNIT..." / "> UNIT TYPE" / "> STATUS" идут подряд
    # с интервалом ~222 мс, поэтому звук берётся на КАЖДУЮ строку, а не один раз
    # на блок. Короткого щелчка в хвосте нет намеренно: этот курок и так
    # не должен превращаться в молчание — строки идут плотно.
    'radar_line' = @('optical_ok1', 'optical_ok', 'key_02')  # строка отчёта радара
    'zone'       = @('radar_sweep1', 'zone_scan', 'key_01')  # переход на новую зону
    'zone_done'  = @('zone_done', 'optical_ok')             # зона просканирована
    'ok'         = @('optical_ok', 'online')                # пункт чек-листа «OK»
    # --- Финал: звонок и его обрыв ------------------------------------------
    'connect'    = @('radar_sweep', 'zone_scan', 'key_02')  # окно звонка открыто
    'lost'       = @('glitch2', '1', 'glitch')                # SIGNAL LOST
    'blocked'    = @('glitch2', 'glitch', 'zone_done')        # PROCESS BLOCKED
    'final'      = @('1', 'optical_ok1')                      # «I'll be back»
}

function Test-SkynetAudioReady {
    <#
    .SYNOPSIS
        Готов ли звуковой слой. Вызывать перед звуком в горячем цикле.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool] $script:Ready
}

function Get-SkynetFileVolume {
    <#
    .SYNOPSIS
        Итоговая громкость файла пакета с учётом фона и индивидуальных множителей.
    .DESCRIPTION
        Единственное место, где считается «во сколько раз фраза громче общей».
        Раньше формула дублировалась в Initialize-SkynetAudio и
        Set-SkynetAudioVolume, и любой новый множитель пришлось бы вписывать
        дважды. Фон (AmbienceVolumeFactor) и частные множители
        (TrackVolumeFactors) перемножаются, если файл попадает в оба списка.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    $factor = 1.0
    if ($script:AmbienceNames -contains $Name) { $factor *= $script:AmbienceVolumeFactor }
    if ($script:TrackVolumeFactors.ContainsKey($Name)) { $factor *= [double] $script:TrackVolumeFactors[$Name] }
    # SetVolume в SkyAudio.cs всё равно обрезает до сотни, но ограничиваем здесь же:
    # тогда в лог и в Get-SkynetAudioStats уходит ровно то, что реально играет.
    $vol = [int][Math]::Round($script:Volume * $factor)
    return [Math]::Max(0, [Math]::Min(100, $vol))
}

function Get-SkynetFileGainDb {
    <#
    .SYNOPSIS
        Усиление файла пакета в децибелах, применяемое к его PCM при загрузке.
    .DESCRIPTION
        Ноль для всех файлов, кроме перечисленных в $script:TrackGainsDb.
        Работает независимо от общей громкости Audio.Volume: усиление впечатывается
        в сэмпл один раз, а Volume уже только множит его в микшере.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    if ($script:TrackGainsDb.ContainsKey($Name)) { return [double] $script:TrackGainsDb[$Name] }
    return 0.0
}

function Initialize-SkynetAudio {
    <#
    .SYNOPSIS
        Скомпилировать SkyAudio.cs и загрузить звуковой пакет.
    .DESCRIPTION
        Параметры берутся из секции Audio в config/skynet.json. Отсутствие
        звука — не ошибка: пишется WARN/DEBUG и шоу продолжает идти без звука.
    #>
    [CmdletBinding()]
    param([switch] $Force)
    if ($script:Ready -and -not $Force) { return $true }
    $script:Ready = $false

    $cfg = $GLOBAL:_SkyNetCore
    if ($cfg) {
        try {
            # Секции конфига в SkyNet.Core «расплющиваются» в плоские ключи.
            if ($cfg.AudioEnabled -ne $true) { return $false }
            $script:Volume = [int][Math]::Round(100 * [double]$cfg.AudioVolume)
            if ($cfg.AudioKeyThrottle) { $script:KeyThrottleMs = [int]$cfg.AudioKeyThrottle }
        } catch { return $false }
    }
    $script:Volume = [Math]::Max(0, [Math]::Min(100, $script:Volume))
    if ($script:Volume -eq 0) { return $false }

    $root = [string]$GLOBAL:_SkyNetCore.ProjectRoot
    if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }
    $cs = Join-Path $PSScriptRoot 'SkyAudio.cs'
    if (-not (Test-Path -LiteralPath $cs -PathType Leaf)) {
        Write-SkynetLog -Message 'Audio: SkyAudio.cs не найден — звук отключён.' -Level 'DEBUG' -Module 'Audio'
        return $false
    }
    if (-not ('SkyAudio' -as [type])) {
        try { Add-Type -Path $cs -ErrorAction Stop } catch {
            Write-SkynetLog -Message "Audio: SkyAudio.cs не скомпилировался ($($_.Exception.Message)) — звук отключён." -Level 'WARN' -Module 'Audio'
            return $false
        }
    }
    if (-not [SkyAudio]::HasDevice) {
        $devices = try { [int][SkyAudio]::DeviceCount } catch { -1 }
        Write-SkynetLog -Message "Audio: звуковое устройство не найдено (winmm: $devices) — звук отключён." -Level 'WARN' -Module 'Audio'
        return $false
    }

    $pack = 'assets\audio'
    if ($cfg) { try { if ($cfg.AudioPack) { $pack = [string]$cfg.AudioPack } } catch { } }
    $packDir = $pack
    if (-not [System.IO.Path]::IsPathRooted($packDir)) { $packDir = Join-Path $root $pack }
    if (-not (Test-Path -LiteralPath $packDir -PathType Container)) {
        Write-SkynetLog -Message "Audio: папка сэмплов не найдена ($packDir) — звук отключён." -Level 'WARN' -Module 'Audio'
        return $false
    }

    $loaded = 0; $failed = @(); $converted = 0
    $audioExts = @('.wav', '.mp3', '.ogg', '.oga', '.flac', '.m4a', '.aac', '.opus', '.wma')
    # .wav идут первыми: если рядом лежат online.wav и online.mp3, побеждает
    # wav — иначе результат зависел бы от порядка обхода папки.
    $files = @(Get-ChildItem -LiteralPath $packDir -File -ErrorAction SilentlyContinue |
        Where-Object { $audioExts -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object @{ Expression = { if ($_.Extension -eq '.wav') { 0 } else { 1 } } }, Name)
    $seen = @{}
    foreach ($file in $files) {
        $name = $file.BaseName
        if ($seen.ContainsKey($name)) {
            Write-SkynetLog -Message "Audio: '$($file.Name)' пропущен — фраза '$name' уже загружена из другого файла." -Level 'DEBUG' -Module 'Audio'
            continue
        }
        $seen[$name] = $true
        $loop = $script:AmbienceNames -contains $name
        $vol = Get-SkynetFileVolume -Name $name
        $wav = Resolve-SkynetSamplePath -File $file -Root $root
        if (-not $wav) { $failed += $name; continue }
        if ($wav -ne $file.FullName) { $converted++ }
        if ([SkyAudio]::Load($name, $wav, $vol, $loop, (Get-SkynetFileGainDb -Name $name))) { $loaded++ } else { $failed += $name }
    }
    if ($loaded -eq 0) {
        Write-SkynetLog -Message "Audio: не загружено ни одной фразы ($([SkyAudio]::LastError)) — звук отключён." -Level 'WARN' -Module 'Audio'
        return $false
    }
    $script:Ready = $true
    $note = if ($converted -gt 0) { " (из них конвертировано: $converted)" } else { '' }
    Write-SkynetLog -Message "Audio: загружено $loaded фраз(ы) из $packDir$note." -Level 'INFO' -Module 'Audio'
    if ($failed.Count) { Write-SkynetLog -Message "Audio: не прочитаны: $($failed -join ', ')." -Level 'WARN' -Module 'Audio' }
    return $true
}

function Resolve-SkynetSamplePath {
    <#
    .SYNOPSIS
        Вернуть путь к готовому PCM-WAV для сэмпла, при необходимости сконвертировав.
    .DESCRIPTION
        SkyAudio.cs понимает только WAV PCM 16 бит. Пользователь же кладёт в папку
        что попало: mp3 с телефона, 24-битное wav, flac. Ручная конвертация — это
        лишний шаг, который почти всегда делают неправильно, поэтому любой
        неподходящий файл переводится автоматически через ffmpeg при загрузке.

        Готовый WAV сначала пробуем грузить как есть — если движок его принял,
        конвертация не нужна. Иначе (или если это не .wav) кодируем в
        cache\audio. Кэш инвалидируется по времени изменения исходника.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $File,
        [string] $Root = ''
    )
    if ($File.Extension.ToLowerInvariant() -eq '.wav') {
        # Пробуем принять файл как есть. Отказавший Load ничего не выделяет,
        # а успешную пробу сразу снимаем, чтобы не держать лишний канал waveOut.
        $probe = 'probe_' + $File.BaseName
        # Усиление (0.0) здесь не нужно: проба сразу снимается, важно только,
        # принял ли движок файл. Ноль передаём явно, потому что Load требует
        # пятый аргумент.
        if ([SkyAudio]::Load($probe, $File.FullName, 0, $false, 0.0)) {
            [void][SkyAudio]::Unload($probe)
            return $File.FullName
        }
    }
    if (-not $Root) { try { $Root = [string]$GLOBAL:_SkyNetCore.ProjectRoot } catch { } }
    if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
    $cacheDir = Join-Path $Root 'cache\audio'
    $target = Join-Path $cacheDir ($File.BaseName + '.wav')

    # Свежий кэш отдаём сразу, НЕ требуя ffmpeg: конвертация уже была
    # сделана ранее, и на машине без ffmpeg готовый результат всё равно годен.
    $cacheFresh = (Test-Path -LiteralPath $target) -and
        ((Get-Item -LiteralPath $target).LastWriteTimeUtc -ge $File.LastWriteTimeUtc)
    if ($cacheFresh) { return $target }

    # ffmpeg нужен только когда конвертировать действительно надо. Get-Command
    # возвращает $null, если ffmpeg не установлен, а под Set-StrictMode
    # -Version Latest обращение к .Source такого $null роняет весь запуск
    # (PropertyNotFoundStrict) — поэтому проверяем наличие команды заранее.
    $ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    $ffmpeg = if ($ffmpegCmd) { $ffmpegCmd.Source } else { '' }
    if (-not $ffmpeg) {
        Write-SkynetLog -Message "Audio: '$($File.Name)' не сконвертирован, ffmpeg не найден (поставьте: winget install Gyan.FFmpeg)." -Level 'WARN' -Module 'Audio'
        return ''
    }
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Force -Path $cacheDir -ErrorAction SilentlyContinue | Out-Null
    }
    if (-not (Test-Path -LiteralPath $cacheDir)) { return '' }
    # Пересобираем кэш, только если исходник новее результата.
    if (-not (Test-Path -LiteralPath $target) -or
        (Get-Item -LiteralPath $target).LastWriteTimeUtc -lt $File.LastWriteTimeUtc) {
        $args = @('-y', '-hide_banner', '-loglevel', 'error', '-i', $File.FullName,
            '-ar', '44100', '-ac', '1', '-c:a', 'pcm_s16le', $target)
        $log = & $ffmpeg @args 2>&1
        if (-not (Test-Path -LiteralPath $target)) {
            Write-SkynetLog -Message "Audio: не удалось сконвертировать $($File.Name): $log" -Level 'WARN' -Module 'Audio'
            return ''
        }
    }
    return $target
}

function Get-SkynetCueCandidates {
    <#
    .SYNOPSIS
        Разрешить имя курка в список реально загруженных фраз.
    .DESCRIPTION
        Курок — это «смысл» ('glitch', 'blocked'), а не имя файла. Здесь он
        превращается в цепочку кандидатов, из которых Play-SkynetSound берёт
        первый доступный. Пустая строка на выходе = ни одного варианта в
        пакете нет, сцена просто звучит «вхолостую» (её не роняет).
        Неизвестное имя (не курок) трактуется как имя файла: старые вызовы
        вида Play-SkynetSound -Name 'zone_done' продолжают работать.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([string] $Name = '')
    if (-not $Name) { return @() }

    $out = New-Object System.Collections.Generic.List[string]
    if ($script:Cues.Contains($Name)) {
        foreach ($candidate in $script:Cues[$Name]) {
            if ($candidate -and [SkyAudio]::Has($candidate)) { $out.Add([string]$candidate) }
        }
        # Порядок цепочки СОХРАНЯЕТСЯ: сцена получает первый доступный файл,
        # то есть строго тот, который для неё назначен. Раньше здесь курки из
        # списка VarietyCues перемешивались, и одна и та же сцена звучала то
        # своим файлом, то чужим — пользователю это и мешало.
        return $out.ToArray()
    }
    if ([SkyAudio]::Has($Name)) { $out.Add($Name) }
    return $out.ToArray()
}

function Get-SkynetCueName {
    <#
    .SYNOPSIS
        Первый доступный файл для курка (для диагностики и отчёта о прогоне).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Name = '')
    $candidates = @(Get-SkynetCueCandidates -Name $Name)
    if ($candidates.Count -eq 0) { return '' }
    return [string]$candidates[0]
}

function Play-SkynetSound {
    <#
    .SYNOPSIS
        Проиграть фразу один раз. Основная точка вызова из сцен.
    .PARAMETER Name
        Либо имя курка ('glitch', 'blocked' — см. $script:Cues), либо имя файла
        без расширения ('zone_done'). Второй вариант оставлен для совместимости.
    .PARAMETER ThrottleMs
        Не проигрывать этот курок чаще, чем раз в N мс. Нужен клавиатурному
        треску: при выводе по 2 мс на символ без этого вышел бы треск пулемёта
        вместо ровного клацанья. Счётчик свой у каждого курка, сцены не
        глушат друг друга. 0 — без ограничения.
    .DESCRIPTION
        Выбор звука ОДНОЗНАЧНЫЙ: курок отдаёт первый доступный файл своей
        цепочки, без перемешивания. Случайного выбора нет намеренно — сцена
        должна звучать тем файлом, который ей назначен.

        Отдельно есть защита от перезапуска: если фраза длиннее
        RetriggerFloorMs и ещё играет, берётся следующий по цепочке. Иначе
        длинный пользовательский сэмпл (boot_step ~3.2 с), который сцена
        дёргает каждые 250 мс, превращался бы в неразборчивый треск.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string] $Name = '',
        [int] $ThrottleMs = 0
    )
    if (-not $script:Ready) { return }
    # Троттлинг ДЕРЕВО на каждый курок, а не общий на весь сеанс. Общий
    # счётчик был второй причиной «то звук, то тишина»: фриз обновлял общую
    # отметку времени, и щелчки следующей строки (у них свой троттлинг 140 мс)
    # отбрасывались как «слишком часто» — хотя это был совсем другой звук.
    # Теперь сцена гасит только саму себя.
    if ($ThrottleMs -gt 0) {
        $now = [datetime]::UtcNow
        $last = $script:LastPlayedAt[$Name]
        if ($last -and ($now - $last).TotalMilliseconds -lt $ThrottleMs) { return }
        $script:LastPlayedAt[$Name] = $now
    }
    if (-not $Name) { return }

    # Никакого случайного выбора: имя сцены — это конкретный курок, а курок —
    # конкретная цепочка файлов. Раньше здесь оставались -Random и шаблон
    # 'glitch*', из-за чего одна и та же сцена звучала то своим файлом, то
    # чужим. Если нужен другой звук, он задаётся в таблице $script:Cues.

    # Курок: берём первый доступный вариант цепочки.
    # Первая доступная фраза и есть «настоящая» — запасные варианты нужны
    # ровно на случай, если пользователь заменил или удалил основной файл.
    $candidates = @(Get-SkynetCueCandidates -Name $Name)
    if ($candidates.Count -eq 0) {
        if ($script:Cues.Contains($Name)) { $script:MissingCues[$Name] = $true }
        return
    }

    $chosen = ''
    foreach ($candidate in $candidates) {
        if (-not [SkyAudio]::Has($candidate)) { continue }
        # Длинная фраза, которая ещё не доиграла, не перезапускается:
        # иначе «шаг» в 3 с под сцену с шагом 70 мс сливается в треск.
        $len = 0
        try { $len = [int][SkyAudio]::LengthMs($candidate) } catch { $len = 0 }
        if ($len -ge $script:RetriggerFloorMs) {
            try { if ([SkyAudio]::IsPlaying($candidate)) { continue } } catch { }
        }
        $chosen = $candidate
        break
    }
    if (-not $chosen) { return }
    try { [void][SkyAudio]::Play($chosen); $script:Played++ } catch { }
}

function Invoke-SkynetSound {
    <#
    .SYNOPSIS
        Вызвать звук из любой сцены: если звука нет — просто ничего.
    .DESCRIPTION
        Единая точка входа для Core, Boot, Prologue. Ошибки проглатываются:
        звук не имеет права останавливать шоу.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string] $Name = '',
        [int] $ThrottleMs = 0
    )
    if (-not $script:Ready) { return }
    try { Play-SkynetSound -Name $Name -ThrottleMs $ThrottleMs } catch { }
}

function Start-SkynetAmbience {
    <#
    .SYNOPSIS
        Включить фоновый гул (фразы, помеченные в пакете как зацикленные).
    #>
    [CmdletBinding()]
    param()
    if (-not $script:Ready) { return }
    try { [SkyAudio]::StartAmbience() } catch { }
}

function Stop-SkynetAmbience {
    <#
    .SYNOPSIS
        Выключить фоновый гул.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:Ready) { return }
    try { [SkyAudio]::StopAmbience() } catch { }
}

function Get-SkynetAudioPackDir {
    <#
    .SYNOPSIS
        Папка со звуковым пакетом (с учётом корня проекта).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $pack = 'assets\audio'
    $cfg = $GLOBAL:_SkyNetCore
    if ($cfg) { try { if ($cfg.AudioPack) { $pack = [string]$cfg.AudioPack } } catch { } }
    if ([System.IO.Path]::IsPathRooted($pack)) { return $pack }
    $root = [string]$GLOBAL:_SkyNetCore.ProjectRoot
    if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }
    return (Join-Path $root $pack)
}

function Set-SkynetAudioVolume {
    <#
    .SYNOPSIS
        Общая громкость 0..100 на лету, с перезаливкой буферов.
    #>
    [CmdletBinding()]
    param([int] $Value = 70)
    $script:Volume = [Math]::Max(0, [Math]::Min(100, $Value))
    if (-not $script:Ready) { return }
    $dir = Get-SkynetAudioPackDir
    if (-not (Test-Path -LiteralPath $dir)) { return }
    # Обходим те же расширения, что и загрузчик: пакет может состоять из mp3,
    # а конвертированные сэмплы лежат в кэше, и SetVolume по одним *.wav
    # оставлял весь пакет без реакции на смену громкости на лету.
    $audioExts = @('.wav', '.mp3', '.ogg', '.oga', '.flac', '.m4a', '.aac', '.opus', '.wma')
    $seen = @{}
    foreach ($file in Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
              Where-Object { $audioExts -contains $_.Extension.ToLowerInvariant() } |
              Sort-Object @{ Expression = { if ($_.Extension -eq '.wav') { 0 } else { 1 } } }, Name) {
        if ($seen.ContainsKey($file.BaseName)) { continue }
        $seen[$file.BaseName] = $true
        $vol = Get-SkynetFileVolume -Name $file.BaseName
        try { [void][SkyAudio]::SetVolume($file.BaseName, $vol) } catch { }
    }
}

function Get-SkynetAudioStats {
    <#
    .SYNOPSIS
        Сколько фраз загружено и сколько раз прозвучало — для диагностики.
    #>
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Ready  = [bool] $script:Ready
        Loaded = if ($script:Ready) { [int][SkyAudio]::LoadedCount } else { 0 }
        Played = [int] $script:Played
        Volume = [int] $script:Volume
        Missing = ($script:MissingCues.Keys | Sort-Object) -join ', '
    }
}

function Get-SkynetSoundMap {
    <#
    .SYNOPSIS
        Какие курки и на какие файлы они сейчас разрешаются.
    .DESCRIPTION
        Диагностика «почему сцена молчит»: показывает связку
        курок → файл для всего пакета, включая курки без вариантов.
    #>
    [CmdletBinding()]
    param()
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($cue in $script:Cues.Keys) {
        $candidates = @(Get-SkynetCueCandidates -Name $cue)
        $rows.Add([pscustomobject]@{
            Cue  = [string] $cue
            File = if ($candidates.Count) { $candidates -join ' | ' } else { '<НЕТ ФАЙЛА>' }
        })
    }
    return $rows
}

function Close-SkynetAudio {
    <#
    .SYNOPSIS
        Остановить гул и освободить звуковые устройства.
    .DESCRIPTION
        Перед освобождением пишет в лог статистику: сколько фраз сыграло за
        прогон. Без неё «молчащую» сцену невозможно отличить от сцены, где
        звук не сработал.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:Ready) { return }
    # Сначала освобождаем устройства, потом пишем статистику: если логгер
    # недоступен, Shutdown всё равно должен отработать.
    $played = $script:Played
    $missing = @($script:MissingCues.Keys | Sort-Object)
    try { [SkyAudio]::Shutdown() } catch { }
    try { Write-SkynetLog -Message "Audio: за прогон прозвучало $played фраз(ы)." -Level 'INFO' -Module 'Audio' } catch { }
    # Явно перечисляем курки без файлов: по логу сразу видно, какую сцену
    # пользователю надо дополнить звуком, а не гадать, где «пропал звук».
    if ($missing.Count) {
        try {
            Write-SkynetLog -Message "Audio: нет файла для курков: $($missing -join ', ') — эти сцены идут без звука." `
                -Level 'WARN' -Module 'Audio'
        } catch { }
    }
    $script:Ready = $false
}

$script:AudioExports = @(
    'Test-SkynetAudioReady', 'Initialize-SkynetAudio', 'Play-SkynetSound', 'Invoke-SkynetSound',
    'Start-SkynetAmbience', 'Stop-SkynetAmbience', 'Set-SkynetAudioVolume',
    'Get-SkynetAudioStats', 'Get-SkynetSoundMap', 'Get-SkynetCueName', 'Get-SkynetCueCandidates',
    'Get-SkynetFileVolume', 'Get-SkynetFileGainDb', 'Close-SkynetAudio'
)
Export-ModuleMember -Function $script:AudioExports

