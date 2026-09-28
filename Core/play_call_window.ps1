<#
.SYNOPSIS
    Окно видеозвонка: терминатор «смотрит на нас» в отдельном окне.

.DESCRIPTION
    Запускается в НОВОМ окне Windows Terminal (wt -w new --size/--pos) и
    выглядит как отдельная программа видеозвонка:

        SKYNET SECURE VIDEO CALL              18:41:03
        T-800 MK-VI  <->  HOST      ENCRYPTED  AES-256
        <кадр T-800 из assets\terminator, настоящие Sixel-пиксели>

    Анимация идёт в темпе, который на 20% быстрее прежнего (full-size
    рендера): окно само калибруется, замеряя стоимость одного кадра в
    размере, близком к прежнему полноэкранному, и держит темп
        perFrame = baseMs / (1 + Speedup/100)
    Кадры не очищаются перед следующим, поэтому картинка не мигает.

    По завершении пишет JSON-отчёт в -DoneFile и завершает процесс:
    вкладка и окно звонка закрываются сами.

.PARAMETER DoneFile
    Файл-маркер: сюда пишется JSON с замерами (родительский процесс ждёт его).

.PARAMETER Speedup
    На сколько процентов ускорить анимацию относительно прежнего
    full-size рендера (по умолчанию 20).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ChafaPath,
    [Parameter(Mandatory)][string] $FramesFolder,
    [Parameter(Mandatory)][string] $DoneFile,
    [string] $Peer = 'T-800 MK-VI',
    [int]    $Speedup = 20,
    [int]    $HeaderRows = 3,
    [int]    $FooterRows = 1,
    [int]    $ExitDelayMs = 200,
    [string] $CallTitle = 'Skype Video',
    [int]    $WindowWidth = 1152,
    [int]    $WindowHeight = 700
)

$esc   = [string][char]27
$reset = "${esc}[0m"
$green = "${esc}[38;2;0;255;102m"
$dim   = "${esc}[38;2;0;150;80m"

# Отчёт пишется ВСЕГДА (даже при ошибке), иначе родительский процесс
# будет ждать маркер до таймаута.
$report = [ordered]@{ ok = $false; error = ''; count = 0; totalMs = 0; baseMs = 0; targetMs = 0; achieved = 0; width = 0; height = 0; cacheBuilt = 0 }

function Initialize-CallWinNative {
    <#
    .SYNOPSIS
        Win32-помощник окна звонка: найти своё окно терминала и задать размер.
    .DESCRIPTION
        У wt.exe ключи --size/--pos не работают (значение превращается в
        команду), поэтому окно уменьшается изнутри: ищем окно Windows Terminal
        по заголовку, который задали при запуске, и задаём ему размер.
    #>
    if ('SkyCallWin' -as [type]) { return }
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class SkyCallWin
{
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] private static extern bool SystemParametersInfo(uint action, uint param, ref RECT r, uint winIni);

    public static bool Resize(string titleContains, int width, int height)
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate (IntPtr h, IntPtr l)
        {
            if (!IsWindowVisible(h)) { return true; }
            var cn = new StringBuilder(256);
            GetClassNameW(h, cn, cn.Capacity);
            if (cn.ToString() != "CASCADIA_HOSTING_WINDOW_CLASS") { return true; }
            var tx = new StringBuilder(512);
            GetWindowTextW(h, tx, tx.Capacity);
            if (titleContains != null && titleContains.Length > 0 &&
                tx.ToString().IndexOf(titleContains, StringComparison.OrdinalIgnoreCase) < 0) { return true; }
            found = h;
            return false;
        }, IntPtr.Zero);
        if (found == IntPtr.Zero) { return false; }
        RECT r = new RECT();
        if (!SystemParametersInfo(0x0030, 0, ref r, 0)) { r.Right = 1920; r.Bottom = 1080; }
        int ww = r.Right - r.Left, wh = r.Bottom - r.Top;
        if (width > ww) { width = ww; }
        if (height > wh) { height = wh; }
        ShowWindow(found, 9);
        System.Threading.Thread.Sleep(150);
        int x = r.Left + (ww - width) / 2;
        int y = r.Top + (wh - height) / 2;
        return SetWindowPos(found, IntPtr.Zero, x, y, width, height, 0x0040);
    }
}
'@
    } catch { }
}

function Set-CallWindowSize {
    <# .SYNOPSIS Уменьшить окно звонка до размера «видеоокна». #>
    [CmdletBinding()]
    param(
        [string] $TitleMatch = 'Skype Video',
        [int] $Width = 1100,
        [int] $Height = 680
    )
    try {
        Initialize-CallWinNative
        if ('SkyCallWin' -as [type]) { [void][SkyCallWin]::Resize($TitleMatch, $Width, $Height) }
    } catch { }
}

