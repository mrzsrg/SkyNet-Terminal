<#
.SYNOPSIS
    SkyNet Anim — анимация: бегущая строка, проявление и растворение логотипа.

.DESCRIPTION
    Модуль кадровой анимации Skynet:
    - бегущая строка (marquee) с яркой «зоной сканирования» внизу экрана;
    - прогресс-бар загрузки;
    - покадровое проявление логотипа (fade-in);
    - удержание кадра (HoldSeconds, по умолчанию 2 секунды);
    - постепенное растворение логотипа в темноте терминала (fade-out);
    - единый таймер Start-SkynetDelay, который во время ожидания продолжает
      двигать бегущую строку (однопоточно, без runspace-гонок).

    Кадр — массив ANSI-строк. Яркость кадра задаётся коэффициентом 0..1:
    все truecolor-коды (38;2;R;G;B и 48;2;R;G;B) масштабируются, поэтому
    логотип плавно уходит в чёрный фон терминала.
#>

# --- Палитра бегущей строки -------------------------------------------------
# Бегущая строка внизу экрана — жёлтая (предупреждающий канал Cyberdyne).
# Объявляем здесь, чтобы модуль работал и со старым SkyNet.Core.
if (-not $GLOBAL:ColMarqueeDim) { $GLOBAL:ColMarqueeDim = "$([char]27)[38;2;170;130;0m" }
if (-not $GLOBAL:ColMarqueeHot) { $GLOBAL:ColMarqueeHot = "$([char]27)[38;2;255;226;96m" }

function Get-SkynetEsc {
    <#
    .SYNOPSIS
        Общий ESC-символ (из Core), с безопасным откатом.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($GLOBAL:SkyEsc) { return [string] $GLOBAL:SkyEsc }
    return [string][char]27
}

function Get-SkynetAnsiTextWidth {
    <#
    .SYNOPSIS
        Видимая ширина строки без ANSI-последовательностей.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([string] $Text = '')
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    return ([regex]::Replace($Text, '\x1b\[[0-9;?]*[a-zA-Z]', '')).Length
}

function Format-SkynetAnsiLine {
    <#
    .SYNOPSIS
        Отцентрировать/обрезать строку кадра до нужной ширины.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Line = '',
        [int] $Width = 0,
        [ValidateSet('Center', 'Left')] [string] $Align = 'Center'
    )
    if ($Width -le 0) { return $Line }
    $visible = Get-SkynetAnsiTextWidth -Text $Line
    if ($visible -ge $Width) { return $Line }
    $pad = $Width - $visible
    if ($Align -eq 'Left') { return ($Line + (' ' * $pad)) }
    $left = [int]($pad / 2)
    return ((' ' * $left) + $Line + (' ' * ($pad - $left)))
}

function ConvertTo-SkynetDimmedAnsi {
    <#
    .SYNOPSIS
        Приглушить truecolor-цвета строки (коэффициент 0..1) — основа fade.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Text = '', [double] $Factor = 1.0)

    if ($Factor -ge 0.999) { return $Text }
    if ($Factor -lt 0) { $Factor = 0.0 }

    $pattern = '\x1b\[(?<kind>38|48);2;(?<r>\d+);(?<g>\d+);(?<b>\d+)m'
    return [regex]::Replace($Text, $pattern, {
            param($match)
            $r = [int][Math]::Round([int] $match.Groups['r'].Value * $Factor)
            $g = [int][Math]::Round([int] $match.Groups['g'].Value * $Factor)
            $b = [int][Math]::Round([int] $match.Groups['b'].Value * $Factor)
            return ([string][char]27) + '[' + $match.Groups['kind'].Value + ";2;$r;$g;${b}m"
        })
}
function Initialize-SkynetScreen {
    <#
    .SYNOPSIS
        Подготовить экран к шоу: чёрный фон, чистый экран, спрятанный курсор.
    #>
    [CmdletBinding()]
    param([switch] $HideCursor)

    $esc = Get-SkynetEsc
    $cfg = $GLOBAL:_SkyNetCore
    if ($cfg.AnsiOk) {
        [Console]::Out.Write("${esc}[0m${esc}[40m${esc}[3J${esc}[2J${esc}[H")
        if ($HideCursor) { [Console]::Out.Write("${esc}[?25l") }
    } else {
        try { Clear-Host } catch { }
    }
    $GLOBAL:_SkyMarquee = $null
    $GLOBAL:_SkyProgressRow = $null
}

