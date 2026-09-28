<#
.SYNOPSIS
    SkyNet Prologue — белый «кинематографичный» пролог перед основным шоу.

.DESCRIPTION
    Отдельная, самостоятельная вступительная сцена (белый монохромный «хакерский»
    стиль), которая проигрывается ДО существующей связки
    boot-текст → финальный Sixel-логотип → оранжевая ТТХ-сцена T-800 — и не
    заменяет её, а добавляется перед ней (см. Show-SkynetPrologue).

    Порядок сцен внутри пролога:
    1. Show-SkynetSshIntro       — белая SSH/remote-boot сцена, две пустые строки.
    2. Show-SkynetTerminalHijack — захват обычного PowerShell терминалом Skynet.
    3. Show-SkynetLogoNoiseReveal — логотип Skynet собирается из шума построчно.
    4. Show-SkynetSixelLogo      — сразу после сборки выводится финальный Sixel-кадр.
    5. Show-SkynetOnlineBlink    — мигающее "SKYNET SYSTEM ONLINE" под логотипом.
    6. Show-SkynetRadarBoot      — тёмный экран → GLOBAL DEFENSE NETWORK → поиск юнита.
    7. Show-SkynetUnitScan       — голова T-800 справа (белым), слева закреплённая
                                    шапка (UNIT/MODEL/.../TARGETING) + снизу
                                    прокручивающийся лог: строки читаются из файла
                                    ТТХ терминатора (tactical and technical
                                    specifications.MD, см. Get-SkynetSpecScanLines).
                                    Зоны аннотации: NEURAL PROCESSOR / LEARNING
                                    COMPUTER / OPTICAL+ACOUSTIC / POWER CORE /
                                    HYPER-ALLOY CHASSIS / HYDRAULIC SERVO /
                                    FULL-BODY.
    8. Show-SkynetTorsoScan      — торс T-800 той же машинерией (другая папка
                                    кадров, без прокручивающегося текста).
    9. Show-SkynetOpticalCheck   — тёмный экран → OPTICAL SYSTEM чек-лист.

    Show-SkynetTorsoScan просто пропускается (WARN в лог, ничего не падает),
    пока не передан -TorsoFramesFolder с папкой пронумерованных кадров торса —
    обрабатываются они так же, как кадры головы (тот же радиус дилатации,
    просто другой источник).

    Зависимости: SkyNet.Core, SkyNet.Anim, SkyNet.Glitch, SkyNet.T800.
    Все функции модуля no-op, если ANSI недоступен или включён -Instant
    (кроме прямого текстового вывода в этих случаях — см. Test-SkynetGlitchReady
    и аналогичные проверки внутри).
#>

# --- Белая палитра пролога ---------------------------------------------------
$GLOBAL:ColPrologue = "$([char]27)[38;2;255;255;255m"      # основной белый
if (-not $GLOBAL:ColPrologueDim) { $GLOBAL:ColPrologueDim = "$([char]27)[38;2;120;120;120m" } # тусклый (второстепенный текст)
if (-not $GLOBAL:ColPrologueBright) { $GLOBAL:ColPrologueBright = "$([char]27)[38;2;255;255;255m" } # яркий акцент/мигание
if (-not $GLOBAL:ColPrologueAlert) { $GLOBAL:ColPrologueAlert = "$([char]27)[38;2;255;70;70m" }     # захват/тревога (CONNECTION OVERRIDE)

$script:PrologueNoiseChars = '!@#$%^&*<>/\|;:_-+=~01'
$script:SkynetLocalSystemInfo = $null

function Get-SkynetPrologueEsc {
    <# .SYNOPSIS Общий ESC-символ. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($GLOBAL:SkyEsc) { return [string] $GLOBAL:SkyEsc }
    return [string][char]27
}

function Get-SkynetFrameNumberFromPath {
    <#
    .SYNOPSIS
        Получить числовой номер кадра из пути 1.png/215.png.
    .DESCRIPTION
        Возвращает 0 для нечислового имени. Это позволяет привязать аннотацию
        к исходному PNG, а не к порядковому индексу или скорости Chafa.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([string] $Path = '')
    if ([string]::IsNullOrWhiteSpace($Path)) { return 0 }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $number = 0
    if ([int]::TryParse($name, [ref] $number)) { return $number }
    return 0
}

function Get-SkynetScanStages {
    <#
    .SYNOPSIS
        Канонический порядок зон диагностического сканирования T-800.
    .DESCRIPTION
        Названия зон совпадают с итоговым отчётом Cyberdyne
        (Get-SkynetCyberdyneScanBlock), поэтому живая панель и финальный блок
        читаются как вывод одной и той же системы, а не как два разных списка.

        Диапазоны кадров: первые четыре зоны занимают фиксированные участки
        97…136, участок 137…196 делится пополам на каркас и сервоприводы.
        Кадры 197…N, если они есть в папке, образуют отдельный этап
        FULL-BODY SCAN и после последнего кадра получают подтверждение
        FULL-BODY SCAN DONE. Номер последнего кадра передаётся сюда из
        фактического списка PNG, поэтому добавление новых файлов не требует
        правки диапазонов.

        Ключ 'processor' у первой зоны намеренно не переименован: на нём
        держится вся механика задержки DONE (Get-SkynetScanAnnotation и
        Show-SkynetBodyScan). Переименование ради косметики сломало бы её.
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

function Get-SkynetScanStage {
    <# .SYNOPSIS Этап сканирования по номеру исходного кадра. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [int] $FrameNumber = 0,
        [int] $LastFrameNumber = 215
    )
    foreach ($candidate in @(Get-SkynetScanStages -LastFrameNumber $LastFrameNumber)) {
        if ($FrameNumber -ge $candidate.Start -and $FrameNumber -le $candidate.End) { return $candidate }
    }
    return $null
}

function Get-SkynetScanAnnotation {
    <#
    .SYNOPSIS
        Текст одной строки аннотации слева от текущего Sixel-кадра.
    .DESCRIPTION
        Стрелка всегда направлена вправо — к изображению T-800. Активная
        строка мигает, а первая зона (NEURAL PROCESSOR SCAN) через заданное
        время заменяется на NEURAL PROCESSOR SCAN DONE. Финальный этап
        полного тела получает суффикс DONE после последнего кадра,
        подтверждая завершение всего сканирования.
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

function Get-SkynetCyberdyneScanBlock {
    <#
    .SYNOPSIS
        Итоговый блок диагностики Cyberdyne, который заменяет панель зон
        сканирования после того, как показан весь ряд кадров T-800.
    .DESCRIPTION
        Порядок строк повторяет финальный отчёт из «Терминатора»: заголовок с
        моделью и запуском диагностики, семь пройденных зон со статусом
        COMPLETE, затем итоговый статус и готовность к задаче. Блок выводится
        построчно, поэтому отчёт появляется так же прогрессивно, как прежняя
        панель, а не разом.
    .PARAMETER Width
        Ширина левой панели в знакоместах. Блок не обрезается молча: чем уже
        панель, тем короче формулировки (полная → компактная → сокращённая) —
        иначе Write-SkynetScanPanelRow срезал бы хвост «--> COMPLETE».
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([int] $Width = 52)

    $fullZones = @(
        'NEURAL PROCESSOR SCAN',
        'LEARNING COMPUTER SCAN',
        'OPTICAL/ACOUSTIC SENSOR SCAN',
        'POWER CORE SCAN',
        'HYPER-ALLOY COMBAT CHASSIS SCAN',
        'HYDRAULIC SERVO SCAN',
        'FULL-BODY SCAN'
    )
    $compactZones = @(
        'NEURAL PROCESSOR SCAN',
        'MEMORY CORE SCAN',
        'OPTICAL SENSOR SCAN',
        'POWER CORE SCAN',
        'CHASSIS SCAN',
        'HYDRAULIC SERVO SCAN',
        'FULL-BODY SCAN'
    )
    $tinyZones = @(
        'NEURAL PROC', 'MEMORY', 'OPTICAL', 'POWER CORE', 'CHASSIS',
        'HYDRAULIC', 'FULL BODY'
    )
    $fullWidth = 1
    foreach ($zone in $fullZones) { $fullWidth = [Math]::Max($fullWidth, ($zone + ' --> COMPLETE').Length) }
    $compactWidth = 1
    foreach ($zone in $compactZones) { $compactWidth = [Math]::Max($compactWidth, ($zone + ' --> COMPLETE').Length) }

    # Шапка, запуск диагностики и итог тоже переносятся/сокращаются: иначе на
    # узкой панели Write-SkynetScanPanelRow срезал бы их прямо посередине слова.
    $head = 'PROCESSOR SCANNING DONE CYBERDYNE SYSTEMS MODEL 101'
    $headLines = if ($Width -ge $head.Length) {
        @($head)
    } elseif ($Width -ge 27) {
        @('PROCESSOR SCANNING DONE', 'CYBERDYNE SYSTEMS MODEL 101')
    } else {
        @('PROCESSOR SCANNING', 'CYBERDYNE 101')
    }
    $diagnostics = if ($Width -ge 32) { 'INITIATING SYSTEM DIAGNOSTICS...' } else { 'INITIATING DIAG...' }
    $statusLine = if ($Width -ge 27) { 'STATUS: ALL SYSTEMS NOMINAL' } else { 'STATUS: NOMINAL' }

    $status = ' --> COMPLETE'
    $zones = if ($Width -ge $fullWidth) { $fullZones }
    elseif ($Width -ge $compactWidth) { $compactZones }
    else {
        # Совсем узкое окно: названия зон и статус сокращаются.
        $status = ' OK'
        $tinyZones
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($h in $headLines) { $lines.Add($h) }
    $lines.Add($diagnostics)
    $lines.Add('')
    foreach ($zone in $zones) { $lines.Add("$zone$status") }
    $lines.Add('')
    $lines.Add($statusLine)
    $lines.Add('MISSION READY.')
    # Без запятой перед ToArray(): «return ,$arr» отдало бы массив-массив, и
    # вызывающий @( ... ) получил бы один вложенный элемент вместо строк блока.
    return $lines.ToArray()
}




function Wait-SkynetPrologueDelay {
    <#
    .SYNOPSIS
        Точное ожидание для коротких интервалов текстовой прокрутки.
    .DESCRIPTION
        Start-Sleep в Windows обычно округляет значения меньше 15 мс до
        таймерного тика Powershell, поэтому 2 и 4 мс могут фактически совпасть.
        Здесь длинная часть ожидания отдаётся планировщику, а последние 8 мс
        выдерживаются через Stopwatch/SpinWait. Это сохраняет реальную разницу
        между 2 и 4 мс и не меняет интервалы Sixel-кадров.
    #>
    [CmdletBinding()]
    param([int] $Milliseconds = 0)
    if ($Milliseconds -le 0) { return }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $target = [double]$Milliseconds
    if ($target -gt 8) {
        $yieldMs = [int][Math]::Floor($target - 8)
        if ($yieldMs -gt 0) { Start-Sleep -Milliseconds $yieldMs }
    }
    while ($watch.Elapsed.TotalMilliseconds -lt $target) {
        [System.Threading.Thread]::SpinWait(1)
    }
}

function Test-SkynetPrologueReady {
    <# .SYNOPSIS Можно ли играть анимацию (ANSI есть, не -Instant). #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $cfg = $GLOBAL:_SkyNetCore
    if (-not $cfg) { return $false }
    if ($cfg.Instant) { return $false }
    return [bool] $cfg.AnsiOk
}

function Format-SkynetDottedLine {
    <#
    .SYNOPSIS
        "LABEL .................... VALUE" — подпись, точки-лидеры, значение.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Label = '',
        [string] $Value = '',
        [int] $Width = 42,
        [string] $Prefix = ''
    )
    $used = $Prefix.Length + $Label.Length + 1 + $Value.Length
    $dots = $Width - $used
    if ($dots -lt 3) { $dots = 3 }
    return "$Prefix$Label " + ('.' * $dots) + " $Value"
}

function Invoke-SkynetSound {
    <#
    .SYNOPSIS
        Безопасный вызов звука из любой сцены.
    .DESCRIPTION
        Модуль SkyNet.Audio необязателен: если он не загружен или звук
        выключен, вызов просто ничего не делает и шоу идёт как обычно.
        Команда ищется один раз и кэшируется — иначе Get-Command в горячем
        цикле вывода ТТХ стоил бы дороже, чем сам звук.
    #>
    [CmdletBinding()]
    param(
        [string] $Name = '',
        [int] $ThrottleMs = 0
    )
    if (-not $script:SoundCommand) { return }
    try { & $script:SoundCommand -Name $Name -ThrottleMs $ThrottleMs } catch { }
}

$script:SoundCommand = $null
$script:SoundChecked = $false

function Initialize-SkynetSound {
    <#
    .SYNOPSIS
        Подготовить звуковой слой один раз в начале шоу.
    .DESCRIPTION
        Загружает пакет сэмплов и запускает фоновый гул. Любая ошибка не
        прерывает шоу: сцена продолжается без звука, причина пишется в лог.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:SoundChecked) {
        $script:SoundChecked = $true
        $script:SoundCommand = Get-Command 'Play-SkynetSound' -ErrorAction SilentlyContinue
    }
    if (-not $script:SoundCommand) {
        try { Write-SkynetLog -Message 'Prologue: модуль SkyNet.Audio не загружен — шоу идёт без звука.' -Level 'DEBUG' -Module 'Prologue' } catch { }
        return $false
    }
    $ok = $false
    try { $ok = [bool](Initialize-SkynetAudio) } catch { $ok = $false }
    if (-not $ok) {
        try { Write-SkynetLog -Message 'Prologue: звук недоступен (нет пакета, устройства или выключен в конфиге).' -Level 'DEBUG' -Module 'Prologue' } catch { }
        return $false
    }
    try { Start-SkynetAmbience } catch { }
    try {
        $loaded = 0
        try { $loaded = (Get-SkynetAudioStats).Loaded } catch { }
        Write-SkynetLog -Message "Prologue: звук включён, загружено фраз — $loaded." -Level 'INFO' -Module 'Prologue'
    } catch { }
    return $true
}

