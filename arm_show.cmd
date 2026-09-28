@echo off
rem SKYNET: создаёт и сразу запускает задачу SKYNET_SHOW (шоу в максимизированном окне терминала).
rem Пути берутся от расположения этого файла (%~dp0), без привязки к OneDrive.
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

rem Оболочка для задачи ищется ЯВНО, полным путём. Раньше здесь был откат на голое
rem имя "pwsh.exe": если PowerShell 7 не установлен, Планировщик запускал задачу
rem и получал 0x80070002 "Не удается найти указанный файл" - вкладка терминала
rem открывалась и сразу закрывалась, шоу не стартовало. Сначала PowerShell 7,
rem и только потом Windows PowerShell 5.1 (шоу на нём работает).
set "PWSH="
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PWSH=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
if not defined PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH if exist "%ProgramFiles%\PowerShell\7-preview\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7-preview\pwsh.exe"
if not defined PWSH for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do if not defined PWSH set "PWSH=%%P"
if not defined PWSH if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "PWSH=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not defined PWSH (
    echo [SKYNET] Не найден ни PowerShell 7, ни Windows PowerShell 5.1
    echo [SKYNET] Установите PowerShell 7: winget install --id Microsoft.PowerShell --source winget
    exit /b 1
)

set "STARTER=%ROOT%\Core\start_skynet_fullscreen.ps1"
if not exist "%STARTER%" (
    echo [SKYNET] Не найден %STARTER%
    exit /b 1
)

if not exist "%ROOT%\logs" mkdir "%ROOT%\logs"

schtasks /Create /TN SKYNET_SHOW /TR "\"%PWSH%\" -NoProfile -ExecutionPolicy Bypass -File \"%STARTER%\" -Pause" /SC ONCE /ST 23:59 /F
echo [%DATE% %TIME%] task created: %PWSH% -File "%STARTER%" >> "%ROOT%\logs\skynet_schtasks.log"
schtasks /Run /TN SKYNET_SHOW
endlocal
