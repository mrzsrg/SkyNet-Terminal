<#
.SYNOPSIS
    SkyNet T800 — вторая сцена: схема T-800, ТТХ и вращающаяся голова.

.DESCRIPTION
    Сцена играется сразу после растворения логотипа:
    - слева панель ТТХ: строки «раскодируются» из шума и периодически
      пересобираются (живая телеметрия);
    - справа голова T-800 вращается вокруг вертикальной оси;
    - снизу продолжает бежать жёлтая бегущая строка и прогресс-бар;
    - поверх всего работает слой SkyNet.Glitch (микрофризы и сдвиги строк).

    Два режима вращения (Show-SkynetT800Scene выбирает сам):

    1) ПОСЛЕДОВАТЕЛЬНОСТЬ КАДРОВ (-FramesFolder) — рекомендуется.
       Папка с пронумерованными PNG (1.png, 2.png, ... N.png — настоящий
       рендер поворота головы, например из ComfyUI/Blender). Файлы
       сортируются по числу в имени (натуральная сортировка: 2 раньше 10),
       каждый рисуется chafa в одну и ту же коробку WIDTHxHEIGHT
       (--stretch), и во время сцены они быстро сменяют друг друга —
       никакого фейка, вращение настоящее, просто «флипбук».

    2) ОДНА КАРТИНКА (-Path) — запасной вариант, если кадров вращения нет.
       Голова — один PNG, отрисованный chafa N раз с разной шириной
       (w = W * |cos a|) и растяжением по высоте (--stretch). Кадры задней
       полусферы зеркалятся по горизонтали (ConvertTo-SkynetMirroredLine).
       Получается «поворот карточки» — грубая имитация, но работает даже
       с одной фотографией анфас.

    Кадры в обоих режимах строятся один раз перед сценой и кэшируются на
    диск (кэш привязан к содержимому — папке/файлу, размерам и цвету),
    поэтому повторные запуски стартуют мгновенно.

    Зависимости: SkyNet.Core, SkyNet.Anim, SkyNet.Render, SkyNet.Glitch.
#>

$script:ScrambleChars = '0123456789ABCDEF#%&*/\|<>=+-_:.'

# --- Профиль отрисовки кадров T-800 ------------------------------------------
# Ошибка «плохого качества картинки»: chafa запускается с выводом в pipe (PowerShell
# читает её stdout в переменную), и для pipe/неизвестного терминала она сама выбирает
# 16 цветов + дитеринг + набор символов с крупными блоками. На контурном арте это
# давало «камуфляжную кашу»: половина знаков — полублоки, контур терялся.
# Теперь профиль задаётся жёстко: самый мелкий растр (брайль — 2x4 субпикселя на
# знакоместо), без дитеринга, максимальное старание (-w 9) и --fg-only, чтобы фон
# источника (прозрачный/белый) вообще не печатался, а светились только линии.
# Строка входит в ключ кэша кадров — старые «блочные» кэши не переиспользуются.
$script:T800RenderFlavor = 'braille-fgonly-v2'


# --- Оранжевая палитра панели ТТХ -------------------------------------------
# ТТХ печатаются оранжевым (сигнальный/тревожный канал, отдельно от зелёного
# фона консоли и жёлтой бегущей строки). Объявляем здесь же, чтобы модуль не
# зависел от правок в SkyNet.Core.
if (-not $GLOBAL:ColT800Dim) { $GLOBAL:ColT800Dim = "$([char]27)[38;2;150;80;0m" }      # ярлык поля (тусклый янтарь)
if (-not $GLOBAL:ColT800Mid) { $GLOBAL:ColT800Mid = "$([char]27)[38;2;255;120;0m" }     # значение в процессе раскодирования
if (-not $GLOBAL:ColT800Bright) { $GLOBAL:ColT800Bright = "$([char]27)[38;2;255;170;40m" } # готовое значение (ярче)
if (-not $GLOBAL:ColT800Scan) { $GLOBAL:ColT800Scan = "$([char]27)[38;2;255;45;45m" }   # накопительные аннотации сканирования

# --- Утолщение тонких линий перед chafa -------------------------------------
# Контурный арт (прозрачный фон, штрихи 1-3px) при сжатии в ~89x43 знакомест
# (это ×15-25 по каждой оси) почти весь проваливается между отсчётами chafa —
# голова рендерится почти пустой. Лечится дилатацией альфа-канала на 2px перед
# рендером: заполнение вырастает с ~28% до ~99% при сохранении узнаваемости
# (проверено на реальном ассете проекта). SkyImagePrep.cs лежит рядом с этим
# модулем и компилируется один раз при первом Import-Module.
if (-not ('SkyImagePrep' -as [type])) {
    $skyImagePrepCs = Join-Path $PSScriptRoot 'SkyImagePrep.cs'
    if (Test-Path -LiteralPath $skyImagePrepCs -PathType Leaf) {
        # .NET 10 (pwsh 7.6+) разнёс System.Drawing по нескольким сборкам, поэтому
        # одного Add-Type -Path уже мало: тип Bitmap лежит в System.Drawing.Common,
        # но зависящие от него типы — в System.Private.Windows.* и
        # System.Drawing.Primitives. Пробуем наборы ссылок от полного к пустому,
        # чтобы модуль продолжал работать и на старой платформе (.NET Framework).
        $refSets = @(
            @('System.Drawing.Common', 'System.Private.Windows.GdiPlus', 'System.Private.Windows.Core', 'System.Drawing.Primitives'),
            @('System.Drawing.Common', 'System.Drawing.Primitives'),
            @()
        )
        foreach ($refs in $refSets) {
            try {
                if ($refs.Count -gt 0) {
                    Add-Type -Path $skyImagePrepCs -ReferencedAssemblies $refs -ErrorAction Stop
                } else {
                    Add-Type -Path $skyImagePrepCs -ErrorAction Stop
                }
            } catch { }
            if ('SkyImagePrep' -as [type]) { break }
        }
        if (-not ('SkyImagePrep' -as [type])) {
            try { Write-SkynetLog -Message 'T-800: SkyImagePrep.cs не скомпилировался — утолщение линий недоступно, кадры рисуются из оригинала.' -Level 'WARN' -Module 'T800' } catch { }
        }
    }
}

function Test-SkynetNeedsThickening {
    <#
    .SYNOPSIS
        Нужна ли дилатация: есть альфа-канал и «чернил» меньше MaxCoverage доли пикселей.
    .DESCRIPTION
        Непрозрачные картинки (обычные фото/рендеры) возвращают $false без изменений —
        дилатация имеет смысл только для прозрачного контурного арта.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [double] $MaxCoverage = 0.3,
        [byte] $AlphaThreshold = 10
    )
    if (-not ('SkyImagePrep' -as [type])) { return $false }
    try {
        $cov = [SkyImagePrep]::MeasureInkCoverage($Path, $AlphaThreshold)
        if ($cov -lt 0) { return $false }   # нет альфа-канала — не наш случай
        return ($cov -le $MaxCoverage)
    } catch { return $false }
}

function Get-SkynetThickenedFramePath {
    <#
    .SYNOPSIS
        Утолщённая версия кадра (если нужна), иначе исходный путь без изменений.
    .DESCRIPTION
        Результат кэшируется в cache\prep\ по имени+радиусу+цвету чернил+времени
        правки исходника — так зелёная и белая версии одного и того же кадра не
        затирают друг друга, а замена картинки автоматически сбрасывает кэш.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [int] $Radius = 2,
        [byte] $AlphaThreshold = 10,
        [byte] $InkR = 40, [byte] $InkG = 255, [byte] $InkB = 90
    )
    if (-not (Test-SkynetNeedsThickening -Path $Path -AlphaThreshold $AlphaThreshold)) { return $Path }

    $root = [string] $GLOBAL:_SkyNetCore.ProjectRoot
    $dir = Join-Path $root 'cache\prep'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        try { $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop } catch { return $Path }
    }
    $stamp = 0
    try { $stamp = (Get-Item -LiteralPath $Path).LastWriteTimeUtc.Ticks } catch { }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $dst = Join-Path $dir ('{0}_r{1}_{2:x2}{3:x2}{4:x2}_{5}.png' -f $name, $Radius, $InkR, $InkG, $InkB, $stamp)
    if (Test-Path -LiteralPath $dst -PathType Leaf) { return $dst }

    $ok = $false
    try { $ok = [SkyImagePrep]::DilateAlpha($Path, $dst, $Radius, $AlphaThreshold, $InkR, $InkG, $InkB) } catch { $ok = $false }
    if (-not $ok) {
        try { Write-SkynetLog -Message "T-800: не удалось утолщить линии ($Path) — использую оригинал." -Level 'WARN' -Module 'T800' } catch { }
        return $Path
    }
    return $dst
}

