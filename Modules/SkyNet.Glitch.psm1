<#
.SYNOPSIS
    SkyNet Glitch — кинематографичные микрофризы, сдвиги строк и разрывы кадра.

.DESCRIPTION
    Слой «нестабильного сигнала» поверх любой отрисовки Skynet:
    - микрофриз (Start-SkynetMicroFreeze) — реальная остановка кадра на 40..160 мс,
      бегущая строка в этот момент тоже замирает, поэтому пауза читается как
      подтормаживание терминала, а не как плавная задержка;
    - джиттер строк (Get-SkynetJitterOffsets) — случайный горизонтальный сдвиг
      части строк на 1..3 колонки;
    - разрыв кадра (Invoke-SkynetFrameGlitch) — 1..3 кадра со сдвигом и
      просадкой яркости, затем мгновенный возврат в исходное положение;
    - глитч boot-текста (Invoke-SkynetBootGlitch) — то же самое для текстовой
      консоли из SkyNet.Anim (Start-SkynetConsole).

    ВАЖНО о сдвиге влево: курсор нельзя поставить в колонку < 1, поэтому весь
    кадр рисуется от базовой колонки BaseCol = 1 + Amplitude, а джиттер гуляет
    в диапазоне -Amplitude..+Amplitude вокруг неё. Постоянный сдвиг на 2-3
    колонки глазом не читается, зато джиттер получается симметричным.

    Модуль ничего не ломает, если ANSI недоступен или включён -Instant:
    все функции тихо выходят (Test-SkynetGlitchReady).
#>

$GLOBAL:_SkyGlitch = @{
    Enabled     = $true
    Intensity   = 1.0      # общий множитель частоты глитчей
    Amplitude   = 3        # максимальный сдвиг строки, колонок
    Density     = 0.35     # доля строк, которые сдвигаются в одном кадре
    MinFreezeMs = 40
    MaxFreezeMs = 150
}

function Get-SkyGlitchEsc {
    <# .SYNOPSIS Общий ESC-символ. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($GLOBAL:SkyEsc) { return [string] $GLOBAL:SkyEsc }
    return [string][char]27
}

function Set-SkynetGlitch {
    <#
    .SYNOPSIS
        Настроить слой глитчей (частота, амплитуда, вкл/выкл).
    .EXAMPLE
        Set-SkynetGlitch -Intensity 1.6 -Amplitude 4
    .EXAMPLE
        Set-SkynetGlitch -Off
    #>
    [CmdletBinding()]
    param(
        [double] $Intensity = -1,
        [int] $Amplitude = 0,
        [double] $Density = -1,
        [switch] $On,
        [switch] $Off
    )
    $g = $GLOBAL:_SkyGlitch
    if ($On) { $g.Enabled = $true }
    if ($Off) { $g.Enabled = $false }
    if ($Intensity -ge 0) { $g.Intensity = $Intensity }
    if ($Amplitude -gt 0) { $g.Amplitude = $Amplitude }
    if ($Density -ge 0) { $g.Density = $Density }
}

function Test-SkynetGlitchReady {
    <# .SYNOPSIS Можно ли сейчас глитчить (ANSI есть, не Instant, слой включён). #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $g = $GLOBAL:_SkyGlitch
    if (-not $g -or -not $g.Enabled) { return $false }
    $cfg = $GLOBAL:_SkyNetCore
    if (-not $cfg) { return $false }
    if ($cfg.Instant) { return $false }
    if (-not $cfg.AnsiOk) { return $false }
    return $true
}

$script:GlitchSound = $null
$script:GlitchSoundChecked = $false

