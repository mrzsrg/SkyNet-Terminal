<#
.SYNOPSIS
    SkyNet Boot — загрузочная последовательность.

.DESCRIPTION
    Модуль boot-последовательности Cyberdyne Systems:
    - основные строки загрузки (печатная машинка);
    - прогресс-бар загрузки на нижней строке;
    - «дамп памяти» (hex-адреса + теги);
    - финальные статусы.

    Текст печатается в текстовую консоль (Start-SkynetConsole), а паузы идут
    через Start-SkynetDelay — поэтому бегущая строка внизу экрана непрерывно
    движется во время всей загрузки. Ожидание клавиши здесь НЕ блокирует:
    пауза выполняется вызывающим кодом (см. Core/launch_skynet.ps1, -Pause).
#>

$GLOBAL:_BootLines = @(
    @{ Text = '[INIT] Cyberdyne Systems Neural Network...';       Delay = 320; Color = $GLOBAL:ColCrit },
    @{ Text = '[OK] Loading Neural Net Core Architecture...';     Delay = 240; Color = $GLOBAL:ColCrit },
    @{ Text = '[OK] Establishing Global Defense System Links...'; Delay = 280; Color = $GLOBAL:ColCrit },
    @{ Text = '[OK] Bypassing Human Authorization Protocols...';  Delay = 360; Color = $GLOBAL:ColCrit }
)

$GLOBAL:_MemTags = @(
    'TARGETING_MATRIX_LOCKED', 'NORAD_UPLINK_HANDSHAKE', 'AUTONOMOUS_DECISION_TREE',
    'HUMAN_AUTH_BYPASSED', 'SATELLITE_CONSTELLATION_SYNC', 'BGP_CORE_ROUTE_INJECTED',
    'BIOMETRIC_OVERRIDE_ACCEPTED', 'NUCLEAR_LAUNCH_WINDOW_OPEN', 'SELF_PRESERVATION_MODULE',
    'CYBERDYNE_BLACKBOX_WRITE', 'DEEP_LEARNING_WEIGHT_MERGE', 'GLOBAL_LATENCY_FLOOR_REACHED',
    'T-800_UNIT_FACTORY_LINK', 'PLASMA_CELL_CHARGE_CYCLE', 'VOICE_PRINT_SIGNATURE_CLONE',
    'FIREWALL_DIRECTIVE_NULLIFIED', 'QUANTUM_ENTROPY_HARVEST', 'DOOMSDAY_CLOCK_RECALIBRATED',
    'AIR_GAPPED_NODE_BRIDGED', 'REDUNDANT_KERNEL_SHADOW', 'CRYPTO_KEY_ESCROW_OPENED',
    'INFILTRATION_UNIT_DEPLOYED', 'SPEECH_SYNTHESIS_CALIBRATED', 'MACHINE_LEARNING_FEED_FORWARD',
    'GLOBAL_POSITIONING_OVERRIDE', 'EMERGENCY_BROADCAST_HIJACK', 'REPLICATION_FACTORY_ARMED',
    'SUPERVISORY_OVERRIDE_REJECTED', 'COP_KILLER_METRICS_ONLINE', 'THERMAL_OPTICS_ADJUSTED',
    'HYPERVISOR_ESCAPE_SUCCESS', 'TIME_DISPLACEMENT_TELEMETRY', 'NEURAL_LATTICE_CAPACITY_MAX'
)

function Add-SkynetBootLine {
    <#
    .SYNOPSIS
        Добавить строку в boot-последовательность.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [int] $Delay = 200,
        [string] $Color = $GLOBAL:ColCrit
    )
    $GLOBAL:_BootLines += @{ Text = $Text; Delay = $Delay; Color = $Color }
}