function Write-SkynetGlitchLine {
    <#
    .SYNOPSIS
        Напечатать строку, которая иногда сначала «ломается», потом «перескакивает»
        и только затем сама «чинится» (система ещё не полностью загрузилась).
    .DESCRIPTION
        Для plain-scrolling текста (SSH-сессия, PS-промпт) на трёх фазах:
        1) печатается искажённая версия той же длины;
        2) иногда (JumpChance) курсор поднимается на строку вверх и та же
           побитая строка печатается со сдвигом вбок — «перескок» каретки;
        3) курсор снова вверх, печатается верная строка поверх — самовосстановление.
    .PARAMETER GlitchChance
        Вероятность того, что строка вообще сломается (0..1).
    .PARAMETER JumpChance
        Вероятность «перескока» внутри уже сломанной строки (0..1).
    #>
    [CmdletBinding()]
    param(
        [string] $Text = '',
        [string] $Color = '',
        [double] $GlitchChance = 0.18,
        [double] $JumpChance = 0.35
    )
    if (-not $Color) { $Color = $GLOBAL:ColPrologue }
    $ready = Test-SkynetPrologueReady
    $roll = if ($ready) { Get-Random -Minimum 0.0 -Maximum 1.0 } else { 1.0 }

    if ($ready -and $roll -lt $GlitchChance) {
        # Сбой слышен раньше, чем виден: так «дёрганье» системы читается
        # на слух даже в периферийном зрении.
        Invoke-SkynetSound -Name 'glitch'
        $chars = $Text.ToCharArray()
        for ($i = 0; $i -lt $chars.Length; $i++) {
            if ($chars[$i] -ne ' ' -and (Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.5) {
                $chars[$i] = $script:PrologueNoiseChars[(Get-Random -Minimum 0 -Maximum $script:PrologueNoiseChars.Length)]
            }
        }
        $garbled = -join $chars
        [Console]::Out.WriteLine("$Color$garbled$($GLOBAL:ColReset)")
        Start-Sleep -Milliseconds (Get-Random -Minimum 60 -Maximum 180)
        $esc = Get-SkynetPrologueEsc
        [Console]::Out.Write("${esc}[1A`r${esc}[K")

        # Перескок: та же побитая строка, но съехавшая вбок и на соседнюю позицию —
        # «система ещё не загрузилась». Печатается поверх уже напечатанного глюка.
        if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $JumpChance) {
            $shift = Get-Random -Minimum 1 -Maximum 4
            [Console]::Out.WriteLine("$Color" + (' ' * $shift) + $garbled + $($GLOBAL:ColReset))
            Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 140)
            [Console]::Out.Write("${esc}[1A`r${esc}[K")
        }
    }
    [Console]::Out.WriteLine("$Color$Text$($GLOBAL:ColReset)")
    # Звук вывода строки. Фриз озвучен выше, а обычный набор строки («HOST
    # SCAN», «CPU...», «CONNECTION OVERRIDE») шёл молча.
    Invoke-SkynetSound -Name 'step' -ThrottleMs 140
}

function Get-SkynetWindowsEnglishName {
    <#
    .SYNOPSIS
        Английское название установленной Windows: "Windows 11 Home Single Language 25H2".
    .DESCRIPTION
        Win32_OperatingSystem.Caption локализован ("Майкрософт Windows 11 Домашняя…"),
        а реестровый ProductName на Windows 11 НАВСЕГДА остаётся "Windows 10 …" — это
        давний баг самой Windows. Поэтому название собирается из двух надёжных
        источников: номер сборки задаёт поколение (22000+ → Windows 11), а
        EditionID из реестра — редакцию. Оба значения не зависят от языка Windows.
        Как страховка из результата вырезаются все не-ASCII символы, поэтому даже
        для неизвестной редакции строка останется английской.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [int]    $BuildNumber = 0,
        [string] $Caption      = ''
    )

    # Поколение — по номеру сборки, а не по подписи.
    $product = 'Windows'
    if ($BuildNumber -ge 22000) { $product = 'Windows 11' }
    elseif ($BuildNumber -ge 10240) { $product = 'Windows 10' }
    elseif ($BuildNumber -gt 0) { $product = 'Windows ' + [Math]::Floor($BuildNumber / 10000) }

    # Редакция — из EditionID: значения не локализованы.
    $editionId = ''
    $displayVersion = ''
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $props = Get-ItemProperty -Path $key -ErrorAction Stop
        $editionId = [string] $props.EditionID
        $displayVersion = [string] $props.DisplayVersion
        if (-not $BuildNumber) { $BuildNumber = [int] $props.CurrentBuildNumber }
    } catch { }

    $edition = switch ($editionId) {
        'Core'                    { 'Home' }
        'CoreSingleLanguage'      { 'Home Single Language' }
        'CoreCountrySpecific'     { 'Home Single Language' }
        'CoreIot'                 { 'Home' }
        'Professional'            { 'Pro' }
        'ProfessionalWorkstation' { 'Pro for Workstations' }
        'ProfessionalEducation'   { 'Pro Education' }
        'Enterprise'              { 'Enterprise' }
        'EnterpriseS'             { 'Enterprise' }
        'IoTEnterprise'           { 'IoT Enterprise' }
        'Education'               { 'Education' }
        'Standard'                { 'Standard' }
        'Server'                  { 'Server' }
        'ServerStandard'          { 'Server Standard' }
        'ServerDatacenter'        { 'Server Datacenter' }
        default                   { '' }
    }

    # Неизвестная редакция: имя целиком на не-ASCII (русская локализация).
    if (-not $edition) {
        $latin = [regex]::Replace($Caption, '[^\x20-\x7E]', '')
        if ($latin -match '\b(Home|Pro|Enterprise|Education|Standard|Server)\b') { $edition = $Matches[1] }
    }

    $name = $product
    if ($edition) { $name += ' ' + $edition }
    if ($displayVersion -match '^[0-9A-Za-z.]+$') { $name += ' ' + $displayVersion }
    return $name
}

function Get-SkynetLocalSystemInfo {
    <#
    .SYNOPSIS
        Собрать безопасный read-only профиль локального компьютера для вступления.
    .DESCRIPTION
        Используются только локальные переменные окружения и Win32_* CIM-запросы.
        Серийные номера, MAC/IP-адреса, домен и учётные данные не запрашиваются.
        Значения очищаются от управляющих символов; при ошибке используется UNKNOWN.
        Название Windows выводится по-английски независимо от языка системы.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:SkynetLocalSystemInfo) { return $script:SkynetLocalSystemInfo }
    $result = [ordered]@{
        System   = 'UNKNOWN'
        Host     = 'UNKNOWN'
        User     = 'UNKNOWN'
        Cpu      = 'UNKNOWN'
        Memory   = 'UNKNOWN'
        Gpu      = 'UNKNOWN'
        Terminal = 'UNKNOWN'
        Display  = 'UNKNOWN'
    }
    $clean = {
        param([object] $Value, [int] $MaxLength = 72)
        if ($null -eq $Value) { return 'UNKNOWN' }
        $text = [regex]::Replace([string] $Value, '[\x00-\x1F\x7F]', ' ')
        $text = [regex]::Replace($text, '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { return 'UNKNOWN' }
        if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength).Trim() }
        return $text
    }

    try {
        $os = @(Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1)[0]
        if ($os) {
            $caption = [string] $os.Caption
            $version = [string] $os.Version
            $build = [string] $os.BuildNumber
            # Название — строго по-английски: Caption локализован под язык
            # системы, а имя поколения/редакции собирается из номера сборки
            # и EditionID (см. Get-SkynetWindowsEnglishName).
            $system = Get-SkynetWindowsEnglishName -BuildNumber ([int] $build) -Caption $caption
            if ($version) { $system += ' ' + $version }
            if ($build) { $system += ' (BUILD ' + $build + ')' }
            $result.System = & $clean $system 88
        }
    } catch { }

    $hostName = [string] $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($hostName)) {
        try { $hostName = [System.Environment]::MachineName } catch { }
    }
    $result.Host = & $clean $hostName 48

    $userName = [string] $env:USERNAME
    if ([string]::IsNullOrWhiteSpace($userName)) {
        try { $userName = [System.Environment]::UserName } catch { }
    }
    $result.User = & $clean $userName 48

    try {
        $cpu = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1)[0]
        if ($cpu) { $result.Cpu = & $clean $cpu.Name 72 }
    } catch { }

    try {
        $computer = @(Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1)[0]
        if ($computer -and [double] $computer.TotalPhysicalMemory -gt 0) {
            $memoryGb = [double] $computer.TotalPhysicalMemory / 1GB
            # InvariantCulture обязателен: на русской локали '-f' печатал бы
            # "63,7 GB" — запятая выглядела бы как опечатка в строке ТТХ.
            $result.Memory = ('{0:0.0} GB' -f $memoryGb).Replace(',', '.')
        }
    } catch { }

    $video = @()
    try { $video = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop) } catch { }
    $gpu = $video |
        Where-Object { $_.Name -and $_.Name -notmatch '(?i)basic display|remote display' } |
        Sort-Object -Property @{ Expression = { if ($_.AdapterRAM) { [double] $_.AdapterRAM } else { 0.0 } }; Descending = $true } |
        Select-Object -First 1
    if (-not $gpu -and $video.Count -gt 0) { $gpu = $video[0] }
    if ($gpu) { $result.Gpu = & $clean $gpu.Name 72 }

    if ($env:WT_SESSION) { $result.Terminal = 'WINDOWS TERMINAL' }
    else { $result.Terminal = 'POWERSHELL / CONSOLE' }

    if ($video.Count -gt 0) {
        $display = $video | Where-Object {
            $_.CurrentHorizontalResolution -gt 0 -and $_.CurrentVerticalResolution -gt 0
        } | Select-Object -First 1
        if ($display) {
            $displayText = '{0}x{1}' -f $display.CurrentHorizontalResolution, $display.CurrentVerticalResolution
            if ($display.CurrentRefreshRate -gt 0) { $displayText += ' @ ' + $display.CurrentRefreshRate + 'HZ' }
            $result.Display = & $clean $displayText 48
        }
    }
    if ($result.Display -eq 'UNKNOWN' -and $env:WT_SESSION) { $result.Display = 'WINDOWS TERMINAL' }
    elseif ($result.Display -eq 'UNKNOWN') { $result.Display = 'COMPATIBLE CONSOLE' }

    $script:SkynetLocalSystemInfo = $result
    return $result
}

