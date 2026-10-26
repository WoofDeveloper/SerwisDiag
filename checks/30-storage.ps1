# Testy kategorii: Dyski

$global:SdSmartNames = @{
    1 = 'Raw Read Error Rate'; 2 = 'Throughput Performance'; 3 = 'Spin-Up Time'; 4 = 'Start/Stop Count'; 5 = 'Reallocated Sectors Count'
    7 = 'Seek Error Rate'; 8 = 'Seek Time Performance'; 9 = 'Power-On Hours'; 10 = 'Spin Retry Count'; 11 = 'Calibration Retry Count'
    12 = 'Power Cycle Count'; 13 = 'Soft Read Error Rate'; 168 = 'SATA PHY Error Count'; 169 = 'Remaining Life / Bad Block Count'
    170 = 'Available Reserved Space'; 171 = 'Program Fail Count'; 172 = 'Erase Fail Count'; 173 = 'Wear Leveling Count'
    174 = 'Unexpected Power Loss Count'; 175 = 'Program Fail Count (Chip)'; 176 = 'Erase Fail Count (Chip)'; 177 = 'Wear Leveling Count'
    178 = 'Used Reserved Block Count (Chip)'; 179 = 'Used Reserved Block Count (Total)'; 180 = 'Unused Reserved Block Count'
    181 = 'Program Fail Count (Total)'; 182 = 'Erase Fail Count'; 183 = 'Runtime Bad Block / SATA Downshift'; 184 = 'End-to-End Error'
    187 = 'Reported Uncorrectable Errors'; 188 = 'Command Timeout'; 189 = 'High Fly Writes'; 190 = 'Airflow Temperature'
    191 = 'G-Sense Error Rate'; 192 = 'Unsafe Shutdown Count'; 193 = 'Load/Unload Cycle Count'; 194 = 'Temperature'
    195 = 'Hardware ECC Recovered'; 196 = 'Reallocation Event Count'; 197 = 'Current Pending Sector Count'
    198 = 'Offline Uncorrectable Sector Count'; 199 = 'UDMA CRC Error Count'; 200 = 'Write Error Rate'; 201 = 'Soft Read Error Rate'
    202 = 'Percent Lifetime Used'; 206 = 'Flying Height'; 209 = 'Remaining Life'; 220 = 'Disk Shift'; 222 = 'Loaded Hours'
    223 = 'Load/Unload Retry Count'; 224 = 'Load Friction'; 226 = 'Load-in Time'; 230 = 'Drive Life Protection Status'
    231 = 'SSD Life Left'; 232 = 'Available Reserved Space'; 233 = 'Media Wearout Indicator'; 234 = 'Vendor Specific'
    235 = 'Vendor Specific'; 240 = 'Head Flying Hours'; 241 = 'Total LBAs Written'; 242 = 'Total LBAs Read'; 250 = 'Read Error Retry Rate'
}

function Get-SdStatusRank {
    param([string]$Status)
    if ($global:SdStatusInfo.ContainsKey($Status)) { return $global:SdStatusInfo[$Status].Rank }
    return 0
}

function Get-SdWorstStatus {
    param([string[]]$Statuses)
    $best = 'ok'; $rank = -1
    foreach ($s in $Statuses) { $r = Get-SdStatusRank $s; if ($r -gt $rank) { $rank = $r; $best = $s } }
    return $best
}

# ---------------------------------------------------------------- SMART ATA (HDD / SSD SATA) przez WMI

function ConvertFrom-SdSmartData {
    # Tablica 512 bajtów: 2 bajty rewizji + do 30 wpisów po 12 bajtów (id, flagi[2], wartość, najgorsza, surowa[6], zarezerwowany).
    param([byte[]]$Data, [byte[]]$Thresholds)
    $thr = @{}
    if ($Thresholds -and $Thresholds.Length -ge 14) {
        for ($i = 2; $i -le ($Thresholds.Length - 12) -and $i -lt 362; $i += 12) {
            $id = [int]$Thresholds[$i]
            if ($id -ne 0) { $thr[$id] = [int]$Thresholds[$i + 1] }
        }
    }
    $list = @()
    if ($Data -and $Data.Length -ge 14) {
        for ($i = 2; $i -le ($Data.Length - 12) -and $i -lt 362; $i += 12) {
            $id = [int]$Data[$i]
            if ($id -eq 0) { continue }
            $raw = [int64]0
            for ($b = 5; $b -ge 0; $b--) { $raw = ($raw * 256) + [int64]$Data[$i + 5 + $b] }
            $name = if ($global:SdSmartNames.ContainsKey($id)) { $global:SdSmartNames[$id] } else { 'Vendor Specific' }
            $list += [pscustomobject]@{
                Id = $id; Name = $name; Current = [int]$Data[$i + 3]; Worst = [int]$Data[$i + 4]
                Threshold = $(if ($thr.ContainsKey($id)) { $thr[$id] } else { 0 }); Raw = $raw
            }
        }
    }
    return $list
}

function Get-SdAtaSmart {
    # Zwraca słownik: klucz = PNPDeviceID dużymi literami (bez sufiksu _0).
    $res = @{}
    if (-not $global:SD.IsAdmin) { return $res }
    $st = @(Get-Cim -Namespace 'root\wmi' -Class MSStorageDriver_FailurePredictStatus)
    if ($st.Count -eq 0) { return $res }
    $dt = @(Get-Cim -Namespace 'root\wmi' -Class MSStorageDriver_FailurePredictData)
    $th = @(Get-Cim -Namespace 'root\wmi' -Class MSStorageDriver_FailurePredictThresholds)
    foreach ($s in $st) {
        $d = $dt | Where-Object { $_.InstanceName -eq $s.InstanceName } | Select-Object -First 1
        $t = $th | Where-Object { $_.InstanceName -eq $s.InstanceName } | Select-Object -First 1
        $thrBytes = $null
        if ($t) { $thrBytes = [byte[]]$t.VendorSpecific }
        $attrs = @()
        if ($d) { $attrs = ConvertFrom-SdSmartData -Data ([byte[]]$d.VendorSpecific) -Thresholds $thrBytes }
        $key = (([string]$s.InstanceName) -replace '_\d+$', '').ToUpper()
        $res[$key] = [pscustomobject]@{ PredictFailure = [bool]$s.PredictFailure; Reason = $s.Reason; Attributes = $attrs }
    }
    return $res
}

