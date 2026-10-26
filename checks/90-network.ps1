# Testy kategorii: Sieć

function Get-SdNetAdapters {
    Get-SdCached 'NetAdapters' {
        $ad = @(Get-Cim Win32_NetworkAdapter -Filter 'PhysicalAdapter=True')
        $cfg = @(Get-Cim Win32_NetworkAdapterConfiguration)
        $statusMap = @{ 0 = 'rozłączony'; 1 = 'łączenie'; 2 = 'połączony'; 3 = 'rozłączanie'; 4 = 'brak sprzętu'; 5 = 'wyłączony'; 6 = 'awaria sprzętu'; 7 = 'brak kabla / sieci'; 8 = 'uwierzytelnianie'; 9 = 'uwierzytelniony'; 10 = 'błąd uwierzytelniania'; 11 = 'nieprawidłowy adres'; 12 = 'wymagane poświadczenia' }
        $out = @()
        foreach ($a in $ad) {
            $c = $cfg | Where-Object { $_.Index -eq $a.Index } | Select-Object -First 1
            $name = [string]$a.Name
            $isWifi = ($name -match 'Wi-?Fi|Wireless|802\.11|WLAN|Bezprzewod' -or [string]$a.NetConnectionID -match 'Wi-?Fi|WLAN|Wireless|Bezprzewod')
            $isVirtual = ($name -match 'Virtual|VPN|TAP|TUN|WireGuard|Hyper-V|VMware|VirtualBox|Bluetooth|Loopback|Proton|vEthernet|Miniport|AnyConnect|Fortinet|PANGP|Juniper|SonicWall|OpenVPN|ZeroTier|Tailscale|NordLynx|Wintun|Npcap')
            $ips = @(); $gw = @(); $dns = @()
            if ($c) {
                if ($c.IPAddress) { $ips = @($c.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }) }
                # 0.0.0.0 to trasa "na łączu" (np. VPN), a nie adres routera
                if ($c.DefaultIPGateway) { $gw = @($c.DefaultIPGateway | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -ne '0.0.0.0' }) }
                if ($c.DNSServerSearchOrder) { $dns = @($c.DNSServerSearchOrder) }
            }
            $statusCode = -1
            if ($null -ne $a.NetConnectionStatus) { $statusCode = [int]$a.NetConnectionStatus }
            $statusTxt = 'nieznany'
            if ($statusMap.ContainsKey($statusCode)) { $statusTxt = $statusMap[$statusCode] }
            $ifIndex = 0
            if ($null -ne $a.InterfaceIndex) { $ifIndex = [int]$a.InterfaceIndex }
            $out += [pscustomobject]@{
                Index = [int]$a.Index; IfIndex = $ifIndex; Name = $name; Connection = [string]$a.NetConnectionID; Wifi = $isWifi; Virtual = $isVirtual
                StatusCode = $statusCode; Status = $statusTxt
                SpeedBps = $(if ($a.Speed) { [double]$a.Speed } else { 0.0 }); Mac = [string]$a.MACAddress
                Ip = $ips; Gateway = $gw; Dns = $dns; Dhcp = $(if ($c) { [bool]$c.DHCPEnabled } else { $false })
                Manufacturer = [string]$a.Manufacturer
            }
        }
        $out
    }
}

function Get-SdDefaultRoutes {
    # Trasy domyślne IPv4 (0.0.0.0/0) z łączną metryką (trasa + interfejs) - tę o najniższej Windows wybiera do ruchu.
    $out = @()
    if (Get-Command Get-NetRoute -ErrorAction SilentlyContinue) {
        try {
            $ifm = @{}
            foreach ($i in @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction Stop)) { $ifm[[int]$i.ifIndex] = [int]$i.InterfaceMetric }
            foreach ($r in @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop)) {
                $out += [pscustomobject]@{ IfIndex = [int]$r.ifIndex; NextHop = [string]$r.NextHop; Metric = [int]$r.RouteMetric + [int]$ifm[[int]$r.ifIndex] }
            }
        } catch { Write-SdLog ('Trasy domyślne: ' + $_.Exception.Message) 'INFO' }
    }
    if ($out.Count -eq 0) {
        foreach ($r in (Get-Cim Win32_IP4RouteTable -Filter "Destination='0.0.0.0' AND Mask='0.0.0.0'")) {
            $out += [pscustomobject]@{ IfIndex = [int]$r.InterfaceIndex; NextHop = [string]$r.NextHop; Metric = [int]$r.Metric1 }
        }
    }
    return $out
}

