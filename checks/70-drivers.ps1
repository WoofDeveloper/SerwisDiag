# Testy kategorii: Sterowniki i urządzenia

Register-Check -Id 'dr.problem' -Category 'drivers' -Title 'Urządzenia z błędami i brakujące sterowniki' -Script {
    $pnp = @(Get-SdPnp)
    if ($pnp.Count -eq 0) {
        Add-Finding 'Urządzenia z błędami' -Status error -Value 'Nie udało się odczytać listy urządzeń (WMI).'
        return
    }
    $bad = @($pnp | Where-Object { $_.ConfigManagerErrorCode -and [int]$_.ConfigManagerErrorCode -ne 0 })
    $disabled = @($bad | Where-Object { [int]$_.ConfigManagerErrorCode -eq 22 })
    $problem = @($bad | Where-Object { [int]$_.ConfigManagerErrorCode -notin @(22, 45, 47) })

    if ($problem.Count -eq 0) {
        Add-Finding 'Urządzenia z błędami' -Status ok -Value ('Wszystkie wykryte urządzenia działają poprawnie (sprawdzono: {0})' -f $pnp.Count)
    } else {
        $rows = @(); $missing = @(); $lines = @(); $worst = 'warn'; $anyMissing = $false
        foreach ($d in $problem) {
            $code = [int]$d.ConfigManagerErrorCode
            $hwid = ''
            if ($d.HardwareID) { $hwid = [string](@($d.HardwareID)[0]) } elseif ($d.PNPDeviceID) { $hwid = [string]$d.PNPDeviceID }
            $vendor = Get-SdVendorName $hwid
            $name = if ($d.Name) { [string]$d.Name } else { 'Nieznane urządzenie' }
            $text = Get-SdPnpErrorText $code
            $cls = if ($d.PNPClass) { [string]$d.PNPClass } else { '-' }
            $rows += [pscustomobject]@{ Urządzenie = $name; Klasa = $cls; Kod = $code; Opis = $text; Producent = $vendor; 'Identyfikator sprzętu' = $hwid }
            $lines += ('{0} [{1}] - kod {2}: {3}{4}' -f $name, $cls, $code, $text, $(if ($vendor) { " (producent: $vendor)" } else { '' }))
            if ($code -eq 28) {
                $anyMissing = $true
                $missing += [pscustomobject]@{ Urządzenie = $name; Klasa = $cls; Producent = $vendor; 'Identyfikator sprzętu' = $hwid; 'Katalog Microsoft' = (Get-SdCatalogUrl $hwid) }
            }
            if ($cls -in @('Display', 'Net', 'HDC', 'SCSIAdapter', 'DiskDrive')) { $worst = 'crit' }
        }
        Add-Table 'Urządzenia z błędami (Menedżer urządzeń)' -Rows $rows
        if ($missing.Count -gt 0) {
            Add-Table 'Brakujące sterowniki - identyfikatory sprzętu' -Rows $missing -Note 'Link „Katalog Microsoft” wyszukuje sterownik po identyfikatorze sprzętu (VEN_xxxx&DEV_xxxx) w Katalogu Microsoft Update.'
            $vs = Get-SdComputerSupportInfo
            $lines += ''
            $lines += ('Strona ze sterownikami producenta ({0}): {1}{2}' -f $vs.Vendor, $vs.Url, $(if ($vs.CopyText) { ' - wpisz tam ' + $vs.CopyLabel + ' komputera' } else { '' }))
        }
        $adv = 'Zainstaluj brakujące sterowniki: Narzędzia serwisowe > „Sterowniki z Windows Update”, a gdy ich tam nie ma - „Brakujące sterowniki (Katalog Microsoft)” lub „Strona sterowników producenta”.'
        if (-not $anyMissing) { $adv = 'Zaktualizuj lub zainstaluj ponownie sterownik urządzenia (Menedżer urządzeń); sprawdź, czy urządzenie jest sprawne i poprawnie podłączone.' }
        Add-Finding 'Urządzenia z błędami' -Status $worst -Value (Format-Count $problem.Count 'urządzenie z błędem' 'urządzenia z błędami' 'urządzeń z błędami') -Details ($lines -join "`n") -Advice $adv
    }
    if ($disabled.Count -gt 0) {
        Add-Finding 'Urządzenia wyłączone' -Status info -Value ((@($disabled | ForEach-Object { $_.Name }) | Select-Object -First 6) -join '; ') `
            -Details 'Urządzenia wyłączone ręcznie w Menedżerze urządzeń (kod 22).'
    }
}

Register-Check -Id 'dr.wu' -Category 'drivers' -Title 'Nowsze sterowniki w Windows Update' -NeedsInternet -Script {
    $r = Find-SdWuDrivers -TimeoutSec 120
    if ($r.TimedOut) {
        Add-Finding 'Sterowniki w Windows Update' -Status info -Value 'Wyszukiwanie przerwano po 120 s (wolne łącze lub usługa Windows Update nie odpowiada)'
        return
    }
    if ($r.Error) {
        Add-Finding 'Sterowniki w Windows Update' -Status info -Value ('Nie udało się wyszukać: ' + (Limit-Text $r.Error 120)) `
            -Advice 'Brak połączenia z Windows Update, zasady firmowe (WSUS) albo uszkodzone składniki Windows Update (Narzędzia serwisowe > Reset komponentów Windows Update).'
        return
    }
    $items = @($r.Items)
    if ($items.Count -eq 0) {
        Add-Finding 'Sterowniki w Windows Update' -Status ok -Value 'Brak nowszych sterowników dla urządzeń tego komputera'
        return
    }
    Add-Table 'Sterowniki dostępne w Windows Update' -Rows (ConvertTo-SdDriverRows $items)
    $size = 0.0
    foreach ($i in $items) { $size += [double]$i.SizeBytes }
    $fix = @($items | Where-Object { [int]$_.DeviceProblem -ne 0 })
    $val = '{0} do zainstalowania ({1})' -f (Format-Count $items.Count 'sterownik' 'sterowniki' 'sterowników'), (Format-Size $size 1)
    if ($fix.Count -gt 0) { $val += ('; w tym dla urządzeń z błędami: {0}' -f $fix.Count) }
    $adv = 'Zainstaluj je: Narzędzia serwisowe > „Sterowniki z Windows Update” (przed instalacją program tworzy punkt przywracania).'
    if (@($items | Where-Object { $_.Class -match '^Display' }).Count -gt 0) { $adv += ' Sterownik karty graficznej warto porównać z wersją ze strony NVIDIA / AMD / Intel - bywa tam nowszy.' }
    Add-Finding 'Sterowniki w Windows Update' -Status (Get-SdDriverUpdateStatus $items) -Value $val `
        -Details (($items | Select-Object -First 12 | ForEach-Object { $_.Title }) -join "`n") -Advice $adv
}