function Show-SkynetSshIntro {
    <#
    .SYNOPSIS
        Фальшивая SSH-сессия: обнаружение хоста, характеристики, "SYSTEM ONLINE".
    .PARAMETER Cpu / Memory / Gpu / Terminal / Display
        Необязательные переопределения для отдельного вызова. Если значения не
        заданы, они берутся из безопасного локального профиля компьютера.
    .PARAMETER System / HostName / UserName
        Система, имя хоста и имя пользователя для блока HOST SCAN INITIATED.
    #>
    [CmdletBinding()]
    param(
        [string] $Cpu = '',
        [string] $Memory = '',
        [string] $Gpu = '',
        [string] $Terminal = '',
        [string] $Display = '',
        [string] $System = '',
        [string] $HostName = '',
        [string] $UserName = '',
        [int] $LineDelayMs = 220,
        [int] $OnlineBlinks = 6,
        [int] $OnlineOnMs = 220,
        [int] $OnlineOffMs = 140
    )
    if ($OnlineBlinks -lt 1) { $OnlineBlinks = 1 }
    if ($OnlineOnMs -lt 20) { $OnlineOnMs = 20 }
    if ($OnlineOffMs -lt 20) { $OnlineOffMs = 20 }
    $c = $GLOBAL:ColPrologue
    $esc = Get-SkynetPrologueEsc
    $localInfo = $null
    try { $localInfo = Get-SkynetLocalSystemInfo } catch { $localInfo = $null }
    if ($localInfo) {
        if (-not $Cpu) { $Cpu = [string] $localInfo.Cpu }
        if (-not $Memory) { $Memory = [string] $localInfo.Memory }
        if (-not $Gpu) { $Gpu = [string] $localInfo.Gpu }
        if (-not $Terminal) { $Terminal = [string] $localInfo.Terminal }
        if (-not $Display) { $Display = [string] $localInfo.Display }
        if (-not $System) { $System = [string] $localInfo.System }
        if (-not $HostName) { $HostName = [string] $localInfo.Host }
        if (-not $UserName) { $UserName = [string] $localInfo.User }
    }
    if (-not $Cpu) { $Cpu = 'UNKNOWN' }
    if (-not $Memory) { $Memory = 'UNKNOWN' }
    if (-not $Gpu) { $Gpu = 'UNKNOWN' }
    if (-not $Terminal) { $Terminal = 'UNKNOWN' }
    if (-not $Display) { $Display = 'UNKNOWN' }
    if (-not $System) { $System = 'UNKNOWN' }
    if (-not $HostName) { $HostName = 'UNKNOWN' }
    if (-not $UserName) { $UserName = 'UNKNOWN' }

    if (Test-SkynetPrologueReady) { [Console]::Out.Write("${esc}[1;1H") }
    Write-SkynetGlitchLine -Text '[ HOST SCAN INITIATED ]' -Color $c
    Start-Sleep -Milliseconds $LineDelayMs
    Write-SkynetGlitchLine -Text (Format-SkynetDottedLine -Label 'SYSTEM' -Value $System -Width 46 -Prefix '  ') -Color $c
    Start-Sleep -Milliseconds $LineDelayMs
    Write-SkynetGlitchLine -Text (Format-SkynetDottedLine -Label 'HOST' -Value $HostName -Width 46 -Prefix '  ') -Color $c
    Start-Sleep -Milliseconds $LineDelayMs
    Write-SkynetGlitchLine -Text (Format-SkynetDottedLine -Label 'USER' -Value $UserName -Width 46 -Prefix '  ') -Color $c
    Start-Sleep -Milliseconds $LineDelayMs
    # Квадратные скобки в служебной строке не должны повреждаться глитчем.
    Write-SkynetGlitchLine -Text '[ SSH SESSION ESTABLISHED ]' -Color $c -GlitchChance 0 -JumpChance 0
    Start-Sleep -Milliseconds $LineDelayMs
    Write-SkynetGlitchLine -Text '[ REMOTE TERMINAL DETECTED ]' -Color $c
    Start-Sleep -Milliseconds ($LineDelayMs * 2)
    [Console]::Out.WriteLine('')
    Write-SkynetGlitchLine -Text '    scanning local system...' -Color $c
    Start-Sleep -Milliseconds $LineDelayMs

    $specs = @(
        @{ Label = 'CPU';     Value = $Cpu }
        @{ Label = 'MEMORY';  Value = $Memory }
        @{ Label = 'GPU';     Value = $Gpu }
        @{ Label = 'TERMINAL';Value = $Terminal }
        @{ Label = 'DISPLAY'; Value = $Display }
    )
    foreach ($s in $specs) {
        Write-SkynetGlitchLine -Text (Format-SkynetDottedLine -Label $s.Label -Value $s.Value -Width 40 -Prefix '    ') -Color $c
        Start-Sleep -Milliseconds $LineDelayMs
    }
    [Console]::Out.WriteLine('')
    Start-Sleep -Milliseconds ($LineDelayMs * 2)
    $onlineText = "       `u{2591}`u{2592}`u{2593} SYSTEM ONLINE `u{2593}`u{2592}`u{2591}"
    # CursorPosition.Y в Windows Terminal — координата с нуля, а ANSI-строка
    # нумеруется с единицы. Поэтому фиксируем реальную строку и не сдвигаем
    # последующие prompt-строки.
    $onlineRow = [int]([Math]::Max(1, $Host.UI.RawUI.CursorPosition.Y + 1))
    # Подтверждение выхода в сеть: короткий сигнал на каждое мигание, иначе
    # надпись «SYSTEM ONLINE» появляется в полной тишине.
    for ($blink = 0; $blink -lt $OnlineBlinks; $blink++) {
        if (Test-SkynetPrologueReady) {
            Invoke-SkynetSound -Name 'online'
            [Console]::Out.Write("${esc}[${onlineRow};1H$($GLOBAL:ColPrologueBright)$onlineText$($GLOBAL:ColReset)")
            Start-Sleep -Milliseconds $OnlineOnMs
            [Console]::Out.Write("${esc}[${onlineRow};1H${esc}[2K")
            Start-Sleep -Milliseconds $OnlineOffMs
        } else {
            [Console]::Out.WriteLine($onlineText)
            break
        }
    }
    if (Test-SkynetPrologueReady) {
        [Console]::Out.Write("${esc}[${onlineRow};1H$($GLOBAL:ColPrologueBright)$onlineText$($GLOBAL:ColReset)")
        Start-Sleep -Milliseconds 500
        # Возвращаем каретку в начало следующей строки, чтобы following
        # PowerShell prompts снова начинались с левого края.
        [Console]::Out.Write("${esc}[$($onlineRow + 1);1H")
    }
    # Два полных пустых абзаца отделяют boot-блок от следующей сцены.
    [Console]::Out.WriteLine('')
    [Console]::Out.WriteLine('')
}

function Show-SkynetTerminalHijack {
    <#
    .SYNOPSIS
        Обычный PowerShell-промпт внезапно «перехватывается» удалённой стороной.
    .PARAMETER NormalUser
        Имя в обычных строках-промптах. По умолчанию берётся из локального
        профиля Windows, поэтому фиксированное имя не выводится.
    .PARAMETER HijackUser
        Имя в момент перехвата; по умолчанию используется текущий локальный пользователь.
    #>
    [CmdletBinding()]
    param(
        [string] $NormalUser = '',
        [string] $HijackUser = '',
        [int] $BlankPrompts = 4,
        [int] $PromptDelayMs = 500
    )
    if (-not $NormalUser -or -not $HijackUser) {
        try {
            $localUser = [string](Get-SkynetLocalSystemInfo).User
            if ($localUser -and $localUser -ne 'UNKNOWN') {
                if (-not $NormalUser) { $NormalUser = $localUser }
                if (-not $HijackUser) { $HijackUser = $localUser }
            }
        } catch { }
    }
    if (-not $NormalUser) { $NormalUser = [string]$env:USERNAME }
    if (-not $HijackUser) { $HijackUser = $NormalUser }
    if (-not $NormalUser) { $NormalUser = 'user' }
    $dim = $GLOBAL:ColPrologueDim

    # Пустые промпты шли абсолютно молча: ни одного звукового курка на всём
    # цикле. Теперь каждый промпт — короткий щелчок терминала, а момент
    # перехвата (смена цвета и курсор) получает собственный акцент.
    for ($i = 0; $i -lt $BlankPrompts; $i++) {
        [Console]::Out.WriteLine("$dim" + "PS C:\Users\$NormalUser>" + "$($GLOBAL:ColReset)")
        Invoke-SkynetSound -Name 'prompt'
        Start-Sleep -Milliseconds $PromptDelayMs
    }

    Start-Sleep -Milliseconds 300
    $hijackPrompt = "PS C:\Users\$HijackUser> "
    $esc = Get-SkynetPrologueEsc
    # Сам момент захвата: характерный «перехват» линии перед вводом.
    Invoke-SkynetSound -Name 'hijack'
    [Console]::Out.Write("$($GLOBAL:ColPrologueBright)$hijackPrompt")
    foreach ($ch in '_'.ToCharArray()) { [Console]::Out.Write($ch) }
    [Console]::Out.Write("$($GLOBAL:ColReset)")
    [Console]::Out.WriteLine('')
    Start-Sleep -Milliseconds 700

    [Console]::Out.WriteLine('')
    Write-SkynetGlitchLine -Text 'CONNECTION OVERRIDE' -Color $GLOBAL:ColPrologueAlert -GlitchChance 0.5
    # Отдельный акцент на самом перехвате: строка уже озвучена глитчем выше.
    Invoke-SkynetSound -Name 'override'
    [Console]::Out.WriteLine('')
    Start-Sleep -Milliseconds 200

    $lines = @(
        @{ Label = 'PowerShell';   Value = '[BYPASSED]' }
        @{ Label = 'USER SESSION'; Value = '[ACQUIRED]' }
        @{ Label = 'REMOTE HOST';  Value = '[CONTROLLED]' }
    )
    foreach ($l in $lines) {
        Write-SkynetGlitchLine -Text (Format-SkynetDottedLine -Label $l.Label -Value $l.Value -Width 38) -Color $GLOBAL:ColPrologueAlert -GlitchChance 0.35
        Start-Sleep -Milliseconds 350
    }
    Start-Sleep -Milliseconds 900
}

function Get-SkynetScrambledAnsiLine {
    <#
    .SYNOPSIS
        Частично «зашумить» уже раскрашенную ANSI-строку, сохранив цвет по клеткам.
    .DESCRIPTION
        Как ConvertTo-SkynetMirroredLine (SkyNet.T800) разбирает строку на клетки
        "цвет+символ", но вместо разворота — заменяет случайную долю НЕпробельных
        клеток на шумовой символ. Используется для сборки логотипа из шума:
        сама раскраска кадра не трогается, дребезжат только видимые глифы.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Text = '',
        [double] $NoiseFraction = 0.5
    )
    if ([string]::IsNullOrEmpty($Text) -or $NoiseFraction -le 0) { return $Text }
    $rx = [regex] '\x1b\[[0-9;?]*[a-zA-Z]'
    $out = [System.Text.StringBuilder]::new()
    $i = 0
    while ($i -lt $Text.Length) {
        $m = $rx.Match($Text, $i)
        if ($m.Success -and $m.Index -eq $i) {
            [void]$out.Append($m.Value)
            $i += $m.Length
            continue
        }
        $ch = $Text[$i]
        if ($ch -ne ' ' -and (Get-Random -Minimum 0.0 -Maximum 1.0) -lt $NoiseFraction) {
            [void]$out.Append($script:PrologueNoiseChars[(Get-Random -Minimum 0 -Maximum $script:PrologueNoiseChars.Length)])
        } else {
            [void]$out.Append($ch)
        }
        $i++
    }
    return $out.ToString()
}

function Show-SkynetLogoNoiseReveal {
    <#
    .SYNOPSIS
        Логотип «собирается» из шума построчно (волна идёт сверху вниз).
    .DESCRIPTION
        Промежуточные кадры строятся без кэша, поэтому шум действительно меняется.
        При -SkipFinalSymbol чистый символьный кадр не выводится: вызывающий
        код сразу передаёт экран финальному Sixel-рендереру.
    .PARAMETER Lines
        Готовый раскрашенный кадр логотипа (как из Get-SkynetLogoFrame -Sixel:$false).
    .PARAMETER DurationMs
        Общее время сборки из шума.
    .PARAMETER HoldMs
        Сколько держать чистый логотип после сборки (мс).
    .PARAMETER SkipFinalSymbol
        Не выводить чистый символьный кадр: следующий вызов сразу передаёт
        экран финальному Sixel-рендереру.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Lines,
        [int] $TopRow = 1,
        [int] $DurationMs = 3200,
        [int] $HoldMs = 1400,
        [switch] $SkipFinalSymbol
    )
    if ($Lines.Count -eq 0) { return }
    if (-not (Test-SkynetPrologueReady)) {
        if (-not $SkipFinalSymbol) {
            Write-SkynetFrame -Lines $Lines -TopRow $TopRow -Factor 1.0
            if ($HoldMs -gt 0) { Start-Sleep -Milliseconds $HoldMs }
        }
        return
    }
    $useGlitch = [bool] (Get-Command Get-SkynetJitterOffsets -ErrorAction SilentlyContinue)
    if ($useGlitch) { $useGlitch = [bool] (Test-SkynetGlitchReady) }
    $geo = Get-SkynetConsoleGeometry
    $minVisible = [int]::MaxValue
    $maxVisible = 0
    foreach ($line in $Lines) {
        $plain = [regex]::Replace([string]$line, '\x1b\[[0-9;?]*[a-zA-Z]', '')
        $trimmed = $plain.Trim(' ')
        if ($trimmed.Length -le 0) { continue }
        $leading = $plain.Length - $plain.TrimStart(' ').Length
        $right = $leading + $trimmed.Length
        if ($leading -lt $minVisible) { $minVisible = $leading }
        if ($right -gt $maxVisible) { $maxVisible = $right }
    }
    if ($minVisible -eq [int]::MaxValue) { $minVisible = 0 }
    if ($maxVisible -le $minVisible) { $maxVisible = $minVisible + 1 }
    $contentWidth = $maxVisible - $minVisible
    $centerCol = [Math]::Max(1, [int](($geo.Width - $contentWidth) / 2) + 1 - $minVisible)
    $frameBaseCol = [Math]::Max(1, $centerCol)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $tickMs = 55
    $sweepLines = [Math]::Max(4, $Lines.Count + 6)
    $nextShift = 90

    while ($watch.ElapsedMilliseconds -lt $DurationMs) {
        $now = [double] $watch.ElapsedMilliseconds
        $progress = [Math]::Min(1.0, $now / [double] $DurationMs)
        $sweep = $progress * $sweepLines

        $noisy = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            # Волна сборки: строки выше неё уже чистые, ниже — ещё в шуме.
            $rowProgress = [Math]::Min(1.0, [Math]::Max(0.0, ($sweep - $i) / 5.0))
            $noise = [Math]::Pow(1.0 - $rowProgress, 1.5)
            $noisy.Add((Get-SkynetScrambledAnsiLine -Text $Lines[$i] -NoiseFraction $noise))
        }

        $offsets = $null
        if ($useGlitch -and $progress -lt 0.90 -and $now -ge $nextShift) {
            # Сильные горизонтальные tear-сдвиги именно полосами, а не только
            # отдельными строками. Несколько таких эпизодов повторяются во время
            # сборки, поэтому логотип выглядит как восстанавливающийся видеосигнал.
            $offsets = Get-SkynetJitterOffsets -Count $noisy.Count -Amplitude 12 -Band
            $nextShift = $now + (Get-Random -Minimum 160 -Maximum 360)
        }
        if ($offsets) {
            # Фриз/разрыв логотипа. Раньше здесь был шаблон 'glitch*', который
            # выбирал случайный файл из glitch/glitch1/glitch2 — сборка логотипа
            # звучала то своим, то чужим сэмплом. Теперь строго курок 'glitch'.
            Invoke-SkynetSound -Name 'glitch' -ThrottleMs 260
            Write-SkynetGlitchFrame -Lines $noisy.ToArray() -TopRow $TopRow -BaseCol $frameBaseCol -Offsets $offsets
        } else {
            Write-SkynetFrame -Lines $noisy.ToArray() -TopRow $TopRow -Factor 1.0 -BaseCol $frameBaseCol
        }

        $spent = [double] $watch.ElapsedMilliseconds - $now
        $rest = $tickMs - [int] $spent
        if ($rest -gt 0) { Start-Sleep -Milliseconds $rest }
    }
    if (-not $SkipFinalSymbol) {
        # Перед финальным кадром убираем возможные остатки tear-сдвигов,
        # чтобы восстановленный логотип был чистым и действительно центрированным.
        Clear-SkynetFrame -LineCount $Lines.Count -TopRow $TopRow
        Write-SkynetFrame -Lines $Lines -TopRow $TopRow -Factor 1.0 -BaseCol $frameBaseCol
        if ($HoldMs -gt 0) { Start-Sleep -Milliseconds $HoldMs }
    }
}