function Resolve-SkynetFramePaths {
    <# .SYNOPSIS Прогнать список путей через Get-SkynetThickenedFramePath (или вернуть как есть, если хелпер недоступен). #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyCollection()][string[]] $Paths = @(),
        [int] $Radius = 2,
        [byte] $InkR = 40, [byte] $InkG = 255, [byte] $InkB = 90
    )
    if (-not ('SkyImagePrep' -as [type])) { return $Paths }
    return @($Paths | ForEach-Object { Get-SkynetThickenedFramePath -Path $_ -Radius $Radius -InkR $InkR -InkG $InkG -InkB $InkB })
}

function Get-SkyT800Esc {
    <# .SYNOPSIS Общий ESC-символ. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($GLOBAL:SkyEsc) { return [string] $GLOBAL:SkyEsc }
    return [string][char]27
}

function Get-SkynetT800Specs {
    <#
    .SYNOPSIS
        Набор строк ТТХ — канонические данные T-800 (tactical_and_technical_specifications.txt).
    .DESCRIPTION
        Value — статическая строка (сам текст ТТХ, без выдумок). Gen — необязательный
        scriptblock для «живого» дребезга счётчика (используется только там, где в исходном
        тексте прямо описана числовая динамика — например, 20 млн сценариев в секунду);
        Gen-строки периодически пересчитываются во время сцены, остальные остаются как есть.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    return @(
        @{ Label = 'UNIT';         Value = 'T-800 / MODEL 101';                          Gen = $null }
        @{ Label = 'WEIGHT';       Value = '320 KG';                                     Gen = $null }
        @{ Label = 'MAX SPEED';    Value = '80 KM/H';                                    Gen = $null }
        @{ Label = 'PRESS FORCE';  Value = '200 TONS (HYDRAULIC)';                       Gen = $null }
        @{ Label = 'AUTONOMY';     Value = '120Y STANDBY / 50Y FULL POWER';              Gen = $null }
        @{ Label = 'CPU';          Value = '';  Gen = { 'PROCESSING {0:N0}/20M SCEN/SEC' -f (Get-Random -Minimum 4000000 -Maximum 20000000) } }
        @{ Label = 'ARMAMENT';     Value = 'NONE — HUMAN-MADE WEAPONRY ONLY';            Gen = $null }
        @{ Label = 'STD LOADOUT';  Value = 'WESTINGHOUSE 40KW PLASMA RIFLE';             Gen = $null }
        @{ Label = 'CAMOUFLAGE';   Value = 'LIVING TISSUE, MODEL CS 101';                Gen = $null }
        @{ Label = 'PROTOTYPE';    Value = 'US ARMY SGT. WILLIAM CANDY';                 Gen = $null }
        @{ Label = 'TISSUE';       Value = 'SIMULATES SWEAT / BLOOD / HAIR';             Gen = $null }
        @{ Label = 'REGEN RATE';   Value = 'FASTER THAN HUMAN TISSUE';                   Gen = $null }
        @{ Label = 'DAMAGE LIMIT'; Value = 'SEVERE = TISSUE NECROSIS';                   Gen = $null }
        @{ Label = 'PROCESSOR';    Value = 'CRANIAL, SELF-LEARNING';                     Gen = $null }
        @{ Label = 'VISION';       Value = 'BUILT-IN NIGHT-VISION MODE';                 Gen = $null }
        @{ Label = 'POWER CELL';   Value = 'IRIDIUM FUEL CELL, CHEST CAVITY';            Gen = $null }
        @{ Label = 'SKELETON';     Value = 'HYPERALLOY ENDOSKELETON';                    Gen = $null }
        @{ Label = 'STATUS';       Value = 'COMBAT READY';                               Gen = $null }
    )
}

function ConvertTo-SkynetMirroredLine {
    <#
    .SYNOPSIS
        Зеркально отразить ANSI-строку по горизонтали (для задней полусферы).
    .DESCRIPTION
        Строка разбирается на «клетки»: за каждым знаком закрепляется текущий
        цвет текста и фона. После разворота порядка клеток цвет остаётся при
        своём знаке — картинка не рассыпается.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Text = '')

    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $rx = [regex] '\x1b\[[0-9;?]*[a-zA-Z]'
    $cells = New-Object System.Collections.Generic.List[string]
    $fg = ''
    $bg = ''
    $i = 0
    while ($i -lt $Text.Length) {
        $m = $rx.Match($Text, $i)
        if ($m.Success -and $m.Index -eq $i) {
            $code = $m.Value
            if ($code -match '\[0?m$') { $fg = ''; $bg = '' }
            elseif ($code -match '\[48;') { $bg = $code }
            elseif ($code -match '\[38;') { $fg = $code }
            $i += $m.Length
            continue
        }
        $cells.Add("$bg$fg$($Text[$i])")
        $i++
    }
    $arr = $cells.ToArray()
    [array]::Reverse($arr)
    return (($arr -join '') + [string] $GLOBAL:ColReset)
}

function Get-SkynetStretchedFrame {
    <#
    .SYNOPSIS
        Кадр картинки ровно WIDTHxHEIGHT знакомест (chafa --stretch).
    .DESCRIPTION
        В отличие от Get-SkynetChafaFrame здесь пропорции НЕ сохраняются:
        для вращения нужно сжимать кадр по горизонтали, не теряя высоту.
        Если chafa недоступен или упал — встроенный рендерер проекта.
    .PARAMETER Symbols
        Классы символов chafa. По умолчанию только брайль: у него 2x4 субпикселя
        на знакоместо (вчетверо плотнее полублоков), поэтому контурный арт
        T-800 остаётся линиями, а не «кашей» из полублоков.
    .PARAMETER FgOnly
        Печатать только линии, не трогая фон терминала (по умолчанию — да).
        Именно это убирает из кадра светлую «заливку» источника.
    .PARAMETER Dither
        Режим дитеринга chafa; пустая строка — не задавать (по умолчанию 'none':
        на контурном арте дитеринг добавляет шум).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [int] $Width = 60,
        [int] $Height = 30,
        [ValidateSet('Original', 'Green')][string] $ColorMode = 'Green',
        [string] $ChafaPath = '',
        [string] $Symbols = 'braille',
        [bool] $FgOnly = $true,
        [string] $Dither = 'none',
        [int] $Work = 9
    )

    if (-not $ChafaPath) { try { $ChafaPath = Get-SkynetChafaPath } catch { $ChafaPath = $null } }
    $lines = $null

    if ($ChafaPath) {
        $chafaArgs = New-Object System.Collections.Generic.List[string]
        $chafaArgs.Add('--format=symbols')
        if (-not $Symbols) { $Symbols = 'braille' }
        $chafaArgs.Add("--symbols=$Symbols")
        $chafaArgs.Add('--color-space=din99d')
        $chafaArgs.Add('-c')
        $chafaArgs.Add('full')
        if ($FgOnly) { $chafaArgs.Add('--fg-only') }
        if ($Work -gt 0) { $chafaArgs.Add('-w'); $chafaArgs.Add([string] $Work) }
        if ($Dither) { $chafaArgs.Add("--dither=$Dither") }
        $chafaArgs.Add('--stretch')
        $chafaArgs.Add("--size=${Width}x${Height}")
        $chafaArgs.Add($Path)
        $savedEncoding = $null
        try { $savedEncoding = [Console]::OutputEncoding } catch { }
        try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
        try {
            $raw = & $ChafaPath @chafaArgs 2>$null
            if ($LASTEXITCODE -eq 0 -and $raw) {
                $clean = New-Object System.Collections.Generic.List[string]
                foreach ($line in $raw) {
                    $s = [string] $line
                    $s = $s.Replace([string][char]27 + '[?25l', '').Replace([string][char]27 + '[?25h', '')
                    $s = $s.Replace([string][char]27 + '[?7l', '').Replace([string][char]27 + '[?7h', '')
                    $s = $s.Replace([string][char]27 + '[7m', '').Replace("`r", '').TrimEnd()
                    if ((Get-SkynetVisibleLength -Text $s) -le 0) { continue }
                    $clean.Add($s)
                }
                if ($clean.Count -gt 0) { $lines = $clean.ToArray() }
            }
        } catch {
            try { Write-SkynetLog -Message "T-800: chafa не сработал ($Width x $Height): $($_.Exception.Message)" -Level 'WARN' -Module 'T800' } catch { }
        } finally {
            if ($savedEncoding) { try { [Console]::OutputEncoding = $savedEncoding } catch { } }
        }
    }

    if (-not $lines) {
        try { $lines = Get-SkynetBuiltInFrame -Path $Path -Width $Width -Height $Height -ColorMode $ColorMode -CharSet 'Block' } catch { $lines = @() }
    } elseif ($ColorMode -eq 'Green') {
        $lines = ConvertTo-SkynetGreenFrame -Lines $lines
    }
    return $lines
}

