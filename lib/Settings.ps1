# SerwisDiag - ustawienia serwisu (nazwa, telefon, technik, logo, katalog raportów)

function Get-SdDefaultSettings {
    return @{
        ShopName   = 'Serwis komputerowy'
        ShopPhone  = ''
        ShopEmail  = ''
        ShopAddress = ''
        Technician = ''
        LogoPath   = ''
        ReportDir  = ''
        Level      = 'Quick'
        # Co otworzyć po diagnostyce: none | customer | technical. Domyślnie nic - raport techniczny zawiera dane
        # prywatne (numery seryjne, klucz OEM, konta), a ekran często ogląda klient.
        OpenAfterScan = 'none'
        AutoPdf       = $false    # po diagnostyce zapisz też raport dla klienta jako PDF
        AutoUpdateCheck = $true   # wersja zainstalowana: raz na dobę sprawdzaj, czy jest nowa wersja (GitHub)
    }
}

function Get-SdSettingsPath {
    param([string]$Root)
    return [System.IO.Path]::Combine($Root, 'config', 'settings.json')
}

function Get-SdSettings {
    param([string]$Root)
    $s = Get-SdDefaultSettings
    $path = Get-SdSettingsPath $Root
    if (Test-Path -LiteralPath $path) {
        try {
            $json = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
            $o = $json | ConvertFrom-Json
            foreach ($p in $o.PSObject.Properties) { if ($s.ContainsKey($p.Name) -and $null -ne $p.Value) { $s[$p.Name] = $p.Value } }
        } catch { Write-SdLog ('Ustawienia: ' + $_.Exception.Message) 'WARN' }
    }
    if (@('none', 'customer', 'technical') -notcontains [string]$s.OpenAfterScan) { $s.OpenAfterScan = 'none' }
    $s.AutoPdf = ($s.AutoPdf -eq $true)
    $s.AutoUpdateCheck = ($s.AutoUpdateCheck -ne $false)
    return $s
}

function Save-SdSettings {
    param([string]$Root, [hashtable]$Settings)
    $path = Get-SdSettingsPath $Root
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $json = ConvertTo-Json -InputObject $Settings -Depth 3
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-SdWritableDir {
    param([string]$Dir)
    try {
        if (-not (Test-Path -LiteralPath $Dir)) { [void](New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop) }
        $t = Join-Path $Dir ('.w' + [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($t, 'x')
        Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

function Test-SdInstalledCopy {
    # Kopia z instalatora (znacznik instalacja.ini zapisuje instalator), a nie przenośna z pendrive'a lub folderu.
    param([string]$Root)
    return (Test-Path -LiteralPath (Join-Path $Root 'instalacja.ini') -PathType Leaf)
}

function Get-SdReportDirCandidates {
    # Kolejno: katalog z ustawień, potem <program>\raporty i Dokumenty\SerwisDiag - w kopii zainstalowanej odwrotnie
    # (folder programu w Program Files to nie miejsce na dane klientów), na końcu %TEMP%\SerwisDiag.
    param([string]$Root, [hashtable]$Settings)
    $cands = @()
    if ($Settings -and $Settings.ReportDir) { $cands += [string]$Settings.ReportDir }
    $docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'SerwisDiag'
    if (Test-SdInstalledCopy $Root) { $cands += $docs; $cands += (Join-Path $Root 'raporty') }
    else { $cands += (Join-Path $Root 'raporty'); $cands += $docs }
    $cands += (Join-Path ([System.IO.Path]::GetTempPath()) 'SerwisDiag')
    return $cands
}

function Resolve-SdReportDir {
    # Pierwszy katalog z listy Get-SdReportDirCandidates, w którym da się zapisać.
    param([string]$Root, [hashtable]$Settings)
    foreach ($c in (Get-SdReportDirCandidates -Root $Root -Settings $Settings)) { if ($c -and (Test-SdWritableDir $c)) { return $c } }
    return [System.IO.Path]::GetTempPath()
}