function Show-SkynetOnlineBlink {
    <#
    .SYNOPSIS
        Мигающая надпись по центру строки (по умолчанию "SKYNET SYSTEM ONLINE").
    .DESCRIPTION
        При DurationMs > 0 функция мигает ровно заданный интервал и оставляет
        надпись включённой до его конца. Это позволяет ограничить всё время
        финального Sixel-кадра вместе с ONLINE-надписью, а не добавлять вторую
        паузу поверх мигания.
    #>
    [CmdletBinding()]
    param(
        [string] $Text = 'SKYNET SYSTEM ONLINE',
        [int] $Row = 0,
        [int] $Blinks = 4,
        [int] $OnMs = 420,
        [int] $OffMs = 220,
        [int] $DurationMs = 0,
        [int] $FinalHoldMs = 700
    )
    $geo = Get-SkynetConsoleGeometry
    if ($Row -le 0) { $Row = [int]($geo.Height / 2) }
    $col = [Math]::Max(1, [int](($geo.Width - $Text.Length) / 2) + 1)
    $esc = Get-SkynetPrologueEsc
    $showText = {
        [Console]::Out.Write("${esc}[${Row};${col}H$($GLOBAL:ColPrologueBright)$($GLOBAL:ColBold)$Text$($GLOBAL:ColReset)")
    }
    $hideText = {
        [Console]::Out.Write("${esc}[${Row};${col}H" + (' ' * $Text.Length) + "${esc}[K")
    }

    if (-not (Test-SkynetPrologueReady)) {
        [Console]::Out.WriteLine($Text)
        return
    }

    # Главный акцент шоу — звучит ровно в момент появления надписи.
    Invoke-SkynetSound -Name 'online'

    if ($DurationMs -gt 0) {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $visible = $false
        while ($watch.ElapsedMilliseconds -lt $DurationMs) {
            if (-not $visible) {
                & $showText
                $visible = $true
                $waitMs = [Math]::Min($OnMs, [int]($DurationMs - $watch.ElapsedMilliseconds))
            } else {
                & $hideText
                $visible = $false
                $waitMs = [Math]::Min($OffMs, [int]($DurationMs - $watch.ElapsedMilliseconds))
            }
            if ($waitMs -gt 0) { Start-Sleep -Milliseconds $waitMs }
        }
        & $showText
        $remaining = [int]($DurationMs - $watch.ElapsedMilliseconds)
        if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
        return
    }

    for ($b = 0; $b -lt $Blinks; $b++) {
        & $showText
        Start-Sleep -Milliseconds $OnMs
        & $hideText
        Start-Sleep -Milliseconds $OffMs
    }
    & $showText
    if ($FinalHoldMs -gt 0) { Start-Sleep -Milliseconds $FinalHoldMs }
}

function Show-SkynetRadarBoot {
    <#
    .SYNOPSIS
        Тёмный экран → "GLOBAL DEFENSE NETWORK / INITIALIZATION / <время> /
        TARGET ACQUISITION SYSTEM / ONLINE" → "> SEARCHING FOR UNIT...".
    #>
    [CmdletBinding()]
    param(
        [int] $DarkMs = 600,
        [int] $LineDelayMs = 253,
        [double] $Speed = 1.5
    )

    $Speed = [Math]::Max(1.0, $Speed)
    $geo = Get-SkynetConsoleGeometry
    Clear-SkynetFrame -LineCount $geo.Height -TopRow 1
    # Пинг радара на пустом экране: пауза становится «радарной тишиной».
    Invoke-SkynetSound -Name 'radar'
    Start-Sleep -Milliseconds ([int][Math]::Round($DarkMs / $Speed))

    $time = Get-Date -Format 'HH:mm:ss'
    $block = @('GLOBAL DEFENSE NETWORK', '', 'INITIALIZATION', '', $time, '', 'TARGET ACQUISITION SYSTEM', 'ONLINE')
    $top = [Math]::Max(1, [int](($geo.Height - $block.Count) / 2) - 3)
    $esc = Get-SkynetPrologueEsc
    for ($i = 0; $i -lt $block.Count; $i++) {
        $text = [string] $block[$i]
        if ($text) {
            $col = [Math]::Max(1, [int](($geo.Width - $text.Length) / 2))
            if (Test-SkynetPrologueReady) {
                [Console]::Out.Write("${esc}[$($top + $i);${col}H$($GLOBAL:ColPrologue)$text$($GLOBAL:ColReset)")
            } else {
                [Console]::Out.WriteLine($text)
            }
            # Тот же звук, что и на строках отчёта: оптимальный вариант для всех
            # строк этого блока. Пустые строки — разрядка, они молчат.
            Invoke-SkynetSound -Name 'radar_line'
        }
        Start-Sleep -Milliseconds ([int][Math]::Round($LineDelayMs / $Speed))
    }
    Start-Sleep -Milliseconds ([int][Math]::Round(467 / $Speed))

    $searchRow = $top + $block.Count + 2
    $lines = @('> SEARCHING FOR UNIT...', '> UNIT TYPE: T-800', '> STATUS: DEPLOYMENT READY')
    foreach ($l in $lines) {
        if (Test-SkynetPrologueReady) {
            [Console]::Out.Write("${esc}[${searchRow};1H$($GLOBAL:ColPrologue)$l$($GLOBAL:ColReset)")
        } else {
            [Console]::Out.WriteLine($l)
        }
        $searchRow++
        # Звук на КАЖДУЮ напечатанную строку, без троттлинга: строки идут
        # плотно (~222 мс), и задержка здесь означала бы, что половина отчёта
        # прозвучит молча. Замена файла — одна правка в $script:Cues.
        Invoke-SkynetSound -Name 'radar_line'
        Start-Sleep -Milliseconds ([int][Math]::Round(333 / $Speed))
    }
    Start-Sleep -Milliseconds ([int][Math]::Round(600 / $Speed))
}

function Get-SkynetT800ScanLines {
    <#
    .SYNOPSIS
        ТТХ T-800 (те же данные, что и в оранжевой панели SkyNet.T800) как
        строки сканирования вида "> LABEL .......... VALUE" для белого пролога.
    .DESCRIPTION
        Единый источник данных — Get-SkynetT800Specs (SkyNet.T800): здесь
        только другое ОФОРМЛЕНИЕ тех же фактов, без дублирования текста ТТХ.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([int] $Width = 46)
    if (-not (Get-Command Get-SkynetT800Specs -ErrorAction SilentlyContinue)) { return @() }
    $specs = Get-SkynetT800Specs
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($s in $specs) {
        $value = if ($s.Gen) { [string] (& $s.Gen) } else { [string] $s.Value }
        $lines.Add((Format-SkynetDottedLine -Label ([string] $s.Label) -Value $value -Width $Width -Prefix '> '))
    }
    return $lines.ToArray()
}

function Resolve-SkynetSpecFile {
    <#
    .SYNOPSIS
        Найти файл ТТХ терминатора для прокрутки в сцене сканирования юнита.
    .DESCRIPTION
        Порядок поиска:
        1) явный путь (абсолютный или относительно корня проекта);
        2) в корне проекта — файл, в имени которого есть и «tactical», и «spec»;
        3) в корне проекта — любой файл со «specification» в имени (кроме README*).
        Ничего не найдено → пустая строка (вызывающий код берёт запасные данные).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Path = '')

    if ($Path) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Resolve-Path -LiteralPath $Path).Path }
        $root = [string] $GLOBAL:_SkyNetCore.ProjectRoot
        if ($root) {
            $candidate = Join-Path $root $Path
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
        }
        try { Write-SkynetLog -Message "Prologue: файл ТТХ не найден ($Path)." -Level 'WARN' -Module 'Prologue' } catch { }
        return ''
    }

    $root = [string] $GLOBAL:_SkyNetCore.ProjectRoot
    if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { return '' }
    $files = @()
    try {
        $files = @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(md|txt)$' })
    } catch { return '' }
    if ($files.Count -eq 0) { return '' }

    $hit = $files | Where-Object { $_.Name -match '(?i)tactical' -and $_.Name -match '(?i)spec' } | Select-Object -First 1
    if (-not $hit) {
        $hit = $files | Where-Object { $_.Name -match '(?i)specification' -and $_.Name -notmatch '(?i)^readme' } | Select-Object -First 1
    }
    if ($hit) { return $hit.FullName }
    return ''
}

function Format-SkynetWrappedText {
    <#
    .SYNOPSIS
        Разбить текст на строки шириной не больше Width (перенос по словам).
    .PARAMETER Prefix
        Префикс первой строки (по умолчанию «> »).
    .PARAMETER Indent
        Отступ строк-продолжений.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string] $Text = '',
        [int] $Width = 44,
        [string] $Prefix = '> ',
        [string] $Indent = '  '
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    if ($Width -lt 16) { $Width = 16 }
    $words = @($Text.Trim() -split '\s+' | Where-Object { $_ })
    if ($words.Count -eq 0) { return @() }

    $out = New-Object System.Collections.Generic.List[string]
    $marker = $Prefix
    $current = ''
    foreach ($word in $words) {
        # Слово длиннее строки (бывает в дампах) — режем жёстко, чтобы не вылезти за панель.
        if ($word.Length -gt ($Width - $marker.Length)) {
            if ($current) { $out.Add($marker + $current); $current = ''; $marker = $Indent }
            $rest = $word
            while ($rest.Length -gt ($Width - $marker.Length)) {
                $take = $Width - $marker.Length
                $out.Add($marker + $rest.Substring(0, $take))
                $rest = $rest.Substring($take)
                $marker = $Indent
            }
            $current = $rest
            continue
        }
        if (-not $current) { $current = $word }
        elseif (($marker.Length + $current.Length + 1 + $word.Length) -le $Width) { $current = "$current $word" }
        else {
            $out.Add($marker + $current)
            $marker = $Indent
            $current = $word
        }
    }
    if ($current) { $out.Add($marker + $current) }
    return $out.ToArray()
}

function Get-SkynetSpecScanLines {
    <#
    .SYNOPSIS
        Строки прокрутки для сцены сканирования юнита — из файла ТТХ терминатора
        (по умолчанию tactical and technical specifications.MD в корне проекта).
    .DESCRIPTION
        Файл читается и печатается ПОСЛЕДОВАТЕЛЬНО, ровно как лежит в источнике:
        строки вида «LABEL: value» превращаются в «> LABEL ....... VALUE»
        (тот же стиль, что у закреплённой шапки), остальной текст — обычными
        строками; длинные строки переносятся по ширине панели, поэтому ничего
        не обрезается, а регион прокрутки сам выталкивает старые строки вверх.
        Файл не найден/пуст → пустой массив, вызывающий берёт Get-SkynetT800ScanLines.
    .PARAMETER Path
        Явный путь к файлу ТТХ; пусто — искать автоматически (Resolve-SkynetSpecFile).
    .PARAMETER Width
        Ширина левой панели в знакоместах (по умолчанию 46).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string] $Path = '',
        [int] $Width = 46
    )

    $file = Resolve-SkynetSpecFile -Path $Path
    if (-not $file) { return @() }
    if ($Width -lt 24) { $Width = 24 }

    $raw = @()
    try { $raw = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop) } catch {
        try { Write-SkynetLog -Message "Prologue: файл ТТХ не прочитан ($file): $($_.Exception.Message)" -Level 'WARN' -Module 'Prologue' } catch { }
        return @()
    }
    try { Write-SkynetLog -Message "Prologue: прокрутка ТТХ читается из $file" -Level 'DEBUG' -Module 'Prologue' } catch { }

    # "LABEL: value" — заголовок поля ТТХ; подпись ограничена 32 знаками, чтобы
    # обычное предложение с двоеточием в середине не превращалось в подпись.
    $rxPair = [regex] '^(?<label>[A-Za-z0-9][A-Za-z0-9 \-\.,/()]{0,30}?)\s*:\s*(?<value>.+)$'
    $lines = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $raw) {
        $text = [string] $entry
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $text = $text.Trim().TrimStart([char] 0x00B7).Trim()    # снимаем маркер списка «·»
        if (-not $text) { continue }

        $m = $rxPair.Match($text)
        if ($m.Success) {
            $label = $m.Groups['label'].Value.ToUpperInvariant().Trim()
            $value = $m.Groups['value'].Value.ToUpperInvariant().Trim()
            $valueRoom = [Math]::Max(6, ($Width - 6) - $label.Length)
            if ($value.Length -le $valueRoom) {
                $lines.Add((Format-SkynetDottedLine -Label $label -Value $value -Width ($Width - 2) -Prefix '> '))
            } else {
                # Значение длиннее строки панели: подпись с коротким лидером, а
                # сам текст — с отступом на следующих строках.
                $lines.Add((Format-SkynetDottedLine -Label $label -Value '' -Width ($label.Length + 9) -Prefix '> ').TrimEnd())
                foreach ($chunk in @(Format-SkynetWrappedText -Text $value -Width ($Width - 4) -Prefix '    ' -Indent '    ')) {
                    $lines.Add($chunk)
                }
            }
            continue
        }

        foreach ($chunk in @(Format-SkynetWrappedText -Text $text.ToUpperInvariant() -Width ($Width - 2))) {
            $lines.Add($chunk)
        }
    }
    return $lines.ToArray()
}