function Set-SkynetFrameBox {
    <#
    .SYNOPSIS
        Вписать кадр в коробку Width x Height: центр по горизонтали и вертикали.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyCollection()][string[]] $Lines = @(),
        [int] $Width = 60,
        [int] $Height = 30
    )
    $result = New-Object System.Collections.Generic.List[string]
    $count = $Lines.Count
    $top = [Math]::Max(0, [int](($Height - $count) / 2))
    for ($i = 0; $i -lt $Height; $i++) {
        $index = $i - $top
        if ($index -lt 0 -or $index -ge $count) { $result.Add(''); continue }
        $line = [string] $Lines[$index]
        $visible = Get-SkynetVisibleLength -Text $line
        $pad = [Math]::Max(0, [int](($Width - $visible) / 2))
        if ($pad -gt 0) { $line = (' ' * $pad) + $line }
        $result.Add($line)
    }
    return $result.ToArray()
}

function Get-SkynetT800CachePath {
    <# .SYNOPSIS Путь кэша кадров вращения для конкретной геометрии. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Path, [int] $Width, [int] $Height, [int] $Steps, [string] $ColorMode)
    $root = [string] $GLOBAL:_SkyNetCore.ProjectRoot
    $dir = Join-Path $root 'cache'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        try { $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop } catch { return $null }
    }
    $stamp = 0
    try { $stamp = (Get-Item -LiteralPath $Path).LastWriteTimeUtc.Ticks } catch { }
    $key = ('{0}_{1}x{2}_{3}_{4}_{5}_{6}' -f ([System.IO.Path]::GetFileNameWithoutExtension($Path)), $Width, $Height, $Steps, $ColorMode, $script:T800RenderFlavor, $stamp)
    return (Join-Path $dir "t800_$key.spin")
}

function Get-SkynetT800FramePaths {
    <#
    .SYNOPSIS
        Пронумерованные кадры вращения из папки (натуральная числовая сортировка).
    .DESCRIPTION
        Файлы сортируются по первому числу в имени, а не по алфавиту —
        иначе "10.png" встал бы раньше "2.png". Поддерживаются
        png/jpg/jpeg/bmp/webp.
    .PARAMETER NumericOnly
        Брать только файлы с ПОЛНОСТЬЮ числовым именем (1.png, 02.png, 31.png).
        Нужно, когда кадры лежат в общей папке (например assets) вперемешку
        с другими картинками — чтобы туда случайно не попал, скажем, логотип.
    .EXAMPLE
        Get-SkynetT800FramePaths -FolderPath .\assets -NumericOnly
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string] $FolderPath,
        [switch] $NumericOnly
    )

    if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) { return @() }
    $exts = @('.png', '.jpg', '.jpeg', '.bmp', '.webp')
    $files = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue |
            Where-Object { $exts -contains $_.Extension.ToLowerInvariant() })
    if ($NumericOnly) {
        $files = @($files | Where-Object { $_.BaseName -match '^\d+$' })
    }
    if ($files.Count -eq 0) { return @() }

    $sorted = $files | Sort-Object -Property @(
        @{ Expression = { if ($_.BaseName -match '(\d+)') { [int] $Matches[1] } else { [int]::MaxValue } } },
        @{ Expression = { $_.BaseName } }
    )
    return @($sorted | ForEach-Object { $_.FullName })
}

function Get-SkynetT800FramesCachePath {
    <# .SYNOPSIS Путь кэша для последовательности кадров (папка + сигнатура файлов). #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string[]] $Paths, [int] $Width, [int] $Height, [string] $ColorMode)
    if (-not $Paths -or $Paths.Count -eq 0) { return $null }
    $root = [string] $GLOBAL:_SkyNetCore.ProjectRoot
    $dir = Join-Path $root 'cache'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        try { $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop } catch { return $null }
    }
    $folderName = Split-Path -Path (Split-Path -Path $Paths[0] -Parent) -Leaf
    $maxTicks = 0L
    $sizeSum = 0L
    foreach ($p in $Paths) {
        try {
            $fi = Get-Item -LiteralPath $p
            if ($fi.LastWriteTimeUtc.Ticks -gt $maxTicks) { $maxTicks = $fi.LastWriteTimeUtc.Ticks }
            $sizeSum += $fi.Length
        } catch { }
    }
    $key = ('{0}_{1}f_{2}x{3}_{4}_{5}_{6}_{7}' -f $folderName, $Paths.Count, $Width, $Height, $ColorMode, $script:T800RenderFlavor, $maxTicks, $sizeSum)
    return (Join-Path $dir "t800seq_$key.spin")
}

function Build-SkynetT800SpinFramesFromImages {
    <#
    .SYNOPSIS
        Построить кадры вращения из готовой последовательности изображений.
    .DESCRIPTION
        В отличие от Build-SkynetT800SpinFrames здесь НЕТ сжатия/зеркала —
        каждый файл уже показывает свой собственный ракурс, chafa просто
        рисует его в коробку WIDTHxHEIGHT (--stretch), чтобы кадры не
        прыгали по размеру при быстрой смене.
    .PARAMETER OnStep
        Scriptblock прогресса: & $OnStep $index $total.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string[]] $Paths,
        [int] $Width = 60,
        [int] $Height = 30,
        [ValidateSet('Original', 'Green')][string] $ColorMode = 'Green',
        [int] $ThickenRadius = 2,
        [byte] $InkR = 40, [byte] $InkG = 255, [byte] $InkB = 90,
        [scriptblock] $OnStep,
        [switch] $NoCache
    )
    if (-not $Paths -or $Paths.Count -eq 0) { return @() }

    # Утолщение тонких линий (если нужно) — резолвим ДО кэш-ключа, чтобы разные
    # цвета чернил не путались в одном и том же файле кэша.
    $Paths = Resolve-SkynetFramePaths -Paths $Paths -Radius $ThickenRadius -InkR $InkR -InkG $InkG -InkB $InkB

    $cacheFile = $null
    if (-not $NoCache) {
        $cacheFile = Get-SkynetT800FramesCachePath -Paths $Paths -Width $Width -Height $Height -ColorMode $ColorMode
        if ($cacheFile -and (Test-Path -LiteralPath $cacheFile -PathType Leaf)) {
            try {
                $blob = [System.IO.File]::ReadAllText($cacheFile, [System.Text.Encoding]::UTF8)
                $frames = @()
                foreach ($chunk in ($blob -split ([string][char]1))) {
                    if (-not $chunk) { continue }
                    $frames += , ($chunk -split "`n")
                }
                if ($frames.Count -eq $Paths.Count) {
                    try { Write-SkynetLog -Message "T-800: кадры вращения (последовательность, $($Paths.Count)) взяты из кэша." -Level 'DEBUG' -Module 'T800' } catch { }
                    return $frames
                }
            } catch { }
        }
    }

    $chafa = $null
    try { $chafa = Get-SkynetChafaPath } catch { }

    $frames = @()
    $total = $Paths.Count
    for ($i = 0; $i -lt $total; $i++) {
        $lines = Get-SkynetStretchedFrame -Path $Paths[$i] -Width $Width -Height $Height -ColorMode $ColorMode -ChafaPath $chafa
        $frames += , (Set-SkynetFrameBox -Lines $lines -Width $Width -Height $Height)
        if ($OnStep) { & $OnStep $i $total }
    }

    if ($cacheFile) {
        try {
            $blob = (($frames | ForEach-Object { $_ -join "`n" }) -join ([string][char]1))
            [System.IO.File]::WriteAllText($cacheFile, $blob, [System.Text.Encoding]::UTF8)
        } catch { }
    }
    return $frames
}