function Select-SdGateway {
    # Brama lokalnego routera do testu pingu: trasa domyślna o najniższej metryce na połączonej karcie fizycznej.
    # VPN (karta wirtualna lub brama 0.0.0.0) nie jest routerem klienta. Bez danych o trasach - pierwsza brama karty fizycznej.
    param($Adapters, $Routes)
    $phys = @($Adapters | Where-Object { $_.StatusCode -eq 2 -and -not $_.Virtual })
    $cand = @()
    foreach ($r in @($Routes)) {
        if (-not $r -or -not $r.NextHop -or $r.NextHop -eq '0.0.0.0' -or $r.NextHop -notmatch '^\d+\.\d+\.\d+\.\d+$') { continue }
        if (@($phys | Where-Object { $_.IfIndex -eq $r.IfIndex }).Count -gt 0) { $cand += $r }
    }
    if ($cand.Count -gt 0) { return [string]($cand | Sort-Object Metric | Select-Object -First 1).NextHop }
    foreach ($a in $phys) { foreach ($g in @($a.Gateway)) { if ($g -and $g -ne '0.0.0.0') { return [string]$g } } }
    return ''
}

function Test-SdPingBurst {
    # Zwraca dla każdego celu: @{ Sent; Received; LossPct; Avg; Min; Max; Jitter }.
    param([string[]]$Targets, [int]$Count = 4, [int]$TimeoutMs = 1500)
    $rtt = @{}; $sent = @{}
    foreach ($t in $Targets) { $rtt[$t] = New-Object System.Collections.ArrayList; $sent[$t] = 0 }
    for ($i = 0; $i -lt $Count; $i++) {
        $tasks = @{}
        $pingers = @()
        foreach ($t in $Targets) {
            $p = New-Object System.Net.NetworkInformation.Ping
            $pingers += $p
            try { $tasks[$t] = $p.SendPingAsync($t, $TimeoutMs) } catch { $tasks[$t] = $null }
            $sent[$t]++
        }
        $arr = @($tasks.Values | Where-Object { $_ })
        if ($arr.Count -gt 0) { try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$arr, $TimeoutMs + 1500) } catch { } }
        foreach ($t in $Targets) {
            $task = $tasks[$t]
            if ($task -and $task.IsCompleted -and -not $task.IsFaulted -and -not $task.IsCanceled) {
                $r = $task.Result
                if ($r -and $r.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { [void]$rtt[$t].Add([double]$r.RoundtripTime) }
            }
        }
        foreach ($p in $pingers) { try { $p.Dispose() } catch { } }
        if ($i -lt ($Count - 1)) { Start-Sleep -Milliseconds 200 }
    }
    $res = @{}
    foreach ($t in $Targets) {
        $l = $rtt[$t]; $n = $l.Count
        $avg = $null; $min = $null; $max = $null; $jit = $null
        if ($n -gt 0) {
            $avg = ($l | Measure-Object -Average).Average; $min = ($l | Measure-Object -Minimum).Minimum; $max = ($l | Measure-Object -Maximum).Maximum
            if ($n -gt 1) { $d = 0.0; for ($k = 1; $k -lt $n; $k++) { $d += [math]::Abs($l[$k] - $l[$k - 1]) }; $jit = $d / ($n - 1) } else { $jit = 0.0 }
        }
        $res[$t] = [pscustomobject]@{ Sent = $sent[$t]; Received = $n; LossPct = (100.0 * ($sent[$t] - $n) / [math]::Max($sent[$t], 1)); Avg = $avg; Min = $min; Max = $max; Jitter = $jit }
    }
    return $res
}