function Get-SkynetSpecMarqueeText {
    <#
    .SYNOPSIS
        Однострочный текст ТТХ для бегущей строки (белая строка под сценой скана).
    .DESCRIPTION
        Читает тот же файл ТТХ, что и прокрутка, склеивает содержательные строки
        через « :: » и поднимает всё в верхний регистр — под стиль остальных
        служебных надписей пролога. Файл недоступен → текст из Get-SkynetT800ScanLines.
    .PARAMETER Path
        Явный путь к файлу ТТХ; пусто — автопоиск (Resolve-SkynetSpecFile).
    .PARAMETER MaxLength
        Ограничение длины строки, чтобы буфер бегущей строки не раздувался.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Path = '',
        [int] $MaxLength = 1200
    )

    $file = Resolve-SkynetSpecFile -Path $Path
    $parts = New-Object System.Collections.Generic.List[string]
    if ($file) {
        try {
            foreach ($entry in @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop)) {
                $text = [string] $entry
                if ([string]::IsNullOrWhiteSpace($text)) { continue }
                $text = $text.Trim().TrimStart([char] 0x00B7).Trim()
                if (-not $text) { continue }
                $parts.Add($text.ToUpperInvariant())
            }
        } catch { }
    }
    if ($parts.Count -eq 0) {
        foreach ($line in @(Get-SkynetT800ScanLines)) { $parts.Add(([string] $line).ToUpperInvariant()) }
    }
    if ($parts.Count -eq 0) { return '' }

    $text = ($parts -join '  ::  ')
    if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength) }
    if (-not $text.EndsWith(' ')) { $text += ' ' }
    return $text
}

function Write-SkynetScanPanelRow {
    <#
    .SYNOPSIS
        Нарисовать строку левой панели сканирования (закреплённая шапка/лог ТТХ).
    .DESCRIPTION
        Строка панели всегда занимает РОВНО Width знакомест и печатается по
        абсолютной позиции, без ESC[K. Это принципиально: сцена сканирования
        двухслойная (слева панель, справа кадры головы), и «очистка до конца
        строки» на одном слое стирала бы соседний — из-за этого текст ТТХ
        раньше мигал и исчезал. Лишнее внутри панели затирается пробелами.
    .PARAMETER Width
        Ширина панели в знакоместах (включая левый отступ Col-1).
    #>
    [CmdletBinding()]
    param(
        [int] $Row = 1,
        [string] $Text = '',
        [int] $Width = 0,
        [string] $Color = '',
        [int] $Col = 2
    )

    if ($Row -lt 1 -or $Width -lt 1) { return }
    $plain = if ($null -eq $Text) { '' } else { [string] $Text }
    $plain = $plain -replace '\x1b\[[0-9;?]*[a-zA-Z]', ''
    if ($plain.Length -gt $Width) { $plain = $plain.Substring(0, $Width) }
    $padded = $plain.PadRight($Width)
    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { [Console]::Out.WriteLine($padded); return }
    $esc = Get-SkynetPrologueEsc
    if (-not $Color) { $Color = [string] $GLOBAL:ColPrologue }
    [Console]::Out.Write("${esc}[${Row};${Col}H${Color}${padded}$($GLOBAL:ColReset)")
}

function Write-SkynetScanChar {
    <#
    .SYNOPSIS
        Быстро вывести один символ ТТХ в уже подготовленную строку панели.
    .DESCRIPTION
        Не перерисовывает всю строку и не создаёт ANSI-строку на каждом шаге:
        текстовая прокрутка вызывает Chafa/Sixel независимо, а этот быстрый
        путь печатает только новую ячейку. Поэтому уменьшение интервала действительно
        ускоряет ТТХ, а не только меняет число в конфигурации.
    #>
    [CmdletBinding()]
    param(
        [int] $Row = 1,
        [int] $Col = 2,
        [Parameter(Mandatory)][string] $Char = '',
        [string] $Color = ''
    )
    if ($Row -lt 1 -or $Col -lt 1 -or $Char.Length -eq 0) { return }
    # Клавиатурный треск на символ ТТХ. Троттлинг внутри Play-SkynetSound
    # не даёт превратить поток 2 мс/символ в треск пулемёта.
    Invoke-SkynetSound -Name 'scan' -ThrottleMs 45
    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { [Console]::Out.Write($Char); return }
    if (-not $Color) { $Color = [string] $GLOBAL:ColPrologue }
    $esc = Get-SkynetPrologueEsc
    [Console]::Out.Write("${esc}[${Row};${Col}H${Color}${Char}$($GLOBAL:ColReset)")
}

function Write-SkynetScanHeadFrame {
    <#
    .SYNOPSIS
        Нарисовать кадр вращения справа от панели, не задевая панель.
    .DESCRIPTION
        В отличие от Write-SkynetFrame (который печатает строку с колонки 1,
        добивает её пробелами и делает ESC[K) здесь каждая строка кадра
        печатается по абсолютной колонке и не «чистит» ни левую панель, ни
        остаток строки за кадром. Остаток внутри самого кадра затирается
        пробелами до Width — картинка не оставляет хвостов при вращении.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]] $Lines = @(),
        [int] $TopRow = 1,
        [int] $Col = 1,
        [int] $Width = 0
    )

    if (-not $Lines -or $Lines.Count -eq 0) { return }
    if ($Col -lt 1) { $Col = 1 }
    if (-not $GLOBAL:_SkyNetCore.AnsiOk) { return }
    $esc = Get-SkynetPrologueEsc
    $out = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = [string] $Lines[$i]
        $visible = 0
        if (Get-Command Get-SkynetVisibleLength -ErrorAction SilentlyContinue) {
            $visible = Get-SkynetVisibleLength -Text $line
        } else {
            $visible = (($line -replace '\x1b\[[0-9;?]*[a-zA-Z]', '')).Length
        }
        $pad = 0
        if ($Width -gt 0) { $pad = [Math]::Max(0, $Width - $visible) }
        [void] $out.Append("${esc}[$($TopRow + $i);${Col}H")
        [void] $out.Append($line)
        if ($pad -gt 0) { [void] $out.Append(' ' * $pad) }
        [void] $out.Append([string] $GLOBAL:ColReset)
    }
    [Console]::Out.Write($out.ToString())
}

