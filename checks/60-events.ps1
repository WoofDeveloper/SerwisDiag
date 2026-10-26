# Testy kategorii: Awarie i zdarzenia
# Zdarzenia czytamy po identyfikatorach i nazwach pól XML (EventData), a nie po treści komunikatów - dzięki temu
# działa to tak samo w każdej wersji językowej Windows.

function Get-SdEventHint {
    param([string]$Provider, [int]$Id)
    $h = Get-SdData 'event-hints'
    if (-not $h -or -not $h.Hints) { return $null }
    $k = "$Provider|$Id"
    if ($h.Hints.ContainsKey($k)) { return $h.Hints[$k] }
    $k2 = "*|$Id"
    if ($h.Hints.ContainsKey($k2)) { return $h.Hints[$k2] }
    return $null
}

function Get-SdFirstLine {
    param($Text, [int]$Max = 160)
    if ($null -eq $Text) { return '' }
    foreach ($l in ([string]$Text -split "`r?`n")) { $t = $l.Trim(); if ($t) { return (Limit-Text $t $Max) } }
    return ''
}

function Get-SdWerEventTime {
    # Czas awarii z raportu WER: EventTime (FILETIME) z Report.wer, a gdy plik jest niedostępny (brak uprawnień) - data utworzenia folderu.
    param([System.IO.DirectoryInfo]$Dir)
    try {
        $f = Join-Path $Dir.FullName 'Report.wer'
        if (Test-Path -LiteralPath $f -ErrorAction SilentlyContinue) {
            $txt = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::Unicode)
            if ($txt -match 'EventTime=(\d{15,19})') { return [DateTime]::FromFileTimeUtc([int64]$Matches[1]).ToLocalTime() }
        }
    } catch { }
    return $Dir.CreationTime
}

# ---------------------------------------------------------------- przypisywanie zdarzeń dyskowych do konkretnych nośników

$global:SdExternalBusTypes = @(7, 12, 13)   # STORAGE_BUS_TYPE: USB, SD, MMC

function Get-SdVolumeMaps {
    # \Device\HarddiskVolumeN -> numer dysku i litera (także woluminy bez litery: EFI, odzyskiwanie)
    Get-SdCached 'VolumeMaps' {
        $devToDisk = @{}; $devToLetter = @{}; $letterToDisk = @{}
        $native = Initialize-SdNative
        if (Get-Command Get-Partition -ErrorAction SilentlyContinue) {
            $parts = @()
            try { $parts = @(Get-Partition -ErrorAction Stop) } catch { Write-SdLog ('Get-Partition: ' + $_.Exception.Message) 'INFO' }
            foreach ($p in $parts) {
                $letter = ''
                if ([string]$p.DriveLetter -match '^[A-Za-z]$') { $letter = ([string]$p.DriveLetter).ToUpper() + ':' }
                if ($letter) { $letterToDisk[$letter] = [int]$p.DiskNumber }
                foreach ($ap in @($p.AccessPaths)) {
                    if ($native -and [string]$ap -match '^\\\\\?\\(Volume\{[0-9a-fA-F-]+\})\\$') {
                        $dev = [SdNative]::DosDevice($Matches[1])
                        if ($dev) { $devToDisk[$dev] = [int]$p.DiskNumber; if ($letter) { $devToLetter[$dev] = $letter } }
                    }
                }
            }
        }
        if ($native) {
            foreach ($ld in (Get-Cim Win32_LogicalDisk)) {
                $l = ([string]$ld.DeviceID).ToUpper()
                if (-not $l) { continue }
                $dev = [SdNative]::DosDevice($l)
                if ($dev -and -not $devToLetter.ContainsKey($dev)) { $devToLetter[$dev] = $l }
            }
        }
        [pscustomobject]@{ DevToDisk = $devToDisk; DevToLetter = $devToLetter; LetterToDisk = $letterToDisk }
    }
}

function Get-SdDiskEventRef {
    # Czego dotyczy zdarzenie: numer dysku (\Device\HarddiskN\DRx), wolumin, litera, typ magistrali i model z danych NTFS.
    param([object[]]$Props, [hashtable]$Data, [string]$Message)
    $r = [pscustomobject]@{ DiskIndex = $null; Volume = ''; Letter = ''; BusType = $null; Device = ''; Port = '' }
    $first = ''
    if ($Props -and $Props.Count -gt 0) { $first = [string]$Props[0] }
    $text = $first + ' ' + $Message
    if ($text -match '\\Device\\Harddisk(\d+)\\DR\d+') { $r.DiskIndex = [int]$Matches[1] }
    if ($Data) {
        if ([string]$Data['VolumeId'] -match '^[A-Za-z]:$') { $r.Letter = ([string]$Data['VolumeId']).ToUpper() }
        if ($Data['DeviceName']) { $r.Volume = [string]$Data['DeviceName'] }
        if ([string]$Data['BusType'] -match '^\d+$') { $r.BusType = [int]$Data['BusType'] }
        $r.Device = Join-NonEmpty @($Data['VendorId'], $Data['ProductId']) ' '
    }
    if (-not $r.Volume -and $text -match '(\\Device\\HarddiskVolume\d+)') { $r.Volume = $Matches[1] }
    if ($text -match '\\Device\\(RaidPort\d+|ScsiPort\d+|Ide\\[^\s,.]+)') { $r.Port = $Matches[1] }
    return $r
}

