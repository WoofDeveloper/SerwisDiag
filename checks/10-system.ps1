# Testy kategorii: System

function Get-SdChassisName {
    param([int[]]$Types)
    $map = @{
        3 = 'Komputer stacjonarny'; 4 = 'Komputer stacjonarny (niski)'; 5 = 'Obudowa pizza-box'; 6 = 'Mini tower'; 7 = 'Tower'
        8 = 'Laptop (przenośny)'; 9 = 'Laptop'; 10 = 'Notebook'; 11 = 'Urządzenie ręczne'; 12 = 'Stacja dokująca'
        13 = 'All-in-One'; 14 = 'Subnotebook'; 15 = 'Obudowa SFF'; 16 = 'Lunch box'; 17 = 'Serwer'
        23 = 'Serwer rack'; 24 = 'Zamknięta obudowa PC'; 30 = 'Tablet'; 31 = 'Laptop 2w1'; 32 = 'Tablet z klawiaturą'
        35 = 'Mini PC'; 36 = 'Stick PC'
    }
    foreach ($t in $Types) { if ($map.ContainsKey([int]$t)) { return $map[[int]$t] } }
    return 'Nieokreślony'
}

Register-Check -Id 'sys.os' -Category 'system' -Title 'System operacyjny i okres wsparcia' -Script {
    $w = Get-SdWinInfo
    $os = Get-SdOs
    if (-not $os) {
        Add-Finding 'System operacyjny' -Status error -Value 'Nie udało się odczytać informacji o systemie (WMI jest niedostępne lub uszkodzone).' `
            -Advice 'Uszkodzone repozytorium WMI? Spróbuj: winmgmt /verifyrepository (jako administrator).'
        return
    }
    $name = Join-NonEmpty @($w.Caption, $w.Version) ' '
    $buildTxt = if ($w.Ubr -gt 0) { '{0}.{1}' -f $w.Build, $w.Ubr } else { [string]$w.Build }
    Set-SdMeta 'OS' ('{0} (kompilacja {1}, {2})' -f $name, $buildTxt, $w.Arch)
    Set-SdMeta 'OSFamily' $w.Family

    $details = @(
        "Edycja: $($w.Edition)"
        "Data instalacji: $(Format-Dt $os.InstallDate)"
        "Katalog systemu: $($os.WindowsDirectory)"
        "Język systemu: $([System.Globalization.CultureInfo]::CurrentUICulture.Name)"
        "Strefa czasowa: $([TimeZoneInfo]::Local.DisplayName)"
        "PowerShell: $($PSVersionTable.PSVersion)"
    )
    Add-Finding 'System operacyjny' -Status info -Value ('{0}, kompilacja {1}, {2}' -f $name, $buildTxt, $w.Arch) -Details ($details -join "`n")

    if ($w.Arch -eq 'x86') {
        Add-Finding 'Architektura systemu' -Status warn -Value 'System 32-bitowy' `
            -Details 'System 32-bitowy wykorzystuje maksymalnie ok. 4 GB RAM i nie uruchomi nowszych aplikacji 64-bitowych.' `
            -Advice 'Jeśli procesor jest 64-bitowy, rozważ instalację systemu 64-bitowego.'
    }

    # --- okres wsparcia (z uwzględnieniem rozszerzonych aktualizacji ESU dla Windows 10 22H2)
    if ($w.IsServer) {
        Add-Finding 'Okres wsparcia systemu' -Status info -Value 'Wersja serwerowa - sprawdź cykl wsparcia na stronie Microsoft.'
        return
    }
    $sup = Get-SdSupportInfo
    if (-not $sup) {
        $lc = Get-SdData 'lifecycle'
        $maxKnown = 0
        if ($lc) { foreach ($k in $lc.Builds.Keys) { if ([int]$k -gt $maxKnown) { $maxKnown = [int]$k } } }
        if ($maxKnown -gt 0 -and $w.Build -gt $maxKnown) {
            Add-Finding 'Okres wsparcia systemu' -Status info -Value ('Kompilacja {0} jest nowsza niż baza programu' -f $w.Build) `
                -Details 'Wersja systemu jest nowsza od danych w pliku data\lifecycle.psd1 (prawdopodobnie bieżące wydanie lub Insider).'
        } else {
            Add-Finding 'Okres wsparcia systemu' -Status info -Value ('Brak danych o kompilacji {0}' -f $w.Build)
        }
        return
    }
    $det = @()
    if ($sup.Note) { $det += $sup.Note }
    $esu = $sup.Esu
    if ($esu -and $esu.Applies) {
        $det += ''
        $det += 'Rozszerzone aktualizacje zabezpieczeń (ESU):'
        $det += ' - licencja ESU (firmy/edukacja): ' + $(if ($esu.LicenseYear -gt 0) { 'rok {0}, ważna do {1}' -f $esu.LicenseYear, (Format-Dt $esu.LicenseUntil -DateOnly) } else { 'brak' })
        $ct = Get-SdEsuConsumerText $esu.ConsumerCode
        $det += ' - program konsumencki: ' + $(if ($ct) { $ct } else { 'brak danych w profilu użytkownika' })
        $det += (' - kompilacja {0}.{1}: {2}' -f $w.Build, $esu.Ubr, $(if ($esu.UbrAfterEos) { 'zawiera poprawki ESU (nowsza niż ostatnia bezpłatna {0}.{1})' -f $w.Build, $esu.LastFreeUbr } else { 'brak poprawek wydanych po zakończeniu wsparcia' }))
    }
    if ($sup.LastPatch) { $det += ('Ostatnia poprawka systemu: {0} - {1}' -f (Format-Dt $sup.LastPatch.Date), (Limit-Text $sup.LastPatch.Title 100)) }
    $det += ('Dane o okresach wsparcia: ' + (Get-SdKnowledgeInfo).Text)
    $st = $sup.Result
    Add-Finding 'Okres wsparcia systemu' -Status $st.Status -Value $st.Value -Details ($det -join "`n") -Advice $st.Advice
}

Register-Check -Id 'sys.uptime' -Category 'system' -Title 'Czas pracy i szybkie uruchamianie' -Script {
    $os = Get-SdOs
    if (-not $os -or -not $os.LastBootUpTime) { return }
    $boot = [datetime]$os.LastBootUpTime
    $up = (Get-Date) - $boot
    $fast = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
    $hib = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled' 0

    $details = "Ostatni start jądra systemu: $(Format-Dt $boot)"
    if ([int]$fast -eq 1) { $details += "`n" + 'Szybkie uruchamianie jest włączone: „Zamknij komputer” nie zeruje tego licznika, liczy się wyłącznie „Uruchom ponownie”.' }
    if ($up.TotalDays -ge 30) {
        Add-Finding 'Czas pracy bez restartu' -Status warn -Value (Format-Span $up) -Details $details `
            -Advice 'Wykonaj pełny restart (opcja „Uruchom ponownie”). Restart stosuje oczekujące aktualizacje, zwalnia pamięć i usuwa część problemów.'
    } elseif ($up.TotalDays -ge 14) {
        Add-Finding 'Czas pracy bez restartu' -Status info -Value (Format-Span $up) -Details $details
    } else {
        Add-Finding 'Czas pracy bez restartu' -Status ok -Value (Format-Span $up) -Details $details
    }
    if ([int]$fast -eq 1) {
        Add-Finding 'Szybkie uruchamianie (Fast Startup)' -Status info -Value 'Włączone' `
            -Details 'Przy wyłączeniu komputer zapisuje stan jądra systemu (hibernacja), więc sterowniki nie ładują się od zera.' `
            -Advice 'Przy problemach z uśpieniem, sterownikami, siecią lub aktualizacjami wyłącz szybkie uruchamianie (Opcje zasilania > Wybierz działanie przycisków zasilania) i sprawdź, czy problem ustąpi.'
    } else {
        Add-Finding 'Szybkie uruchamianie (Fast Startup)' -Status ok -Value 'Wyłączone'
    }
}

Register-Check -Id 'sys.identity' -Category 'system' -Title 'Komputer, płyta główna i BIOS/UEFI' -Script {
    $cs = Get-SdCs
    $bios = Get-Cim Win32_BIOS | Select-Object -First 1
    $bb = Get-Cim Win32_BaseBoard | Select-Object -First 1
    $csp = Get-Cim Win32_ComputerSystemProduct | Select-Object -First 1
    $enc = Get-Cim Win32_SystemEnclosure | Select-Object -First 1
    $biosReg = Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction SilentlyContinue

    $mfr = if ($cs) { Get-SdCleanString $cs.Manufacturer '' } else { '' }
    $model = if ($cs) { Get-SdCleanString $cs.Model '' } else { '' }
    $family = ''
    if ($biosReg -and $biosReg.PSObject.Properties['SystemFamily']) { $family = Get-SdCleanString ([string]$biosReg.SystemFamily) '' }
    if (-not $family -and $csp) { $family = Get-SdCleanString ([string]$csp.Version) '' }
    $chassis = 'Nieokreślony'
    if ($enc -and $enc.ChassisTypes) { $chassis = Get-SdChassisName @($enc.ChassisTypes | ForEach-Object { [int]$_ }) }
    $isVm = Test-SdVm

    $title = Join-NonEmpty @($mfr, $model, $(if ($family -and $family -ne $model) { "($family)" })) ' '
    Set-SdMeta 'Model' $title
    Set-SdMeta 'Chassis' $chassis
    $lines = @("Typ obudowy: $chassis")
    if ($cs) {
        if ($cs.PartOfDomain) { $lines += "Domena: $($cs.Domain)" } else { $lines += "Grupa robocza: $($cs.Domain)" }
    }
    Add-Finding 'Komputer' -Status info -Value $(if ($title) { $title } else { 'Nie rozpoznano modelu' }) -Details ($lines -join "`n")

    $serial = ''
    if ($bios) { $serial = Get-SdCleanString ([string]$bios.SerialNumber) '' }
    if (-not $serial -and $csp) { $serial = Get-SdCleanString ([string]$csp.IdentifyingNumber) '' }
    if ($serial) {
        Set-SdMeta 'Serial' $serial
        Add-Finding 'Numer seryjny' -Status info -Value $serial -Private
    } else {
        Add-Finding 'Numer seryjny' -Status info -Value 'Producent nie wpisał numeru seryjnego do BIOS.' -Private
    }

    if ($isVm) {
        Add-Finding 'Maszyna wirtualna' -Status info -Value 'Wykryto środowisko wirtualne' -Details 'Część testów sprzętowych (SMART, bateria, temperatury) nie ma w maszynie wirtualnej sensu.'
    }

    if ($bb) {
        $bbTitle = Join-NonEmpty @((Get-SdCleanString ([string]$bb.Manufacturer) ''), (Get-SdCleanString ([string]$bb.Product) '')) ' '
        if ($bbTitle) { Add-Finding 'Płyta główna' -Status info -Value $bbTitle; Set-SdMeta 'Board' $bbTitle }
    }

    $fw = Get-SdFirmwareType
    if ($bios) {
        $rel = $bios.ReleaseDate
        $age = $null
        if ($rel) { $age = (Get-Date) - [datetime]$rel }
        $biosTxt = Join-NonEmpty @($bios.Manufacturer, $bios.SMBIOSBIOSVersion, $(if ($rel) { "z dnia $(Format-Dt $rel -DateOnly)" })) ' '
        Set-SdMeta 'Bios' $biosTxt
        $adv = ''
        $st = 'info'
        if ($age -and $age.TotalDays -gt 365 * 6 -and -not $isVm) {
            $st = 'info'
            $adv = 'BIOS jest starszy niż 6 lat. Sprawdź na stronie producenta, czy są poprawki (stabilność, zgodność z Windows 11, luki w zabezpieczeniach). Aktualizuj tylko przy podłączonym zasilaniu i naładowanej baterii.'
        }
        Add-Finding 'BIOS / UEFI' -Status $st -Value ("$biosTxt; tryb: $fw") -Advice $adv
    } else {
        Add-Finding 'Tryb rozruchu' -Status info -Value $fw
    }
}

Register-Check -Id 'sys.win11' -Category 'system' -Title 'Gotowość na Windows 11' -Script {
    $w = Get-SdWinInfo
    if ($w.Build -ge 22000) {
        Add-Finding 'Gotowość na Windows 11' -Status ok -Value 'Windows 11 jest już zainstalowany.'
        return
    }
    if ($w.IsServer) { return }

    $cpu = Get-SdCpus | Select-Object -First 1
    $ci = Get-SdCpuInfo ([string]$cpu.Name)
    $cs = Get-SdCs

    # RAM: preferuj sumę zainstalowanych kości (TotalPhysicalMemory jest pomniejszone o pamięć zarezerwowaną)
    $installed = 0.0
    foreach ($m in (Get-Cim Win32_PhysicalMemory)) { $installed += [double]$m.Capacity }
    if ($installed -le 0 -and $cs) { $installed = [double]$cs.TotalPhysicalMemory }
    $ramGb = $installed / 1GB

    # Dysk systemowy
    $diskGb = 0.0
    $ld = Get-Cim Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $env:SystemDrive) | Select-Object -First 1
    if ($ld) {
        $diskGb = [double]$ld.Size / 1GB
        try {
            $part = Get-CimAssociatedInstance -InputObject $ld -Association Win32_LogicalDiskToPartition -ErrorAction Stop | Select-Object -First 1
            if ($part) {
                $drive = Get-CimAssociatedInstance -InputObject $part -Association Win32_DiskDriveToDiskPartition -ErrorAction Stop | Select-Object -First 1
                if ($drive -and $drive.Size) { $diskGb = [double]$drive.Size / 1GB }
            }
        } catch { }
    }

    $fw = Get-SdFirmwareType
    $sb = Get-SdSecureBoot
    $tpm = Get-SdTpm

    $rows = New-Object System.Collections.ArrayList
    $hard = @()      # blokady sprzętowe (wymiana podzespołów)
    $soft = @()      # do naprawienia ustawieniami / drobną modernizacją

    # procesor
    if ($ci.Win11 -eq $true) { [void]$rows.Add("✔ Procesor: $($cpu.Name) - na liście zgodnych (szacunek)") }
    elseif ($ci.Win11 -eq $false) { [void]$rows.Add("✖ Procesor: $($cpu.Name) - $($ci.Gen) nie jest obsługiwany"); $hard += 'procesor' }
    else { [void]$rows.Add("? Procesor: $($cpu.Name) - sprawdź na liście procesorów Microsoft") }
    if ($ci.Note) { [void]$rows.Add("   $($ci.Note)") }
    if ($w.Arch -notin @('x64', 'ARM64')) { $soft += '64-bitowy system'; [void]$rows.Add("✖ System jest 32-bitowy (wymagany 64-bitowy)") }
    if ($cpu -and [int]$cpu.NumberOfLogicalProcessors -lt 2) { $hard += 'liczba rdzeni'; [void]$rows.Add('✖ Wymagane co najmniej 2 rdzenie logiczne') }

    # RAM
    if ($ramGb -ge 3.7) { [void]$rows.Add(("✔ RAM: {0} GB (min. 4 GB)" -f (Format-Num $ramGb 1))) }
    else { [void]$rows.Add(("✖ RAM: {0} GB (min. 4 GB)" -f (Format-Num $ramGb 1))); $soft += 'RAM' }

    # dysk
    if ($diskGb -ge 63) { [void]$rows.Add(("✔ Dysk systemowy: {0} GB (min. 64 GB)" -f (Format-Num $diskGb 0))) }
    else { [void]$rows.Add(("✖ Dysk systemowy: {0} GB (min. 64 GB)" -f (Format-Num $diskGb 0))); $soft += 'dysk' }

    # UEFI / Secure Boot
    if ($fw -eq 'UEFI') {
        [void]$rows.Add('✔ Tryb UEFI')
        if ($sb.Known -and $sb.Enabled) { [void]$rows.Add('✔ Secure Boot włączony') }
        elseif ($sb.Known) { [void]$rows.Add('✖ Secure Boot jest wyłączony - włącz w BIOS/UEFI (wymaga dysku GPT)'); $soft += 'Secure Boot' }
        else { [void]$rows.Add('✖ Secure Boot nieobsługiwany przez firmware'); $hard += 'Secure Boot' }
    } elseif ($fw -eq 'BIOS') {
        [void]$rows.Add('✖ Tryb Legacy BIOS - wymagany UEFI (konwersja MBR→GPT narzędziem mbr2gpt i przełączenie w BIOS)'); $soft += 'UEFI'
    } else { [void]$rows.Add('? Nie rozpoznano trybu rozruchu') }

    # TPM
    if ($tpm.Present -and $tpm.Version -like '2*') {
        if ($tpm.Enabled -eq $false) { [void]$rows.Add('✖ TPM 2.0 jest wyłączony - włącz w BIOS (fTPM / PTT)'); $soft += 'TPM' }
        else { [void]$rows.Add('✔ TPM 2.0') }
    } elseif ($tpm.Present -and $tpm.Version -like '1*') {
        [void]$rows.Add('✖ Wykryto TPM 1.2 (wymagany 2.0)'); $hard += 'TPM 2.0'
    } elseif ($tpm.Present) {
        [void]$rows.Add('? Wykryto TPM o nieustalonej wersji')
    } else {
        [void]$rows.Add('✖ Nie wykryto TPM - sprawdź w BIOS opcje fTPM / Intel PTT / AMD fTPM'); $soft += 'TPM'
    }
    [void]$rows.Add('(DirectX 12 / WDDM 2.x oraz wyświetlacz HD nie są sprawdzane)')

    $details = ($rows -join "`n")
    $cpuTxt = if ($ci.Gen) { " ($($ci.Gen)$(if ($ci.Year) { ', ' + $ci.Year }))" } else { '' }
    if ($hard.Count -gt 0) {
        Add-Finding 'Gotowość na Windows 11' -Status warn -Value ('Niezgodny sprzęt: ' + ($hard -join ', ')) -Details $details `
            -Advice 'Ten komputer nie spełnia sprzętowych wymagań Windows 11. Przy zakończonym wsparciu Windows 10 rozważ wymianę komputera lub program ESU; instalacja z pominięciem wymagań nie jest wspierana przez Microsoft.'
    }
    elseif ($soft.Count -gt 0) {
        Add-Finding 'Gotowość na Windows 11' -Status warn -Value ('Do poprawy przed aktualizacją: ' + ($soft -join ', ')) -Details $details `
            -Advice 'Sprzęt rokuje dobrze, ale wymaga zmian w ustawieniach BIOS lub drobnej modernizacji (RAM/dysk). Po usunięciu blokad można zaktualizować do Windows 11.'
    }
    elseif ($ci.Win11 -eq $null) {
        Add-Finding 'Gotowość na Windows 11' -Status info -Value 'Prawdopodobnie zgodny - zweryfikuj procesor' -Details $details `
            -Advice 'Uruchom aplikację „Kontrola kondycji komputera” (PC Health Check) lub porównaj model procesora z listą Microsoft.'
    }
    else {
        Add-Finding 'Gotowość na Windows 11' -Status ok -Value ('Spełnia wymagania (szacunek)' + $cpuTxt) -Details $details `
            -Advice 'Komputer można zaktualizować do Windows 11 przez Windows Update (przed aktualizacją wykonaj kopię danych).'
    }
}

Register-Check -Id 'sys.restore' -Category 'system' -Title 'Punkty przywracania systemu' -NeedsAdmin -Script {
    $points = @()
    try { $points = @(Get-ComputerRestorePoint -ErrorAction Stop) } catch { Write-SdLog ("Punkty przywracania: " + $_.Exception.Message) 'WARN' }
    if ($points.Count -eq 0) {
        Add-Finding 'Punkty przywracania systemu' -Status info -Value 'Brak punktów przywracania (ochrona systemu może być wyłączona)' `
            -Advice 'Przed większymi zmianami (sterowniki, naprawa systemu) utwórz punkt przywracania lub obraz systemu.'
        return
    }
    $last = $points | Sort-Object SequenceNumber | Select-Object -Last 1
    $lastDate = $null
    try { $lastDate = [Management.ManagementDateTimeConverter]::ToDateTime($last.CreationTime) } catch { }
    Add-Finding 'Punkty przywracania systemu' -Status ok -Value ('{0}; ostatni: {1} ({2})' -f (Format-Count $points.Count 'punkt' 'punkty' 'punktów'), (Format-Dt $lastDate), $last.Description)
}
