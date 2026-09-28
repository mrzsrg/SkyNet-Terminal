<#
.SYNOPSIS
    SkyNet Log — единая система логирования.

.DESCRIPTION
    Логи с уровнями DEBUG / INFO / WARN / ERROR / FATAL.
    Формат: [2026-09-21 11:25:38] [INFO] [Core] Message here

    Записи идут В ФАЙЛ (по умолчанию logs\skynet_boot.log в корне проекта),
    чтобы не рвать кадровую анимацию бегущей строки и затухания логотипа.
    В консоль логи выводятся только если это включено явно
    (config/skynet.json → Logging.Console или -LogToConsole);
    сообщения уровня ERROR/FATAL печатаются всегда.
    Файл ротируется по размеру (Logging.MaxSizeKB).
#>

function Get-SkynetLogLevelMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{ DEBUG = 0; INFO = 1; WARN = 2; ERROR = 3; FATAL = 4 }
}

function Set-SkynetLogLevel {
    <#
    .SYNOPSIS
        Минимальный уровень логирования.
    #>
    [CmdletBinding()]
    param([ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')][string] $Level = 'INFO')
    if ($GLOBAL:_SkyNetCore) { $GLOBAL:_SkyNetCore.LogMinLevel = $Level }
    Set-SkynetConfig -Key 'LogMinLevel' -Value $Level
}

function Set-SkynetLogFile {
    <#
    .SYNOPSIS
        Путь к файлу логов.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    if ($GLOBAL:_SkyNetCore) { $GLOBAL:_SkyNetCore.LogFile = $Path }
}

function Enable-SkynetLogging {
    <# .SYNOPSIS Включить логирование. #>
    [CmdletBinding()] param()
    if ($GLOBAL:_SkyNetCore) { $GLOBAL:_SkyNetCore.LogEnabled = $true }
}

function Disable-SkynetLogging {
    <# .SYNOPSIS Выключить логирование. #>
    [CmdletBinding()] param()
    if ($GLOBAL:_SkyNetCore) { $GLOBAL:_SkyNetCore.LogEnabled = $false }
}

function Enable-SkynetConsoleLog {
    <# .SYNOPSIS Выводить логи и в консоль (по умолчанию выключено). #>
    [CmdletBinding()] param()
    if ($GLOBAL:_SkyNetCore) { $GLOBAL:_SkyNetCore.LogConsole = $true }
}

function Disable-SkynetConsoleLog {
    <# .SYNOPSIS Не выводить логи в консоль. #>
    [CmdletBinding()] param()
    if ($GLOBAL:_SkyNetCore) { $GLOBAL:_SkyNetCore.LogConsole = $false }
}

function Remove-SkynetOldLogs {
    <#
    .SYNOPSIS
        Ротация лог-файла по размеру.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path, [int] $MaxSizeKB = 5120)

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
        $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if (-not $item -or $item.Length -lt ([int64] $MaxSizeKB * 1024)) { return }
        $backup = "$Path.1"
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
        Move-Item -LiteralPath $Path -Destination $backup -Force -ErrorAction SilentlyContinue
    } catch { }
}

function Write-SkynetLog {
    <#
    .SYNOPSIS
        Записать сообщение в лог (и, при необходимости, в консоль).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')][string] $Level = 'INFO',
        [string] $Module = 'Core'
    )

    $cfg = $GLOBAL:_SkyNetCore
    $enabled = if ($cfg) { [bool] $cfg.LogEnabled } else { $true }
    if (-not $enabled) { return }

    $levels = Get-SkynetLogLevelMap
    $minLevel = if ($cfg -and $cfg.LogMinLevel) { [string] $cfg.LogMinLevel } else { 'INFO' }
    if ($levels[$Level] -lt $levels[$minLevel]) { return }

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$stamp] [$Level] [$Module] $Message"

    # Консоль: только по флагу, а ошибки — всегда (иначе сбои останутся незамеченными).
    $toConsole = ($cfg -and [bool] $cfg.LogConsole) -or $Level -eq 'ERROR' -or $Level -eq 'FATAL'
    if ($toConsole) {
        if (Get-Command Write-SkynetHud -ErrorAction SilentlyContinue) {
            $color = switch ($Level) {
                'DEBUG' { $GLOBAL:ColDim }
                'INFO' { $GLOBAL:ColBright }
                'WARN' { $GLOBAL:ColWarn }
                default { $GLOBAL:ColError }
            }
            Write-SkynetHud -Text $line -Color $color
        } else {
            Write-Host $line
        }
    }

    $logFile = if ($cfg -and $cfg.LogFile) { [string] $cfg.LogFile } else { Join-Path $env:TEMP 'skynet_boot.log' }
    try {
        $dir = Split-Path -Parent $logFile
        if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        if ($cfg -and $cfg.LogRotate) { Remove-SkynetOldLogs -Path $logFile -MaxSizeKB ([int] $cfg.LogMaxSizeKB) }
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

$script:LogExports = @(
    'Write-SkynetLog', 'Set-SkynetLogLevel', 'Set-SkynetLogFile', 'Enable-SkynetLogging',
    'Disable-SkynetLogging', 'Enable-SkynetConsoleLog', 'Disable-SkynetConsoleLog',
    'Remove-SkynetOldLogs', 'Get-SkynetLogLevelMap'
)
Export-ModuleMember -Function $script:LogExports
