<#
.SYNOPSIS
    Cyberdyne Systems / Skynet — загрузочное шоу с анимацией.

.DESCRIPTION
    Проигрывает загрузочную последовательность Skynet, затем показывает
    логотип проекта в символьной сборке и Sixel-графике:
      0) пролог: белая SSH/boot-сцена → захват PowerShell → сборка логотипа
         из шума → финальный Sixel-кадр и SKYNET SYSTEM ONLINE под ним →
         GLOBAL DEFENSE NETWORK → сканирование юнита T-800
         (закреплённая шапка + прокрутка ТТХ из
         tactical and technical specifications.MD) → торс → OPTICAL SYSTEM;
      1) boot-текст (печатная машинка) + прогресс-бар;
      2) бегущая строка загрузки внизу экрана (движется всё шоу);
      3) финальный логотип: Sixel-пиксели (или символьный fade в -Sixel:$false);
      4) финальный кадр 2 секунды;
      5) статус "AWAITING ORDERS, HUMAN.".

    Логотип — ОРИГИНАЛ из корня проекта (skynet_logo.png, см. config/skynet.json
    → DefaultLogo). Файл никогда не генерируется и не перезаписывается:
    Tools/generate_logo.ps1 пишет только в assets/generated.

    Символьная сборка логотипа из шума выполняется в прологе. Финальный кадр
    по умолчанию выводится напрямую через chafa --format=sixel: это настоящие
    пиксели Windows Terminal, а не символы и не встроенный truecolor-рендерер.

.PARAMETER LogoPath
    Явный путь к файлу логотипа (по умолчанию — оригинал из конфига).

.PARAMETER Size
    Размер графики WIDTHxHEIGHT (по умолчанию пусто — авто: весь экран
    в пределах конфига, максимальное разрешение — самые мелкие блоки).
    Размер автоматически ужимается под фактическое окно терминала.

.PARAMETER LogoColor
    Original (по умолчанию) — реальные цвета логотипа. Green — зелёный фосфор.

.PARAMETER Charset
    Block (по умолчанию) — half-blocks truecolor. Ascii — совместимость.

.PARAMETER HoldSeconds
    Сколько секунд держать финальный логотип (по умолчанию 2).

.PARAMETER FadeInMs
    Длительность проявления логотипа, мс (по умолчанию 1400).

.PARAMETER FadeOutMs
    Длительность растворения логотипа, мс (по умолчанию 1800).

.PARAMETER NoFade
    Показать логотип без проявления/растворения (мгновенно).

.PARAMETER NoMarquee
    Отключить бегущую строку.

.PARAMETER MarqueeText
    Свой текст бегущей строки.

.PARAMETER SkipBoot
    Пропустить boot-текст и сразу показать логотип.

.PARAMETER SkipLogo
    Только загрузка, без логотипа.

.PARAMETER CineSize
    Кинорежим: микрошрифт консоли (только conhost) и пересчёт графики под окно.

.PARAMETER Sixel
    Пиксельный режим chafa (Windows Terminal 1.22+). Без покадрового fade.

.PARAMETER NoChafa
    Не использовать chafa, всегда встроенный рендерер.

.PARAMETER Instant
    Отключить все задержки и анимацию (для тестов и CI).

.PARAMETER NoAnsi
    Полностью отключить ANSI-цвета.

.PARAMETER Pause
    Дождаться нажатия клавиши в конце (по умолчанию окно закрывается само).

.PARAMETER Fullscreen
    Legacy-режим для отдельного conhost: развернуть окно на весь экран через Win32.
    Обычный launcher Windows Terminal использует максимизированное окно без
    полноэкранного режима (--maximized), чтобы терминал был виден на видео.

.PARAMETER ExitDelayMs
    Пауза перед завершением, мс (по умолчанию 2500).

.PARAMETER LogToConsole
    Дублировать лог в консоль (по умолчанию лог только в файл).

.PARAMETER ConfigPath
    Путь к конфигу (по умолчанию config/skynet.json).

.PARAMETER NoPrologue
    Пропустить белый вступительный пролог (SSH-сессия → перехват PowerShell →
    сборка логотипа из шума → радар → сканирование юнита/торса → оптический тест).

.PARAMETER TorsoFramesFolder
    Папка с пронумерованными кадрами вращения торса для сцены торса в прологе
    (по умолчанию — assets\torso_frames, иначе та же папка, что и у головы).

.PARAMETER SpecFile
    Файл ТТХ для прокрутки в сцене сканирования юнита
    (по умолчанию — tactical and technical specifications.MD в корне проекта;
    можно указать абсолютный путь или путь относительно корня проекта).

.EXAMPLE
    .\Core\launch_skynet.ps1

.EXAMPLE
    .\Core\launch_skynet.ps1 -HoldSeconds 2 -LogoColor Green -CineSize

.EXAMPLE
    .\Core\launch_skynet.ps1 -Instant -SkipLogo     # smoke-прогон без анимации