function Invoke-GlitchSound {
    <#
    .SYNOPSIS
        Звук сбоя сигнала. Если SkyNet.Audio не загружен — ничего не делает.
    .DESCRIPTION
        Раньше фризы были полностью беззвучными: звуковые курки жили только в
        прологе, а модуль глитчей — общий слой и для загрузки, и для логотипа,
        и для финала — молчал. Теперь каждый сбой кадра слышен, причём
        «жёсткий» провал сигнала звучит иначе, чем короткий разрыв.

        Get-Command кэшируется: функция вызывается из горячих циклов рендера.
    #>
    [CmdletBinding()]
    param(
        [string] $Cue = 'glitch',
        [int] $ThrottleMs = 0
    )
    if (-not $script:GlitchSoundChecked) {
        $script:GlitchSoundChecked = $true
        $script:GlitchSound = Get-Command 'Invoke-SkynetSound' -ErrorAction SilentlyContinue
    }
    if (-not $script:GlitchSound) { return }
    try { & $script:GlitchSound -Name $Cue -ThrottleMs $ThrottleMs } catch { }
}

function Start-SkynetMicroFreeze {
    <#
    .SYNOPSIS
        Микрофриз: кадр замирает целиком (без обновления бегущей строки).
    .PARAMETER MinMs
        Нижняя граница паузы (по умолчанию из профиля глитчей).
    .PARAMETER MaxMs
        Верхняя граница паузы.
    .PARAMETER Hard
        Длинный «провал сигнала»: пауза увеличивается в 2.5 раза.
    .PARAMETER Silent
        Не проигрывать звук сбоя (повторный вызов из сцены, которая уже
        озвучила свой фриз, — иначе два «щелчка» на один обрыв).
    #>
    [CmdletBinding()]
    param(
        [int] $MinMs = 0,
        [int] $MaxMs = 0,
        [switch] $Hard,
        [switch] $Silent
    )
    if (-not (Test-SkynetGlitchReady)) { return }
    $g = $GLOBAL:_SkyGlitch
    if ($MinMs -le 0) { $MinMs = [int] $g.MinFreezeMs }
    if ($MaxMs -le $MinMs) { $MaxMs = [int] $g.MaxFreezeMs }
    if ($MaxMs -le $MinMs) { $MaxMs = $MinMs + 40 }
    $ms = Get-Random -Minimum $MinMs -Maximum $MaxMs
    if ($Hard) { $ms = [int]($ms * 2.5) }
    # Звук идёт ДО паузы: сбой слышен в момент, когда кадр ещё держится.
    if (-not $Silent) { Invoke-GlitchSound -Cue $(if ($Hard) { 'glitch_hard' } else { 'glitch' }) }
    # Именно Start-Sleep, а не Start-SkynetDelay: бегущая строка должна застыть.
    Start-Sleep -Milliseconds $ms
}

function Get-SkynetJitterOffsets {
    <#
    .SYNOPSIS
        Массив горизонтальных сдвигов для строк кадра.
    .PARAMETER Count
        Число строк.
    .PARAMETER Amplitude
        Максимальный сдвиг (по модулю).
    .PARAMETER Density
        Доля строк, которые вообще сдвигаются (0..1).
    .PARAMETER Band
        Сдвигать не отдельные строки, а сплошную полосу (эффект разрыва кадра).
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory)][int] $Count,
        [int] $Amplitude = 0,
        [double] $Density = -1,
        [switch] $Band
    )
    $g = $GLOBAL:_SkyGlitch
    if ($Amplitude -le 0) { $Amplitude = [int] $g.Amplitude }
    if ($Density -lt 0) { $Density = [double] $g.Density }
    $offsets = New-Object 'int[]' $Count
    if ($Count -le 0) { return $offsets }

    if ($Band) {
        # Одна-две полосы съезжают целиком — классический tear аналогового сигнала.
        $bands = Get-Random -Minimum 1 -Maximum 3
        for ($b = 0; $b -lt $bands; $b++) {
            $height = Get-Random -Minimum 1 -Maximum ([Math]::Max(2, [int]($Count / 4)))
            $top = Get-Random -Minimum 0 -Maximum ([Math]::Max(1, $Count - $height))
            $shift = Get-Random -Minimum (-$Amplitude) -Maximum ($Amplitude + 1)
            if ($shift -eq 0) { $shift = $Amplitude }
            for ($i = $top; $i -lt ($top + $height) -and $i -lt $Count; $i++) { $offsets[$i] = $shift }
        }
        return $offsets
    }

    for ($i = 0; $i -lt $Count; $i++) {
        if ((Get-Random -Minimum 0.0 -Maximum 1.0) -gt $Density) { continue }
        $offsets[$i] = Get-Random -Minimum (-$Amplitude) -Maximum ($Amplitude + 1)
    }
    return $offsets
}