function Resolve-SdDiskEventTarget {
    # Kind: internal (dysk komputera) | external (dysk USB/karta podłączony teraz) | absent (nośnik niepodłączony) | controller | unknown
    param($Ref, $Disks, $Maps)
    $letter = [string]$Ref.Letter
    if (-not $letter -and $Ref.Volume -and $Maps.DevToLetter.ContainsKey($Ref.Volume)) { $letter = $Maps.DevToLetter[$Ref.Volume] }
    $idx = $Ref.DiskIndex
    if ($null -eq $idx -and $Ref.Volume -and $Maps.DevToDisk.ContainsKey($Ref.Volume)) { $idx = $Maps.DevToDisk[$Ref.Volume] }
    if ($null -eq $idx -and $letter -and $Maps.LetterToDisk.ContainsKey($letter)) { $idx = $Maps.LetterToDisk[$letter] }
    $extBus = ($null -ne $Ref.BusType -and $global:SdExternalBusTypes -contains [int]$Ref.BusType)
    $extra = @()
    if ($Ref.Device) { $extra += ([string]$Ref.Device).Trim() }
    if ($extBus) { $extra += @{ 7 = 'USB'; 12 = 'karta SD'; 13 = 'karta MMC' }[[int]$Ref.BusType] }
    $extraTxt = ''
    if ($extra.Count -gt 0) { $extraTxt = ' (' + ($extra -join ', ') + ')' }
    $letterTxt = ''
    if ($letter) { $letterTxt = ' ' + $letter }

    if ($null -ne $idx) {
        $d = @($Disks | Where-Object { $_.Index -eq $idx }) | Select-Object -First 1
        if ($d) {
            $isExt = ($extBus -or $d.Bus -eq 'USB' -or $d.Iface -eq 'USB' -or (Get-SdDiskTypeName $d) -match '^USB')
            $label = 'Dysk {0}: {1}{2}' -f $idx, $d.Model, $(if ($letter) { " ($letter)" } else { '' })
            if ($isExt) { return [pscustomobject]@{ Kind = 'external'; Key = "disk$idx"; Label = $label + ' - dysk zewnętrzny' } }
            return [pscustomobject]@{ Kind = 'internal'; Key = "disk$idx"; Label = $label }
        }
        return [pscustomobject]@{ Kind = 'absent'; Key = "disk$idx"; Label = ('Harddisk{0}{1}{2} - nośnik obecnie niepodłączony' -f $idx, $letterTxt, $extraTxt) }
    }
    if ($letter -or $Ref.Volume) {
        $name = $(if ($letter) { $letter } else { [string]$Ref.Volume })
        return [pscustomobject]@{ Kind = 'absent'; Key = "vol$name"; Label = ('Wolumin {0}{1} - nośnik obecnie niepodłączony' -f $name, $extraTxt) }
    }
    if ($Ref.Port) { return [pscustomobject]@{ Kind = 'controller'; Key = 'port' + $Ref.Port; Label = ('Kontroler pamięci masowej ({0})' -f $Ref.Port) } }
    return [pscustomobject]@{ Kind = 'unknown'; Key = 'unknown'; Label = 'Nie udało się ustalić nośnika' }
}

function Get-SdDiskEventStatus {
    # Ocena grupy zdarzeń: tylko dyski komputera mogą dać "krytyczne"; nośniki zewnętrzne i niepodłączone nie obciążają werdyktu.
    param([string]$Kind, [string]$HintSeverity)
    switch ($Kind) {
        'internal'   { return $HintSeverity }
        'controller' { return $HintSeverity }
        'unknown'    { return 'warn' }
        'external'   { return 'warn' }
        default      { return 'info' }
    }
}