#>
[CmdletBinding()]
param(
    [string] $LogoPath,
    [string] $Size = '',
    [ValidateSet('Original', 'Green', '')] [string] $LogoColor = '',
    [ValidateSet('Block', 'Ascii', 'Braille', '')] [string] $Charset = '',
    [int] $HoldSeconds = -1,
    [int] $FadeInMs = -1,
    [int] $FadeOutMs = -1,
    [int] $ExitDelayMs = -1,
    [string] $MarqueeText = '',
    [switch] $NoFade,
    [switch] $NoMarquee,
    [switch] $SkipBoot,
    [switch] $SkipLogo,
    [switch] $CineSize,
    [switch] $Sixel = $true,
    [switch] $NoChafa,
    [switch] $Instant,
    [switch] $NoAnsi,
    [switch] $Pause,
    [switch] $Fullscreen,
    [switch] $LogToConsole,
    [string] $T800Path,                 # запасной вариант: PNG со схемой T-800 (по умолчанию assets/t800.png)
    [string] $T800FramesFolder,         # папка с настоящими кадрами вращения (1.png..N.png)
    [int]    $T800Seconds = 18,         # длительность второй сцены
    [double] $SpinSeconds = 4.0,        # один оборот головы (по последовательности кадров)
                                        # ВАЖНО: это ЖЕЛАЕМЫЙ темп, а не достижимый.
                                        # Реально вращение упирается в отрисовку (~58 мс на
                                        # кадр 76x38), поэтому ускорение делается не здесь,
                                        # а прореживанием кадров в Show-SkynetT800SixelSequence.
    [int]    $SpinSteps   = 16,         # кадров на оборот — только для режима одной картинки
    [switch] $NoT800,                   # пропустить вторую сцену
    [switch] $NoGlitch,                 # выключить микрофризы и сдвиги строк
    [switch] $NoUnitImage,              # не рисовать робота в основном окне (только в окне звонка)
    [double] $GlitchIntensity = 1.0,    # частота глитчей
    [switch] $NoPrologue,               # пропустить белый вступительный пролог
    [string] $TorsoFramesFolder,        # папка с кадрами вращения торса (для пролога)
    [string] $SpecFile,                 # файл ТТХ для прокрутки в прологе (по умолчанию tactical and technical specifications.MD)
    [string] $FinaleFramesFolder = '',  # папка кадров финала (по умолчанию assets\terminator)
    [int]    $FinaleFrameIntervalMs = 1,# минимальный интервал между кадрами финала
    [int]    $FinaleSpeedup = 20,      # ускорение анимации финала, %
    [string] $ContactText = 'Visual contact complited', # мигающая строка во время звонка
    [int]    $ContactBlinkMs = 200,    # период моргания строки контакта, мс
    [switch] $NoCallWindow,            # окно звонка не открывать (анимация в текущем терминале)
    [switch] $NoRestoreWindow,         # не уменьшать окно терминала в конце шоу
    [switch] $KeepShell,               # не завершать процесс: оставить рабочий промпт
    [string] $ConfigPath
)
    
    
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExitCode = 0

# ---------------------------------------------------------------------------
#  Загрузка модулей
# ---------------------------------------------------------------------------
$moduleRoot = Join-Path $PSScriptRoot '..\Modules'
if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container)) {
    Write-Host "КРИТИЧНО: не найдена папка модулей: $moduleRoot" -ForegroundColor Red
    exit 1
}
try { $moduleRoot = (Resolve-Path -LiteralPath $moduleRoot).Path } catch { }

