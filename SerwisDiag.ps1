<#
.SYNOPSIS
    SerwisDiag - zaawansowana diagnostyka komputerów z systemem Windows 8 / 8.1 / 10 / 11.

.DESCRIPTION
    Bez parametrów uruchamia okno programu. Z parametrem -NoGui działa w konsoli i zapisuje raporty.
    Wymaga Windows PowerShell 3.0 lub nowszego (wbudowany w Windows 8 i nowsze). Najlepiej uruchamiać jako administrator
    (-Elevate prosi o uprawnienia przez UAC; po odmowie program działa bez nich).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File SerwisDiag.ps1 -Elevate
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File SerwisDiag.ps1 -NoGui -Level Full -Ticket 2025-014 -Customer "Jan Kowalski"
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File SerwisDiag.ps1 -NoGui -Level Quick -TestIds tt.disk,tt.cpu
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File SerwisDiag.ps1 -NoGui -CompareWith raporty\2025-014_PC_20260101-1000.json -WorkDone "Wymiana dysku na SSD"
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File SerwisDiag.ps1 -CompareBefore przed.json -CompareAfter po.json -WorkDone "Czyszczenie, nowa pasta"
#>
param(
    [switch]$NoGui,
    [ValidateSet('Quick', 'Full')][string]$Level = 'Quick',
    [string]$TestIds = '',
    [string]$OutDir = '',
    [string]$Ticket = '',
    [string]$Customer = '',
    [string]$Technician = '',
    [string]$Note = '',
    [switch]$Open,
    [switch]$Offline,          # tryb bez internetu: pomija testy wymagające internetu (brak sieci nie jest wtedy usterką)
    [switch]$InstallDrivers,   # tryb konsolowy: po diagnostyce zainstaluj zalecane sterowniki z Windows Update (administrator)
    [switch]$Repair,           # tryb konsolowy: po diagnostyce wykonaj zalecane naprawy (lista: -RepairList)
    [string]$RepairIds = '',   # tryb konsolowy: wykonaj wskazane naprawy, np. fx.dism,fx.sfc,fx.cleanup
    [switch]$RepairList,       # tryb konsolowy: tylko pokaż, co program może naprawić (bez zmian)
    [switch]$Elevate,          # gdy brak uprawnień administratora: uruchom ponownie przez UAC
    [switch]$Pause,            # na końcu czekaj na Enter (okno konsoli otwarte przez .cmd)
    [switch]$SkipIntegrity,    # nie przerywaj, gdy pliki programu nie zgadzają się z manifestem
    [string]$CompareWith = '', # tryb konsolowy: po diagnostyce porównaj z wcześniejszym raportem JSON (przed naprawą)
    [string]$CompareBefore = '',
    [string]$CompareAfter = '',
    [string]$WorkDone = '',    # opis wykonanych czynności do raportu porównawczego
    [switch]$Pdf,              # tryb konsolowy: zapisz też raport dla klienta jako PDF (przez Microsoft Edge albo Chrome)
    [switch]$Anonymous,        # tryb konsolowy: zapisz też raport anonimowy (bez danych identyfikujących) do pokazania na forum
    [string]$Backup = '',      # kopia przed reinstalacją Windows do wskazanego folderu (bez diagnostyki)
    [string]$BackupInclude = '', # zawartość kopii: drivers,programs,system (domyślnie), dodatkowo wifi,bitlocker
    [string]$UndoRepair = '',  # cofnij zmiany ustawień z dziennika napraw: ścieżka *_naprawy.json albo "ostatni" (bez diagnostyki)
    [switch]$Monitor,          # monitorowanie w tle: ikona przy zegarze (uruchamia SerwisDiagMonitor.exe przy logowaniu)
    [switch]$EnableMonitor,    # wersja zainstalowana: włącz autostart monitorowania i uruchom je (-NoStart: bez uruchamiania)
    [switch]$DisableMonitor,   # wyłącz autostart monitorowania i zakończ działający monitor
    [switch]$NoStart,
    [switch]$Update,           # wersja zainstalowana: sprawdź, pobierz i zainstaluj nową wersję z GitHuba
    [switch]$SelfTest,
    [string]$ScreenshotPath = ''
)

$ErrorActionPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host 'SerwisDiag wymaga Windows PowerShell 3.0 lub nowszego (Windows 8 i nowsze).' -ForegroundColor Red
    exit 3
}

# Tryb ograniczony PowerShell (AppLocker, App Control, Smart App Control w Windows 11): program korzysta z wstawek C#
# i okna WPF, które w nim nie działają. Sprawdzenie i komunikat celowo bez wywołań .NET - w tym trybie działają tylko
# polecenia PowerShell i typy podstawowe. Bez tego użytkownik zobaczyłby niezrozumiały błąd albo (okno z ukrytą
# konsolą) nic.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    $blockText = @'
SerwisDiag nie może działać na tym komputerze.

PowerShell pracuje tu w trybie ograniczonym ({0}). Włącza go blokada uruchamiania programów:
AppLocker albo App Control na komputerach firmowych lub Smart App Control w Windows 11.
Program korzysta z wstawek C# i okna WPF, których w tym trybie nie da się uruchomić.

Co możesz zrobić:
 1. Komputer firmowy: poproś administratora IT o zgodę na uruchomienie programu.
 2. Program pobrany z internetu: zanim rozpakujesz plik ZIP, kliknij go prawym przyciskiem myszy,
    wybierz Właściwości, zaznacz Odblokuj i rozpakuj go ponownie.
 3. Smart App Control (Zabezpieczenia Windows > Kontrola aplikacji i przeglądarki): program zadziała
    po jego wyłączeniu. Wyłączaj go tylko za zgodą właściciela komputera - w starszych wersjach
    Windows 11 nie da się go potem włączyć bez ponownej instalacji systemu.
'@ -f $ExecutionContext.SessionState.LanguageMode
    Write-Host $blockText -ForegroundColor Yellow
    if (-not $NoGui -and -not $SelfTest) {
        # okno programu działa z ukrytą konsolą - komunikat pokazujemy w Notatniku
        $blockFile = Join-Path $env:TEMP 'SerwisDiag-blokada.txt'
        try {
            Set-Content -LiteralPath $blockFile -Value $blockText -Encoding UTF8 -ErrorAction Stop
            Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $blockFile + '"')
        } catch { }
    }
    if ($Pause) { [void](Read-Host 'Naciśnij Enter, aby zamknąć okno') }
    exit 5
}
$SdRoot = $PSScriptRoot
if (-not $SdRoot) { $SdRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$global:SdRoot = $SdRoot
$compareOnly = [bool]($CompareBefore -or $CompareAfter)
$useGui = -not $NoGui -and -not $compareOnly -and -not $Backup -and -not $UndoRepair -and -not $Monitor -and -not $EnableMonitor -and -not $DisableMonitor -and -not $Update
$undoLatest = (@('ostatni', 'latest') -contains $UndoRepair.ToLower())

# Ścieżki względne liczymy od bieżącego katalogu PowerShell - po ponownym uruchomieniu przez UAC katalog bieżący
# to System32, więc dalej przekazujemy już ścieżki pełne.
foreach ($pn in 'OutDir', 'CompareWith', 'CompareBefore', 'CompareAfter', 'ScreenshotPath', 'Backup', 'UndoRepair') {
    $pv = [string](Get-Variable -Name $pn -ValueOnly)
    if ($pn -eq 'UndoRepair' -and $undoLatest) { continue }
    if ($pv) {
        $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($pv)
        Set-Variable -Name $pn -Value $full
        if ($PSBoundParameters.ContainsKey($pn)) { $PSBoundParameters[$pn] = $full }
    }
}

function Wait-SdPause {
    if ($Pause) { Write-Host ''; [void](Read-Host 'Naciśnij Enter, aby zamknąć okno') }
}

. (Join-Path $SdRoot 'lib\Integrity.ps1')
. (Join-Path $SdRoot 'lib\Core.ps1')

# --- uprawnienia administratora: ponowne uruchomienie przez UAC z tymi samymi parametrami
if ($Elevate -and -not (Test-SdAdmin)) {
    $fwd = @()
    foreach ($k in $PSBoundParameters.Keys) {
        if ($k -eq 'Elevate') { continue }
        $v = $PSBoundParameters[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $fwd += ('-' + $k) } }
        else { $fwd += ('-' + $k); $fwd += (Format-SdCmdArg ([string]$v)) }
    }
    $hide = ($useGui -and -not $Pause)
    $argLine = '-NoProfile -ExecutionPolicy Bypass' + $(if ($useGui) { ' -STA' } else { '' }) + $(if ($hide) { ' -WindowStyle Hidden' } else { '' }) + ' -File ' + (Format-SdCmdArg $PSCommandPath)
    if ($fwd.Count -gt 0) { $argLine += ' ' + ($fwd -join ' ') }
    try {
        $sp = @{ FilePath = (Get-Process -Id $PID).Path; ArgumentList = $argLine; Verb = 'RunAs'; ErrorAction = 'Stop' }
        if ($hide) { $sp['WindowStyle'] = 'Hidden' }
        Start-Process @sp
        exit 0
    } catch {
        Write-Host 'Nie uzyskano uprawnień administratora (anulowano UAC) - program działa bez nich, część testów zostanie pominięta.' -ForegroundColor Yellow
    }
}

