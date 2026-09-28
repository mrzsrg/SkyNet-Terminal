<#
.SYNOPSIS
    Сверка звуковой карты в README с живым кодом.

.DESCRIPTION
    Таблица «какой звук за какую сцену» в README неизбежно устаревает: сцены
    добавляются, курки переименовываются, а цепочки меняются. Этот скрипт
    ловит расхождения автоматически и печатает, что именно разъехалось:

    1) каждый курок из $script:Cues (Modules/SkyNet.Audio.psm1) упомянут в README;
    2) в README нет курков, которых больше нет в коде (призраки);
    3) колонка «Играет сейчас» совпадает с первым файлом цепочки;
    4) нет мёртвых курков — объявленных, но нигде не вызываемых.

    Код возврата: 0 — расхождений нет, 1 — есть (пригодно для CI).

.EXAMPLE
    .\Tools\check_audio_docs.ps1
#>
[CmdletBinding()]
param([string] $Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Path) { $Path = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path }
$Path = (Resolve-Path -LiteralPath $Path).Path

$root = $Path
foreach ($m in 'SkyNet.Core', 'SkyNet.Log', 'SkyNet.Audio') {
    Import-Module (Join-Path $root "Modules\$m.psm1") -Force -ErrorAction Stop
}
$null = Import-SkynetJsonConfig -Path (Join-Path $root 'config\skynet.json')
$null = [Console]::Out
$null = Initialize-SkynetAudio
$map = Get-SkynetSoundMap
Close-SkynetAudio

$readme = Get-Content (Join-Path $root 'README.md') -Raw -Encoding UTF8
$fail = 0

# 1) Каждый курок из кода упомянут в README.
$missing = @($map | Where-Object { $readme -notmatch [regex]::Escape(('`' + $_.Cue + '`')) })
if ($missing.Count) {
    Write-Host "FAIL: курки не упомянуты в README: $($missing.Cue -join ', ')" -ForegroundColor Red
    $fail++
} else {
    Write-Host "OK: все $($map.Count) курков из кода есть в README" -ForegroundColor Green
}

# 2) В README нет курков, которых больше нет в коде.
$inReadme = [regex]::Matches($readme, '`(boot|step|mem|scan|prompt|hijack|override|status|online|glitch_hard|glitch|alert|radar|zone_done|zone|ok|connect|waiting|lost|blocked|final)`') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$ghost = @($inReadme | Where-Object { $map.Cue -notcontains $_ })
if ($ghost.Count) {
    Write-Host "FAIL: в README есть несуществующие курки: $($ghost -join ', ')" -ForegroundColor Red
    $fail++
} else {
    Write-Host 'OK: в README нет курков-призраков' -ForegroundColor Green
}

# 3) «Играет сейчас» совпадает с первым файлом цепочки.
$bad = @()
foreach ($row in $map) {
    $first = ($row.File -split ' \| ')[0]
    $lines = $readme -split "`r?`n" | Where-Object { $_ -match ('^\|.*`' + [regex]::Escape($row.Cue) + '`') }
    if (-not ($lines | Where-Object { $_ -match [regex]::Escape($first) })) {
        $bad += "$($row.Cue) -> README не упоминает '$first'"
    }
}
if ($bad.Count) {
    $bad | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    $fail++
} else {
    Write-Host 'OK: «Играет сейчас» в README совпадает с цепочками в коде' -ForegroundColor Green
}

# 4) Нет мёртвых курков. Берём ЛЮБОе строковое имя курка из модулей сцен, а не
#    только -Name 'x' / -Cue 'x': в Boot курки живут в хештаблицах
#    (Cue = 'alert'), в Glitch — внутри $(if ...) { '...' }. Наивный разбор
#    объявлял их мёртвыми и тем самым врал.
$used = @()
foreach ($f in 'SkyNet.Prologue', 'SkyNet.Boot', 'SkyNet.Finale', 'SkyNet.Glitch') {
    $t = Get-Content (Join-Path $root "Modules\$f.psm1") -Raw -Encoding UTF8
    foreach ($cue in (@($map.Cue) + @('glitch*'))) {
        if ($t -match ("'" + [regex]::Escape($cue) + "'")) { $used += $cue }
    }
}
$dead = @($map.Cue | Sort-Object -Unique | Where-Object { $used -notcontains $_ })
if ($dead.Count) {
    Write-Host "FAIL: курки без вызовов (мёртвые): $($dead -join ', ')" -ForegroundColor Red
    $fail++
} else {
    Write-Host 'OK: мёртвых курков нет' -ForegroundColor Green
}

Write-Host ''
if ($fail) { Write-Host "Расхождений: $fail" -ForegroundColor Red; exit 1 }
Write-Host "Звуковая карта в README актуальна (курков: $($map.Count))." -ForegroundColor Green
exit 0