Register-Check -Id 'dr.signed' -Category 'drivers' -Title 'Sterowniki kluczowych urządzeń (wersje, daty, podpisy)' -Script {
    $drv = @(Get-Cim Win32_PnPSignedDriver -Timeout 90)
    if ($drv.Count -eq 0) { return }
    $keyClasses = @('DISPLAY', 'NET', 'MEDIA', 'HDC', 'SCSIADAPTER', 'BLUETOOTH', 'CAMERA', 'IMAGE', 'BIOMETRIC', 'FIRMWARE', 'SECURITYDEVICES')
    $now = Get-Date
    $rows = @(); $old = @(); $unsigned = @()
    foreach ($d in $drv) {
        $cls = ([string]$d.DeviceClass).ToUpper()
        $isMs = ([string]$d.DriverProviderName -match 'Microsoft') -or ([string]$d.Manufacturer -match 'Microsoft')
        $ageY = $null
        if ($d.DriverDate) { $ageY = ($now - [datetime]$d.DriverDate).TotalDays / 365.25 }
        if ($d.IsSigned -eq $false -and -not $isMs -and $d.DeviceName) {
            $unsigned += [pscustomobject]@{ Urządzenie = [string]$d.DeviceName; Klasa = $cls; Producent = [string]$d.DriverProviderName; Wersja = [string]$d.DriverVersion; Data = (Format-Dt $d.DriverDate -DateOnly); Plik = [string]$d.InfName }
        }
        if ($keyClasses -contains $cls -and $d.DeviceName -and ($isMs -eq $false -or $cls -eq 'DISPLAY')) {
            $rows += [pscustomobject]@{
                Urządzenie = [string]$d.DeviceName; Klasa = $cls; Producent = [string]$d.DriverProviderName; Wersja = [string]$d.DriverVersion
                Data = (Format-Dt $d.DriverDate -DateOnly); 'Wiek (lata)' = $(if ($null -ne $ageY) { Format-Num $ageY 1 } else { '-' }); Podpisany = $(if ($d.IsSigned) { 'tak' } else { 'nie' })
            }
            if ($null -ne $ageY -and -not $isMs) {
                $limit = switch ($cls) { 'DISPLAY' { 2.5 } 'NET' { 4 } 'BLUETOOTH' { 4 } 'MEDIA' { 6 } default { 99 } }
                if ($ageY -gt $limit) { $old += ('{0} ({1}, {2} lat)' -f $d.DeviceName, $cls, (Format-Num $ageY 0)) }
            }
        }
    }
    if ($rows.Count -gt 0) { Add-Table 'Sterowniki kluczowych urządzeń' -Rows @($rows | Sort-Object Klasa, Urządzenie) }
    if ($unsigned.Count -gt 0) {
        Add-Table 'Sterowniki bez podpisu cyfrowego' -Rows $unsigned
        Add-Finding 'Sterowniki bez podpisu cyfrowego' -Status info -Value (Format-Count $unsigned.Count 'sterownik' 'sterowniki' 'sterowników') `
            -Details (($unsigned | Select-Object -First 8 | ForEach-Object { '{0} ({1})' -f $_.Urządzenie, $_.Producent }) -join "`n") `
            -Advice 'Niepodpisane sterowniki mogą być blokowane przez Windows 11 (Izolacja rdzenia / Secure Boot) i obniżają stabilność. Poszukaj podpisanych wersji u producenta.'
    } else {
        Add-Finding 'Podpisy sterowników' -Status ok -Value 'Wszystkie sterowniki spoza Microsoft są podpisane cyfrowo'
    }
    if ($old.Count -gt 0) {
        Add-Finding 'Wiek sterowników' -Status info -Value (Format-Count $old.Count 'stary sterownik' 'stare sterowniki' 'starych sterowników') -Details ($old -join "`n") `
            -Advice 'Sprawdź u producenta, czy dostępne są nowsze wersje (szczególnie sterownik grafiki, sieci i Bluetooth). Nie instaluj sterowników z automatycznych „aktualizatorów”.'
    } elseif ($rows.Count -gt 0) {
        Add-Finding 'Wiek sterowników' -Status ok -Value 'Sterowniki kluczowych urządzeń nie są przestarzałe'
    }
}

Register-Check -Id 'dr.devices' -Category 'drivers' -Title 'Lista urządzeń (Menedżer urządzeń)' -Level Full -Script {
    $pnp = @(Get-SdPnp)
    if ($pnp.Count -eq 0) { return }
    $rows = @($pnp | Where-Object { $_.Name } | Sort-Object PNPClass, Name | ForEach-Object {
            [pscustomobject]@{ Urządzenie = [string]$_.Name; Klasa = [string]$_.PNPClass; Producent = [string]$_.Manufacturer; Usługa = [string]$_.Service; Stan = $(if ($_.ConfigManagerErrorCode) { 'błąd ' + $_.ConfigManagerErrorCode } else { 'OK' }) }
        })
    Add-Table 'Urządzenia (Menedżer urządzeń)' -Rows $rows
}
