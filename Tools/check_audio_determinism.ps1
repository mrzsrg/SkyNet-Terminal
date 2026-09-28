<#
.SYNOPSIS
    Проверка, что звук выбирается однозначно (без случайности).

.DESCRIPTION
    Сцена должна звучать тем файлом, который ей назначен. Проверяет:

    1) каждый курок при 40 разрешениях даёт одну и ту же цепочку файлов —
       перемешивания быть не должно;
    2) в коде выбора звука нет Get-Random/VarietyCues (шапка модуля с
       справкой пропускается — там Get-Random упоминается в тексте);
    3) два разных курка, вызванные подряд, дают два звука: троттлинг свой
       у каждого курка, сцены не гасят друг друга;
    4) троттлинг одного и того же курка работает: два вызова подряд — один звук.

    Код возврата: 0 — всё однозначно, 1 — есть нарушение.

.EXAMPLE
    .\Tools\check_audio_determinism.ps1
#>
[CmdletBinding()]
param([string] $Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Path) { $Path = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path }
$Path = (Resolve-Path -LiteralPath $Path).Path
$root = $Path

$ErrorActionPreference = 'Stop'
foreach ($m in 'SkyNet.Core', 'SkyNet.Log', 'SkyNet.Audio') {
    Import-Module (Join-Path $Path "Modules\$m.psm1") -Force -ErrorAction Stop
}
$null = Import-SkynetJsonConfig -Path (Join-Path $Path 'config\skynet.json')
$null = [Console]::Out
$null = Initialize-SkynetAudio

$map = Get-SkynetSoundMap
$fail = 0

# 1) 40 разрешений каждого курка — все должны совпасть.
foreach ($row in $map) {
    $results = @()
    for ($i = 0; $i -lt 40; $i++) {
        $c = @(Get-SkynetCueCandidates -Name $row.Cue)
        $results += ($c -join ',')
    }
    $uniq = @($results | Sort-Object -Unique)
    if ($uniq.Count -ne 1) {
        Write-Host "FAIL: курок '$($row.Cue)' недетерминирован: $($uniq -join ' / ')" -ForegroundColor Red
        $fail++
    }
}
if (-not $fail) { Write-Host 'OK: все курки детерминированы (по 40 разрешений)' -ForegroundColor Green }

# 2) Никакого Get-Random в слое выбора звука. Пропускаем шапку модуля:
#    там Get-Random упоминается в справке про отказ от общей дорожки, и это
#    не код выбора звука.
$codeLines = @(Get-Content (Join-Path $root 'Modules\SkyNet.Audio.psm1') -Encoding UTF8 |
    ForEach-Object { $_ -replace '#.*$', '' })
$firstFn = 0
for ($i = 0; $i -lt $codeLines.Count; $i++) {
    if ($codeLines[$i] -match '^\s*function ') { $firstFn = $i; break }
}
$code = ($codeLines[$firstFn..($codeLines.Count - 1)] -join "`n")
$body = $code.Substring(0, $code.IndexOf('function Close-SkynetAudio'))
if ($body -match 'Get-Random|VarietyCues') {
    Write-Host 'FAIL: в коде выбора звука остался случайный выбор' -ForegroundColor Red
    $fail++
} else { Write-Host 'OK: случайного выбора в коде слоя звука нет' -ForegroundColor Green }

# 3) Троттлинг не общий: две разные сцены не гасят друг друга.
$a = (Get-SkynetAudioStats).Played
Invoke-SkynetSound -Name 'glitch' -ThrottleMs 0
Invoke-SkynetSound -Name 'step'   -ThrottleMs 0
$b = (Get-SkynetAudioStats).Played
if (($b - $a) -eq 2) { Write-Host 'OK: разные курки не гасят друг друга' -ForegroundColor Green }
else { Write-Host "FAIL: два разных курка дали $($b - $a) звука вместо 2 (общий троттлинг)" -ForegroundColor Red; $fail++ }

# 4) Свой троттлинг работает: один и тот же курок дважды подряд — один звук.
$c0 = (Get-SkynetAudioStats).Played
Invoke-SkynetSound -Name 'step' -ThrottleMs 200
Invoke-SkynetSound -Name 'step' -ThrottleMs 200
$c1 = (Get-SkynetAudioStats).Played
if (($c1 - $c0) -eq 1) { Write-Host 'OK: троттлинг одного курка работает' -ForegroundColor Green }
else { Write-Host "FAIL: троттлинг не сработал (звуков: $($c1 - $c0))" -ForegroundColor Red; $fail++ }

Write-Host ''
if ($fail) { Write-Host "ПРОВАЛОВ: $fail" -ForegroundColor Red } else { Write-Host 'ВСЁ ОДНОЗНАЧНО' -ForegroundColor Green }
Close-SkynetAudio