function Build-SkynetT800SpinFrames {
    <#
    .SYNOPSIS
        Построить кадры вращения головы вокруг вертикальной оси.
    .PARAMETER Steps
        Число кадров на полный оборот (16 — достаточно плавно и быстро строится).
    .PARAMETER OnStep
        Scriptblock прогресса: & $OnStep $index $total.
    .OUTPUTS
        Массив кадров; каждый кадр — string[] высотой Height и шириной Width.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [int] $Width = 60,
        [int] $Height = 30,
        [int] $Steps = 16,
        [ValidateSet('Original', 'Green')][string] $ColorMode = 'Green',
        [int] $ThickenRadius = 2,
        [byte] $InkR = 40, [byte] $InkG = 255, [byte] $InkB = 90,
        [scriptblock] $OnStep,
        [switch] $NoCache
    )

    $Path = Get-SkynetThickenedFramePath -Path $Path -Radius $ThickenRadius -InkR $InkR -InkG $InkG -InkB $InkB

    $cacheFile = $null
    if (-not $NoCache) {
        $cacheFile = Get-SkynetT800CachePath -Path $Path -Width $Width -Height $Height -Steps $Steps -ColorMode $ColorMode
        if ($cacheFile -and (Test-Path -LiteralPath $cacheFile -PathType Leaf)) {
            try {
                $blob = [System.IO.File]::ReadAllText($cacheFile, [System.Text.Encoding]::UTF8)
                $frames = @()
                foreach ($chunk in ($blob -split ([string][char]1))) {
                    if (-not $chunk) { continue }
                    $frames += , ($chunk -split "`n")
                }
                if ($frames.Count -eq $Steps) {
                    try { Write-SkynetLog -Message "T-800: кадры вращения взяты из кэша ($cacheFile)." -Level 'DEBUG' -Module 'T800' } catch { }
                    return $frames
                }
            } catch { }
        }
    }

    $chafa = $null
    try { $chafa = Get-SkynetChafaPath } catch { }

    $frames = @()
    for ($i = 0; $i -lt $Steps; $i++) {
        $angle = 2.0 * [Math]::PI * $i / [double] $Steps
        $cos = [Math]::Cos($angle)
        $scale = [Math]::Max(0.16, [Math]::Abs($cos))
        $frameWidth = [int][Math]::Round($Width * $scale)
        if ($frameWidth -lt 6) { $frameWidth = 6 }

        $lines = Get-SkynetStretchedFrame -Path $Path -Width $frameWidth -Height $Height -ColorMode $ColorMode -ChafaPath $chafa
        if ($cos -lt 0) {
            $mirrored = New-Object System.Collections.Generic.List[string]
            foreach ($line in $lines) { $mirrored.Add((ConvertTo-SkynetMirroredLine -Text $line)) }
            $lines = $mirrored.ToArray()
        }
        $frames += , (Set-SkynetFrameBox -Lines $lines -Width $Width -Height $Height)
        if ($OnStep) { & $OnStep $i $Steps }
    }

    if ($cacheFile) {
        try {
            $blob = (($frames | ForEach-Object { $_ -join "`n" }) -join ([string][char]1))
            [System.IO.File]::WriteAllText($cacheFile, $blob, [System.Text.Encoding]::UTF8)
        } catch { }
    }
    return $frames
}

function Get-SkynetScrambledText {
    <#
    .SYNOPSIS
        Текст, частично «раскодированный» из шума (progress 0..1).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Text = '', [double] $Progress = 1.0)

    if ($Progress -ge 1.0) { return $Text }
    if ($Progress -lt 0) { $Progress = 0 }
    $len = $Text.Length
    $solid = [int][Math]::Floor($len * $Progress)
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $len; $i++) {
        if ($i -lt $solid) { [void]$sb.Append($Text[$i]); continue }
        if ($Text[$i] -eq ' ') { [void]$sb.Append(' '); continue }
        [void]$sb.Append($script:ScrambleChars[(Get-Random -Minimum 0 -Maximum $script:ScrambleChars.Length)])
    }
    return $sb.ToString()
}

function New-SkynetT800PanelState {
    <# .SYNOPSIS Начальное состояние панели ТТХ. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([int] $Width = 50)

    $specs = Get-SkynetT800Specs
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($spec in $specs) {
        $value = [string] $spec.Value
        if ($spec.Gen) { $value = [string] (& $spec.Gen) }
        $rows.Add(@{
                Label    = [string] $spec.Label
                Value    = $value
                Gen      = $spec.Gen
                Progress = 0.0      # 0 — шум, 1 — читаемая строка
                Active   = $false   # уже начала раскодироваться
                Dirty    = $true    # требует перерисовки
            })
    }
    return @{ Rows = $rows; Width = $Width; Next = 0 }
}

function Format-SkynetT800Row {
    <# .SYNOPSIS Собрать строку панели: «LABEL ....... VALUE». #>
    [CmdletBinding()]
    [OutputType([string])]
    param([hashtable] $Row, [int] $Width = 50)

    $label = ([string] $Row.Label).PadRight(12)
    $value = Get-SkynetScrambledText -Text ([string] $Row.Value) -Progress ([double] $Row.Progress)
    $text = "$label $value"
    if ($text.Length -gt $Width) { $text = $text.Substring(0, $Width) }

    $labelColor = [string] $GLOBAL:ColT800Dim
    $valueColor = if ([double] $Row.Progress -ge 1.0) { [string] $GLOBAL:ColT800Bright } else { [string] $GLOBAL:ColT800Mid }
    $head = $text.Substring(0, [Math]::Min(12, $text.Length))
    $tail = if ($text.Length -gt 12) { $text.Substring(12) } else { '' }
    return "$labelColor$head$valueColor$tail$($GLOBAL:ColReset)"
}