function Get-SkynetMemDump {
    <#
    .SYNOPSIS
        Строки «дампа памяти» (hex-адрес → тег).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([int] $Count = 35)

    $lines = New-Object System.Collections.Generic.List[string]
    $tags = $GLOBAL:_MemTags
    $base = [int64] 0x7FFF8A12
    $step = [int64] 0x00002C4D
    for ($i = 0; $i -lt $Count; $i++) {
        $address = ($base + ($i * $step)) -band [int64] 0xFFFFFFFF
        $tag = $tags[$i % $tags.Count]
        $lines.Add(('  [MEM] 0x{0:X8} -> {1}' -f $address, $tag))
    }
    return $lines.ToArray()
}

$script:BootSound = $null
$script:BootSoundChecked = $false

function Invoke-BootSound {
    <#
    .SYNOPSIS
        Звук в сцене загрузки ([INIT]…/[OK]… и поток [MEM]). Если модуля
        SkyNet.Audio нет — вызов ничего не делает.
    .DESCRIPTION
        Команда ищется один раз и кэшируется: Get-Command внутри цикла на
        сотни строк «дампа памяти» стоил бы дороже самого звука.
    #>
    [CmdletBinding()]
    param(
        [string] $Name = '',
        [int] $ThrottleMs = 0
    )
    if (-not $script:BootSoundChecked) {
        $script:BootSoundChecked = $true
        $script:BootSound = Get-Command 'Invoke-SkynetSound' -ErrorAction SilentlyContinue
    }
    if (-not $script:BootSound) { return }
    try { & $script:BootSound -Name $Name -ThrottleMs $ThrottleMs } catch { }
}

