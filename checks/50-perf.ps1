# Testy kategorii: Wydajność

Register-Check -Id 'pf.sample' -Category 'perf' -Title 'Obciążenie procesora, pamięci i dysku (próbkowanie)' -Script {
    $logical = 0
    foreach ($c in (Get-SdCpus)) { $logical += [int]$c.NumberOfLogicalProcessors }
    if ($logical -le 0) { $logical = [Environment]::ProcessorCount }

    # Liczniki PDH (nazwy angielskie, niezależne od języka systemu); migawki procesów z WMI.
    $pdh = New-SdPdh
    $iCpu = -1; $iDisk = -1; $iQueue = -1
    if ($pdh) {
        $iCpu = $pdh.Add('\Processor(_Total)\% Processor Time')
        $iDisk = $pdh.Add('\PhysicalDisk(_Total)\% Disk Time')
        $iQueue = $pdh.Add('\PhysicalDisk(_Total)\Current Disk Queue Length')
        [void]$pdh.Collect()
    }
    $cpuS = New-Object System.Collections.ArrayList
    $dskS = New-Object System.Collections.ArrayList
    $qS = New-Object System.Collections.ArrayList

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $a1 = $clock.Elapsed.TotalSeconds
    $p1 = @{}
    foreach ($p in (Get-Cim Win32_Process)) { $p1[[int]$p.ProcessId] = $p }
    $b1 = $clock.Elapsed.TotalSeconds

    for ($i = 0; $i -lt 5; $i++) {
        Start-Sleep -Milliseconds 1000
        if ($pdh) {
            [void]$pdh.Collect()
            $v = $pdh.Get($iCpu);   if (-not [double]::IsNaN($v)) { [void]$cpuS.Add($v) }
            $v = $pdh.Get($iDisk);  if (-not [double]::IsNaN($v)) { [void]$dskS.Add([math]::Min($v, 100.0)) }
            $v = $pdh.Get($iQueue); if (-not [double]::IsNaN($v)) { [void]$qS.Add($v) }
        }
    }
    if ($pdh) { $pdh.Dispose() }
    if ($cpuS.Count -eq 0) {
        # awaryjnie: WMI (wolniejsze)
        for ($i = 0; $i -lt 3; $i++) {
            $lp = (@(Get-Cim Win32_Processor) | Measure-Object -Property LoadPercentage -Average).Average
            if ($null -ne $lp) { [void]$cpuS.Add([double]$lp) }
        }
    }
    $a2 = $clock.Elapsed.TotalSeconds
    $p2 = @(Get-Cim Win32_Process)
    $b2 = $clock.Elapsed.TotalSeconds
    Write-SdLog ('pf.sample: p1 {0:N1}-{1:N1}s, p2 {2:N1}-{3:N1}s' -f $a1, $b1, $a2, $b2) 'DEBUG'
    # migawka WMI przypada mniej więcej w połowie czasu trwania zapytania
    $dt = [math]::Max((($a2 + $b2) / 2) - (($a1 + $b1) / 2), 0.5)

    # --- ranking procesorów / pamięci / dysku
    $rows = @()
    foreach ($p in $p2) {
        $pid2 = [int]$p.ProcessId
        if ($pid2 -eq 0) { continue }
        $prev = $p1[$pid2]
        $cpu = 0.0; $rd = 0.0; $wr = 0.0
        if ($prev) {
            $cpuSec = (([double]$p.KernelModeTime + [double]$p.UserModeTime) - ([double]$prev.KernelModeTime + [double]$prev.UserModeTime)) / 1e7
            $cpu = [math]::Max(0.0, 100.0 * $cpuSec / ($dt * $logical))
            $rd = [math]::Max(0.0, ([double]$p.ReadTransferCount - [double]$prev.ReadTransferCount) / $dt)
            $wr = [math]::Max(0.0, ([double]$p.WriteTransferCount - [double]$prev.WriteTransferCount) / $dt)
        }
        $rows += [pscustomobject]@{
            Proces = [string]$p.Name; PID = $pid2; CpuNum = $cpu; RamNum = [double]$p.WorkingSetSize; IoNum = ($rd + $wr)
            Ścieżka = [string]$p.ExecutablePath
        }
    }

    # --- procesor
    $cpuAvg = 0.0; $cpuMax = 0.0
    if ($cpuS.Count -gt 0) { $cpuAvg = ($cpuS | Measure-Object -Average).Average; $cpuMax = ($cpuS | Measure-Object -Maximum).Maximum }
    $topCpu = @($rows | Sort-Object CpuNum -Descending | Select-Object -First 5)
    $topTxt = ($topCpu | Where-Object { $_.CpuNum -ge 1 } | ForEach-Object { '{0} ({1}%)' -f $_.Proces, (Format-Num $_.CpuNum 0) }) -join ', '
    $cpuDetails = "Próbkowanie: $($cpuS.Count) pomiarów w ciągu $(Format-Num $dt 0) s; maksimum $(Format-Num $cpuMax 0)%"
    if ($topTxt) { $cpuDetails += "`nNajbardziej obciążające procesy: $topTxt" }
    $cpuVal = 'średnio {0}%' -f (Format-Num $cpuAvg 0)
    if ($topTxt -and $cpuAvg -ge 25) { $cpuVal += '; głównie: ' + (($topCpu | Where-Object { $_.CpuNum -ge 5 } | Select-Object -First 3 | ForEach-Object { $_.Proces }) -join ', ') }
    if ($cpuAvg -ge 90) {
        Add-Finding 'Obciążenie procesora' -Status warn -Value $cpuVal -Details $cpuDetails `
            -Advice 'Procesor jest niemal stale obciążony. Sprawdź wskazane procesy (Menedżer zadań > Szczegóły), skanowanie antywirusowe, aktualizacje w tle oraz możliwe złośliwe oprogramowanie (np. koparki kryptowalut).'
    } elseif ($cpuAvg -ge 60) {
        Add-Finding 'Obciążenie procesora' -Status info -Value $cpuVal -Details $cpuDetails
    } else {
        Add-Finding 'Obciążenie procesora' -Status ok -Value $cpuVal -Details $cpuDetails
    }

    # --- pamięć
    $os = Get-Cim Win32_OperatingSystem | Select-Object -First 1
    if ($os) {
        $totalKb = [double]$os.TotalVisibleMemorySize; $freeKb = [double]$os.FreePhysicalMemory
        $usedPct = 100.0 * ($totalKb - $freeKb) / $totalKb
        $commitTotal = [double]$os.TotalVirtualMemorySize; $commitFree = [double]$os.FreeVirtualMemory
        $commitPct = if ($commitTotal -gt 0) { 100.0 * ($commitTotal - $commitFree) / $commitTotal } else { 0 }
        $topRam = @($rows | Sort-Object RamNum -Descending | Select-Object -First 5)
        $ramTxt = ($topRam | ForEach-Object { '{0} ({1})' -f $_.Proces, (Format-Size $_.RamNum 0) }) -join ', '
        $d = "Zajęte: $(Format-Size (($totalKb - $freeKb) * 1KB) 1) z $(Format-Size ($totalKb * 1KB) 1); zatwierdzona pamięć wirtualna: $(Format-Num $commitPct 0)%`nNajwiększe procesy: $ramTxt"
        $val = '{0}% zajęte ({1} z {2})' -f (Format-Num $usedPct 0), (Format-Size (($totalKb - $freeKb) * 1KB) 1), (Format-Size ($totalKb * 1KB) 1)
        if ($usedPct -ge 95 -or $commitPct -ge 95) {
            Add-Finding 'Zużycie pamięci RAM' -Status crit -Value $val -Details $d `
                -Advice 'Pamięć jest niemal całkowicie wykorzystana - system intensywnie korzysta z wolnego pliku wymiany. Zamknij zbędne programy, sprawdź wycieki pamięci w procesach i rozważ dołożenie RAM.'
        } elseif ($usedPct -ge 85 -or $commitPct -ge 85) {
            Add-Finding 'Zużycie pamięci RAM' -Status warn -Value $val -Details $d `
                -Advice 'Wysokie zużycie pamięci. Sprawdź największe procesy i programy w autostarcie; rozważ dołożenie RAM.'
        } else {
            Add-Finding 'Zużycie pamięci RAM' -Status ok -Value $val -Details $d
        }
    }

    # --- dysk
    if ($dskS.Count -gt 0) {
        $dAvg = ($dskS | Measure-Object -Average).Average; $dMax = ($dskS | Measure-Object -Maximum).Maximum
        $qAvg = ($qS | Measure-Object -Average).Average
        $topIo = @($rows | Sort-Object IoNum -Descending | Select-Object -First 5 | Where-Object { $_.IoNum -gt 50KB })
        $ioTxt = ($topIo | ForEach-Object { '{0} ({1}/s)' -f $_.Proces, (Format-Size $_.IoNum 1) }) -join ', '
        $d = "Czas aktywności dysku: średnio $(Format-Num $dAvg 0)%, maks. $(Format-Num $dMax 0)%; średnia kolejka: $(Format-Num $qAvg 1)"
        if ($ioTxt) { $d += "`nNajwięcej operacji dyskowych: $ioTxt" }
        $val = 'aktywność średnio {0}%{1}' -f (Format-Num $dAvg 0), $(if ($ioTxt -and $dAvg -ge 40) { '; głównie: ' + (($topIo | Select-Object -First 3 | ForEach-Object { $_.Proces }) -join ', ') } else { '' })
        if ($dAvg -ge 90) {
            Add-Finding 'Aktywność dysku' -Status warn -Value $val -Details $d `
                -Advice 'Dysk jest stale obciążony na ~100% - typowa przyczyna wolnego działania (szczególnie HDD). Sprawdź procesy z listy, indeksowanie, Windows Update, antywirus; zalecana wymiana HDD na SSD.'
        } elseif ($dAvg -ge 60) {
            Add-Finding 'Aktywność dysku' -Status info -Value $val -Details $d
        } else {
            Add-Finding 'Aktywność dysku' -Status ok -Value $val -Details $d
        }
    }

    # --- pula nonpaged (wycieki w sterownikach)
    $mem = Get-Cim Win32_PerfFormattedData_PerfOS_Memory | Select-Object -First 1
    if ($mem -and $mem.PoolNonpagedBytes) {
        $np = [double]$mem.PoolNonpagedBytes
        $d = "Pula nonpaged: $(Format-Size $np 0); pula paged: $(Format-Size $mem.PoolPagedBytes 0); pamięć podręczna: $(Format-Size $mem.CacheBytes 0)"
        if ($np -ge 1.5GB) {
            Add-Finding 'Pula pamięci jądra (nonpaged)' -Status warn -Value (Format-Size $np 0) -Details $d `
                -Advice 'Bardzo duża pula nonpaged zwykle oznacza wyciek pamięci w sterowniku. Zaktualizuj sterowniki (sieć, dyski, antywirus, VPN); pomocny jest PoolMon.'
        } else {
            Add-Finding 'Pula pamięci jądra (nonpaged)' -Status ok -Value (Format-Size $np 0) -Details $d
        }
    }

    # --- tabela procesów
    $tbl = @($rows | Sort-Object @{ Expression = { $_.CpuNum + ($_.RamNum / 1GB) } } -Descending | Select-Object -First 20 | ForEach-Object {
            [pscustomobject]@{
                Proces = $_.Proces; PID = $_.PID; 'CPU %' = (Format-Num $_.CpuNum 1); RAM = (Format-Size $_.RamNum 0)
                'Dysk /s' = (Format-Size $_.IoNum 1); Ścieżka = $_.Ścieżka
            }
        })
    Add-Table 'Najbardziej obciążające procesy' -Rows $tbl
    Set-SdMeta 'ProcessCount' $p2.Count
}

