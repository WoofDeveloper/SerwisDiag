# SerwisDiag - informacje o programie: aktualność bazy wiedzy i sprawdzanie nowej wersji.
# Baza wiedzy (data\lifecycle.psd1: okresy wsparcia Windows, ESU) starzeje się - ta sama wersja programu używana przez
# rok podawałaby klientom nieaktualne daty. Pobieranie i instalację nowej wersji obsługuje lib\Update.ps1.

$global:SdKnowledgeMaxDays = 183   # po tylu dniach od weryfikacji danych program przypomina o nowej wersji

function Get-SdKnowledgeInfo {
    # Data weryfikacji bazy wiedzy i jej wiek. Stale = dane starsze niż ok. pół roku.
    param([datetime]$Now = (Get-Date))
    $r = [pscustomobject]@{ Date = $null; AgeDays = -1; Stale = $false; Text = 'brak danych' }
    $lc = Get-SdData 'lifecycle'
    $d = [datetime]::MinValue
    if ($lc -and [datetime]::TryParseExact([string]$lc.Verified, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) {
        $r.Date = $d
        $r.AgeDays = [int][math]::Floor(($Now.Date - $d).TotalDays)
        # zegar cofnięty (np. rozładowana bateria płyty głównej) daje wiek ujemny - wtedy nie ostrzegamy
        $r.Stale = ($r.AgeDays -gt $global:SdKnowledgeMaxDays)
        $r.Text = 'stan na ' + $d.ToString('dd.MM.yyyy')
        if ($r.Stale) {
            $m = [int][math]::Floor($r.AgeDays / 30.44)
            $r.Text += ' - ponad ' + (Format-Count $m 'miesiąc' 'miesiące' 'miesięcy') + ', pobierz nową wersję programu'
        }
    }
    return $r
}

function Get-SdGitHubRepo {
    # 'https://github.com/konto/repo' -> 'konto/repo'; inny adres -> ''.
    param([string]$Url)
    if ([string]$Url -match '^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$') { return ($Matches[1] + '/' + $Matches[2]) }
    return ''
}

function ConvertTo-SdVersion {
    # 'v1.2.3', '1.2', 'SerwisDiag-1.2.0' -> [version]; $null, gdy w tekście nie ma numeru wersji.
    param([string]$Text)
    if ([string]$Text -match '(\d+)\.(\d+)(?:\.(\d+))?') {
        $b = 0
        if ($Matches[3]) { $b = [int]$Matches[3] }
        return (New-Object System.Version([int]$Matches[1], [int]$Matches[2], $b))
    }
    return $null
}

function Get-SdLatestRelease {
    # Najnowsze wydanie projektu na GitHubie. -Json: odpowiedź podana z zewnątrz (testy).
    # Wynik: Ok; Latest (numer); Newer (czy nowsza od uruchomionej); Url (strona wydania); Error; Notes (opis wydania);
    # adresy plików wydania: Setup (instalator), SetupName, SetupSha (jego suma SHA-256), Zip, ZipSha.
    param([string]$ProjectUrl = $global:SdProjectUrl, [int]$TimeoutSec = 8, [string]$Json = '')
    $r = [pscustomobject]@{ Ok = $false; Latest = ''; Newer = $false; Url = ''; Error = ''; Notes = ''; Setup = ''; SetupName = ''; SetupSha = ''; Zip = ''; ZipSha = '' }
    $repo = Get-SdGitHubRepo $ProjectUrl
    if (-not $repo) { $r.Error = 'Nie ustawiono adresu strony projektu na GitHubie.'; return $r }
    if (-not $Json) {
        try {
            # TLS 1.2 nie jest domyślnie włączony w .NET 4.5 (Windows 8 / 8.1)
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            $req = [System.Net.HttpWebRequest]::Create('https://api.github.com/repos/' + $repo + '/releases/latest')
            $req.UserAgent = 'SerwisDiag/' + $global:SdVersion
            $req.Accept = 'application/vnd.github+json'
            $req.Timeout = $TimeoutSec * 1000
            $resp = $req.GetResponse()
            try {
                $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
                $Json = $sr.ReadToEnd()
            } finally { $resp.Close() }
        } catch {
            $ex = $_.Exception
            while ($ex.InnerException) { $ex = $ex.InnerException }
            if ([string]$ex.Message -match '\(404\)') { $r.Error = 'Projekt nie ma jeszcze opublikowanych wydań.' }
            else { $r.Error = 'Nie udało się połączyć z GitHubem: ' + $ex.Message }
            return $r
        }
    }
    $o = $null
    try { $o = $Json | ConvertFrom-Json } catch { }
    if (-not $o -or -not $o.PSObject.Properties['tag_name']) { $r.Error = 'Niezrozumiała odpowiedź serwera.'; return $r }
    $latest = ConvertTo-SdVersion ([string]$o.tag_name)
    if (-not $latest) { $r.Error = 'Nie rozpoznano numeru wersji: ' + [string]$o.tag_name; return $r }
    $cur = ConvertTo-SdVersion $global:SdVersion
    $r.Ok = $true
    $r.Latest = $latest.ToString()
    $r.Newer = [bool]($cur -and $latest -gt $cur)
    $r.Url = $(if ($o.PSObject.Properties['html_url'] -and $o.html_url) { [string]$o.html_url } else { $ProjectUrl.TrimEnd('/') + '/releases' })
    if ($o.PSObject.Properties['body'] -and $o.body) { $r.Notes = Limit-Text ([string]$o.body) 1500 }
    if ($o.PSObject.Properties['assets']) {
        foreach ($a in @($o.assets)) {
            if ($null -eq $a) { continue }
            $nm = [string]$a.name; $u = [string]$a.browser_download_url
            if ($nm -match '-setup\.exe$') { $r.SetupName = $nm; $r.Setup = $u }
            elseif ($nm -match '-setup\.exe\.sha256$') { $r.SetupSha = $u }
            elseif ($nm -match '\.zip$') { $r.Zip = $u }
            elseif ($nm -match '\.zip\.sha256$') { $r.ZipSha = $u }
        }
    }
    return $r
}

function Get-SdLatestReleaseText {
    # Komunikat dla użytkownika z wyniku Get-SdLatestRelease.
    param($Release)
    if (-not $Release.Ok) { return $Release.Error }
    if ($Release.Newer) { return ('Dostępna jest nowsza wersja: {0} (masz {1}). Strona wydania: {2}' -f $Release.Latest, $global:SdVersion, $Release.Url) }
    return ('Masz najnowszą wersję ({0}).' -f $global:SdVersion)
}
