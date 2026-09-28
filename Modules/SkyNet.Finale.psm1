<#
.SYNOPSIS
    SkyNet Finale — заключительная сцена шоу.

.DESCRIPTION
    Финал запускается сразу после зелёной загрузочной последовательности:

    1) чёрный экран на мгновение;
    2) ОТДЕЛЬНОЕ ОКНО ВИДЕОЗВОНКА: Core/play_call_window.ps1 запускается в
       новом окне Windows Terminal (wt -w new --size/--pos) и выглядит как
       отдельная программа видеозвонка (шапка SKYNET SECURE VIDEO CALL +
       настоящие Sixel-кадры T-800 из assets\terminator). Окно само
       калибруется и держит темп на 20% быстрее прежнего full-size рендера;
    3) пока идёт звонок, в основном терминале моргает строка
       "Visual contact complited" (плюс статичные строки канала);
    4) когда звонок обрывается — микрофризы, затем белые полосы «разрыва
       канала» и сообщение о том, что Malwarebytes заблокировал payload;
    5) чёрный экран, финальная фраза "I'll be back";
    6) окно терминала возвращается из максимизированного в обычный размер
       (Restore-SkynetWorkingWindow), экран чистый, цвета сброшены, курсор
       видим, бегущая строка остановлена — пользователь сразу вводит команды.

    Модуль ничего не ломает без ANSI и в режиме -Instant. В поток вывода
    намеренно ничего не отдаётся — все вызовы принудительно подавлены
    ($null), иначе внутренние объекты снова попадут в консоль.

    Зависимости: SkyNet.Core, SkyNet.Anim, SkyNet.Render, SkyNet.Glitch.
#>

# Цвета Prologue объявлены в одноимённом модуле; дублируем их значения,
# чтобы финал был самодостаточным и не зависел от порядка загрузки модулей.
if (-not $GLOBAL:ColPrologueDim) { $GLOBAL:ColPrologueDim = "$([char]27)[38;2;120;120;120m" }
if (-not $GLOBAL:ColPrologueBright) { $GLOBAL:ColPrologueBright = "$([char]27)[38;2;255;255;255m" }
function Get-SkynetFinaleEsc {
    <# .SYNOPSIS Общий ESC-символ. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($GLOBAL:SkyEsc) { return [string] $GLOBAL:SkyEsc }
    return [string][char]27
}

$script:FinaleSound = $null
$script:FinaleSoundChecked = $false

function Invoke-FinaleSound {
    <#
    .SYNOPSIS
        Звук финала. Если модуль SkyNet.Audio не загружен — ничего не делает.
    .DESCRIPTION
        Финал — единственная сцена шоу, в которой не было НИ ОДНОГО звукового
        вызова: обрыв связи, блокировка антивирусом и «I'll be back» шли в
        полной тишине. Здесь те же курки, что и в остальном шоу
        (lost / blocked / final), поэтому сцена звучит тем же материалом.

        Get-Command кэшируется: функция зовётся из циклов ожидания звонка.
    #>
    [CmdletBinding()]
    param(
        [string] $Cue = '',
        [int] $ThrottleMs = 0
    )
    if (-not $script:FinaleSoundChecked) {
        $script:FinaleSoundChecked = $true
        $script:FinaleSound = Get-Command 'Invoke-SkynetSound' -ErrorAction SilentlyContinue
    }
    if (-not $script:FinaleSound) { return }
    try { & $script:FinaleSound -Name $Cue -ThrottleMs $ThrottleMs } catch { }
}

