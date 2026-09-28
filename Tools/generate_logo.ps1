<#
.SYNOPSIS
    Генератор ДЕМО-логотипа SkyNet (в служебной папке, оригинал не трогает).

.DESCRIPTION
    Оригинальный логотип проекта живёт в корне репозитория (skynet_logo.png)
    и НИКОГДА не перезаписывается: этот скрипт по умолчанию пишет результат
    в assets/generated/, а попытку записать файл skynet_logo.* в корень проекта
    прерывает с ошибкой. Так оригинал невозможно «затереть» повторной генерацией.

    Скрипт рисует схематичный логотип (пирамида из трёх треугольников +
    надписи SKYNET / CYBERDYNE SYSTEMS) — он годится только как черновик.

.PARAMETER OutPath
    Куда сохранить результат (по умолчанию assets/generated/skynet_logo_generated.jpg).

.PARAMETER Width
.PARAMETER Height
    Размер картинки (по умолчанию 800x620).

.EXAMPLE
    .\Tools\generate_logo.ps1
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [int] $Width = 800,
    [int] $Height = 620
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$originalLogo = Join-Path $projectRoot 'skynet_logo.png'

if (-not $OutPath) { $OutPath = Join-Path $projectRoot 'assets\generated\skynet_logo_generated.jpg' }
if (-not [System.IO.Path]::IsPathRooted($OutPath)) { $OutPath = Join-Path $projectRoot $OutPath }

# --- Защита оригинала ------------------------------------------------------
$outDir = Split-Path -Parent $OutPath
$outName = Split-Path -Leaf $OutPath
$resolvedOutDir = $null
if ($outDir) { $resolvedOutDir = (Resolve-Path -LiteralPath $outDir -ErrorAction SilentlyContinue).Path }
if ($resolvedOutDir -and $resolvedOutDir -eq $projectRoot -and $outName -like 'skynet_logo.*') {
    throw "Отказ: нельзя писать '$outName' в корень проекта — там лежит ОРИГИНАЛ логотипа. Используйте папку assets/generated."
}
if ((Test-Path -LiteralPath $OutPath) -and (Test-Path -LiteralPath $originalLogo)) {
    if ((Get-Item -LiteralPath $OutPath).FullName -eq (Get-Item -LiteralPath $originalLogo).FullName) {
        throw 'Отказ: цель совпадает с оригинальным логотипом проекта.'
    }
}

if (-not $outDir) { $outDir = $projectRoot }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Add-Type -AssemblyName System.Drawing

# --- Оригинал: показываем контрольную сумму, чтобы её можно было сверить ----
if (Test-Path -LiteralPath $originalLogo) {
    $hash = (Get-FileHash -LiteralPath $originalLogo -Algorithm SHA256).Hash
    Write-Host "[SKYNET] Оригинал: $originalLogo" -ForegroundColor DarkGreen
    Write-Host "[SKYNET]   SHA256: $hash" -ForegroundColor DarkGray
} else {
    Write-Host "[SKYNET] ВНИМАНИЕ: оригинал $originalLogo не найден." -ForegroundColor Yellow
}
$bmp = [System.Drawing.Bitmap]::new($Width, $Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$redMain = [System.Drawing.Color]::FromArgb(200, 60, 50)
$redDark = [System.Drawing.Color]::FromArgb(140, 35, 28)
$whiteText = [System.Drawing.Color]::FromArgb(220, 220, 220)
$redSmall = [System.Drawing.Color]::FromArgb(180, 55, 45)

$topPts = [System.Drawing.Point[]]@(
    [System.Drawing.Point]::new(400, 60),
    [System.Drawing.Point]::new(270, 255),
    [System.Drawing.Point]::new(530, 255)
)
$leftPts = [System.Drawing.Point[]]@(
    [System.Drawing.Point]::new(270, 255),
    [System.Drawing.Point]::new(50, 410),
    [System.Drawing.Point]::new(350, 410)
)
$rightPts = [System.Drawing.Point[]]@(
    [System.Drawing.Point]::new(530, 255),
    [System.Drawing.Point]::new(450, 410),
    [System.Drawing.Point]::new(750, 410)
)

$fill = [System.Drawing.SolidBrush]::new($redMain)
foreach ($poly in $topPts, $leftPts, $rightPts) { $g.FillPolygon($fill, $poly) }
$fill.Dispose()

$scanPen = [System.Drawing.Pen]::new($redDark, 1.0)
foreach ($pts in $topPts, $leftPts, $rightPts) {
    $yMin = ($pts | Measure-Object -Property Y -Minimum).Minimum
    $yMax = ($pts | Measure-Object -Property Y -Maximum).Maximum
    for ($y = $yMin; $y -le $yMax; $y += 4) {
        $leftX = $null; $rightX = $null
        for ($i = 0; $i -lt 3; $i++) {
            $p1 = $pts[$i]; $p2 = $pts[($i + 1) % 3]
            if (($p1.Y -le $y -and $p2.Y -gt $y) -or ($p2.Y -le $y -and $p1.Y -gt $y)) {
                $t = ($y - $p1.Y) / [double] ($p2.Y - $p1.Y)
                $x = $p1.X + $t * ($p2.X - $p1.X)
                if ($null -eq $leftX -or $x -lt $leftX) { $leftX = $x }
                if ($null -eq $rightX -or $x -gt $rightX) { $rightX = $x }
            }
        }
        if ($null -ne $leftX -and $null -ne $rightX -and $leftX -lt $rightX) {
            $g.DrawLine($scanPen, [int] $leftX, $y, [int] $rightX, $y)
        }
    }
}
$scanPen.Dispose()

$outlinePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(100, 100, 100), 1.5)
foreach ($poly in $topPts, $leftPts, $rightPts) { $g.DrawPolygon($outlinePen, $poly) }
$outlinePen.Dispose()

$whiteBrush = [System.Drawing.SolidBrush]::new($whiteText)
$redBrush = [System.Drawing.SolidBrush]::new($redSmall)

$titleFont = [System.Drawing.Font]::new('Arial Black', 70, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$titleSize = $g.MeasureString('SKYNET', $titleFont)
$g.DrawString('SKYNET', $titleFont, $whiteBrush, [int](($Width - $titleSize.Width) / 2), 420)
$titleFont.Dispose()

$subFont = [System.Drawing.Font]::new('Arial', 17, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$subText = 'NEURAL NET-BASED ARTIFICIAL INTELLIGENCE'
$subSize = $g.MeasureString($subText, $subFont)
$g.DrawString($subText, $subFont, $whiteBrush, [int](($Width - $subSize.Width) / 2), 420 + [int] $titleSize.Height + 20)
$subFont.Dispose()

$smallFont = [System.Drawing.Font]::new('Arial', 13, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$smallText = 'CYBERDYNE SYSTEMS CORPORATION'
$smallSize = $g.MeasureString($smallText, $smallFont)
$g.DrawString($smallText, $smallFont, $redBrush, [int](($Width - $smallSize.Width) / 2), 420 + [int] $titleSize.Height + 52)
$smallFont.Dispose()

$whiteBrush.Dispose(); $redBrush.Dispose()

$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose()
$bmp.Dispose()

Write-Host "[SKYNET] Черновик сохранён: $OutPath" -ForegroundColor Green
Write-Host "[SKYNET] Оригинал $originalLogo не изменялся." -ForegroundColor DarkGreen