function Get-SkynetT800ScanStages {
    <#
    .SYNOPSIS
        Канонический порядок зон диагностического сканирования T-800.
    .DESCRIPTION
        Названия зон совпадают с итоговым отчётом Cyberdyne из
        Get-SkynetCyberdyneScanBlock (SkyNet.Prologue), поэтому сцена основного
        шоу и пролог выводят один и тот же список, а не два разных.

        Диапазоны кадров: первые четыре зоны занимают фиксированные участки
        97…136, участок 137…196 делится пополам на каркас и сервоприводы.
        Кадры 197…N, если они есть в папке, образуют отдельный этап
        FULL-BODY SCAN и после последнего кадра получают подтверждение
        FULL-BODY SCAN DONE. Номер последнего кадра передаётся из
        фактического списка PNG.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([int] $LastFrameNumber = 215)
    $stages = @(
        @{ Key = 'processor'; Label = 'NEURAL PROCESSOR SCAN'; Target = 'HEAD'; Start = 97; End = 106; Order = 0; Blink = $true },
        @{ Key = 'memory'; Label = 'LEARNING COMPUTER SCAN'; Target = 'HEAD'; Start = 107; End = 116; Order = 1; Blink = $true },
        @{ Key = 'optics'; Label = 'OPTICAL/ACOUSTIC SENSOR SCAN'; Target = 'HEAD'; Start = 117; End = 126; Order = 2; Blink = $true },
        @{ Key = 'power'; Label = 'POWER CORE SCAN'; Target = 'CHEST CAVITY'; Start = 127; End = 136; Order = 3; Blink = $true },
        @{ Key = 'chassis'; Label = 'HYPER-ALLOY COMBAT CHASSIS SCAN'; Target = 'FULL UNIT'; Start = 137; End = 166; Order = 4; Blink = $true },
        @{ Key = 'hydraulic'; Label = 'HYDRAULIC SERVO SCAN'; Target = 'LEGS'; Start = 167; End = 196; Order = 5; Blink = $true }
    )
    if ($LastFrameNumber -ge 197) {
        $stages += @{ Key = 'body'; Label = 'FULL-BODY SCAN'; Target = 'FULL UNIT'; Start = 197; End = $LastFrameNumber; Order = 6; Blink = $true }
    }
    return @($stages)
}

function Get-SkynetT800ScanStage {
    <# .SYNOPSIS Этап сканирования по номеру исходного кадра. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [int] $FrameNumber = 0,
        [int] $LastFrameNumber = 215
    )
    foreach ($candidate in @(Get-SkynetT800ScanStages -LastFrameNumber $LastFrameNumber)) {
        if ($FrameNumber -ge $candidate.Start -and $FrameNumber -le $candidate.End) { return $candidate }
    }
    return $null
}

function Get-SkynetT800ScanAnnotation {
    <#
    .SYNOPSIS
        Аннотация слева от T-800; стрелка направлена вправо к Sixel-кадру.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [hashtable] $Stage = $null,
        [int] $ElapsedSinceProcessorMs = 0,
        [int] $ProcessorScanMs = 1000,
        [bool] $Visible = $true,
        [int] $PanelWidth = 40,
        [bool] $Completed = $false
    )
    if (-not $Stage) { return '' }
    $arrow = ' ---->'
    $label = [string] $Stage.Label
    if ($Completed) {
        $label = "$label DONE"
    } elseif ($Stage.Key -eq 'processor') {
        if ($ElapsedSinceProcessorMs -lt $ProcessorScanMs) {
            if (-not $Visible) { return '' }
        } else {
            $label = "$label DONE"
        }
    } elseif ($Stage.Blink -and -not $Visible) {
        return ''
    }
    $maxLabel = [Math]::Max(1, $PanelWidth - $arrow.Length)
    if ($label.Length -gt $maxLabel) {
        # Названия зон длиннее прежних (HYPER-ALLOY COMBAT CHASSIS SCAN), и
        # обрезка пополам рвала слово. Режем по последнему пробелу, но только
        # если от него остаётся больше половины строки, иначе — простой срез.
        $cut = $label.Substring(0, $maxLabel)
        $spaceAt = $cut.LastIndexOf(' ')
        if ($spaceAt -ge [int][Math]::Ceiling($maxLabel / 2)) { $cut = $cut.Substring(0, $spaceAt) }
        $label = $cut.TrimEnd()
    }
    return ($label.PadRight($maxLabel) + $arrow)
}

function Write-SkynetT800ScanRow {
    <#
    .SYNOPSIS
        Локальный абсолютный вывод строки аннотации, без зависимости T-800 от Prologue.
    #>
    [CmdletBinding()]
    param(
        [int] $Row = 1,
        [string] $Text = '',
        [int] $Width = 40,
        [string] $Color = ''
    )
    if ($Width -lt 1) { return }
    $plain = [regex]::Replace([string] $Text, '\x1b\[[0-9;?]*[a-zA-Z]', '')
    if ($plain.Length -gt $Width) { $plain = $plain.Substring(0, $Width) }
    $padded = $plain.PadRight($Width)
    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { [Console]::Out.WriteLine($padded); return }
    if (-not $Color) { $Color = [string] $GLOBAL:ColT800Dim }
    $esc = Get-SkyT800Esc
    [Console]::Out.Write("${esc}[${Row};2H${Color}${padded}${GLOBAL:ColReset}")
}

