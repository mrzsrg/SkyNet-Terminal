<#
.SYNOPSIS
    Безопасный выход из проекта: всё, что не попало в коммит, сохраняется.

.DESCRIPTION
    Нужно, когда вы закончили работу и хотите переключиться на другой
    проект, но боитесь потерять несохранённое. Скрипт за один запуск:

      1) проверяет, что рабочее дерево не потеряно (git status);
      2) если есть незакоммиченные изменения — делает из них отдельный
         коммит «запасной», ничего не удаляя;
      3) ставит тег- якорь на текущее состояние, к которому всегда
         можно вернуться одной командой;
      4) копирует изменённые файлы в папку вне репозитория
         (C:\Users\<user>\Desktop\SkyNet_rescue_<дата>), потому что
         при переключении папок в редакторе буфер может пропасть.

    Код возврата: 0 — можно переключаться, 1 — что-то пошло не так.

.PARAMETER SkipRescue
    Не делать копию файлов вне репозитория (только коммит и тег).

.PARAMETER Message
    Текст запасного коммита. По умолчанию — с датой.

.EXAMPLE
    .\Tools\safe_leave.ps1

.EXAMPLE
    .\Tools\safe_leave.ps1 -Message "Звук радара, вручную"
#>
[CmdletBinding()]
param(
    [switch] $SkipRescue,
    [string] $Message
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

Write-Host ''
Write-Host '=== SkyNet: безопасный выход из проекта ===' -ForegroundColor Cyan
Write-Host "Папка: $root"
Write-Host ''

# --- 1. Состояние репозитория -------------------------------------------------
$status = @(git status --porcelain)
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$head   = (git rev-parse --short HEAD).Trim()
Write-Host "Ветка: $branch   HEAD: $head   Незакоммиченных: $($status.Count)"

if ($status.Count -eq 0) {
    Write-Host 'Рабочее дерево чистое — терять нечего.' -ForegroundColor Green
}
else {
    Write-Host 'Есть незакоммиченные изменения:' -ForegroundColor Yellow
    foreach ($line in $status) { Write-Host "  $line" }
}

# --- 2. Запасной коммит --------------------------------------------------------
# Делается всегда, если есть что коммитить: так переключение папок
# в редакторе ничего не уносит с собой.
if ($status.Count -gt 0) {
    if (-not $Message) {
        $Message = 'Запасной авто-коммит перед переключением проекта, ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
    }
    git add -A
    git commit -m $Message | Out-Null
    $new = (git rev-parse --short HEAD).Trim()
    Write-Host "Запасной коммит создан: $new" -ForegroundColor Green
    $status = @(git status --porcelain)
    $head   = $new
    if ($status.Count -gt 0) {
        Write-Host "ВНИМАНИЕ: после коммита осталось $($status.Count) записей — проверьте вручную." -ForegroundColor Red
    }
}

# --- 3. Тег-якорь --------------------------------------------------------------
# Возврат одной командой: git switch --detach <тег>.
# Ставится ДО копии: RESCUE.txt внутри копии ссылается на этот тег,
# и без этого ссылки в нём не будет.
$tag = 'anchor-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
git tag $tag | Out-Null
Write-Host "Тег-якорь: $tag" -ForegroundColor Green

# --- 4. Копия файлов вне репозитория ------------------------------------------
# Страховка от буфера редактора: папка лежит на рабочем столе рядом
# с проектом и переживает переключение.
$rescue = $null
if (-not $SkipRescue) {
    $stamp  = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $rescue = Join-Path ([Environment]::GetFolderPath('Desktop')) "SkyNet_rescue_$stamp"
    try {
        # Копируем ВЕСЬ исходный код проекта, а не только файлы последнего
        # коммита: страховка должна пережить переключение папки целиком.
        # Тяжёлое (assets, кадры, exe) не трогаем — это восстанавливается
        # и местами весит сотни мегабайт.
        $tracked = @(git ls-files '*.ps1' '*.psm1' '*.cs' '*.json' '*.md' '*.cmd' '*.txt')
        foreach ($f in $tracked) {
            $src = Join-Path $root $f
            if (-not (Test-Path -LiteralPath $src)) { continue }
            $dst = Join-Path $rescue $f
            $dir = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
        $copied = @(Get-ChildItem -Path $rescue -Recurse -File).Count
        # Состояние репозитория фиксируем текстом, чтобы восстановиться
        # вручную можно было даже без git. Русские сообщения коммитов git
        # отдаёт в UTF-8, а PowerShell на Windows декодирует вывод нативных
        # команд через [Console]::OutputEncoding (по умолчанию CP866) —
        # отсюда мусор вроде «╨Т╨Н╨С╨А». Поэтому на время чтения
        # кодировку принудительно ставим в UTF-8.
        $gitLog = @()
        $gitStatus = ''
        $prevEnc = $null
        try {
            $prevEnc = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            $gitLog = @(git log --oneline -5)
            $gitStatus = ((git status --short) -join "`n").TrimEnd()
        }
        finally {
            if ($null -ne $prevEnc) { [Console]::OutputEncoding = $prevEnc }
        }

        $log = @()
        $log += "SkyNet rescue $stamp"
        $log += "HEAD: $head  ($branch)"
        $log += ''
        $log += '--- git status ---'
        $log += $(if ($gitStatus) { $gitStatus } else { '(чисто)' })
        $log += ''
        $log += '--- последние коммиты ---'
        $log += $gitLog
        $log += ''
        $log += '--- вернуться к этому состоянию ---'
        $log += "git switch --detach $tag"
        Set-Content -LiteralPath (Join-Path $rescue 'RESCUE.txt') -Value $log -Encoding UTF8
        Write-Host "Копия сохранена: $rescue  (файлов: $copied)" -ForegroundColor Green
    }
    catch {
        Write-Host "Копию сделать не удалось: $($_.Exception.Message)" -ForegroundColor Yellow
        $rescue = $null
    }
}

Write-Host ''
Write-Host 'ГОТОВО. Теперь можно спокойно переключать папку.' -ForegroundColor Green
Write-Host ''
Write-Host 'Если что-то пошло не так, вернуть состояние одной командой:' -ForegroundColor Yellow
Write-Host "  git switch --detach $tag"
if ($rescue) {
    Write-Host "или просто скопировать файлы из: $rescue" -ForegroundColor Yellow
}
Write-Host ''