function Wait-CallFrameDue {
    <#
    .SYNOPSIS
        Дождаться текущего кадра анимации (точный таймер).
    .DESCRIPTION
        Start-Sleep в PowerShell пере overshoots на 1-2 мс, что на 137 кадрах
        даёт сотни миллисекунд. Поэтому ожидание двухступенчатое: грубый
        Start-Sleep, затем Thread::Sleep(1). Дедлайны абсолютные, поэтому
        ошибки не накапливаются.
    #>
    [CmdletBinding()]
    param(
        [double] $DueMs,
        [System.Diagnostics.Stopwatch] $Clock
    )
    while ($true) {
        $left = $DueMs - $Clock.Elapsed.TotalMilliseconds
        if ($left -le 0.4) { break }
        if ($left -gt 4) { Start-Sleep -Milliseconds ([int][Math]::Floor($left) - 1) }
        else { [System.Threading.Thread]::Sleep(1) }
    }
}

function Write-CallRow {
    param([int] $Row, [string] $Text, [int] $Width, [string] $Color = '')
    if (-not $Color) { $Color = $green }
    $body = $Text
    if ($body.Length -lt $Width) { $body = $body + (' ' * ($Width - $body.Length)) }
    [Console]::Out.Write("${esc}[${Row};1H${Color}${body}${reset}${esc}[K")
}

function Write-CallRowLR {
    param([int] $Row, [string] $Left, [string] $Right, [int] $Width, [string] $Color = '')
    $gap = [Math]::Max(1, $Width - $Left.Length - $Right.Length)
    Write-CallRow -Row $Row -Text ($Left + (' ' * $gap) + $Right) -Width $Width -Color $Color
}


