<#
.SYNOPSIS
    Запуск шоу SkyNet в максимизированном окне PowerShell 7.

.DESCRIPTION
    Открывает новый терминал PowerShell 7 (pwsh) в максимизированном режиме
    и запускает Core/launch_skynet.ps1. Полноэкранный режим не используется:
    заголовок окна, вкладки и системная рамка остаются видимыми для записи видео.
#>
[CmdletBinding()]
param(
    [int] $HoldSeconds = 2,
    [ValidateSet('Original', 'Green')] [string] $LogoColor = 'Original',
    [string] $Size = '',
    [string] $Charset = '',
    [switch] $Pause,
    [switch] $NoPause,
    [switch] $NoChafa,
    [switch] $NoBoot,
    [switch] $Windowed,
    [switch] $NormalFont,
    [switch] $ShowOnly,
    [switch] $Wait,
    [switch] $Sixel,
    # --- Финал: окно видеозвонка -------------------------------------------
    [int]    $FinaleSpeedup = 20,       # ускорение анимации финала, %
    [string] $ContactText = 'Visual contact complited',
    [int]    $ContactBlinkMs = 200,
    [switch] $NoCallWindow,             # не открывать отдельное окно звонка
    [switch] $KeepWindowSize,           # не уменьшать окно в конце шоу
    [switch] $CloseAfterShow,            # старое поведение: закрыть окно в конце
    # --- Выбор оболочки ------------------------------------------------------
    [ValidateSet('Auto', 'Pwsh', 'WindowsPowerShell')]
    [string] $Shell = 'Auto'             # Auto — сначала PS 7, иначе 5.1;
                                         # Pwsh — требовать PS 7; WindowsPowerShell — только 5.1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$show = Join-Path $PSScriptRoot 'launch_skynet.ps1'
if (-not (Test-Path -LiteralPath $show -PathType Leaf)) { throw "Не найден скрипт шоу: $show" }

# Корень проекта: из него берутся и рабочий каталог вкладки, и startingDirectory
# профиля терминала. Считается один раз, чтобы пути не разъезжались.
$projectRoot = Split-Path -Parent $PSScriptRoot

# Шоу по умолчанию запускается как `pwsh -NoExit -Command "& '<show>' ..."`.
# -NoExit оставляет интерактивный промпт после шоу, поэтому вкладка не
# закрывается и пользователь может сразу вводить команды. -KeepShell
# запрещает самому сценарию вызывать exit. Прежний режим (-CloseAfterShow)
# запускает шоу через -File и закрывает окно после -Pause.
$keepShell = -not $CloseAfterShow
if ($keepShell) { Write-Host '[SKYNET] Режим: окно останется интерактивным после шоу (-NoExit).' -ForegroundColor DarkGreen }

# --- Оболочка: PowerShell 7, при его отсутствии — Windows PowerShell 5.1 -----
# $Shell позволяет выбрать оболочку принудительно: 'Pwsh' требует PS 7,
# 'WindowsPowerShell' запускает шоу только на 5.1 (нужно, когда проверяется
# поведение 5.1 или когда PS 7 стоит, но запускать надо именно в нём).
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pwshPath = $null
if ($Shell -eq 'WindowsPowerShell') {
    if (-not (Test-Path -LiteralPath $ps51 -PathType Leaf)) {
        throw "Windows PowerShell 5.1 не найден: $ps51"
    }
    $pwshPath = $ps51
    Write-Host "[SKYNET] Оболочка по требованию (-Shell WindowsPowerShell): $pwshPath" -ForegroundColor DarkGreen
} else {
    $pwshCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'),
        (Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
    )
    foreach ($candidate in $pwshCandidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { $pwshPath = $candidate; break }
    }
    if (-not $pwshPath) {
        # Запасной вариант — Windows PowerShell 5.1: шоу на нём запускается (проверено
        # на 27.09.2026: сцена T-800 идёт, не собирается только SkyImagePrep.cs —
        # утолщение штрихов). Раньше здесь был безусловный throw, из-за чего машина
        # без PowerShell 7 молча не запускала шоу вовсе.
        if (Test-Path -LiteralPath $ps51 -PathType Leaf) {
            $pwshPath = $ps51
            Write-Host '[SKYNET] ВНИМАНИЕ: PowerShell 7 (pwsh.exe) не найден — запуск через Windows PowerShell 5.1.' -ForegroundColor Yellow
            Write-Host '[SKYNET] Для полного шоу поставьте PS 7: winget install --id Microsoft.PowerShell --source winget' -ForegroundColor Yellow
        } else {
            throw 'PowerShell 7 (pwsh.exe) не найден. Установите: winget install Microsoft.PowerShell'
        }
    } elseif ($Shell -eq 'Pwsh') {
        Write-Host "[SKYNET] Оболочка: $pwshPath" -ForegroundColor DarkGreen
    }
}

# Команда для профиля Windows Terminal. Пишем ТОТ ЖЕ исполняемый файл, которым
# реально запускаем шоу: жёсткое 'pwsh.exe' в профиле давало на машине без
# PowerShell 7 окно с ошибкой 0x80070002 «Не удается найти указанный файл».
$wtCommandLine = if ($pwshPath -match '\s') { '"{0}" -NoProfile' -f $pwshPath } else { '{0} -NoProfile' -f $pwshPath }

# --- Параметры самого шоу ---------------------------------------------------
# Значения собираются БЕЗ кавычек, а готовую строку команды pwsh разберёт сам.
# Так не возникает двойного экранирования при передаче через wt.exe.
$showArgs = New-Object System.Collections.Generic.List[string]
if ($HoldSeconds -ge 0) { $showArgs.Add('-HoldSeconds'); $showArgs.Add([string] $HoldSeconds) }
$showArgs.Add('-LogoColor'); $showArgs.Add($LogoColor)
if ($Size) { $showArgs.Add('-Size'); $showArgs.Add($Size) }
if ($Charset) { $showArgs.Add('-Charset'); $showArgs.Add($Charset) }
# По умолчанию оставляем окно открытым после шоу; -NoPause явно отключает ожидание.
if ($Pause -or -not $NoPause) { $showArgs.Add('-Pause') }
if ($NoChafa) { $showArgs.Add('-NoChafa') }
if ($NoBoot) { $showArgs.Add('-SkipBoot') }
if ($Sixel) { $showArgs.Add('-Sixel') }
$showArgs.Add('-FinaleSpeedup'); $showArgs.Add([string] $FinaleSpeedup)
$showArgs.Add('-ContactText'); $showArgs.Add($ContactText)
$showArgs.Add('-ContactBlinkMs'); $showArgs.Add([string] $ContactBlinkMs)
if ($NoCallWindow) { $showArgs.Add('-NoCallWindow') }
if ($KeepWindowSize) { $showArgs.Add('-NoRestoreWindow') }
if ($keepShell) { $showArgs.Add('-KeepShell') }

function ConvertTo-SkynetArgLiteral {
    <# .SYNOPSIS Значение аргумента PowerShell в одинарных кавычках. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Value = '')
    return "'" + ($Value -replace "'", "''") + "'"
}

# Команда целиком: & '<путь>' -Key 'value' -Switch
# Имена параметров (начинаются с '-') кавычками НЕ берутся — иначе
# -Command воспримет их как строковые литералы, а не как параметры.
$tokens = @((ConvertTo-SkynetArgLiteral -Value $show))
foreach ($arg in $showArgs) {
    if ($arg.StartsWith('-')) { $tokens += $arg } else { $tokens += (ConvertTo-SkynetArgLiteral -Value $arg) }
}
$showCommand = '& ' + ($tokens -join ' ')

# --- Оконный хост: Windows Terminal, иначе conhost ---------------------------
# Внутри Windows Terminal в PATH появляется папка самого WT и Get-Command
# wt.exe возвращает несколько путей — нужен ровно один (иначе $wtPath станет
# массивом и Start-Process упадёт). Приоритет — псевдоним WindowsApps.
$wtPath = $null
$wtAlias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
if (-not $Windowed -and (Test-Path -LiteralPath $wtAlias -PathType Leaf)) { $wtPath = $wtAlias }
if (-not $wtPath -and -not $Windowed) {
    $wtCandidates = @(Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    if ($wtCandidates.Count -gt 0) { $wtPath = [string] $wtCandidates[0] }
    if (-not $wtPath) {
        try {
            $package = Get-AppxPackage Microsoft.WindowsTerminal -ErrorAction Stop
            foreach ($name in 'Terminal.exe', 'WindowsTerminal.exe') {
                $probe = Join-Path $package.InstallLocation $name
                if (Test-Path -LiteralPath $probe -PathType Leaf) { $wtPath = $probe; break }
            }
        } catch { }
    }
}

# --- Шрифт в духе HUD из «Терминатора» (1987) ---------------------------------
# Экраны Cyberdyne 101/800 нарисованы авторским шрифтом студии, точной копии в
# Windows нет. Подбираем ближайший по геометрии МОНОШИРИННЫЙ шрифт из
# установленных: Unispace — квадратный техно-шрифт с равномерной сеткой, самый
# близкий к экранам фильма; Eurostile/Microgramma/Michroma — клоны sci-fi
# гарнитуры эпохи; Consolas — гарантированный запасной вариант.
#
# Проверка моноширинности обязательна. Windows Terminal выравнивает экран по
# ячейкам, и пропорциональный шрифт (Agency FB, Bahnschrift) разъезжает всю
# вёрстку: Sixel-кадры, панели и стрелки аннотаций разъезжаются, а жирное
# начертание обрезает подписи. Кандидат отбрасывается, если буквы разной ширины.
$skynetFontCandidates = @(
    'Unispace', 'Eurostile', 'Microgramma', 'Eurostile Extended', 'Michroma',
    'Rajdhani', 'Orbitron', 'Share Tech Mono', 'JetBrains Mono', 'Consolas'
)
function Test-SkynetMonospaceFont {
    <#
    .SYNOPSIS
        Моноширинный ли шрифт: одинаковая ли ширина у i, W и M.
    #>
    param([string] $Name = '', [int] $Size = 14)
    $font = $null; $bitmap = $null; $graphics = $null
    try {
        $font = New-Object System.Drawing.Font($Name, $Size,
            [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $bitmap = New-Object System.Drawing.Bitmap 4, 4
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
        $narrow = $graphics.MeasureString('iiiiiiiiii', $font).Width
        $wide = $graphics.MeasureString('WWWWWWWWWW', $font).Width
        $other = $graphics.MeasureString('MMMMMMMMMM', $font).Width
        return ([Math]::Abs($narrow - $wide) -lt 0.5) -and ([Math]::Abs($wide - $other) -lt 0.5)
    } catch {
        return $false
    } finally {
        if ($font) { $font.Dispose() }
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
    }
}
$skynetFont = 'Consolas'
try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $installedFonts = @((New-Object System.Drawing.Text.InstalledFontCollection).Families |
        Select-Object -ExpandProperty Name)
    foreach ($fontCandidate in $skynetFontCandidates) {
        if (($installedFonts -contains $fontCandidate) -and (Test-SkynetMonospaceFont -Name $fontCandidate)) {
            $skynetFont = $fontCandidate
            break
        }
    }
} catch { }

# --- Настройка профиля Windows Terminal «SkyNet HiRes» под стиль Терминатора ---
$wtProfileName = $null
if ($wtPath -and -not $Windowed -and -not $NormalFont) {
    try {
        $fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\SkyNet'
        $fragmentPath = Join-Path $fragmentDir 'skynet.json'
        $fragment = @{
            profiles = @(
                @{
                    name             = 'SkyNet HiRes'
                    guid             = '{d3a1c9e2-6b4f-4c8a-9e0d-71f2b5a6c8d9}'
                    commandline      = $wtCommandLine
                    startingDirectory = $projectRoot
                    fontFace         = $skynetFont
                    fontSize         = 14
                    fontWeight       = 'bold'
                    background       = '#000000'
                    foreground       = '#00FF66'
                    cursorShape      = 'filledBox'
                    scrollbarState   = 'hidden'
                    padding          = '5'
                }
            )
        }
        $fragmentJson = $fragment | ConvertTo-Json -Depth 5
        
        New-Item -ItemType Directory -Force -Path $fragmentDir | Out-Null
        [System.IO.File]::WriteAllText($fragmentPath, $fragmentJson, [System.Text.UTF8Encoding]::new($false))
        $wtProfileName = 'SkyNet HiRes'
        Write-Host "[SKYNET] Профиль терминала обновлен: шрифт 14px, полужирный ($skynetFont)." -ForegroundColor DarkGreen
    } catch {
        Write-Host "[SKYNET] Не удалось создать профиль WT: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

if ($wtPath -and -not $Windowed) {
    # Полноэкранный режим не используем: при записи видео должны быть видны
    # заголовок окна, вкладки и системная рамка терминала.
    $wtArgs = @('--maximized', 'new-tab')
    # Рабочий каталог вкладки задаём ЯВНО, а не через startingDirectory профиля.
    # Профиль WT держит его у себя и отдаёт из кэша: если в кэше остался уже
    # удалённый каталог (например, папка SkyNet_rescue_* от safe_leave.ps1),
    # Windows Terminal падает с 0x8007010B — «не удалось войти в каталог» —
    # и вместо шоу показывает окно с ошибкой. Путь из $PSScriptRoot всегда есть.
    $wtArgs += @('--startingDirectory', ('"{0}"' -f $projectRoot))
    if ($wtProfileName) {
        $wtArgs += @('-p', ('"{0}"' -f $wtProfileName))
    }
    # -NoExit -Command "& '<show>' ..." — после шоу остаётся интерактивный промпт.
    # Внутренние значения уже в одинарных кавычках, внешние — двойные (аргумент
    # wt.exe содержит пробелы).
    $pwshTail = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    # Для -File значения с пробелами берутся в двойных кавычках (их разбирает
    # сам pwsh), для -Command — в одинарных (парсит сам PowerShell).
    $fileArgs = @()
    foreach ($arg in $showArgs) {
        if ($arg.StartsWith('-')) { $fileArgs += $arg } elseif ($arg -match '\s') { $fileArgs += ('"{0}"' -f $arg) } else { $fileArgs += $arg }
    }
    if ($keepShell) {
        # Аргументы уже вшиты в $showCommand — отдельно их не добавляем.
        $pwshTail += @('-NoExit', '-Command', ('"{0}"' -f $showCommand))
        $wtArgs += @('--title', '"SKYNET TERMINAL"', ('"{0}"' -f $pwshPath)) + $pwshTail
    } else {
        $wtArgs += @('--title', '"SKYNET TERMINAL"', ('"{0}"' -f $pwshPath)) + $pwshTail
        $wtArgs += @('-File', ('"{0}"' -f $show)) + $fileArgs
    }
    $commandLine = ($wtArgs -join ' ')
    Write-Host "[SKYNET] Windows Terminal maximized (с видимой рамкой, без fullscreen) -> $pwshPath" -ForegroundColor DarkGreen
    if ($ShowOnly) { Write-Host ('"{0}" {1}' -f $wtPath, $commandLine); return }
    if ($Wait) { Start-Process -FilePath $wtPath -ArgumentList $commandLine -Wait }
    else { Start-Process -FilePath $wtPath -ArgumentList $commandLine | Out-Null }
    return
}

# conhost: обычное максимизированное окно без перехода в полноэкранный режим.
$fallbackArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
$fileArgs = @()
foreach ($arg in $showArgs) {
    if ($arg.StartsWith('-')) { $fileArgs += $arg } elseif ($arg -match '\s') { $fileArgs += ('"{0}"' -f $arg) } else { $fileArgs += $arg }
}
if ($keepShell) { $fallbackArgs += @('-NoExit', '-Command', ('"{0}"' -f $showCommand)) }
else { $fallbackArgs += @('-File', ('"{0}"' -f $show)) + $fileArgs }
$fallbackLine = ($fallbackArgs -join ' ')
Write-Host '[SKYNET] Классическая консоль: максимизированное окно (без fullscreen).' -ForegroundColor DarkGreen
if ($ShowOnly) { Write-Host ('"{0}" {1}' -f $pwshPath, $fallbackLine); return }
if ($Wait) { Start-Process -FilePath $pwshPath -ArgumentList $fallbackLine -WindowStyle Maximized -Wait }
else { Start-Process -FilePath $pwshPath -ArgumentList $fallbackLine -WindowStyle Maximized | Out-Null }