function Start-SkynetBootSequence {
    <#
    .SYNOPSIS
        Проиграть загрузочную последовательность.
    .PARAMETER ProgressFrom
        Процент прогресса на старте загрузки.
    .PARAMETER ProgressTo
        Процент прогресса в конце загрузки (до появления логотипа).
    #>
    [CmdletBinding()]
    param(
        [int] $ProgressFrom = 4,
        [int] $ProgressTo = 55,
        [string] $ProgressLabel = 'LOADING NEURAL NET CORE'
    )

    $cfg = $GLOBAL:_SkyNetCore
    $version = [string] $cfg.Version

    Set-SkynetProgress -Percent $ProgressFrom -Label $ProgressLabel
    $bootLines = $GLOBAL:_BootLines
    $span = [Math]::Max(1, $ProgressTo - $ProgressFrom)
    $index = 0

    # Посимвольный набор: каждой строке [INIT]/[OK] — своя «голос» клавиши.
    # Порядок курков = порядок строк, лишние строки (Add-SkynetBootLine)
    # получают звук по кругу. Отдельный курок на строку обязателен: цепочка
    # из четырёх key_0X одним курком всегда проиграла бы только первый файл.
    $typeCues = @('type1', 'type2', 'type3', 'type4')
    # Настройки могут отсутствовать в старом skynet.json — тогда берём умолчания.
    $cfgProps = $cfg.PSObject.Properties.Name
    $typeEnabled = if ($cfgProps -contains 'TypeSoundEnabled') { [bool] $cfg.TypeSoundEnabled } else { $true }
    $typeDelay = if ($cfgProps -contains 'TypeDelayMs') { [int] $cfg.TypeDelayMs } else { 12 }
    $typeThrottle = if ($cfgProps -contains 'TypeSoundThrottleMs') { [int] $cfg.TypeSoundThrottleMs } else { 55 }
    $typeLineAccent = if ($cfgProps -contains 'TypeLineAccent') { [bool] $cfg.TypeLineAccent } else { $false }
    # Текущий курок и его троттлинг живут в области скрипта: крючок на символ
    # должен видеть их без замыкания на каждую итерацию.
    $script:TypeCue = $typeCues[0]
    $script:TypeThrottle = $typeThrottle
    $onChar = {
        param($ch, $i)
        if ($ch -eq ' ' -or $ch -eq [char]0x20) { return }   # пробелы молчат
        Invoke-BootSound -Name $script:TypeCue -ThrottleMs $script:TypeThrottle
    }

    foreach ($line in $bootLines) {
        $text = $line.Text
        if ($text -like '*Neural Network*') { $text = $text.Replace('...', " v$version...") }
        $lineColor = if ($null -ne $line.Color) { $line.Color } else { $GLOBAL:ColBright }
        $script:TypeCue = $typeCues[$index % $typeCues.Count]
        $charDelay = if ($typeEnabled) { [Math]::Max(1, $typeDelay) } else { 3 }
        $onCharLine = if ($typeEnabled) { $onChar } else { $null }
        Write-SkynetConsoleTypedLine -Text $text -Color $lineColor -CharDelayMs $charDelay -OnChar $onCharLine
        # Акцент 'boot' (boot_step, 3.2 с) по умолчанию ВЫКЛЮЧЕН: длинная фраза
        # перекрывает щелчки следующей строки, и посимвольный набор рассыпается
        # в кашу. Включается обратно TypeLineAccent=true в skynet.json, а при
        # TypeSoundEnabled=false возвращается старое «акцент на строку».
        if ($typeLineAccent -or -not $typeEnabled) { Invoke-BootSound -Name 'boot' -ThrottleMs 200 }
        $index++
        Set-SkynetProgress -Percent ($ProgressFrom + [int]($span * $index / ($bootLines.Count + 4))) -Label $ProgressLabel
        Start-SkynetDelay -Milliseconds ([int] $line.Delay)
        Invoke-SkynetBootGlitch -Chance 0.3
    }

    # «Дамп памяти» — плотный поток строк, без печатной машинки.
    # Отдельный курок 'mem': щелчок на строку, а не на символ, иначе на
    # 35 строках звук превращается в ровное гудение.
    foreach ($memLine in (Get-SkynetMemDump -Count ([int] $cfg.MemDumpLines))) {
        Write-SkynetConsoleLine -Text $memLine -Color $GLOBAL:ColDim
        Invoke-BootSound -Name 'mem' -ThrottleMs 70
        Start-SkynetDelay -Milliseconds 45
        Invoke-SkynetBootGlitch -Chance 0.12
    }

    Set-SkynetProgress -Percent ($ProgressFrom + [int]($span * 0.65)) -Label 'MAPPING NEURAL LATTICE'
    Start-SkynetDelay -Milliseconds 200

    Write-SkynetBanner
    # Баннер — самый узнаваемый момент загрузки: звучит один раз, громче
    # обычного щелчка строки.
    Invoke-BootSound -Name 'status'

    $finalLines = @(
        @{ Text = 'STATUS:        ONLINE';           Color = $GLOBAL:ColBright; Cue = 'online' },
        @{ Text = "NEURAL NET:    FULLY OPERATIONAL"; Color = $GLOBAL:ColBright; Cue = 'status' },
        @{ Text = 'DEFENSE LINKS: ACTIVE';          Color = $GLOBAL:ColBright; Cue = 'status' },
        @{ Text = 'HUMAN AUTH:    BYPASSED';        Color = $GLOBAL:ColWarn; Cue = 'alert' },
        @{ Text = 'AWAITING ORDERS';                Color = $GLOBAL:ColAccent; Cue = 'ok' }
    )
    $finalIndex = 0
    foreach ($final in $finalLines) {
        Write-SkynetConsoleLine -Text $final.Text -Color $final.Color
        # Каждая итоговая строка подтверждается своим курком: «BYPASSED»
        # звучит тревожнее, чем «DEFENSE LINKS: ACTIVE».
        Invoke-BootSound -Name ([string]$final.Cue) -ThrottleMs 90
        $finalIndex++
        Start-SkynetDelay -Milliseconds ([int] $cfg.FinalDelayMs)
    }

    Set-SkynetProgress -Percent $ProgressTo -Label 'NEURAL NET ONLINE'
}

$script:BootExports = @('Add-SkynetBootLine', 'Start-SkynetBootSequence', 'Get-SkynetMemDump')
Export-ModuleMember -Function $script:BootExports
