# SerwisDiag - kontrola integralności plików programu (manifest sum SHA-256).
# Program zwykle pracuje z pendrive'a podłączanego do wielu, także zainfekowanych komputerów. Kontrola wykrywa
# uszkodzone (wadliwy nośnik) lub zmienione i dopisane pliki programu, zanim zostaną wykonane z uprawnieniami
# administratora. Nie zastąpi nośnika z blokadą zapisu: celowy atak może podmienić także manifest.
# Plik celowo bez zależności od reszty programu - jest ładowany przed pozostałymi modułami.

$global:SdManifestName = 'manifest.sha256'

function Get-SdProgramFiles {
    # Ścieżki względne plików, które program wykonuje lub wczytuje (bez ustawień i raportów).
    param([Parameter(Mandatory = $true)][string]$Root)
    $out = @()
    foreach ($f in 'SerwisDiag.ps1', 'SerwisDiag.cmd', 'SerwisDiag-konsola.cmd', 'SerwisDiag-debug.cmd', 'SerwisDiag.exe', 'SerwisDiagMonitor.exe') {
        if (Test-Path -LiteralPath (Join-Path $Root $f) -PathType Leaf) { $out += $f }
    }
    foreach ($d in 'lib', 'checks', 'data') {
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $Root $d) -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if ($f.Extension -match '^\.(ps1|psd1|psm1|dll|exe|cmd|bat)$') { $out += ($d + '\' + $f.Name) }
        }
    }
    return $out
}

function Get-SdFileSha256 {
    # Get-FileHash jest dopiero w PowerShell 4.0 - liczymy sumę przez .NET.
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try { return (([BitConverter]::ToString($sha.ComputeHash($fs))) -replace '-', '').ToLower() }
        finally { $fs.Dispose() }
    } finally { $sha.Dispose() }
}

function New-SdManifest {
    # Zapisuje manifest (tools\check.ps1 robi to po każdej zmianie plików programu).
    param([Parameter(Mandatory = $true)][string]$Root)
    $lines = @('# SerwisDiag - sumy SHA-256 plików programu. Generuje: tools\check.ps1 (po każdej zmianie plików).')
    foreach ($rel in (Get-SdProgramFiles $Root)) { $lines += ('{0}  {1}' -f (Get-SdFileSha256 (Join-Path $Root $rel)), $rel) }
    [System.IO.File]::WriteAllText((Join-Path $Root $global:SdManifestName), (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
}

function Read-SdManifest {
    # Słownik: ścieżka względna (małymi literami) -> suma SHA-256.
    param([Parameter(Mandatory = $true)][string]$Path)
    $map = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*([0-9a-fA-F]{64})\s+(.+?)\s*$') { $map[$Matches[2].ToLower()] = $Matches[1].ToLower() }
    }
    return $map
}

function Test-SdIntegrity {
    # Status: ok | nomanifest | changed. Changed / Missing / Extra - listy ścieżek względnych. Summary - opis do raportu.
    param([Parameter(Mandatory = $true)][string]$Root)
    $r = [pscustomobject]@{ Status = 'ok'; Changed = @(); Missing = @(); Extra = @(); Summary = '' }
    $mf = Join-Path $Root $global:SdManifestName
    if (-not (Test-Path -LiteralPath $mf -PathType Leaf)) {
        $r.Status = 'nomanifest'
        $r.Summary = 'nie sprawdzono (brak pliku ' + $global:SdManifestName + ')'
        return $r
    }
    try { $expected = Read-SdManifest $mf } catch { $expected = @{} }
    $present = @{}
    foreach ($rel in (Get-SdProgramFiles $Root)) {
        $key = $rel.ToLower()
        $present[$key] = $true
        if (-not $expected.ContainsKey($key)) { $r.Extra += $rel; continue }
        $h = ''
        try { $h = Get-SdFileSha256 (Join-Path $Root $rel) } catch { $h = '' }
        if ($h -ne $expected[$key]) { $r.Changed += $rel }
    }
    foreach ($k in $expected.Keys) { if (-not $present.ContainsKey($k)) { $r.Missing += $k } }
    $n = $r.Changed.Count + $r.Missing.Count + $r.Extra.Count
    if ($n -gt 0) {
        $r.Status = 'changed'
        $parts = @()
        if ($r.Changed.Count) { $parts += ('zmienione: ' + ($r.Changed -join ', ')) }
        if ($r.Missing.Count) { $parts += ('brakujące: ' + ($r.Missing -join ', ')) }
        if ($r.Extra.Count) { $parts += ('dodatkowe: ' + ($r.Extra -join ', ')) }
        $r.Summary = 'NIEZGODNOŚĆ - ' + ($parts -join '; ')
    } else {
        $r.Summary = ('zgodne z manifestem (sprawdzono: {0})' -f $expected.Count)
    }
    return $r
}