function Get-SdAtaVerdict {
    param($Smart, [bool]$IsSsd)
    $a = @{}
    foreach ($x in $Smart.Attributes) { $a[[int]$x.Id] = $x }
    # 0xFFFFFFFFL (long) - bez sufiksu L literał byłby w PowerShell liczbą ujemną (-1) i maska nie działałaby
    $raw32 = { param($id) if ($a.ContainsKey($id)) { return [int64]($a[$id].Raw -band 0xFFFFFFFFL) } else { return $null } }
    $issues = @()

    if ($Smart.PredictFailure) { $issues += [pscustomobject]@{ Status = 'crit'; Text = 'SMART zgłasza przewidywaną awarię dysku' } }
    $re = & $raw32 5
    $pe = & $raw32 197
    $un = & $raw32 198
    $ru = & $raw32 187
    $crc = & $raw32 199
    $cto = & $raw32 188
    if ($null -ne $re -and $re -gt 0) {
        $issues += [pscustomobject]@{ Status = $(if ($re -ge 100) { 'crit' } else { 'warn' }); Text = "Przeniesione (reallocated) sektory: $re" }
    }
    if ($null -ne $pe -and $pe -gt 0) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Sektory oczekujące na przeniesienie (pending): $pe" } }
    if ($null -ne $un -and $un -gt 0) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Niemożliwe do odczytania sektory (uncorrectable): $un" } }
    if ($null -ne $ru -and $ru -gt 0) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Zgłoszone nieskorygowane błędy odczytu: $ru" } }
    if ($null -ne $crc -and $crc -gt 0) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Błędy transmisji UDMA CRC: $crc (sprawdź kabel SATA / złącza)" } }
    if ($null -ne $cto -and $cto -gt 20) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Przekroczenia czasu poleceń: $cto" } }
    foreach ($x in $Smart.Attributes) {
        if ($x.Threshold -gt 0 -and $x.Current -le $x.Threshold -and @(5, 10, 184, 187, 196, 197, 198, 231, 233) -contains $x.Id) {
            $issues += [pscustomobject]@{ Status = 'crit'; Text = "Atrybut $($x.Id) ($($x.Name)) osiągnął próg SMART" }
        }
    }

    $temp = $null
    foreach ($id in 194, 190) { if (-not $temp -and $a.ContainsKey($id)) { $t = [int]($a[$id].Raw -band 0xFF); if ($t -gt 0 -and $t -lt 120) { $temp = $t } } }
    $hours = & $raw32 9
    $life = $null
    foreach ($id in 231, 233, 169, 173, 177) {
        if ($null -eq $life -and $a.ContainsKey($id) -and $IsSsd) { $v = $a[$id].Current; if ($v -gt 0 -and $v -le 100) { $life = $v } }
    }
    if ($null -eq $life -and $a.ContainsKey(202) -and $IsSsd) { $u = [int]($a[202].Raw -band 0xFF); if ($u -le 100) { $life = 100 - $u } }
    if ($null -ne $life) {
        if ($life -le 10) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Szacowany pozostały czas życia SSD: $life%" } }
        elseif ($life -le 30) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Szacowany pozostały czas życia SSD: $life%" } }
    }
    if ($null -ne $temp) {
        $tw = if ($IsSsd) { 70 } else { 55 }; $tc = if ($IsSsd) { 80 } else { 60 }
        if ($temp -ge $tc) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Temperatura dysku: $temp °C" } }
        elseif ($temp -ge $tw) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Temperatura dysku: $temp °C" } }
    }
    if (-not $IsSsd -and $null -ne $hours) {
        if ($hours -ge 40000) { $issues += [pscustomobject]@{ Status = 'warn'; Text = ("Dysk pracował {0} godzin (ponad {1} lat) - zwiększone ryzyko awarii" -f (Format-Num $hours 0), [math]::Floor($hours / 8760)) } }
    }
    return [pscustomobject]@{
        Issues = $issues; Temp = $temp; Hours = $hours; LifeLeft = $life
        Reallocated = $re; Pending = $pe; Uncorrectable = $un
    }
}

# ---------------------------------------------------------------- NVMe (dziennik zdrowia)

function Get-SdNvmeHealth {
    param([int]$DiskNumber)
    if (-not (Initialize-SdNative)) { return $null }
    $err = 0
    $log = $null
    try { $log = [SdNative]::NvmeHealthLog($DiskNumber, [ref]$err) } catch { Write-SdLog ('NVMe: ' + $_.Exception.Message) 'WARN' }
    if (-not $log) { Write-SdLog ("NVMe dysk {0}: brak dziennika zdrowia (Win32 {1})" -f $DiskNumber, $err) 'INFO'; return $null }
    return (ConvertFrom-SdNvmeLog $log)
}