function Write-SkynetGlitchFrame {
    <#
    .SYNOPSIS
        Нарисовать кадр с горизонтальным сдвигом строк и заданной яркостью.
    .DESCRIPTION
        Универсальный писатель кадра: используется и логотипом, и сценой T-800,
        и текстовой консолью. Строка рисуется от колонки BaseCol + Offsets[i],
        слева добивается пробелами, справа гасится ESC[K.
    .PARAMETER BaseCol
        Базовая колонка кадра (1 = левый край экрана).
    .PARAMETER Factor
        Яркость 0..1 (масштабирование truecolor, как в SkyNet.Anim).
    .PARAMETER Offsets
        Сдвиги строк; пустой массив = ровный кадр.
    .PARAMETER Cache
        Кэш приглушённых строк (ключ «фактор|индекс»).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]] $Lines = @(),
        [int] $TopRow = 1,
        [int] $BaseCol = 1,
        [double] $Factor = 1.0,
        [int[]] $Offsets,
        [hashtable] $Cache,
        [int] $ClearWidth = 0
    )
    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { return }
    $esc = Get-SkyGlitchEsc
    $out = [System.Text.StringBuilder]::new()
    $factorKey = [Math]::Round($Factor, 2)
    $reset = [string] $GLOBAL:ColReset

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $row = $TopRow + $i
        $shift = 0
        if ($Offsets -and $i -lt $Offsets.Count) { $shift = [int] $Offsets[$i] }
        $col = $BaseCol + $shift
        if ($col -lt 1) { $col = 1 }

        $text = [string] $Lines[$i]
        if ($Factor -lt 0.999) {
            if ($Cache) {
                $key = "$factorKey|$i"
                if (-not $Cache.ContainsKey($key)) { $Cache[$key] = ConvertTo-SkynetDimmedAnsi -Text $text -Factor $Factor }
                $text = [string] $Cache[$key]
            } else {
                $text = ConvertTo-SkynetDimmedAnsi -Text $text -Factor $Factor
            }
        }

        [void]$out.Append("${esc}[${row};1H$reset")
        if ($col -gt 1) { [void]$out.Append(' ' * ($col - 1)) }
        [void]$out.Append($text)
        [void]$out.Append($reset)
        if ($ClearWidth -le 0) { [void]$out.Append("${esc}[K") }
    }
    [Console]::Out.Write($out.ToString())
}

function Invoke-SkynetFrameGlitch {
    <#
    .SYNOPSIS
        Разрыв кадра: 1..3 «плохих» кадра со сдвигом и просадкой яркости.
    .DESCRIPTION
        После глитча кадр ОБЯЗАТЕЛЬНО перерисовывается ровно — иначе сдвиг
        останется на экране до следующей полной отрисовки.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]] $Lines = @(),
        [int] $TopRow = 1,
        [int] $BaseCol = 1,
        [double] $Factor = 1.0,
        [int] $Frames = 0,
        [hashtable] $Cache,
        [switch] $Band
    )
    if (-not (Test-SkynetGlitchReady)) { return }
    if ($Lines.Count -le 0) { return }

    if ($Frames -le 0) { $Frames = Get-Random -Minimum 1 -Maximum 4 }
    for ($f = 0; $f -lt $Frames; $f++) {
        $offsets = Get-SkynetJitterOffsets -Count $Lines.Count -Band:$Band
        $dim = $Factor * (Get-Random -Minimum 70 -Maximum 101) / 100.0
        Write-SkynetGlitchFrame -Lines $Lines -TopRow $TopRow -BaseCol $BaseCol -Factor $dim -Offsets $offsets -Cache $Cache
        Start-Sleep -Milliseconds (Get-Random -Minimum 25 -Maximum 70)
    }
    # Возврат в норму.
    Write-SkynetGlitchFrame -Lines $Lines -TopRow $TopRow -BaseCol $BaseCol -Factor $Factor -Cache $Cache
}

