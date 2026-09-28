<#
.SYNOPSIS
    SkyNet Render — поиск логотипа и построение кадра логотипа.

.DESCRIPTION
    Кадр логотипа — только для символьного режима. При -Sixel функция
    возвращает Source='sixel' и пустой Lines, не вызывая ни Chafa в режиме
    symbols, ни встроенный рендерер; прямой вывод выполняет
    Show-SkynetSixelLogo.
#>

function Get-SkynetChafaPath {
    <#
    .SYNOPSIS
        Найти исполняемый файл chafa.
    .DESCRIPTION
        Порядок поиска:
          1) явный путь из config/skynet.json (Render.ChafaPath);
          2) chafa из PATH;
          3) Chafa.exe в корне проекта (bundled, 13 MB);
          4) Chafa.exe в Modules;
          5) пакет из winget/WindowsApps.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $cfg = $GLOBAL:_SkyNetCore
    if ($cfg.ChafaPath -and (Test-Path -LiteralPath $cfg.ChafaPath -PathType Leaf)) { return $cfg.ChafaPath }

    $candidates = New-Object System.Collections.Generic.List[string]
    $fromPath = Get-Command chafa -CommandType Application -ErrorAction SilentlyContinue
    if ($fromPath) { $candidates.Add($fromPath.Source) }

    $root = Get-SkynetProjectRoot
    if ($root) {
        $candidates.Add((Join-Path $root 'Chafa.exe'))
        $candidates.Add((Join-Path $root 'Modules\Chafa.exe'))
        $candidates.Add((Join-Path $root 'Tools\Chafa.exe'))
    }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\chafa.exe'))
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\chafa.exe'))
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function Resolve-LogoPath {
    <#
    .SYNOPSIS
        Найти оригинальный файл логотипа проекта.
    .DESCRIPTION
        Оригинал логотипа живёт в корне проекта (по умолчанию skynet_logo.png)
        и никогда не перезаписывается генераторами (см. Tools/generate_logo.ps1).
        Порядок поиска:
          1) явный -Explicit;
          2) <корень проекта>\<DefaultLogo из конфига>;
          3) skynet_logo.* в корне проекта (крупные файлы раньше мелких);
          4) то же в Modules;
          5) «внешние» каталоги (OneDrive/Desktop) — только как последний шанс:
             там исторически лежали сгенерированные обрезки на пару килобайт.
        Возвращает путь или $null (без исключений — вызывающая сторона решает).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Explicit, [switch] $Verbose_)

    if ($Explicit) {
        if (Test-Path -LiteralPath $Explicit -PathType Leaf) { return (Resolve-Path -LiteralPath $Explicit).Path }
        Write-SkynetLog -Message "Логотип по явному пути не найден: $Explicit" -Level 'WARN' -Module 'Render'
        return $null
    }

    $cfg = $GLOBAL:_SkyNetCore
    $root = Get-SkynetProjectRoot
    $extensions = @('png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp')

    # 1-2. Конфиг DefaultLogo + корень проекта + assets\.
    $primary = New-Object System.Collections.Generic.List[string]
    if ($cfg.DefaultLogo) {
        if ($root) {
            $primary.Add((Join-Path $root $cfg.DefaultLogo))
            $primary.Add((Join-Path (Join-Path $root 'assets') $cfg.DefaultLogo))
        }
        $primary.Add((Join-Path $cfg.ModulesPath $cfg.DefaultLogo))
    }
    foreach ($path in $primary) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return (Resolve-Path -LiteralPath $path).Path }
    }

    # 3-4. Любой skynet_logo.* в проекте (корень, assets, Modules).
    $localDirs = @($root, (Join-Path $root 'assets'), $cfg.ModulesPath) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    $localCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $localDirs) {
        foreach ($ext in $extensions) { $localCandidates.Add((Join-Path $dir "skynet_logo.$ext")) }
    }

    # 5. Внешние каталоги — в самом конце.
    $outerDirs = @(
        (Join-Path $HOME 'OneDrive\Desktop\SkyNet'),
        (Join-Path $HOME 'Desktop\SkyNet'),
        (Join-Path $HOME 'OneDrive\Desktop'),
        (Join-Path $HOME 'Desktop')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    foreach ($dir in $outerDirs) {
        foreach ($ext in $extensions) { $localCandidates.Add((Join-Path $dir "skynet_logo.$ext")) }
    }

    $good = New-Object System.Collections.Generic.List[string]
    $small = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in $localCandidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $info = Test-SkynetLogoFile -Path $candidate
        if (-not $info.Ok) {
            Write-SkynetLog -Message "Кандидат в логотипы отклонён ($($info.Reason)): $candidate" -Level 'DEBUG' -Module 'Render'
            continue
        }
        if ($info.Small) { $small.Add($candidate) } else { $good.Add($candidate) }
    }

    if ($good.Count -gt 0) { return (Resolve-Path -LiteralPath $good[0]).Path }
    if ($small.Count -gt 0) {
        Write-SkynetLog -Message "Найдены только мелкие (< $($cfg.LogoMinBytes) байт) файлы логотипа: $($small[0])" -Level 'WARN' -Module 'Render'
        return (Resolve-Path -LiteralPath $small[0]).Path
    }

    Write-SkynetLog -Message "Логотип не найден ни в одной из стандартных локаций." -Level 'ERROR' -Module 'Render'
    return $null
}
function Test-SkynetChafa {
    <#
    .SYNOPSIS
        Проверка доступности chafa (совместимость со старой версией API).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $path = Get-SkynetChafaPath
    if ($path) { return @{ Found = $true; Path = $path } }
    return @{ Found = $false; Path = $null }
}