function ConvertFrom-SdNvmeLog {
    # Dziennik SMART / Health Information NVMe (Log Page 02h, 512 bajtów) -> obiekt z polami opisowymi.
    param([byte[]]$log)
    $k = [BitConverter]::ToUInt16($log, 1)
    $temp = $null
    if ($k -gt 273) { $temp = [int]$k - 273 }
    return [pscustomobject]@{
        CriticalWarning = [int]$log[0]
        Temperature     = $temp
        AvailableSpare  = [int]$log[3]
        SpareThreshold  = [int]$log[4]
        PercentUsed     = [int]$log[5]
        BytesRead       = [double][BitConverter]::ToUInt64($log, 32) * 512000
        BytesWritten    = [double][BitConverter]::ToUInt64($log, 48) * 512000
        PowerCycles     = [int64][BitConverter]::ToUInt64($log, 112)
        PowerOnHours    = [int64][BitConverter]::ToUInt64($log, 128)
        UnsafeShutdowns = [int64][BitConverter]::ToUInt64($log, 144)
        MediaErrors     = [int64][BitConverter]::ToUInt64($log, 160)
        ErrorLogEntries = [int64][BitConverter]::ToUInt64($log, 176)
        WarnTempMinutes = [int64][BitConverter]::ToUInt32($log, 192)
        CritTempMinutes = [int64][BitConverter]::ToUInt32($log, 196)
    }
}

function Get-SdNvmeVerdict {
    param($H)
    $issues = @()
    if ($H.CriticalWarning -ne 0) {
        $w = @()
        if ($H.CriticalWarning -band 1) { $w += 'zapas bloków poniżej progu' }
        if ($H.CriticalWarning -band 2) { $w += 'temperatura poza zakresem' }
        if ($H.CriticalWarning -band 4) { $w += 'niezawodność pogorszona' }
        if ($H.CriticalWarning -band 8) { $w += 'dysk w trybie tylko do odczytu' }
        if ($H.CriticalWarning -band 16) { $w += 'awaria pamięci podręcznej' }
        $issues += [pscustomobject]@{ Status = 'crit'; Text = 'Ostrzeżenie krytyczne dysku NVMe: ' + ($w -join ', ') }
    }
    if ($H.AvailableSpare -le $H.SpareThreshold -and $H.CriticalWarning -eq 0) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Zapas zapasowych bloków ($($H.AvailableSpare)%) osiągnął próg" } }
    elseif ($H.AvailableSpare -lt 50) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Mały zapas zapasowych bloków: $($H.AvailableSpare)%" } }
    if ($H.PercentUsed -ge 90) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Zużycie SSD: $($H.PercentUsed)% deklarowanej wytrzymałości" } }
    elseif ($H.PercentUsed -ge 70) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Zużycie SSD: $($H.PercentUsed)% deklarowanej wytrzymałości" } }
    if ($H.MediaErrors -ge 10) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Błędy nośnika i integralności danych: $($H.MediaErrors)" } }
    elseif ($H.MediaErrors -gt 0) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Błędy nośnika i integralności danych: $($H.MediaErrors)" } }
    if ($null -ne $H.Temperature) {
        if ($H.Temperature -ge 80) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Temperatura dysku: $($H.Temperature) °C" } }
        elseif ($H.Temperature -ge 70) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Temperatura dysku: $($H.Temperature) °C" } }
    }
    if ($H.CritTempMinutes -gt 0) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Dysk spędził $($H.CritTempMinutes) min w temperaturze krytycznej (przegrzewanie)" } }
    return $issues
}

# ---------------------------------------------------------------- inwentarz dysków

function Get-SdDiskTypeName {
    param($Disk)
    if ($Disk.Bus -eq 'NVMe' -or $Disk.Pnp -match 'NVME') { return 'NVMe SSD' }
    $pre = ''
    if ($Disk.Bus -eq 'USB' -or $Disk.Iface -eq 'USB') { $pre = 'USB ' }
    if ($Disk.Media -eq 'SSD') { return ($pre + 'SSD') }
    if ($Disk.Media -eq 'HDD') { return ($pre + 'HDD') }
    if ($Disk.Model -match 'SSD|Solid State|NVMe') { return ($pre + 'SSD') }
    if ($Disk.Model -match 'Virtual|VMware|VBOX|QEMU') { return 'Dysk wirtualny' }
    return ($pre + 'dysk')
}

function Get-SdDiskInventory {
    Get-SdCached 'Disks' {
        $drives = @(Get-Cim Win32_DiskDrive)
        $pds = @(); $gds = @()
        if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) { try { $pds = @(Get-PhysicalDisk -ErrorAction Stop) } catch { Write-SdLog ('Get-PhysicalDisk: ' + $_.Exception.Message) 'WARN' } }
        if (Get-Command Get-Disk -ErrorAction SilentlyContinue) { try { $gds = @(Get-Disk -ErrorAction Stop) } catch { Write-SdLog ('Get-Disk: ' + $_.Exception.Message) 'WARN' } }
        $out = @()
        foreach ($d in $drives) {
            $pd = $pds | Where-Object { [string]$_.DeviceId -eq [string]$d.Index } | Select-Object -First 1
            $gd = $gds | Where-Object { [int]$_.Number -eq [int]$d.Index } | Select-Object -First 1
            $out += [pscustomobject]@{
                Index = [int]$d.Index; Model = (([string]$d.Model) -replace '\s+', ' ').Trim(); Serial = (([string]$d.SerialNumber).Trim())
                Size = [double]$d.Size; Iface = [string]$d.InterfaceType; Firmware = [string]$d.FirmwareRevision; Pnp = [string]$d.PNPDeviceID
                WmiStatus = [string]$d.Status; Partitions = [int]$d.Partitions
                Bus = $(if ($pd) { [string]$pd.BusType } else { '' }); Media = $(if ($pd) { [string]$pd.MediaType } else { '' })
                Health = $(if ($pd) { [string]$pd.HealthStatus } else { '' }); Operational = $(if ($pd) { (@($pd.OperationalStatus) -join ',') } else { '' })
                Spindle = $(if ($pd) { $pd.SpindleSpeed } else { $null })
                PartStyle = $(if ($gd) { [string]$gd.PartitionStyle } else { '' }); IsSystem = $(if ($gd) { [bool]$gd.IsSystem } else { $false })
                PD = $pd
            }
        }
        $out
    }
}

