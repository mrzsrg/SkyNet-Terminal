<#
.SYNOPSIS
    SkyNet Core — базовые функции, ANSI-палитра, терминал, конфигурация.

.DESCRIPTION
    Базовый модуль проекта SkyNet:
    - единый ESC-символ, доступный всем модулям ($GLOBAL:SkyEsc);
    - ANSI-палитра (truecolor phosphor green);
    - настройка терминала (UTF-8, VT-режим, фон);
    - загрузка config/skynet.json с graceful fallback;
    - геометрия консоли/экрана (Win32);
    - проверка файла логотипа.
#>

$script:ESC = [char]27

# Модули выполняются каждый в своём session state, общий у них только global scope.
# Раньше ESC жил только как $script:ESC внутри Core, поэтому модуль Render собирал
# escape-последовательности без символа ESC и рисовал мусор вида "[38;2;0m0".
# Теперь ESC и палитра публикуются в global — их видят все модули.
$GLOBAL:SkyEsc = $script:ESC

$GLOBAL:ColBright = "$($script:ESC)[38;2;0;255;70m"
$GLOBAL:ColDim    = "$($script:ESC)[38;2;0;150;50m"
$GLOBAL:ColWarn   = "$($script:ESC)[38;2;0;220;100m"
$GLOBAL:ColAccent = "$($script:ESC)[38;2;0;255;150m"
$GLOBAL:ColCrit   = "$($script:ESC)[38;2;255;90;60m"
$GLOBAL:ColError  = "$($script:ESC)[38;2;255;60;60m"
$GLOBAL:ColBold   = "$($script:ESC)[1m"
$GLOBAL:ColReset  = "$($script:ESC)[0m"

$GLOBAL:_SkyNetCore = @{
    # --- общее ---
    Version         = '2.5.3'
    ProjectName     = 'SkyNet'
    Company         = 'Cyberdyne Systems'
    ProjectRoot     = $null
    ModulesPath     = $null
    ConfigPath      = $null

    # --- логотип ---
    DefaultLogo     = 'skynet_logo.png'
    LogoPath        = $null
    LogoColor       = 'Original'
    LogoMinBytes    = 8192

    # --- рендер ---
    Charset         = 'auto'
    CharsetExplicit = $false
    Size            = 'auto'
    AutoSize        = $true
    MaxFrameWidth   = 400
    MaxFrameHeight  = 140
    RenderWidth     = 160
    RenderHeight    = 50
    CineSize        = $false
    Sixel           = $false
    ChafaPath       = $null

    # --- режимы запуска ---
    Instant         = $false
    SkipLogo        = $false
    NoAnsi          = $false
    Pause           = $false

    # --- анимация ---
    Marquee         = $true
    MarqueeText     = 'SKYNET v2.5.0  ::  LOADING NEURAL NET CORE  ::  CYBERDYNE SYSTEMS  ::  DEFENSE GRID UPLINK  ::  DO NOT POWER OFF  ::  '
    MarqueeSpeed    = 34
    HoldSeconds     = 2
    FadeInMs        = 1400
    FadeOutMs       = 1800
    ExitDelayMs     = 2500
    Flicker         = $true

    # --- boot ---
    MemDumpLines    = 35
    FinalDelayMs    = 200
    DelayMultiplier = 1
    WaitKey         = $false
    # Посимвольный набор строк [INIT]/[OK].
    # TypeDelayMs — пауза между символами. 12 мс ≈ 83 симв/с: щелчок
    # (71…101 мс) успевает звучать, набор не превращается в треск.
    # TypeSoundThrottleMs — минимальный интервал между щелчками, страхует
    # от наложений при меньшем TypeDelayMs.
    TypeSoundEnabled   = $true
    TypeDelayMs        = 12
    TypeSoundThrottleMs = 55
    # TypeLineAccent — дополнительно проигрывать длинный boot_step в конце
    # строки. По умолчанию выключено: он перекрывает набор следующей строки.
    TypeLineAccent     = $false

    # --- логирование ---
    LogEnabled      = $true
    LogFile         = $null
    LogMinLevel     = 'INFO'
    LogMaxSizeKB    = 5120
    LogRotate       = $true
    LogConsole      = $false

    # --- терминал ---
    Utf8Output      = $false
    AnsiOk          = $false
    ForceAnsi       = $false
}