Register-Check -Id 'ev.crash' -Category 'events' -Title 'Awarie systemu: BSOD i nieoczekiwane restarty' -Script {
    $days = 90
    $since = (Get-Date).AddDays(-$days)
    $since30 = (Get-Date).AddDays(-30)

    # --- niebieskie ekrany (BugCheck 1001)
    $bug = @(Get-SdEvents -Filter @{ LogName = 'System'; Id = 1001; ProviderName = @('Microsoft-Windows-WER-SystemErrorReporting', 'BugCheck'); StartTime = $since } -Max 300)
    $crashes = New-Object System.Collections.ArrayList
    foreach ($e in $bug) {
        $d = Get-SdEventData $e
        $s = $d['param1']
        if (-not $s -and $e.Properties.Count -gt 0) { $s = [string]$e.Properties[0].Value }
        if ($s -match '(0x[0-9a-fA-F]{1,8})') {
            $info = Get-SdBugcheckInfo $Matches[1]
            if ($info) { [void]$crashes.Add([pscustomobject]@{ Time = $e.TimeCreated; Info = $info; Raw = $s }) }
        }
    }
    # --- Kernel-Power 41 (nieoczekiwany restart)
    $kp = @(Get-SdEvents -Filter @{ LogName = 'System'; Id = 41; ProviderName = 'Microsoft-Windows-Kernel-Power'; StartTime = $since } -Max 300)
    $unexp = New-Object System.Collections.ArrayList
    foreach ($e in $kp) {
        $d = Get-SdEventData $e
        $code = 0L; [void][int64]::TryParse([string]$d['BugcheckCode'], [ref]$code)
        $ptsRaw = 0L; [void][int64]::TryParse([string]$d['PowerButtonTimestamp'], [ref]$ptsRaw)
        $sleep = 0; [void][int]::TryParse([string]$d['SleepInProgress'], [ref]$sleep)
        $kind = 'power'
        if ($code -ne 0) { $kind = 'bsod' }
        elseif ($ptsRaw -ne 0) { $kind = 'button' }
        elseif ($sleep -ne 0) { $kind = 'sleep' }
        [void]$unexp.Add([pscustomobject]@{ Time = $e.TimeCreated; Kind = $kind; Code = $code })
        # BSOD bez zdarzenia 1001 (np. nie powstał zrzut) - dolicz z Kernel-Power
        if ($kind -eq 'bsod') {
            $dup = $false
            foreach ($c in $crashes) { if ([math]::Abs(($c.Time - $e.TimeCreated).TotalMinutes) -le 5) { $dup = $true; break } }
            if (-not $dup) {
                $info = Get-SdBugcheckInfo $code
                if ($info) { [void]$crashes.Add([pscustomobject]@{ Time = $e.TimeCreated; Info = $info; Raw = 'Kernel-Power 41' }) }
            }
        }
    }

    # --- BSOD: podsumowanie
    $c30 = @($crashes | Where-Object { $_.Time -ge $since30 }).Count
    if ($crashes.Count -gt 0) {
        $byCode = $crashes | Group-Object { $_.Info.Code } | Sort-Object Count -Descending
        $rows = @($byCode | ForEach-Object {
                $i = $_.Group[0].Info
                $last = ($_.Group | Sort-Object Time -Descending | Select-Object -First 1).Time
                [pscustomobject]@{ 'Kod STOP' = $i.Code; Nazwa = $i.Name; Liczba = $_.Count; Ostatnio = (Format-Dt $last); Przyczyna = $i.Hint }
            })
        Add-Table 'Niebieskie ekrany (BSOD)' -Rows $rows
        $causeLabels = @{ driver = 'sterowniki'; memory = 'pamięć RAM'; disk = 'dysk / kontroler'; hardware = 'sprzęt (CPU/płyta/zasilanie)'; gpu = 'karta graficzna'; power = 'zasilanie'; system = 'pliki systemowe'; unknown = 'nieustalona' }
        $causes = $crashes | Group-Object { $_.Info.Cause } | Sort-Object Count -Descending
        $topCause = $causes | Select-Object -First 1
        $causeTxt = '{0} ({1} z {2})' -f $causeLabels[[string]$topCause.Name], $topCause.Count, $crashes.Count
        $top = @($byCode | Select-Object -First 3 | ForEach-Object { '{0} {1} ×{2}' -f $_.Group[0].Info.Code, $_.Group[0].Info.Name, $_.Count })
        $lastCrash = ($crashes | Sort-Object Time -Descending | Select-Object -First 1)
        $d = @("Awarie w ciągu $days dni: $($crashes.Count) (w ostatnich 30 dniach: $c30); ostatnia: $(Format-Dt $lastCrash.Time)")
        $d += 'Najczęstsze kody: ' + ($top -join '; ')
        $d += 'Najbardziej prawdopodobna grupa przyczyn: ' + $causeTxt
        $d += ''
        $d += 'Wskazówka dla najczęstszego kodu: ' + $byCode[0].Group[0].Info.Hint
        $st = if ($c30 -ge 3) { 'crit' } elseif ($c30 -ge 1) { 'warn' } else { 'info' }
        Add-Finding 'Niebieskie ekrany (BSOD)' -Status $st -Value ('{0} w ciągu {1} dni (ostatnie 30 dni: {2}); najczęściej: {3}' -f $crashes.Count, $days, $c30, $top[0]) -Details ($d -join "`n") -LastEvent $lastCrash.Time `
            -Advice ('Najpierw wyeliminuj grupę przyczyn: ' + $causeTxt + '. Przeanalizuj zrzuty (WinDbg !analyze -v / BlueScreenView), zaktualizuj sterowniki i BIOS, przetestuj RAM (MemTest86) i dysk (SMART), sprawdź temperatury.')
    } else {
        Add-Finding 'Niebieskie ekrany (BSOD)' -Status ok -Value "Brak w ciągu $days dni"
    }

    # --- nieoczekiwane restarty bez BSOD
    $nb = @($unexp | Where-Object { $_.Kind -ne 'bsod' })
    $kindLabel = @{ power = 'nagła utrata zasilania / reset / zabezpieczenie termiczne'; button = 'wymuszone wyłączenie przyciskiem zasilania (po zawieszeniu)'; sleep = 'awaria podczas przejścia w uśpienie lub wznawiania'; bsod = 'niebieski ekran' }
    if ($unexp.Count -gt 0) {
        Add-Table 'Nieoczekiwane restarty (Kernel-Power 41)' -Rows @($unexp | Sort-Object Time -Descending | Select-Object -First 15 | ForEach-Object {
                [pscustomobject]@{ Czas = (Format-Dt $_.Time); Rodzaj = $kindLabel[[string]$_.Kind]; 'Kod STOP' = $(if ($_.Code -ne 0) { '0x' + ([int64]$_.Code).ToString('X8') } else { '-' }) }
            })
    }
    if ($nb.Count -gt 0) {
        $n30 = @($nb | Where-Object { $_.Time -ge $since30 }).Count
        $kinds = $nb | Group-Object Kind | Sort-Object Count -Descending
        $lastNb = Get-SdLatestTime $nb 'Time'
        $d = @("Nieoczekiwane restarty bez niebieskiego ekranu: $($nb.Count) w ciągu $days dni (ostatnie 30 dni: $n30); ostatni: $(Format-Dt $lastNb)")
        foreach ($k in $kinds) { $d += ' - {0}: {1}' -f $kindLabel[[string]$k.Name], $k.Count }
        $adv = switch ([string]$kinds[0].Name) {
            'sleep'  { 'Awarie w trakcie uśpienia: zaktualizuj BIOS oraz sterowniki (chipset, grafika, Intel ME/AMD PSP), wyłącz szybkie uruchamianie i hibernację jako test, sprawdź baterię i zasilacz.' }
            'button' { 'System zawiesza się na tyle, że użytkownik wymusza wyłączenie. Szukaj przyczyny zawieszeń: sterowniki grafiki/dysku, błędy dysku, przegrzanie, uszkodzony RAM.' }
            default  { 'Nagłe wyłączenia: sprawdź zasilacz/ładowarkę, baterię, gniazdo i listwę, przegrzewanie (czyszczenie układu chłodzenia) oraz zasilacz PSU w komputerach stacjonarnych.' }
        }
        $st = if ($n30 -ge 6) { 'crit' } elseif ($n30 -ge 2) { 'warn' } else { 'info' }
        Add-Finding 'Nieoczekiwane restarty (bez BSOD)' -Status $st -Value ('{0} w ciągu {1} dni (ostatnie 30 dni: {2})' -f $nb.Count, $days, $n30) -Details ($d -join "`n") -Advice $adv -LastEvent $lastNb
    } else {
        Add-Finding 'Nieoczekiwane restarty (bez BSOD)' -Status ok -Value "Brak w ciągu $days dni"
    }

    # --- ostatnie restarty / wyłączenia zainicjowane przez system lub użytkownika (zdarzenie 1074)
    $sd = @(Get-SdEvents -Filter @{ LogName = 'System'; Id = 1074; ProviderName = 'User32'; StartTime = $since30 } -Max 40)
    if ($sd.Count -gt 0) {
        $rows = @($sd | Select-Object -First 15 | ForEach-Object {
                $p = $_.Properties
                [pscustomobject]@{
                    Czas = (Format-Dt $_.TimeCreated); Proces = (Split-Path ([string]$p[0].Value) -Leaf); Rodzaj = [string]$p[4].Value
                    Powód = (Limit-Text ([string]$p[2].Value) 80); Użytkownik = [string]$p[6].Value
                }
            })
        Add-Table 'Ostatnie restarty i wyłączenia (zainicjowane)' -Rows $rows -Private
    }

    # --- zrzuty pamięci
    $dumpRows = @()
    $mini = Join-Path $env:SystemRoot 'Minidump'
    foreach ($f in @(Get-ChildItem -LiteralPath $mini -Filter '*.dmp' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        $dumpRows += [pscustomobject]@{ Plik = $f.Name; Rodzaj = 'Minidump'; Rozmiar = (Format-Size $f.Length 1); Data = (Format-Dt $f.LastWriteTime) }
    }
    $full = Join-Path $env:SystemRoot 'MEMORY.DMP'
    if (Test-Path -LiteralPath $full) { $f = Get-Item -LiteralPath $full -Force; $dumpRows += [pscustomobject]@{ Plik = 'MEMORY.DMP'; Rodzaj = 'Zrzut jądra/pełny'; Rozmiar = (Format-Size $f.Length 1); Data = (Format-Dt $f.LastWriteTime) } }
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'LiveKernelReports') -Recurse -Filter '*.dmp' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 10)) {
        $dumpRows += [pscustomobject]@{ Plik = $f.Name; Rodzaj = 'LiveKernelReport (' + $f.Directory.Name + ')'; Rozmiar = (Format-Size $f.Length 1); Data = (Format-Dt $f.LastWriteTime) }
    }
    $cc = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue
    $dumpMode = if ($cc) { [int]$cc.CrashDumpEnabled } else { -1 }
    $modeTxt = switch ($dumpMode) { 0 { 'wyłączone' } 1 { 'pełny zrzut pamięci' } 2 { 'zrzut jądra' } 3 { 'mały zrzut (minidump)' } 7 { 'automatyczny zrzut' } default { 'nieznany' } }
    if ($dumpRows.Count -gt 0) {
        Add-Table 'Zrzuty pamięci (dumpy)' -Rows $dumpRows
        Add-Finding 'Zrzuty pamięci' -Status info -Value ('{0}; ostatni: {1}; tryb zapisu: {2}' -f (Format-Count $dumpRows.Count 'plik' 'pliki' 'plików'), $dumpRows[0].Data, $modeTxt) `
            -Advice 'Analiza zrzutu wskaże sterownik/moduł powodujący awarię: WinDbg (!analyze -v), BlueScreenView lub WhoCrashed.'
    } elseif ($crashes.Count -gt 0 -and $dumpMode -eq 0) {
        Add-Finding 'Zrzuty pamięci' -Status warn -Value 'Zapis zrzutów jest wyłączony, a system ulegał awariom' `
            -Advice 'Włącz zapis małych zrzutów pamięci (Zaawansowane ustawienia systemu > Uruchamianie i odzyskiwanie), aby kolejna awaria mogła zostać przeanalizowana.'
    }
    if ($crashes.Count -gt 0 -and $cc -and [int]$cc.AutoReboot -eq 1) {
        Add-Finding 'Automatyczny restart po awarii' -Status info -Value 'Włączony - niebieski ekran znika po chwili' `
            -Advice 'Na czas diagnozy wyłącz automatyczne ponowne uruchamianie, aby odczytać kod STOP z ekranu.'
    }

    # --- raporty WER typu Kernel_<kod>_...: kod w nazwie to kod STOP / LiveKernelEvent zapisany szesnastkowo.
    # Datą awarii jest EventTime z Report.wer (lub data utworzenia folderu) - data modyfikacji zmienia się przy każdej próbie wysłania raportu.
    $wer = Join-Path $env:ProgramData 'Microsoft\Windows\WER'
    $kr = @()
    foreach ($sub in 'ReportArchive', 'ReportQueue') {
        foreach ($dir in @(Get-ChildItem -LiteralPath (Join-Path $wer $sub) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Kernel_[0-9a-fA-F]+_' })) {
            $when = Get-SdWerEventTime $dir
            if ($when -ge $since) { $kr += [pscustomobject]@{ Name = $dir.Name; Time = $when } }
        }
    }
    if ($kr.Count -gt 0) {
        $grp = @($kr | Group-Object { ($_.Name -split '_')[1] } | Sort-Object Count -Descending)
        $lines = @(); $gpu = 0
        foreach ($g in $grp) {
            $info = Get-SdBugcheckInfo ('0x' + $g.Name)
            $known = ($info -and $info.Name -ne 'Nieznany kod')
            $nm = if ($known) { '{0} {1}' -f $info.Code, $info.Name } else { 'kod 0x' + $g.Name }
            if ($known -and $info.Cause -eq 'gpu') { $gpu += $g.Count }
            $lastTime = ($g.Group | Sort-Object Time -Descending | Select-Object -First 1).Time
            $lines += ('{0} ×{1}, ostatnio {2}' -f $nm, $g.Count, (Format-Dt $lastTime))
            if ($known) { $lines += '    ' + $info.Hint }
        }
        $st = if ($gpu -ge 2) { 'warn' } else { 'info' }
        $short = ($grp | Select-Object -First 3 | ForEach-Object { $i = Get-SdBugcheckInfo ('0x' + $_.Name); '{0} ×{1}' -f $(if ($i -and $i.Name -ne 'Nieznany kod') { $i.Name } else { 'kod 0x' + $_.Name }), $_.Count }) -join '; '
        Add-Finding 'Raporty awarii jądra (WER)' -Status $st -Value $short -LastEvent (Get-SdLatestTime $kr 'Time') `
            -Details (("Raporty Kernel_* w ProgramData\Microsoft\Windows\WER z ostatnich $days dni (także zawieszenia sterowników bez niebieskiego ekranu).`n") + ($lines -join "`n")) `
            -Advice 'Powtarzające się zawieszenia GPU (kody 0x141/0x117): zainstaluj czysto sterownik grafiki, sprawdź temperatury, zasilanie i stabilność podkręcenia/VRAM.'
    }
}

function Get-SdStabilitySummary {
    # Indeks stabilności Monitora niezawodności (1-10, wyliczany co godzinę): wartość bieżąca, minima z 7 i 30 dni,
    # wartość sprzed tygodnia, minima dzienne i ocena. Points: obiekty { Time; Index }. Funkcja czysta (testy jednostkowe).
    param([object[]]$Points, [datetime]$Now)
    $p = @($Points | Where-Object { $null -ne $_ } | Sort-Object Time)
    if ($p.Count -eq 0) { return $null }
    $cur = $p[$p.Count - 1]
    $d7 = $Now.AddDays(-7); $d30 = $Now.AddDays(-30)
    $last7 = @($p | Where-Object { $_.Time -ge $d7 })
    $last30 = @($p | Where-Object { $_.Time -ge $d30 })
    if ($last7.Count -eq 0) { $last7 = @($cur) }
    if ($last30.Count -eq 0) { $last30 = @($cur) }
    $min7 = [double]($last7 | Measure-Object Index -Minimum).Minimum
    $min30 = [double]($last30 | Measure-Object Index -Minimum).Minimum
    $weekAgo = $null
    $older = @($p | Where-Object { $_.Time -le $d7 })
    if ($older.Count -gt 0) { $weekAgo = [double]$older[$older.Count - 1].Index }
    $daily = @($last30 | Group-Object { ([datetime]$_.Time).ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{ Day = $_.Name; Min = [double]($_.Group | Measure-Object Index -Minimum).Minimum; Last = [double]($_.Group | Sort-Object Time | Select-Object -Last 1).Index }
        })
    $idx = [double]$cur.Index
    $status = 'ok'
    if ($idx -lt 5) { $status = 'warn' }
    elseif ($idx -lt 7 -or $min7 -lt 5) { $status = 'info' }
    $drop = ($null -ne $weekAgo -and ($weekAgo - $idx) -ge 2)
    if ($drop -and $status -eq 'ok') { $status = 'info' }
    $stale = (($Now - [datetime]$cur.Time).TotalDays -gt 3)
    return [pscustomobject]@{ Current = $idx; Time = [datetime]$cur.Time; Min7 = $min7; Min30 = $min30; WeekAgo = $weekAgo; Drop = $drop; Stale = $stale; Daily = $daily; Status = $status }
}

Register-Check -Id 'ev.stability' -Category 'events' -Title 'Indeks stabilności systemu (Monitor niezawodności)' -Script {
    $raw = @(Get-Cim Win32_ReliabilityStabilityMetrics -Timeout 60)
    $pts = @($raw | Where-Object { $null -ne $_.SystemStabilityIndex -and $_.TimeGenerated } | ForEach-Object { [pscustomobject]@{ Time = [datetime]$_.TimeGenerated; Index = [double]$_.SystemStabilityIndex } })
    $s = Get-SdStabilitySummary -Points $pts -Now (Get-Date)
    if (-not $s) {
        Add-Finding 'Indeks stabilności systemu' -Status info -Value 'Brak danych Monitora niezawodności' `
            -Details 'Windows nie zebrał danych o niezawodności (np. wyłączone zadanie harmonogramu \Microsoft\Windows\RAC\RacTask lub zasady firmowe).' `
            -Advice 'Jeśli Monitor niezawodności (perfmon /rel) jest pusty, włącz zadanie RacTask w Harmonogramie zadań - dane zbierają się co godzinę.'
        return
    }
    $val = '{0} / 10 (najniższy w 30 dniach: {1}' -f (Format-Num $s.Current 1), (Format-Num $s.Min30 1)
    if ($null -ne $s.WeekAgo) { $val += '; tydzień temu: ' + (Format-Num $s.WeekAgo 1) }
    $val += ')'
    $d = @(
        'Indeks 1-10 wylicza co godzinę Monitor niezawodności Windows na podstawie awarii aplikacji, systemu i sterowników oraz nieudanych instalacji. 10 = brak problemów; po awarii indeks spada i powoli wraca.'
        ('Ostatni pomiar: {0}; najniższa wartość w ostatnich 7 dniach: {1}' -f (Format-Dt $s.Time), (Format-Num $s.Min7 1))
    )
    if ($s.Drop) { $d += 'W ciągu tygodnia indeks spadł o co najmniej 2 punkty - pojawiły się nowe awarie.' }
    if ($s.Stale) { $d += 'Ostatni pomiar jest starszy niż 3 dni - Monitor niezawodności mógł przestać zbierać dane.' }
    Add-Table 'Indeks stabilności - minimum dzienne (30 dni)' -Rows @($s.Daily | Sort-Object Day -Descending | ForEach-Object { [pscustomobject]@{ Dzień = $_.Day; Minimum = (Format-Num $_.Min 2); 'Na koniec dnia' = (Format-Num $_.Last 2) } })
    $adv = ''
    if ($s.Status -ne 'ok') { $adv = 'Otwórz Monitor niezawodności (perfmon /rel lub Narzędzia serwisowe), aby zobaczyć, które awarie obniżyły indeks; porównaj z wynikami testów BSOD i awarii aplikacji.' }
    Set-SdMeta 'Stability' (Format-Num $s.Current 1)
    Add-Finding 'Indeks stabilności systemu' -Status $s.Status -Value $val -Details ($d -join "`n") -Advice $adv
}