Register-Check -Id 'st.disks' -Category 'storage' -Title 'Dyski fizyczne i stan zdrowia (SMART)' -Script {
    $disks = @(Get-SdDiskInventory)
    if ($disks.Count -eq 0) {
        Add-Finding 'Dyski fizyczne' -Status error -Value 'Nie wykryto żadnego dysku (WMI).' `
            -Advice 'Jeśli system działa, sprawdź w BIOS/UEFI, czy dysk jest widoczny, oraz tryb kontrolera (AHCI/RAID).'
        return
    }
    $ata = Get-SdAtaSmart
    $isVm = Test-SdVm
    $tableRows = @()
    $metaParts = @()
    $serialLines = @()

    foreach ($d in $disks) {
        $typ = Get-SdDiskTypeName $d
        $isSsd = ($typ -match 'SSD')
        $sizeTxt = Format-Size $d.Size 0
        $metaParts += ('{0} {1}' -f $typ, $sizeTxt)
        $issues = @()
        $lines = @(
            "Model: $($d.Model)"
            "Typ: $typ; interfejs: $(Join-NonEmpty @($d.Bus, $d.Iface) ' / ')"
            "Pojemność: $sizeTxt; partycji: $($d.Partitions); styl: $(if ($d.PartStyle) { $d.PartStyle } else { '-' })"
            "Firmware: $(if ($d.Firmware) { $d.Firmware } else { '-' })"
        )
        if ($d.Serial) { $serialLines += ('Dysk {0} ({1}): {2}' -f $d.Index, $d.Model, $d.Serial) }

        # 1) stan wg systemu (Storage / WMI)
        if ($d.Health -eq 'Unhealthy') { $issues += [pscustomobject]@{ Status = 'crit'; Text = 'System Windows ocenia dysk jako niesprawny (Unhealthy)' } }
        elseif ($d.Health -eq 'Warning') { $issues += [pscustomobject]@{ Status = 'warn'; Text = 'System Windows zgłasza ostrzeżenie dla dysku (Warning)' } }
        if ($d.Operational -match 'Predictive|Lost Communication|IO Error|Failed|Stopping|Not Ready') {
            $issues += [pscustomobject]@{ Status = 'crit'; Text = "Stan operacyjny: $($d.Operational)" }
        }
        if ($d.WmiStatus -eq 'Pred Fail') { $issues += [pscustomobject]@{ Status = 'crit'; Text = 'Dysk przewiduje awarię (Pred Fail)' } }

        $detailRows = $null
        $smartTable = $null
        $tempTxt = ''; $hoursTxt = ''; $wearTxt = ''
        $hadDeepData = $false

        # 2) NVMe
        if ($typ -eq 'NVMe SSD') {
            $h = Get-SdNvmeHealth $d.Index
            if ($h) {
                $hadDeepData = $true
                $issues += @(Get-SdNvmeVerdict $h)
                $tbw = $h.BytesWritten / 1e12
                $lines += "NVMe: zużycie $($h.PercentUsed)%, zapas bloków $($h.AvailableSpare)% (próg $($h.SpareThreshold)%)"
                $lines += ("Zapisano łącznie: {0} TB; odczytano: {1} TB" -f (Format-Num $tbw 1), (Format-Num ($h.BytesRead / 1e12) 1))
                $lines += "Godziny pracy: $(Format-Num $h.PowerOnHours 0); cykle zasilania: $(Format-Num $h.PowerCycles 0); nieczyste wyłączenia: $(Format-Num $h.UnsafeShutdowns 0)"
                $lines += "Błędy nośnika: $($h.MediaErrors); wpisy w dzienniku błędów: $($h.ErrorLogEntries)"
                if ($null -ne $h.Temperature) { $tempTxt = "$($h.Temperature) °C" }
                $hoursTxt = Format-Num $h.PowerOnHours 0
                $wearTxt = "zużycie $($h.PercentUsed)%, zapisano $(Format-Num $tbw 1) TB"
                $detailRows = @(
                    [pscustomobject]@{ Parametr = 'Ostrzeżenie krytyczne'; Wartość = $h.CriticalWarning }
                    [pscustomobject]@{ Parametr = 'Temperatura złożona'; Wartość = $(if ($null -ne $h.Temperature) { "$($h.Temperature) °C" } else { '-' }) }
                    [pscustomobject]@{ Parametr = 'Zapas zapasowych bloków'; Wartość = "$($h.AvailableSpare)% (próg $($h.SpareThreshold)%)" }
                    [pscustomobject]@{ Parametr = 'Zużycie (Percentage Used)'; Wartość = "$($h.PercentUsed)%" }
                    [pscustomobject]@{ Parametr = 'Zapisano łącznie'; Wartość = "$(Format-Num $tbw 2) TB" }
                    [pscustomobject]@{ Parametr = 'Odczytano łącznie'; Wartość = "$(Format-Num ($h.BytesRead / 1e12) 2) TB" }
                    [pscustomobject]@{ Parametr = 'Godziny pracy'; Wartość = Format-Num $h.PowerOnHours 0 }
                    [pscustomobject]@{ Parametr = 'Cykle zasilania'; Wartość = Format-Num $h.PowerCycles 0 }
                    [pscustomobject]@{ Parametr = 'Nieczyste wyłączenia'; Wartość = Format-Num $h.UnsafeShutdowns 0 }
                    [pscustomobject]@{ Parametr = 'Błędy nośnika i integralności'; Wartość = Format-Num $h.MediaErrors 0 }
                    [pscustomobject]@{ Parametr = 'Wpisy w dzienniku błędów'; Wartość = Format-Num $h.ErrorLogEntries 0 }
                    [pscustomobject]@{ Parametr = 'Czas w temp. ostrzegawczej / krytycznej (min)'; Wartość = "$($h.WarnTempMinutes) / $($h.CritTempMinutes)" }
                )
            }
        }

        # 3) SATA / HDD - atrybuty SMART (wymaga administratora)
        $key = $d.Pnp.ToUpper()
        if (-not $hadDeepData -and $ata.ContainsKey($key)) {
            $sm = $ata[$key]
            $hadDeepData = $true
            $v = Get-SdAtaVerdict -Smart $sm -IsSsd $isSsd
            $issues += @($v.Issues)
            if ($null -ne $v.Temp) { $tempTxt = "$($v.Temp) °C"; $lines += "Temperatura: $tempTxt" }
            if ($null -ne $v.Hours) { $hoursTxt = Format-Num $v.Hours 0; $lines += "Godziny pracy: $hoursTxt" }
            if ($null -ne $v.LifeLeft) { $wearTxt = "pozostało ok. $($v.LifeLeft)%"; $lines += "Szacowany pozostały czas życia SSD: $($v.LifeLeft)%" }
            $lines += "Sektory: przeniesione $(if ($null -ne $v.Reallocated) { $v.Reallocated } else { '-' }), oczekujące $(if ($null -ne $v.Pending) { $v.Pending } else { '-' }), niemożliwe do odczytu $(if ($null -ne $v.Uncorrectable) { $v.Uncorrectable } else { '-' })"
            $smartRows = @()
            foreach ($x in $sm.Attributes) {
                $flag = ''
                if ($x.Threshold -gt 0 -and $x.Current -le $x.Threshold) { $flag = 'PRÓG PRZEKROCZONY' }
                elseif (@(5, 197, 198, 187) -contains $x.Id -and ($x.Raw -band 0xFFFFFFFFL) -gt 0) { $flag = 'UWAGA' }
                $smartRows += [pscustomobject]@{ ID = $x.Id; Atrybut = $x.Name; Wartość = $x.Current; Najgorsza = $x.Worst; Próg = $x.Threshold; Surowa = $x.Raw; Ocena = $flag }
            }
            $smartTable = $smartRows
        }

        # 4) liczniki niezawodności Storage (administrator) - jeśli nic głębszego nie mamy
        if (-not $hadDeepData -and $global:SD.IsAdmin -and $d.PD -and (Get-Command Get-StorageReliabilityCounter -ErrorAction SilentlyContinue)) {
            $rc = $null
            try { $rc = $d.PD | Get-StorageReliabilityCounter -ErrorAction Stop } catch { Write-SdLog ('ReliabilityCounter: ' + $_.Exception.Message) 'INFO' }
            if ($rc) {
                $hadDeepData = $true
                if ($rc.Temperature) { $tempTxt = "$($rc.Temperature) °C"; $lines += "Temperatura: $tempTxt (maks. $($rc.TemperatureMax) °C)" }
                if ($rc.PowerOnHours) { $hoursTxt = Format-Num $rc.PowerOnHours 0; $lines += "Godziny pracy: $hoursTxt" }
                if ($null -ne $rc.Wear) { $wearTxt = "zużycie $($rc.Wear)%"; $lines += "Zużycie: $($rc.Wear)%"; if ([int]$rc.Wear -ge 90) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Zużycie SSD: $($rc.Wear)%" } } elseif ([int]$rc.Wear -ge 70) { $issues += [pscustomobject]@{ Status = 'warn'; Text = "Zużycie SSD: $($rc.Wear)%" } } }
                if ($rc.ReadErrorsUncorrected -gt 0) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Nieskorygowane błędy odczytu: $($rc.ReadErrorsUncorrected)" } }
                if ($rc.WriteErrorsUncorrected -gt 0) { $issues += [pscustomobject]@{ Status = 'crit'; Text = "Nieskorygowane błędy zapisu: $($rc.WriteErrorsUncorrected)" } }
                if ($rc.Temperature -and -not $isSsd -and [int]$rc.Temperature -ge 55) { $issues += [pscustomobject]@{ Status = $(if ([int]$rc.Temperature -ge 60) { 'crit' } else { 'warn' }); Text = "Temperatura dysku: $($rc.Temperature) °C" } }
            }
        }

        if (-not $hadDeepData -and -not $isVm) {
            if ($d.Bus -eq 'USB' -or $d.Iface -eq 'USB') { $lines += 'Dysk USB: szczegółowe dane SMART zwykle nie są dostępne przez mostek USB.' }
            elseif (-not $global:SD.IsAdmin) { $lines += 'Szczegółowe dane SMART wymagają uruchomienia programu jako administrator.' }
            else { $lines += 'Sterownik nie udostępnia szczegółowych danych SMART.' }
        }

        $status = Get-SdWorstStatus @($issues | ForEach-Object { $_.Status })
        if ($issues.Count -eq 0) { $status = 'ok' }
        $issueTxt = ($issues | Sort-Object { - (Get-SdStatusRank $_.Status) } | ForEach-Object { $_.Text }) -join '; '
        $valueParts = @($typ, $sizeTxt)
        if ($tempTxt) { $valueParts += $tempTxt }
        if ($wearTxt) { $valueParts += $wearTxt }
        $value = Join-NonEmpty $valueParts ', '
        if ($issues.Count -gt 0) { $value += ' — ' + $issueTxt } elseif ($hadDeepData) { $value += ' — stan dobry' }

        $advice = ''
        if ($status -eq 'crit') {
            $advice = 'Natychmiast wykonaj kopię zapasową danych i wymień dysk. Nie uruchamiaj chkdsk /r na uszkodzonym dysku przed skopiowaniem danych - może pogorszyć sytuację.'
        } elseif ($status -eq 'warn') {
            $advice = 'Wykonaj kopię zapasową ważnych danych i obserwuj dysk; przy wzroście liczby błędów lub spadku wydajności zaplanuj jego wymianę.'
        }
        if ($isVm) { $status = 'info'; $advice = '' }
        # ocena dla testów obciążeniowych (tt.disk nie obciąża dysku z objawami awarii)
        if (-not $global:SD.Cache.ContainsKey('DiskStatus')) { $global:SD.Cache['DiskStatus'] = @{} }
        $global:SD.Cache['DiskStatus'][[int]$d.Index] = $(if ($issues.Count -gt 0) { [string](Get-SdWorstStatus @($issues | ForEach-Object { $_.Status })) } else { 'ok' })
        Add-Finding ('Dysk {0}: {1}' -f $d.Index, $d.Model) -Status $status -Value $value -Details ($lines -join "`n") -Advice $advice

        if ($detailRows) { Add-Table ('Zdrowie NVMe - dysk {0}' -f $d.Index) -Rows $detailRows }
        if ($smartTable) { Add-Table ('Atrybuty SMART - dysk {0}' -f $d.Index) -Rows $smartTable }
        $tableRows += [pscustomobject]@{
            Nr = $d.Index; Model = $d.Model; Typ = $typ; Pojemność = $sizeTxt; Interfejs = (Join-NonEmpty @($d.Bus, $d.Iface) ' / ')
            Firmware = $d.Firmware; 'Styl partycji' = $d.PartStyle; Stan = $(if ($d.Health) { $d.Health } else { $d.WmiStatus })
        }
    }
    Set-SdMeta 'Disks' ($metaParts -join '; ')
    Add-Table 'Dyski fizyczne' -Rows $tableRows
    if ($serialLines.Count -gt 0) { Add-Finding 'Numery seryjne dysków' -Status info -Value ($serialLines -join '; ') -Private }
}

