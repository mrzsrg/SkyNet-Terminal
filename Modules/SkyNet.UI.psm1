<#
.SYNOPSIS
    SkyNet UI — примитивы вывода: HUD, баннер, печатная машинка.

.DESCRIPTION
    Текстовый вывод boot-фазы. Все паузы идут через Start-SkynetDelay
    (модуль SkyNet.Anim), поэтому бегущая строка не останавливается,
    пока печатается boot-текст.
#>

function Clear-SkynetScreen {
    <#
    .SYNOPSIS
        Очистить экран (ANSI или Clear-Host как fallback).
    #>
    [CmdletBinding()]
    param([switch] $UseAnsi)
    $esc = if ($GLOBAL:SkyEsc) { [string] $GLOBAL:SkyEsc } else { [string][char]27 }
    if ($UseAnsi -or $GLOBAL:_SkyNetCore.AnsiOk) { [Console]::Out.Write("${esc}[3J${esc}[2J${esc}[H") }
    else { try { Clear-Host } catch { [Console]::Out.Write("`n`n`n") } }
}

function Write-SkynetHud {
    <#
    .SYNOPSIS
        Вывести строку HUD с цветом (или без ANSI).
    #>
    [CmdletBinding()]
    param([string] $Text = '', [string] $Color = '', [switch]$Force)
    if (-not $Color) { $Color = $GLOBAL:ColBright }
    if ($GLOBAL:_SkyNetCore.AnsiOk -or $Force) { [Console]::Out.WriteLine("${Color}${Text}$($GLOBAL:ColReset)") }
    else { [Console]::Out.WriteLine($Text) }
}

function Write-SkynetTypeLine {
    <#
    .SYNOPSIS
        Печатная машинка: вывести строку посимвольно.
    #>
    [CmdletBinding()]
    param([string] $Text = '', [string] $Color = '', [int]$CharDelayMs = 4)
    if (-not $Color) { $Color = $GLOBAL:ColBright }
    if (-not $GLOBAL:_SkyNetCore.AnsiOk -or $GLOBAL:_SkyNetCore.Instant -or $CharDelayMs -le 0) {
        Write-SkynetHud -Text $Text -Color $Color
        return
    }
    [Console]::Out.Write($GLOBAL:ColBold + $Color)
    foreach ($ch in $Text.ToCharArray()) {
        [Console]::Out.Write($ch)
        if ($CharDelayMs -gt 0) { Start-Sleep -Milliseconds $CharDelayMs }
    }
    [Console]::Out.Write($GLOBAL:ColReset)
    [Console]::Out.Write([Environment]::NewLine)
}

function Write-SkynetBanner {
    <#
    .SYNOPSIS
        Баннер отключён (по просьбе — раньше показывал ASCII-арт + 2 строки HUD).
    .DESCRIPTION
        Оставлена пустой функцией, а не удалена: её вызывает Boot.psm1, и без
        этой заглушки загрузка упала бы на "command not found". Если решишь
        вернуть баннер — старый текст можно достать из истории чата/бэкапа.
    #>
    [CmdletBinding()]
    param()
    # намеренно ничего не делает
}

function Start-SkynetTick {
    <#
    .SYNOPSIS
        Пауза кадра (совместимость): делегирует в Start-SkynetDelay,
        чтобы во время ожидания двигалась бегущая строка.
    #>
    [CmdletBinding()]
    param([int] $Milliseconds = 100)
    if (Get-Command Start-SkynetDelay -ErrorAction SilentlyContinue) { Start-SkynetDelay -Milliseconds $Milliseconds }
    elseif (-not $GLOBAL:_SkyNetCore.Instant -and $Milliseconds -gt 0) { Start-Sleep -Milliseconds $Milliseconds }
}

function Write-SkynetSixelLine {
    <#
    .SYNOPSIS
        Пиксельная строка текста через chafa (только если chafa найден).
    #>
    [CmdletBinding()]
    param([string] $Text = '', [string]$HexColor = '00FF46', [int] $Cells = 3, [int]$FontPx = 26)

    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { Write-SkynetHud -Text $Text -Color $GLOBAL:ColBright; return }
    $chafa = Get-SkynetChafaPath
    if (-not $chafa) { Write-SkynetHud -Text $Text -Color $GLOBAL:ColBright; return }

    try {
        if (-not ('System.Drawing.Bitmap' -as [type])) { Add-Type -AssemblyName System.Drawing }
        $font = [System.Drawing.Font]::new('Consolas', $FontPx, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $measureBmp = [System.Drawing.Bitmap]::new(4, 4)
        $graphics = [System.Drawing.Graphics]::FromImage($measureBmp)
        $size = $graphics.MeasureString($Text, $font)
        $graphics.Dispose()
        $measureBmp.Dispose()

        $width = [Math]::Max(8, [int][Math]::Ceiling($size.Width) + 4)
        $height = [Math]::Max(8, [int][Math]::Ceiling($size.Height) + 4)
        $bmp = [System.Drawing.Bitmap]::new($width, $height)
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $graphics.Clear([System.Drawing.Color]::Black)
        $r = [Convert]::ToInt32($HexColor.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($HexColor.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($HexColor.Substring(4, 2), 16)
        $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, $r, $g, $b))
        $graphics.DrawString($Text, $font, $brush, 2, 2)
        $graphics.Dispose()
        $brush.Dispose()
        $font.Dispose()

        $tmp = Join-Path $env:TEMP ('skynet_txt_' + [guid]::NewGuid().ToString('N') + '.png')
        $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        & $chafa --format=sixel ('--size=999x{0}' -f $Cells) $tmp 2>$null
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    } catch {
        Write-SkynetHud -Text $Text -Color $GLOBAL:ColBright
    }
}

$script:UiExports = @('Clear-SkynetScreen', 'Write-SkynetHud', 'Write-SkynetTypeLine', 'Write-SkynetBanner', 'Start-SkynetTick', 'Write-SkynetSixelLine')
Export-ModuleMember -Function $script:UiExports