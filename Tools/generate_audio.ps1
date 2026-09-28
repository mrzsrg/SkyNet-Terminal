<#
.SYNOPSIS
    Генерация стартового звукового пакета SkyNet (синтез через ffmpeg).

.DESCRIPTION
    Все звуки создаются процедурно, а не берутся из фильма: это и юридически
    чисто, и технически правильнее — квадратные волны, FM и фильтрованный шум
    дают ровно тот «холодный» sci-fi характер, который нужен терминалу.

    Формат на выходе — WAV PCM 16 бит, моно, 44100 Гц. Именно такой ждёт
    SkyAudio.cs (winmm): другой формат он не принимает.

.EXAMPLE
    .\Tools\generate_audio.ps1
    .\Tools\generate_audio.ps1 -Only zone_done,online
#>
[CmdletBinding()]
param(
    [string] $OutDir = '',
    [string] $Only = '',
    [switch] $Force,             # перезаписать уже существующие файлы
    [switch] $Preview            # проиграть результат через ffplay
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $root 'assets\audio' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# Существующие файлы по умолчанию НЕ трогаем: иначе пересборка пакета
# затёрла бы звуки, записанные вручную. Перезапись — только с -Force.
$script:Force = [bool]$Force

$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { throw 'ffmpeg не найден в PATH. Установите: winget install Gyan.FFmpeg' }

# Каждая запись: имя → массив аргументов ffmpeg.
# Общий хвост: -ar 44100 -ac 1 -c:a pcm_s16le
$pack = [ordered]@{
    'key_01' = @{ Dur = '0.040'; Src = 'anoisesrc=color=white:duration=0.040:amplitude=0.55'; Flt = 'highpass=f=2600,lowpass=f=9500,afade=t=in:st=0:d=0.001,afade=t=out:st=0.006:d=0.034,volume=0.45' }
    'key_02' = @{ Dur = '0.045'; Src = 'anoisesrc=color=white:duration=0.045:amplitude=0.55'; Flt = 'highpass=f=2200,lowpass=f=8200,afade=t=in:st=0:d=0.001,afade=t=out:st=0.008:d=0.037,volume=0.45' }
    'key_03' = @{ Dur = '0.035'; Src = 'anoisesrc=color=white:duration=0.035:amplitude=0.55'; Flt = 'highpass=f=3000,lowpass=f=11000,afade=t=in:st=0:d=0.001,afade=t=out:st=0.005:d=0.030,volume=0.42' }
    'key_04' = @{ Dur = '0.050'; Src = 'anoisesrc=color=white:duration=0.050:amplitude=0.50'; Flt = 'highpass=f=1800,lowpass=f=7000,afade=t=in:st=0:d=0.001,afade=t=out:st=0.010:d=0.040,volume=0.40' }

    # Зона сканирования: нарастающий свип 280 → 1180 Гц.
    'zone_scan' = @{ Dur = '0.45'; Src = 'aevalsrc=0.55*sin(2*PI*(280*t+0.5*900*t*t)):s=44100:d=0.45'; Flt = 'lowpass=f=3200,afade=t=in:d=0.02,afade=t=out:st=0.33:d=0.12,volume=0.55' }

    # Зона подтверждена: две чистые ноты вверх (880 → 1320 Гц).
    'zone_done' = @{ Dur = '0.30'; Src = 'sine=f=880:d=0.10'; Src2 = 'sine=f=1320:d=0.20'; Flt = '[0:a]afade=t=out:st=0.02:d=0.08[a0];[1:a]afade=t=out:st=0.08:d=0.12[a1];[a0][a1]amix=inputs=2:duration=longest,alimiter=limit=0.85,volume=0.6[out]' }

    # «SKYNET SYSTEM ONLINE» — главный акцент: длинный свип плюс звёздная подсветка.
    'online' = @{
        Dur  = '0.95'
        Src  = 'aevalsrc=0.5*sin(2*PI*(200*t+0.5*700*t*t)):s=44100:d=0.80'
        Src2 = 'sine=f=1760:d=0.55'
        Flt  = '[0:a]lowpass=f=4200,afade=t=in:d=0.01,afade=t=out:st=0.62:d=0.18[a0];[1:a]adelay=250,afade=t=out:st=0.25:d=0.25,volume=0.22[a1];[a0][a1]amix=inputs=2:duration=first,alimiter=limit=0.9,volume=0.8[out]'
    }

    # Сбой: розовый шум в полосе + низкий дрожащий тон, с эхом.
    'glitch' = @{
        Dur  = '0.28'
        Src  = 'anoisesrc=color=pink:duration=0.28:amplitude=0.65'
        Src2 = 'aevalsrc=0.35*sin(2*PI*(80+600*t)*t):s=44100:d=0.28'
        Flt  = '[0:a]bandpass=f=1700:width_type=h:w=900,aecho=0.7:0.6:45:0.4[a0];[1:a]volume=0.5[a1];[a0][a1]amix=inputs=2,alimiter=limit=0.9,afade=t=out:st=0.16:d=0.12,volume=0.7[out]'
    }

    # Радар: короткий пинг с двумя хвостами эха.
    'radar_sweep' = @{ Dur = '1.60'; Src = 'sine=f=920:d=0.14'; Flt = 'aecho=0.8:0.7:260:0.5,aecho=0.8:0.7:520:0.32,afade=t=out:st=0.06:d=0.08,volume=0.55,apad=pad_dur=1.5,atrim=0:1.6' }

    'optical_ok' = @{ Dur = '0.10'; Src = 'sine=f=1760:d=0.10'; Flt = 'afade=t=out:st=0.02:d=0.08,volume=0.45' }
    'boot_step' = @{ Dur = '0.18'; Src = 'sine=f=160:d=0.18'; Flt = 'lowpass=f=700,afade=t=out:st=0.03:d=0.15,volume=0.5' }
}

# Фоновый гул. Периоды подобраны так, чтобы 20 секунд были целым числом
# колебаний — иначе на стыке цикла слышен щелчок.
$ambience = @{
    Dur  = '20'
    Src  = 'sine=f=55:d=20'
    Src2 = 'sine=f=82.5:d=20'
    Flt  = '[0:a]volume=0.5[a0];[1:a]volume=0.28[a1];[2:a]lowpass=f=350,volume=0.7[a2];[a0][a1][a2]amix=inputs=3,afade=t=in:st=0:d=0.6,afade=t=out:st=19.4:d=0.6,alimiter=limit=0.45[out]'
    Src3 = 'anoisesrc=color=brown:duration=20:amplitude=0.25'
}

$only = if ($Only) { $Only.Split(',') | ForEach-Object { $_.Trim() } } else { $null }
$fail = @()
$made = 0
$kept = 0

function Build([string] $name, [hashtable] $spec) {
    $out = Join-Path $OutDir "$name.wav"
    if ((Test-Path -LiteralPath $out) -and -not $script:Force) {
        $script:kept++
        '  {0,-14} {1,9} {2}' -f "$name.wav", '', 'оставлен (своя версия)'
        return
    }
    $args = @('-y', '-hide_banner', '-loglevel', 'error')
    $args += @('-f', 'lavfi', '-i', $spec.Src)
    $multi = $false
    if ($spec.Src2) { $args += @('-f', 'lavfi', '-i', $spec.Src2); $multi = $true }
    if ($spec.Src3) { $args += @('-f', 'lavfi', '-i', $spec.Src3); $multi = $true }
    # Схемы с метками [0:a] работают только через -filter_complex; одиночный
    # источник проще и надёжнее отдать в -af.
    if ($multi) { $args += @('-filter_complex', $spec.Flt, '-map', '[out]') }
    else { $args += @('-af', $spec.Flt) }
    $args += @('-t', $spec.Dur)
    $args += @('-ar', '44100', '-ac', '1', '-c:a', 'pcm_s16le', $out)
    $log = & $script:ffmpeg @args 2>&1
    if (-not (Test-Path $out)) {
        $script:fail += $name
        Write-Host "  ОШИБКА $name : $log" -ForegroundColor Yellow
        return
    }
    $script:made++
    '  {0,-14} {1,7:N0} KB' -f "$name.wav", ((Get-Item $out).Length / 1KB)
}

'Генерация звукового пакета SkyNet...'
foreach ($k in $pack.Keys) {
    if ($only -and ($only -notcontains $k)) { continue }
    Build $k $pack[$k]
}
if (-not $only -or ($only -contains 'ambient_radar')) { Build 'ambient_radar' $ambience }

"`nГотово: $made файл(ов) в $OutDir"
if ($kept -gt 0) {
    "Сохранено своих версий: $kept (перезаписать — с ключом -Force)"
}
if ($fail.Count) { "НЕ УДАЛОСЬ: $($fail -join ', ')"; exit 1 }
if ($Preview) {
    Get-Command ffplay -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($f in Get-ChildItem $OutDir -Filter '*.wav') { & $_.Source -autoexit -nodisp $f.FullName }
    }
}