function Get-SkynetGreenRgb {
    <#
    .SYNOPSIS
        Яркость (0..255) → RGB зелёного фосфора.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([int] $Intensity)

    if ($Intensity -le 0) { return '0;0;0' }
    $t = [Math]::Min(1.0, $Intensity / 255.0)
    $r = [int][Math]::Round(90 * [Math]::Pow($t, 2.6))
    $g = [int][Math]::Round(255 * [Math]::Pow($t, 1.25))
    $b = [int][Math]::Round(120 * [Math]::Pow($t, 2.6))
    return "$r;$g;$b"
}

function Get-SkynetBuiltInFrame {
    <#
    .SYNOPSIS
        Встроенный truecolor-рендерер логотипа.
    .DESCRIPTION
        Режимы Charset:
          Block   — половина блока ▀: 1 пиксель на колонку, 2 на знакоместо;
          Braille — брайль (U+2800..): 2x4 субпикселя на знак (в 4 раза плотнее);
          Ascii   — символьная рампа по яркости.
        Пиксели читаются через LockBits (один memcpy вместо тысяч GetPixel).
        Возвращает массив строк шириной ровно Width знакомест.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [int] $Width = 160,
        [int] $Height = 50,
        [ValidateSet('Original', 'Green')][string] $ColorMode = 'Original',
        [ValidateSet('Block', 'Ascii', 'Braille')][string] $CharSet = 'Block'
    )

    if (-not ('System.Drawing.Image' -as [type])) { Add-Type -AssemblyName System.Drawing }

    $esc = Get-SkynetEsc
    $brailleMode = ($CharSet -eq 'Braille')
    $asciiMode = ($CharSet -eq 'Ascii')
    $subW = if ($brailleMode) { 2 } else { 1 }
    $subH = if ($brailleMode) { 4 } else { 2 }
    $pixelWidth = $Width * $subW
    $pixelHeight = $Height * $subH
    $threshold = 24
    $ramp = ' .:-=+*#%@'

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $stream = [System.IO.MemoryStream]::new($bytes)
    try {
        $source = [System.Drawing.Image]::FromStream($stream)
        try {
            $bmp = [System.Drawing.Bitmap]::new($pixelWidth, $pixelHeight)
            try {
                $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                try {
                    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $gfx.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                    $gfx.Clear([System.Drawing.Color]::Black)

                    $scale = [Math]::Min($pixelWidth / [double] $source.Width, $pixelHeight / [double] $source.Height)
                    $drawWidth = [Math]::Min($pixelWidth, [int][Math]::Round($source.Width * $scale))
                    $drawHeight = [Math]::Min($pixelHeight, [int][Math]::Round($source.Height * $scale))
                    $offsetX = [int](($pixelWidth - $drawWidth) / 2)
                    $offsetY = [int](($pixelHeight - $drawHeight) / 2)
                    $gfx.DrawImage($source, $offsetX, $offsetY, $drawWidth, $drawHeight)
                } finally { $gfx.Dispose() }

                # Один memcpy вместо тысяч GetPixel — иначе крупный кадр рендерится минуты.
                $bounds = [System.Drawing.Rectangle]::new(0, 0, $pixelWidth, $pixelHeight)
                $bits = $bmp.LockBits($bounds, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
                try {
                    $buffer = [byte[]]::new([int] $bits.Stride * $pixelHeight)
                    [System.Runtime.InteropServices.Marshal]::Copy($bits.Scan0, $buffer, 0, $buffer.Length)
                } finally { $bmp.UnlockBits($bits) }
                $stride = [int] $bits.Stride
            } finally { $bmp.Dispose() }
        } finally { $source.Dispose() }
    } finally { $stream.Dispose() }
    $lines = New-Object System.Collections.Generic.List[string]
    $brailleBits = @(@([int] 0x01, [int] 0x08), @([int] 0x02, [int] 0x10), @([int] 0x04, [int] 0x20), @([int] 0x40, [int] 0x80))

    for ($cellRow = 0; $cellRow -lt $Height; $cellRow++) {
        $line = [System.Text.StringBuilder]::new()

        for ($x = 0; $x -lt $Width; $x++) {
            if ($brailleMode) {
                # 2x4 субпикселя на знак; цвет ячейки — среднее по «горящим» точкам.
                $code = [int] 0
                $sumR = [int] 0; $sumG = [int] 0; $sumB = [int] 0; $onCount = [int] 0
                $sumLum = [int] 0
                for ($dy = 0; $dy -lt 4; $dy++) {
                    $py = $cellRow * 4 + $dy
                    $rowOffset = $py * $stride
                    for ($dx = 0; $dx -lt 2; $dx++) {
                        $px = $x * 2 + $dx
                        $idx = $rowOffset + $px * 4
                        $b = $buffer[$idx]; $g = $buffer[$idx + 1]; $r = $buffer[$idx + 2]
                        $lum = [int](($r * 0.299) + ($g * 0.587) + ($b * 0.114))
                        if ($lum -ge $threshold) {
                            $code += $brailleBits[$dy][$dx]
                            $sumR += $r; $sumG += $g; $sumB += $b; $sumLum += $lum; $onCount++
                        }
                    }
                }
                if ($code -eq 0) { [void] $line.Append("$($esc)[0m "); continue }
                $avgR = [int][Math]::Round($sumR / [double] $onCount)
                $avgG = [int][Math]::Round($sumG / [double] $onCount)
                $avgB = [int][Math]::Round($sumB / [double] $onCount)
                $rgb = if ($ColorMode -eq 'Green') { Get-SkynetGreenRgb -Intensity ([int]($sumLum / $onCount)) } else { "$avgR;$avgG;$avgB" }
                [void] $line.Append("$($esc)[38;2;${rgb}m$([char](0x2800 + $code))")
            }
            else {
                $py = $cellRow * 2
                $idxTop = ($py * $stride) + ($x * 4)
                $idxBottom = (([Math]::Min($py + 1, $pixelHeight - 1)) * $stride) + ($x * 4)
                $tB = $buffer[$idxTop]; $tG = $buffer[$idxTop + 1]; $tR = $buffer[$idxTop + 2]
                $bB = $buffer[$idxBottom]; $bG = $buffer[$idxBottom + 1]; $bR = $buffer[$idxBottom + 2]
                $tLum = [int](($tR * 0.299) + ($tG * 0.587) + ($tB * 0.114))
                $bLum = [int](($bR * 0.299) + ($bG * 0.587) + ($bB * 0.114))

                if ($asciiMode) {
                    $level = [Math]::Min(9, [Math]::Max(0, [int][Math]::Round($tLum / 25.5)))
                    if ($level -eq 0) { [void] $line.Append(' '); continue }
                    $rgb = if ($ColorMode -eq 'Green') { Get-SkynetGreenRgb -Intensity ([int]($level * 25.5)) } else { "$tR;$tG;$tB" }
                    [void] $line.Append("$($esc)[38;2;${rgb}m$($ramp[$level])")
                }
                else {
                    if ($tLum -lt $threshold -and $bLum -lt $threshold) { [void] $line.Append("$($esc)[0m "); continue }
                    $topRgb = if ($ColorMode -eq 'Green') { Get-SkynetGreenRgb -Intensity $tLum } else { "$tR;$tG;$tB" }
                    $bottomRgb = if ($ColorMode -eq 'Green') { Get-SkynetGreenRgb -Intensity $bLum } else { "$bR;$bG;$bB" }
                    [void] $line.Append("$($esc)[38;2;${topRgb}m$($esc)[48;2;${bottomRgb}m▀")
                }
            }
        }
        [void] $line.Append("$($esc)[0m")
        $lines.Add($line.ToString())
    }
    return $lines.ToArray()
}