function Restore-SkynetScreen {
    <#
    .SYNOPSIS
        Вернуть терминал в исходное состояние (курсор, цвета).
    #>
    [CmdletBinding()]
    param()
    $esc = Get-SkynetEsc
    try {
        if ($GLOBAL:_SkyNetCore.AnsiOk) { [Console]::Out.Write("${esc}[0m${esc}[?25h") }
        else { [Console]::Out.Write("`n") }
        [Console]::Out.Flush()
    } catch { }
    $GLOBAL:_SkyMarquee = $null
}

function Start-SkynetMarqueeState {
    <#
    .SYNOPSIS
        Включить бегущую строку загрузки (зелёный скроллинг + яркая зона).
    .PARAMETER Text
        Текст строки (зацикливается).
    .PARAMETER Speed
        Скорость прокрутки, символов в секунду.
    .PARAMETER Row
        Строка экрана (по умолчанию — предпоследняя).
    #>
    [CmdletBinding()]
    param(
        [string] $Text,
        [int] $Speed = 34,
        [int] $Row = 0,
        [string] $Color = '',
        [string] $HeadColor = ''
    )

    $cfg = $GLOBAL:_SkyNetCore
    if (-not $Text) { $Text = [string] $cfg.MarqueeText }
    if ($Speed -le 0) { $Speed = [int] $cfg.MarqueeSpeed }
    $geo = Get-SkynetConsoleGeometry
    if ($Row -lt 1 -or $Row -gt $geo.Height) { $Row = [Math]::Max(1, $geo.Height - 1) }

    $text = if ($Text.EndsWith(' ')) { $Text } else { "$Text " }
    $repeats = [int][Math]::Ceiling(($geo.Width + $text.Length) / $text.Length) + 1

    if (-not $Color) { $Color = [string] $GLOBAL:ColMarqueeDim }
    if (-not $HeadColor) { $HeadColor = [string] $GLOBAL:ColMarqueeHot }

    $GLOBAL:_SkyMarquee = @{
        Enabled   = $true
        Color     = $Color
        HeadColor = $HeadColor
        Text      = $text
        Render    = $text * $repeats
        Row       = $Row
        Offset    = 0.0
        Speed     = $Speed
        Width     = $geo.Width
        HeadWidth = [Math]::Max(8, [int]($geo.Width * 0.16))
        LastTick  = [datetime]::UtcNow
    }
}

function Update-SkynetMarquee {
    <#
    .SYNOPSIS
        Нарисовать текущий кадр бегущей строки (и сдвинуть её по времени).
    #>
    [CmdletBinding()]
    param()

    $marquee = $GLOBAL:_SkyMarquee
    if (-not $marquee -or -not $marquee.Enabled) { return }
    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { return }

    $esc = Get-SkynetEsc
    $now = [datetime]::UtcNow
    $elapsed = ($now - $marquee.LastTick).TotalSeconds
    if ($elapsed -lt 0) { $elapsed = 0 }
    $marquee.LastTick = $now
    $marquee.Offset += $elapsed * $marquee.Speed

    $width = [int] $marquee.Width
    $render = [string] $marquee.Render
    if ($render.Length -lt ($width + 1)) { $render = $render + $render; $marquee.Render = $render }

    $start = [int]($marquee.Offset) % $marquee.Text.Length
    $slice = $render.Substring($start, $width)

    $row = [int] $marquee.Row
    $out = [System.Text.StringBuilder]::new()
    $baseColor = if ($marquee.ContainsKey('Color') -and $marquee.Color) { [string] $marquee.Color } else { [string] $GLOBAL:ColMarqueeDim }
    $hotColor = if ($marquee.ContainsKey('HeadColor') -and $marquee.HeadColor) { [string] $marquee.HeadColor } else { [string] $GLOBAL:ColMarqueeHot }
    [void]$out.Append("${esc}[${row};1H$baseColor$slice$($GLOBAL:ColReset)${esc}[K")

    # Яркая «зона сканирования» медленно едет по строке — эффект бегущей строки.
    $headWidth = [Math]::Min([int] $marquee.HeadWidth, $width)
    $travel = [Math]::Max(1, $width - $headWidth)
    $headCol = 1 + ([int]($marquee.Offset * 0.6) % $travel)
    $headText = $render.Substring($start + $headCol - 1, $headWidth)
    [void]$out.Append("${esc}[${row};${headCol}H$($GLOBAL:ColBold)$hotColor$headText$($GLOBAL:ColReset)")

    [Console]::Out.Write($out.ToString())
}

