# Testy kategorii: Sprzęt

Register-Check -Id 'hw.cpu' -Category 'hardware' -Title 'Procesor' -Script {
    $cpus = @(Get-SdCpus)
    if ($cpus.Count -eq 0) {
        Add-Finding 'Procesor' -Status error -Value 'Brak danych o procesorze (WMI).'
        return
    }
    $c = $cpus[0]
    $name = (([string]$c.Name) -replace '\s+', ' ').Trim()
    $cores = 0; $threads = 0
    foreach ($p in $cpus) { $cores += [int]$p.NumberOfCores; $threads += [int]$p.NumberOfLogicalProcessors }
    $ghz = if ($c.MaxClockSpeed) { [math]::Round([double]$c.MaxClockSpeed / 1000, 2) } else { 0 }
    $ci = Get-SdCpuInfo $name
    $cs = Get-SdCs

    Set-SdMeta 'Cpu' ('{0} ({1} rdzeni / {2} wątków)' -f $name, $cores, $threads)
    $d = @(
        "Producent: $($c.Manufacturer)"
        "Rdzenie / wątki: $cores / $threads"
        "Taktowanie maksymalne (znamionowe): $(Format-Num $ghz 2) GHz"
        "Gniazdo: $($c.SocketDesignation)"
        "Pamięć podręczna L2: $(Format-Num ([double]$c.L2CacheSize / 1024) 1) MB, L3: $(Format-Num ([double]$c.L3CacheSize / 1024) 1) MB"
    )
    if ($cpus.Count -gt 1) { $d += "Liczba procesorów fizycznych: $($cpus.Count)" }
    if ($ci.Gen) { $d += "Rozpoznana generacja: $($ci.Gen)$(if ($ci.Year) { ', rok premiery ok. ' + $ci.Year })" }
    Add-Finding 'Procesor' -Status info -Value ('{0}; {1} rdzeni / {2} wątków' -f $name, $cores, $threads) -Details ($d -join "`n")

    if ($ci.Year -and ((Get-Date).Year - $ci.Year) -ge 9 -and -not (Test-SdVm)) {
        Add-Finding 'Wiek procesora' -Status info -Value ('Procesor z ok. {0} r. ({1} lat)' -f $ci.Year, ((Get-Date).Year - $ci.Year)) `
            -Details 'Starsza platforma: ograniczona wydajność, brak zgodności z Windows 11 (przy generacjach sprzed 8. Intel / sprzed Ryzen 2000).' `
            -Advice 'Największy zysk w takim komputerze daje dysk SSD i minimum 8 GB RAM; przy ocenie opłacalności napraw weź pod uwagę wiek platformy.'
    }

    # wirtualizacja
    $hv = $false
    if ($cs -and $cs.PSObject.Properties['HypervisorPresent']) { $hv = [bool]$cs.HypervisorPresent }
    if ($hv) {
        Add-Finding 'Wirtualizacja sprzętowa' -Status ok -Value 'System korzysta z wirtualizacji (Hyper-V / zabezpieczenia oparte na wirtualizacji)'
    } elseif ($c.PSObject.Properties['VirtualizationFirmwareEnabled'] -and $c.VirtualizationFirmwareEnabled -eq $false -and -not (Test-SdVm)) {
        Add-Finding 'Wirtualizacja sprzętowa' -Status info -Value 'Wyłączona w BIOS/UEFI (Intel VT-x / AMD-V)' `
            -Advice 'Włącz w BIOS, jeśli użytkownik potrzebuje WSL2, Hyper-V, Windows Sandbox lub emulatorów Androida.'
    } elseif ($c.PSObject.Properties['VirtualizationFirmwareEnabled'] -and $c.VirtualizationFirmwareEnabled) {
        Add-Finding 'Wirtualizacja sprzętowa' -Status ok -Value 'Włączona w BIOS/UEFI'
    }
}

Register-Check -Id 'hw.ram' -Category 'hardware' -Title 'Pamięć RAM' -Script {
    $mods = @(Get-Cim Win32_PhysicalMemory)
    $arr = Get-Cim Win32_PhysicalMemoryArray | Select-Object -First 1
    $cs = Get-SdCs
    $w = Get-SdWinInfo

    $typeMap = @{ 20 = 'DDR'; 21 = 'DDR2'; 22 = 'DDR2 FB-DIMM'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $ffMap = @{ 8 = 'DIMM'; 12 = 'SO-DIMM'; 9 = 'RIMM'; 13 = 'SRIMM'; 11 = 'SIMM' }

    $totalBytes = 0.0
    $rows = @()
    $caps = @(); $speeds = @()
    foreach ($m in $mods) {
        $cap = [double]$m.Capacity
        $totalBytes += $cap
        $t = ''
        $tn = 0
        if ($m.PSObject.Properties['SMBIOSMemoryType'] -and $m.SMBIOSMemoryType) { $tn = [int]$m.SMBIOSMemoryType }
        if ($tn -le 1 -and $m.MemoryType) { $tn = [int]$m.MemoryType }
        if ($typeMap.ContainsKey($tn)) { $t = $typeMap[$tn] }
        $ff = ''
        if ($m.FormFactor -and $ffMap.ContainsKey([int]$m.FormFactor)) { $ff = $ffMap[[int]$m.FormFactor] }
        if ($m.DeviceLocator -match 'Onboard|Memory Down|Soldered|OnBoard') { $ff = 'lutowana' }
        $rated = [int]$m.Speed
        $conf = 0
        if ($m.PSObject.Properties['ConfiguredClockSpeed'] -and $m.ConfiguredClockSpeed) { $conf = [int]$m.ConfiguredClockSpeed }
        $caps += $cap; $speeds += $(if ($conf) { $conf } else { $rated })
        $rows += [pscustomobject]@{
            Slot         = (Join-NonEmpty @($m.DeviceLocator, $m.BankLabel) ' / ')
            Pojemność    = (Format-Size $cap 0)
            Typ          = Join-NonEmpty @($t, $ff) ' '
            'MHz (znam.)' = $rated
            'MHz (ustaw.)' = $(if ($conf) { $conf } else { '-' })
            Producent    = (Get-SdCleanString ([string]$m.Manufacturer) '-')
            'Numer części' = (Get-SdCleanString (([string]$m.PartNumber).Trim()) '-')
        }
    }
    if ($mods.Count -eq 0 -and $cs) { $totalBytes = [double]$cs.TotalPhysicalMemory }
    $totalGb = $totalBytes / 1GB
    $slots = 0
    if ($arr -and $arr.MemoryDevices) { $slots = [int]$arr.MemoryDevices }
    $maxGb = 0.0
    if ($arr) {
        if ($arr.PSObject.Properties['MaxCapacityEx'] -and $arr.MaxCapacityEx) { $maxGb = [double]$arr.MaxCapacityEx / 1MB }
        elseif ($arr.MaxCapacity) { $maxGb = [double]$arr.MaxCapacity / 1MB }
    }
    $first = $rows | Select-Object -First 1
    $typeTxt = if ($first) { ($first.Typ -replace '\s?(DIMM|SO-DIMM|lutowana)$', '') } else { '' }
    $speedTxt = ''
    if ($speeds.Count -gt 0 -and $speeds[0]) { $speedTxt = " $($speeds[0]) MHz" }
    $typeSeg = ''
    if ($typeTxt) { $typeSeg = ' ' + $typeTxt }
    $summary = if ($mods.Count -gt 0) {
        '{0} GB ({1} × {2}{3}{4})' -f (Format-Num $totalGb 0), $mods.Count, (Format-Size $caps[0] 0), $typeSeg, $speedTxt
    } else { '{0} GB' -f (Format-Num $totalGb 1) }
    Set-SdMeta 'Ram' $summary

    $d = @("Zainstalowane moduły: $($mods.Count)$(if ($slots) { ' z ' + $slots + ' gniazd' })")
    if ($maxGb -gt 0) { $d += "Maksymalna pojemność wg płyty: $(Format-Num $maxGb 0) GB" }
    if ($cs) { $d += "Dostępne dla systemu: $(Format-Size $cs.TotalPhysicalMemory 1)" }

    $minOk = if ($w.Build -ge 10240) { 8 } else { 4 }
    if ($totalGb -lt 3.7) {
        Add-Finding 'Pamięć RAM' -Status warn -Value $summary -Details ($d -join "`n") `
            -Advice 'Bardzo mało pamięci RAM. Dołożenie modułu (docelowo min. 8 GB) znacząco poprawi komfort pracy.'
    } elseif ($totalGb -lt 7.5 -and $w.Build -ge 10240) {
        Add-Finding 'Pamięć RAM' -Status warn -Value $summary -Details ($d -join "`n") `
            -Advice 'Dla Windows 10/11 to niewiele - przy przeglądarce z wieloma kartami komputer będzie używał wolnego pliku wymiany. Rozważ dołożenie RAM do 8-16 GB.'
    } else {
        Add-Finding 'Pamięć RAM' -Status ok -Value $summary -Details ($d -join "`n")
    }

    if ($rows.Count -gt 0) { Add-Table 'Moduły pamięci RAM' -Rows $rows }

    # tryb jedno- / dwukanałowy
    $removable = ($mods | Where-Object { $_.DeviceLocator -notmatch 'Onboard|Memory Down|Soldered|OnBoard' } | Measure-Object).Count
    if ($mods.Count -eq 1 -and $slots -ge 2 -and $removable -ge 1 -and $totalGb -ge 3.7) {
        Add-Finding 'Tryb pracy pamięci' -Status info -Value 'Jeden moduł - tryb jednokanałowy' `
            -Details "Komputer ma $slots gniazda pamięci, a zajęte jest tylko jedno." `
            -Advice 'Drugi moduł o takiej samej pojemności i parametrach włączy tryb dwukanałowy - widocznie szybszą grafikę zintegrowaną i ogólną wydajność.'
    }
    # różne moduły
    $uniqCaps = @($caps | Select-Object -Unique)
    $uniqSpeeds = @($speeds | Where-Object { $_ } | Select-Object -Unique)
    if ($mods.Count -gt 1 -and ($uniqCaps.Count -gt 1 -or $uniqSpeeds.Count -gt 1)) {
        Add-Finding 'Zgodność modułów pamięci' -Status info -Value 'Moduły różnią się pojemnością lub szybkością' `
            -Details 'Pamięć pracuje z parametrami najwolniejszego modułu, a tryb dwukanałowy może obejmować tylko część pojemności.' `
            -Advice 'Jeśli to możliwe, stosuj identyczne moduły (ten sam producent, pojemność i taktowanie).'
    }
    # XMP / EXPO nie włączone (tylko komputery stacjonarne z DIMM)
    $desktopDimm = ($rows | Where-Object { $_.Typ -match '(^| )DIMM$' -and $_.Typ -notmatch 'SO-DIMM' } | Measure-Object).Count
    foreach ($m in $mods) {
        $rated = [int]$m.Speed; $conf = 0
        if ($m.PSObject.Properties['ConfiguredClockSpeed'] -and $m.ConfiguredClockSpeed) { $conf = [int]$m.ConfiguredClockSpeed }
        if ($desktopDimm -gt 0 -and $conf -gt 0 -and $rated -gt 0 -and $conf -lt ($rated * 0.8)) {
            Add-Finding 'Profil XMP / EXPO' -Status info -Value ('Pamięć pracuje {0} MHz zamiast znamionowych {1} MHz' -f $conf, $rated) `
                -Advice 'Włącz profil XMP (Intel) lub EXPO/DOCP (AMD) w BIOS/UEFI, aby pamięć osiągnęła deklarowaną szybkość.'
            break
        }
    }
    # system 32-bitowy z dużą ilością RAM
    if ($w.Arch -eq 'x86' -and $totalGb -gt 4.2) {
        Add-Finding 'RAM a architektura systemu' -Status warn -Value ('Zainstalowano {0} GB, a system jest 32-bitowy' -f (Format-Num $totalGb 0)) `
            -Advice 'System 32-bitowy wykorzysta najwyżej ok. 3-4 GB. Zainstaluj wersję 64-bitową, aby wykorzystać całą pamięć.'
    }
}

function Get-SdGpuVram {
    # Prawdziwy rozmiar VRAM z rejestru (Win32_VideoController.AdapterRAM jest ucinane do 4 GB).
    param([string]$Name)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($k in (Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
        if ($k.PSChildName -notmatch '^\d{4}$') { continue }
        $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
        if (-not $p -or $p.DriverDesc -ne $Name) { continue }
        $q = $p.PSObject.Properties['HardwareInformation.qwMemorySize']
        if ($q -and $q.Value) { return [double]$q.Value }
        $m = $p.PSObject.Properties['HardwareInformation.MemorySize']
        if ($m -and $m.Value) {
            if ($m.Value -is [byte[]]) { return [double][BitConverter]::ToUInt32($m.Value, 0) }
            return [double]$m.Value
        }
    }
    return 0.0
}

Register-Check -Id 'hw.gpu' -Category 'hardware' -Title 'Karta graficzna' -Script {
    $gpus = @(Get-Cim Win32_VideoController)
    if ($gpus.Count -eq 0) {
        Add-Finding 'Karta graficzna' -Status warn -Value 'Nie wykryto żadnej karty graficznej.'
        return
    }
    $rows = @()
    $names = @()
    foreach ($g in $gpus) {
        $vram = Get-SdGpuVram ([string]$g.Name)
        if ($vram -le 0 -and $g.AdapterRAM) { $vram = [double]$g.AdapterRAM }
        $res = ''
        if ($g.CurrentHorizontalResolution) { $res = '{0}×{1} @ {2} Hz' -f $g.CurrentHorizontalResolution, $g.CurrentVerticalResolution, $g.CurrentRefreshRate }
        $age = $null
        if ($g.DriverDate) { $age = ((Get-Date) - [datetime]$g.DriverDate).TotalDays / 365.25 }
        $basic = ([string]$g.Name -match 'Basic Display|Basic Render|Standardowa karta graficzna|Standard VGA|Microsoft Basic')
        $names += [string]$g.Name

        $rows += [pscustomobject]@{
            Karta = [string]$g.Name; 'VRAM' = $(if ($vram -gt 0) { Format-Size $vram 0 } else { '-' })
            'Wersja sterownika' = [string]$g.DriverVersion; 'Data sterownika' = (Format-Dt $g.DriverDate -DateOnly); Rozdzielczość = $res
        }
        $d = @("Wersja sterownika: $($g.DriverVersion) z dnia $(Format-Dt $g.DriverDate -DateOnly)")
        if ($vram -gt 0) { $d += "Pamięć wideo: $(Format-Size $vram 0)" }
        if ($res) { $d += "Aktualny tryb: $res" }
        $d += "Identyfikator: $($g.PNPDeviceID)"

        if ($basic) {
            Add-Finding ('Karta graficzna: ' + $g.Name) -Status warn -Value 'Działa na sterowniku podstawowym Microsoft' -Details ($d -join "`n") `
                -Advice 'Brak właściwego sterownika grafiki: obniżona wydajność, brak akceleracji i skalowania. Zainstaluj sterownik producenta komputera lub układu (Intel/NVIDIA/AMD).'
        }
        elseif ($g.ConfigManagerErrorCode -and [int]$g.ConfigManagerErrorCode -ne 0) {
            Add-Finding ('Karta graficzna: ' + $g.Name) -Status crit -Value ('Błąd urządzenia (kod ' + $g.ConfigManagerErrorCode + ')') `
                -Details (($d -join "`n") + "`n" + (Get-SdPnpErrorText ([int]$g.ConfigManagerErrorCode))) `
                -Advice 'Zainstaluj ponownie sterownik grafiki (najlepiej czysta instalacja z DDU); sprawdź, czy karta jest poprawnie osadzona i zasilona.'
        }
        elseif ($age -ne $null -and $age -gt 3) {
            Add-Finding ('Karta graficzna: ' + $g.Name) -Status info -Value ('{0}; sterownik sprzed {1} lat' -f $(if ($vram -gt 0) { Format-Size $vram 0 } else { 'brak danych o VRAM' }), (Format-Num $age 0)) `
                -Details ($d -join "`n") `
                -Advice 'Sterownik grafiki jest stary - sprawdź, czy producent udostępnia nowszy (poprawki stabilności i wydajności).'
        }
        else {
            Add-Finding ('Karta graficzna: ' + $g.Name) -Status ok -Value $(if ($vram -gt 0) { Format-Size $vram 0 } else { 'brak danych o VRAM' }) -Details ($d -join "`n")
        }
    }
    Set-SdMeta 'Gpu' ($names -join ' + ')
    Add-Table 'Karty graficzne' -Rows $rows
    if (@($gpus | Where-Object { $_.Name -notmatch 'Basic|Remote|Mirror|Virtual' }).Count -ge 2) {
        Add-Finding 'Układy graficzne' -Status info -Value 'Zintegrowana i dedykowana grafika (hybrydowa)' `
            -Advice 'W razie problemów z wydajnością sprawdź w Ustawieniach grafiki, który układ obsługuje daną aplikację.'
    }
}

Register-Check -Id 'hw.monitors' -Category 'hardware' -Title 'Wyświetlacze' -Script {
    $ids = @(Get-Cim -Namespace 'root\wmi' -Class WmiMonitorID)
    if ($ids.Count -eq 0) { return }
    $params = @(Get-Cim -Namespace 'root\wmi' -Class WmiMonitorBasicDisplayParams)
    $vendors = @{
        AUO = 'AU Optronics'; BOE = 'BOE'; LGD = 'LG Display'; SDC = 'Samsung Display'; CMN = 'Chimei Innolux'; IVO = 'InfoVision'; SHP = 'Sharp'
        LEN = 'Lenovo'; DEL = 'Dell'; SAM = 'Samsung'; GSM = 'LG Electronics'; ACI = 'ASUS'; AUS = 'ASUS'; AOC = 'AOC'; PHL = 'Philips'
        HWP = 'HP'; BNQ = 'BenQ'; ACR = 'Acer'; VSC = 'ViewSonic'; MSI = 'MSI'; GBT = 'Gigabyte'; NEC = 'NEC'; HKC = 'HKC'; CSO = 'CSOT'; TMX = 'Tianma'
    }
    $rows = @()
    foreach ($m in $ids) {
        $conv = { param($a) if ($a) { (($a | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '').Trim() } else { '' } }
        $mf = & $conv $m.ManufacturerName
        $nm = & $conv $m.UserFriendlyName
        $pc = & $conv $m.ProductCodeID
        $diag = '-'
        $p = $params | Where-Object { $_.InstanceName -eq $m.InstanceName } | Select-Object -First 1
        if ($p -and $p.MaxHorizontalImageSize -and $p.MaxVerticalImageSize) {
            $diag = '{0}"' -f (Format-Num ([math]::Sqrt([math]::Pow($p.MaxHorizontalImageSize, 2) + [math]::Pow($p.MaxVerticalImageSize, 2)) / 2.54) 1)
        }
        $rows += [pscustomobject]@{
            Producent = $(if ($vendors.ContainsKey($mf)) { $vendors[$mf] + " ($mf)" } else { $mf })
            Model = $(if ($nm) { $nm } else { '(wbudowany panel)' }); 'Kod panelu' = $pc
            Rok = $m.YearOfManufacture; Przekątna = $diag
        }
    }
    # ten sam panel bywa raportowany raz na każdą kartę graficzną
    $rows = @($rows | Sort-Object Producent, Model, 'Kod panelu', Rok -Unique)
    $first = $rows | Select-Object -First 1
    Add-Finding 'Wyświetlacze' -Status info -Value ('{0} szt.; {1} {2} {3}' -f $rows.Count, $first.Producent, $first.'Kod panelu', $first.Przekątna)
    Add-Table 'Wyświetlacze' -Rows $rows
}

Register-Check -Id 'hw.thermal' -Category 'hardware' -Title 'Temperatury (czujniki ACPI)' -NeedsAdmin -Script {
    $zones = @(Get-Cim -Namespace 'root\wmi' -Class MSAcpi_ThermalZoneTemperature)
    if ($zones.Count -eq 0) {
        Add-Finding 'Temperatury (ACPI)' -Status info -Value 'Brak czujnika dostępnego przez WMI' `
            -Details 'Wiele płyt nie udostępnia temperatur przez ACPI. Rzeczywiste temperatury CPU/GPU zmierzysz w HWiNFO lub HWMonitor.'
        return
    }
    $max = -1000.0
    $d = @()
    foreach ($z in $zones) {
        $c = [double]$z.CurrentTemperature / 10 - 273.15
        $crit = $null
        if ($z.CriticalTripPoint) { $crit = [double]$z.CriticalTripPoint / 10 - 273.15 }
        if ($c -gt $max) { $max = $c }
        $critTxt = ''
        if ($crit) { $critTxt = ' (punkt krytyczny ' + (Format-Num $crit 0) + ' °C)' }
        $d += ('{0}: {1} °C{2}' -f $z.InstanceName, (Format-Num $c 1), $critTxt)
    }
    $d += 'Uwaga: to temperatura strefy ACPI, a nie rdzenia procesora.'
    if ($max -ge 90) {
        Add-Finding 'Temperatury (ACPI)' -Status crit -Value ('{0} °C' -f (Format-Num $max 1)) -Details ($d -join "`n") `
            -Advice 'Bardzo wysoka temperatura. Oczyść układ chłodzenia, wymień pastę termoprzewodzącą, sprawdź wentylatory.'
    } elseif ($max -ge 80) {
        Add-Finding 'Temperatury (ACPI)' -Status warn -Value ('{0} °C' -f (Format-Num $max 1)) -Details ($d -join "`n") `
            -Advice 'Wysoka temperatura już w spoczynku/lekkim obciążeniu. Sprawdź drożność wentylacji i wentylatory.'
    } else {
        Add-Finding 'Temperatury (ACPI)' -Status ok -Value ('{0} °C' -f (Format-Num $max 1)) -Details ($d -join "`n")
    }
}

Register-Check -Id 'hw.printers' -Category 'hardware' -Title 'Drukarki' -Script {
    $pr = @(Get-Cim Win32_Printer)
    if ($pr.Count -eq 0) { return }
    $jobs = @(Get-Cim Win32_PrintJob)
    $rows = @()
    foreach ($p in $pr) {
        if ($p.Name -match 'OneNote|Microsoft Print to PDF|Microsoft XPS|Fax|Send To|Zapisz jako PDF|Adobe PDF') { continue }
        $rows += [pscustomobject]@{
            Nazwa = $p.Name; Domyślna = $(if ($p.Default) { 'tak' } else { '' }); Port = $p.PortName; Sterownik = $p.DriverName
            Offline = $(if ($p.WorkOffline) { 'TAK' } else { '' }); 'Zadania w kolejce' = @($jobs | Where-Object { $_.Name -like ($p.Name + ',*') }).Count
        }
    }
    if ($rows.Count -eq 0) { return }
    $offline = @($rows | Where-Object { $_.Offline -eq 'TAK' })
    $stuck = @($rows | Where-Object { $_.'Zadania w kolejce' -gt 0 })
    $spool = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    $d = @()
    if ($spool) { $d += "Usługa Bufor wydruku: $($spool.Status)" }
    if ($stuck.Count -gt 0) {
        Add-Finding 'Drukarki' -Status warn -Value ('{0}; zadania w kolejce: {1}' -f (Format-Count $rows.Count 'drukarka' 'drukarki' 'drukarek'), ($stuck.Nazwa -join ', ')) -Details ($d -join "`n") `
            -Advice 'Zablokowane zadania wydruku: zatrzymaj usługę Bufor wydruku, wyczyść C:\Windows\System32\spool\PRINTERS i uruchom usługę ponownie.'
    } elseif ($offline.Count -gt 0) {
        Add-Finding 'Drukarki' -Status info -Value ('{0}; offline: {1}' -f (Format-Count $rows.Count 'drukarka' 'drukarki' 'drukarek'), ($offline.Nazwa -join ', ')) -Details ($d -join "`n") `
            -Advice 'Drukarka jest w trybie offline - sprawdź zasilanie, kabel/sieć i opcję „Użyj drukarki w trybie offline”.'
    } else {
        Add-Finding 'Drukarki' -Status ok -Value ('Zainstalowane: {0}' -f $rows.Count) -Details ($d -join "`n")
    }
    Add-Table 'Drukarki' -Rows $rows
}