Register-Check -Id 'st.volumes' -Category 'storage' -Title 'Wolumeny i wolne miejsce' -Script {
    $vols = @(Get-Cim Win32_Volume -Filter 'DriveType=3')
    if ($vols.Count -eq 0) {
        $ld = @(Get-Cim Win32_LogicalDisk -Filter 'DriveType=3')
        $vols = @($ld | ForEach-Object { [pscustomobject]@{ DriveLetter = $_.DeviceID; Label = $_.VolumeName; FileSystem = $_.FileSystem; Capacity = $_.Size; FreeSpace = $_.FreeSpace; DirtyBitSet = $false; SystemVolume = $false; BootVolume = $false } })
    }
    $rows = @()
    $sysDrive = $env:SystemDrive
    foreach ($v in ($vols | Sort-Object { if ($_.DriveLetter) { $_.DriveLetter } else { 'ZZ' } })) {
        if (-not $v.Capacity) { continue }
        $cap = [double]$v.Capacity; $free = [double]$v.FreeSpace
        $pct = 100.0 * $free / $cap
        $letter = [string]$v.DriveLetter
        $label = [string]$v.Label
        $rows += [pscustomobject]@{
            Wolumin = $(if ($letter) { $letter } else { '(bez litery)' }); Etykieta = $label; 'System plików' = $v.FileSystem
            Pojemność = (Format-Size $cap 1); Wolne = (Format-Size $free 1); 'Wolne %' = (Format-Num $pct 1)
            Uwagi = (Join-NonEmpty @($(if ($v.SystemVolume) { 'systemowy (rozruch)' }), $(if ($v.BootVolume) { 'zawiera Windows' })) ', ')
        }
        if (-not $letter) { continue }   # partycje techniczne (EFI, Recovery) oceniamy tylko w tabeli

        $isSys = ($letter -eq $sysDrive)
        $freeGb = $free / 1GB
        $status = 'ok'; $adv = ''
        if ($isSys) {
            if ($pct -lt 5 -or $freeGb -lt 3) { $status = 'crit' } elseif ($pct -lt 15 -or $freeGb -lt 10) { $status = 'warn' }
        } else {
            if ($pct -lt 2) { $status = 'crit' } elseif ($pct -lt 10) { $status = 'warn' }
        }
        if ($status -ne 'ok') {
            $adv = 'Zwolnij miejsce: Oczyszczanie dysku (cleanmgr), usunięcie niepotrzebnych plików i programów, przeniesienie danych na inny nośnik. Przy zapełnieniu dysku system i aktualizacje działają niestabilnie.'
        }
        $val = '{0} wolne z {1} ({2}%), {3}' -f (Format-Size $free 1), (Format-Size $cap 1), (Format-Num $pct 0), $(if ($v.FileSystem) { $v.FileSystem } else { 'brak systemu plików' })
        $det = @()
        if ($label) { $det += "Etykieta: $label" }
        if ($isSys) { $det += 'Dysk systemowy.' }
        Add-Finding ('Wolumin {0}' -f $letter) -Status $status -Value $val -Details ($det -join "`n") -Advice $adv
        if ($v.DirtyBitSet) {
            Add-Finding ('Wolumin {0} - znacznik „brudny”' -f $letter) -Status warn -Value 'System plików oznaczony jako wymagający sprawdzenia' `
                -Details 'Ustawiony bit „dirty” oznacza nieprawidłowe zamknięcie lub błędy systemu plików.' `
                -Advice 'Zaplanuj sprawdzenie dysku (chkdsk) - po wcześniejszym skopiowaniu danych, jeśli dysk wykazuje oznaki awarii.'
        }
    }
    Add-Table 'Wolumeny' -Rows $rows
}