function Get-SkynetConsoleSnapshot {
    <#
    .SYNOPSIS
        Текущее содержимое текстовой консоли (Start-SkynetConsole) как кадр.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $console = $GLOBAL:_SkyConsole
    if (-not $console) { return $null }
    $lines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $console.Rows; $i++) {
        if ($i -lt $console.Lines.Count) { $lines.Add([string] $console.Lines[$i]) } else { $lines.Add('') }
    }
    return @{ Lines = $lines.ToArray(); TopRow = [int] $console.Top }
}

function Invoke-SkynetConsoleGlitch {
    <#
    .SYNOPSIS
        Сдвиг строк boot-текста + микрофриз, затем возврат.
    .PARAMETER Band
        Сдвигать сплошную полосу строк (жёсткий разрыв), а не отдельные строки.
    .PARAMETER Silent
        Не проигрывать звук сбоя (сцена уже озвучила фриз сама).
    #>
    [CmdletBinding()]
    param(
        [int] $Frames = 0,
        [switch] $Band,
        [switch] $NoFreeze,
        [switch] $Silent
    )
    if (-not (Test-SkynetGlitchReady)) { return }
    $snap = Get-SkynetConsoleSnapshot
    if (-not $snap) { return }

    $g = $GLOBAL:_SkyGlitch
    Invoke-SkynetFrameGlitch -Lines $snap.Lines -TopRow $snap.TopRow -BaseCol (1 + [int] $g.Amplitude) -Frames $Frames -Band:$Band
    if (-not $NoFreeze) { Start-SkynetMicroFreeze -Silent:$Silent }
    # Ровная перерисовка от колонки 1 — консоль возвращается на своё место.
    Write-SkynetGlitchFrame -Lines $snap.Lines -TopRow $snap.TopRow -BaseCol 1
}

function Invoke-SkynetBootGlitch {
    <#
    .SYNOPSIS
        Случайный глитч во время загрузки boot-текста.
    .DESCRIPTION
        Вызывается после каждой напечатанной строки. С вероятностью Chance
        (умноженной на Intensity профиля) проигрывает один из трёх эффектов:
        короткий фриз, джиттер строк, разрыв полосы с длинным фризом.
    #>
    [CmdletBinding()]
    param([double] $Chance = 0.22)

    if (-not (Test-SkynetGlitchReady)) { return }
    $g = $GLOBAL:_SkyGlitch
    $roll = Get-Random -Minimum 0.0 -Maximum 1.0
    if ($roll -gt ($Chance * [double] $g.Intensity)) { return }

    switch (Get-Random -Minimum 0 -Maximum 3) {
        0 { Start-SkynetMicroFreeze }
        1 { Invoke-SkynetConsoleGlitch -Frames 2 }
        default {
            Invoke-SkynetConsoleGlitch -Frames 2 -Band -NoFreeze
            Start-SkynetMicroFreeze -Hard
        }
    }
}

$script:GlitchExports = @(
    'Set-SkynetGlitch', 'Test-SkynetGlitchReady', 'Invoke-GlitchSound',
    'Start-SkynetMicroFreeze', 'Get-SkynetJitterOffsets',
    'Write-SkynetGlitchFrame', 'Invoke-SkynetFrameGlitch', 'Get-SkynetConsoleSnapshot',
    'Invoke-SkynetConsoleGlitch', 'Invoke-SkynetBootGlitch'
)
Export-ModuleMember -Function $script:GlitchExports
