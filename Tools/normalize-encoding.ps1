<#
.SYNOPSIS
    Нормализация кодировок и переводов строк в проекте.

.DESCRIPTION
    PowerShell 5.1 читает .ps1/.psm1 без BOM как ANSI (cp866) и ломает
    кириллицу в комментариях и строках — поэтому все скрипты и модули
    сохраняются в UTF-8 С BOM и с переводами строк CRLF.

    Файлы данных (.json), разметка (.md), пакетные файлы (.cmd) и .gitignore
    сохраняются в UTF-8 БЕЗ BOM: BOM в них ломает сторонние парсеры и cmd.exe.

.PARAMETER Path
    Корень проекта (по умолчанию — родитель папки Tools).

.EXAMPLE
    .\Tools\normalize-encoding.ps1
#>
[CmdletBinding()]
param([string] $Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Path) { $Path = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path }
$Path = (Resolve-Path -LiteralPath $Path).Path

# Служебные каталоги не трогаем: там лежат байт-в-байт копии прошлых версий.
$skipDirs = @('backup_v2.4.1', 'legacy', '.git', 'logs', 'assets')

$bomExtensions = @('.ps1', '.psm1', '.psd1', '.cs')
$plainExtensions = @('.json', '.md', '.cmd', '.txt', '.gitignore')

$utf8Bom = [System.Text.UTF8Encoding]::new($true)
$utf8Plain = [System.Text.UTF8Encoding]::new($false)
$stats = @{ BOM = 0; Plain = 0; Skipped = 0 }

$files = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $relative = $_.FullName.Substring($Path.Length).TrimStart('\')
    $skip = $false
    foreach ($dir in $skipDirs) { if ($relative -like "$dir\*" -or $relative -eq $dir) { $skip = $true } }
    -not $skip
}

foreach ($file in $files) {
    $extension = $file.Extension.ToLowerInvariant()
    if ($file.Name -eq '.gitignore') { $extension = '.gitignore' }

    $withBom = $bomExtensions -contains $extension
    $plain = $plainExtensions -contains $extension
    if (-not $withBom -and -not $plain) { $stats.Skipped++; continue }
    if ($file.Length -gt 4MB) { $stats.Skipped++; continue }

    $text = [System.IO.File]::ReadAllText($file.FullName)
    $normalized = $text -replace "`r`n", "`n" -replace "`r", "`n" -replace "`n", "`r`n"

    $encoding = if ($withBom) { $utf8Bom } else { $utf8Plain }
    [System.IO.File]::WriteAllText($file.FullName, $normalized, $encoding)

    if ($withBom) { $stats['BOM']++ } else { $stats['Plain']++ }
}

Write-Host ("[SKYNET] Нормализовано: UTF-8+BOM — {0}, UTF-8 без BOM — {1}, пропущено — {2}" -f $stats['BOM'], $stats['Plain'], $stats['Skipped']) -ForegroundColor Green

