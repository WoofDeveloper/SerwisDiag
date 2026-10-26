# Testy kategorii: Zasilanie i bateria

function Get-SdBatteryReport {
    # powercfg /batteryreport /xml (Windows 10 1607+); na starszych systemach zwraca pustą tablicę.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('sd-batt-' + [guid]::NewGuid().ToString('N') + '.xml')
    $out = @()
    try {
        $exe = Join-Path $env:SystemRoot 'System32\powercfg.exe'
        [void](Invoke-Native -File $exe -Arguments ('/batteryreport /xml /output "{0}"' -f $tmp) -TimeoutSec 30)
        if (Test-Path -LiteralPath $tmp) {
            $xml = New-Object System.Xml.XmlDocument
            $xml.Load($tmp)
            $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
            $ns.AddNamespace('b', 'http://schemas.microsoft.com/battery/2012')
            foreach ($n in $xml.SelectNodes('//b:Batteries/b:Battery', $ns)) {
                $get = { param($name) $x = $n.SelectSingleNode('b:' + $name, $ns); if ($x) { $x.InnerText } else { '' } }
                $design = 0; $full = 0; $cycles = 0
                [void][int]::TryParse((& $get 'DesignCapacity'), [ref]$design)
                [void][int]::TryParse((& $get 'FullChargeCapacity'), [ref]$full)
                [void][int]::TryParse((& $get 'CycleCount'), [ref]$cycles)
                $out += [pscustomobject]@{
                    Id = (& $get 'Id'); Manufacturer = (& $get 'Manufacturer'); Chemistry = (& $get 'Chemistry')
                    DesignCapacity = $design; FullChargeCapacity = $full; CycleCount = $cycles
                }
            }
        }
    } catch { Write-SdLog ('Raport baterii: ' + $_.Exception.Message) 'WARN' }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    return $out
}