$moduleNames = @('SkyNet.Core', 'SkyNet.Log', 'SkyNet.Anim', 'SkyNet.Glitch', 'SkyNet.UI', 'SkyNet.Render', 'SkyNet.Boot', 'SkyNet.T800', 'SkyNet.Audio', 'SkyNet.Prologue', 'SkyNet.Finale')
foreach ($name in $moduleNames) {
    $path = Join-Path $moduleRoot "$name.psm1"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "КРИТИЧНО: отсутствует модуль $path" -ForegroundColor Red
        exit 1
    }
    try {
        # -DisableNameChecking глушит штатное предупреждение PowerShell о командах
        # с неутверждёнными глаголами (Play- в SkyNet.Audio, Redraw- в
        # SkyNet.Anim). Оно ничего не проверяет и не влияет на работу — просто
        # занимает первые строки экрана перед шоу, где их быть не должно.
        # Переименовывать команды ради этого нельзя: они публичные и описаны
        # в README.
        Import-Module $path -Force -ErrorAction Stop -DisableNameChecking
    } catch {
        Write-Host "КРИТИЧНО: модуль $name не загружен: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
# ---------------------------------------------------------------------------
#  Конфигурация
# ---------------------------------------------------------------------------
$cfg = Import-SkynetJsonConfig -Path $ConfigPath

if ($LogoPath) { $cfg.LogoPath = $LogoPath }
if ($Size) { $cfg.Size = $Size; $cfg.AutoSize = $false }
if ($Charset) { $cfg.Charset = $Charset; $cfg.CharsetExplicit = $true }
if ($LogoColor) { $cfg.LogoColor = $LogoColor }
if ($HoldSeconds -ge 0) { $cfg.HoldSeconds = $HoldSeconds }
if ($FadeInMs -ge 0) { $cfg.FadeInMs = $FadeInMs }
if ($FadeOutMs -ge 0) { $cfg.FadeOutMs = $FadeOutMs }
if ($ExitDelayMs -ge 0) { $cfg.ExitDelayMs = $ExitDelayMs }
if ($MarqueeText) { $cfg.MarqueeText = $MarqueeText }
if ($NoMarquee) { $cfg.Marquee = $false }
$cfg.CineSize = [bool] $CineSize
$cfg.NoChafa = [bool] $NoChafa
# Sixel включён по умолчанию. Явный -NoChafa сохраняет документированный
# fallback на символьный/встроенный рендерер.
$cfg.Sixel = [bool] $Sixel -and -not $cfg.NoChafa
$cfg.Instant = [bool] $Instant
$cfg.SkipLogo = [bool] $SkipLogo
$cfg.SkipBoot = [bool] $SkipBoot
$cfg.NoAnsi = [bool] $NoAnsi
$cfg.NoFade = [bool] $NoFade
$cfg.Pause = [bool] $Pause
# -KeepShell: процесс не должен завершаться, иначе вкладка Windows Terminal
# закроется вместе с окном и работать будет негде. Ожидание нажатия клавиши
# в этом режиме тоже не нужно — пользователь должен вводить команды сразу.
if ($KeepShell) {
    $cfg.Pause = $false
    # Заголовок окна задаётся явно: по нему финал находит своё окно
    # терминала (класс CASCADIA_HOSTING_WINDOW_CLASS). PowerShell иначе
    # перетирает заголовок, заданный wt.exe, текущим каталогом.
    try { $Host.UI.RawUI.WindowTitle = 'SKYNET TERMINAL' } catch { }
}
$cfg.LogToConsole = [bool] $LogToConsole
$cfg.Fullscreen = [bool] $Fullscreen

# ---------------------------------------------------------------------------
#  Источник кадров вращения (голова/торс) — единая точка разрешения путей,
#  переиспользуется и прологом (Show-SkynetPrologue), и основной сценой
#  T-800 (Show-SkynetT800Scene) ниже, чтобы не дублировать логику дважды.
#  Приоритет для головы: -T800FramesFolder → assets\t800_frames → сама
#  assets, если там ≥2 файлов с чисто числовым именем (1.png, 2.png, ...).
# ---------------------------------------------------------------------------
$t800Frames = ''
if ($T800FramesFolder) {
    $t800Frames = $T800FramesFolder
} else {
    $dedicated = Join-Path $cfg.ProjectRoot 'assets\t800_frames'
    $assetsDir = Join-Path $cfg.ProjectRoot 'assets'
    if (Test-Path -LiteralPath $dedicated -PathType Container) {
        $t800Frames = $dedicated
    } elseif (Test-Path -LiteralPath $assetsDir -PathType Container) {
        $numericCount = @(Get-ChildItem -LiteralPath $assetsDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -match '^\d+$' -and (@('.png', '.jpg', '.jpeg', '.bmp', '.webp') -contains $_.Extension.ToLowerInvariant()) }).Count
        if ($numericCount -ge 2) { $t800Frames = $assetsDir }
    }
}
$torsoFrames = if ($TorsoFramesFolder) { $TorsoFramesFolder } else { '' }
if (-not $torsoFrames) {
    $torsoDedicated = Join-Path $cfg.ProjectRoot 'assets\torso_frames'
    if (Test-Path -LiteralPath $torsoDedicated -PathType Container) { $torsoFrames = $torsoDedicated }
}
# Важно: если отдельной папки кадров торса нет, торс НЕ подменяется кадрами
# головы. Иначе пролог крутил бы одну и ту же последовательность двумя сценами
# подряд — это и были «два цикла прокрутки изображений».

# ---------------------------------------------------------------------------
#  Терминал и ANSI
# ---------------------------------------------------------------------------
# PATH восстанавливаем ПЕРВЫМ делом. При запуске из Windows Terminal (MSIX-пакет)
# потомок получает PATH из двух папок WindowsApps, и в нём не находятся ни
# cmd, ни chafa, ни ffmpeg, ни wt.exe. Без этого и шоу не нашло бы свои
# инструменты, и терминал, остающийся после шоу, был бы нерабочим.
Restore-SkynetTerminalPath
Set-SkynetTermEnv
Set-SkynetAnsiFlags
if ($NoGlitch) { Set-SkynetGlitch -Off } else { Set-SkynetGlitch -On -Intensity $GlitchIntensity }
if ($LogToConsole) { Enable-SkynetConsoleLog }