Register-Check -Id 'ev.hardware' -Category 'events' -Title 'Błędy sprzętowe w dzienniku: dysk, WHEA, grafika, throttling' -Script {
    $days = 30
    $since = (Get-Date).AddDays(-$days)
    # --- dyski i system plików: każde zdarzenie przypisujemy do konkretnego nośnika. Błędy pendrive'a albo
    # odłączonego w trakcie zapisu dysku USB nie mogą dawać werdyktu "poważne problemy" dla dysków komputera.
    $diskEv = @(Get-SdEvents -Filter @{ LogName = 'System'; ProviderName = @('disk', 'Ntfs', 'Microsoft-Windows-Ntfs', 'storahci', 'stornvme', 'iaStorA', 'iaStorAC', 'iaStorAVC', 'nvstor', 'amdsata', 'volmgr', 'Microsoft-Windows-StorPort'); Id = @(7, 9, 11, 15, 51, 52, 55, 129, 137, 140, 153); StartTime = $since } -Max 500)
    if ($diskEv.Count -eq 0) {
        Add-Finding 'Błędy dysku i systemu plików' -Status ok -Value "Brak zdarzeń w ciągu $days dni"
    } else {
        $disks = @(Get-SdDiskInventory)
        $maps = Get-SdVolumeMaps
        $groups = @{}
        foreach ($e in $diskEv) {
            $props = @($e.Properties | ForEach-Object { $_.Value })
            $ref = Get-SdDiskEventRef -Props $props -Data (Get-SdEventData $e) -Message (Get-SdFirstLine $e.Message 300)
            $t = Resolve-SdDiskEventTarget -Ref $ref -Disks $disks -Maps $maps
            if (-not $groups.ContainsKey($t.Key)) { $groups[$t.Key] = [pscustomobject]@{ Target = $t; Events = New-Object System.Collections.ArrayList } }
            [void]$groups[$t.Key].Events.Add($e)
        }
        $order = @('internal', 'controller', 'unknown', 'external', 'absent')
        $lines = @(); $statuses = @(); $count = @{}
        foreach ($g in ($groups.Values | Sort-Object { $order.IndexOf($_.Target.Kind) })) {
            $k = $g.Target.Kind
            $count[$k] = [int]$count[$k] + $g.Events.Count
            $lines += ($g.Target.Label + ':')
            $hintSev = 'warn'
            foreach ($sub in ($g.Events | Group-Object { '{0}|{1}' -f $_.ProviderName, $_.Id } | Sort-Object Count -Descending)) {
                $p = $sub.Name -split '\|'
                $hint = Get-SdEventHint $p[0] ([int]$p[1])
                if ($hint -and $hint.Sev -eq 'crit') { $hintSev = 'crit' }
                $last = $sub.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
                $txt = if ($hint) { $hint.Text } else { Get-SdFirstLine $last.Message 140 }
                $lines += ('    {0}/{1} ×{2}, ostatnio {3} - {4}' -f $p[0], $p[1], $sub.Count, (Format-Dt $last.TimeCreated), $txt)
            }
            $statuses += (Get-SdDiskEventStatus -Kind $k -HintSeverity $hintSev)
        }
        $status = Get-SdWorstStatus $statuses
        $onComputer = [int]$count['internal'] + [int]$count['controller'] + [int]$count['unknown']
        $parts = @()
        if ($onComputer -gt 0) { $parts += ('{0} na dyskach komputera' -f (Format-Count $onComputer 'zdarzenie' 'zdarzenia' 'zdarzeń')) }
        if ($count['external']) { $parts += ('{0} na dysku zewnętrznym' -f (Format-Count $count['external'] 'zdarzenie' 'zdarzenia' 'zdarzeń')) }
        if ($count['absent']) { $parts += ('{0} na nośniku, który nie jest teraz podłączony' -f (Format-Count $count['absent'] 'zdarzenie' 'zdarzenia' 'zdarzeń')) }
        $value = ('W ciągu {0} dni: ' -f $days) + ($parts -join '; ')
        if ($onComputer -gt 0) {
            $advice = 'Zdarzenia na dyskach komputera wskazują na problem z dyskiem, kablem SATA, kontrolerem lub zasilaniem. Sprawdź SMART, wykonaj kopię danych, wymień kabel; sam chkdsk /r na niesprawnym dysku może pogorszyć sytuację.'
        } elseif ($count['external']) {
            $advice = 'Błędy dotyczą dysku zewnętrznego (USB / karta pamięci). Sprawdź ten nośnik osobno, wymień kabel lub port i nie odłączaj go w trakcie zapisu.'
        } else {
            $advice = 'Błędy dotyczą nośnika, którego teraz nie ma (pendrive, dysk USB, karta pamięci) - nie świadczą o awarii dysków tego komputera. Jeśli nośnik należy do klienta, sprawdź go osobno; nagłe odłączenie podczas zapisu też wywołuje takie błędy.'
        }
        Add-Finding 'Błędy dysku i systemu plików' -Status $status -Value $value -Details ($lines -join "`n") -Advice $advice -LastEvent (Get-SdLatestTime $diskEv)
    }

    # --- pozostałe zdarzenia sprzętowe: tylko poziomy krytyczny, błąd i ostrzeżenie (bez wpisów informacyjnych sterowników)
    $defs = @(
        @{ Title = 'Błędy sprzętowe zgłoszone przez WHEA'
           Filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; Level = @(1, 2, 3); StartTime = $since }
           Advice = 'WHEA raportuje błędy sprzętowe procesora, pamięci lub magistrali PCIe. Sprawdź temperatury, RAM (MemTest86), zasilanie, zresetuj podkręcanie/XMP i zaktualizuj BIOS.' }
        @{ Title = 'Zawieszenia sterownika grafiki (TDR)'
           Filter = @{ LogName = 'System'; ProviderName = @('Display', 'nvlddmkm', 'amdkmdag', 'amdwddmg', 'igfx'); Level = @(1, 2, 3); StartTime = $since }
           Advice = 'Sterownik grafiki przestaje odpowiadać. Zainstaluj czysto aktualny sterownik, sprawdź temperatury i zasilanie karty, wyłącz podkręcanie GPU.' }
        @{ Title = 'Ograniczanie wydajności procesora (throttling)'
           Filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'; Id = 37; StartTime = $since }
           Advice = 'Firmware ogranicza taktowanie procesora - zwykle przegrzanie lub niewystarczające zasilanie. Oczyść chłodzenie, wymień pastę termoprzewodzącą, sprawdź zasilacz/ładowarkę.' }
    )
    foreach ($def in $defs) {
        $ev = @(Get-SdEvents -Filter $def.Filter -Max 500)
        if ($ev.Count -eq 0) {
            Add-Finding $def.Title -Status ok -Value "Brak zdarzeń w ciągu $days dni"
            continue
        }
        $worst = 'warn'
        $lines = @()
        $grp = $ev | Group-Object { '{0}|{1}' -f $_.ProviderName, $_.Id } | Sort-Object Count -Descending
        foreach ($g in $grp) {
            $parts = $g.Name -split '\|'
            $hint = Get-SdEventHint $parts[0] ([int]$parts[1])
            if ($hint -and $hint.Sev -eq 'crit') { $worst = 'crit' }
            $last = ($g.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1)
            $txt = if ($hint) { $hint.Text } else { Get-SdFirstLine $last.Message 140 }
            $lines += ('{0} (ID {1}) ×{2}, ostatnio {3} - {4}' -f $parts[0], $parts[1], $g.Count, (Format-Dt $last.TimeCreated), $txt)
        }
        $sum = ($grp | Select-Object -First 3 | ForEach-Object { '{0}/{1} ×{2}' -f ($_.Name -split '\|')[0], ($_.Name -split '\|')[1], $_.Count }) -join ', '
        Add-Finding $def.Title -Status $worst -Value ('{0} w ciągu {1} dni: {2}' -f (Format-Count $ev.Count 'zdarzenie' 'zdarzenia' 'zdarzeń'), $days, $sum) -Details ($lines -join "`n") -Advice $def.Advice -LastEvent (Get-SdLatestTime $ev)
    }
}