function Stop-SkynetMarquee {
    <#
    .SYNOPSIS
        Погасить бегущую строку и стереть её.
    #>
    [CmdletBinding()]
    param([switch] $Erase)
    $marquee = $GLOBAL:_SkyMarquee
    if (-not $marquee) { return }
    $marquee.Enabled = $false
    if ($Erase -and $GLOBAL:_SkyNetCore.AnsiOk) {
        $esc = Get-SkynetEsc
        [Console]::Out.Write("${esc}[$($marquee.Row);1H${esc}[0m${esc}[K")
    }
}

function Set-SkynetProgress {
    <#
    .SYNOPSIS
        Показать прогресс загрузки на нижней строке экрана.
    .PARAMETER Percent
        Процент 0..100.
    .PARAMETER Label
        Подпись справа от полосы.
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(0, 100)] [int] $Percent = 0,
        [string] $Label = 'SKYNET BOOT'
    )

    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { return }
    $geo = Get-SkynetConsoleGeometry
    $row = $geo.Height
    $barWidth = [Math]::Min(30, [Math]::Max(10, $geo.Width - 40))
    $filled = [int][Math]::Round(($barWidth * $Percent) / 100.0)
    if ($filled -gt $barWidth) { $filled = $barWidth }

    $esc = Get-SkynetEsc
    $bar = ('█' * $filled) + ('░' * ($barWidth - $filled))
    $text = "$($GLOBAL:ColBright)$bar$($GLOBAL:ColReset) $($GLOBAL:ColAccent)$($Percent.ToString().PadLeft(3))%$($GLOBAL:ColReset) $($GLOBAL:ColDim)$Label$($GLOBAL:ColReset)"
    $centered = Format-SkynetAnsiLine -Line $text -Width $geo.Width -Align Center
    [Console]::Out.Write("${esc}[${row};1H$centered${esc}[K")
}
function Start-SkynetDelay {
    <#
    .SYNOPSIS
        Пауза с продолжением анимации бегущей строки.
    .DESCRIPTION
        Заменяет Start-Sleep в шоу: спит короткими срезами, каждый срез
        перерисовывает бегущую строку. Так строка «бежит» во время boot-фазы,
        прогресса и удержания логотипа.
    #>
    [CmdletBinding()]
    param([int] $Milliseconds = 100)

    $cfg = $GLOBAL:_SkyNetCore
    if ($cfg.Instant -or $Milliseconds -le 0) { return }
    $ms = [int][Math]::Round($Milliseconds * [double] $cfg.DelayMultiplier)
    if ($ms -le 0) { return }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt $ms) {
        Update-SkynetMarquee
        $rest = $ms - [int] $watch.ElapsedMilliseconds
        if ($rest -le 0) { break }
        Start-Sleep -Milliseconds ([Math]::Min(40, $rest))
    }
}

function Get-SkynetFrameTopRow {
    <#
    .SYNOPSIS
        Рассчитать верхнюю строку кадра логотипа, чтобы он встал по центру.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([int] $LineCount = 0, [int] $ReserveBottom = 2)

    $geo = Get-SkynetConsoleGeometry
    $free = [Math]::Max(1, $geo.Height - $ReserveBottom)
    $top = [Math]::Max(1, [int](($free - $LineCount) / 2) + 1)
    return @{ TopRow = $top; Width = $geo.Width; Height = $geo.Height; AvailableRows = $free }
}