$script:ModuleRoot = $PSScriptRoot
$script:ProjectRoot = Split-Path -Parent $script:ModuleRoot
try { $script:ProjectRoot = (Resolve-Path -LiteralPath $script:ProjectRoot).Path } catch { }

$GLOBAL:_SkyNetCore.ModulesPath = $script:ModuleRoot
$GLOBAL:_SkyNetCore.ProjectRoot = $script:ProjectRoot
$GLOBAL:_SkyNetCore.ConfigPath  = Join-Path $script:ProjectRoot 'config\skynet.json'

# C#-хелперы: VT-режим, шрифт консоли, Win32-геометрия окна.
foreach ($cs in 'SkyNetVt.cs', 'SkyCine.cs', 'SkyWin.cs') {
    $typeName = [System.IO.Path]::GetFileNameWithoutExtension($cs)
    if (-not ($typeName -as [type])) {
        try { Add-Type -Path (Join-Path $script:ModuleRoot $cs) -ErrorAction Stop } catch { }
    }
}
function Set-SkynetTermEnv {
    <#
    .SYNOPSIS
        Подготовить терминал: UTF-8, чёрный фон, зелёный текст.
    #>
    [CmdletBinding()]
    param()
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $GLOBAL:_SkyNetCore.Utf8Output = $true } catch { }
    try { $OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    try { [Console]::BackgroundColor = 'Black'; [Console]::ForegroundColor = 'Green' } catch { }
    try { $Host.UI.RawUI.BackgroundColor = 'Black' } catch { }
}