function Show-SkynetT800SixelSequence {
    <#
    .SYNOPSIS
        Показать последовательность T-800 как настоящий Sixel-видеоряд.
    .DESCRIPTION
        Каждый файл вызывается напрямую через Show-SkynetSixelImage/Chafa.
        Символьные кэши и Get-SkynetStretchedFrame здесь не используются.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Paths,
        [int] $Seconds = 18,
        [double] $SpinSeconds = 4.0,
        [string] $Title = 'CYBERDYNE SYSTEMS :: UNIT IDENTIFICATION SCAN',
        [string] $ChafaPath = '',
        [int] $FrameCycles = 1,
        [int] $FrameIntervalMs = 8,
        [int] $TitleOnMs = 180,
        [int] $TitleOffMs = 100
    )
    if ($FrameCycles -lt 1) { $FrameCycles = 1 }
    if ($FrameIntervalMs -lt 1) { $FrameIntervalMs = 1 }

    $cfg = $GLOBAL:_SkyNetCore
    if (-not $ChafaPath) { $ChafaPath = [string](Get-SkynetChafaPath) }
    if (-not $cfg.AnsiOk -or $cfg.Instant -or $Paths.Count -eq 0 -or -not $ChafaPath) { return }
    $esc = Get-SkyT800Esc
    $geo = Get-SkynetConsoleGeometry
    $topRow = 2
    $bottomReserve = 3
    $rows = [Math]::Max(8, $geo.Height - $bottomReserve - $topRow)
    $panelWidth = [Math]::Max(34, [int]($geo.Width * 0.44))
    if ($panelWidth -gt ($geo.Width - 24)) { $panelWidth = [Math]::Max(24, $geo.Width - 24) }
    $headCol = $panelWidth + 4
    $headWidth = [Math]::Max(20, $geo.Width - $headCol - 2)

    $first = Test-SkynetLogoFile -Path $Paths[0]
    $pixelAspect = if ($first.Ok -and $first.Width -gt 0 -and $first.Height -gt 0) {
        $first.Width / [double] $first.Height
    } else { 1.0 }
    $gridAspect = $pixelAspect / 0.5
    if ($gridAspect -ge ($headWidth / [double] $rows)) {
        $sixelWidth = $headWidth
        $sixelHeight = [Math]::Max(1, [int][Math]::Floor($sixelWidth / $gridAspect))
    } else {
        $sixelHeight = $rows
        $sixelWidth = [Math]::Max(1, [int][Math]::Floor($sixelHeight * $gridAspect))
    }
    $sixelLeft = $headCol + [int][Math]::Floor(($headWidth - $sixelWidth) / 2)
    # Последний номер берём из фактического списка: 197…N — полный проход тела.
    $lastFrameNumber = 0
    foreach ($path in $Paths) {
        $match = [regex]::Match([IO.Path]::GetFileNameWithoutExtension($path), '\d+')
        if ($match.Success) {
            $candidateNumber = [int]$match.Value
            if ($candidateNumber -gt $lastFrameNumber) { $lastFrameNumber = $candidateNumber }
        }
    }
    if ($lastFrameNumber -lt 1) { $lastFrameNumber = $Paths.Count }
    $frameIntervalMs = [Math]::Max(1, $FrameIntervalMs)
    $totalFrameCount = $Paths.Count * $FrameCycles

    Set-SkynetProgress -Percent 60 -Label 'STREAMING T-800 SIXEL SEQUENCE'
    Clear-SkynetFrame -LineCount ($geo.Height - $bottomReserve) -TopRow 1
    Write-SkynetStatusLine -Text $Title -Row 1 -Color $GLOBAL:ColWarn
    $scanStages = @(Get-SkynetT800ScanStages -LastFrameNumber $lastFrameNumber)
    $annotationTop = $topRow + 1
    # Панель ТТХ размещается после трёх пустых строк под полным блоком
    # сканирования, включая FULL-BODY SCAN. Аннотации остаются закреплённым
    # слоем и не могут быть затерты прокруткой ТТХ.
    $panel = New-SkynetT800PanelState -Width $panelWidth
    $panelTop = $annotationTop + $scanStages.Count + 3
    $panelBottom = [Math]::Min($geo.Height - $bottomReserve, $topRow + $rows - 1)
    $panelRows = @($panel.Rows | Select-Object -First ([Math]::Max(0, $panelBottom - $panelTop + 1)))

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastFrame = -1
    $titleState = @{ Visible = $true; NextAtMs = [int]$TitleOnMs }
    $annotationState = @{
        FrameNumber = 0
        ActiveStageKey = ''
        CompletedStageKeys = [System.Collections.Generic.List[string]]::new()
        ProcessorStartedAtMs = -1
        ProcessorDone = $false
        ProcessorDoneShownAtMs = -1
        BlinkOn = $true
        NextBlinkAtMs = 0
        Complete = $false
    }
    # Удержание 106.png нужно ровно один раз — на первом кадре после зоны
    # процессора. Без этого флага блок повторялся бы на каждом кадре и
    # сбрасывал активный этап обратно на processor, из-за чего строки
    # MEMORY/OPTICS/POWER никогда не переключались бы в мигание.
    $processorHoldPending = $true
    function Update-SkynetT800Annotation {
        param([int] $FrameNumber)
        $now = [int]$watch.ElapsedMilliseconds
        $annotationState.FrameNumber = $FrameNumber
        $stage = Get-SkynetT800ScanStage -FrameNumber $FrameNumber -LastFrameNumber $lastFrameNumber
        if (-not $stage) {
            if (-not $annotationState.ActiveStageKey) {
                foreach ($candidate in $scanStages) {
                    Write-SkynetT800ScanRow -Row ($annotationTop + $candidate.Order) -Text '' -Width $panelWidth -Color $GLOBAL:ColT800Scan
                }
            }
            return $null
        }

        if ($annotationState.ActiveStageKey -ne $stage.Key) {
            if ($annotationState.ActiveStageKey) {
                [void]$annotationState.CompletedStageKeys.Add($annotationState.ActiveStageKey)
            }
            $annotationState.ActiveStageKey = $stage.Key
            $annotationState.BlinkOn = $true
            $annotationState.NextBlinkAtMs = $now + 180
        }
        if ($stage.Key -eq 'processor' -and $annotationState.ProcessorStartedAtMs -lt 0) {
            $annotationState.ProcessorStartedAtMs = $now
        }
        $processorElapsed = if ($annotationState.ProcessorStartedAtMs -ge 0) {
            $now - $annotationState.ProcessorStartedAtMs
        } else { 0 }
        if ($stage.Key -eq 'processor' -and $processorElapsed -ge 1000 -and -not $annotationState.ProcessorDone) {
            $annotationState.ProcessorDone = $true
            $annotationState.ProcessorDoneShownAtMs = $now
        }
        if (-not ($stage.Key -eq 'processor' -and $annotationState.ProcessorDone) -and
            $now -ge $annotationState.NextBlinkAtMs) {
            $annotationState.BlinkOn = -not $annotationState.BlinkOn
            $annotationState.NextBlinkAtMs = $now + $(if ($annotationState.BlinkOn) { 180 } else { 120 })
        }

        foreach ($candidate in $scanStages) {
            $key = [string] $candidate.Key
            $isActive = $key -eq $annotationState.ActiveStageKey
            $isCompleted = $annotationState.CompletedStageKeys.Contains($key)
            if (-not $isActive -and -not $isCompleted) { continue }
            $visible = (-not $isActive) -or $annotationState.BlinkOn -or
                ($key -eq 'processor' -and $annotationState.ProcessorDone)
            $annotation = Get-SkynetT800ScanAnnotation -Stage $candidate `
                -ElapsedSinceProcessorMs $processorElapsed -ProcessorScanMs 1000 `
                -Visible $visible -PanelWidth $panelWidth `
                -Completed:($annotationState.Complete -and $key -eq 'body')
            Write-SkynetT800ScanRow -Row ($annotationTop + $candidate.Order) -Text $annotation `
                -Width $panelWidth -Color $GLOBAL:ColT800Scan
        }
        # ВАЖНО: функция обновления ничего не возвращает. Иначе PowerShell
        # печатает в консоль сам хештаблит зоны (Target/Label/Key/Blink/
        # Order/Start/End) — это и создавало «кашу» поверх Sixel-кадра.
    }
    function Update-SkynetT800ScanTitle {
        $now = [int]$watch.ElapsedMilliseconds
        if ($now -lt $titleState.NextAtMs) { return }
        if ($titleState.Visible) {
            Write-SkynetStatusLine -Text $Title -Row 1 -Color $GLOBAL:ColDim
            $titleState.NextAtMs = $now + [Math]::Max(1, $TitleOnMs)
        } else {
            Write-SkynetStatusLine -Text (' ' * $Title.Length) -Row 1 -Color $GLOBAL:ColDim
            $titleState.NextAtMs = $now + [Math]::Max(1, $TitleOffMs)
        }
        $titleState.Visible = -not $titleState.Visible
    }

    try {
        for ($cycle = 1; $cycle -le $FrameCycles; $cycle++) {
            for ($i = 0; $i -lt $Paths.Count; $i++) {
                $frameNumber = [int]([regex]::Match([IO.Path]::GetFileNameWithoutExtension($Paths[$i]), '\d+').Value)
                # Держим 106.png на экране до секундного DONE и короткого
                # удержания результата; 107.png не должен обгонять этот этап.
                if ($processorHoldPending -and $frameNumber -gt 106 -and $annotationState.ProcessorStartedAtMs -ge 0) {
                    $processorHoldPending = $false
                    $heldFrameNumber = 106
                    while ($true) {
                        Update-SkynetT800Annotation -FrameNumber $heldFrameNumber
                        $elapsed = $watch.ElapsedMilliseconds - $annotationState.ProcessorStartedAtMs
                        $ready = $annotationState.ProcessorDone -and
                            ($watch.ElapsedMilliseconds - $annotationState.ProcessorDoneShownAtMs) -ge 350
                        if ($ready) { break }
                        Update-SkynetT800ScanTitle
                        Update-SkynetMarquee
                        $waitMs = if ($annotationState.ProcessorDone) {
                            [Math]::Max(1, [Math]::Min(8, 350 - ($watch.ElapsedMilliseconds - $annotationState.ProcessorDoneShownAtMs)))
                        } else {
                            [Math]::Max(1, [Math]::Min(8, 1000 - $elapsed))
                        }
                        Start-Sleep -Milliseconds $waitMs
                    }
                }
            Show-SkynetSixelImage -Path $Paths[$i] -ChafaPath $ChafaPath `
                -TopRow $topRow -Col $sixelLeft -Width $sixelWidth -Height $sixelHeight `
                -ClearPrevious:$false
            $lastFrame = $i
            $frameNumber = [int]([regex]::Match([IO.Path]::GetFileNameWithoutExtension($Paths[$i]), '\d+').Value)
            Update-SkynetT800Annotation -FrameNumber $frameNumber
            $nextFrameNumber = if ($i + 1 -lt $Paths.Count) { [int]([regex]::Match([IO.Path]::GetFileNameWithoutExtension($Paths[$i + 1]), '\d+').Value) } else { 0 }
            if ($annotationState.ProcessorStartedAtMs -ge 0 -and $nextFrameNumber -gt 106 -and -not $annotationState.ProcessorDone) {
                $remaining = 1000 - ($watch.ElapsedMilliseconds - $annotationState.ProcessorStartedAtMs)
                if ($remaining -gt 0) { Start-Sleep -Milliseconds ([Math]::Min(8, $remaining)) }
            } elseif ($annotationState.ProcessorDone -and $annotationState.ProcessorDoneShownAtMs -ge 0 -and
                ($watch.ElapsedMilliseconds - $annotationState.ProcessorDoneShownAtMs) -lt 350) {
                Start-Sleep -Milliseconds 8
            }
            Update-SkynetT800ScanTitle
            Update-SkynetMarquee
            $until = $watch.ElapsedMilliseconds + $frameIntervalMs
            while ($watch.ElapsedMilliseconds -lt $until) {
                Update-SkynetT800ScanTitle
                Update-SkynetT800Annotation -FrameNumber $frameNumber
                Update-SkynetMarquee
                Start-Sleep -Milliseconds 8
            }
            }
        }
        # После последнего кадра закрепляем последнюю активную строку на экране.
        # До этого она могла закончить проход на выключенной фазе мигания.
        $annotationState.Complete = $true
        $annotationState.BlinkOn = $true
        $annotationState.NextBlinkAtMs = [int]::MaxValue
        $finalFrameNumber = [int]([regex]::Match([IO.Path]::GetFileNameWithoutExtension($Paths[-1]), '\d+').Value)
        Update-SkynetT800Annotation -FrameNumber $finalFrameNumber
        # Поток ТТХ раскрывается только после полного прохода и закрепления
        # FULL-BODY SCAN DONE. До этого момента панель остаётся пустой, поэтому
        # все строки зон сканирования всегда видны и не смешиваются с ТТХ.
        for ($j = 0; $j -lt $panelRows.Count; $j++) {
            $panelRows[$j].Progress = 1.0
            $panelRows[$j].Active = $true
            $line = Format-SkynetT800Row -Row $panelRows[$j] -Width $panelWidth
            [Console]::Out.Write("${esc}[$($panelTop + $j);2H$line$($GLOBAL:ColReset)")
        }
        $holdUntil = $watch.ElapsedMilliseconds + [Math]::Max(300, $Seconds * 50)
        while ($watch.ElapsedMilliseconds -lt $holdUntil) {
            Update-SkynetT800ScanTitle
            Update-SkynetMarquee
            Start-Sleep -Milliseconds 8
        }
        try { Write-SkynetLog -Message "T-800: Sixel-циклы завершены, показано $totalFrameCount/$totalFrameCount кадров." -Level 'INFO' -Module 'T800' } catch { }
    } finally {
        try {
            $clear = [System.Text.StringBuilder]::new()
            for ($row = $topRow; $row -lt ($topRow + $sixelHeight); $row++) {
                [void]$clear.Append("${esc}[${row};${sixelLeft}H$($GLOBAL:ColReset)${esc}[K")
            }
            [Console]::Out.Write($clear.ToString())
        } catch { }
    }
}