function Get-SdEventData {
    # Zwraca słownik pól <EventData><Data Name=...> zdarzenia (odporne na lokalizację i kolejność pól).
    param($Event)
    $h = @{}
    try {
        $x = [xml]$Event.ToXml()
        foreach ($n in $x.Event.EventData.Data) { if ($n.Name) { $h[[string]$n.Name] = [string]$n.'#text' } }
    } catch { }
    return $h
}

Register-Check -Id 'pf.boot' -Category 'perf' -Title 'Czas uruchamiania systemu' -NeedsAdmin -Script {
    $days = if ($global:SD.Level -eq 'Full') { 90 } else { 45 }
    $since = (Get-Date).AddDays(-$days)
    $ev = @(Get-SdEvents -Filter @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100; StartTime = $since } -Max 40)
    if ($ev.Count -eq 0) {
        Add-Finding 'Czas uruchamiania systemu' -Status skip -Value 'Brak danych o rozruchu w dzienniku Diagnostics-Performance (dziennik wyłączony lub wyczyszczony).'
        return
    }
    $boots = @()
    foreach ($e in ($ev | Sort-Object TimeCreated -Descending | Select-Object -First 12)) {
        $d = Get-SdEventData $e
        $bt = 0.0; $mp = 0.0; $pb = 0.0
        [void][double]::TryParse($d['BootTime'], [ref]$bt)
        [void][double]::TryParse($d['MainPathBootTime'], [ref]$mp)
        [void][double]::TryParse($d['BootPostBootTime'], [ref]$pb)
        if ($bt -le 0) { continue }
        $boots += [pscustomobject]@{ Data = $e.TimeCreated; Total = $bt / 1000; Main = $mp / 1000; Post = $pb / 1000 }
    }
    if ($boots.Count -eq 0) { return }
    $avgMain = ($boots | Measure-Object -Property Main -Average).Average
    $avgTotal = ($boots | Measure-Object -Property Total -Average).Average
    $last = $boots[0]
    $rows = @($boots | ForEach-Object { [pscustomobject]@{ Data = (Format-Dt $_.Data); 'Do pulpitu (s)' = (Format-Num $_.Main 0); 'Po starcie (s)' = (Format-Num $_.Post 0); 'Razem (s)' = (Format-Num $_.Total 0) } })
    Add-Table 'Czasy uruchamiania systemu' -Rows $rows
    $val = 'średnio {0} s do pulpitu (ostatnio {1} s); {2} s do pełnej responsywności' -f (Format-Num $avgMain 0), (Format-Num $last.Main 0), (Format-Num $avgTotal 0)
    $d = "Analizowane rozruchy: $($boots.Count) (ostatnie $days dni)"
    if ($avgMain -ge 120) {
        Add-Finding 'Czas uruchamiania systemu' -Status warn -Value $val -Details $d `
            -Advice 'Bardzo wolny start. Zmniejsz liczbę programów w autostarcie, sprawdź elementy spowalniające start (poniżej), a przy dysku HDD wymień go na SSD.'
    } elseif ($avgMain -ge 60) {
        Add-Finding 'Czas uruchamiania systemu' -Status info -Value $val -Details $d `
            -Advice 'Start jest dość powolny - warto przejrzeć autostart; SSD skraca go zwykle kilkukrotnie.'
    } else {
        Add-Finding 'Czas uruchamiania systemu' -Status ok -Value $val -Details $d
    }

    # elementy spowalniające uruchamianie (zdarzenia 101-110)
    $deg = @(Get-SdEvents -Filter @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = @(101, 102, 103, 106, 109); StartTime = $since } -Max 300)
    if ($deg.Count -gt 0) {
        $kind = @{ 101 = 'Aplikacja'; 102 = 'Sterownik'; 103 = 'Usługa'; 106 = 'Urządzenie'; 109 = 'Zadanie logowania' }
        $agg = @{}
        foreach ($e in $deg) {
            $d = Get-SdEventData $e
            $n = $d['FriendlyName']; if (-not $n) { $n = $d['Name'] }; if (-not $n) { $n = $d['FileName'] }
            if (-not $n) { continue }
            $k = '{0}|{1}' -f $e.Id, $n
            $deg1 = 0.0; [void][double]::TryParse($d['DegradationTime'], [ref]$deg1)
            $tot = 0.0; [void][double]::TryParse($d['TotalTime'], [ref]$tot)
            if (-not $agg.ContainsKey($k)) { $agg[$k] = [pscustomobject]@{ Typ = $kind[[int]$e.Id]; Nazwa = $n; Razy = 0; Suma = 0.0; Maks = 0.0 } }
            $agg[$k].Razy++; $agg[$k].Suma += $deg1; if ($tot -gt $agg[$k].Maks) { $agg[$k].Maks = $tot }
        }
        $top = @($agg.Values | Sort-Object Suma -Descending | Select-Object -First 12)
        if ($top.Count -gt 0) {
            $trows = @($top | ForEach-Object { [pscustomobject]@{ Typ = $_.Typ; Nazwa = $_.Nazwa; 'Liczba rozruchów' = $_.Razy; 'Łączne opóźnienie (s)' = (Format-Num ($_.Suma / 1000) 0); 'Najdłuższy czas (s)' = (Format-Num ($_.Maks / 1000) 0) } })
            Add-Table 'Elementy spowalniające uruchamianie' -Rows $trows
            $names = ($top | Select-Object -First 3 | ForEach-Object { $_.Nazwa }) -join ', '
            Add-Finding 'Elementy spowalniające start' -Status info -Value ('Najbardziej opóźniają start: ' + $names) `
                -Details 'Pełna lista w tabeli „Elementy spowalniające uruchamianie”.' `
                -Advice 'Rozważ wyłączenie niepotrzebnych programów z autostartu lub aktualizację/usunięcie wymienionych sterowników i usług.'
        }
    }
}