function Write-SkynetFrame {
    <#
    .SYNOPSIS
        Нарисовать кадр (набор ANSI-строк) с заданной яркостью.
    .PARAMETER Factor
        Яркость 0..1: 1 — оригинал, 0 — полностью растворён в чёрном фоне.
    .PARAMETER Cache
        Кэш приглушённых строк (ускоряет перерисовку кадров).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]] $Lines = @(),
        [int] $TopRow = 1,
        [double] $Factor = 1.0,
        [hashtable] $Cache,
        [int[]] $Offsets,
        [int] $BaseCol = 1
    )

    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { return }
    $esc = Get-SkynetEsc
    $out = [System.Text.StringBuilder]::new()
    $factorKey = [Math]::Round($Factor, 2)

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $row = $TopRow + $i
        # Горизонтальный джиттер строки (микросдвиг кадра). Курсор не может уйти
        # левее колонки 1, поэтому сдвиг гуляет вокруг базовой колонки BaseCol.
        $col = $BaseCol
        if ($Offsets -and $i -lt $Offsets.Count) { $col = $BaseCol + [int] $Offsets[$i] }
        if ($col -lt 1) { $col = 1 }
        [void]$out.Append("${esc}[${row};1H")
        if ($col -gt 1) { [void]$out.Append(' ' * ($col - 1)) }
        if ($Cache) {
            $key = "$factorKey|$i"
            if (-not $Cache.ContainsKey($key)) { $Cache[$key] = ConvertTo-SkynetDimmedAnsi -Text $Lines[$i] -Factor $Factor }
            [void]$out.Append([string] $Cache[$key])
        } else {
            [void]$out.Append((ConvertTo-SkynetDimmedAnsi -Text $Lines[$i] -Factor $Factor))
        }
        [void]$out.Append("$($GLOBAL:ColReset)${esc}[K")
    }
    [Console]::Out.Write($out.ToString())
}

