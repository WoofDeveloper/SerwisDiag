@echo off
setlocal EnableExtensions
rem SerwisDiag - tryb konsolowy (bez okna): wykonuje diagnostyke i zapisuje raporty.
rem Prosi o uprawnienia administratora (UAC) - diagnostyka uruchomi sie wtedy w nowym oknie.
rem Przyklady:  SerwisDiag-konsola.cmd
rem             SerwisDiag-konsola.cmd -Level Full -Ticket 2025-014 -Customer "Jan Kowalski"
rem             SerwisDiag-konsola.cmd -TestIds tt.disk,tt.cpu
rem             SerwisDiag-konsola.cmd -CompareWith raporty\przed.json -WorkDone "Wymiana dysku na SSD"
rem             SerwisDiag-konsola.cmd -CompareBefore przed.json -CompareAfter po.json -WorkDone "Czyszczenie"
chcp 65001 >nul 2>&1

set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0SerwisDiag.ps1" -NoGui -Elevate -Pause %*
endlocal