try {
    $ErrorActionPreference = 'Stop'
    if (-not (Test-Path -LiteralPath $ChafaPath -PathType Leaf)) { throw "chafa не найден: $ChafaPath" }
    if (-not (Test-Path -LiteralPath $FramesFolder -PathType Container)) { throw "нет папки кадров: $FramesFolder" }

    $exts = @('.jpg', '.jpeg', '.png', '.bmp', '.webp')
    $files = @(Get-ChildItem -LiteralPath $FramesFolder -File |
        Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object { $n = $_.BaseName -replace '\D', ''; if ($n) { [int] $n } else { 0 } })
    $count = $files.Count
    if ($count -lt 1) { throw "в папке нет кадров: $FramesFolder" }
    $report.count = $count

    try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

    # --- Геометрия окна звонка ---------------------------------------------
    # Окно уменьшается до размера «видеоокна»: wt.exe не умеет --size/--pos,
    # поэтому размер задаётся изнутри по заголовку окна.
    if ($WindowWidth -gt 0 -and $WindowHeight -gt 0) {
        Start-Sleep -Milliseconds 220
        Set-CallWindowSize -TitleMatch $CallTitle -Width $WindowWidth -Height $WindowHeight
        Start-Sleep -Milliseconds 320
    }
    $cols = 100; $rows = 30
    try { $ws = $Host.UI.RawUI.WindowSize; $cols = [int] $ws.Width; $rows = [int] $ws.Height } catch { }
    if ($cols -lt 40) { $cols = 100 }
    if ($rows -lt 12) { $rows = 30 }

    $availH = [Math]::Max(4, $rows - $HeaderRows - $FooterRows)
    $availW = [Math]::Max(10, $cols - 2)

    # Размер кадра в знакоместах: соотношение сторон с учётом font-ratio 1/2.
    $iw = 16; $ih = 9
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $probe = [System.Drawing.Image]::FromFile($files[0].FullName)
        try { $iw = [int] $probe.Width; $ih = [int] $probe.Height } finally { $probe.Dispose() }
    } catch { }
    $gridAspect = ($iw / [double] $ih) / 0.5
    $w = [Math]::Max(1, [int][Math]::Floor([Math]::Min($availW, $availH * $gridAspect)))
    $h = [Math]::Max(1, [int][Math]::Floor([Math]::Min($availH, $w / $gridAspect)))
    $top = $HeaderRows + 1 + [Math]::Max(0, [int][Math]::Floor(($availH - $h) / 2))
    $col = 1 + [Math]::Max(0, [int][Math]::Floor(($availW - $w) / 2))
    $report.width = $w; $report.height = $h

    # --- Шапка «программы видеозвонка» --------------------------------------
    [Console]::Out.Write("${esc}[0m${esc}[40m${esc}[2J${esc}[H${esc}[?25l")
    $stamp = (Get-Date).ToString('HH:mm:ss')
    Write-CallRowLR -Row 1 -Left '  SKYNET SECURE VIDEO CALL' -Right "  $stamp  " -Width $cols -Color $green
    Write-CallRowLR -Row 2 -Left "  $Peer  <->  HOST" -Right '  ENCRYPTED  AES-256  ' -Width $cols -Color $dim

    # --- Калибровка: стоимость кадра в «старом» full-size рендере ----------
    # Замеряем НАСТОЯЩИЙ кадр из исходника в размере, близком к прежнему
    # полноэкранному рендеру. Это честная база «до ускорения».
    $baseW = [Math]::Min(200, [Math]::Max($w, 120))
    $baseH = [Math]::Min(60, [Math]::Max($h, 34))
    $baseArgs = @('--format=sixel', "--size=$($baseW)x$($baseH)", '--font-ratio=1/2', '--dither=none', '-c', 'full')
    $samples = @()
    for ($c = 0; $c -lt 2; $c++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try { & $ChafaPath @baseArgs $files[0].FullName | Out-Null } catch { }
        $sw.Stop()
        $samples += [double] $sw.Elapsed.TotalMilliseconds
    }
    $baseMs = [Math]::Max(1.0, ($samples | Measure-Object -Average).Average)
    if ($Speedup -lt 0) { $Speedup = 0 }
    $targetTotal = ($count * $baseMs) / (1.0 + ($Speedup / 100.0))
    $perFrame = $targetTotal / $count
    $report.baseMs = [Math]::Round($baseMs, 1)
    $report.targetMs = [int][Math]::Round($targetTotal)

    # --- Кэш Sixel-кадров ---------------------------------------------------
    # Chafa тратит ~30 мс на ЗАПУСК ПРОЦЕССА независимо от размера кадра, поэтому
    # уменьшение окна почти не ускоряет анимацию. Единственный способ реально
    # ускорить её — не вызывать chafa на каждом кадре. Поэтому готовые Sixel-
    # кадры один раз кэшируются на диск, а при показе просто выводятся в поток.
    # Кэш инвалидируется по времени изменения исходного файла.
    $cacheDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'cache\finale_sixel'
    $cacheTag = "$($w)x$($h)"
    $cacheDir = Join-Path $cacheDir $cacheTag
    $cached = New-Object 'System.Collections.Generic.List[string]'
    $cacheReady = $true
    $builtNow = 0
    try {
        if (-not (Test-Path -LiteralPath $cacheDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
        }
        $playArgs = @('--format=sixel', "--size=$($w)x$($h)", '--font-ratio=1/2', '--dither=none', '-c', 'full')
        $ascii = [System.Text.Encoding]::ASCII
        for ($i = 0; $i -lt $count; $i++) {
            $src = $files[$i]
            $dst = Join-Path $cacheDir ('{0:D4}.sixel' -f ($i + 1))
            $need = $true
            if (Test-Path -LiteralPath $dst -PathType Leaf) {
                $need = ([System.IO.File]::GetLastWriteTimeUtc($dst)) -lt ([System.IO.File]::GetLastWriteTimeUtc($src.FullName))
            }
            if ($need) {
                $text = (& $ChafaPath @playArgs $src.FullName | Out-String)
                if (-not $text) { $cacheReady = $false; break }
                [System.IO.File]::WriteAllText($dst, $text, $ascii)
                $builtNow++
            }
            $cached.Add($dst)
        }
    } catch {
        $cacheReady = $false
    }
    $report.cacheBuilt = $builtNow

    # --- Проигрывание кадров в заданном темпе --------------------------------
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    if ($cacheReady -and $cached.Count -eq $count) {
        # Быстрый путь: готовые Sixel-кадры просто выводятся в поток.
        for ($i = 0; $i -lt $count; $i++) {
            [Console]::Out.Write("${esc}[$($top);$($col)H${esc}[?25l")
            [Console]::Out.Write([System.IO.File]::ReadAllText($cached[$i]))
            Wait-CallFrameDue -DueMs ($i * $perFrame) -Clock $clock
        }
    } else {
        # Запасной путь: если кэш недоступен, chafa вызывается на каждом кадре.
        for ($i = 0; $i -lt $count; $i++) {
            [Console]::Out.Write("${esc}[$($top);$($col)H${esc}[?25l")
            & $ChafaPath @playArgs $files[$i].FullName
            Wait-CallFrameDue -DueMs ($i * $perFrame) -Clock $clock
        }
    }
    $clock.Stop()

    $report.ok = $true
    $report.totalMs = [int][Math]::Round($clock.Elapsed.TotalMilliseconds)
    $report.achieved = [Math]::Round((($count * $baseMs) / [Math]::Max(1, $report.totalMs) - 1.0) * 100.0, 1)

    # --- Подвал окна звонка и выход ------------------------------------------
    Write-CallRowLR -Row $rows -Left '  [REC]   SECURE UPLINK ACTIVE' -Right '  SKYNET  ' -Width $cols -Color $dim
} catch {
    $report.error = $_.Exception.Message
} finally {
    try { [Console]::Out.Write("${esc}[0m${esc}[?25h") } catch { }
    if ($ExitDelayMs -gt 0) { Start-Sleep -Milliseconds $ExitDelayMs }
    try {
        [IO.File]::WriteAllText($DoneFile, ($report | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
    } catch { }
}