Register-Check -Id 'ev.errors' -Category 'events' -Title 'Najczęstsze błędy w dzienniku zdarzeń' -Script {
    $days = if ($global:SD.Level -eq 'Full') { 30 } else { 14 }
    $since = (Get-Date).AddDays(-$days)
    $ev = @(Get-SdEvents -Filter @{ LogName = @('System', 'Application'); Level = @(1, 2); StartTime = $since } -Max 4000)
    if ($ev.Count -eq 0) {
        Add-Finding 'Błędy w dzienniku zdarzeń' -Status ok -Value "Brak błędów i zdarzeń krytycznych w ciągu $days dni"
        return
    }
    # Kernel-Power 41 (zdarzenie krytyczne) jest oceniane w teście nieoczekiwanych restartów - nie liczymy go drugi raz.
    $critEv = @($ev | Where-Object { $_.Level -eq 1 -and -not ($_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $_.Id -eq 41) })
    $crit = $critEv.Count
    $sysN = @($ev | Where-Object { $_.LogName -eq 'System' }).Count
    $appN = @($ev | Where-Object { $_.LogName -eq 'Application' }).Count
    $grp = $ev | Group-Object { '{0}|{1}|{2}' -f $_.LogName, $_.ProviderName, $_.Id } | Sort-Object Count -Descending
    $rows = @()
    $real = 0
    foreach ($g in ($grp | Select-Object -First 25)) {
        $p = $g.Name -split '\|'
        $hint = Get-SdEventHint $p[1] ([int]$p[2])
        $last = ($g.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1)
        $mean = if ($hint) { $hint.Text } else { Get-SdFirstLine $last.Message 150 }
        $noise = ($hint -and $hint.Sev -eq 'noise')
        $rows += [pscustomobject]@{ Dziennik = $p[0]; Źródło = $p[1]; ID = [int]$p[2]; Liczba = $g.Count; Ostatnio = (Format-Dt $last.TimeCreated); Opis = $(if ($noise) { '(nieszkodliwe) ' + $mean } else { $mean }) }
    }
    foreach ($g in $grp) {
        $p = $g.Name -split '\|'
        $hint = Get-SdEventHint $p[1] ([int]$p[2])
        if (-not ($hint -and $hint.Sev -eq 'noise')) { $real += $g.Count }
    }
    Add-Table 'Najczęstsze błędy w dzienniku zdarzeń' -Rows $rows
    $top = ($rows | Where-Object { $_.Opis -notlike '(nieszkodliwe)*' } | Select-Object -First 3 | ForEach-Object { '{0}/{1} ×{2}' -f $_.Źródło, $_.ID, $_.Liczba }) -join ', '
    $val = 'w ciągu {0} dni - System: {1}, Aplikacje: {2}; zdarzeń krytycznych: {3}' -f $days, $sysN, $appN, $crit
    if ($top) { $val += '; najczęściej: ' + $top }
    if ($crit -gt 0) {
        # ostrzeżenie wynika ze zdarzeń krytycznych - liczy się ostatnie z nich, a nie najnowszy zwykły błąd
        Add-Finding 'Błędy w dzienniku zdarzeń' -Status warn -Value $val -Details 'Zdarzenia krytyczne (poziom 1) zwykle oznaczają awarię lub nagłe wyłączenie systemu - zob. test o BSOD.' -LastEvent (Get-SdLatestTime $critEv) `
            -Advice 'Przejrzyj tabelę „Najczęstsze błędy w dzienniku zdarzeń” oraz Podgląd zdarzeń (eventvwr.msc) dla wskazanych źródeł.'
    } elseif ($real -ge 300) {
        Add-Finding 'Błędy w dzienniku zdarzeń' -Status info -Value $val -Details 'Duża liczba błędów jednego źródła często wskazuje źródło problemu.' `
            -Advice 'Sprawdź źródła z największą liczbą błędów w tabeli „Najczęstsze błędy w dzienniku zdarzeń”.'
    } else {
        Add-Finding 'Błędy w dzienniku zdarzeń' -Status ok -Value $val
    }
}