function Restore-SkynetTerminalPath {
    <#
    .SYNOPSIS
        Восстановить $env:PATH, если терминал запущен из Windows Terminal.
    .DESCRIPTION
        Windows Terminal — MSIX-пакет. Оболочка, запущенная из него, получает
        окружение, собранное из графа пакетов: в $env:PATH остаются 2–4 папки
        WindowsApps, и ни cmd, ни git, ни python не находятся. Пользователь
        после шоу вводит команду и получает «не распознаётся как имя ...».

        Воспроизводится без всякого профиля: обычная вкладка Windows Terminal
        с `pwsh -NoProfile` уже даёт PATH из двух записей без System32.

        Здесь PATH собирается заново из реестра (Machine + User) и
        объединяется с текущим: папки самого WT и pwsh сохраняются, дубликаты
        и регистр отбрасываются. Функция ничего не заменяет вслепую — только
        дополняет недостающее, поэтому идемпотентна и безопасна: повторный
        вызов не меняет результат.

        Вызывается в самом начале шоу: сразу становятся доступны инструменты
        (chafa, ffmpeg, wt.exe), и оставшийся после шоу терминал рабочий.
    #>
    [CmdletBinding()]
    param([switch] $Quiet)
    try {
        $current = @($env:PATH -split ';' | Where-Object { $_ -and $_.Trim() })
        $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $user = [Environment]::GetEnvironmentVariable('Path', 'User')

        $result = New-Object System.Collections.Generic.List[string]
        $seen = New-Object System.Collections.Generic.HashSet[string]
        # Порядок важен: сначала текущий PATH (папки WT/pwsh), затем реестр.
        foreach ($entry in (@($current) + @(
                    ($machine -split ';'), ($user -split ';') | ForEach-Object { $_ }))) {
            $clean = ([string]$entry).Trim().TrimEnd('\', '/')
            if (-not $clean) { continue }
            # Сравнение без учёта регистра и хвостовых слэшей: иначе
            # C:\Windows\System32 и C:\WINDOWS\SYSTEM32\ считаются разными.
            $key = $clean.ToLowerInvariant().TrimEnd('\', '/')
            if ($seen.Add($key)) { $result.Add($clean) }
        }
        if ($result.Count -eq 0) { return $false }

        $before = $current.Count
        $env:PATH = ($result -join ';')
        if (-not $Quiet) {
            $added = $result.Count - $before
            if ($added -gt 0) {
                try {
                    Write-SkynetLog -Message "PATH восстановлен: $before → $($result.Count) записей (добавлено $added). Терминал запущен из MSIX-пакета (Windows Terminal) и получил урезанный PATH." -Level 'INFO' -Module 'Core'
                } catch { }
            } else {
                try { Write-SkynetLog -Message "PATH в порядке: $($result.Count) записей." -Level 'DEBUG' -Module 'Core' } catch { }
            }
        }
        return $true
    } catch {
        try { Write-SkynetLog -Message "Не удалось восстановить PATH ($($_.Exception.Message)) — команды могут не находиться." -Level 'WARN' -Module 'Core' } catch { }
        return $false
    }
}

function Test-SkynetAnsiSupport {
    <#
    .SYNOPSIS
        Проверить поддержку ANSI (VT) в текущем терминале.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([switch] $NoAnsi)
    if ($NoAnsi) { return $false }
    if (-not [string]::IsNullOrEmpty($env:NO_COLOR)) { return $false }
    if ('SkyNetVt' -as [type]) { try { return [SkyNetVt]::Enable() } catch { return $false } }
    return $false
}

function Set-SkynetAnsiFlags {
    <#
    .SYNOPSIS
        Определить и запомнить режим ANSI в конфиге.
    #>
    [CmdletBinding()]
    param()
    $cfg = $GLOBAL:_SkyNetCore
    $cfg.ForceAnsi = $false
    if (-not $cfg.NoAnsi -and [string]::IsNullOrEmpty($env:NO_COLOR)) {
        if (-not [string]::IsNullOrEmpty($env:SSH_CONNECTION) -or -not [string]::IsNullOrEmpty($env:SSH_CLIENT) -or -not [string]::IsNullOrEmpty($env:TERM)) {
            $cfg.ForceAnsi = $true
        }
    }
    $vt = $false
    try { $vt = [bool] $Host.UI.SupportsVirtualTerminal } catch { }
    if ($cfg.NoAnsi -or -not [string]::IsNullOrEmpty($env:NO_COLOR)) { $cfg.AnsiOk = $false; return }
    if ($vt) { $cfg.AnsiOk = $true }
    elseif ($cfg.ForceAnsi) { $cfg.AnsiOk = $true }
    else { try { if (Test-SkynetAnsiSupport) { $cfg.AnsiOk = $true } } catch { } }
}

function Get-SkynetProjectRoot {
    <#
    .SYNOPSIS
        Каталог проекта (родитель папки Modules).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return $script:ProjectRoot
}

function Get-SkynetConfig {
    <#
    .SYNOPSIS
        Вернуть текущую конфигурацию (hashtable).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return $GLOBAL:_SkyNetCore
}

function Set-SkynetConfig {
    <#
    .SYNOPSIS
        Изменить значение конфигурации.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Key, [object] $Value)
    if ($GLOBAL:_SkyNetCore.ContainsKey($Key)) { $GLOBAL:_SkyNetCore[$Key] = $Value }
}

function Get-SkynetConsoleGeometry {
    <#
    .SYNOPSIS
        Размер видимого окна консоли (колонки/строки).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $w = 0; $h = 0
    try { $sz = $Host.UI.RawUI.WindowSize; $w = [int] $sz.Width; $h = [int] $sz.Height } catch { }
    if (($w -lt 20 -or $h -lt 5) -and ('SkyWin' -as [type])) {
        try { $size = [SkyWin]::ConsoleSize(); $w = [int] $size[0]; $h = [int] $size[1] } catch { }
    }
    if ($w -lt 20 -or $h -lt 5) { $w = 120; $h = 30 }
    return @{ Width = $w; Height = $h }
}

function Test-SkynetLogoFile {
    <#
    .SYNOPSIS
        Проверить, что файл является читаемым изображением-логотипом.
    .DESCRIPTION
        Возвращает hashtable: Ok, Path, Bytes, Width, Height, Reason.
        Файлы подозрительно малого размера (битые/сгенерированные обрезки)
        помечаются как Small — Resolve-LogoPath отодвигает их в конец списка.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string] $Path)

    $result = @{ Ok = $false; Path = $Path; Bytes = 0; Width = 0; Height = 0; Small = $false; Reason = '' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $result.Reason = 'файл не найден'; return $result }

    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) { $result.Reason = 'файл недоступен'; return $result }
    $result.Bytes = [int64] $item.Length
    if ($item.Length -lt 512) { $result.Reason = 'файл слишком мал'; return $result }

    try {
        if (-not ('System.Drawing.Image' -as [type])) { Add-Type -AssemblyName System.Drawing }
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $ms = [System.IO.MemoryStream]::new($bytes)
        try {
            $img = [System.Drawing.Image]::FromStream($ms)
            try { $result.Width = [int] $img.Width; $result.Height = [int] $img.Height } finally { $img.Dispose() }
        } finally { $ms.Dispose() }
    } catch {
        $result.Reason = "не читается как изображение: $($_.Exception.Message)"
        return $result
    }

    if ($result.Bytes -lt [int64] $GLOBAL:_SkyNetCore.LogoMinBytes) { $result.Small = $true }
    $result.Ok = $true
    return $result
}