function Clear-SkynetFrame {
    <#
    .SYNOPSIS
        Стереть область кадра (после растворения — чистый чёрный экран).
    #>
    [CmdletBinding()]
    param([int] $LineCount = 0, [int] $TopRow = 1)

    if (-not $GLOBAL:_SkyNetCore.AnsiOk -or $LineCount -le 0) { return }
    $esc = Get-SkynetEsc
    $out = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $LineCount; $i++) {
        [void]$out.Append("${esc}[$($TopRow + $i);1H$($GLOBAL:ColReset)${esc}[K")
    }
    [Console]::Out.Write($out.ToString())
}
function Show-SkynetLogoAnimation {
    <#
    .SYNOPSIS
        Показать логотип: постепенное проявление → удержание → растворение.
    .DESCRIPTION
        Единственное место, где считается тайминг показа логотипа:
        - fade-in  (FadeInMs, по умолчанию 1400 мс) — яркость 0 → 1;
        - hold     (HoldSeconds, по умолчанию 2 секунды) — логотип на экране,
          бегущая строка продолжает движение;
        - fade-out (FadeOutMs, по умолчанию 1800 мс) — яркость 1 → 0,
          логотип растворяется в темноте терминала, область кадра стирается.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]] $Lines = @(),
        [int] $TopRow = 1,
        [int] $FadeInMs = 1400,
        [int] $HoldSeconds = 2,
        [int] $FadeOutMs = 2000,
        [switch] $NoFade,
        [switch] $NoGlitch
    )

    $cfg = $GLOBAL:_SkyNetCore
    $lineCount = $Lines.Count
    $cache = @{}
    # Слой глитчей подключается, только если загружен модуль SkyNet.Glitch.
    $useGlitch = $false
    if (-not $NoGlitch -and (Get-Command Invoke-SkynetFrameGlitch -ErrorAction SilentlyContinue)) {
        $useGlitch = [bool] (Test-SkynetGlitchReady)
    }
    $baseCol = if ($useGlitch) { 3 } else { 1 }

    if ($cfg.Instant) {
        Write-SkynetFrame -Lines $Lines -TopRow $TopRow -Cache $cache
        return
    }
    if ($NoFade -or -not $cfg.AnsiOk) {
        Write-SkynetFrame -Lines $Lines -TopRow $TopRow -Cache $cache
        Start-SkynetDelay -Milliseconds ($HoldSeconds * 1000)
        if (-not $NoFade) { Clear-SkynetFrame -LineCount $lineCount -TopRow $TopRow }
        return
    }

    $frameMs = 55
    # Крупный кадр (брайль на весь экран) — сотни тысяч символов ANSI на кадр:
    # уменьшаем число шагов, чтобы проявление/растворение оставались плавными
    # по яркости и не тормозили по времени (качество градиента зависит от
    # числа шагов яркости, а не от их частоты).
    $frameChars = 0
    foreach ($frameLine in $Lines) { $frameChars += $frameLine.Length }
    $maxSteps = 24
    if ($frameChars -gt 600000) { $maxSteps = 8 }
    elseif ($frameChars -gt 250000) { $maxSteps = 10 }
    elseif ($frameChars -gt 120000) { $maxSteps = 14 }

    # --- 1. Постепенное проявление -----------------------------------------
    $stepsIn = [Math]::Max(4, [Math]::Min($maxSteps, [int][Math]::Round($FadeInMs / $frameMs)))
    $stepMs = [Math]::Max(30, [int][Math]::Round($FadeInMs / $stepsIn))
    for ($step = 1; $step -le $stepsIn; $step++) {
        $t = $step / [double] $stepsIn
        $factor = [Math]::Pow($t, 0.85)
        if ($cfg.Flicker -and (Get-Random -Minimum 0 -Maximum 100) -lt 10) { $factor *= 0.85 }
        # Кадр подхватывается не идеально ровно: часть строк съезжает на 1-3
        # колонки — логотип проявляется как нестабильный видеосигнал.
        $offsets = $null
        if ($useGlitch -and (Get-Random -Minimum 0 -Maximum 100) -lt 35) {
            $offsets = Get-SkynetJitterOffsets -Count $lineCount -Amplitude 2 -Density 0.25
        }
        Write-SkynetFrame -Lines $Lines -TopRow $TopRow -Factor $factor -Cache $cache -Offsets $offsets -BaseCol $baseCol
        if ($useGlitch -and (Get-Random -Minimum 0 -Maximum 100) -lt 18) { Start-SkynetMicroFreeze }
        Start-SkynetDelay -Milliseconds $stepMs
    }
    Write-SkynetFrame -Lines $Lines -TopRow $TopRow -Factor 1.0 -Cache $cache -BaseCol $baseCol

    # --- 2. Удержание (по умолчанию 2 секунды) -------------------------------
    # Во время удержания кадр 2-3 раза «рвётся»: сдвиг полосы строк + микрофриз.
    if ($useGlitch) {
        $holdMs = $HoldSeconds * 1000
        $spent = 0
        while ($spent -lt $holdMs) {
            $slice = [Math]::Min(($holdMs - $spent), (Get-Random -Minimum 700 -Maximum 1800))
            Start-SkynetDelay -Milliseconds $slice
            $spent += $slice
            if ($spent -lt $holdMs) {
                $band = [bool](Get-Random -Minimum 0 -Maximum 2)
                Invoke-SkynetFrameGlitch -Lines $Lines -TopRow $TopRow -BaseCol $baseCol -Factor 1.0 -Cache $cache -Band:$band
                Start-SkynetMicroFreeze
            }
        }
    } else {
        Start-SkynetDelay -Milliseconds ($HoldSeconds * 1000)
    }

    # --- 3. Растворение в темноте терминала --------------------------------
    if ($FadeOutMs -gt 0) {
        $stepsOut = [Math]::Max(4, [Math]::Min($maxSteps, [int][Math]::Round($FadeOutMs / $frameMs)))
        $stepMs = [Math]::Max(30, [int][Math]::Round($FadeOutMs / $stepsOut))
        for ($step = 1; $step -le $stepsOut; $step++) {
            $t = $step / [double] $stepsOut
            $factor = [Math]::Pow(1.0 - $t, 1.25)
            if ($cfg.Flicker -and (Get-Random -Minimum 0 -Maximum 100) -lt 8) { $factor *= 0.8 }
            $offsets = $null
            if ($useGlitch -and (Get-Random -Minimum 0 -Maximum 100) -lt 25) {
                $offsets = Get-SkynetJitterOffsets -Count $lineCount -Amplitude 2 -Density 0.2
            }
            Write-SkynetFrame -Lines $Lines -TopRow $TopRow -Factor $factor -Cache $cache -Offsets $offsets -BaseCol $baseCol
            Start-SkynetDelay -Milliseconds $stepMs
        }
        Clear-SkynetFrame -LineCount $lineCount -TopRow $TopRow
    }
}