Register-Check -Id 'st.layout' -Category 'storage' -Title 'Partycje, kontroler dysku, TRIM' -Script {
    $disks = @(Get-SdDiskInventory)
    $anySsd = $false
    foreach ($d in $disks) { if ((Get-SdDiskTypeName $d) -match 'SSD') { $anySsd = $true } }

    # wyrównanie partycji
    $mis = @()
    foreach ($p in (Get-Cim Win32_DiskPartition)) {
        if ($null -ne $p.StartingOffset -and ([uint64]$p.StartingOffset % 4096) -ne 0) { $mis += ('Dysk {0}, partycja {1}' -f $p.DiskIndex, ([int]$p.Index + 1)) }
    }
    if ($mis.Count -gt 0) {
        Add-Finding 'Wyrównanie partycji' -Status warn -Value ('Niewyrównane do 4 KB: ' + ($mis -join '; ')) `
            -Details 'Partycje nie są wyrównane do granicy 4 KB, co obniża wydajność SSD i dysków Advanced Format.' `
            -Advice 'Wyrównaj partycje narzędziem do partycjonowania (po wykonaniu kopii zapasowej).'
    } else {
        Add-Finding 'Wyrównanie partycji' -Status ok -Value 'Partycje wyrównane do 4 KB'
    }

    # tryb kontrolera
    $ctrl = @(Get-SdPnp | Where-Object { $_.PNPClass -in @('HDC', 'SCSIAdapter') })
    if ($ctrl.Count -gt 0) {
        $rows = @($ctrl | ForEach-Object { [pscustomobject]@{ Kontroler = $_.Name; Usługa = $_.Service; Producent = $_.Manufacturer; Stan = $(if ($_.ConfigManagerErrorCode) { 'błąd ' + $_.ConfigManagerErrorCode } else { 'OK' }) } })
        Add-Table 'Kontrolery pamięci masowej' -Rows $rows
        $ide = @($ctrl | Where-Object { $_.Service -match '^(pciide|intelide|atapi|viaide|amdide)$' -and $_.Name -notmatch 'ATAPI' })
        if ($ide.Count -gt 0 -and $anySsd) {
            Add-Finding 'Tryb kontrolera dysku' -Status warn -Value 'Kontroler działa w trybie IDE / kompatybilności' `
                -Details (($ide | ForEach-Object { $_.Name }) -join "`n") `
                -Advice 'SSD w trybie IDE traci wydajność i funkcje (TRIM, NCQ). Przełączenie na AHCI w BIOS wymaga wcześniejszego włączenia sterownika AHCI w Windows (tryb awaryjny), inaczej system się nie uruchomi.'
        } elseif ($ide.Count -gt 0) {
            Add-Finding 'Tryb kontrolera dysku' -Status info -Value 'Kontroler działa w trybie IDE (kompatybilności)' `
                -Advice 'Tryb AHCI zapewnia lepszą wydajność i obsługę nowoczesnych funkcji. Zmianę trybu należy zaplanować (patrz uwagi o sterowniku AHCI).'
        } else {
            $names = (@($ctrl | ForEach-Object { $_.Name }) | Select-Object -First 3) -join '; '
            Add-Finding 'Tryb kontrolera dysku' -Status ok -Value $names
        }
        $bad = @($ctrl | Where-Object { $_.ConfigManagerErrorCode })
        if ($bad.Count -gt 0) {
            Add-Finding 'Kontroler dysku - błąd urządzenia' -Status crit -Value (($bad | ForEach-Object { '{0} (kod {1})' -f $_.Name, $_.ConfigManagerErrorCode }) -join '; ') `
                -Advice 'Zainstaluj lub zaktualizuj sterownik kontrolera pamięci masowej (Intel RST / AMD / producent płyty).'
        }
    }

    # TRIM
    if ($anySsd) {
        $t1 = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'DisableDeleteNotification' 0
        $t2 = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableDeleteNotification' 0
        if ([int]$t1 -eq 1 -or [int]$t2 -eq 1) {
            Add-Finding 'TRIM dla SSD' -Status warn -Value 'Wyłączony' `
                -Advice 'Włącz TRIM poleceniem: fsutil behavior set DisableDeleteNotify 0 (jako administrator).'
        } else {
            Add-Finding 'TRIM dla SSD' -Status ok -Value 'Włączony'
        }
    }
}

Register-Check -Id 'st.pagefile' -Category 'storage' -Title 'Plik wymiany i hibernacji' -Script {
    $cs = Get-SdCs
    $pf = @(Get-Cim Win32_PageFileUsage)
    $auto = $false
    if ($cs -and $cs.PSObject.Properties['AutomaticManagedPagefile']) { $auto = [bool]$cs.AutomaticManagedPagefile }
    if ($pf.Count -eq 0) {
        Add-Finding 'Plik wymiany (pagefile)' -Status warn -Value 'Wyłączony lub nie wykryto' `
            -Advice 'Włącz plik wymiany zarządzany przez system (Zaawansowane ustawienia systemu > Wydajność). Jego brak powoduje błędy braku pamięci i uniemożliwia zrzuty awaryjne.'
    } else {
        $d = @(); $worst = 0.0
        foreach ($p in $pf) {
            $alloc = [double]$p.AllocatedBaseSize; $peak = [double]$p.PeakUsage
            $pct = if ($alloc -gt 0) { 100.0 * $peak / $alloc } else { 0 }
            if ($pct -gt $worst) { $worst = $pct }
            $d += ('{0}: przydzielono {1} MB, bieżące użycie {2} MB, szczyt {3} MB ({4}%)' -f $p.Name, $alloc, $p.CurrentUsage, $peak, (Format-Num $pct 0))
        }
        $d += $(if ($auto) { 'Rozmiar zarządzany automatycznie przez system.' } else { 'Rozmiar ustawiony ręcznie.' })
        if ($worst -ge 90) {
            Add-Finding 'Plik wymiany (pagefile)' -Status warn -Value ('Szczytowe użycie {0}% przydziału' -f (Format-Num $worst 0)) -Details ($d -join "`n") `
                -Advice 'Plik wymiany bywa wykorzystany niemal w całości - zwiększ jego rozmiar lub włącz zarządzanie automatyczne; rozważ dołożenie RAM.'
        } else {
            Add-Finding 'Plik wymiany (pagefile)' -Status ok -Value ('{0}; szczytowe użycie {1}%' -f $(if ($auto) { 'automatyczny' } else { 'ręczny' }), (Format-Num $worst 0)) -Details ($d -join "`n")
        }
    }
    $hib = Get-Item -LiteralPath (Join-Path $env:SystemDrive 'hiberfil.sys') -Force -ErrorAction SilentlyContinue
    if ($hib) {
        Add-Finding 'Plik hibernacji (hiberfil.sys)' -Status info -Value (Format-Size $hib.Length 1) `
            -Details 'Plik zajmuje miejsce na dysku systemowym; jest wymagany dla hibernacji i szybkiego uruchamiania.' `
            -Advice 'Jeśli brakuje miejsca na dysku, a hibernacja nie jest potrzebna: powercfg /h off (wyłącza też szybkie uruchamianie).'
    }
}

function Get-SdUserProfiles {
    Get-SdCached 'Profiles' {
        $list = @(Get-Cim Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) })
        $list
    }
}