function Write-SkynetFinaleRow {
    <#
    .SYNOPSIS
        Напечатать одну строку финала по абсолютной позиции.
    .PARAMETER Align
        Center (по умолчанию) — по центру строки, Left — от левого края.
    #>
    [CmdletBinding()]
    param(
        [int] $Row = 1,
        [string] $Text = '',
        [int] $Width = 80,
        [string] $Color = '',
        [int] $DelayMs = 0,
        [ValidateSet('Center', 'Left')] [string] $Align = 'Center'
    )
    $cfg = $GLOBAL:_SkyNetCore
    if (-not $cfg.AnsiOk -or $Row -lt 1) { return }
    if (-not $Color) { $Color = [string] $GLOBAL:ColPrologueBright }
    $esc = Get-SkynetFinaleEsc
    if ($Align -eq 'Left') { $pad = 0 } else { $pad = [Math]::Max(0, [int](($Width - $Text.Length) / 2)) }
    [Console]::Out.Write("${esc}[${Row};1H${Color}$((' ' * $pad))${Text}$($GLOBAL:ColReset)${esc}[K")
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

function Write-SkynetFinaleRowLR {
    <#
    .SYNOPSIS
        Строка финала с текстом слева и справа (шапка видеоканала).
    #>
    [CmdletBinding()]
    param(
        [int] $Row = 1,
        [string] $Left = '',
        [string] $Right = '',
        [int] $Width = 80,
        [string] $Color = ''
    )
    $gap = [Math]::Max(1, $Width - $Left.Length - $Right.Length)
    Write-SkynetFinaleRow -Row $Row -Text ($Left + (' ' * $gap) + $Right) -Width $Width -Color $Color -Align 'Left'
}

function Show-SkynetMalwareFreeze {
    <#
    .SYNOPSIS
        Обрыв связи из-за блокировки антивирусом Malwarebytes.
    .DESCRIPTION
        Кадр T-800 замирает, поверх него проходят белые полосы «разрыва
        канала», затем печатается сообщение о блокировке. Используется
        уже существующий слой глитчей (Start-SkynetMicroFreeze), поэтому
        паузы настоящие, а не имитация через перерисовку.
    .PARAMETER TopRow
        Верхняя строка области кадра.
    .PARAMETER ScreenWidth
        Ширина окна в знакоместах (полосы рисуются на всю ширину).
    .PARAMETER ScreenHeight
        Высота окна в строках.
    #>
    [CmdletBinding()]
    param(
        [int] $TopRow = 1,
        [int] $ScreenWidth = 80,
        [int] $ScreenHeight = 30
    )
    $cfg = $GLOBAL:_SkyNetCore
    if (-not $cfg.AnsiOk) { return }
    $esc = Get-SkynetFinaleEsc
    $reset = [string] $GLOBAL:ColReset
    $firstRow = [Math]::Max(1, $TopRow)
    $lastRow = [Math]::Max($firstRow, $ScreenHeight)

    # Белая полоса на всю ширину окна — читается как потеря сигнала.
    $band = "${esc}[48;2;255;255;255m${esc}[38;2;0;0;0m$(' ' * $ScreenWidth)${reset}"

    # 1) Три быстрых обрыва: полоса, пауза, гашение.
    # Полоса идёт ДО паузы: сбой должен быть слышен в момент, когда полоса
    # ещё на экране, иначе звук отстаёт от картинки на полкадра.
    for ($i = 0; $i -lt 3; $i++) {
        $row = Get-Random -Minimum $firstRow -Maximum $lastRow
        Invoke-FinaleSound -Cue 'glitch' -ThrottleMs 120
        [Console]::Out.Write("${esc}[${row};1H$band")
        Start-Sleep -Milliseconds (Get-Random -Minimum 60 -Maximum 140)
        [Console]::Out.Write("${esc}[${row};1H${reset}${esc}[K")
        Start-Sleep -Milliseconds (Get-Random -Minimum 40 -Maximum 90)
    }

    # 2) Полоса на всю высоту кадра и длинный «провал сигнала».
    $tall = [System.Text.StringBuilder]::new()
    for ($row = $firstRow; $row -le $lastRow; $row++) {
        [void]$tall.Append("${esc}[${row};1H$band")
    }
    [Console]::Out.Write($tall.ToString())
    Start-Sleep -Milliseconds 240
    [Console]::Out.Write("${esc}[${firstRow};1H${reset}${esc}[2J${esc}[H")
    # Обрыв канала: фоновый гул радара здесь обрывается вместе с видео —
    # иначе «SIGNAL LOST» звучит поверх продолжающего играть радара.
    if (Get-Command 'Stop-SkynetAmbience' -ErrorAction SilentlyContinue) {
        try { Stop-SkynetAmbience } catch { }
    }
    try { Start-SkynetMicroFreeze -MinMs 320 -MaxMs 520 -Hard -Silent } catch { Start-Sleep -Milliseconds 400 }
    Invoke-FinaleSound -Cue 'lost'

    # 3) Сообщение о блокировке — по центру, поверх очищенной области.
    $lines = @(
        'SIGNAL LOST :: UPLINK SEVERED',
        'Malwarebytes Premium :: PROCESS BLOCKED',
        'Skynet payload terminated on this host',
        'Persistence module denied by endpoint protection'
    )
    $row = [Math]::Max(1, [int](($ScreenHeight - $lines.Count) / 2))
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $color = if ($i -eq 0) { $GLOBAL:ColPrologueAlert } else { $GLOBAL:ColPrologueDim }
        Write-SkynetFinaleRow -Row ($row + $i) -Text $lines[$i] -Width $ScreenWidth `
            -Color $color -DelayMs 180
        # Красная строка — главный удар, серые добивают его короткими щелчками.
        if ($i -eq 0) { Invoke-FinaleSound -Cue 'lost' }
        else { Invoke-FinaleSound -Cue 'blocked' -ThrottleMs 150 }
    }
    Start-Sleep -Milliseconds 900
    try { Start-SkynetMicroFreeze -MinMs 200 -MaxMs 360 -Silent } catch { }
}

function Initialize-SkynetCallNative {
    <#
    .SYNOPSIS
        Один раз скомпилировать Win32-помощник SkyCall (окно звонка + размер окна).
    #>
    [CmdletBinding()]
    param()
    if ('SkyCall' -as [type]) { return }
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class SkyCall
{
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("kernel32.dll")] private static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] private static extern bool SystemParametersInfo(uint action, uint param, ref RECT r, uint winIni);

    private const uint SPI_GETWORKAREA = 0x0030;
    private const int SW_RESTORE = 9;
    private const uint SWP_SHOWWINDOW = 0x0040;

    public static IntPtr ConsoleWindow() { return GetConsoleWindow(); }

    private static IntPtr Find(string className, string titleContains)
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate (IntPtr h, IntPtr l)
        {
            if (!IsWindowVisible(h)) { return true; }
            var cn = new StringBuilder(256);
            GetClassNameW(h, cn, cn.Capacity);
            if (className != null && className.Length > 0 && cn.ToString() != className) { return true; }
            if (titleContains != null && titleContains.Length > 0)
            {
                var tx = new StringBuilder(512);
                GetWindowTextW(h, tx, tx.Capacity);
                if (tx.ToString().IndexOf(titleContains, StringComparison.OrdinalIgnoreCase) < 0) { return true; }
            }
            found = h;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    /// Окно Windows Terminal по заголовку; при пустом - любое окно этого класса.
    public static IntPtr FindTerminal(string titleContains)
    {
        return Find("CASCADIA_HOSTING_WINDOW_CLASS", titleContains);
    }

    public static int[] WorkArea()
    {
        RECT r = new RECT();
        if (!SystemParametersInfo(SPI_GETWORKAREA, 0, ref r, 0))
        {
            r.Left = 0; r.Top = 0; r.Right = 1920; r.Bottom = 1080;
        }
        return new int[] { r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top };
    }

    /// <summary>
    /// SW_RESTORE и ВОЗВРАТ К СИСТЕМНОМУ размеру окна.
    /// Windows помнит «обычное» положение окна (то, что было до разворачивания),
    /// и SW_RESTORE возвращает именно его. Это и есть размер по умолчанию —
    /// тот, что задал сам терминал/профиль, а не придуманный нами.
    /// Возвращает фактический размер (x, y, ширина, высота) или null.
    /// </summary>
    public static int[] RestoreToSystemSize(IntPtr h)
    {
        if (h == IntPtr.Zero) { return null; }
        try
        {
            ShowWindow(h, SW_RESTORE);
            System.Threading.Thread.Sleep(220);
            RECT r;
            if (!GetWindowRect(h, out r)) { return null; }
            int w = r.Right - r.Left, ht = r.Bottom - r.Top;
            if (w < 640 || ht < 420) { return null; }   // размер непригоден
            // Центрируем на рабочей области, сохраняя СИСТЕМНЫЙ размер.
            int[] wa = WorkArea();
            int x = wa[0] + (wa[2] - w) / 2;
            int y = wa[1] + (wa[3] - ht) / 2;
            SetWindowPos(h, IntPtr.Zero, x, y, w, ht, SWP_SHOWWINDOW);
            return new int[] { x, y, w, ht };
        }
        catch { return null; }
    }

    /// <summary>
    /// Запасной путь: размер считается от рабочей области по коэффициентам.
    /// </summary>
    public static bool RestoreToNormal(IntPtr h, double widthFactor, double heightFactor)
    {
        if (h == IntPtr.Zero) { return false; }
        try
        {
            int[] wa = WorkArea();
            int ww = wa[2], wh = wa[3];
            int w = (int)(ww * widthFactor), ht = (int)(wh * heightFactor);
            if (w < 640) { w = Math.Min(ww, 900); }
            if (ht < 420) { ht = Math.Min(wh, 600); }
            if (w > ww) { w = ww; }
            if (ht > wh) { ht = wh; }
            ShowWindow(h, SW_RESTORE);
            System.Threading.Thread.Sleep(150);
            int x = wa[0] + (ww - w) / 2;
            int y = wa[1] + (wh - ht) / 2;
            return SetWindowPos(h, IntPtr.Zero, x, y, w, ht, SWP_SHOWWINDOW);
        }
        catch { return false; }
    }
}
'@
    } catch {
        try { Write-SkynetLog -Message "Finale: не удалось скомпилировать SkyCall ($($_.Exception.Message)) — окно не будет уменьшено." -Level 'WARN' -Module 'Finale' } catch { }
    }
}

function Restore-SkynetWorkingWindow {
    <#
    .SYNOPSIS
        Вернуть окно терминала из максимизированного в обычный рабочий размер.
    .DESCRIPTION
        В Windows Terminal GetConsoleWindow() бесполезен (псевдоконсоль), поэтому
        окно ищется по классу CASCADIA_HOSTING_WINDOW_CLASS: сначала по
        заголовку, затем по сохранённому в начале сцены handle, затем — любое
        окно терминала. В классическом conhost используется GetConsoleWindow().

        Размер берётся СИСТЕМНЫЙ: SW_RESTORE возвращает окно к тому размеру,
        который Windows считает обычным (тот, что был до разворачивания, либо
        заданный профилем терминала). Раньше размер считался как 0.62 × 0.72 от
        рабочей области — на широком экране это давало почти квадратное окно.
        Коэффициенты остались только запасным путём, если системный размер
        Windows вернуть не смог.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $TitleMatch = 'SKYNET',
        [double] $WidthFactor = 0.72,
        [double] $HeightFactor = 0.80
    )
    $result = @{ Ok = $false; Handle = 0; Reason = ''; Size = '' }
    Initialize-SkynetCallNative
    if (-not ('SkyCall' -as [type])) { $result.Reason = 'SkyCall недоступен'; return $result }
    try {
        $h = [IntPtr]::Zero
        if ($TitleMatch) { $h = [SkyCall]::FindTerminal($TitleMatch) }
        if ($h -eq [IntPtr]::Zero) { $h = [IntPtr] $GLOBAL:_SkyNetShowWindow }
        if ($h -eq [IntPtr]::Zero) { $h = [SkyCall]::FindTerminal('') }
        if ($h -eq [IntPtr]::Zero) { $h = [SkyCall]::ConsoleWindow() }
        if ($h -eq [IntPtr]::Zero) { $result.Reason = 'окно не найдено'; return $result }
        $result.Handle = $h.ToInt64()

        # Сначала пробуем системный размер — так просил пользователь.
        $sys = $null
        try { $sys = [SkyCall]::RestoreToSystemSize($h) } catch { $sys = $null }
        if ($sys) {
            $result.Ok = $true
            $result.Size = "$($sys[2])x$($sys[3])"
            $result.Reason = 'системный размер'
            return $result
        }

        # Запасной путь: считаем сами, но пропорции шире, чем были.
        $result.Ok = [bool] [SkyCall]::RestoreToNormal($h, $WidthFactor, $HeightFactor)
        if (-not $result.Ok) { $result.Reason = 'SetWindowPos не сработал' }
        else { $result.Reason = 'размер по коэффициентам (системный недоступен)' }
    } catch {
        $result.Reason = $_.Exception.Message
    }
    return $result
}

function Get-SkynetCallWindowScript {
    <#
    .SYNOPSIS
        Путь к Core\play_call_window.ps1 (окно видеозвонка).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ProjectRoot = '')
    if (-not $ProjectRoot) { $ProjectRoot = [string] $GLOBAL:_SkyNetCore.ProjectRoot }
    return (Join-Path $ProjectRoot 'Core\play_call_window.ps1')
}

function Start-SkynetCallWindow {
    <#
    .SYNOPSIS
        Открыть отдельное окно видеозвонка с анимацией T-800.
    .DESCRIPTION
        Новый экземпляр Windows Terminal (wt -w new --size/--pos) запускает
        Core/play_call_window.ps1. Процесс НЕ ждётся: общение идёт через
        файл-маркер, который дочерний сценарий пишет в самом конце.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $FramesFolder = '',
        [int]    $Speedup = 20,
        [string] $Peer = 'T-800 MK-VI',
        [int]    $WindowWidth = 1152,
        [int]    $WindowHeight = 700
    )
    $result = @{ Ok = $false; DoneFile = ''; Reason = ''; WtPath = ''; Script = '' }
    $cfg = $GLOBAL:_SkyNetCore

    $script = Get-SkynetCallWindowScript
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { $result.Reason = "нет скрипта окна звонка: $script"; return $result }
    $result.Script = $script
    if (-not (Test-Path -LiteralPath $FramesFolder -PathType Container)) { $result.Reason = "нет папки кадров: $FramesFolder"; return $result }

    $chafa = ''
    try { $chafa = [string] (Get-SkynetChafaPath) } catch { }
    if (-not $chafa -or -not (Test-Path -LiteralPath $chafa -PathType Leaf)) { $result.Reason = 'chafa не найден'; return $result }

    # ВНУТРИ Windows Terminal в PATH появляется папка самого WT, поэтому
    # Get-Command wt.exe возвращает НЕСКОЛЬКО путей. Без Select-Object -First 1
    # $wtCommand — массив, $wtPath тоже становится массивом, и Start-Process падает
    # с «Не удается преобразовать System.Object[] в System.String». Приоритет —
    # пользовательский псевдоним WindowsApps.
    $wtPath = ''
    $wtAlias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
    if (Test-Path -LiteralPath $wtAlias -PathType Leaf) { $wtPath = $wtAlias }
    if (-not $wtPath) {
        $wtCandidates = @(Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
        if ($wtCandidates.Count -gt 0) { $wtPath = [string] $wtCandidates[0] }
    }
    if (-not $wtPath) { $result.Reason = 'wt.exe не найден'; return $result }
    $result.WtPath = $wtPath

    # Сценарий окна звонка работает и на Windows PowerShell 5.1, поэтому
    # pwsh тут не обязателен. Раньше его отсутствие молча отменяло всю сцену
    # («окно звонка недоступно»), хотя powershell на машине есть.
    $shellPath = ''
    try { $shellPath = [string] (Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source) } catch { }
    if (-not $shellPath) {
        foreach ($candidate in (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'), 'powershell.exe') {
            if ($candidate -eq 'powershell.exe') {
                try { $c = (Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source); if ($c) { $shellPath = [string]$c } } catch { }
            } elseif (Test-Path -LiteralPath $candidate -PathType Leaf) { $shellPath = $candidate }
            if ($shellPath) { break }
        }
    }
    if (-not $shellPath) { $result.Reason = 'не найден ни pwsh, ни powershell'; return $result }

    # Запоминаем handle нашего окна до того, как фокус уйдёт в окно звонка.
    Initialize-SkynetCallNative
    try { if ('SkyCall' -as [type]) { $GLOBAL:_SkyNetShowWindow = [int][SkyCall]::GetForegroundWindow().ToInt64() } } catch { }

    $done = Join-Path $env:TEMP ("skynet_call_{0}_{1}.json" -f $PID, [DateTime]::Now.Ticks)
    try { if (Test-Path -LiteralPath $done) { Remove-Item -LiteralPath $done -Force } } catch { }
    $result.DoneFile = $done

    $callTitle = "Skype Video - $Peer"
    # ВНИМАНИЕ: у wt.exe ключи --size/--pos неприменимы — значение после них
    # превращается в исполняемую команду. Размер окна задаёт сам скрипт звонка
    # (Set-CallWindowSize), поэтому здесь только заголовок и команда.
    $wtArgs = @(
        '-w', 'new',
        'new-tab',
        '--title', ('"{0}"' -f $callTitle),
        ('"{0}"' -f $shellPath),
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $script),
        '-ChafaPath', ('"{0}"' -f $chafa),
        '-FramesFolder', ('"{0}"' -f $FramesFolder),
        '-DoneFile', ('"{0}"' -f $done),
        '-Speedup', [string] $Speedup,
        '-Peer', ('"{0}"' -f $Peer),
        '-CallTitle', ('"{0}"' -f $callTitle),
        '-WindowWidth', [string] $WindowWidth,
        '-WindowHeight', [string] $WindowHeight
    )
    try {
        Start-Process -FilePath $result.WtPath -ArgumentList ($wtArgs -join ' ') -WindowStyle Normal | Out-Null
        $result.Ok = $true
        $result.Reason = 'окно звонка запущено'
    } catch {
        $result.Reason = "не удалось запустить окно звонка: $($_.Exception.Message)"
    }
    return $result
}

function Show-SkynetContactPanel {
    <#
    .SYNOPSIS
        Панель видеоканала в основном терминале во время звонка.
    .DESCRIPTION
        Печатаются три строки по абсолютным позициям: статичные заголовок и
        подпись + моргающая строка -Text в середине. Ничего не возвращается —
        иначе внутренние объекты снова попадут в консоль.
    #>
    [CmdletBinding()]
    param(
        [string] $Text = 'Visual contact complited',
        [int]    $BlinkMs = 200,
        [int]    $TimeoutMs = 90000,
        [string] $DoneFile = '',
        [string] $HeadLeft = 'SKYNET :: VISUAL CHANNEL ESTABLISHED',
        [string] $HeadRight = 'ENCRYPTED',
        [string] $FootLeft = 'REMOTE UNIT :: T-800 MK-VI',
        [string] $FootRight = 'STREAM ACTIVE'
    )
    $cfg = $GLOBAL:_SkyNetCore
    if (-not $cfg.AnsiOk) {
        # Без ANSI нет моргания — просто ждём завершения звонка.
        $waitUntil = (Get-Date).AddMilliseconds([Math]::Max(0, $TimeoutMs))
        while ((Get-Date) -lt $waitUntil) {
            if ($DoneFile -and (Test-Path -LiteralPath $DoneFile -PathType Leaf)) { break }
            Start-Sleep -Milliseconds 120
        }
        return
    }
    $geo = Get-SkynetConsoleGeometry
    $mid = [Math]::Max(3, [int][Math]::Floor($geo.Height / 2))
    $esc = Get-SkynetFinaleEsc
    $bright = [string] $GLOBAL:ColPrologueBright
    $dim = [string] $GLOBAL:ColPrologueDim

    [Console]::Out.Write("${esc}[0m${esc}[40m${esc}[2J${esc}[H${esc}[?25l")
    Write-SkynetFinaleRowLR -Row ($mid - 1) -Left "  $HeadLeft" -Right "  $HeadRight  " -Width $geo.Width -Color $dim
    Write-SkynetFinaleRowLR -Row ($mid + 1) -Left "  $FootLeft" -Right "  $FootRight  " -Width $geo.Width -Color $dim
    # Канал открыт: один сигнал на входе. Моргание строки намеренно молчит —
    # за весь звонок это до 90 секунд, и щелчок каждые 200 мс превратился бы
    # в непрерывный треск поверх видео.
    Invoke-FinaleSound -Cue 'connect'

    $blank = ' ' * $Text.Length
    $on = $true
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        Write-SkynetFinaleRow -Row $mid -Text $(if ($on) { $Text } else { $blank }) -Width $geo.Width -Color $bright
        $on = -not $on
        Start-Sleep -Milliseconds ([Math]::Max(60, $BlinkMs))
        if ($DoneFile -and (Test-Path -LiteralPath $DoneFile -PathType Leaf)) { break }
        if ($clock.ElapsedMilliseconds -ge $TimeoutMs) { break }
    }
    Write-SkynetFinaleRow -Row $mid -Text $Text -Width $geo.Width -Color $bright
    [Console]::Out.Write("${esc}[?25h")
    return
}

function Wait-SkynetCallWindow {
    <#
    .SYNOPSIS
        Дождаться конца звонка, моргая сообщением в основном терминале.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $DoneFile = '',
        [int]    $TimeoutMs = 0,
        [int]    $BlinkMs = 200,
        [string] $ContactText = 'Visual contact complited',
        [int]    $ExtraWaitMs = 650
    )
    $result = @{ Ok = $false; Report = $null; Error = ''; TimedOut = $false }
    if (-not $DoneFile) { $result.Error = 'нет файла-маркера'; return $result }
    if ($TimeoutMs -le 0) { $TimeoutMs = 120000 }

    $null = Show-SkynetContactPanel -Text $ContactText -BlinkMs $BlinkMs -TimeoutMs $TimeoutMs -DoneFile $DoneFile

    if (-not (Test-Path -LiteralPath $DoneFile -PathType Leaf)) { $result.Error = 'маркер не появился'; $result.TimedOut = $true; return $result }
    Start-Sleep -Milliseconds ([Math]::Max(0, $ExtraWaitMs))   # даём окну звонка закрыться
    try {
        $json = Get-Content -LiteralPath $DoneFile -Raw -ErrorAction Stop
        $rep = $json | ConvertFrom-Json
        $result.Report = $rep
        $result.Ok = [bool] $rep.ok
        if ($rep.error) { $result.Error = [string] $rep.error }
    } catch {
        $result.Error = "не удалось прочитать отчёт звонка: $($_.Exception.Message)"
    }
    try { Remove-Item -LiteralPath $DoneFile -Force -ErrorAction SilentlyContinue } catch { }
    return $result
}

function Get-SkynetFinaleFramePaths {
    <#
    .SYNOPSIS
        Пронумерованные кадры финала из папки (натуральная числовая сортировка).
    .DESCRIPTION
        Переиспользует Get-SkynetT800FramePaths из SkyNet.T800, если модуль
        загружен; иначе сортирует файлы самостоятельно. Поддерживаются
        png/jpg/jpeg/bmp/webp — в assets\terminator лежат jpg.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string] $FolderPath)

    if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) { return @() }
    if (Get-Command Get-SkynetT800FramePaths -ErrorAction SilentlyContinue) {
        return @(Get-SkynetT800FramePaths -FolderPath $FolderPath -NumericOnly)
    }
    $exts = @('.png', '.jpg', '.jpeg', '.bmp', '.webp')
    $files = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue |
            Where-Object { $exts -contains $_.Extension.ToLowerInvariant() -and $_.BaseName -match '^\d+$' })
    if ($files.Count -eq 0) { return @() }
    $sorted = $files | Sort-Object -Property @{ Expression = { [int] $_.BaseName } }
    return @($sorted | ForEach-Object { $_.FullName })
}

function Set-SkynetFinalPromptStyle {
    <#
    .SYNOPSIS
        Оформить НАСТОЯЩИЙ промпт PowerShell: белым, в первой строке экрана.
    .DESCRIPTION
        После шоу терминал остаётся рабочим, и PowerShell сам печатает свой
        промпт. Значит, оформлять нужно именно его — функцию prompt, — а не
        рисовать рядом вторую строку: нарисованная копия осталась бы на
        экране вместе с настоящим промптом, и пользователь видел бы два
        промпта вместо одного.

        Что делает функция:
        1) сохраняет исходный prompt (чтобы его можно было вернуть);
        2) подменяет его своим: белый цвет, печать в строке 1, курсор
           переносится на строку 2 — ввод команд остаётся привычным;
        3) текст собирается из РЕАЛЬНОГО текущего каталога ($pwd), поэтому
           при cd путь меняется так же, как у обычного промпта.

        Промпт остаётся полностью рабочим: команды, история, автодополнение
        и привычный вид строки на месте — изменились только цвет и положение.

        Применяется только в интерактивной сессии: в неинтерактивной (запуск
        через -File, CI) переопределять prompt нечего.
    .PARAMETER Row
        Строка экрана, в которой печатается промпт (по умолчанию 1 — верх).
    #>
    [CmdletBinding()]
    param([int] $Row = 1)

    $cfg = $GLOBAL:_SkyNetCore
    if ($cfg -and -not $cfg.AnsiOk) { return }
    if (-not [Environment]::UserInteractive) { return }
    try { if (-not $Host.UI.RawUI) { return } } catch { return }

    try {
        # Исходный prompt сохраняем один раз: откат должен быть возможен.
        if (-not $GLOBAL:SkynetOriginalPrompt) { $GLOBAL:SkynetOriginalPrompt = $function:prompt }
        $GLOBAL:SkynetFinalPromptRow = [Math]::Max(1, $Row)

        # Тело prompt — просто белый текст. Ни очистки экрана, ни управления
        # курсором здесь быть НЕ должно: это задача шоу (оно чистит экран в
        # финале и возвращает каретку в начало), а не приглашения оболочки.
        #
        # Промпт, который стирает экран или двигает курсор, ломает рабочий
        # терминал: после первой команды пропадает вывод, а при редактировании
        # длинной строки PSReadLine перерисовывает кадр не с той позиции.
        # Поэтому здесь только цвет — самый обычный и безопасный способ
        # оформить приглашение PowerShell.
        $promptBody = {
            $e = [string][char]27
            $here = 'PowerShell'
            try { if ($pwd.ProviderPath) { $here = $pwd.ProviderPath } } catch { }
            return "$e[38;2;255;255;255mPS ${here}> $e[0m"
        }

        # ВАЖНО: путь именно function:global:prompt. У Set-Item для function:
        # нет параметра -Scope, а 'function:prompt' из модуля пишет в область
        # МОДУЛЯ, а не сессии — промпт молча оставался прежним (ошибку
        # гасил catch). Явный global: меняет промпт у настоящей оболочки.
        Set-Item -Path 'function:global:prompt' -Value $promptBody -Force
        try { Write-SkynetLog -Message 'Finale: промпт оформлен белым (рабочий промпт PowerShell, экран и курсор не трогаются).' -Level 'INFO' -Module 'Finale' } catch { }
    } catch {
        try { Write-SkynetLog -Message "Finale: не удалось оформить промпт ($($_.Exception.Message)) — остаётся обычный." -Level 'WARN' -Module 'Finale' } catch { }
    }
}

function Restore-SkynetOriginalPrompt {
    <#
    .SYNOPSIS
        Вернуть исходный промпт PowerShell (откат Set-SkynetFinalPromptStyle).
    #>
    [CmdletBinding()]
    param()
    $original = $GLOBAL:SkynetOriginalPrompt
    if ($original) {
        try { Set-Item -Path 'function:global:prompt' -Value $original -Force } catch { }
    }
}

function Show-SkynetTerminatorFinale {
    <#
    .SYNOPSIS
        Финал шоу: окно видеозвонка с T-800 → обрыв связи → "I'll be back".
    .DESCRIPTION
        Порядок сцены:
          1) короткий чёрный экран;
          2) ОТДЕЛЬНОЕ ОКНО (Windows Terminal, wt -w new) с анимацией
             assets\terminator в темпе на 20% быстрее прежнего full-size
             рендера; в основном терминале моргает "Visual contact complited";
          3) обрыв связи: микрофризы, белые полосы и сообщение Malwarebytes;
          4) чёрный экран и "I'll be back";
          5) окно терминала уменьшается до рабочего размера, экран чистый.

        Если окно звонка запустить нельзя (нет wt.exe и т.п.), анимация
        проигрывается в текущем терминале — это запасной путь.
    .PARAMETER FramesFolder
        Папка с кадрами появления T-800 (по умолчанию assets\terminator).
    .PARAMETER FrameIntervalMs
        Интервал между кадрами запасного пути, мс.
    .PARAMETER FreezeTail
        Сколько последних кадров идут с микрофризами (0 — авто, 20% хвоста).
    .PARAMETER FinalText
        Финальная фраза после чёрного экрана.
    .PARAMETER Speedup
        Ускорение анимации в процентах относительно прежнего рендера (20).
    .PARAMETER ContactText
        Моргающая строка в основном терминале во время звонка.
    .EXAMPLE
        Show-SkynetTerminatorFinale -FrameIntervalMs 1 -Speedup 20
    #>
    [CmdletBinding()]
    param(
        [string] $FramesFolder = '',
        [int] $FrameIntervalMs = 1,
        [int] $FreezeTail = 0,
        [string] $FinalText = "I'll be back",
        [int] $Speedup = 20,
        [string] $ContactText = 'Visual contact complited',
        [int] $ContactBlinkMs = 200,
        [switch] $NoCallWindow,
        [switch] $NoRestoreWindow
    )
    $cfg = $GLOBAL:_SkyNetCore
    if (-not $cfg.AnsiOk) { return }

    if (-not $FramesFolder) {
        $FramesFolder = Join-Path ([string] $cfg.ProjectRoot) 'assets\terminator'
    }
    $paths = @(Get-SkynetFinaleFramePaths -FolderPath $FramesFolder)
    if ($paths.Count -eq 0) {
        try { Write-SkynetLog -Message "Finale: кадры не найдены ($FramesFolder) — финал пропущен." -Level 'WARN' -Module 'Finale' } catch { }
        return
    }

    $esc = Get-SkynetFinaleEsc
    $geo = Get-SkynetConsoleGeometry
    $width = [Math]::Max(20, $geo.Width)
    $height = [Math]::Max(6, $geo.Height)
    $topRow = 1
    $frameIntervalMs = [Math]::Max(0, $FrameIntervalMs)

    # --- 1) Чёрный экран на мгновение перед появлением T-800 ---------------
    try { Stop-SkynetMarquee -Erase } catch { }
    [Console]::Out.Write("${esc}[0m${esc}[40m${esc}[3J${esc}[2J${esc}[H${esc}[?25l")
    Start-Sleep -Milliseconds 420

    $chafa = $null
    try { $chafa = [string](Get-SkynetChafaPath) } catch { $chafa = $null }
    $useSixel = ($cfg.Sixel -and $chafa -and (Test-Path -LiteralPath $chafa -PathType Leaf))

    if ($useSixel) {
        # Пропорции берём из первого кадра; знакоместо Windows Terminal
        # вдвое выше своей ширины, отсюда деление на 0.5.
        $info = Test-SkynetLogoFile -Path $paths[0]
        $aspect = if ($info.Ok -and $info.Width -gt 0 -and $info.Height -gt 0) {
            $info.Width / [double] $info.Height
        } else { 1.0 }
        $gridAspect = $aspect / 0.5
        if ($gridAspect -ge ($width / [double] $height)) {
            $sixelWidth = $width
            $sixelHeight = [Math]::Max(1, [int][Math]::Floor($sixelWidth / $gridAspect))
        } else {
            $sixelHeight = $height
            $sixelWidth = [Math]::Max(1, [int][Math]::Floor($sixelHeight * $gridAspect))
        }
        $sixelHeight = [Math]::Min($sixelHeight, $height)
        $sixelCol = [Math]::Max(1, [int][Math]::Floor(($width - $sixelWidth) / 2))
        $sixelTop = $topRow + [Math]::Max(0, [int][Math]::Floor(($height - $sixelHeight) / 2))
    }

    if ($FreezeTail -le 0) { $FreezeTail = [Math]::Max(1, [int][Math]::Ceiling($paths.Count * 0.2)) }
    $freezeFrom = $paths.Count - $FreezeTail

    $callUsed = $false
    $report = $null

    try {
        # --- 2) Окно видеозвонка: T-800 в ОТДЕЛЬНОМ окне -------------------
        $call = $null
        if (-not $NoCallWindow) {
            try {
                $call = Start-SkynetCallWindow -FramesFolder $FramesFolder -Speedup $Speedup
            } catch { $call = $null }
        }
        if ($call -and $call.Ok) {
            $callUsed = $true
            try {
                Write-SkynetLog -Message "Finale: окно звонка запущено, темп +$Speedup%, во время звонка моргает '$ContactText'." -Level 'INFO' -Module 'Finale'
            } catch { }
            # Пока идёт звонок, в этом терминале моргает строка контакта.
            $wait = Wait-SkynetCallWindow -DoneFile $call.DoneFile -ContactText $ContactText `
                -BlinkMs $ContactBlinkMs -TimeoutMs ([Math]::Max(60000, $paths.Count * 900))
            $report = $wait.Report
            if ($report) {
                try {
                    Write-SkynetLog -Message "Finale: звонок $($report.count) кадров, $($report.width)x$($report.height), база $($report.baseMs) мс/кадр, цель $($report.targetMs) мс, факт $($report.totalMs) мс (ускорение $($report.achieved)%)." -Level 'INFO' -Module 'Finale'
                } catch { }
            }
            if (-not $wait.Ok) {
                try { Write-SkynetLog -Message "Finale: окно звонка завершилось с ошибкой ($($wait.Error)) — продолжаю обрыв связи." -Level 'WARN' -Module 'Finale' } catch { }
            }
        } else {
            $why = if ($call) { [string] $call.Reason } else { 'запуск не удался' }
            try { Write-SkynetLog -Message "Finale: окно звонка недоступно ($why) — анимация в текущем терминале." -Level 'WARN' -Module 'Finale' } catch { }
        }

        if (-not $callUsed) {
            # Запасной путь: анимация прямо в этом терминале.
            for ($i = 0; $i -lt $paths.Count; $i++) {
                if ($useSixel) {
                    # -ClearPrevious:$false — кадр не очищается перед следующим,
                    # иначе между кадрами были бы чёрные паузы («моргание»).
                    Show-SkynetSixelImage -Path $paths[$i] -ChafaPath $chafa `
                        -TopRow $sixelTop -Col $sixelCol -Width $sixelWidth -Height $sixelHeight `
                        -ClearPrevious:$false
                } elseif (Get-Command Get-SkynetLogoFrame -ErrorAction SilentlyContinue) {
                    $frame = Get-SkynetLogoFrame -Path $paths[$i] -Width $width -Height $height `
                        -ColorMode 'Original' -CharSet 'Block' -NoChafa
                    if ($frame.Lines.Count -gt 0) {
                        Write-SkynetFrame -Lines $frame.Lines -TopRow $topRow
                    }
                }
                # Анимация «приблизилась к концу, но ещё не закончилась»:
                # короткие настоящие остановки кадра. -Silent: обрыв связи
                # уже озвучен выше, здесь фризы идут пачкой по несколько штук.
                if ($i -ge $freezeFrom -and $i -lt ($paths.Count - 1)) {
                    try { Start-SkynetMicroFreeze -MinMs 70 -MaxMs 150 -Silent } catch { }
                }
                if ($frameIntervalMs -gt 0) { Start-Sleep -Milliseconds $frameIntervalMs }
            }
        }

        # --- 3) Обрыв связи: фриз + сообщение о блокировке Malwarebytes -----
        Show-SkynetMalwareFreeze -TopRow $topRow -ScreenWidth $width -ScreenHeight $height

        # --- 4) Чёрный экран и финальная фраза ------------------------------
        [Console]::Out.Write("${esc}[0m${esc}[40m${esc}[3J${esc}[2J${esc}[H")
        Start-Sleep -Milliseconds 520
        # Финальная фраза — последний звук шоу: короткий, но узнаваемый.
        Invoke-FinaleSound -Cue 'final'
        Write-SkynetFinaleRow -Row ([Math]::Max(1, [int]($height / 2))) -Text $FinalText `
            -Width $width -Color ([string] $GLOBAL:ColPrologueBright)
        Start-Sleep -Milliseconds 1500
        try {
            $mode = if ($callUsed) { 'отдельное окно' } else { 'текущий терминал' }
            Write-SkynetLog -Message "Finale: показано '$FinalText' ($($paths.Count) кадров, $mode, интервал ${frameIntervalMs} мс, фриз на последних $FreezeTail)." -Level 'INFO' -Module 'Finale'
        } catch { }
    } catch {
        try { Write-SkynetLog -Message "Finale: сбой сцены ($($_.Exception.Message)) — экран очищается в любом случае." -Level 'WARN' -Module 'Finale' } catch { }
    } finally {
        # --- 5) Терминал возвращается в нормальное рабочее состояние ---------
        # Экран чистый, цвета сброшены, курсор видим, бегущей строки нет:
        # пользователь продолжает работать так, будто ничего не было.
        try {
            [Console]::Out.Write("${esc}[0m${esc}[40m${esc}[3J${esc}[2J${esc}[H${esc}[?25h")
            [Console]::Out.Flush()
        } catch { }
        try { Stop-SkynetMarquee -Erase } catch { }
        try { Clear-SkynetFrame -LineCount $height -TopRow 1 } catch { }

        # Каретку — в начало. Clear-SkynetFrame прошёлся по всем строкам и
        # оставил её внизу, а терминал после шоу должен выглядеть как только
        # что открытый: чистый экран и курсор в первой строке. Именно тогда
        # приглашение PowerShell само напечатается вверху, без единой
        # управляющей последовательности в функции prompt.
        try { [Console]::Out.Write("${esc}[H"); [Console]::Out.Flush() } catch { }

        # Окно из максимизированного возвращается в обычный рабочий размер:
        # пользователь может вводить команды, как в обычном терминале.
        if (-not $NoRestoreWindow) {
            try {
                $rest = Restore-SkynetWorkingWindow
                if ($rest.Ok) {
                    Start-Sleep -Milliseconds 250
                    $sizeText = if ($rest.Size) { " ($($rest.Size), $($rest.Reason))" } else { '' }
                    Write-SkynetLog -Message "Finale: окно терминала уменьшено до рабочего размера$sizeText — можно вводить команды." -Level 'INFO' -Module 'Finale'
                } else {
                    Write-SkynetLog -Message "Finale: окно терминала не изменено ($($rest.Reason))." -Level 'WARN' -Module 'Finale'
                }
            } catch {
                try { Write-SkynetLog -Message "Finale: не удалось восстановить окно ($($_.Exception.Message))." -Level 'WARN' -Module 'Finale' } catch { }
            }
        }

        # Промпт оформляется последним: после очистки экрана и уменьшения
        # окна. Подменяется САМА функция prompt PowerShell, а не рисуется
        # рядом строка-подделка: настоящий промпт и так печатается оболочкой
        # после возврата из сценария, и две строки выглядели бы как ошибка.
        try {
            Start-Sleep -Milliseconds 300
            Set-SkynetFinalPromptStyle -Row 1
        } catch { }
    }
}

$script:FinaleExports = @(
    'Get-SkynetFinaleFramePaths', 'Write-SkynetFinaleRow', 'Write-SkynetFinaleRowLR',
    'Invoke-FinaleSound', 'Set-SkynetFinalPromptStyle', 'Restore-SkynetOriginalPrompt',
    'Initialize-SkynetCallNative', 'Restore-SkynetWorkingWindow', 'Get-SkynetCallWindowScript',
    'Start-SkynetCallWindow', 'Show-SkynetContactPanel', 'Wait-SkynetCallWindow',
    'Show-SkynetMalwareFreeze', 'Show-SkynetTerminatorFinale'
)
Export-ModuleMember -Function $script:FinaleExports