function Test-SkynetCineSupport {
    <#
    .SYNOPSIS
        Доступен ли микрошрифт консоли (только классический conhost).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (-not [string]::IsNullOrEmpty($env:WT_SESSION)) { return $false }
    return ('SkyCine' -as [type]) -ne $null
}

function Set-SkynetCineFont {
    <#
    .SYNOPSIS
        Поставить мелкий TrueType-шрифт консоли (только классический conhost).
    .PARAMETER FaceName
        Имя шрифта (по умолчанию Consolas; Cascadia Mono поддерживает брайль).
    .PARAMETER HeightPx
        Высота шрифта в пикселях (по умолчанию 8 — кинорежим).
    #>
    [CmdletBinding()]
    param(
        [string] $FaceName = 'Consolas',
        # Именно [int], а не [short]: акселератор short появился только в
        # PowerShell 7, и на Windows PowerShell 5.1 вызов падал с
        # «Не удалось найти тип [short]», роня всё шоу целиком.
        [int] $HeightPx = 8
    )
    if ([string]::IsNullOrEmpty($env:WT_SESSION) -and ('SkyCine' -as [type])) {
        try { [void] [SkyCine]::SetFont($FaceName, $HeightPx, 400) } catch { }
    }
}

function Get-SkynetCellSize {
    <#
    .SYNOPSIS
        Размер знакоместа консоли в пикселях.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    if ('SkyCine' -as [type]) {
        try {
            $width = [SkyCine]::CellWidth()
            $height = [SkyCine]::CellHeight()
            return @{ Width = $width; Height = $height }
        } catch { return $null }
    }
    return $null
}
function Import-SkynetJsonConfig {
    <#
    .SYNOPSIS
        Загрузить config/skynet.json в конфигурацию проекта.
    .DESCRIPTION
        Читает JSON, аккуратно переносит известные ключи в общую конфигурацию,
        неизвестные игнорирует. При любой ошибке остаются значения по умолчанию
        (graceful fallback) — загрузка шоу не должна падать из-за конфига.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string] $Path)

    $cfg = $GLOBAL:_SkyNetCore
    if (-not $Path) { $Path = $cfg.ConfigPath }
    $cfg.ConfigPath = $Path

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        try { Write-SkynetLog -Message "Конфиг не найден: $Path — используются значения по умолчанию." -Level 'WARN' -Module 'Core' } catch { }
        return $cfg
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        try { Write-SkynetLog -Message "Конфиг не разобран: $($_.Exception.Message)" -Level 'WARN' -Module 'Core' } catch { }
        return $cfg
    }

    $map = @(
        @{ S = '';             N = 'Version';         K = 'Version';         T = 'string' }
        @{ S = '';             N = 'ProjectName';     K = 'ProjectName';     T = 'string' }
        @{ S = '';             N = 'Company';         K = 'Company';         T = 'string' }
        @{ S = '';             N = 'DefaultLogo';     K = 'DefaultLogo';     T = 'string' }
        @{ S = 'Logo';         N = 'MinBytes';        K = 'LogoMinBytes';    T = 'int'    }
        @{ S = 'Render';       N = 'Charset';         K = 'Charset';         T = 'string' }
        @{ S = 'Render';       N = 'ColorMode';       K = 'LogoColor';       T = 'string' }
        @{ S = 'Render';       N = 'ChafaPath';       K = 'ChafaPath';       T = 'string' }
        @{ S = 'Render';       N = 'AutoSize';        K = 'AutoSize';        T = 'bool'   }
        @{ S = 'Render';       N = 'MaxWidth';        K = 'MaxFrameWidth';   T = 'int'    }
        @{ S = 'Render';       N = 'MaxHeight';       K = 'MaxFrameHeight';  T = 'int'    }
        @{ S = 'Render';       N = 'DefaultWidth';    K = 'RenderWidth';     T = 'int'    }
        @{ S = 'Render';       N = 'DefaultHeight';   K = 'RenderHeight';    T = 'int'    }
        @{ S = 'Animation';    N = 'Marquee';         K = 'Marquee';         T = 'bool'   }
        @{ S = 'Animation';    N = 'MarqueeText';     K = 'MarqueeText';     T = 'string' }
        @{ S = 'Animation';    N = 'MarqueeSpeed';    K = 'MarqueeSpeed';    T = 'int'    }
        @{ S = 'Animation';    N = 'HoldSeconds';     K = 'HoldSeconds';     T = 'int'    }
        @{ S = 'Animation';    N = 'FadeInMs';        K = 'FadeInMs';        T = 'int'    }
        @{ S = 'Animation';    N = 'FadeOutMs';       K = 'FadeOutMs';       T = 'int'    }
        @{ S = 'Animation';    N = 'ExitDelayMs';     K = 'ExitDelayMs';     T = 'int'    }
        @{ S = 'Animation';    N = 'Flicker';         K = 'Flicker';         T = 'bool'   }
        @{ S = 'BootSequence'; N = 'MemDumpLines';    K = 'MemDumpLines';    T = 'int'    }
        @{ S = 'BootSequence'; N = 'FinalDelayMs';    K = 'FinalDelayMs';    T = 'int'    }
        @{ S = 'BootSequence'; N = 'DelayMultiplier'; K = 'DelayMultiplier'; T = 'double' }
        @{ S = 'BootSequence'; N = 'WaitKey';         K = 'WaitKey';         T = 'bool'   }
        @{ S = 'BootSequence'; N = 'TypeSoundEnabled';   K = 'TypeSoundEnabled';   T = 'bool'   }
        @{ S = 'BootSequence'; N = 'TypeDelayMs';        K = 'TypeDelayMs';        T = 'int'    }
        @{ S = 'BootSequence'; N = 'TypeSoundThrottleMs'; K = 'TypeSoundThrottleMs'; T = 'int'   }
        @{ S = 'BootSequence'; N = 'TypeLineAccent';     K = 'TypeLineAccent';     T = 'bool'   }
        @{ S = 'Logging';      N = 'Enabled';         K = 'LogEnabled';      T = 'bool'   }
        @{ S = 'Logging';      N = 'MinLevel';        K = 'LogMinLevel';     T = 'string' }
        @{ S = 'Logging';      N = 'MaxSizeKB';       K = 'LogMaxSizeKB';    T = 'int'    }
        @{ S = 'Logging';      N = 'Rotate';          K = 'LogRotate';       T = 'bool'   }
        @{ S = 'Logging';      N = 'Console';         K = 'LogConsole';      T = 'bool'   }
        @{ S = 'Terminal';     N = 'Sixel';           K = 'Sixel';           T = 'bool'   }
        @{ S = 'Terminal';     N = 'CineMode';        K = 'CineSize';        T = 'bool'   }
        @{ S = 'Audio';        N = 'Enabled';         K = 'AudioEnabled';    T = 'bool'   }
        @{ S = 'Audio';        N = 'Volume';          K = 'AudioVolume';     T = 'double' }
        @{ S = 'Audio';        N = 'Pack';            K = 'AudioPack';       T = 'string' }
        @{ S = 'Audio';        N = 'KeyThrottleMs';   K = 'AudioKeyThrottle'; T = 'int'    }
    )

    $applied = 0
    foreach ($item in $map) {
        $source = $json
        if ($item.S) {
            $section = $json.PSObject.Properties[$item.S]
            if (-not $section) { continue }
            $source = $section.Value
        }
        $prop = $source.PSObject.Properties[$item.N]
        if (-not $prop -or $null -eq $prop.Value) { continue }
        $value = $prop.Value
        switch ($item.T) {
            'int' {
                # Явная инвариантная культура: в ru-RU TryParse без неё
                # отвергает «0.7» (там десятичный разделитель — запятая),
                # и значение молча не применялось.
                $intValue = 0
                if ([int]::TryParse([string] $value, [System.Globalization.NumberStyles]::Integer,
                        [System.Globalization.CultureInfo]::InvariantCulture, [ref] $intValue)) {
                    $cfg[$item.K] = $intValue; $applied++
                }
            }
            'double' {
                $dblValue = 0.0
                if ([double]::TryParse([string] $value, [System.Globalization.NumberStyles]::Float,
                        [System.Globalization.CultureInfo]::InvariantCulture, [ref] $dblValue)) {
                    $cfg[$item.K] = $dblValue; $applied++
                }
            }
            'bool' {
                $boolValue = $false
                if ([bool]::TryParse([string] $value, [ref] $boolValue)) { $cfg[$item.K] = $boolValue; $applied++ }
            }
            default { $cfg[$item.K] = [string] $value; $applied++ }
        }
    }
    # Лог-файл: относительный путь считается от корня проекта.
    $logFile = $null
    $logSection = $json.PSObject.Properties['Logging']
    if ($logSection) {
        $logProp = $logSection.Value.PSObject.Properties['File']
        if ($logProp) { $logFile = [string] $logProp.Value }
    }
    if ($logFile) {
        if (-not [System.IO.Path]::IsPathRooted($logFile)) { $logFile = Join-Path $cfg.ProjectRoot $logFile }
        $cfg.LogFile = $logFile
    }
    if (-not $cfg.LogFile) { $cfg.LogFile = Join-Path $cfg.ProjectRoot 'logs\skynet_boot.log' }

    try { Write-SkynetLog -Message "Конфиг загружен: $Path (ключей применено: $applied)" -Level 'DEBUG' -Module 'Core' } catch { }
    return $cfg
}

Export-ModuleMember -Function Set-SkynetTermEnv, Restore-SkynetTerminalPath, Test-SkynetAnsiSupport, Set-SkynetAnsiFlags, Get-SkynetConfig, Set-SkynetConfig, Get-SkynetProjectRoot, Import-SkynetJsonConfig, Get-SkynetConsoleGeometry, Test-SkynetLogoFile, Test-SkynetCineSupport, Set-SkynetCineFont, Get-SkynetCellSize