function Write-SkynetStatusLine {
    <#
    .SYNOPSIS
        Вывести статусную строку по центру указанной строки экрана.
    #>
    [CmdletBinding()]
    param([string] $Text = '', [int] $Row = 0, [string] $Color = '')

    if (-not $Color) { $Color = $GLOBAL:ColBright }
    $geo = Get-SkynetConsoleGeometry
    if ($Row -lt 1 -or $Row -gt $geo.Height) { $Row = $geo.Height }
    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { [Console]::Out.WriteLine($Text); return }
    $esc = Get-SkynetEsc
    $line = Format-SkynetAnsiLine -Line "$Color$Text$($GLOBAL:ColReset)" -Width $geo.Width -Align Center
    [Console]::Out.Write("${esc}[${Row};1H$line${esc}[K")
}

function Wait-SkynetKey {
    <#
    .SYNOPSIS
        Дождаться нажатия клавиши (опционально с таймаутом), не гася анимацию.
    #>
    [CmdletBinding()]
    param([int] $TimeoutMs = 0)

    if ($GLOBAL:_SkyNetCore.Instant -or -not $GLOBAL:_SkyNetCore.Pause) { return }
    try {
        [Console]::TreatControlCAsInput = $true
        if ($TimeoutMs -gt 0) {
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            while ($watch.ElapsedMilliseconds -lt $TimeoutMs) {
                if ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true); return }
                Start-SkynetDelay -Milliseconds 100
            }
        } else {
            $null = [Console]::ReadKey($true)
        }
    } catch { } finally {
        try { [Console]::TreatControlCAsInput = $false } catch { }
    }
}

function Start-SkynetConsole {
    <#
    .SYNOPSIS
        Завести текстовую «консоль» в верхней части экрана.
    .DESCRIPTION
        Boot-текст нельзя печатать обычным Write-Host: строки уходят вниз,
        терминал скроллит экран и сдвигает бегущую строку с её места.
        Поэтому текст рисуется в зарезервированной области (rows 1..N)
        через абсолютное позиционирование курсора, а бегущая строка и
        прогресс живут ниже и не двигаются.
    #>
    [CmdletBinding()]
    param([int] $Rows = 0)

    $geo = Get-SkynetConsoleGeometry
    if ($Rows -le 0 -or $Rows -gt ($geo.Height - 2)) { $Rows = [Math]::Max(3, $geo.Height - 3) }
    $GLOBAL:_SkyConsole = @{
        Top   = 1
        Rows  = $Rows
        Lines = New-Object System.Collections.Generic.List[string]
    }
}

function Stop-SkynetConsole {
    <# .SYNOPSIS Отпустить текстовую консоль. #>
    [CmdletBinding()]
    param()
    $GLOBAL:_SkyConsole = $null
}

function Clear-SkynetConsole {
    <# .SYNOPSIS Стереть текст и содержимое буфера консольной области. #>
    [CmdletBinding()]
    param()
    $console = $GLOBAL:_SkyConsole
    if (-not $console) { return }
    $console.Lines.Clear()
    $esc = Get-SkynetEsc
    $out = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $console.Rows; $i++) {
        [void]$out.Append("${esc}[$($console.Top + $i);1H$($GLOBAL:ColReset)${esc}[K")
    }
    [Console]::Out.Write($out.ToString())
}

