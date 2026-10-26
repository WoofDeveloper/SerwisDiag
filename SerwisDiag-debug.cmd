@echo off
setlocal EnableExtensions
rem SerwisDiag - okno programu z widoczna konsola (do diagnozowania problemow z samym programem).
rem Po zamknieciu okna konsola czeka na Enter, aby mozna bylo odczytac komunikaty.
chcp 65001 >nul 2>&1

set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0SerwisDiag.ps1" -Elevate -Pause %*
endlocal