Register-Check -Id 'st.cleanup' -Category 'storage' -Title 'Miejsce możliwe do odzyskania' -Level Full -Script {
    $sysDrive = $env:SystemDrive
    $win = $env:SystemRoot
    $items = New-Object System.Collections.ArrayList
    function Add-SdCleanItem($name, $path, $safe, $note) { [void]$items.Add([pscustomobject]@{ Name = $name; Path = $path; Safe = $safe; Note = $note }) }

    Add-SdCleanItem 'Pliki tymczasowe systemu' (Join-Path $win 'Temp') $true 'Bezpieczne do usunięcia'
    Add-SdCleanItem 'Pamięć podręczna Windows Update' (Join-Path $win 'SoftwareDistribution\Download') $true 'Pobrane pakiety aktualizacji'
    Add-SdCleanItem 'Raporty błędów Windows (WER)' (Join-Path $env:ProgramData 'Microsoft\Windows\WER') $true 'Raporty awarii'
    Add-SdCleanItem 'Poprzednia instalacja Windows (Windows.old)' (Join-Path $sysDrive 'Windows.old') $false 'Umożliwia powrót do poprzedniej wersji; usuń przez Oczyszczanie dysku po upewnieniu się, że nie jest potrzebna'
    Add-SdCleanItem 'Kosz' (Join-Path $sysDrive '$Recycle.Bin') $false 'Zawartość kosza użytkowników'
    foreach ($up in (Get-SdUserProfiles)) {
        $user = Split-Path $up.LocalPath -Leaf
        Add-SdCleanItem ("Temp użytkownika $user") (Join-Path $up.LocalPath 'AppData\Local\Temp') $true 'Bezpieczne do usunięcia (poza otwartymi plikami)'
        Add-SdCleanItem ("Pamięć podręczna Chrome ($user)") (Join-Path $up.LocalPath 'AppData\Local\Google\Chrome\User Data\Default\Cache') $true 'Cache przeglądarki'
        Add-SdCleanItem ("Pamięć podręczna Edge ($user)") (Join-Path $up.LocalPath 'AppData\Local\Microsoft\Edge\User Data\Default\Cache') $true 'Cache przeglądarki'
        Add-SdCleanItem ("Pamięć podręczna Firefox ($user)") (Join-Path $up.LocalPath 'AppData\Local\Mozilla\Firefox\Profiles') $true 'Cache przeglądarki (wraz z profilem - rozmiar zawyżony)'
    }
    $rows = @(); $safeTotal = 0.0; $winOld = 0.0
    foreach ($it in $items) {
        if (-not (Test-Path -LiteralPath $it.Path)) { continue }
        $s = Get-SdDirSize $it.Path
        if ($s.Bytes -le 0) { continue }
        if ($it.Safe -and $it.Name -notmatch 'Firefox') { $safeTotal += $s.Bytes }
        if ($it.Name -match 'Windows.old') { $winOld = $s.Bytes }
        $rows += [pscustomobject]@{ Lokalizacja = $it.Name; Rozmiar = (Format-Size $s.Bytes 1); 'Liczba plików' = $s.Files; 'Bezpieczne' = $(if ($it.Safe) { 'tak' } else { 'sprawdź' }); Ścieżka = $it.Path; Uwagi = $it.Note }
    }
    if ($rows.Count -eq 0) { Add-Finding 'Miejsce do odzyskania' -Status ok -Value 'Brak dużych zbędnych plików'; return }
    Add-Table 'Miejsce możliwe do odzyskania' -Rows $rows
    $valueTxt = 'Około {0} z plików tymczasowych i pamięci podręcznych' -f (Format-Size $safeTotal 1)
    if ($winOld -gt 0) { $valueTxt += '; dodatkowo Windows.old: ' + (Format-Size $winOld 1) }
    $st = if ($safeTotal -ge 5GB -or $winOld -ge 5GB) { 'info' } else { 'ok' }
    Add-Finding 'Miejsce do odzyskania' -Status $st -Value $valueTxt `
        -Advice 'Wyczyść pliki tymczasowe (Oczyszczanie dysku / Ustawienia > System > Pamięć). Szczegóły w tabeli „Miejsce możliwe do odzyskania”.'
}