function Select-SdBatteryData {
    # Dane baterii z root\wmi (BatteryStaticData, BatteryFullChargedCapacity, ...) dla konkretnej baterii z Win32_Battery.
    # Kolejność instancji w poszczególnych klasach bywa różna, więc dopasowujemy po InstanceName ("ACPI\PNP0C0A\1_0")
    # = PNPDeviceID baterii + "_0", następnie po nazwie (BatteryStaticData.DeviceName = Win32_Battery.Name).
    # Przy jednej baterii i jednym wpisie bierzemy jedyny wpis.
    param($Battery, $Items, $Static = $null, [int]$BatteryCount = 1)
    $list = @($Items | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { return $null }
    $pnp = ([string]$Battery.PNPDeviceID).ToUpper()
    if ($pnp) {
        foreach ($x in $list) { if ((([string]$x.InstanceName) -replace '_\d+$', '').ToUpper() -eq $pnp) { return $x } }
    }
    $nm = [string]$Battery.Name
    if ($nm) {
        foreach ($s in @($Static | Where-Object { $null -ne $_ })) {
            if (([string]$s.DeviceName).Trim() -eq $nm.Trim()) {
                foreach ($x in $list) { if ([string]$x.InstanceName -eq [string]$s.InstanceName) { return $x } }
            }
        }
    }
    if ($BatteryCount -eq 1 -and $list.Count -eq 1) { return $list[0] }
    return $null
}

Register-Check -Id 'pw.battery' -Category 'power' -Title 'Bateria' -Script {
    $isLaptop = Test-SdLaptop
    $isVm = Test-SdVm
    $bats = @(Get-Cim Win32_Battery)
    if ($bats.Count -eq 0) {
        if ($isLaptop -and -not $isVm) {
            Add-Finding 'Bateria' -Status warn -Value 'Nie wykryto baterii w laptopie' `
                -Details 'System nie widzi baterii: może być odłączona, całkowicie zużyta/uszkodzona lub mieć problem ze sterownikiem ACPI.' `
                -Advice 'Sprawdź połączenie baterii, uruchom laptop bez baterii z samym zasilaczem (jeśli to możliwe) i sprawdź w Menedżerze urządzeń „Bateria z metodą sterowania zgodna z ACPI”.'
        } else {
            Add-Finding 'Bateria' -Status skip -Value 'Nie dotyczy (komputer bez baterii)'
        }
        return
    }

    $full = @(Get-Cim -Namespace 'root\wmi' -Class BatteryFullChargedCapacity)
    $stat = @(Get-Cim -Namespace 'root\wmi' -Class BatteryStaticData)
    $cyc = @(Get-Cim -Namespace 'root\wmi' -Class BatteryCycleCount)
    $live = @(Get-Cim -Namespace 'root\wmi' -Class BatteryStatus)
    $report = @()
    $needReport = ($stat.Count -eq 0 -or -not $stat[0].DesignedCapacity)
    if ($needReport) { $report = @(Get-SdBatteryReport) }

    $idx = 0
    foreach ($b in $bats) {
        $n = $bats.Count
        $st = Select-SdBatteryData -Battery $b -Items $stat -Static $stat -BatteryCount $n
        $fc = Select-SdBatteryData -Battery $b -Items $full -Static $stat -BatteryCount $n
        $cy = Select-SdBatteryData -Battery $b -Items $cyc -Static $stat -BatteryCount $n
        $lv = Select-SdBatteryData -Battery $b -Items $live -Static $stat -BatteryCount $n
        # raport powercfg: Id baterii = jej nazwa urządzenia
        $rep = @($report | Where-Object { $b.Name -and ([string]$_.Id).Trim() -eq ([string]$b.Name).Trim() }) | Select-Object -First 1
        if (-not $rep -and $n -eq 1 -and $report.Count -eq 1) { $rep = $report[0] }

        $design = 0.0; $fullCap = 0.0; $cycles = $null
        if ($st -and $st.DesignedCapacity) { $design = [double]$st.DesignedCapacity }
        elseif ($rep -and $rep.DesignCapacity) { $design = [double]$rep.DesignCapacity }
        if ($fc -and $fc.FullChargedCapacity) { $fullCap = [double]$fc.FullChargedCapacity }
        elseif ($rep -and $rep.FullChargeCapacity) { $fullCap = [double]$rep.FullChargeCapacity }
        if ($cy -and $null -ne $cy.CycleCount) { $cycles = [int]$cy.CycleCount }
        elseif ($rep) { $cycles = [int]$rep.CycleCount }
        $chem = ''
        if ($rep) { $chem = $rep.Chemistry }
        $mfr = ''
        if ($st -and $st.ManufactureName) { $mfr = [string]$st.ManufactureName } elseif ($rep) { $mfr = $rep.Manufacturer }
        $name = if ($b.Name) { [string]$b.Name } else { "Bateria $($idx + 1)" }

        $d = @("Model: $name")
        if ($mfr) { $d += "Producent: $mfr" }
        if ($chem) { $d += "Technologia: $chem" }
        $rows = @([pscustomobject]@{ Parametr = 'Model'; Wartość = $name })
        $health = $null
        if ($design -gt 0 -and $fullCap -gt 0) {
            $health = 100.0 * $fullCap / $design
            $d += ('Pojemność fabryczna: {0} mWh' -f (Format-Num $design 0))
            $d += ('Pojemność przy pełnym naładowaniu: {0} mWh' -f (Format-Num $fullCap 0))
            $rows += [pscustomobject]@{ Parametr = 'Pojemność fabryczna'; Wartość = ('{0} mWh' -f (Format-Num $design 0)) }
            $rows += [pscustomobject]@{ Parametr = 'Pojemność aktualna (pełne naładowanie)'; Wartość = ('{0} mWh' -f (Format-Num $fullCap 0)) }
            $rows += [pscustomobject]@{ Parametr = 'Kondycja baterii'; Wartość = ('{0}%' -f (Format-Num $health 1)) }
        }
        if ($null -ne $cycles -and $cycles -gt 0) { $d += "Liczba cykli ładowania: $cycles"; $rows += [pscustomobject]@{ Parametr = 'Cykle ładowania'; Wartość = $cycles } }
        $charge = [int]$b.EstimatedChargeRemaining
        $stateTxt = ''
        if ($lv) {
            if ($lv.Charging) { $stateTxt = 'ładuje się' } elseif ($lv.Discharging) { $stateTxt = 'rozładowuje się' } elseif ($lv.PowerOnline) { $stateTxt = 'zasilanie sieciowe' }
        }
        if (-not $stateTxt) {
            switch ([int]$b.BatteryStatus) { 1 { $stateTxt = 'rozładowuje się' } 2 { $stateTxt = 'zasilanie sieciowe' } 3 { $stateTxt = 'naładowana' } 6 { $stateTxt = 'ładuje się' } }
        }
        $d += "Poziom naładowania: $charge% ($stateTxt)"
        $rows += [pscustomobject]@{ Parametr = 'Poziom naładowania'; Wartość = "$charge% ($stateTxt)" }
        if ($b.EstimatedRunTime -and [double]$b.EstimatedRunTime -lt 1000000 -and $lv -and $lv.Discharging) {
            $d += ('Szacowany czas pracy: {0}' -f (Format-Span ([timespan]::FromMinutes([double]$b.EstimatedRunTime))))
        }
        if ($lv -and $lv.Voltage) { $d += ('Napięcie: {0} V' -f (Format-Num ([double]$lv.Voltage / 1000) 2)) }

        $status = 'ok'; $advice = ''
        $valParts = @()
        if ($null -ne $health) {
            if ($health -gt 130) {
                $status = 'info'; $valParts += 'Dane o pojemności niewiarygodne (producent podaje nietypowe wartości)'
            } else {
                $h = [math]::Min($health, 100.0)
                $valParts += ('kondycja {0}% (pojemność {1} z {2} mWh)' -f (Format-Num $h 0), (Format-Num $fullCap 0), (Format-Num $design 0))
                if ($h -lt 50) { $status = 'crit'; $advice = 'Bateria jest mocno zużyta - czas pracy będzie bardzo krótki, a przy dalszym spadku pojemności mogą wystąpić nagłe wyłączenia. Zalecana wymiana baterii.' }
                elseif ($h -lt 65) { $status = 'warn'; $advice = 'Bateria jest wyraźnie zużyta (poniżej 65% pojemności). Rozważ wymianę, jeśli czas pracy na baterii jest dla użytkownika zbyt krótki.' }
                elseif ($h -lt 80) { $status = 'info' }
            }
        } else {
            $valParts += 'brak danych o pojemności fabrycznej'
            $status = 'info'
        }
        if ($null -ne $cycles -and $cycles -gt 0) { $valParts += (Format-Count $cycles 'cykl' 'cykle' 'cykli') }
        $valParts += "$charge% ($stateTxt)"
        if ($b.Status -and $b.Status -ne 'OK') {
            $status = Get-SdWorstStatus @($status, 'warn')
            $valParts += "stan: $($b.Status)"
            if (-not $advice) { $advice = 'System zgłasza nieprawidłowy stan baterii - sprawdź baterię i sterownik ACPI.' }
        }
        if ($lv -and $lv.Critical) { $status = 'crit'; $valParts += 'krytycznie niski poziom' }

        Add-Finding ('Bateria' + $(if ($bats.Count -gt 1) { " $($idx + 1)" } else { '' })) -Status $status -Value ($valParts -join '; ') -Details ($d -join "`n") -Advice $advice
        Add-Table ('Bateria' + $(if ($bats.Count -gt 1) { " $($idx + 1)" } else { '' })) -Rows $rows
        if ($health -ne $null -and $health -le 130) { Set-SdMeta 'BatteryHealth' ([math]::Round([math]::Min($health, 100), 0)) }
        $idx++
    }
}

Register-Check -Id 'pw.plan' -Category 'power' -Title 'Plan zasilania' -Script {
    $exe = Join-Path $env:SystemRoot 'System32\powercfg.exe'
    $r = Invoke-Native -File $exe -Arguments '/getactivescheme' -TimeoutSec 15
    if ($r.ExitCode -ne 0 -or $r.StdOut -notmatch '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return }
    $guid = $Matches[1].ToLower()
    $friendly = ''
    if ($r.StdOut -match '\(([^)]+)\)\s*$') { $friendly = $Matches[1] } elseif ($r.StdOut -match '\(([^)]+)\)') { $friendly = $Matches[1] }
    $known = @{
        '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Zrównoważony'
        '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'Wysoka wydajność'
        'a1841308-3541-4fab-bc81-f71556f20b4a' = 'Oszczędzanie energii'
        'e9a42b02-d5df-448d-aa00-03f14749eb61' = 'Najwyższa wydajność'
    }
    $name = if ($known.ContainsKey($guid)) { $known[$guid] } elseif ($friendly) { $friendly } else { $guid }
    if ($guid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a') {
        Add-Finding 'Plan zasilania' -Status info -Value $name `
            -Details 'Plan „Oszczędzanie energii” ogranicza taktowanie procesora i jasność ekranu.' `
            -Advice 'Jeśli komputer wydaje się wolny, zmień plan na „Zrównoważony” lub „Wysoka wydajność” (zwłaszcza przy zasilaniu sieciowym).'
    } else {
        Add-Finding 'Plan zasilania' -Status ok -Value $name
    }
}