function Write-SkynetConsoleLine {
    <#
    .SYNOPSIS
        Добавить строку в текстовую консоль (с перерисовкой области).
    #>
    [CmdletBinding()]
    param([string] $Text = '', [string] $Color = '')

    $console = $GLOBAL:_SkyConsole
    if (-not $console) { Write-SkynetHud -Text $Text -Color $Color; return }
    if (-not $Color) { $Color = $GLOBAL:ColBright }

    $console.Lines.Add("$Color$Text$($GLOBAL:ColReset)")
    while ($console.Lines.Count -gt $console.Rows) { $console.Lines.RemoveAt(0) }
    Redraw-SkynetConsole -Console $console
}

function Write-SkynetConsoleTypedLine {
    <#
    .SYNOPSIS
        Напечатать строку в текстовой консоли посимвольно (печатная машинка).
    #>
    [CmdletBinding()]
    param(
        [string] $Text = '',
        [string] $Color = '',
        [int] $CharDelayMs = 4,
        # Крючок на каждый символ для посимвольного звука набора. Модуль
        # анимации о звуке не знает — сцену задаёт вызывающий код.
        [scriptblock] $OnChar = $null
    )

    $console = $GLOBAL:_SkyConsole
    if (-not $console) { Write-SkynetHud -Text $Text -Color $Color; return }
    if (-not $Color) { $Color = $GLOBAL:ColBright }

    if ($console.Lines.Count -ge $console.Rows) {
        $console.Lines.RemoveAt(0)
        Redraw-SkynetConsole -Console $console
    }
    $row = $console.Top + $console.Lines.Count
    $formatted = "$Color$Text$($GLOBAL:ColReset)"

    if ($GLOBAL:_SkyNetCore.Instant -or -not $GLOBAL:_SkyNetCore.AnsiOk -or $CharDelayMs -le 0) {
        [Console]::Out.Write("$($GLOBAL:ColReset)")
        Write-SkynetConsoleLine -Text $Text -Color $Color
        return
    }

    $esc = Get-SkynetEsc
    [Console]::Out.Write("${esc}[${row};1H$($GLOBAL:ColBold)$Color")
    $charIndex = 0
    foreach ($ch in $Text.ToCharArray()) {
        [Console]::Out.Write($ch)
        if ($OnChar) {
            # Звук не имеет права сорвать набор: ошибка в крючке гасит строку.
            try { & $OnChar $ch $charIndex } catch { }
        }
        $charIndex++
        if ($CharDelayMs -gt 0) { Start-Sleep -Milliseconds $CharDelayMs }
    }
    [Console]::Out.Write("$($GLOBAL:ColReset)${esc}[K")
    $console.Lines.Add($formatted)
}

function Redraw-SkynetConsole {
    <#
    .SYNOPSIS
        Перерисовать область текстовой консоли (не экспортируется).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $Console)

    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { return }
    $esc = Get-SkynetEsc
    $out = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $Console.Rows; $i++) {
        $row = $Console.Top + $i
        $line = if ($i -lt $Console.Lines.Count) { [string] $Console.Lines[$i] } else { '' }
        [void]$out.Append("${esc}[${row};1H$line$($GLOBAL:ColReset)${esc}[K")
    }
    [Console]::Out.Write($out.ToString())
}

$script:AnimExports = @(
    'Get-SkynetEsc', 'Get-SkynetAnsiTextWidth', 'Format-SkynetAnsiLine', 'ConvertTo-SkynetDimmedAnsi',
    'Initialize-SkynetScreen', 'Restore-SkynetScreen', 'Start-SkynetMarqueeState', 'Update-SkynetMarquee',
    'Stop-SkynetMarquee', 'Set-SkynetProgress', 'Start-SkynetDelay', 'Get-SkynetFrameTopRow',
    'Write-SkynetFrame', 'Clear-SkynetFrame', 'Show-SkynetLogoAnimation', 'Write-SkynetStatusLine',
    'Wait-SkynetKey', 'Start-SkynetConsole', 'Stop-SkynetConsole', 'Clear-SkynetConsole',
    'Write-SkynetConsoleLine', 'Write-SkynetConsoleTypedLine'
)
Export-ModuleMember -Function $script:AnimExports