# Okno WPF (i ikona monitora) wymaga wątku STA (domyślnego w powershell.exe 3.0+). Przy uruchomieniu w MTA przeładowujemy skrypt w STA.
if (($useGui -or $Monitor) -and [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    $relaunch = @()
    foreach ($k in $PSBoundParameters.Keys) {
        if ($k -eq 'Elevate') { continue }
        $v = $PSBoundParameters[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $relaunch += "-$k" } }
        else { $relaunch += "-$k"; $relaunch += [string]$v }
    }
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -STA -File $PSCommandPath @relaunch
    exit $LASTEXITCODE
}

# --- integralność plików programu (przed wczytaniem testów - zmieniony plik nie zostanie wykonany bez zgody)
$global:SdIntegrity = Test-SdIntegrity -Root $SdRoot
if ($global:SdIntegrity.Status -eq 'changed' -and -not $SkipIntegrity -and -not $SelfTest) {
    $msg = "Pliki programu nie zgadzają się z manifestem (manifest.sha256):`n" + $global:SdIntegrity.Summary +
        "`n`nPrzyczyną może być uszkodzony nośnik albo modyfikacja plików (np. przez złośliwe oprogramowanie na komputerze, do którego był podłączony pendrive). " +
        'Jeśli pliki zmieniono świadomie, zaktualizuj manifest: tools\check.ps1.'
    if ($useGui) {
        Add-Type -AssemblyName PresentationFramework
        $ans = [System.Windows.MessageBox]::Show($msg + "`n`nCzy mimo to uruchomić program?", 'SerwisDiag - kontrola plików programu', 'YesNo', 'Warning', 'No')
        if ([string]$ans -ne 'Yes') { exit 4 }
    } else {
        Write-Host $msg -ForegroundColor Red
        Write-Host 'Przerwano. Aby mimo to uruchomić program, dodaj parametr -SkipIntegrity.' -ForegroundColor Yellow
        Wait-SdPause
        exit 4
    }
}

. (Join-Path $SdRoot 'lib\Load.ps1')