Write-SkynetLog -Message "SkyNet v$($cfg.Version): старт шоу (source=$($cfg.ProjectRoot))" -Level 'INFO' -Module 'Core'
Write-SkynetLog -Message "ANSI=$($cfg.AnsiOk), UTF8=$($cfg.Utf8Output), Instant=$($cfg.Instant), Chafa=$(Get-SkynetChafaPath)" -Level 'DEBUG' -Module 'Core'

if (-not $cfg.AnsiOk) {
    Write-SkynetLog -Message 'ANSI недоступен: цвета и позиционирование курсора отключены.' -Level 'WARN' -Module 'Core'
}

try {
    if ($cfg.Fullscreen -and ('SkyWin' -as [type])) {
        try {
            [SkyWin]::Fullscreen()
            Start-Sleep -Milliseconds 250
            Write-SkynetLog -Message 'Окно развёрнуто на весь экран (conhost/Win32).' -Level 'DEBUG' -Module 'Core'
        } catch { }
    }

    # Плотность кадра: в классическом conhost шрифт можно уменьшить программно.
    # Мельче шрифт = больше колонок/строк = выше детализация логотипа.
    if (-not [string]::IsNullOrEmpty($env:WT_SESSION)) {
        Write-SkynetLog -Message "Windows Terminal (шрифт задаёт профиль, WT_SESSION=$($env:WT_SESSION))." -Level 'DEBUG' -Module 'Core'
    } elseif (Test-SkynetCineSupport) {
        Set-SkynetCineFont -FaceName 'Cascadia Mono' -HeightPx 10
        Start-Sleep -Milliseconds 450
        Write-SkynetLog -Message 'conhost: шрифт Cascadia Mono 10px — максимум колонок/строк.' -Level 'INFO' -Module 'Render'
    }

    Initialize-SkynetScreen -HideCursor

    # Звук поднимается здесь, а не в прологе: основное шоу (сцена загрузки
    # [INIT]/[OK] и «дампа памяти») идёт после пролога, и раньше звук там
    # просто отсутствовал. Фоновый гул теперь живёт до самого финала.
    try {
        if (Get-Command 'Initialize-SkynetAudio' -ErrorAction SilentlyContinue) {
            if (Initialize-SkynetAudio) { Start-SkynetAmbience }
        }
    } catch { }

    # Режим микрошрифта — только классический conhost.
    if ($cfg.CineSize) {
        if (Test-SkynetCineSupport) {
            Set-SkynetCineFont
            Start-Sleep -Milliseconds 350
            Write-SkynetLog -Message 'Кинорежим: микрошрифт Consolas 8px включён.' -Level 'INFO' -Module 'Render'
        } else {
            Write-SkynetLog -Message 'Кинорежим: шрифтовый API недоступен (Windows Terminal) — пропуск.' -Level 'WARN' -Module 'Render'
        }
    }

    # Бегущая строка загрузки — главный визуальный элемент фона шоу.
    if ($cfg.Marquee) {
        Start-SkynetMarqueeState -Text $cfg.MarqueeText -Speed $cfg.MarqueeSpeed
    }
    Start-SkynetConsole

    # Набор знаков: auto → брайль в Windows Terminal (2x4 субпикселя на знак),
    # полублоки в классическом conhost (Consolas не имеет глифов брайля).
    # Резолвим ДО пролога: он тоже строит символьный кадр логотипа, а
    # Get-SkynetLogoFrame принимает только Block/Ascii/Braille — значение
    # "auto" из конфига роняло пролог на ValidateSet, и он пропускался целиком.
    if (-not $cfg.CharsetExplicit -and ([string] $cfg.Charset -eq 'auto')) {
        $cfg.Charset = if (-not [string]::IsNullOrEmpty($env:WT_SESSION)) { 'Braille' } else { 'Block' }
    }

    # -----------------------------------------------------------------------
    #  Фаза 0: белый вступительный пролог (SSH-сессия → перехват PowerShell →
    #  сборка логотипа из шума → радар → сканирование юнита). Не заменяет
    #  остальное шоу, а проигрывается перед ним.
    #
    #  $script:PrologueRan: пролог уже показал символьную сборку, финальный
    #  Sixel (если включён) и одну сцену T-800. Повторять их в основной части не нужно.
    # -----------------------------------------------------------------------
    $script:PrologueRan = $false
    $script:PrologueLogoFinalShown = $false
    if (-not $NoPrologue -and -not $cfg.SkipLogo) {
        $prologueLogoFile = Resolve-LogoPath -Explicit $(if ($cfg.LogoPath) { $cfg.LogoPath } else { $null })
        if ($prologueLogoFile -and $cfg.AnsiOk) {
            try {
                $geo0 = Get-SkynetConsoleGeometry
                # Логотип должен оставаться пропорциональным исходному PNG.
                # Ширину берём по доступному окну, но высоту ограничиваем
                # соотношением сторон: иначе на низком окне 146×8 картинка
                # сплющивается и теряет качество. Минимум 4 строки оставляем
                # нижней тени/маркеру, если высота окна это позволяет.
                # Для символьной сборки оставляем по 14 колонок запаса слева и
                # справа: tear-сдвиги до 12 колонок не должны переносить строки.
                # Финальный Sixel-кадр имеет отдельный размер и выводится после
                # короткого удержания видимого символьного кадра.
                $glitchMargin = 28
                $pw = [Math]::Min([Math]::Max(20, $geo0.Width - 1 - $glitchMargin), [int] $cfg.MaxFrameWidth)
                $frameWidth = [Math]::Max(1, $pw)
                $logoInfo0 = Test-SkynetLogoFile -Path $prologueLogoFile
                $sourceWidth = if ($logoInfo0.Ok -and $logoInfo0.Width -gt 0) { [int] $logoInfo0.Width } else { 2145 }
                $sourceHeight = if ($logoInfo0.Ok -and $logoInfo0.Height -gt 0) { [int] $logoInfo0.Height } else { 1207 }
                $frameHeight = [int][Math]::Round(($frameWidth * $sourceHeight / [double] $sourceWidth) / 2.0)
                $availableHeight = [Math]::Max(4, $geo0.Height - 3)
                $ph = [Math]::Max(4, [Math]::Min([Math]::Min($availableHeight, $frameHeight), [int] $cfg.MaxFrameHeight))
                # Прологу нужен именно посимвольный кадр (для «сборки из шума»
                # построчно) — sixel-картинку разобрать на символы нельзя,
                # поэтому здесь всегда -Sixel:$false независимо от $cfg.Sixel;
                # основной показ логотипа ниже по-прежнему уважает выбор
                # пользователя (sixel либо символы).
                # Набор знаков подстраховываем: в Get-SkynetLogoFrame допустимы
                # только Block/Ascii/Braille (см. резолв auto выше).
                $prologueCharSet = if (@('Block', 'Ascii', 'Braille') -contains [string] $cfg.Charset) { [string] $cfg.Charset } else { 'Block' }
                # Пропорции клетки шрифта — всегда, а не только в кинорежиме:
                # chafa получает реальный font-ratio и не растягивает картинку,
                # отсюда чёткие мелкие детали вместо крупных размытых блоков.
                $prologueFontRatio = 0
                try {
                    $cell0 = Get-SkynetCellSize
                    if ($cell0 -and $cell0.Width -gt 0 -and $cell0.Height -gt 0) { $prologueFontRatio = $cell0.Width / [double] $cell0.Height }
                } catch { }
                $prologueFrame = Get-SkynetLogoFrame -Path $prologueLogoFile -Width $pw -Height $ph -ColorMode $cfg.LogoColor `
                    -CharSet $prologueCharSet -FontRatio $prologueFontRatio -Sixel:$false -NoChafa:$cfg.NoChafa
                $prologueFrame.Lines = @($prologueFrame.Lines)
                if ($prologueFrame.Lines.Count -gt 0) {
                    $place0 = Get-SkynetFrameTopRow -LineCount $prologueFrame.Lines.Count -ReserveBottom 3

                    # Финальный Sixel готовим отдельно от символьного кадра.
                    # Get-SkynetLogoFrame -Sixel намеренно вернёт Source=sixel
                    # и Lines=@(), после чего прямой callback выведет пиксели.
                    $prologueFinalAction = $null
                    $prologueOnlineRow = [int]($place0.TopRow + $prologueFrame.Lines.Count)
                    if ($cfg.Sixel) {
                        $sixelCellRatio = if ($prologueFontRatio -gt 0.1) { $prologueFontRatio } else { 0.5 }
                        $sixelGridAspect = ($sourceWidth / [double] $sourceHeight) / $sixelCellRatio
                        $sixelAvailWidth = [Math]::Max(1, $geo0.Width - 2)
                        # Оставляем две нижние строки под ONLINE и запас снизу,
                        # чтобы мигающая надпись не перекрывала Sixel-кадр.
                        $sixelAvailHeight = [Math]::Max(1, $geo0.Height - 4)
                        $sixelWidth = [Math]::Max(1, [int][Math]::Floor([Math]::Min(
                            [Math]::Min([int] $cfg.MaxFrameWidth, $sixelAvailWidth),
                            [Math]::Floor($sixelAvailHeight * $sixelGridAspect)
                        )))
                        $sixelHeight = [Math]::Max(1, [int][Math]::Floor([Math]::Min(
                            $sixelAvailHeight,
                            [Math]::Floor($sixelWidth / $sixelGridAspect)
                        )))
                        $sixelFrame = Get-SkynetLogoFrame -Path $prologueLogoFile -Width $sixelWidth -Height $sixelHeight `
                            -ColorMode $cfg.LogoColor -Sixel -NoChafa:$cfg.NoChafa
                        if ($sixelFrame.Source -eq 'sixel') {
                            $sixelPath = [string] $sixelFrame.Path
                            $sixelChafa = [string] $sixelFrame.Chafa
                            $sixelTopRow = [Math]::Max(1, [int](($geo0.Height - $sixelHeight) / 2) + 1)
                            $sixelCol = [Math]::Max(1, [int](($geo0.Width - $sixelWidth) / 2) + 1)
                            $prologueOnlineRow = [Math]::Max(1, [int]($sixelTopRow + $sixelHeight))
                            $prologueFinalAction = {
                                Show-SkynetSixelLogo -Path $sixelPath -ChafaPath $sixelChafa `
                                    -Width $sixelWidth -Height $sixelHeight -TopRow $sixelTopRow -Col $sixelCol
                            }.GetNewClosure()
                            Write-SkynetLog -Message "Prologue: Sixel-кадр подготовлен (${sixelWidth}x${sixelHeight}) и будет показан после символьной сборки." -Level 'INFO' -Module 'Render'
                        }
                    }

                    Show-SkynetPrologue -LogoLines $prologueFrame.Lines -LogoTopRow $place0.TopRow `
                        -FramesFolder $t800Frames -TorsoFramesFolder $torsoFrames -SpecFilePath ([string] $SpecFile) `
                        -LogoFinalAction $prologueFinalAction -LogoFinalHoldMs 2000 `
                        -LogoOnlineRow $prologueOnlineRow -NoUnitImage:$NoUnitImage
                    $script:PrologueRan = -not [bool] $cfg.Instant
                    $script:PrologueLogoFinalShown = (-not [bool] $cfg.Instant -and $null -ne $prologueFinalAction)
                } else {
                    Write-SkynetLog -Message 'Prologue: кадр логотипа пуст — пролог пропущен.' -Level 'WARN' -Module 'Prologue'
                }
            } catch {
                Write-SkynetLog -Message "Prologue: ошибка ($($_.Exception.Message)) — пролог пропущен." -Level 'WARN' -Module 'Prologue'
            }
        } else {
            Write-SkynetLog -Message 'Prologue: логотип не найден или ANSI недоступен — пролог пропущен.' -Level 'WARN' -Module 'Prologue'
        }
    }

    # -----------------------------------------------------------------------
    #  Фаза 1: boot-текст
    # -----------------------------------------------------------------------
    if (-not $cfg.SkipBoot) {
        Start-SkynetBootSequence -ProgressFrom 4 -ProgressTo 55 -ProgressLabel 'LOADING NEURAL NET CORE'
    } else {
        Set-SkynetProgress -Percent 55 -Label 'NEURAL NET CORE READY'
    }
    # -----------------------------------------------------------------------
    #  Фаза 1.5: финал после зелёной загрузки.
    #  Чёрный экран → ОТДЕЛЬНОЕ ОКНО видеозвонка с T-800 (ускорено на
    #  $FinaleSpeedup%) → обрыв связи из-за Malwarebytes → чёрный экран →
    #  "I'll be back" → окно терминала уменьшается до рабочего размера.
    #  Пока идёт звонок, в этом терминале моргает "$ContactText".
    # -----------------------------------------------------------------------
    if (-not $cfg.Instant) {
        Show-SkynetTerminatorFinale -FramesFolder $FinaleFramesFolder -FrameIntervalMs $FinaleFrameIntervalMs `
            -Speedup $FinaleSpeedup -ContactText $ContactText -ContactBlinkMs $ContactBlinkMs `
            -NoCallWindow:$NoCallWindow -NoRestoreWindow:$NoRestoreWindow
    }
    # -----------------------------------------------------------------------
    #  Финализация: логотип отключён или уже показан в прологе.
    #  Если Sixel не был показан (например, -Sixel:$false), обычная ветка ниже
    #  всё равно выведет финальный символьный кадр.
    # -----------------------------------------------------------------------
    if ($cfg.SkipLogo -or $script:PrologueLogoFinalShown) {
        Set-SkynetProgress -Percent 100 -Label 'SKYNET ONLINE'
        Write-SkynetStatusLine -Text 'AWAITING ORDERS, HUMAN.' -Color $GLOBAL:ColBright
        $skipReason = if ($cfg.SkipLogo) { '-SkipLogo' } else { 'Sixel-логотип уже показан в прологе после символьной сборки' }
        Write-SkynetLog -Message "Boot-последовательность завершена, повторный показ пропущен ($skipReason)." -Level 'INFO' -Module 'Boot'
        Wait-SkynetKey
        Start-SkynetDelay -Milliseconds $cfg.ExitDelayMs
        $script:ExitCode = 0
    } else {

        # -------------------------------------------------------------------
        #  Финальный логотип. Сюда попадаем только если он не был показан
        #  в прологе (например, -Sixel:$false).
        # -------------------------------------------------------------------
        $logoFile = Resolve-LogoPath -Explicit $(if ($cfg.LogoPath) { $cfg.LogoPath } else { $null })
        if (-not $logoFile) {
            Set-SkynetProgress -Percent 55 -Label 'LOGO NOT FOUND'
            Write-SkynetStatusLine -Text 'SKYNET ERROR: LOGO FILE NOT FOUND' -Color $GLOBAL:ColError
            Write-SkynetLog -Message 'Логотип не найден — проверьте skynet_logo.png в корне проекта или в assets\.' -Level 'ERROR' -Module 'Render'
            $script:ExitCode = 1
        } else {
            $logoInfo = Test-SkynetLogoFile -Path $logoFile
            Write-SkynetLog -Message "Логотип: $logoFile ($($logoInfo.Bytes) байт, $($logoInfo.Width)x$($logoInfo.Height))" -Level 'INFO' -Module 'Render'
            if ($logoInfo.Small) {
                Write-SkynetLog -Message 'Внимание: файл логотипа подозрительно мал — оригинал может быть утерян.' -Level 'WARN' -Module 'Render'
            }

            # Размер графики: AUTO = всё окно (максимум колонок/строк) либо WxH из конфига.
            $geo = Get-SkynetConsoleGeometry
            $maxCols = [Math]::Max(20, $geo.Width - 1)
            $maxRows = [Math]::Max(5, $geo.Height - 3)

            if ($cfg.AutoSize) {
                $wantedWidth = [Math]::Min($maxCols, [int] $cfg.MaxFrameWidth)
                $wantedHeight = [Math]::Min($maxRows, [int] $cfg.MaxFrameHeight)
            } else {
                $sizeParts = [string] $cfg.Size -split 'x'
                $wantedWidth = [int] $cfg.RenderWidth
                $wantedHeight = [int] $cfg.RenderHeight
                $parsed = 0
                if ($sizeParts.Count -ge 1 -and [int]::TryParse($sizeParts[0], [ref] $parsed) -and $parsed -gt 0) { $wantedWidth = $parsed }
                $parsed = 0
                if ($sizeParts.Count -ge 2 -and [int]::TryParse($sizeParts[1], [ref] $parsed) -and $parsed -gt 0) { $wantedHeight = $parsed }
            }

            $logoWidth = [Math]::Min($wantedWidth, $maxCols)
            $logoHeight = [Math]::Min($wantedHeight, $maxRows)

            # Набор знаков уже разрезолвлен из "auto" перед прологом (см. выше) —
            # здесь только фиксируем итог в логе.
            Write-SkynetLog -Message "Кадр: окно $($geo.Width)x$($geo.Height), знакомест ${logoWidth}x${logoHeight}, знаки=$($cfg.Charset)" -Level 'INFO' -Module 'Render'

            # Boot-текст уступает место логотипу.
            Clear-SkynetConsole
            if ($cfg.AnsiOk) { Clear-SkynetFrame -LineCount ([Math]::Max(1, $geo.Height - 3)) -TopRow 1 }
            Set-SkynetProgress -Percent 72 -Label 'RENDERING SKYNET LOGO'
            Start-SkynetDelay -Milliseconds 200

            # FontRatio — всегда (не только в кинорежиме): реальные пропорции
            # клетки шрифта дают chafa нерастянутый кадр с мелкими деталями.
            $fontRatio = 0
            try {
                $cell = Get-SkynetCellSize
                if ($cell -and $cell.Width -gt 0 -and $cell.Height -gt 0) { $fontRatio = $cell.Width / [double] $cell.Height }
            } catch { }

            $frame = Get-SkynetLogoFrame -Path $logoFile -Width $logoWidth -Height $logoHeight -ColorMode $cfg.LogoColor `
                -CharSet $cfg.Charset -FontRatio $fontRatio -Sixel:$cfg.Sixel -NoChafa:$cfg.NoChafa
            # PowerShell разворачивает массив из 0/1 элементов при return в скаляр —
            # без этого @() кадр логотипа с одной строкой (или пустой) падал на
            # обязательном параметре Show-SkynetLogoAnimation -Lines [string[]].
            $frame.Lines = @($frame.Lines)
            Write-SkynetLog -Message "Кадр логотипа: источник=$($frame.Source), строк=$($frame.Lines.Count), ширина=$logoWidth" -Level 'INFO' -Module 'Render'
            if ($frame.Source -ne 'sixel' -and $frame.Lines.Count -eq 0) {
                Write-SkynetLog -Message 'Кадр логотипа пуст (0 строк) — chafa/встроенный рендерер не смогли построить картинку. Проверь путь к логотипу и размеры.' -Level 'ERROR' -Module 'Render'
            }

            if ($frame.Source -eq 'sixel') {
                # Sixel не поддерживает fade кадра: прямой вывод chafa целиком.
                $finalTopRow = [Math]::Max(1, [int](($geo.Height - $logoHeight) / 2) + 1)
                $finalCol = [Math]::Max(1, [int](($geo.Width - $logoWidth) / 2) + 1)
                Show-SkynetSixelLogo -Path $logoFile -ChafaPath $frame.Chafa -Width $logoWidth -Height $logoHeight `
                    -TopRow $finalTopRow -Col $finalCol
                Set-SkynetProgress -Percent 100 -Label 'SKYNET ONLINE'
                Start-SkynetDelay -Milliseconds ($cfg.HoldSeconds * 1000)
            } else {
                # Этот путь используется только с -Sixel:$false или -NoChafa.
                Set-SkynetProgress -Percent 85 -Label 'NEURAL NET ONLINE'
                $place = Get-SkynetFrameTopRow -LineCount $frame.Lines.Count -ReserveBottom 3
                Show-SkynetLogoAnimation -Lines $frame.Lines -TopRow $place.TopRow -FadeInMs $cfg.FadeInMs `
                    -HoldSeconds $cfg.HoldSeconds -FadeOutMs $cfg.FadeOutMs -NoFade:($cfg.NoFade -or -not $cfg.AnsiOk)
            }

            # Логотип показан (символами или sixel-картинкой) — включаем сцену T-800.
            # Для sixel-режима нет покадрового растворения, пиксели остаются на экране,
            # поэтому перед сценой принудительно чистим весь терминал.
            if (-not $NoT800 -and -not $script:PrologueRan) {
                if ($frame.Source -eq 'sixel' -and $cfg.AnsiOk) {
                    $esc = Get-SkynetEsc
                    [Console]::Out.Write("${esc}[0m${esc}[40m${esc}[3J${esc}[2J${esc}[H")
                }

                # Источник кадров вращения уже разрешён в самом начале скрипта
                # (см. $t800Frames выше) — переиспользуем, без повторной логики.

                $t800 = if ($T800Path) { $T800Path } else { Join-Path $cfg.ProjectRoot 'assets\t800.png' }
                if ($t800Frames -or (Test-Path -LiteralPath $t800 -PathType Leaf)) {
                    Show-SkynetT800Scene -FramesFolder $t800Frames -Path $t800 -Seconds $T800Seconds `
                        -SpinSeconds $SpinSeconds -SpinSteps $SpinSteps -ColorMode 'Green'
                } else {
                    Write-SkynetLog -Message "T-800: нет ни папки кадров, ни файла ($t800) — сцена пропущена." -Level 'WARN' -Module 'T800'
                }
            }

            Set-SkynetProgress -Percent 100 -Label 'SKYNET ONLINE'
            Write-SkynetStatusLine -Text 'AWAITING ORDERS, HUMAN.' -Color $GLOBAL:ColBright
            Write-SkynetLog -Message 'Skynet online: логотип показан.' -Level 'INFO' -Module 'Core'
            Wait-SkynetKey
            Start-SkynetDelay -Milliseconds $cfg.ExitDelayMs
        }
    }
} catch {
    $script:ExitCode = 1
    Write-SkynetLog -Message "Сбой шоу: $($_.Exception.Message) [$($_.InvocationInfo.ScriptLineNumber)]" -Level 'FATAL' -Module 'Core'
    try {
        Write-SkynetLog -Message "Стек: $($_.ScriptStackTrace)" -Level 'DEBUG' -Module 'Core'
        Write-SkynetStatusLine -Text "SKYNET FAILURE: $($_.Exception.Message)" -Color $GLOBAL:ColError
    } catch { }
} finally {
    # Фоновый гул играет до самого конца шоу, а освобождается здесь — после
    # финала, в единственном месте, отвечающем за весь прогон.
    try { if (Get-Command 'Close-SkynetAudio' -ErrorAction SilentlyContinue) { Close-SkynetAudio } } catch { }
    try { Stop-SkynetMarquee -Erase } catch { }
    try { Stop-SkynetConsole } catch { }
    Restore-SkynetScreen

    # Каретку — в первую строку, ПОСЛЕДНЕЙ операцией шоу. Раньше это делалось
    # в финале, но следом Stop-SkynetMarquee -Erase уводил курсор на строку
    # бегущей строки (вниз), и PowerShell печатал приглашение уже там.
    # Теперь промпт (он лишь красит текст, не двигает курсор) сам окажется
    # в первой строке — а терминал при этом остаётся рабочим.
    try {
        if ($cfg.AnsiOk) { [Console]::Out.Write("$([char]27)[H") }
        [Console]::Out.Flush()
    } catch { }
}

# -KeepShell: не выходим из процесса, чтобы после шоу остался рабочий
# промпт PowerShell в уже восстановленном окне терминала.
if ($KeepShell) { return }

exit $script:ExitCode