function Show-SkynetT800Scene {
    <#
    .SYNOPSIS
        Вторая сцена: ТТХ T-800 слева, вращающаяся голова справа.
    .PARAMETER FramesFolder
        Папка с пронумерованными кадрами настоящего вращения (1.png..N.png).
        Если задана и в ней есть хотя бы 2 картинки — используется она,
        параметр -Path и -SpinSteps в этом случае игнорируются (шагов
        ровно столько, сколько файлов).
    .PARAMETER Path
        Запасной вариант: один PNG со схемой/головой T-800 (имитация
        вращения сжатием+зеркалом), используется если FramesFolder не
        задан или в нём меньше 2 файлов.
    .PARAMETER Seconds
        Длительность сцены (по умолчанию 18 секунд).
    .PARAMETER SpinSeconds
        Время одного полного оборота головы.
    .PARAMETER SpinSteps
        Число кадров на оборот — только для режима -Path (одна картинка).
    .PARAMETER Title
        Заголовок сцены над панелью.
    .EXAMPLE
        Show-SkynetT800Scene -FramesFolder .\assets\t800_frames -Seconds 20 -SpinSeconds 4
    .EXAMPLE
        Show-SkynetT800Scene -Path .\assets\t800.png -Seconds 20 -SpinSeconds 4
    #>
    [CmdletBinding()]
    param(
        [string] $FramesFolder = '',
        [string] $Path = '',
        [int] $Seconds = 18,
        [double] $SpinSeconds = 4.0,
        [int] $SpinSteps = 16,
        [ValidateSet('Original', 'Green')][string] $ColorMode = 'Green',
        [int] $ThickenRadius = 2,
        [byte] $InkR = 40, [byte] $InkG = 255, [byte] $InkB = 90,
        [int] $FadeInMs = 900,
        [int] $FadeOutMs = 1200,
        [string] $Title = 'CYBERDYNE SYSTEMS :: UNIT IDENTIFICATION SCAN'
    )

    $cfg = $GLOBAL:_SkyNetCore

    # --- 0. Выбор источника: последовательность кадров или одна картинка ---
    $framePaths = @()
    $usingSequence = $false
    if ($FramesFolder) {
        $framePaths = Get-SkynetT800FramePaths -FolderPath $FramesFolder -NumericOnly
        if ($framePaths.Count -ge 2) {
            $usingSequence = $true
            try { Write-SkynetLog -Message "T-800: найдена последовательность кадров ($($framePaths.Count) файлов) в $FramesFolder." -Level 'INFO' -Module 'T800' } catch { }
        } else {
            try { Write-SkynetLog -Message "T-800: в папке кадров меньше 2 файлов ($FramesFolder) — пробую -Path." -Level 'WARN' -Module 'T800' } catch { }
        }
    }
    if (-not $usingSequence) {
        if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            try { Write-SkynetLog -Message "T-800: нет ни папки кадров, ни файла ($Path) — сцена пропущена." -Level 'WARN' -Module 'T800' } catch { }
            return
        }
    }
    if (-not $cfg.AnsiOk) { return }

    $esc = Get-SkyT800Esc
    $geo = Get-SkynetConsoleGeometry
    $topRow = 2
    $bottomReserve = 3                                   # бегущая строка + прогресс
    $rows = [Math]::Max(8, $geo.Height - $bottomReserve - $topRow)
    $panelWidth = [Math]::Max(34, [int]($geo.Width * 0.44))
    $headCol = $panelWidth + 4
    $headWidth = [Math]::Max(20, $geo.Width - $headCol - 2)

    # В Sixel-режиме основная T-800-сцена также использует исходные PNG напрямую.
    # Это важно для -NoPrologue и для любых будущих вызовов Show-SkynetT800Scene;
    # в обычном запуске эта сцена уже показана в прологе и не дублируется.
    $sixelChafa = [string](Get-SkynetChafaPath)
    if ($cfg.Sixel -and $usingSequence -and $framePaths.Count -gt 0 -and $sixelChafa -and
        (Get-Command Show-SkynetT800SixelSequence -ErrorAction SilentlyContinue)) {
        Show-SkynetT800SixelSequence -Paths $framePaths -Seconds $Seconds -SpinSeconds $SpinSeconds -Title $Title -ChafaPath $sixelChafa -FrameCycles 1 -FrameIntervalMs 8
        return
    }

    # --- 1. Кадры вращения (стройка один раз, потом кэш) --------------------
    Set-SkynetProgress -Percent 60 -Label 'RECONSTRUCTING T-800 MESH'
    $progressCb = {
        param($index, $total)
        $pct = 60 + [int](30.0 * ($index + 1) / $total)
        Set-SkynetProgress -Percent $pct -Label ('BUILDING SPIN FRAME {0}/{1}' -f ($index + 1), $total)
        Update-SkynetMarquee
    }
    if ($usingSequence) {
        if ($cfg.Instant) { $framePaths = @($framePaths[0]) }
        $frames = Build-SkynetT800SpinFramesFromImages -Paths $framePaths -Width $headWidth -Height $rows -ColorMode $ColorMode `
            -ThickenRadius $ThickenRadius -InkR $InkR -InkG $InkG -InkB $InkB -OnStep $progressCb
    } else {
        $spinSteps = if ($cfg.Instant) { 4 } else { $SpinSteps }
        $frames = Build-SkynetT800SpinFrames -Path $Path -Width $headWidth -Height $rows -Steps $spinSteps -ColorMode $ColorMode `
            -ThickenRadius $ThickenRadius -InkR $InkR -InkG $InkG -InkB $InkB -OnStep $progressCb
    }
    if (-not $frames -or $frames.Count -eq 0) {
        try { Write-SkynetLog -Message 'T-800: кадры не построены — сцена пропущена.' -Level 'ERROR' -Module 'T800' } catch { }
        return
    }
    Set-SkynetProgress -Percent 92 -Label 'T-800 TELEMETRY ONLINE'

    # --- 2. Чистый экран под сцену -----------------------------------------
    Clear-SkynetFrame -LineCount ($geo.Height - $bottomReserve) -TopRow 1
    Write-SkynetStatusLine -Text $Title -Row 1 -Color $GLOBAL:ColWarn

    # Аннотация выводится только в Sixel-ветке; обычный символьный кадр
    # оставляет панель на исходной строке.
    $panel = New-SkynetT800PanelState -Width $panelWidth
    $panelTop = $topRow + 1
    $panelRows = $panel.Rows
    $frameCache = @{}

    if ($cfg.Instant) {
        foreach ($row in $panelRows) { $row.Progress = 1.0 }
        for ($i = 0; $i -lt $panelRows.Count -and $i -lt $rows; $i++) {
            [Console]::Out.Write("${esc}[$($panelTop + $i);2H" + (Format-SkynetT800Row -Row $panelRows[$i] -Width $panelWidth))
        }
        Write-SkynetGlitchFrame -Lines $frames[0] -TopRow $topRow -BaseCol $headCol
        return
    }

    # --- 3. Основной цикл сцены ---------------------------------------------
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $totalMs = $Seconds * 1000
    $tickMs = 70
    $lastFrameIndex = -1
    $nextReveal = 0.0          # когда «раскодировать» следующую строку
    $revealIndex = 0
    $nextRefresh = 4000.0      # когда пересобрать случайную телеметрию
    $nextGlitch = (Get-Random -Minimum 1500 -Maximum 3200)

    while ($watch.ElapsedMilliseconds -lt $totalMs) {
        $now = [double] $watch.ElapsedMilliseconds

        # Яркость сцены: проявление в начале, растворение в конце.
        $factor = 1.0
        if ($now -lt $FadeInMs) { $factor = [Math]::Pow($now / [double] $FadeInMs, 0.85) }
        elseif ($now -gt ($totalMs - $FadeOutMs)) { $factor = [Math]::Pow([Math]::Max(0.0, ($totalMs - $now) / [double] $FadeOutMs), 1.25) }
        if ($factor -gt 1.0) { $factor = 1.0 }

        # --- голова: кадр по времени -----------------------------------------
        $phase = ($now / 1000.0) / $SpinSeconds
        $frameIndex = [int][Math]::Floor($phase * $frames.Count) % $frames.Count
        if ($frameIndex -lt 0) { $frameIndex += $frames.Count }
        if ($frameIndex -ne $lastFrameIndex -or $factor -lt 0.999) {
            Write-SkynetGlitchFrame -Lines $frames[$frameIndex] -TopRow $topRow -BaseCol $headCol -Factor $factor -Cache $frameCache
            $lastFrameIndex = $frameIndex
        }

        # --- панель ТТХ: раскодирование строк по очереди ----------------------
        if ($revealIndex -lt $panelRows.Count -and $now -ge $nextReveal) {
            $panelRows[$revealIndex].Active = $true
            $panelRows[$revealIndex].Dirty = $true
            $revealIndex++
            $nextReveal = $now + (Get-Random -Minimum 110 -Maximum 260)
        }

        # --- периодическая пересборка живой телеметрии ------------------------
        if ($now -ge $nextRefresh) {
            $candidates = @()
            for ($i = 0; $i -lt $panelRows.Count; $i++) { if ($panelRows[$i].Gen) { $candidates += $i } }
            if ($candidates.Count -gt 0) {
                $pick = $candidates[(Get-Random -Minimum 0 -Maximum $candidates.Count)]
                $panelRows[$pick].Value = [string] (& $panelRows[$pick].Gen)
                $panelRows[$pick].Progress = 0.0
                $panelRows[$pick].Dirty = $true
            }
            $nextRefresh = $now + (Get-Random -Minimum 900 -Maximum 2200)
        }

        for ($i = 0; $i -lt $panelRows.Count -and $i -lt $rows; $i++) {
            $row = $panelRows[$i]
            if (-not $row.Active) { continue }
            if ([double] $row.Progress -lt 1.0) {
                $row.Progress = [Math]::Min(1.0, [double] $row.Progress + 0.18)
                $row.Dirty = $true
            }
            if (-not $row.Dirty) { continue }
            $line = Format-SkynetT800Row -Row $row -Width $panelWidth
            if ($factor -lt 0.999) { $line = ConvertTo-SkynetDimmedAnsi -Text $line -Factor $factor }
            [Console]::Out.Write("${esc}[$($panelTop + $i);2H$line$($GLOBAL:ColReset)${esc}[K")
            if ([double] $row.Progress -ge 1.0) { $row.Dirty = $false }
        }

        # --- глитчи и бегущая строка ------------------------------------------
        if ($now -ge $nextGlitch -and $factor -gt 0.5) {
            switch (Get-Random -Minimum 0 -Maximum 3) {
                0 { Start-SkynetMicroFreeze }
                1 { Invoke-SkynetFrameGlitch -Lines $frames[$frameIndex] -TopRow $topRow -BaseCol $headCol -Factor $factor -Frames 2 -Cache $frameCache }
                default {
                    Invoke-SkynetFrameGlitch -Lines $frames[$frameIndex] -TopRow $topRow -BaseCol $headCol -Factor $factor -Frames 2 -Band -Cache $frameCache
                    Start-SkynetMicroFreeze -Hard
                    foreach ($row in $panelRows) { if ($row.Active) { $row.Dirty = $true } }
                }
            }
            $nextGlitch = $now + (Get-Random -Minimum 1400 -Maximum 3600)
        }

        Update-SkynetMarquee
        $spent = [double] $watch.ElapsedMilliseconds - $now
        $rest = $tickMs - [int] $spent
        if ($rest -gt 0) { Start-Sleep -Milliseconds $rest }
    }

    Clear-SkynetFrame -LineCount ($geo.Height - $bottomReserve) -TopRow 1
}

$script:T800Exports = @(
    'Get-SkynetT800Specs', 'ConvertTo-SkynetMirroredLine', 'Get-SkynetStretchedFrame',
    'Set-SkynetFrameBox', 'Build-SkynetT800SpinFrames', 'Get-SkynetT800FramePaths',
    'Build-SkynetT800SpinFramesFromImages', 'Get-SkynetScrambledText',
    'Test-SkynetNeedsThickening', 'Get-SkynetThickenedFramePath', 'Resolve-SkynetFramePaths',
    'New-SkynetT800PanelState', 'Format-SkynetT800Row', 'Get-SkynetT800ScanStages',
    'Get-SkynetT800ScanStage', 'Get-SkynetT800ScanAnnotation', 'Write-SkynetT800ScanRow',
    'Show-SkynetT800SixelSequence', 'Show-SkynetT800Scene'
)
Export-ModuleMember -Function $script:T800Exports