Register-Check -Id 'nw.adapters' -Category 'network' -Title 'Karty sieciowe i konfiguracja IP' -Script {
    $ad = @(Get-SdNetAdapters)
    if ($ad.Count -eq 0) {
        Add-Finding 'Karty sieciowe' -Status warn -Value 'Nie wykryto fizycznej karty sieciowej' `
            -Advice 'Sprawdź w Menedżerze urządzeń i BIOS, czy karta sieciowa jest włączona i ma zainstalowany sterownik.'
        return
    }
    $rows = @()
    foreach ($a in $ad) {
        $typ = if ($a.Wifi) { 'Wi-Fi' } elseif ($a.Virtual) { 'wirtualna/VPN' } else { 'Ethernet' }
        $spd = '-'
        if ($a.SpeedBps -gt 0) { $spd = (Format-Num ($a.SpeedBps / 1e6) 0) + ' Mb/s' }
        $rows += [pscustomobject]@{
            Karta = $a.Connection; Opis = $a.Name; Typ = $typ; Stan = $a.Status; 'Prędkość' = $spd
            IPv4 = ($a.Ip -join ', '); Brama = ($a.Gateway -join ', '); DNS = ($a.Dns -join ', '); DHCP = $(if ($a.Dhcp) { 'tak' } else { 'nie' }); MAC = $a.Mac
        }
    }
    Add-Table 'Karty sieciowe' -Rows $rows

    $connected = @($ad | Where-Object { $_.StatusCode -eq 2 })
    $offline = Test-SdOffline
    if ($connected.Count -eq 0) {
        Add-Finding 'Połączenie sieciowe' -Status $(if ($offline) { 'info' } else { 'warn' }) -Value ('Brak aktywnego połączenia sieciowego' + $(if ($offline) { ' (diagnostyka w trybie bez internetu)' } else { '' })) `
            -Details (($ad | ForEach-Object { '{0}: {1}' -f $_.Connection, $_.Status }) -join "`n") `
            -Advice $(if ($offline) { '' } else { 'Sprawdź kabel / włącznik Wi-Fi, tryb samolotowy, sterownik karty oraz router.' })
    } else {
        $d = @($connected | ForEach-Object {
                $gwTxt = ''
                if ($_.Gateway.Count) { $gwTxt = ' brama ' + ($_.Gateway -join ', ') }
                '{0} ({1}): {2}{3}' -f $_.Connection, $_.Name, ($_.Ip -join ', '), $gwTxt
            })
        Add-Finding 'Połączenie sieciowe' -Status ok -Value ('Aktywne: ' + (($connected | ForEach-Object { $_.Connection }) -join ', ')) -Details ($d -join "`n")
    }
    foreach ($a in $connected) {
        $apipa = @($a.Ip | Where-Object { $_ -like '169.254.*' })
        if ($apipa.Count -gt 0) {
            Add-Finding ('Adres IP karty ' + $a.Connection) -Status crit -Value ('Adres APIPA: ' + ($apipa -join ', ')) `
                -Details 'Karta nie uzyskała adresu z serwera DHCP, więc system nadał sobie adres awaryjny 169.254.x.x.' `
                -Advice 'Sprawdź router/serwer DHCP, kabel i port; wykonaj „ipconfig /release” i „ipconfig /renew”; zrestartuj router.'
        }
        elseif (-not $a.Virtual -and $a.Ip.Count -gt 0 -and $a.Gateway.Count -eq 0) {
            Add-Finding ('Brama domyślna karty ' + $a.Connection) -Status $(if ($offline) { 'info' } else { 'warn' }) -Value 'Brak bramy domyślnej' -Advice 'Bez bramy domyślnej komputer nie wyjdzie poza sieć lokalną - sprawdź konfigurację IP/DHCP.'
        }
        if (-not $a.Wifi -and -not $a.Virtual -and $a.SpeedBps -gt 0 -and $a.SpeedBps -le 100e6 -and $a.Name -match 'Gigabit|GbE|1000|Gb') {
            Add-Finding ('Prędkość łącza ' + $a.Connection) -Status warn -Value ('{0} Mb/s przy karcie gigabitowej' -f (Format-Num ($a.SpeedBps / 1e6) 0)) `
                -Advice 'Łącze działa z prędkością 100 Mb/s - wymień kabel (uszkodzone żyły / kategoria poniżej 5e), sprawdź gniazdo i port routera.'
        }
    }
    foreach ($a in @($ad | Where-Object { $_.StatusCode -in @(5, 6) })) {
        Add-Finding ('Karta ' + $a.Connection) -Status info -Value $a.Status -Advice 'Karta jest wyłączona lub zgłasza awarię sprzętu - włącz ją w Połączeniach sieciowych (ncpa.cpl) lub sprawdź sterownik.'
    }
}

Register-Check -Id 'nw.wifi' -Category 'network' -Title 'Połączenie Wi-Fi' -Script {
    $ad = @(Get-SdNetAdapters | Where-Object { $_.Wifi -and $_.StatusCode -eq 2 })
    if ($ad.Count -eq 0) { return }
    $r = Invoke-Native -File (Join-Path $env:SystemRoot 'System32\netsh.exe') -Arguments 'wlan show interfaces' -TimeoutSec 15
    $pairs = @()
    foreach ($line in ($r.StdOut -split "`r?`n")) {
        if ($line -match '^\s*(.+?)\s*:\s+(.+?)\s*$') { $pairs += [pscustomobject]@{ Key = $Matches[1]; Val = $Matches[2] } }
    }
    $ssid = ($pairs | Where-Object { $_.Key -eq 'SSID' } | Select-Object -First 1).Val
    $signal = ($pairs | Where-Object { $_.Val -match '^\d{1,3}%$' } | Select-Object -First 1).Val
    $radio = ($pairs | Where-Object { $_.Val -match '^802\.11[a-z/ ]*$' } | Select-Object -First 1).Val
    $channel = ($pairs | Where-Object { $_.Key -match '^(Channel|Kana)' } | Select-Object -First 1).Val
    $rates = @($pairs | Where-Object { $_.Key -match '\((Mbps|Mb/s)\)' } | ForEach-Object { $_.Val })
    if (-not $signal) {
        Add-Finding 'Wi-Fi: sygnał' -Status info -Value 'Nie udało się odczytać parametrów (np. brak dostępu do lokalizacji dla netsh w nowych wersjach Windows)'
        return
    }
    $pct = [int]($signal.TrimEnd('%'))
    $band = ''
    $ch = 0
    if ($channel -and [int]::TryParse($channel, [ref]$ch)) { if ($ch -le 14) { $band = '2,4 GHz' } else { $band = '5/6 GHz' } }
    $d = @("Sieć (SSID): $ssid", "Sygnał: $signal")
    if ($radio) { $d += "Standard: $radio" }
    if ($channel) { $d += "Kanał: $channel ($band)" }
    if ($rates.Count -ge 2) { $d += "Prędkość odbioru / transmisji: $($rates[0]) / $($rates[1]) Mb/s" }
    $rx = 0.0
    if ($rates.Count -ge 1) { [void][double]::TryParse(($rates[0] -replace ',', '.'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$rx) }
    $val = 'sygnał ' + $pct + '%'
    if ($radio) { $val += ', ' + $radio }
    if ($band) { $val += ', ' + $band }
    if ($pct -lt 40) {
        Add-Finding 'Wi-Fi: jakość połączenia' -Status warn -Value $val -Details ($d -join "`n") `
            -Advice 'Słaby sygnał Wi-Fi: zbliż się do routera, zmień kanał/pasmo (5 GHz), usuń przeszkody, rozważ wzmacniacz lub kabel. W laptopach sprawdź też antenę i sterownik karty.'
    } elseif ($pct -lt 60 -or ($rx -gt 0 -and $rx -lt 54)) {
        Add-Finding 'Wi-Fi: jakość połączenia' -Status info -Value $val -Details ($d -join "`n") -Advice 'Średnia jakość łącza - przy problemach z prędkością rozważ pasmo 5 GHz lub lepsze ustawienie routera.'
    } else {
        Add-Finding 'Wi-Fi: jakość połączenia' -Status ok -Value $val -Details ($d -join "`n")
    }
}

Register-Check -Id 'nw.connectivity' -Category 'network' -Title 'Łączność z internetem, DNS i czas' -Script {
    $conn = @(Get-SdNetAdapters | Where-Object { $_.StatusCode -eq 2 })
    if ($conn.Count -eq 0) {
        Add-Finding 'Test łączności' -Status skip -Value 'Brak aktywnego połączenia sieciowego - testy łączności pominięto.'
        return
    }
    $gw = Select-SdGateway -Adapters $conn -Routes (Get-SdDefaultRoutes)
    $offline = Test-SdOffline
    $targets = @()
    if ($gw) { $targets += $gw }
    if (-not $offline) { $targets += '1.1.1.1'; $targets += '8.8.8.8' }
    $p = @{}
    if ($targets.Count -gt 0) { $p = Test-SdPingBurst -Targets $targets -Count 4 -TimeoutMs 1500 }

    if ($gw) {
        $g = $p[$gw]
        if ($g.Received -eq 0) {
            Add-Finding 'Ping do bramy (routera)' -Status warn -Value "Brak odpowiedzi od $gw" -Details 'Router może blokować ICMP - sprawdź wynik testu internetu poniżej.' `
                -Advice 'Jeśli internet też nie działa: sprawdź kabel/Wi-Fi, zrestartuj router i kartę sieciową.'
        } else {
            $st = 'ok'
            if ($g.LossPct -ge 25) { $st = 'warn' } elseif ($g.Avg -gt 30) { $st = 'info' }
            $adv = ''
            if ($st -eq 'warn') { $adv = 'Utrata pakietów już do routera wskazuje na problem lokalny: kabel, sygnał Wi-Fi lub zakłócenia.' }
            elseif ($st -eq 'info') { $adv = 'Wysokie opóźnienie do routera - zła jakość sygnału Wi-Fi lub przeciążona sieć lokalna.' }
            Add-Finding 'Ping do bramy (routera)' -Status $st -Value ('{0}: śr. {1} ms, utrata pakietów {2}%, jitter {3} ms' -f $gw, (Format-Num $g.Avg 0), (Format-Num $g.LossPct 0), (Format-Num $g.Jitter 0)) -Advice $adv
        }
    }
    if ($offline) {
        # sieć lokalna sprawdzona powyżej; testy internetu nie mają sensu na stanowisku celowo odłączonym od internetu
        Add-Finding 'Łączność z internetem' -Status skip -Value ($global:SdOfflineSkipText + ' Nie sprawdzano: ping do internetu, DNS, HTTP/HTTPS, zegar.')
        return
    }
    $okTargets = @('1.1.1.1', '8.8.8.8' | Where-Object { $p[$_].Received -gt 0 })
    $internetUp = ($okTargets.Count -gt 0)
    if (-not $internetUp) {
        Add-Finding 'Ping do internetu (1.1.1.1, 8.8.8.8)' -Status crit -Value 'Brak odpowiedzi' `
            -Details 'Zapora lub operator mogą blokować ICMP - sprawdź wyniki testów HTTP i DNS poniżej.' -Advice 'Brak łączności z internetem: sprawdź router, kabel/Wi-Fi, ustawienia IP i DNS, proxy oraz zaporę.'
    } else {
        $best = $p[$okTargets[0]]
        $lossMax = ($okTargets | ForEach-Object { $p[$_].LossPct } | Measure-Object -Maximum).Maximum
        $st = 'ok'
        if ($lossMax -ge 25 -or $best.Avg -gt 120) { $st = 'warn' } elseif ($best.Avg -gt 60) { $st = 'info' }
        $adv = ''
        if ($st -eq 'warn') { $adv = 'Wysokie opóźnienie lub utrata pakietów do internetu - sprawdź jakość łącza, Wi-Fi, obciążenie sieci i usługodawcę.' }
        Add-Finding 'Ping do internetu (1.1.1.1, 8.8.8.8)' -Status $st -Value ('śr. {0} ms, utrata pakietów do {1}%, jitter {2} ms' -f (Format-Num $best.Avg 0), (Format-Num $lossMax 0), (Format-Num $best.Jitter 0)) -Advice $adv
    }

    # DNS (z limitem czasu)
    $dnsRes = @()
    foreach ($h in 'www.microsoft.com', 'www.google.com') {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ok = $false
        try {
            $t = [System.Net.Dns]::GetHostAddressesAsync($h)
            if ($t.Wait(5000) -and -not $t.IsFaulted) { $ok = ($t.Result.Count -gt 0) }
        } catch { }
        $sw.Stop()
        $dnsRes += [pscustomobject]@{ Host = $h; Ok = $ok; Ms = $sw.ElapsedMilliseconds }
    }
    $dnsOk = @($dnsRes | Where-Object { $_.Ok }).Count
    $txt = ($dnsRes | ForEach-Object { '{0}: {1}' -f $_.Host, $(if ($_.Ok) { "$($_.Ms) ms" } else { 'BŁĄD' }) }) -join '; '
    if ($dnsOk -eq 0) {
        $st = if ($internetUp) { 'crit' } else { 'warn' }
        $det = ''
        if ($internetUp) { $det = 'Ping po adresie IP działa, a nazwy nie są rozpoznawane - problem z DNS.' }
        Add-Finding 'Rozpoznawanie nazw (DNS)' -Status $st -Value ('Nie działa: ' + $txt) -Details $det `
            -Advice 'Sprawdź serwery DNS w ustawieniach karty (ustaw 1.1.1.1 / 8.8.8.8 jako test), wykonaj „ipconfig /flushdns”; sprawdź plik hosts, VPN i proxy.'
    } elseif ($dnsOk -lt $dnsRes.Count) {
        Add-Finding 'Rozpoznawanie nazw (DNS)' -Status warn -Value $txt -Advice 'Część nazw nie jest rozpoznawana - sprawdź serwery DNS i plik hosts.'
    } else {
        $slow = @($dnsRes | Where-Object { $_.Ms -gt 800 }).Count
        $st = 'ok'; $adv = ''
        if ($slow -gt 0) { $st = 'info'; $adv = 'Wolne odpowiedzi DNS - rozważ szybszy serwer DNS (np. 1.1.1.1).' }
        Add-Finding 'Rozpoznawanie nazw (DNS)' -Status $st -Value $txt -Advice $adv
    }

    # sonda HTTP (NCSI) i HTTPS + różnica czasu
    $probe = {
        param($url)
        $res = [pscustomobject]@{ Ok = $false; Code = 0; Body = ''; Date = $null; Error = '' }
        try {
            try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls } catch { }
            $req = [System.Net.WebRequest]::Create($url)
            $req.Timeout = 6000
            $req.AllowAutoRedirect = $false
            $resp = $req.GetResponse()
            $res.Code = [int]$resp.StatusCode
            $res.Date = $resp.Headers['Date']
            $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $res.Body = $sr.ReadToEnd()
            $sr.Close(); $resp.Close()
            $res.Ok = $true
        } catch [System.Net.WebException] {
            $res.Error = $_.Exception.Message
            if ($_.Exception.Response) { $res.Code = [int]$_.Exception.Response.StatusCode; $res.Date = $_.Exception.Response.Headers['Date']; $res.Ok = $true }
        } catch { $res.Error = $_.Exception.Message }
        return $res
    }
    $http = & $probe 'http://www.msftconnecttest.com/connecttest.txt'
    if (-not $http.Ok) {
        $st = if ($internetUp) { 'warn' } else { 'crit' }
        Add-Finding 'Dostęp do internetu (HTTP)' -Status $st -Value ('Brak odpowiedzi: ' + (Limit-Text $http.Error 90)) `
            -Advice 'Brak dostępu HTTP: sprawdź proxy (Ustawienia > Sieć > Serwer proxy), zaporę, VPN oraz DNS.'
    } elseif ($http.Body.Trim() -eq 'Microsoft Connect Test') {
        Add-Finding 'Dostęp do internetu (HTTP)' -Status ok -Value 'Test Microsoft Connect: poprawny'
    } else {
        Add-Finding 'Dostęp do internetu (HTTP)' -Status warn -Value ('Nieoczekiwana odpowiedź (HTTP {0})' -f $http.Code) -Details 'Odpowiedź różni się od oczekiwanej - możliwy portal logowania (hotspot), proxy lub filtrowanie treści.' `
            -Advice 'Otwórz przeglądarkę i zaloguj się do sieci (portal przechwytujący) albo sprawdź ustawienia proxy/filtra.'
    }
    # HTTPS: kilka niezależnych celów. .NET Framework nie ma "Happy Eyeballs", więc pojedyncza witryna
    # z uszkodzoną trasą IPv6 potrafi się zawiesić - pojedyncze niepowodzenie nie świadczy o awarii internetu.
    $httpsTargets = 'https://www.cloudflare.com/', 'https://www.google.com/generate_204', 'https://www.microsoft.com/'
    $httpsOk = $null; $failed = @()
    foreach ($u in $httpsTargets) {
        $r = & $probe $u
        if ($r.Ok) { $httpsOk = $r; break } else { $failed += (($u -replace '^https://([^/]+)/.*$', '$1') + ': ' + (Limit-Text $r.Error 60)) }
    }
    if ($httpsOk) {
        $skew = $null
        if ($httpsOk.Date) {
            $sd = [datetime]::MinValue
            if ([datetime]::TryParse([string]$httpsOk.Date, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$sd)) { $skew = ([datetime]::UtcNow - $sd).TotalMinutes }
        }
        if ($null -ne $skew -and [math]::Abs($skew) -gt 5) {
            Add-Finding 'Zegar systemowy' -Status warn -Value ('Różnica względem serwera: {0} min' -f (Format-Num $skew 0)) `
                -Details 'Błędny czas psuje działanie certyfikatów HTTPS, logowania do usług i aktualizacji.' `
                -Advice 'Ustaw poprawną datę/strefę czasową i zsynchronizuj czas (Ustawienia > Czas i język > Synchronizuj teraz). Sprawdź baterię CMOS na płycie głównej, jeśli zegar się resetuje.'
        } elseif ($null -ne $skew) {
            Add-Finding 'Zegar systemowy' -Status ok -Value ('Różnica względem serwera: {0} min' -f (Format-Num $skew 1))
        }
        $det = ''
        if ($failed.Count -gt 0) { $det = 'Nie odpowiedziały (przy poprawnej łączności z pozostałymi): ' + ($failed -join '; ') + "`nPojedyncze witryny mogą nie działać np. przez uszkodzoną trasę IPv6 lub VPN." }
        Add-Finding 'Dostęp do internetu (HTTPS)' -Status ok -Value 'Połączenie szyfrowane działa' -Details $det
    } else {
        $st = if ($http.Ok) { 'warn' } else { 'info' }
        Add-Finding 'Dostęp do internetu (HTTPS)' -Status $st -Value 'Brak połączenia szyfrowanego z żadnym z testowanych serwerów' -Details ($failed -join "`n") `
            -Advice 'Jeśli HTTP działa, a HTTPS nie: sprawdź datę i czas, certyfikaty główne, antywirus filtrujący HTTPS oraz obsługę TLS 1.2 w systemie.'
    }
}

Register-Check -Id 'nw.config' -Category 'network' -Title 'Proxy, DNS i plik hosts' -Script {
    # Proxy
    $is = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $pe = Get-RegValue $is 'ProxyEnable' 0
    $ps = Get-RegValue $is 'ProxyServer' ''
    $pac = Get-RegValue $is 'AutoConfigURL' ''
    if ([int]$pe -eq 1 -and $ps) {
        Add-Finding 'Serwer proxy' -Status warn -Value ('Włączony: ' + $ps) -Details 'Ręcznie skonfigurowany proxy bywa pozostałością po VPN/oprogramowaniu lub działaniem złośliwego programu.' `
            -Advice 'Jeśli proxy nie jest wymagane, wyłącz je (Ustawienia > Sieć i internet > Serwer proxy); sprawdź także przeglądarki.'
    } elseif ($pac) {
        Add-Finding 'Serwer proxy' -Status info -Value ('Skrypt automatycznej konfiguracji: ' + $pac) -Advice 'Upewnij się, że skrypt PAC jest zamierzony (sieć firmowa).'
    } else {
        Add-Finding 'Serwer proxy' -Status ok -Value 'Brak ręcznego proxy'
    }

    # DNS - niestandardowe serwery
    $dnsAll = @()
    foreach ($a in (Get-SdNetAdapters | Where-Object { $_.StatusCode -eq 2 })) { $dnsAll += $a.Dns }
    $dnsAll = @($dnsAll | Select-Object -Unique)
    if ($dnsAll.Count -gt 0) {
        $known = '1.1.1.1', '1.0.0.1', '8.8.8.8', '8.8.4.4', '9.9.9.9', '149.112.112.112', '208.67.222.222', '208.67.220.220', '94.140.14.14', '94.140.15.15'
        $odd = @($dnsAll | Where-Object { $_ -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.)' -and $known -notcontains $_ })
        $det = ''
        if ($odd.Count -gt 0) { $det = 'Serwery spoza sieci lokalnej i popularnych publicznych usług: ' + ($odd -join ', ') + ' (zwykle DNS operatora - jeśli nie, zweryfikuj).' }
        Add-Finding 'Serwery DNS' -Status info -Value ($dnsAll -join ', ') -Details $det
    }

    # plik hosts
    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    if (Test-Path -LiteralPath $hostsPath) {
        $lines = @(Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*[^#\s]' })
        $custom = @($lines | Where-Object { $_ -notmatch '^\s*(127\.0\.0\.1|::1)\s+localhost\s*$' })
        if ($custom.Count -eq 0) {
            Add-Finding 'Plik hosts' -Status ok -Value 'Domyślny (bez własnych wpisów)'
        } else {
            $susp = @($custom | Where-Object { $_ -match 'microsoft|windowsupdate|google|facebook|paypal|bank|mbank|pekao|ing\.|santander|kaspersky|avast|eset|bitdefender|malwarebytes|norton|mcafee' })
            $st = if ($susp.Count -gt 0) { 'warn' } else { 'info' }
            $d = @("Własne wpisy: $($custom.Count)")
            $d += @($custom | Select-Object -First 12 | ForEach-Object { '  ' + (Limit-Text $_.Trim() 110) })
            if ($custom.Count -gt 12) { $d += '  ...' }
            $adv = 'Przejrzyj plik hosts (C:\Windows\System32\drivers\etc\hosts). Wpisy przekierowujące strony systemu, banków lub antywirusów są typowe dla złośliwego oprogramowania.'
            if ($custom.Count -gt 200) { $adv += ' Bardzo długi plik hosts (listy blokujące) potrafi spowalniać usługę DNS.' }
            $suspTxt = ''
            if ($susp.Count -gt 0) { $suspTxt = '; podejrzane przekierowania: ' + $susp.Count }
            Add-Finding 'Plik hosts' -Status $st -Value ('Własne wpisy: {0}{1}' -f $custom.Count, $suspTxt) -Details ($d -join "`n") -Advice $adv
        }
    }
}

Register-Check -Id 'nw.ports' -Category 'network' -Title 'Porty nasłuchujące' -Level Full -Script {
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) { return }
    $conns = @()
    try { $conns = @(Get-NetTCPConnection -State Listen -ErrorAction Stop) } catch { return }
    $procs = @{}
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) { $procs[[int]$p.Id] = $p.ProcessName }
    $rows = @()
    foreach ($c in ($conns | Sort-Object LocalPort)) {
        $rows += [pscustomobject]@{ Port = $c.LocalPort; Adres = $c.LocalAddress; Proces = $procs[[int]$c.OwningProcess]; PID = $c.OwningProcess }
    }
    $ext = @($rows | Where-Object { $_.Adres -in @('0.0.0.0', '::') })
    Add-Table 'Porty nasłuchujące (TCP)' -Rows $rows
    $risky = @($ext | Where-Object { $_.Port -in @(21, 23, 3389, 5900, 5985, 445, 139) })
    $d = ($risky | ForEach-Object { 'port {0} ({1})' -f $_.Port, $_.Proces }) -join ', '
    if ($risky.Count -gt 0) {
        Add-Finding 'Porty nasłuchujące' -Status info -Value ('Porty dostępne z sieci: {0}; wrażliwe: {1}' -f $ext.Count, $d) `
            -Advice 'Upewnij się, że usługi na wrażliwych portach (RDP 3389, SMB 445, VNC 5900, Telnet 23, FTP 21) są potrzebne i niedostępne z internetu.'
    } else {
        Add-Finding 'Porty nasłuchujące' -Status ok -Value ('Porty nasłuchujące na wszystkich interfejsach: {0}' -f $ext.Count)
    }
}