function Get-SkynetVisibleLength {
    <#
    .SYNOPSIS
        Длина строки без ANSI-последовательностей.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([string] $Text = '')
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    return ([regex]::Replace($Text, '\x1b\[[0-9;?]*[a-zA-Z]', '')).Length
}

function Repair-SkynetChafaLine {
    <#
    .SYNOPSIS
        Убрать reverse-video (ESC[7m) из строки chafa, не потеряв цвет ячейки.
    .DESCRIPTION
        Для «пустых» ячеек (пустой брайль / пробел) chafa пишет
        ESC[7m ESC[38;2;R;G;B m <глиф>: цвет R;G;B задан как fg + реверс, то есть
        по факту это ЗАЛИВКА ячейки цветом R;G;B. Простое удаление ESC[7m (как было
        раньше) превращало такие ячейки в чёрные дыры — так «прорезались» буквы SKYNET
        и терялась заливка красных полос. Здесь реверс раскрывается явно:
        fg становится чёрным, а цвет уходит в bg.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Line = '')
    $esc = [string][char]27
    # reverse + fg + bg  → меняем местами
    $Line = [regex]::Replace($Line, '\x1b\[7m\x1b\[38;2;(\d+);(\d+);(\d+);48;2;(\d+);(\d+);(\d+)m', ($esc + '[38;2;${4};${5};${6};48;2;${1};${2};${3}m'))
    # reverse + только fg → цвет уходит в фон, глиф рисуется чёрным
    $Line = [regex]::Replace($Line, '\x1b\[7m\x1b\[38;2;(\d+);(\d+);(\d+)m', ($esc + '[38;2;0;0;0;48;2;${1};${2};${3}m'))
    # остатки (реверс без явного цвета) — как раньше, просто убираем
    $Line = $Line.Replace($esc + '[7m', '')
    # chafa склеивает fg и bg в ОДНУ последовательность 38;2;..;48;2;..m. Fade
    # (ConvertTo-SkynetDimmedAnsi) и зелёный режим ищут 38/48 по отдельности и такие
    # ячейки не затемняли — логотип не гас плавно, а часть ячеек «горела» до конца.
    # Разделяем на две обычные последовательности.
    return [regex]::Replace($Line, '\x1b\[38;2;(\d+);(\d+);(\d+);48;2;(\d+);(\d+);(\d+)m', ($esc + '[38;2;${1};${2};${3}m' + $esc + '[48;2;${4};${5};${6}m'))
}

function Get-SkynetChafaFrame {
    <#
    .SYNOPSIS
        Кадр логотипа через chafa (truecolor, символы-блоки).
    .DESCRIPTION
        Вывод chafa чистится от управляющих последовательностей, которые ломают
        нашу кадровую отрисовку (?25l, ?7l, reverse-video) и центрируется
        по ширине окна. Если chafa выдал строку шире запрошенной — возвращается
        $null, и вызывающий код уходит на встроенный рендерер.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $ChafaPath,
        [int] $Width = 160,
        [int] $Height = 50,
        [double] $FontRatio = 0,
        [string] $Symbols = 'block+border+space'
    )

    $chafaArgs = New-Object System.Collections.Generic.List[string]
    $chafaArgs.Add('--format=symbols')
    if (-not $Symbols) { $Symbols = 'block+border+space' }
    $chafaArgs.Add("--symbols=$Symbols")
    $chafaArgs.Add('--color-space=din99d')
    $chafaArgs.Add('-c')
    $chafaArgs.Add('full')
    # Максимум качества: -w 9 (полный перебор символов), без дитеринга (на плоских
    # красных полосах он даёт «песок»), -O 0 — chafa не «склеивает» близкие цвета
    # соседних ячеек ради экономии escape-кодов (это давало ступеньки в градиентах).
    $chafaArgs.Add('-w'); $chafaArgs.Add('9')
    $chafaArgs.Add('--dither=none')
    $chafaArgs.Add('-O'); $chafaArgs.Add('0')
    $chafaArgs.Add("--size=${Width}x${Height}")
    # Не форсируем --exact-size. У Chafa 1.18 параметр требует явного значения
    # (например, --exact-size=on); прежний --exact-size без значения завершался
    # ошибкой, после чего Get-SkynetLogoFrame незаметно уходил в грубый встроенный
    # растр. Обычный --size сохраняет естественные пропорции исходного PNG.
    if ($FontRatio -gt 0.1 -and $FontRatio -lt 1.0) { $chafaArgs.Add(('--font-ratio={0}' -f [Math]::Round($FontRatio, 3))) }
    $chafaArgs.Add($Path)

    # ОБЯЗАТЕЛЬНО: chafa печатает UTF-8 (рамки, блоки). Если консоль декодирует
    # вывод в OEM-кодировке (cp866), псевдографика превращается в кириллический
    # мусор и ширина строки «распухает» в 2-3 раза. Поэтому явно задаём UTF-8
    # на время вызова и возвращаем прежнюю кодировку после.
    $savedOutputEncoding = $null
    try { $savedOutputEncoding = [Console]::OutputEncoding } catch { }
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

    try {
        $raw = & $ChafaPath @chafaArgs 2>$null
        $exit = $LASTEXITCODE
    } finally {
        if ($savedOutputEncoding) { try { [Console]::OutputEncoding = $savedOutputEncoding } catch { } }
    }

    if ($exit -ne 0 -or -not $raw) {
        Write-SkynetLog -Message "chafa завершился с кодом $exit" -Level 'WARN' -Module 'Render'
        return $null
    }

    # Каждый элемент массива содержит ESC-последовательности только без Ctrl+C; остальное чистим.
    $cleaned = New-Object System.Collections.Generic.List[string]
    $maxVisible = 0
    foreach ($line in $raw) {
        $clean = [string] $line
        $clean = $clean.Replace([string][char]27 + '[?25l', '').Replace([string][char]27 + '[?25h', '')
        $clean = $clean.Replace([string][char]27 + '[?7l', '').Replace([string][char]27 + '[?7h', '')
        $clean = Repair-SkynetChafaLine -Line $clean
        $clean = $clean.Replace("`r", '')
        $clean = $clean.TrimEnd()
        $visible = Get-SkynetVisibleLength -Text $clean
        if ($visible -le 0) { continue }
        if ($visible -gt $Width) {
            Write-SkynetLog -Message "chafa вернул строку шире $Width колонок ($visible) — используем встроенный рендерер." -Level 'WARN' -Module 'Render'
            return $null
        }
        if ($visible -gt $maxVisible) { $maxVisible = $visible }
        $cleaned.Add($clean)
    }
    if ($cleaned.Count -eq 0) { return $null }

    # Центрируем кадр целиком (одинаковый сдвиг для всех строк — картинка не плывёт).
    $offset = [int](($Width - $maxVisible) / 2)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($clean in $cleaned) {
        if ($offset -gt 0) { $clean = (' ' * $offset) + $clean }
        $lines.Add($clean)
    }
    return $lines.ToArray()
}


function ConvertTo-SkynetGreenFrame {
    <#
    .SYNOPSIS
        Перевести кадр в зелёный фосфор (цвет по яркости пикселя).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([AllowEmptyCollection()][string[]] $Lines = @())

    $fgPattern = '\x1b\[38;2;(?<r>\d+);(?<g>\d+);(?<b>\d+)m'
    $bgPattern = '\x1b\[48;2;(?<r>\d+);(?<g>\d+);(?<b>\d+)m'
    $combined = '\x1b\[38;2;(?<r>\d+);(?<g>\d+);(?<b>\d+);48;2;(?<r2>\d+);(?<g2>\d+);(?<b2>\d+)m'
    $result = New-Object System.Collections.Generic.List[string]
    $esc = [string][char]27
    foreach ($line in $Lines) {
        # fg+bg в одной последовательности (её выдаёт Repair-SkynetChafaLine и chafa)
        $green = [regex]::Replace($line, $combined, {
                param($match)
                $lf = [int](([int] $match.Groups['r'].Value * 0.299) + ([int] $match.Groups['g'].Value * 0.587) + ([int] $match.Groups['b'].Value * 0.114))
                $lb = [int](([int] $match.Groups['r2'].Value * 0.299) + ([int] $match.Groups['g2'].Value * 0.587) + ([int] $match.Groups['b2'].Value * 0.114))
                return $esc + '[38;2;' + (Get-SkynetGreenRgb -Intensity $lf) + ';48;2;' + (Get-SkynetGreenRgb -Intensity $lb) + 'm'
            })
        $green = [regex]::Replace($green, $fgPattern, {
                param($match)
                $lum = [int](([int] $match.Groups['r'].Value * 0.299) + ([int] $match.Groups['g'].Value * 0.587) + ([int] $match.Groups['b'].Value * 0.114))
                return $esc + '[38;2;' + (Get-SkynetGreenRgb -Intensity $lum) + 'm'
            })
        # Фон тоже красим по яркости (раньше гасился в чёрный — теперь так нельзя:
        # сплошные ячейки хранятся именно в bg).
        $green = [regex]::Replace($green, $bgPattern, {
                param($match)
                $lum = [int](([int] $match.Groups['r'].Value * 0.299) + ([int] $match.Groups['g'].Value * 0.587) + ([int] $match.Groups['b'].Value * 0.114))
                return $esc + '[48;2;' + (Get-SkynetGreenRgb -Intensity $lum) + 'm'
            })
        $result.Add($green)
    }
    return $result.ToArray()
}
function Get-SkynetLogoFrame {
    <#
    .SYNOPSIS
        Построить кадр логотипа для анимации.
    .DESCRIPTION
        В символьном режиме пытается отрисовать логотип через chafa, при любой
        неудаче — встроенным рендерером. При -Sixel возвращает только
        Source = 'sixel' и пустой Lines: символьный кадр вообще не строится.
        Вывод выполняет Show-SkynetSixelLogo напрямую в stdout терминала.
    .OUTPUTS
        Hashtable: Lines, Source, Width, Height, Chafa, Path.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [int] $Width = 160,
        [int] $Height = 50,
        [ValidateSet('Original', 'Green')][string] $ColorMode = 'Original',
        [ValidateSet('Block', 'Ascii', 'Braille')][string] $CharSet = 'Block',
        [double] $FontRatio = 0,
        [switch] $Sixel,
        [switch] $NoChafa
    )

    $chafa = if ($NoChafa) { $null } else { Get-SkynetChafaPath }
    $frame = @{ Lines = @(); Source = 'built-in'; Width = $Width; Height = $Height; Chafa = $chafa; Path = $Path; CharSet = $CharSet }

    # В Sixel-режиме не выбираем и не строим символьный кадр вообще.
    if ($Sixel) {
        if (-not $chafa) { throw 'Режим -Sixel требует chafa, но он не найден.' }
        $frame.Source = 'sixel'
        return $frame
    }

    # Режим символов chafa подбирается под набор знаков кадра.
    # Block (по умолчанию): блоки+пробел — сплошная заливка, красные полосы и буквы
    # без «точечных» артефактов (шрифт Windows Terminal рисует брайль КРУГЛЫМИ ТОЧКАМИ,
    # из-за чего заливка выглядит пунктиром). Braille — только по явному -Charset Braille.
    $symbols = switch ($CharSet) {
        'Braille' { 'braille+block+space' }
        'Ascii' { 'ascii+space' }
        default { 'block+space' }
    }

    if ($chafa) {
        try {
            $lines = Get-SkynetChafaFrame -Path $Path -ChafaPath $chafa -Width $Width -Height $Height -FontRatio $FontRatio -Symbols $symbols
            if ($lines -and $lines.Count -gt 0) {
                $frame.Lines = $lines
                $frame.Source = 'chafa'
                $frame.Height = $lines.Count
                if ($ColorMode -eq 'Green') { $frame.Lines = ConvertTo-SkynetGreenFrame -Lines $frame.Lines }
                return $frame
            }
        } catch {
            Write-SkynetLog -Message "chafa не сработал: $($_.Exception.Message)" -Level 'WARN' -Module 'Render'
        }
    } else {
        Write-SkynetLog -Message 'chafa не найден — встроенный truecolor-рендерер.' -Level 'INFO' -Module 'Render'
    }

    $builtIn = Get-SkynetBuiltInFrame -Path $Path -Width $Width -Height $Height -ColorMode $ColorMode -CharSet $CharSet
    $frame.Lines = $builtIn
    $frame.Source = 'built-in'
    $frame.Height = $builtIn.Count
    return $frame
}

function Show-SkynetSixelImage {
    <#
    .SYNOPSIS
        Вывести один PNG как настоящий Sixel-кадр в заданную область терминала.
    .DESCRIPTION
        Это отдельный путь для покадровой графики T-800. Chafa вызывается напрямую,
        его stdout не перехватывается и не очищается регулярными выражениями.
        При -ClearPrevious заполняется только правая область экрана; левая панель ТТХ
        не затрагивается. В основном цикле очистка отключена, чтобы Sixel-кадры
        не мигали. Размер Chafa задаётся в знакоместах, а --view-size и
        --font-ratio фиксируют одинаковую геометрию для всех кадров последовательности.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $ChafaPath,
        [int] $TopRow = 1,
        [int] $Col = 1,
        [int] $Width = 60,
        [int] $Height = 30,
        [switch] $ClearPrevious
    )

    if ($Width -lt 1 -or $Height -lt 1) { throw 'Sixel: недопустимый размер кадра.' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Sixel: файл не найден: $Path" }
    if (-not (Test-Path -LiteralPath $ChafaPath -PathType Leaf)) { throw "Sixel: chafa не найден: $ChafaPath" }

    $esc = Get-SkynetEsc
    $reset = [string] $GLOBAL:ColReset
    $safeTop = [Math]::Max(1, $TopRow)
    $safeCol = [Math]::Max(1, $Col)

    if ($ClearPrevious) {
        # Sixel занимает графический слой терминала. Чёрные пробелы в его
        # прямоугольнике убирают старый кадр, но не затирают левую панель.
        $blank = (' ' * $Width)
        $clear = [System.Text.StringBuilder]::new()
        for ($row = $safeTop; $row -lt ($safeTop + $Height); $row++) {
            [void]$clear.Append("${esc}[${row};${safeCol}H${esc}[40m${reset}${blank}${esc}[K")
        }
        [Console]::Out.Write($clear.ToString())
    }

    # Никакого перенаправления/захвата stdout: Windows Terminal получает
    # настоящие Sixel-последовательности напрямую от Chafa.
    [Console]::Out.Write("${esc}[${safeTop};${safeCol}H${esc}[?25l")
    $chafaArgs = @(
        '--format=sixel',
        "--size=${Width}x${Height}",
        "--view-size=${Width}x${Height}",
        '--align=top,left',
        '--font-ratio=1/2',
        '--dither=none',
        '-c', 'full', $Path
    )
    & $ChafaPath @chafaArgs
    if ($LASTEXITCODE -ne 0) { throw "Sixel: chafa завершился с кодом $LASTEXITCODE ($Path)." }
    [Console]::Out.Write("${esc}[?25l")
}


function Show-SkynetSixelLogo {
    <#
    .SYNOPSIS
        Показать логотип в пиксельном режиме (chafa sixel) без покадрового fade.
    .DESCRIPTION
        Прямой вызов Chafa без перенаправления stdout. Sixel-последовательности
        должны попасть прямо в Windows Terminal, который сам рисует пиксели.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $ChafaPath,
        [int] $Width = 160,
        [int] $Height = 50,
        [int] $TopRow = 0,
        [int] $Col = 0
    )
    if ($Width -lt 1 -or $Height -lt 1) { throw 'Sixel: недопустимый размер кадра.' }
    if ($TopRow -gt 0 -or $Col -gt 0) {
        $esc = Get-SkynetEsc
        $safeRow = [Math]::Max(1, $TopRow)
        $safeCol = [Math]::Max(1, $Col)
        [Console]::Out.Write("${esc}[${safeRow};${safeCol}H")
    }
    $chafaArgs = @('--format=sixel', "--size=${Width}x${Height}", '-c', 'full', $Path)
    & $ChafaPath @chafaArgs
    if ($LASTEXITCODE -ne 0) { throw "Sixel: chafa завершился с кодом $LASTEXITCODE." }
}