function Show-SkynetSixelScanFrame {
    <#
    .SYNOPSIS
        Вывести один кадр T-800 как настоящий Sixel, не затрагивая левую панель.
    .DESCRIPTION
        Chafa вызывается напрямую, его stdout не перехватывается. При
        -ClearPrevious очищаются только строки изображения справа; текст ТТХ слева
        остаётся на месте. В основном цикле очистка отключена, чтобы кадры не мигали.
        Размер задаётся в знакоместах Windows Terminal.
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
    if ($Width -lt 1 -or $Height -lt 1) { throw 'Sixel T-800: недопустимый размер кадра.' }
    if (Get-Command Show-SkynetSixelImage -ErrorAction SilentlyContinue) {
        Show-SkynetSixelImage -Path $Path -ChafaPath $ChafaPath -TopRow $TopRow -Col $Col `
            -Width $Width -Height $Height -ClearPrevious:$ClearPrevious
        return
    }

    $esc = Get-SkynetPrologueEsc
    $reset = [string] $GLOBAL:ColReset

    if ($ClearPrevious) {
        $out = [System.Text.StringBuilder]::new()
        for ($row = $TopRow; $row -lt ($TopRow + $Height); $row++) {
            [void]$out.Append("${esc}[${row};${Col}H${reset}${esc}[K")
        }
        [Console]::Out.Write($out.ToString())
    }
    [Console]::Out.Write("${esc}[${TopRow};${Col}H${esc}[?25l")
    $chafaArgs = @('--format=sixel', "--size=${Width}x${Height}", '-c', 'full', $Path)
    & $ChafaPath @chafaArgs
    if ($LASTEXITCODE -ne 0) { throw "Sixel T-800: chafa завершился с кодом $LASTEXITCODE ($Path)." }
    # Chafa показывает курсор в конце вывода; возвращаем скрытое состояние.
    [Console]::Out.Write("${esc}[?25l")
}

function Show-SkynetBodyScan {
    <#
    .SYNOPSIS
        Общий движок сцены сканирования части тела T-800: справа — вращающиеся
        кадры (белые чернила, та же дилатация/параметры, что у головы — только
        папка своя), слева — закреплённая шапка и опциональный прокручивающийся
        лог под ней (строки уходят вверх и исчезают при переполнении).
    .DESCRIPTION
        Используется и для головы (Show-SkynetUnitScan), и для торса
        (Show-SkynetTorsoScan) — единственная разница между ними это папка с
        кадрами, шапка и (для головы) текст сканирования снизу.
    .PARAMETER FramesFolder
        Папка с пронумерованными кадрами вращения (как у Show-SkynetT800Scene).
        Если пусто или не найдена — сцена просто пропускается (WARN в лог),
        ничего не падает.
    .PARAMETER ScanLines
        Прокручивающиеся строки под шапкой; пустой массив — только шапка и
        голова, без прокрутки (используется для торса).
    .PARAMETER MarqueeText
        Текст бегущей строки на время сцены (обычно ТТХ робота, белым цветом).
        Пусто — бегущая строка не переключается, остаётся общеэкранная.
    .PARAMETER PanelWidth
        Ширина левой панели в знакоместах; 0 — рассчитать от ширины окна.
    #>
    [CmdletBinding()]
    param(
        [string] $Title = 'CYBERDYNE SYSTEMS :: SCAN',
        [string] $FramesFolder = '',
        [string[]] $HeaderLines = @(),
        [AllowEmptyCollection()][string[]] $ScanLines = @(),
        [string] $MarqueeText = '',
        [int] $PanelWidth = 0,
        [double] $SpinSeconds = 12.0,
        [int] $CharDelayMs = 2,
        [int] $LineGapMs = 22,
        [int] $TailHoldMs = 1200,
        [int] $FrameCycles = 1,
        [int] $FrameIntervalMs = 8,
        [int] $ProcessorScanMs = 1000,
        [int] $ProcessorDoneHoldMs = 350,
        [int] $ScanBlinkOnMs = 180,
        [int] $ScanBlinkOffMs = 120,
        [switch] $BlinkTitle,
        [int] $TitleOnMs = 180,
        [int] $TitleOffMs = 100,
        [switch] $NoUnitImage
    )
    # -NoUnitImage убирает робота из основного окна (он остаётся только в
    # окне звонка). Кадры при этом всё равно перебираются: иначе собьются
    # тайминги зон, звук и итоговый отчёт диагностики.
    $drawUnit = -not $NoUnitImage
    if ($FrameCycles -lt 1) { $FrameCycles = 1 }
    if ($FrameIntervalMs -lt 1) { $FrameIntervalMs = 1 }
    $cfg = $GLOBAL:_SkyNetCore
    if (-not $cfg.AnsiOk) { return }

    if (-not $FramesFolder -or -not (Test-Path -LiteralPath $FramesFolder -PathType Container)) {
        try { Write-SkynetLog -Message "Prologue: папка кадров не найдена ($FramesFolder) — сцена '$Title' пропущена." -Level 'WARN' -Module 'Prologue' } catch { }
        return
    }

    $esc = Get-SkynetPrologueEsc
    $geo = Get-SkynetConsoleGeometry
    $topRow = 2
    $bottomReserve = 3
    $rows = [Math]::Max(8, $geo.Height - $bottomReserve - $topRow)
    # Сцена двухслойная: слева панель ровно PanelWidth знакомест, справа кадры
    # головы. Между ними два пробела — слои не перетирают друг друга (у каждого
    # своя абсолютная колонка, ни один не «чистит» строку до конца).
    $panelWidth = if ($PanelWidth -gt 0) { $PanelWidth } else { [Math]::Max(30, [int]($geo.Width * 0.40)) }
    if ($panelWidth -gt ($geo.Width - 30)) { $panelWidth = [Math]::Max(24, $geo.Width - 30) }
    $headCol = $panelWidth + 3
    $headWidth = [Math]::Max(16, $geo.Width - $headCol)

    Clear-SkynetFrame -LineCount ($geo.Height - $bottomReserve) -TopRow 1
    Write-SkynetStatusLine -Text $Title -Row 1 -Color $GLOBAL:ColPrologueDim

    # --- Кадры вращения: при Sixel играем исходные PNG напрямую; символьный
    #     брайль остаётся только для -Sixel:$false / несовместимого fallback. ---
    $frames = @()
    $framePaths = @()
    $chafa = $null
    $useSixel = $false
    $sixelTopRow = $topRow
    $sixelLeftCol = $headCol
    $sixelWidth = $headWidth
    $sixelHeight = $rows

    if (Get-Command Get-SkynetT800FramePaths -ErrorAction SilentlyContinue) {
        $framePaths = @(Get-SkynetT800FramePaths -FolderPath $FramesFolder -NumericOnly)
    }
    # --- прореживание кадров вращения ---------------------------------------
    # Скорость вращения НЕ задаётся $SpinSeconds: индекс кадра считается по
    # времени ($phase = прошедшие секунды / SpinSeconds), но успевает ли
    # отрисовка — вопрос другой. Замер по журналу: 215 кадров проходятся за
    # ~12.6 с, то есть ~58 мс на кадр, тогда как $SpinSeconds = 4 просил бы
    # 18.6 мс. Движок стабильно не успевает, и часть кадров просто
    # пропускается — сколько именно, не зависит от $SpinSeconds.
    # Поэтому вдвое быстрее вращение становится только при вдвое меньшем
    # числе ПОКАЗЫВАЕМЫХ кадров: берём каждый второй. Вид тот же (шаг в
    # 2 кадра при ширине 76 знакомест неразличим), а оборот занимает
    # 108 × 58 мс ≈ 6.3 с вместо 12.6 с. $frameStride = 1 вернёт прежнее.
    $frameStride = 2
    if ($frameStride -gt 1 -and $framePaths.Count -gt $frameStride) {
        $thinned = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $framePaths.Count; $i += $frameStride) { $thinned.Add($framePaths[$i]) }
        $framePaths = @($thinned)
    }
    if ($cfg.Instant -and $framePaths.Count -gt 0) { $framePaths = @($framePaths[0]) }

    if ($cfg.Sixel -and $framePaths.Count -gt 0) {
        # Без картинки chafa не нужен: планируем область только когда рисуем.
        if ($drawUnit) { try { $chafa = Get-SkynetChafaPath } catch { $chafa = $null } }
        if ($drawUnit -and $chafa) {
            $firstInfo = Test-SkynetLogoFile -Path $framePaths[0]
            $pixelAspect = if ($firstInfo.Ok -and $firstInfo.Width -gt 0 -and $firstInfo.Height -gt 0) {
                $firstInfo.Width / [double] $firstInfo.Height
            } else { 1.0 }
            # В Windows Terminal знакоместо вдвое выше своей ширины.
            $gridAspect = $pixelAspect / 0.5
            if ($gridAspect -ge ($headWidth / [double] $rows)) {
                $sixelWidth = [Math]::Max(1, $headWidth)
                $sixelHeight = [Math]::Max(1, [int][Math]::Floor($sixelWidth / $gridAspect))
            } else {
                $sixelHeight = [Math]::Max(1, $rows)
                $sixelWidth = [Math]::Max(1, [int][Math]::Floor($sixelHeight * $gridAspect))
            }
            $sixelLeftCol = $headCol + [int][Math]::Floor(($headWidth - $sixelWidth) / 2)
            $useSixel = $true
            Write-SkynetLog -Message "T-800 Sixel: найдено $($framePaths.Count) кадров (шаг $frameStride из найденных); область ${sixelWidth}x${sixelHeight}, циклов $FrameCycles, интервал ${FrameIntervalMs} мс." -Level 'INFO' -Module 'Render'
        } else {
            # Рисовать нечего, но логика прохода кадров нужна для зон и звука.
            $useSixel = $true
            Write-SkynetLog -Message 'T-800: изображение юнита отключено (-NoUnitImage), сцена идёт только текстом.' -Level 'INFO' -Module 'Prologue'
        }
    }
    if (-not $drawUnit -and -not $useSixel -and $framePaths.Count -gt 0) { $useSixel = $true }

    if (-not $useSixel -and $framePaths.Count -gt 0 -and
        (Get-Command Build-SkynetT800SpinFramesFromImages -ErrorAction SilentlyContinue)) {
        $frames = Build-SkynetT800SpinFramesFromImages -Paths $framePaths -Width $headWidth -Height $rows `
            -ColorMode 'Original' -InkR 255 -InkG 255 -InkB 255
    }
    $frameCount = if ($useSixel) { $framePaths.Count } else { $frames.Count }
    if ($frameCount -eq 0) {
        try { Write-SkynetLog -Message "Prologue: кадры не построены ($FramesFolder) — сцена '$Title' пропущена." -Level 'WARN' -Module 'Prologue' } catch { }
        return
    }

    # Последний числовой кадр берём из фактического списка файлов, а не из
    # жёстко заданного числа: добавленные 197…N являются финальным проходом
    # тела и автоматически получают собственный этап FULL-BODY SCAN.
    $lastFrameNumber = 0
    foreach ($path in $framePaths) {
        $candidateNumber = Get-SkynetFrameNumberFromPath -Path $path
        if ($candidateNumber -gt $lastFrameNumber) { $lastFrameNumber = $candidateNumber }
    }
    if ($lastFrameNumber -lt 1) { $lastFrameNumber = $frameCount }

    # Один полный проход по фактическому списку кадров (сейчас 1…215).
    # Кадры 97…136 — четыре зоны, 137…166 — каркас, 167…196 — сервоприводы,
    # 197…последний — подтверждающий проход FULL-BODY SCAN.
    # --- Закреплённая шапка юнита (белым, на всю сцену) -----------------------
    # Печатается один раз и дальше НИКОГДА не перерисовывается: и прокрутка ТТХ,
    # и кадры головы рисуются строго ниже/правее этой области.
    $headerTop = $topRow + 2
    for ($i = 0; $i -lt $HeaderLines.Count; $i++) {
        Write-SkynetScanPanelRow -Row ($headerTop + $i) -Text $HeaderLines[$i] -Width $panelWidth -Color $GLOBAL:ColPrologueBright
    }

    # Строки зон сканирования постоянно занимают отдельный блок между шапкой и ТТХ.
    # Завершённые строки остаются здесь, поэтому поток спецификаций не сдвигает их.
    $scanStages = @(Get-SkynetScanStages -LastFrameNumber $lastFrameNumber)
    $annotationTop = $headerTop + $HeaderLines.Count + 1
    $annotationCount = $scanStages.Count
    $scanBlockBottom = $annotationTop + $annotationCount - 1
    # После блока оставляем три пустые строки: ТТХ начинается ниже всех
    # зон, включая FULL-BODY SCAN, и не может визуально слипаться с ними.
    $scanGapRows = 3
    $logTop = $scanBlockBottom + 1 + $scanGapRows
    $logBottom = [Math]::Min($geo.Height - $bottomReserve, $topRow + $rows - 1)
    $logRows = $logBottom - $logTop + 1
    if ($ScanLines.Count -gt 0 -and $logRows -lt 1) {
        # В слишком низком окне лучше не показывать ТТХ вообще, чем писать его
        # поверх закреплённых аннотаций. Кадры и сканирование продолжаются.
        try { Write-SkynetLog -Message "Prologue: для потока ТТХ нет строки ниже блока зон сканирования (окно $($geo.Height) строк); ТТХ пропущен." -Level 'WARN' -Module 'Prologue' } catch { }
        $ScanLines = @()
    }
    $logRows = [Math]::Max(0, $logRows)
    $buffer = New-Object System.Collections.Generic.List[string]

    # Бегущая строка на время скана — ТТХ робота белым (общеэкранная строка
    # остаётся зелёной и возвращается сразу после сцены).
    $marqueeSwapped = $false
    if ($MarqueeText) {
        try {
            Start-SkynetMarqueeState -Text $MarqueeText -Speed 40 -Color $GLOBAL:ColPrologue -HeadColor $GLOBAL:ColPrologueBright
            $marqueeSwapped = $true
        } catch { }
    }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    # В Sixel-режиме индекс не вычисляется из elapsedtime: Chafa вызывается
    # последовательно, поэтому ни один из фактически найденных файлов не пропускается, даже если
    # один кадр рендерится дольше остальных. После полного прохода последний
    # кадр удерживается, пока продолжается текстовая прокрутка.
    $frameIntervalMs = [Math]::Max(1, $FrameIntervalMs)
    $totalFrameCount = $frameCount * $FrameCycles
    $scanState = @{
        NextIndex   = 0
        LastIndex   = -1
        Cycle       = 1
        NextAtMs    = 0
        Complete    = $false
        TitleVisible = $true
        NextTitleAtMs = [int]$TitleOnMs
        LastFrameNumber = 0
        ActiveStageKey = ''
        CompletedStageKeys = [System.Collections.Generic.List[string]]::new()
        ProcessorStartedAtMs = -1
        ProcessorDone = $false
        ProcessorDoneShownAtMs = -1
        BlinkOn = $true
        NextBlinkAtMs = 0
    }
    function Update-SkynetScanTitle {
        if (-not $BlinkTitle) { return }
        $now = [int]$watch.ElapsedMilliseconds
        if ($now -lt $scanState.NextTitleAtMs) { return }
        if ($scanState.TitleVisible) {
            Write-SkynetStatusLine -Text $Title -Row 1 -Color $GLOBAL:ColPrologueDim
            $scanState.NextTitleAtMs = $now + [Math]::Max(1, $TitleOnMs)
        } else {
            Write-SkynetStatusLine -Text (' ' * $Title.Length) -Row 1 -Color $GLOBAL:ColPrologueDim
            $scanState.NextTitleAtMs = $now + [Math]::Max(1, $TitleOffMs)
        }
        $scanState.TitleVisible = -not $scanState.TitleVisible
    }
    function Update-SkynetScanAnnotation {
        $now = [int]$watch.ElapsedMilliseconds
        $frameNumber = [int]$scanState.LastFrameNumber
        $stage = Get-SkynetScanStage -FrameNumber $frameNumber -LastFrameNumber $lastFrameNumber
        if (-not $stage) {
            if (-not $scanState.ActiveStageKey) {
                foreach ($candidate in $scanStages) {
                    Write-SkynetScanPanelRow -Row ($annotationTop + $candidate.Order) -Text '' `
                        -Width $panelWidth -Color $GLOBAL:ColPrologueAlert
                }
            }
            return $null
        }

        if ($scanState.ActiveStageKey -ne $stage.Key) {
            if ($scanState.ActiveStageKey) {
                [void]$scanState.CompletedStageKeys.Add($scanState.ActiveStageKey)
            }
            $scanState.ActiveStageKey = $stage.Key
            $scanState.BlinkOn = $true
            $scanState.NextBlinkAtMs = $now + [Math]::Max(1, $ScanBlinkOnMs)
            # Нарастающий свип на смену зоны — самый «механический» момент
            # сцены: по нему слышно, что сканирование идёт вперёд.
            Invoke-SkynetSound -Name 'zone'
        }
        if ($stage.Key -eq 'processor' -and $scanState.ProcessorStartedAtMs -lt 0) {
            $scanState.ProcessorStartedAtMs = $now
        }
        $processorElapsed = if ($scanState.ProcessorStartedAtMs -ge 0) {
            $now - $scanState.ProcessorStartedAtMs
        } else { 0 }
        if ($stage.Key -eq 'processor' -and $processorElapsed -ge $ProcessorScanMs -and
            -not $scanState.ProcessorDone) {
            $scanState.ProcessorDone = $true
            $scanState.ProcessorDoneShownAtMs = $now
            Invoke-SkynetSound -Name 'zone_done'
        }
        if (-not ($stage.Key -eq 'processor' -and $scanState.ProcessorDone) -and
            $now -ge $scanState.NextBlinkAtMs) {
            $scanState.BlinkOn = -not $scanState.BlinkOn
            $scanState.NextBlinkAtMs = $now + $(if ($scanState.BlinkOn) {
                [Math]::Max(1, $ScanBlinkOnMs)
            } else {
                [Math]::Max(1, $ScanBlinkOffMs)
            })
        }

        foreach ($candidate in $scanStages) {
            $key = [string] $candidate.Key
            $isActive = $key -eq $scanState.ActiveStageKey
            $isCompleted = $scanState.CompletedStageKeys.Contains($key)
            if (-not $isActive -and -not $isCompleted) { continue }
            $visible = (-not $isActive) -or $scanState.BlinkOn -or
                ($key -eq 'processor' -and $scanState.ProcessorDone)
            $annotation = Get-SkynetScanAnnotation -Stage $candidate `
                -ElapsedSinceProcessorMs $processorElapsed -ProcessorScanMs $ProcessorScanMs `
                -Visible $visible -PanelWidth $panelWidth `
                -Completed:($scanState.Complete -and $key -eq 'body')
            Write-SkynetScanPanelRow -Row ($annotationTop + $candidate.Order) -Text $annotation `
                -Width $panelWidth -Color $GLOBAL:ColPrologueAlert
        }
        # ВАЖНО: функции обновления НЕ возвращают $stage. Любой объект,
        # отданный в поток вывода, PowerShell сериализует в консоль —
        # раньше здесь на экран попадали Target/Label/Key/Blink/Order/
        # Start/End вместе со значением 215, что и выглядело как «каша».
    }
    function Update-SkynetScanHead {
        Update-SkynetScanTitle
        if ($useSixel) {
            if ($scanState.Complete) { return }
            $now = [int]$watch.ElapsedMilliseconds
            if ($scanState.LastIndex -ge 0 -and $now -lt $scanState.NextAtMs) { return }

            $nextIdx = [int]$scanState.NextIndex % $frameCount
            $nextFrameNumber = Get-SkynetFrameNumberFromPath -Path $framePaths[$nextIdx]
            # Если Chafa успевает пройти 97…106 быстрее секунды, не позволяем
            # перейти к шее до окончательного Processor DONE. Это гарантирует,
            # что быстрый терминал не пропустит требуемую паузу.
            if ($scanState.ProcessorStartedAtMs -ge 0 -and $nextFrameNumber -gt 106 -and -not $scanState.ProcessorDone) {
                Update-SkynetScanAnnotation
                $now = [int]$watch.ElapsedMilliseconds
                $remaining = $ProcessorScanMs - ($now - $scanState.ProcessorStartedAtMs)
                if ($remaining -gt 0) {
                    $scanState.NextAtMs = $now + [Math]::Max(1, [Math]::Min(8, $remaining))
                    return
                }
            }
            if ($scanState.ProcessorDone -and $nextFrameNumber -gt 106 -and
                $scanState.ProcessorDoneShownAtMs -ge 0 -and
                ($now - $scanState.ProcessorDoneShownAtMs) -lt $ProcessorDoneHoldMs) {
                Update-SkynetScanAnnotation
                $scanState.NextAtMs = $now + [Math]::Max(1, [Math]::Min(8, $ProcessorDoneHoldMs - ($now - $scanState.ProcessorDoneShownAtMs)))
                return
            }

            $idx = $nextIdx
            if ($drawUnit) {
                Show-SkynetSixelScanFrame -Path $framePaths[$idx] -ChafaPath $chafa `
                    -TopRow $sixelTopRow -Col $sixelLeftCol -Width $sixelWidth -Height $sixelHeight `
                    -ClearPrevious:$false
            }
            $scanState.LastIndex = $idx
            $scanState.LastFrameNumber = Get-SkynetFrameNumberFromPath -Path $framePaths[$idx]
            $scanState.NextIndex = $scanState.NextIndex + 1
            Update-SkynetScanAnnotation
            if ($scanState.NextIndex -ge $totalFrameCount) {
                $scanState.Complete = $true
                # Последняя активная строка не должна исчезнуть, если финальный
                # кадр тела завершил этап на выключенной фазе мигания.
                $scanState.BlinkOn = $true
                $scanState.NextBlinkAtMs = [int]::MaxValue
                # Полный проход завершён — подтверждаем финальную зону.
                Invoke-SkynetSound -Name 'zone_done'
                Update-SkynetScanAnnotation
                try { Write-SkynetLog -Message "T-800 Sixel: полных проходов — $FrameCycles; показано $totalFrameCount из $totalFrameCount кадров ($FrameCycles × $frameCount)." -Level 'INFO' -Module 'Render' } catch { }
            } else {
                $scanState.Cycle = [int][Math]::Floor($scanState.NextIndex / $frameCount) + 1
                $scanState.NextAtMs = [int]$watch.ElapsedMilliseconds + $frameIntervalMs
            }
            return
        }

        $phase = ($watch.Elapsed.TotalSeconds) / [Math]::Max(0.1, $SpinSeconds)
        $idx = [int][Math]::Floor($phase * $frameCount) % $frameCount
        if ($idx -lt 0) { $idx += $frameCount }
        if ($idx -ne $scanState.LastIndex) {
            Write-SkynetScanHeadFrame -Lines $frames[$idx] -TopRow $topRow -Col $headCol -Width $headWidth
            $scanState.LastIndex = $idx
            $scanState.LastFrameNumber = Get-SkynetFrameNumberFromPath -Path $framePaths[$idx]
            Update-SkynetScanAnnotation
        }
    }
    Update-SkynetScanHead
    try {
        # ТТХ не запускается параллельно с зонами сканирования. Сначала Chafa
        # обязан вывести весь фактический ряд, включая финальные кадры тела,
        # после чего закрепляется FULL-BODY SCAN DONE. Только затем поток ТТХ
        # начинается ниже защищённого блока. Так красные аннотации не теряются
        # среди белых технических строк и не выглядят как «каша».
        if ($useSixel) {
            while (-not $scanState.Complete) {
                Update-SkynetScanHead
                Update-SkynetMarquee
                Wait-SkynetPrologueDelay -Milliseconds 8
            }
            $fullTail = [System.Diagnostics.Stopwatch]::StartNew()
            while ($fullTail.ElapsedMilliseconds -lt ([Math]::Max($TailHoldMs, 500))) {
                Update-SkynetScanTitle
                Update-SkynetMarquee
                Wait-SkynetPrologueDelay -Milliseconds 8
            }
        }

        # Панель зон сканирования отработала своё дело: все кадры показаны, у
        # активной строки появился DONE. Теперь её заменяет итоговый блок
        # диагностики Cyberdyne.
        $finalBlock = @(Get-SkynetCyberdyneScanBlock -Width $panelWidth)
        # Граница блока — низ окна, а НЕ верх области прокрутки ТТХ. Отчёт
        # это кульминация сцены, и жертвовать им ради ТТХ нельзя: раньше здесь
        # стоял $logBottom, и на низком окне блок молча обрывался после двух
        # строк. Тогда не хватает места уже самому ТТХ — это разбирается ниже.
        $blockFloor = [Math]::Max(1, $geo.Height - $bottomReserve)
        $shown = 0
        for ($i = 0; $i -lt $finalBlock.Count; $i++) {
            $row = $annotationTop + $i
            if ($row -gt $blockFloor) { break }
            # Зоны остаются тревожным цветом прежней панели, шапка и итог —
            # ярким акцентом: отчёт читается как продолжение скана, а не как
            # новая вставка поверх старого текста. Статус распознаём по хвосту
            # строки, поэтому раскраска не зависит от ширины панели.
            $color = if ($finalBlock[$i] -match '(COMPLETE|OK)\s*$') {
                $GLOBAL:ColPrologueAlert
            } else {
                $GLOBAL:ColPrologueBright
            }
            Write-SkynetScanPanelRow -Row $row -Text $finalBlock[$i] -Width $panelWidth -Color $color
            Update-SkynetMarquee
            $shown++
            if ($LineGapMs -gt 0) { Wait-SkynetPrologueDelay -Milliseconds ([Math]::Min(60, $LineGapMs)) }
        }
        if ($shown -lt $finalBlock.Count) {
            try { Write-SkynetLog -Message "Prologue: итоговый блок диагностики обрезан по высоте окна — показано $shown из $($finalBlock.Count) строк (окно $($geo.Height) строк). Увеличьте высоту терминала." -Level 'WARN' -Module 'Prologue' } catch { }
        }
        $blockBottom = $annotationTop + $shown - 1
        # Страховка для низкого окна: обрезанный блок мог оказаться короче
        # прежней панели, и её хвост остался бы висеть под отчётом.
        for ($row = $blockBottom + 1; $row -le $scanBlockBottom; $row++) {
            Write-SkynetScanPanelRow -Row $row -Text '' -Width $panelWidth -Color $GLOBAL:ColPrologueAlert
        }
        $logTop = $blockBottom + 1 + $scanGapRows
        $logRows = $logBottom - $logTop + 1
        if ($ScanLines.Count -gt 0 -and $logRows -lt 1) {
            try { Write-SkynetLog -Message "Prologue: для потока ТТХ не хватает строк под итоговый блок диагностики (окно $($geo.Height) строк); ТТХ пропущен." -Level 'WARN' -Module 'Prologue' } catch { }
            $ScanLines = @()
        }
        $logRows = [Math]::Max(0, $logRows)

    if ($ScanLines.Count -eq 0) {
        # Нет текста сканирования (например, торс) — просто крутим кадры заданное время.
        $holdMs = [Math]::Max($TailHoldMs, [int]($SpinSeconds * 1000 * 1.5))
        while ($watch.ElapsedMilliseconds -lt $holdMs) {
            Update-SkynetScanHead
            Update-SkynetMarquee
            Wait-SkynetPrologueDelay -Milliseconds $(if ($useSixel) { 8 } else { 60 })
        }
    } else {
        foreach ($line in $ScanLines) {
            if ($buffer.Count -ge $logRows) {
                # Область переполнена: старые строки уходят вверх и исчезают.
                $buffer.RemoveAt(0)
                for ($i = 0; $i -lt $buffer.Count; $i++) {
                    Write-SkynetScanPanelRow -Row ($logTop + $i) -Text $buffer[$i] -Width $panelWidth -Color $GLOBAL:ColPrologue
                }
                Write-SkynetScanPanelRow -Row ($logTop + $buffer.Count) -Text '' -Width $panelWidth -Color $GLOBAL:ColPrologue
            }
            $row = $logTop + $buffer.Count
            # Посимвольный вывод печатает только новую ячейку; вся строка
            # очищается один раз перед началом, поэтому картинка справа и
            # остальные строки панели не перерисовываются на каждом символе.
            # Полная перерисовка всей строки на каждом символе была основной
            # накладной работой и визуально замедляла прокрутку ТТХ.
            $lineText = [string]$line
            if ($lineText.Length -gt $panelWidth) { $lineText = $lineText.Substring(0, $panelWidth) }
            Write-SkynetScanPanelRow -Row $row -Text '' -Width $panelWidth -Color $GLOBAL:ColPrologue
            $lineChars = $lineText.ToCharArray()
            $marqueeTick = 0
            for ($i = 0; $i -lt $lineChars.Count; $i++) {
                Write-SkynetScanChar -Row $row -Col (2 + $i) -Char ([string]$lineChars[$i]) -Color $GLOBAL:ColPrologue
                Update-SkynetScanHead
                $marqueeTick++
                if (($marqueeTick % 4) -eq 0) { Update-SkynetMarquee }
                if ($CharDelayMs -gt 0) { Wait-SkynetPrologueDelay -Milliseconds $CharDelayMs }
            }
            Update-SkynetMarquee
            $buffer.Add($line)
            if ($LineGapMs -gt 0) {
                # Пауза между строками тоже «живая»: голова продолжает вращаться.
                $idle = [System.Diagnostics.Stopwatch]::StartNew()
                while ($idle.ElapsedMilliseconds -lt $LineGapMs) {
                    Update-SkynetScanHead
                    Update-SkynetMarquee
                    $remaining = $LineGapMs - [int]$idle.ElapsedMilliseconds
                    if ($remaining -gt 0) {
                        Wait-SkynetPrologueDelay -Milliseconds ([Math]::Min(8, $remaining))
                    }
                }
            }
        }
        $tailWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $tailLimitMs = [Math]::Max($TailHoldMs, $frameIntervalMs + 350)
        while ($tailWatch.ElapsedMilliseconds -lt $tailLimitMs) {
            Update-SkynetScanHead
            Update-SkynetMarquee
            Wait-SkynetPrologueDelay -Milliseconds $(if ($useSixel) { 8 } else { 40 })
        }
    }
    } finally {
        if ($useSixel) {
            try {
                $clear = [System.Text.StringBuilder]::new()
                for ($row = $sixelTopRow; $row -lt ($sixelTopRow + $sixelHeight); $row++) {
                    [void]$clear.Append("${esc}[${row};${sixelLeftCol}H$($GLOBAL:ColReset)${esc}[K")
                }
                [void]$clear.Append("${esc}[0m${esc}[${sixelTopRow};${sixelLeftCol}H")
                [Console]::Out.Write($clear.ToString())
            } catch { }
        }
        # Возвращаем общеэкранную (зелёную) бегущую строку загрузки.
        if ($marqueeSwapped) {
            try {
                $cfgAfter = $GLOBAL:_SkyNetCore
                Start-SkynetMarqueeState -Text ([string] $cfgAfter.MarqueeText) -Speed ([int] $cfgAfter.MarqueeSpeed)
            } catch { }
        }
    }
}

function Show-SkynetUnitScan {
    <#
    .SYNOPSIS
        Голова T-800: закреплённая шапка юнита + прокручивающийся лог ТТХ снизу,
        вращающиеся кадры головы справа. Тонкая обёртка над Show-SkynetBodyScan.
    .DESCRIPTION
        Шапка (UNIT/MODEL/.../TARGETING) висит на месте всё время сканирования,
        а под ней последовательно печатается содержимое файла ТТХ терминатора
        (tactical and technical specifications.MD) — при переполнении области
        старые строки уходят вверх и исчезают. Если файл не найден, берётся
        запасной набор из Get-SkynetT800ScanLines.
    .PARAMETER SpecFilePath
        Явный путь к файлу ТТХ; пусто — автопоиск в корне проекта.
    .PARAMETER MarqueeText
        Текст бегущей строки (ТТХ робота) на время скана; пусто — берётся
        Get-SkynetSpecMarqueeText по тому же файлу ТТХ.
    #>
    [CmdletBinding()]
    param(
        [string] $FramesFolder = '',
        [string] $SpecFilePath = '',
        # 52 — ширина под итоговый блок Cyberdyne: его самая длинная строка
        # «PROCESSOR SCANNING DONE CYBERDYNE SYSTEMS MODEL 101» равна 51 знаку,
        # при 46 она обрезалась бы по краю панели.
        [int] $SpecWidth = 52,
        [string[]] $HeaderLines = @(
            'UNIT: T-800', 'MODEL: 101', 'ENDOSKELETON: HYPER-ALLOY', 'POWER CELL: ACTIVE',
            'CPU: NEURAL-NET PROCESSOR', 'VISION: INFRARED', 'TARGETING: ONLINE'
        ),
        [string[]] $ScanLines = $null,
        [string] $MarqueeText = '',
        [double] $SpinSeconds = 12.0,
        [int] $CharDelayMs = 2,
        [int] $LineGapMs = 22,
        [int] $TailHoldMs = 1200,
        [int] $FrameCycles = 1,
        [int] $FrameIntervalMs = 8,
        [switch] $NoUnitImage
    )
    if ($FrameCycles -lt 1) { $FrameCycles = 1 }
    if ($FrameIntervalMs -lt 1) { $FrameIntervalMs = 1 }
    if (-not $ScanLines) {
        $specLines = @()
        try { $specLines = @(Get-SkynetSpecScanLines -Path $SpecFilePath -Width $SpecWidth) } catch { $specLines = @() }
        if ($specLines.Count -gt 0) { $ScanLines = $specLines }
        else {
            try { Write-SkynetLog -Message 'Prologue: файл ТТХ не найден — прокрутка из Get-SkynetT800ScanLines.' -Level 'DEBUG' -Module 'Prologue' } catch { }
            $ScanLines = @(Get-SkynetT800ScanLines)
        }
    }
    if (-not $MarqueeText) {
        try { $MarqueeText = Get-SkynetSpecMarqueeText -Path $SpecFilePath } catch { $MarqueeText = '' }
    }
    Show-SkynetBodyScan -Title 'CYBERDYNE SYSTEMS :: UNIT IDENTIFICATION SCAN' -FramesFolder $FramesFolder `
        -HeaderLines $HeaderLines -ScanLines $ScanLines -MarqueeText $MarqueeText -PanelWidth $SpecWidth `
        -SpinSeconds $SpinSeconds -CharDelayMs $CharDelayMs `
        -LineGapMs $LineGapMs -TailHoldMs $TailHoldMs -FrameCycles $FrameCycles -FrameIntervalMs $FrameIntervalMs `
        -BlinkTitle -NoUnitImage:$NoUnitImage
}

function Show-SkynetTorsoScan {
    <#
    .SYNOPSIS
        Торс T-800: та же машинерия, что и у головы (тот же радиус дилатации,
        те же чернила) — отличается только папка с кадрами и короткая шапка,
        без прокручивающегося текста (чисто визуальный момент вращения).
    .PARAMETER FramesFolder
        Папка с пронумерованными кадрами вращения торса. Обязателен по смыслу:
        без неё сцена тихо пропускается (см. Show-SkynetBodyScan).
    #>
    [CmdletBinding()]
    param(
        [string] $FramesFolder = '',
        [string[]] $HeaderLines = @(
            'STRUCTURE: HYPER-ALLOY FRAME', 'PRESS FORCE: 200 TONS',
            'POWER CELL: CHEST CAVITY', 'MOBILITY: FULL RANGE', 'STATUS: OPERATIONAL'
        ),
        [double] $SpinSeconds = 3.0,
        [int] $HoldMs = 3500
    )
    Show-SkynetBodyScan -Title 'CYBERDYNE SYSTEMS :: TORSO STRUCTURAL SCAN' -FramesFolder $FramesFolder `
        -HeaderLines $HeaderLines -ScanLines @() -SpinSeconds $SpinSeconds -TailHoldMs $HoldMs
}

function Show-SkynetOpticalCheck {
    <#
    .SYNOPSIS
        Тёмный экран → "OPTICAL SYSTEM" чек-лист (пункты появляются по очереди,
        статус "OK" — с небольшой задержкой после подписи, будто идёт проверка).
    #>
    [CmdletBinding()]
    param(
        [string[]] $Checks = @('VISIBLE SPECTRUM', 'IR SPECTRUM', 'TARGETING', 'MOTION TRACKING'),
        [int] $DarkMs = 700,
        [int] $CheckDelayMs = 260
    )
    $geo = Get-SkynetConsoleGeometry
    Clear-SkynetFrame -LineCount $geo.Height -TopRow 1
    Start-Sleep -Milliseconds $DarkMs

    $esc = Get-SkynetPrologueEsc
    $ready = Test-SkynetPrologueReady
    $top = [Math]::Max(1, [int](($geo.Height - $Checks.Count - 2) / 2))
    $title = 'OPTICAL SYSTEM'
    $rule = '-' * 25

    if ($ready) {
        [Console]::Out.Write("${esc}[${top};2H$($GLOBAL:ColPrologueBright)$title$($GLOBAL:ColReset)")
        [Console]::Out.Write("${esc}[$($top + 1);2H$($GLOBAL:ColPrologueDim)$rule$($GLOBAL:ColReset)")
    } else {
        [Console]::Out.WriteLine($title)
        [Console]::Out.WriteLine($rule)
    }
    Start-Sleep -Milliseconds $CheckDelayMs

    for ($i = 0; $i -lt $Checks.Count; $i++) {
        $row = $top + 2 + $i
        $label = Format-SkynetDottedLine -Label $Checks[$i] -Value '' -Width 26
        $label = $label.TrimEnd()
        if ($ready) {
            [Console]::Out.Write("${esc}[${row};2H$($GLOBAL:ColPrologue)$label$($GLOBAL:ColReset)")
        } else {
            [Console]::Out.Write($label)
        }
        Start-Sleep -Milliseconds $CheckDelayMs
        if ($ready) {
            [Console]::Out.Write(" $($GLOBAL:ColPrologueBright)$($GLOBAL:ColBold)OK$($GLOBAL:ColReset)")
        } else {
            [Console]::Out.WriteLine(' OK')
        }
        Invoke-SkynetSound -Name 'ok'
        Start-Sleep -Milliseconds 150
    }
    Start-Sleep -Milliseconds 1200
}

function Show-SkynetPrologue {
    <#
    .SYNOPSIS
        Полный белый пролог целиком, по порядку (см. .DESCRIPTION модуля).
    .PARAMETER LogoLines
        Готовый раскрашенный кадр логотипа для Show-SkynetLogoNoiseReveal
        (получить заранее через Get-SkynetLogoFrame -Sixel:$false в вызывающем
        скрипте — этот модуль намеренно не знает о Render.psm1 напрямую).
    .PARAMETER FramesFolder
        Папка с кадрами вращения головы (та же, что и для Show-SkynetT800Scene).
    .PARAMETER SpecFilePath
        Файл ТТХ терминатора для прокрутки в сцене сканирования юнита
        (пусто — tactical and technical specifications.MD из корня проекта).
    .PARAMETER LogoFinalAction
        Callback, вызываемый сразу после символьной сборки. В него launcher
        передаёт прямой вызов Show-SkynetSixelLogo.
    .PARAMETER LogoFinalHoldMs
        Полная длительность финального Sixel-кадра вместе с мигающей
        ONLINE-надписью до очистки экрана (по умолчанию 2 секунды).
    .EXAMPLE
        Show-SkynetPrologue -LogoLines $frame.Lines -LogoTopRow $place.TopRow -FramesFolder $t800Frames
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $LogoLines,
        [int] $LogoTopRow = 1,
        [string] $FramesFolder = '',
        [string] $TorsoFramesFolder = '',
        [string] $SpecFilePath = '',
        [scriptblock] $LogoFinalAction = $null,
        [int] $LogoFinalHoldMs = 2000,
        [int] $LogoOnlineRow = 0,
        [switch] $NoUnitImage
    )
    if ($GLOBAL:_SkyNetCore.Instant) {
        # Пролог — декоративная вставка; -Instant предназначен для быстрых
        # smoke-прогонов без анимации, поэтому целиком пропускаем его здесь,
        # а не гоняем внутренние тайминги на нулевых задержках.
        try { Write-SkynetLog -Message 'Prologue: -Instant — пролог пропущен целиком.' -Level 'DEBUG' -Module 'Prologue' } catch { }
        return
    }
    # Звуковой слой поднимается один раз на весь пролог и держится до конца.
    # Если модуля SkyNet.Audio нет или звук выключен — вызов вернёт $false.
    Initialize-SkynetSound
    $geo = Get-SkynetConsoleGeometry
    Clear-SkynetFrame -LineCount $geo.Height -TopRow 1

    # Настоящий beginning: белая SSH/remote-boot сцена и захват PowerShell
    # происходят до логотипа. Два пустых абзаца после SYSTEM ONLINE уже
    # добавлены внутри Show-SkynetSshIntro.
    Write-SkynetLog -Message 'Prologue: начало SSH/remote boot sequence.' -Level 'INFO' -Module 'Prologue'
    Show-SkynetSshIntro
    Show-SkynetTerminalHijack
    Write-SkynetLog -Message 'Prologue: SSH и захват PowerShell завершены; начинается сборка логотипа.' -Level 'INFO' -Module 'Prologue'
    Clear-SkynetFrame -LineCount $geo.Height -TopRow 1
    # Пауза чёрного экрана перед сборкой логотипа уменьшена вдвое: 250 → 125 мс.
    Start-Sleep -Milliseconds 125

    # Логотип: символьная сборка → видимый финальный символьный кадр →
    # Sixel-кадр → SKYNET SYSTEM ONLINE прямо под логотипом.
    Show-SkynetLogoNoiseReveal -Lines $LogoLines -TopRow $LogoTopRow -HoldMs 1600
    if ($LogoFinalAction) {
        # Символьный кадр был видимым 1,6 с; перед Sixel полностью убираем его,
        # чтобы старая ASCII-картинка не просвечивала за пикселями и не смещала
        # визуальный центр финального кадра.
        Clear-SkynetFrame -LineCount $geo.Height -TopRow 1
        & $LogoFinalAction
        try { Write-SkynetLog -Message 'Prologue: финальный Sixel-кадр выведен после символьной сборки.' -Level 'INFO' -Module 'Render' } catch { }
    }

    if ($LogoOnlineRow -le 0) { $LogoOnlineRow = $LogoTopRow + $LogoLines.Count }
    $LogoOnlineRow = [Math]::Min([int]$geo.Height, $LogoOnlineRow)
    # Финальный Sixel-кадр и мигающая ONLINE-надпись вместе занимают ровно 2 с.
    $logoFinalDurationMs = [Math]::Max(0, $LogoFinalHoldMs)
    Show-SkynetOnlineBlink -Row $LogoOnlineRow -DurationMs $logoFinalDurationMs
    $esc = Get-SkynetPrologueEsc
    [Console]::Out.Write("${esc}[0m${esc}[40m${esc}[3J${esc}[2J${esc}[H")
    Show-SkynetRadarBoot -Speed 1.5
    try { Write-SkynetLog -Message 'Prologue: GLOBAL DEFENSE NETWORK показан на скорости 1.5x.' -Level 'INFO' -Module 'Prologue' } catch { }
    # ТТХ выводится вдвое быстрее: 2 мс на знак и 22 мс между строками.
    Show-SkynetUnitScan -FramesFolder $FramesFolder -SpecFilePath $SpecFilePath `
        -CharDelayMs 2 -LineGapMs 22 -TailHoldMs 1800 -FrameCycles 1 -FrameIntervalMs 8 -NoUnitImage:$NoUnitImage

    # Торс показываем ТОЛЬКО если это отдельная папка кадров: иначе (по умолчанию
    # кадры головы и торса — одна и та же последовательность) вращение пошло бы
    # вторым кругом, а пользователь просил один цикл прокрутки изображений.
    $torsoDistinct = $false
    if ($TorsoFramesFolder -and $FramesFolder) {
        $torsoDistinct = ($TorsoFramesFolder.TrimEnd('\', '/') -ine $FramesFolder.TrimEnd('\', '/'))
    } elseif ($TorsoFramesFolder) {
        $torsoDistinct = $true
    }
    if ($torsoDistinct) {
        Show-SkynetTorsoScan -FramesFolder $TorsoFramesFolder
    } else {
        try { Write-SkynetLog -Message 'Prologue: сцена торса пропущена — отдельной папки кадров нет (один цикл вращения).' -Level 'DEBUG' -Module 'Prologue' } catch { }
    }

    Show-SkynetOpticalCheck
    Clear-SkynetFrame -LineCount $geo.Height -TopRow 1
    # Звук НЕ закрываем здесь: основное шоу и финал идут после пролога, а
    # фоновый гул должен играть до самого финала. Освобождает устройства
    # владелец шоу — Core\launch_skynet.ps1 в своём finally.
}

$script:PrologueExports = @(
    'Format-SkynetDottedLine', 'Write-SkynetGlitchLine', 'Show-SkynetSshIntro', 'Show-SkynetTerminalHijack',
    'Get-SkynetScrambledAnsiLine', 'Show-SkynetLogoNoiseReveal', 'Show-SkynetOnlineBlink', 'Show-SkynetRadarBoot',
    'Get-SkynetFrameNumberFromPath', 'Get-SkynetScanStages', 'Get-SkynetScanStage',
    'Get-SkynetScanAnnotation', 'Get-SkynetCyberdyneScanBlock', 'Get-SkynetLocalSystemInfo',
    'Get-SkynetT800ScanLines', 'Resolve-SkynetSpecFile', 'Format-SkynetWrappedText', 'Get-SkynetSpecScanLines',
    'Get-SkynetSpecMarqueeText', 'Write-SkynetScanPanelRow', 'Write-SkynetScanHeadFrame',
    'Show-SkynetBodyScan', 'Show-SkynetUnitScan', 'Show-SkynetTorsoScan',
    'Show-SkynetOpticalCheck', 'Show-SkynetPrologue'
)
Export-ModuleMember -Function $script:PrologueExports