Register-Check -Id 'ev.apps' -Category 'events' -Title 'Awarie i zawieszenia aplikacji' -Script {
    $days = 30
    $since = (Get-Date).AddDays(-$days)
    $ev = @(Get-SdEvents -Filter @{ LogName = 'Application'; Id = @(1000, 1002); ProviderName = @('Application Error', 'Application Hang'); StartTime = $since } -Max 1500)
    if ($ev.Count -eq 0) {
        Add-Finding 'Awarie aplikacji' -Status ok -Value "Brak awarii aplikacji w ciągu $days dni"
        return
    }
    $agg = @{}
    foreach ($e in $ev) {
        $d = Get-SdEventData $e
        $app = $d['AppName']; if (-not $app) { $app = '?' }
        $mod = $d['ModuleName']; if (-not $mod) { $mod = '' }
        $kind = if ($e.Id -eq 1002) { 'zawieszenie' } else { 'awaria' }
        $k = "$app|$mod|$kind"
        if (-not $agg.ContainsKey($k)) { $agg[$k] = [pscustomobject]@{ App = $app; Mod = $mod; Kind = $kind; Count = 0; Last = $e.TimeCreated; Ver = $d['AppVersion']; Code = $d['ExceptionCode'] } }
        $agg[$k].Count++
        if ($e.TimeCreated -gt $agg[$k].Last) { $agg[$k].Last = $e.TimeCreated }
    }
    $top = @($agg.Values | Sort-Object Count -Descending)
    $rows = @($top | Select-Object -First 20 | ForEach-Object {
            [pscustomobject]@{ Aplikacja = $_.App; Wersja = $_.Ver; Rodzaj = $_.Kind; 'Moduł powodujący' = $_.Mod; 'Kod wyjątku' = $_.Code; Liczba = $_.Count; Ostatnio = (Format-Dt $_.Last) }
        })
    Add-Table 'Awarie i zawieszenia aplikacji' -Rows $rows
    $worst = $top[0]
    $gpuMod = @($top | Where-Object { $_.Mod -match '^(nv|atidxx|amdxx|ig[a-z0-9]*icd|nvwgf2|nvlddmkm|aticfx|amdvlk)' })
    $sum = ($top | Select-Object -First 3 | ForEach-Object { '{0} ×{1}' -f $_.App, $_.Count }) -join ', '
    $st = if ($worst.Count -ge 10) { 'warn' } else { 'info' }
    $adv = 'Zaktualizuj lub zainstaluj ponownie najczęściej wysypujące się aplikacje; sprawdź ich zgodność i dostępne poprawki.'
    if ($gpuMod.Count -gt 0) { $adv += ' Awarie w modułach sterownika grafiki wskazują na problem ze sterownikiem GPU - wykonaj czystą instalację sterownika.' }
    Add-Finding 'Awarie aplikacji' -Status $st -Value ('{0} w ciągu {1} dni; najczęściej: {2}' -f (Format-Count $ev.Count 'zdarzenie' 'zdarzenia' 'zdarzeń'), $days, $sum) `
        -Details 'Pełna lista w tabeli „Awarie i zawieszenia aplikacji”.' -Advice $adv -LastEvent (Get-SdLatestTime $ev)
}

Register-Check -Id 'ev.services' -Category 'events' -Title 'Błędy usług i sterowników' -Script {
    $days = 14
    $since = (Get-Date).AddDays(-$days)
    $ev = @(Get-SdEvents -Filter @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = @(7000, 7001, 7009, 7011, 7023, 7024, 7031, 7034); StartTime = $since } -Max 800)
    if ($ev.Count -eq 0) {
        Add-Finding 'Błędy usług' -Status ok -Value "Brak błędów uruchamiania i awarii usług w ciągu $days dni"
    } else {
        $agg = @{}
        foreach ($e in $ev) {
            $name = ''
            if ($e.Properties.Count -gt 0) { $name = [string]$e.Properties[0].Value }
            if (-not $name) { continue }
            if (-not $agg.ContainsKey($name)) { $agg[$name] = [pscustomobject]@{ Name = $name; Count = 0; Ids = @{}; Last = $e.TimeCreated } }
            $agg[$name].Count++; $agg[$name].Ids[[string]$e.Id] = $true
            if ($e.TimeCreated -gt $agg[$name].Last) { $agg[$name].Last = $e.TimeCreated }
        }
        $top = @($agg.Values | Sort-Object Count -Descending)
        $rows = @($top | Select-Object -First 15 | ForEach-Object { [pscustomobject]@{ Usługa = $_.Name; Liczba = $_.Count; 'ID zdarzeń' = (($_.Ids.Keys | Sort-Object) -join ', '); Ostatnio = (Format-Dt $_.Last) } })
        Add-Table 'Usługi kończące się błędem' -Rows $rows
        $sum = ($top | Select-Object -First 3 | ForEach-Object { '{0} ×{1}' -f $_.Name, $_.Count }) -join ', '
        $st = if ($ev.Count -ge 10) { 'warn' } else { 'info' }
        Add-Finding 'Błędy usług' -Status $st -Value ('{0} w ciągu {1} dni: {2}' -f (Format-Count $ev.Count 'zdarzenie' 'zdarzenia' 'zdarzeń'), $days, $sum) `
            -Details 'Zdarzenia 7000/7001/7009/7011/7023/7024/7031/7034 menedżera usług.' -LastEvent (Get-SdLatestTime $ev) `
            -Advice 'Sprawdź w services.msc wskazane usługi (typ uruchamiania, konto, zależności). Powtarzające się awarie usługi zwykle wymagają aktualizacji lub ponownej instalacji powiązanego programu.'
    }
    $pnp = @(Get-SdEvents -Filter @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-PnP'; Id = 219; StartTime = $since } -Max 200)
    if ($pnp.Count -gt 0) {
        $names = @($pnp | ForEach-Object { Get-SdFirstLine $_.Message 110 } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { '{0} (×{1})' -f $_.Name, $_.Count })
        # sterownik UMDF (WUDFRd) zgłasza to przy wielu urządzeniach wirtualnych/przenośnych - zwykle nieszkodliwe
        $onlyUmdf = (@($pnp | Where-Object { (Get-SdFirstLine $_.Message 200) -notmatch 'WUDFRd' }).Count -eq 0)
        $cnt = Format-Count $pnp.Count 'zdarzenie' 'zdarzenia' 'zdarzeń'
        if ($onlyUmdf) {
            Add-Finding 'Sterowniki, których nie udało się załadować' -Status info -Value ('{0} w ciągu {1} dni (wyłącznie sterownik UMDF WUDFRd - zwykle nieszkodliwe)' -f $cnt, $days) -Details ($names -join "`n") -LastEvent (Get-SdLatestTime $pnp)
        } else {
            Add-Finding 'Sterowniki, których nie udało się załadować' -Status warn -Value ('{0} w ciągu {1} dni' -f $cnt, $days) -Details ($names -join "`n") -LastEvent (Get-SdLatestTime $pnp) `
                -Advice 'Zainstaluj ponownie lub zaktualizuj sterowniki wskazanych urządzeń (Menedżer urządzeń); sprawdź też, czy nie blokuje ich Izolacja rdzenia (Memory integrity).'
        }
    }
}

Register-Check -Id 'ev.memdiag' -Category 'events' -Title 'Wynik diagnostyki pamięci Windows' -Script {
    $ev = @(Get-SdEvents -Filter @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results'; StartTime = (Get-Date).AddDays(-365) } -Max 10)
    if ($ev.Count -eq 0) { return }
    $e = $ev | Sort-Object TimeCreated -Descending | Select-Object -First 1
    $msg = Get-SdFirstLine $e.Message 200
    $st = 'info'
    if ($msg -match 'nie wykry|no errors|did not detect|nie znalaz') { $st = 'ok' }
    elseif ($msg -match 'sprzętow|hardware errors|wykry[łl]o błędy|detected hardware|detected errors') { $st = 'crit' }
    $adv = ''
    if ($st -eq 'crit') { $adv = 'Test pamięci wykrył błędy - wymień uszkodzony moduł RAM (testuj moduły pojedynczo) i sprawdź gniazda.' }
    Add-Finding 'Diagnostyka pamięci Windows' -Status $st -Value ('{0}: {1}' -f (Format-Dt $e.TimeCreated), $msg) -Advice $adv
}
