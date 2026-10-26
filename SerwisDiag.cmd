@echo off
setlocal EnableExtensions
rem SerwisDiag - uruchamia program (okno graficzne) i prosi o uprawnienia administratora (UAC).
rem Po odmowie program dziala bez nich (czesc testow zostanie pominieta).
rem Dziala w Windows 8, 8.1, 10 i 11. Wymaga tylko wbudowanego Windows PowerShell 3.0 lub nowszego.
rem Parametry sa przekazywane do programu, np.:  SerwisDiag.cmd -Ticket 2025-014 -Customer "Jan Kowalski"

set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
start "" "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0SerwisDiag.ps1" -Elevate %*
endlocal