$settings = Get-SdSettings $SdRoot
if ($Technician) { $settings.Technician = $Technician }
$testList = @($TestIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Write-SdComparisonPaths {
    param($Paths)
    Write-Host ('Porównanie (technik): ' + $Paths['Technical'])
    Write-Host ('Porównanie (klient) : ' + $Paths['Customer'])
}

# ------------------------------------------------------------------ porównanie dwóch zapisanych raportów (bez diagnostyki)
if ($compareOnly) {
    $global:SD = New-SdContext -Root $SdRoot
    if (-not $CompareBefore -or -not $CompareAfter) {
        Write-Host 'Porównanie wymaga obu parametrów: -CompareBefore <raport.json> i -CompareAfter <raport.json>.' -ForegroundColor Red
        Wait-SdPause; exit 3
    }
    try {
        $cmp = New-SdComparison -Before (Import-SdReportJson $CompareBefore) -After (Import-SdReportJson $CompareAfter) -WorkDone $WorkDone
        $dir = if ($OutDir) { $OutDir } else { Split-Path -Parent $CompareAfter }
        $cp = Save-SdComparisonReports -Comparison $cmp -Settings $settings -OutDir $dir
    } catch {
        Write-Host ('Nie udało się porównać raportów: ' + $_.Exception.Message) -ForegroundColor Red
        Wait-SdPause; exit 3
    }
    Write-Host ('Porównanie: ' + (Get-SdComparisonSummaryText $cmp.Counts))
    foreach ($n in $cmp.Notes) { Write-Host ('Uwaga: ' + $n) -ForegroundColor Yellow }
    Write-SdComparisonPaths $cp
    if ($Open) { Start-Process $cp['Technical'] }
    Wait-SdPause
    exit 0
}

# ------------------------------------------------------------------ cofnięcie napraw z dziennika (bez diagnostyki)
if ($UndoRepair) {
    $global:SD = New-SdContext -Root $SdRoot
    $path = $UndoRepair
    if ($undoLatest) {
        $dirU = if ($OutDir) { $OutDir } else { Resolve-SdReportDir -Root $SdRoot -Settings $settings }
        $path = [string](@(Find-SdRepairJson -Dir $dirU) | Select-Object -First 1)
        if (-not $path) { Write-Host ('Nie znaleziono dziennika napraw tego komputera w: ' + $dirU) -ForegroundColor Red; Wait-SdPause; exit 3 }
    }
    try { $rlog = Read-SdRepairJson $path } catch { Write-Host ('Nie wczytano dziennika napraw: ' + $_.Exception.Message) -ForegroundColor Red; Wait-SdPause; exit 3 }
    if ([string]$rlog.computer -ne $env:COMPUTERNAME) { Write-Host ('Dziennik pochodzi z innego komputera (' + $rlog.computer + ') - przerwano.') -ForegroundColor Red; Wait-SdPause; exit 3 }
    if (-not $global:SD.IsAdmin) { Write-Host 'Cofanie zmian wymaga uprawnień administratora (dodaj -Elevate).' -ForegroundColor Red; Wait-SdPause; exit 3 }
    $items = @(Get-SdUndoItems $rlog)
    Write-Host ('Dziennik napraw: ' + $path)
    if ($items.Count -eq 0) { Write-Host 'Brak zmian ustawień do cofnięcia.' -ForegroundColor Green; Wait-SdPause; exit 0 }
    $undo = @(Invoke-SdUndo $items)
    $colorsU = @{ ok = 'Green'; skip = 'DarkGray'; error = 'Red' }
    foreach ($u in $undo) { Write-Host ('  [{0}] {1}{2}' -f $u.Result.ToUpper(), $u.Text, $(if ($u.Message) { ' - ' + $u.Message } else { '' })) -ForegroundColor $colorsU[[string]$u.Result] }
    foreach ($t in @(Get-SdNotUndoable $rlog)) { Write-Host ('  bez cofania (punkt przywracania): ' + $t) -ForegroundColor DarkGray }
    Write-Host ('Dziennik cofnięcia: ' + (Save-SdUndoLog -Results $undo -RepairJsonPath $path))
    Wait-SdPause
    if (@($undo | Where-Object { $_.Result -eq 'error' }).Count -gt 0) { exit 1 } else { exit 0 }
}

# ------------------------------------------------------------------ monitorowanie w tle i aktualizacje (bez diagnostyki)
if ($Monitor) {
    if (-not (Test-SdInstalledCopy $SdRoot) -and -not $env:SERWISDIAG_MONITOR_TEST) { Write-Host 'Monitorowanie w tle działa w wersji zainstalowanej (instalator SerwisDiag-<wersja>-setup.exe).' -ForegroundColor Yellow; exit 3 }
    try { Start-SdMonitor -Root $SdRoot -Settings $settings }
    catch { Write-SdMonitorLog ('Monitor zakończony błędem: ' + $_.Exception.Message + "`r`n" + $_.ScriptStackTrace); exit 1 }
    exit 0
}
if ($EnableMonitor -or $DisableMonitor) {
    $global:SD = New-SdContext -Root $SdRoot
    if ($DisableMonitor) {
        $was = Stop-SdMonitorProcess -Wait
        $removed = @(Unregister-SdMonitorAutostart)
        Write-Host ('Monitorowanie wyłączone' + $(if ($removed.Count) { ' (usunięto: ' + ($removed -join ', ') + ')' } else { '' }) + $(if ($was) { '; działający monitor zakończy pracę' } else { '' }) + '.')
        Wait-SdPause; exit 0
    }
    if (-not (Test-SdInstalledCopy $SdRoot)) { Write-Host 'Monitorowanie w tle działa w wersji zainstalowanej (instalator SerwisDiag-<wersja>-setup.exe).' -ForegroundColor Yellow; Wait-SdPause; exit 3 }
    try { $how = Register-SdMonitorAutostart -Root $SdRoot }
    catch { Write-Host ('Nie włączono monitorowania: ' + $_.Exception.Message) -ForegroundColor Red; Wait-SdPause; exit 1 }
    # poprzedni monitor (np. sprzed aktualizacji) kończy pracę, zanim wystartuje nowy
    [void](Stop-SdMonitorProcess -Wait)
    if (-not $NoStart) { Start-SdMonitorProcess -Root $SdRoot }
    Write-Host ('Monitorowanie włączone: ' + $(if ($how -eq 'task') { 'zadanie Harmonogramu dla wszystkich użytkowników' } else { 'autostart bieżącego użytkownika' }) + '.')
    Wait-SdPause; exit 0
}
if ($Update) {
    $global:SD = New-SdContext -Root $SdRoot
    try { $u = Invoke-SdUpdate -Root $SdRoot }
    catch { Write-Host $_.Exception.Message -ForegroundColor Red; Wait-SdPause; exit 1 }
    Write-Host $u.Message -ForegroundColor $(if ($u.Started) { 'Green' } else { 'Cyan' })
    Wait-SdPause
    if (-not $u.Release.Ok) { exit 1 } else { exit 0 }
}

# ------------------------------------------------------------------ kopia przed reinstalacją Windows (bez diagnostyki)
if ($Backup) {
    $global:SD = New-SdContext -Root $SdRoot
    $inc = @(Get-SdBackupIncludeList $BackupInclude)
    Write-Host ('Kopia przed reinstalacją Windows: ' + ($inc -join ', ')) -ForegroundColor Cyan
    if (-not $global:SD.IsAdmin) { Write-Host 'Uwaga: bez uprawnień administratora sterowniki, profile Wi-Fi i klucze BitLocker zostaną pominięte (dodaj -Elevate).' -ForegroundColor Yellow }
    try { $bk = Invoke-SdBackup -Dest $Backup -Include $inc -OnStep { param($t) if ($t) { Write-Host $t -ForegroundColor DarkGray } } }
    catch { Write-Host ('Nie udało się utworzyć kopii: ' + $_.Exception.Message) -ForegroundColor Red; Wait-SdPause; exit 3 }
    $colorsB = @{ ok = 'Green'; warn = 'Yellow'; skip = 'DarkGray'; error = 'Red' }
    foreach ($p in $bk.Parts) { Write-Host ('  [{0}] {1}: {2}' -f $p.Result.ToUpper(), $p.Label, $p.Message) -ForegroundColor $colorsB[[string]$p.Result] }
    foreach ($wn in $bk.Warnings) { Write-Host ('Uwaga: ' + $wn) -ForegroundColor Yellow }
    Write-Host ('Folder kopii: ' + $bk.Dir)
    Wait-SdPause
    if (@($bk.Parts | Where-Object { $_.Result -eq 'error' }).Count -gt 0) { exit 1 } else { exit 0 }
}

# ------------------------------------------------------------------ okno programu
if ($useGui) {
    try {
        . (Join-Path $SdRoot 'lib\Gui.ps1')
        Start-SdGui -Root $SdRoot -Settings $settings -SelfTest:$SelfTest -ScreenshotPath $ScreenshotPath -Ticket $Ticket -Customer $Customer -Note $Note -Offline:$Offline
    } catch {
        # Program działa z ukrytą konsolą - błąd startu musi być widoczny dla użytkownika.
        $detail = ($_ | Out-String)
        $logDir = Join-Path $SdRoot 'logs'
        $logFile = ''
        try {
            if (-not (Test-Path -LiteralPath $logDir)) { [void](New-Item -ItemType Directory -Path $logDir -Force) }
            $logFile = Join-Path $logDir ('blad-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
            [System.IO.File]::WriteAllText($logFile, $detail, (New-Object System.Text.UTF8Encoding($true)))
        } catch { $logFile = '' }
        try {
            Add-Type -AssemblyName PresentationFramework
            $text = "Program napotkał błąd i musi zostać zamknięty.`n`n" + $_.Exception.Message
            if ($logFile) { $text += "`n`nSzczegóły zapisano w:`n" + $logFile }
            [void][System.Windows.MessageBox]::Show($text, 'SerwisDiag', 'OK', 'Error')
        } catch { Write-Host $detail -ForegroundColor Red }
        Wait-SdPause
        exit 1
    }
    Wait-SdPause
    exit 0
}

# ------------------------------------------------------------------ tryb konsolowy
$global:SD = New-SdContext -Root $SdRoot -Level $Level -Tests $testList -Offline:$Offline
Set-SdMeta 'Ticket' $Ticket
Set-SdMeta 'Customer' $Customer
Set-SdMeta 'Technician' $settings.Technician
Set-SdMeta 'Notes' $Note
Set-SdMeta 'Integrity' $global:SdIntegrity.Summary
$global:SD['OnProgress'] = {
    param($i, $n, $c)
    Write-Host ('[{0,2}/{1}] {2}' -f $i, $n, $c.Title) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host ('SerwisDiag {0} - tryb {1}{2}{3}' -f $global:SdVersion, $(if ($Level -eq 'Full') { 'pełny' } else { 'szybki' }), $(if ($testList.Count) { ' + testy: ' + ($testList -join ', ') } else { '' }), $(if ($Offline) { ' (bez internetu)' } else { '' })) -ForegroundColor Cyan
if (-not $global:SD.IsAdmin) {
    Write-Host 'Uwaga: program działa bez uprawnień administratora - część testów (SMART, BitLocker, dzienniki) zostanie pominięta.' -ForegroundColor Yellow
}
$kb = Get-SdKnowledgeInfo
if ($kb.Stale) { Write-Host ('Uwaga: baza wiedzy programu (okresy wsparcia Windows i ESU): ' + $kb.Text + '.') -ForegroundColor Yellow }
$before = $null
if ($CompareWith) {
    try { $before = Import-SdReportJson $CompareWith }
    catch { Write-Host ('Nie wczytano raportu do porównania: ' + $_.Exception.Message) -ForegroundColor Yellow }
}
Invoke-SdScan

$result = Get-SdResult
$dir = if ($OutDir) { $OutDir } else { Resolve-SdReportDir -Root $SdRoot -Settings $settings }
$paths = Save-SdReports -Result $result -Settings $settings -OutDir $dir

$colors = @{ crit = 'Red'; warn = 'Yellow'; ok = 'Green'; info = 'Cyan'; skip = 'DarkGray'; error = 'Magenta' }
Write-Host ''
foreach ($f in $result.Findings) {
    if ($f.Status -in @('crit', 'warn', 'error')) {
        Write-Host ('[{0}] {1}: {2}' -f $global:SdStatusInfo[[string]$f.Status].Label, $f.Title, $f.Value) -ForegroundColor $colors[[string]$f.Status]
        if ($f.Advice) { Write-Host ('      zalecenie: ' + $f.Advice) -ForegroundColor DarkYellow }
    }
}
Write-Host ''
Write-Host ('WYNIK: {0} (krytyczne: {1}, ostrzeżenia: {2}, informacje: {3}, OK: {4}, pominięte: {5})' -f $result.Verdict.Title, $result.Counts['crit'], $result.Counts['warn'], $result.Counts['info'], $result.Counts['ok'], $result.Counts['skip']) -ForegroundColor $(if ($result.Verdict.Level -eq 'crit') { 'Red' } elseif ($result.Verdict.Level -eq 'warn') { 'Yellow' } else { 'Green' })
Write-Host ('Raport techniczny : ' + $paths['Technical'])
Write-Host ('Raport dla klienta: ' + $paths['Customer'])
Write-Host ('Dane JSON         : ' + $paths['Json'])
if ($Pdf -or $settings.AutoPdf) {
    $pdfRes = ConvertTo-SdPdf -HtmlPath $paths['Customer']
    if ($pdfRes.Ok) { Write-Host ('PDF dla klienta   : ' + $pdfRes.Path) } else { Write-Host ('PDF dla klienta   : nie zapisano - ' + $pdfRes.Error) -ForegroundColor Yellow }
}
if ($Anonymous) {
    try { $anonPaths = Save-SdAnonymousReports -Result $result -OutDir $dir; Write-Host ('Raport anonimowy  : ' + $anonPaths['Html'] + ' (przejrzyj przed publikacją)') }
    catch { Write-Host ('Raport anonimowy  : nie zapisano - ' + $_.Exception.Message) -ForegroundColor Yellow }
}
if ($before) {
    try {
        $cmp = New-SdComparison -Before $before -After $result -WorkDone $WorkDone
        $cp = Save-SdComparisonReports -Comparison $cmp -Settings $settings -OutDir $dir
        Write-Host ('Porównanie z raportem sprzed naprawy: ' + (Get-SdComparisonSummaryText $cmp.Counts)) -ForegroundColor Cyan
        foreach ($n in $cmp.Notes) { Write-Host ('Uwaga: ' + $n) -ForegroundColor Yellow }
        Write-SdComparisonPaths $cp
    } catch { Write-Host ('Nie udało się utworzyć porównania: ' + $_.Exception.Message) -ForegroundColor Yellow }
}
# --- naprawy po diagnostyce (-RepairList: tylko lista; -Repair: zalecane; -RepairIds: wskazane)
if ($Repair -or $RepairIds -or $RepairList) {
    Write-Host ''
    $cands = @(Get-SdFixCandidates -Context @{ Result = $result; IsAdmin = $global:SD.IsAdmin; Offline = [bool]$Offline })
    $ids = @($RepairIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    Write-Host ('Program może naprawić: {0}' -f (Format-Count $cands.Count 'problem' 'problemy' 'problemów')) -ForegroundColor Cyan
    foreach ($c in $cands) {
        $mark = $(if ($c.Blocked) { '-' } elseif ($c.Default) { 'x' } else { ' ' })
        Write-Host ('  [{0}] {1,-14} {2}{3}' -f $mark, $c.FixId, $c.Title, $(if ($c.Blocked) { '  (niedostępne: ' + $c.Blocked + ')' } else { '' }))
        if ($c.Problem) { Write-Host ('                       ' + $c.Problem) -ForegroundColor DarkGray }
    }
    Write-Host '  [x] = zalecane (-Repair); pozostałe wskaż przez -RepairIds' -ForegroundColor DarkGray
    $sel = $(if ($ids.Count -gt 0) { @($cands | Where-Object { $ids -contains $_.FixId }) } elseif ($Repair) { @($cands | Where-Object { $_.Default }) } else { @() })
    if (-not $RepairList -and $sel.Count -eq 0) { Write-Host 'Brak napraw do wykonania.' -ForegroundColor Green }
    elseif (-not $RepairList) {
        Write-Host 'Naprawy zmieniają ustawienia systemu. Program jest udostępniany bez gwarancji - wykonujesz je na własną odpowiedzialność.' -ForegroundColor Yellow
        $runnable = @($sel | Where-Object { -not $_.Blocked })
        $pre = @()
        if ($runnable.Count -gt 0) {
            # najpierw włączenie ochrony systemu (jeśli wybrane) - bez niej punkt przywracania nie powstanie
            $rpFix = @($runnable | Where-Object { $_.FixId -eq 'fx.restoreon' })
            if ($rpFix.Count -gt 0) { $pre = @(Invoke-SdFixes -Candidates $rpFix) }
            try {
                New-SdRepairRestorePoint
                Write-Host 'Punkt przywracania: utworzony (albo istnieje punkt z ostatnich 24 godzin).'
            } catch { Write-Host ('Nie utworzono punktu przywracania: ' + $_.Exception.Message) -ForegroundColor Yellow }
        }
        $fixRes = @($pre) + @(Invoke-SdFixes -Candidates @($sel | Where-Object { $_.FixId -ne 'fx.restoreon' -or $_.Blocked }) -OnItem { param($i, $n, $c) Write-Host ('[{0}/{1}] {2}...' -f $i, $n, $c.Title) -ForegroundColor DarkGray })
        $colorsR = @{ ok = 'Green'; warn = 'Yellow'; error = 'Red'; skip = 'DarkGray' }
        foreach ($r in $fixRes) { Write-Host ('  {0}: {1}{2}' -f $r.Title, $r.Result.ToUpper(), $(if ($r.Message) { ' - ' + $r.Message } else { '' })) -ForegroundColor $colorsR[[string]$r.Result] }
        $logPath = Save-SdRepairLog -Results $fixRes -Meta $result.Meta -OutDir $dir
        Write-Host ('Dziennik napraw: ' + $logPath)
        if (@($fixRes | Where-Object { $_.Reboot -and $_.Result -ne 'error' }).Count -gt 0) { Write-Host 'Część napraw zadziała po ponownym uruchomieniu komputera.' -ForegroundColor Yellow }
    }
}

# --- instalacja zalecanych sterowników z Windows Update (na wyraźne żądanie: -InstallDrivers)
if ($InstallDrivers) {
    Write-Host ''
    if ($Offline) { Write-Host 'Instalację sterowników pominięto - tryb bez internetu.' -ForegroundColor Yellow }
    elseif (-not $global:SD.IsAdmin) { Write-Host 'Instalacja sterowników wymaga uprawnień administratora (dodaj -Elevate).' -ForegroundColor Yellow }
    else {
        Write-Host 'Wyszukiwanie sterowników w Windows Update...' -ForegroundColor Cyan
        $found = & $global:SdWuDriverSearch -KeepResult
        $sel = @(Select-SdDriversToInstall $found.Items)
        if ($found.Error) { Write-Host ('Nie udało się wyszukać sterowników: ' + $found.Error) -ForegroundColor Red }
        elseif ($sel.Count -eq 0) { Write-Host 'Brak zalecanych sterowników do zainstalowania.' -ForegroundColor Green }
        else {
            foreach ($s in $sel) { Write-Host (' - ' + $s.Title) }
            try {
                Checkpoint-Computer -Description 'SerwisDiag - przed instalacją sterowników' -RestorePointType DEVICE_DRIVER_INSTALL -ErrorAction Stop
                Write-Host 'Punkt przywracania: utworzony (albo istnieje punkt z ostatnich 24 godzin).'
            } catch { Write-Host ('Nie utworzono punktu przywracania: ' + $_.Exception.Message) -ForegroundColor Yellow }
            $st = @{ Text = '' }
            $ins = & $global:SdWuDriverInstall -UpdateIds @($sel | ForEach-Object { $_.UpdateId }) -Status $st
            if ($ins.Error) { Write-Host ('Instalacja nie powiodła się: ' + $ins.Error) -ForegroundColor Red }
            foreach ($x in $ins.Results) { Write-Host ('{0}: {1}' -f $x.Title, (Get-SdWuResultText $x.ResultCode)) -ForegroundColor $(if ($x.ResultCode -eq 2) { 'Green' } else { 'Yellow' }) }
            if ($ins.RebootRequired) { Write-Host 'Wymagane ponowne uruchomienie komputera.' -ForegroundColor Yellow }
        }
    }
}
if ($Open) { Start-Process $paths['Technical'] }
Wait-SdPause
if ($result.Counts['crit'] -gt 0) { exit 2 } elseif ($result.Counts['warn'] -gt 0) { exit 1 } else { exit 0 }
