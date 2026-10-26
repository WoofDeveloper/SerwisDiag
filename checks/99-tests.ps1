# Testy obciążeniowe (poziom "Test"): uruchamiane wyłącznie na życzenie technika.

$global:SdTestSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class SdBenchResult
{
    public double SeqWriteMBs;
    public double SeqReadMBs;
    public double Rand4kReadIops;
    public double Rand4kWriteIops;
    public string Error;
}

// Test dysku bez buforowania systemowego (FILE_FLAG_NO_BUFFERING | WRITE_THROUGH): mierzy urzadzenie, a nie pamiec podreczna.
public static class SdDiskBench
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteFile(SafeFileHandle h, IntPtr buf, uint n, out uint written, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadFile(SafeFileHandle h, IntPtr buf, uint n, out uint read, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFilePointerEx(SafeFileHandle h, long dist, out long newPos, uint method);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr VirtualAlloc(IntPtr addr, UIntPtr size, uint type, uint protect);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool VirtualFree(IntPtr addr, UIntPtr size, uint type);

    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint DELETE = 0x00010000;
    private const uint SHARE_ALL = 7;
    private const uint CREATE_ALWAYS = 2;
    private const uint FLAGS = 0x20000000 | 0x80000000 | 0x04000000; // NO_BUFFERING | WRITE_THROUGH | DELETE_ON_CLOSE
    private const uint MEM_COMMIT_RESERVE = 0x3000;
    private const uint MEM_RELEASE = 0x8000;
    private const uint PAGE_READWRITE = 4;

    public static SdBenchResult Run(string path, int sizeMB, int randSeconds)
    {
        SdBenchResult r = new SdBenchResult();
        const int chunk = 1024 * 1024;
        IntPtr buf = IntPtr.Zero;
        try
        {
            buf = VirtualAlloc(IntPtr.Zero, new UIntPtr((uint)chunk), MEM_COMMIT_RESERVE, PAGE_READWRITE);
            if (buf == IntPtr.Zero) { r.Error = "VirtualAlloc " + Marshal.GetLastWin32Error(); return r; }
            byte[] rnd = new byte[chunk];
            new Random(12345).NextBytes(rnd);          // dane losowe - nie do skompresowania przez kontroler SSD
            Marshal.Copy(rnd, 0, buf, chunk);

            using (SafeFileHandle h = CreateFile(path, GENERIC_READ | GENERIC_WRITE | DELETE, SHARE_ALL, IntPtr.Zero, CREATE_ALWAYS, FLAGS, IntPtr.Zero))
            {
                if (h.IsInvalid) { r.Error = "CreateFile " + Marshal.GetLastWin32Error(); return r; }
                uint n; long pos;
                Stopwatch sw = Stopwatch.StartNew();
                for (int i = 0; i < sizeMB; i++)
                {
                    if (!WriteFile(h, buf, (uint)chunk, out n, IntPtr.Zero)) { r.Error = "WriteFile " + Marshal.GetLastWin32Error(); return r; }
                }
                sw.Stop();
                r.SeqWriteMBs = sizeMB / Math.Max(sw.Elapsed.TotalSeconds, 0.001);

                SetFilePointerEx(h, 0, out pos, 0);
                sw.Reset(); sw.Start();
                for (int i = 0; i < sizeMB; i++)
                {
                    if (!ReadFile(h, buf, (uint)chunk, out n, IntPtr.Zero)) { r.Error = "ReadFile " + Marshal.GetLastWin32Error(); return r; }
                }
                sw.Stop();
                r.SeqReadMBs = sizeMB / Math.Max(sw.Elapsed.TotalSeconds, 0.001);

                long blocks = ((long)sizeMB * 1024 * 1024) / 4096;
                Random rr = new Random(777);
                long ops = 0;
                sw.Reset(); sw.Start();
                while (sw.Elapsed.TotalSeconds < randSeconds)
                {
                    long off = (long)(rr.NextDouble() * blocks) * 4096;
                    SetFilePointerEx(h, off, out pos, 0);
                    if (!ReadFile(h, buf, 4096, out n, IntPtr.Zero)) break;
                    ops++;
                }
                sw.Stop();
                r.Rand4kReadIops = ops / Math.Max(sw.Elapsed.TotalSeconds, 0.001);

                ops = 0;
                sw.Reset(); sw.Start();
                while (sw.Elapsed.TotalSeconds < randSeconds)
                {
                    long off = (long)(rr.NextDouble() * blocks) * 4096;
                    SetFilePointerEx(h, off, out pos, 0);
                    if (!WriteFile(h, buf, 4096, out n, IntPtr.Zero)) break;
                    ops++;
                }
                sw.Stop();
                r.Rand4kWriteIops = ops / Math.Max(sw.Elapsed.TotalSeconds, 0.001);
            }
        }
        catch (Exception ex) { r.Error = ex.Message; }
        finally { if (buf != IntPtr.Zero) VirtualFree(buf, UIntPtr.Zero, MEM_RELEASE); }
        return r;
    }
}

// Obciazenie procesora: po jednym watku na kazdy procesor logiczny.
public static class SdBurn
{
    private static volatile bool stop;
    private static System.Threading.Thread[] threads;

    public static void Start(int count)
    {
        stop = false;
        threads = new System.Threading.Thread[count];
        for (int i = 0; i < count; i++)
        {
            threads[i] = new System.Threading.Thread(Work);
            threads[i].IsBackground = true;
            threads[i].Start();
        }
    }

    public static void Stop()
    {
        stop = true;
        if (threads != null)
        {
            foreach (System.Threading.Thread t in threads) { if (t != null) t.Join(3000); }
        }
    }

    private static void Work()
    {
        double x = 1.2345;
        while (!stop)
        {
            for (int i = 0; i < 2000000; i++) { x = Math.Sqrt(x * 1.000001 + 0.5) + Math.Sin(x); }
            if (double.IsNaN(x) || double.IsInfinity(x)) x = 1.0;
        }
    }
}
'@

function Initialize-SdTestNative {
    if ('SdDiskBench' -as [type]) { return $true }
    try { Add-Type -TypeDefinition $global:SdTestSource -Language CSharp -ErrorAction Stop; return $true }
    catch { Write-SdLog ('Kompilacja testów: ' + $_.Exception.Message) 'ERROR'; return $false }
}

function Set-SdProgressText {
    param([string]$Text)
    if ($null -ne $global:SD -and $null -ne $global:SD.Progress) { $global:SD.Progress.Title = $Text }
}

function Get-SdSystemDiskRisk {
    # Opis zagrożenia, gdy dysk systemowy ma objawy awarii (ocena SMART z tego skanowania albo stan zgłaszany przez Windows).
    # Pusty napis = można testować. Test zapisuje i czyta 512 MB - słabnący dysk mógłby się przy tym dobić.
    $disks = @(Get-SdDiskInventory)
    $idx = $null
    $maps = Get-SdVolumeMaps
    $letter = ([string]$env:SystemDrive).ToUpper()
    if ($maps -and $maps.LetterToDisk.ContainsKey($letter)) { $idx = [int]$maps.LetterToDisk[$letter] }
    if ($null -eq $idx) { $sys = $disks | Where-Object { $_.IsSystem } | Select-Object -First 1; if ($sys) { $idx = [int]$sys.Index } }
    if ($null -eq $idx) { return '' }
    $st = $global:SD.Cache['DiskStatus']
    if ($st -and $st.ContainsKey($idx) -and $st[$idx] -eq 'crit') { return ('dysk systemowy (dysk {0}) ma objawy awarii w ocenie SMART - zob. kategoria Dyski' -f $idx) }
    $d = $disks | Where-Object { $_.Index -eq $idx } | Select-Object -First 1
    if ($d -and ($d.Health -eq 'Unhealthy' -or $d.WmiStatus -eq 'Pred Fail' -or $d.Operational -match 'Predictive|Failed|IO Error|Lost Communication')) {
        return ('Windows zgłasza awarię dysku systemowego (dysk {0}: {1})' -f $idx, (Join-NonEmpty @($d.Health, $d.WmiStatus, $d.Operational) ', '))
    }
    return ''
}

Register-Check -Id 'tt.disk' -Category 'tests' -Title 'Test szybkości dysku systemowego' -Level Test -Script {
    if (-not (Initialize-SdTestNative)) { Add-Finding 'Test szybkości dysku' -Status error -Value 'Nie udało się skompilować modułu testowego.'; return }
    $risk = Get-SdSystemDiskRisk
    if ($risk) {
        Add-Finding 'Test szybkości dysku' -Status skip -Value ('Pominięto: ' + $risk) `
            -Advice 'Najpierw zabezpiecz dane (kopia lub klon dysku), dopiero potem testuj wydajność - intensywny zapis i odczyt może przyspieszyć awarię.'
        return
    }
    $drive = $env:SystemDrive
    $vol = Get-Cim Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $drive) | Select-Object -First 1
    $sizeMb = 512
    if ($vol -and [double]$vol.FreeSpace -lt (4GB)) {
        Add-Finding 'Test szybkości dysku' -Status skip -Value 'Za mało wolnego miejsca na teście (potrzeba min. 4 GB).'
        return
    }
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('sd-bench-' + [guid]::NewGuid().ToString('N') + '.tmp')
    Set-SdProgressText 'Test dysku: zapis i odczyt sekwencyjny, losowe 4K (ok. 25 s)...'
    $r = [SdDiskBench]::Run($path, $sizeMb, 4)
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($r.Error) { Add-Finding 'Test szybkości dysku' -Status error -Value ('Błąd testu: ' + $r.Error); return }

    $disks = @(Get-SdDiskInventory)
    $sys = $disks | Where-Object { $_.IsSystem } | Select-Object -First 1
    if (-not $sys) { $sys = $disks | Select-Object -First 1 }
    $typ = if ($sys) { Get-SdDiskTypeName $sys } else { 'dysk' }
    # progi orientacyjne (odczyt sekwencyjny MB/s, losowy odczyt 4K QD1 IOPS) dla danego typu nośnika
    if ($typ -match 'NVMe') { $thr = @{ Seq = 800; Iops = 6000 } }
    elseif ($typ -match 'SSD') { $thr = @{ Seq = 300; Iops = 4000 } }
    else { $thr = @{ Seq = 60; Iops = 60 } }
    $val = 'zapis sekw. {0} MB/s; odczyt sekw. {1} MB/s; losowy odczyt 4K: {2} IOPS; losowy zapis 4K: {3} IOPS' -f (Format-Num $r.SeqWriteMBs 0), (Format-Num $r.SeqReadMBs 0), (Format-Num $r.Rand4kReadIops 0), (Format-Num $r.Rand4kWriteIops 0)
    $d = @("Typ dysku: $typ; plik testowy: $sizeMb MB na $drive (usunięty po teście)", 'Test bez pamięci podręcznej systemu, wątek pojedynczy (głębokość kolejki 1).')
    $rows = @(
        [pscustomobject]@{ Test = 'Odczyt sekwencyjny'; Wynik = ('{0} MB/s' -f (Format-Num $r.SeqReadMBs 0)) }
        [pscustomobject]@{ Test = 'Zapis sekwencyjny'; Wynik = ('{0} MB/s' -f (Format-Num $r.SeqWriteMBs 0)) }
        [pscustomobject]@{ Test = 'Odczyt losowy 4 KB (QD1)'; Wynik = ('{0} IOPS (~{1} MB/s)' -f (Format-Num $r.Rand4kReadIops 0), (Format-Num ($r.Rand4kReadIops * 4096 / 1MB) 1)) }
        [pscustomobject]@{ Test = 'Zapis losowy 4 KB (QD1)'; Wynik = ('{0} IOPS (~{1} MB/s)' -f (Format-Num $r.Rand4kWriteIops 0), (Format-Num ($r.Rand4kWriteIops * 4096 / 1MB) 1)) }
    )
    Add-Table 'Wyniki testu dysku' -Rows $rows
    $slow = ($r.SeqReadMBs -lt $thr.Seq) -or ($r.Rand4kReadIops -lt $thr.Iops)
    if ($slow) {
        Add-Finding 'Test szybkości dysku' -Status warn -Value $val -Details ($d -join "`n") `
            -Advice 'Wydajność dysku jest niższa niż typowa dla tego typu nośnika. Sprawdź tryb kontrolera (AHCI), stan SMART, kabel SATA i sterowniki; zapełniony lub zużyty dysk bywa wolniejszy. Przy HDD zalecany SSD.'
    } else {
        Add-Finding 'Test szybkości dysku' -Status ok -Value $val -Details ($d -join "`n")
    }
}

Register-Check -Id 'tt.cpu' -Category 'tests' -Title 'Test obciążeniowy procesora (dławienie, temperatura)' -Level Test -Script {
    if (-not (Initialize-SdTestNative)) { Add-Finding 'Test obciążeniowy procesora' -Status error -Value 'Nie udało się skompilować modułu testowego.'; return }
    $logical = [Environment]::ProcessorCount
    $burnSec = 45
    $pdh = New-SdPdh
    $iFreq = -1; $iLoad = -1
    if ($pdh) {
        $iFreq = $pdh.Add('\Processor Information(_Total)\% of Maximum Frequency')
        $iLoad = $pdh.Add('\Processor(_Total)\% Processor Time')
        [void]$pdh.Collect()
    }
    $readThermal = {
        $t = Get-Cim Win32_PerfFormattedData_Counters_ThermalZoneInformation
        $r = [pscustomobject]@{ TempC = $null; PassiveLimit = $null; Reasons = 0 }
        foreach ($z in $t) {
            $c = $null
            if ($z.HighPrecisionTemperature) { $c = [double]$z.HighPrecisionTemperature / 10 - 273.15 } elseif ($z.Temperature) { $c = [double]$z.Temperature - 273.15 }
            if ($null -ne $c -and ($null -eq $r.TempC -or $c -gt $r.TempC)) { $r.TempC = $c }
            if ($null -ne $z.PercentPassiveLimit -and ($null -eq $r.PassiveLimit -or [double]$z.PercentPassiveLimit -lt $r.PassiveLimit)) { $r.PassiveLimit = [double]$z.PercentPassiveLimit }
            if ($z.ThrottleReasons) { $r.Reasons = $r.Reasons -bor [int]$z.ThrottleReasons }
        }
        $r
    }
    $freq = New-Object System.Collections.ArrayList
    $load = New-Object System.Collections.ArrayList
    $temps = New-Object System.Collections.ArrayList
    $passive = New-Object System.Collections.ArrayList
    $reasons = 0
    $idleTemp = $null
    $bat = @(Get-Cim Win32_Battery | Where-Object { $_.BatteryStatus -eq 1 }).Count -gt 0

    try {
        Set-SdProgressText 'Test CPU: pomiar w spoczynku...'
        $idle = & $readThermal
        $idleTemp = $idle.TempC
        Start-Sleep -Milliseconds 800
        [SdBurn]::Start($logical)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tick = 0
        while ($sw.Elapsed.TotalSeconds -lt $burnSec) {
            Start-Sleep -Milliseconds 1000
            $tick++
            Set-SdProgressText ('Test CPU: obciążenie wszystkich wątków... {0}/{1} s' -f [int]$sw.Elapsed.TotalSeconds, $burnSec)
            if ($pdh) {
                [void]$pdh.Collect()
                $v = $pdh.Get($iFreq); if (-not [double]::IsNaN($v)) { [void]$freq.Add($v) }
                $v = $pdh.Get($iLoad); if (-not [double]::IsNaN($v)) { [void]$load.Add($v) }
            }
            if (($tick % 3) -eq 0) {
                $th = & $readThermal
                if ($null -ne $th.TempC) { [void]$temps.Add($th.TempC) }
                if ($null -ne $th.PassiveLimit) { [void]$passive.Add($th.PassiveLimit) }
                $reasons = $reasons -bor [int]$th.Reasons
                if ($freq.Count -eq 0) {
                    # awaryjnie: WMI zamiast PDH
                    $pi = Get-Cim Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" | Select-Object -First 1
                    if ($pi) { [void]$freq.Add([double]$pi.PercentOfMaximumFrequency) }
                }
            }
            if ($global:SD.Cancel) { break }
        }
    } finally {
        [SdBurn]::Stop()
        if ($pdh) { $pdh.Dispose() }
    }
    if ($freq.Count -lt 8 -or $load.Count -lt 8) {
        Add-Finding 'Test obciążeniowy procesora' -Status info -Value 'Za mało próbek, aby ocenić dławienie (liczniki wydajności niedostępne).'
        return
    }
    $startF = ($freq | Select-Object -Skip 3 -First 6 | Measure-Object -Average).Average
    $endF = ($freq | Select-Object -Last 12 | Measure-Object -Average).Average
    $minF = ($freq | Measure-Object -Minimum).Minimum
    $avgLoad = ($load | Select-Object -Skip 3 | Measure-Object -Average).Average
    $maxTemp = $null; $tempNote = ''
    if ($temps.Count -gt 0) {
        $maxTemp = ($temps | Measure-Object -Maximum).Maximum
        # stały odczyt = czujnik ACPI nie odzwierciedla temperatury rdzeni (częste w laptopach) - nie oceniamy po nim
        if ($temps.Count -ge 3 -and ($maxTemp - ($temps | Measure-Object -Minimum).Minimum) -lt 0.6) {
            $tempNote = 'Odczyt temperatury ACPI był stały podczas całego testu - czujnik nie odzwierciedla temperatury procesora (użyj HWiNFO / HWMonitor).'
            $maxTemp = $null
        }
    }
    $minPassive = 100.0; if ($passive.Count -gt 0) { $minPassive = ($passive | Measure-Object -Minimum).Minimum }
    $drop = $startF - $endF

    $rows = @(
        [pscustomobject]@{ Parametr = 'Średnie obciążenie w trakcie testu'; Wartość = ('{0}%' -f (Format-Num $avgLoad 0)) }
        [pscustomobject]@{ Parametr = 'Taktowanie na początku (% wartości znamionowej)'; Wartość = ('{0}%' -f (Format-Num $startF 0)) }
        [pscustomobject]@{ Parametr = 'Taktowanie pod koniec testu'; Wartość = ('{0}%' -f (Format-Num $endF 0)) }
        [pscustomobject]@{ Parametr = 'Najniższe taktowanie'; Wartość = ('{0}%' -f (Format-Num $minF 0)) }
        [pscustomobject]@{ Parametr = 'Temperatura strefy ACPI w spoczynku / maks.'; Wartość = $(if ($null -ne $maxTemp) { '{0} / {1} °C' -f (Format-Num $idleTemp 0), (Format-Num $maxTemp 0) } else { 'brak odczytu' }) }
        [pscustomobject]@{ Parametr = 'Najniższy limit pasywny (dławienie termiczne)'; Wartość = ('{0}%' -f (Format-Num $minPassive 0)) }
    )
    Add-Table 'Wyniki testu obciążeniowego CPU' -Rows $rows
    $d = @("Czas obciążenia: $burnSec s, wątków: $logical")
    if ($bat) { $d += 'Uwaga: test wykonano przy zasilaniu z baterii - spadek taktowania jest wtedy normalny (oszczędzanie energii).' }
    if ($tempNote) { $d += $tempNote } else { $d += 'Temperatura pochodzi ze strefy ACPI i nie zawsze odpowiada temperaturze rdzeni procesora.' }
    $val = 'obciążenie {0}%, taktowanie {1}% → {2}% (spadek {3} pkt), limit pasywny {4}%' -f (Format-Num $avgLoad 0), (Format-Num $startF 0), (Format-Num $endF 0), (Format-Num $drop 0), (Format-Num $minPassive 0)
    if ($null -ne $maxTemp) { $val += ', maks. temperatura ' + (Format-Num $maxTemp 0) + ' °C' }

    $throttle = ($minPassive -lt 100 -or $reasons -ne 0 -or $drop -gt 25 -or $endF -lt 60)
    if ($avgLoad -lt 80) {
        Add-Finding 'Test obciążeniowy procesora' -Status info -Value $val -Details ($d -join "`n") -Advice 'Nie udało się w pełni obciążyć procesora (inne procesy lub ograniczenia mocy) - wynik jest orientacyjny.'
    } elseif ($null -ne $maxTemp -and $maxTemp -ge 95) {
        Add-Finding 'Test obciążeniowy procesora' -Status crit -Value $val -Details ($d -join "`n") -Advice 'Krytycznie wysoka temperatura pod obciążeniem. Oczyść chłodzenie, wymień pastę termoprzewodzącą, sprawdź wentylatory i przepływ powietrza.'
    } elseif ($throttle -and -not $bat) {
        Add-Finding 'Test obciążeniowy procesora' -Status warn -Value $val -Details ($d -join "`n") `
            -Advice 'Procesor zwalnia pod obciążeniem (dławienie termiczne lub limit mocy). Oczyść układ chłodzenia, wymień pastę termoprzewodzącą, sprawdź zasilacz (moc) i plan zasilania.'
    } elseif ($throttle) {
        Add-Finding 'Test obciążeniowy procesora' -Status info -Value $val -Details ($d -join "`n") -Advice 'Powtórz test przy podłączonym zasilaniu sieciowym, aby ocenić prawdziwe dławienie termiczne.'
    } else {
        Add-Finding 'Test obciążeniowy procesora' -Status ok -Value $val -Details ($d -join "`n")
    }
}

Register-Check -Id 'tt.net' -Category 'tests' -Title 'Test prędkości pobierania' -Level Test -NeedsInternet -Script {
    $servers = @(
        @{ Name = 'Cloudflare'; Url = 'https://speed.cloudflare.com/__down?bytes=30000000' }
        @{ Name = 'Cloudflare (alt.)'; Url = 'https://speed.cloudflare.com/__down?bytes=15000000' }
        @{ Name = 'ThinkBroadband'; Url = 'http://ipv4.download.thinkbroadband.com/20MB.zip' }
    )
    try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls } catch { }
    foreach ($s in $servers) {
        Set-SdProgressText ('Test prędkości: pobieranie z ' + $s.Name + '...')
        $total = 0L; $sw = $null; $err = ''; $ttfb = 0
        try {
            $req = [System.Net.WebRequest]::Create($s.Url)
            $req.Timeout = 6000; $req.ReadWriteTimeout = 6000
            $t0 = [System.Diagnostics.Stopwatch]::StartNew()
            $resp = $req.GetResponse()
            $ttfb = $t0.ElapsedMilliseconds
            $stream = $resp.GetResponseStream()
            $buf = New-Object byte[] 65536
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 10) {
                $n = $stream.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }
                $total += $n
            }
            $sw.Stop(); $stream.Close(); $resp.Close()
        } catch { $err = $_.Exception.Message }
        if ($total -gt 500000 -and $sw -and $sw.Elapsed.TotalSeconds -gt 0.5) {
            $mbps = ($total * 8 / 1e6) / $sw.Elapsed.TotalSeconds
            $st = 'ok'; $adv = ''
            if ($mbps -lt 5) { $st = 'warn'; $adv = 'Bardzo niska prędkość pobierania - porównaj z pakietem u operatora, sprawdź Wi-Fi/kabel, inne urządzenia w sieci i router.' }
            elseif ($mbps -lt 25) { $st = 'info' }
            Add-Finding 'Test prędkości pobierania' -Status $st -Value ('{0} Mb/s (pobrano {1} w {2} s; serwer: {3}; opóźnienie odpowiedzi {4} ms)' -f (Format-Num $mbps 0), (Format-Size $total 1), (Format-Num $sw.Elapsed.TotalSeconds 1), $s.Name, $ttfb) -Advice $adv
            return
        }
    }
    Add-Finding 'Test prędkości pobierania' -Status warn -Value 'Nie udało się pobrać danych testowych z żadnego serwera.' `
        -Advice 'Brak internetu, blokada przez zaporę/proxy lub filtr. Wynik testów łączności znajdziesz w kategorii Sieć.'
}

Register-Check -Id 'tt.volscan' -Category 'tests' -Title 'Skan systemu plików NTFS (online, tylko odczyt)' -Level Test -NeedsAdmin -Script {
    if (-not (Get-Command Repair-Volume -ErrorAction SilentlyContinue)) { Add-Finding 'Skan NTFS' -Status skip -Value 'Polecenie Repair-Volume niedostępne.'; return }
    $letter = $env:SystemDrive.TrimEnd(':')
    Set-SdProgressText ("Skan NTFS wolumenu {0}: może potrwać kilka minut..." -f $env:SystemDrive)
    $res = $null
    try { $res = Repair-Volume -DriveLetter $letter -Scan -ErrorAction Stop } catch { Add-Finding 'Skan NTFS' -Status error -Value ('Błąd: ' + (Limit-Text $_.Exception.Message 140)); return }
    $s = [string]$res
    if ($s -eq 'NoErrorsFound') { Add-Finding ('Skan NTFS ' + $env:SystemDrive) -Status ok -Value 'Nie wykryto błędów systemu plików' }
    else { Add-Finding ('Skan NTFS ' + $env:SystemDrive) -Status warn -Value ('Wynik: ' + $s) -Advice 'Zaplanuj naprawę (chkdsk /f) po wykonaniu kopii danych i sprawdzeniu stanu SMART dysku.' }
}

Register-Check -Id 'tt.dism' -Category 'tests' -Title 'Pełna weryfikacja magazynu składników (DISM ScanHealth)' -Level Test -NeedsAdmin -Script {
    if (-not (Get-Command Repair-WindowsImage -ErrorAction SilentlyContinue)) { Add-Finding 'DISM ScanHealth' -Status skip -Value 'Polecenie Repair-WindowsImage niedostępne.'; return }
    Set-SdProgressText 'DISM ScanHealth: może potrwać kilka minut...'
    $r = $null
    try { $r = Repair-WindowsImage -Online -ScanHealth -ErrorAction Stop } catch { Add-Finding 'DISM ScanHealth' -Status error -Value ('Błąd: ' + (Limit-Text $_.Exception.Message 140)); return }
    $s = [string]$r.ImageHealthState
    switch ($s) {
        'Healthy'    { Add-Finding 'DISM ScanHealth' -Status ok -Value 'Magazyn składników jest zdrowy' }
        'Repairable' { Add-Finding 'DISM ScanHealth' -Status warn -Value 'Wykryto uszkodzenia możliwe do naprawy' -Advice 'Uruchom DISM /Online /Cleanup-Image /RestoreHealth, następnie sfc /scannow i uruchom ponownie komputer.' }
        default      { Add-Finding 'DISM ScanHealth' -Status crit -Value ('Stan: ' + $s) -Advice 'Uszkodzeń nie da się naprawić online - użyj nośnika instalacyjnego jako źródła naprawy lub zainstaluj system z zachowaniem plików.' }
    }
}