function Start-SkynetRender {
    <#
    .SYNOPSIS
        Совместимость: отрисовать логотип сразу (без анимации).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [int] $Width = 160,
        [int] $Height = 50,
        [ValidateSet('Original', 'Green')][string] $ColorMode = 'Original',
        [ValidateSet('Block', 'Ascii', 'Braille')][string] $CharSet = 'Block',
        [switch] $CineSize,
        [switch] $Sixel
    )

    $fontRatio = 0
    if ($CineSize) {
        $cell = Get-SkynetCellSize
        if ($cell -and $cell.Width -gt 0 -and $cell.Height -gt 0) { $fontRatio = [Math]::Round($cell.Width / [double] $cell.Height, 3) }
    }

    $frame = Get-SkynetLogoFrame -Path $Path -Width $Width -Height $Height -ColorMode $ColorMode -CharSet $CharSet -FontRatio $fontRatio -Sixel:$Sixel
    if ($frame.Source -eq 'sixel') {
        Show-SkynetSixelLogo -Path $Path -ChafaPath $frame.Chafa -Width $Width -Height $Height
        return $frame
    }

    $lines = $frame.Lines
    if (Get-Command Write-SkynetFrame -ErrorAction SilentlyContinue) {
        Write-SkynetFrame -Lines $lines -TopRow 1
    } else {
        [Console]::Out.Write(($lines -join [Environment]::NewLine))
        [Console]::Out.Write([Environment]::NewLine)
    }
    return $frame
}

$script:RenderExports = @(
    'Get-SkynetChafaPath', 'Test-SkynetChafa', 'Resolve-LogoPath', 'Get-SkynetGreenRgb',
    'Get-SkynetBuiltInFrame', 'Get-SkynetChafaFrame', 'Repair-SkynetChafaLine', 'ConvertTo-SkynetGreenFrame',
    'Get-SkynetLogoFrame', 'Show-SkynetSixelImage', 'Show-SkynetSixelLogo', 'Start-SkynetRender', 'Get-SkynetVisibleLength'
)
Export-ModuleMember -Function $script:RenderExports
