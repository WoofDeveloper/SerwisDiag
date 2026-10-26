# SerwisDiag - kopia przed reinstalacją Windows: w jednym folderze (np. na pendrive) to, co zwykle ginie przy
# reinstalacji: sterowniki producentów, lista programów, klucz Windows z BIOS/UEFI i dane komputera, a na życzenie
# także profile Wi-Fi z hasłami i klucze odzyskiwania BitLocker. Program niczego w systemie przy tym nie zmienia.

$global:SdBackupParts = @(
    [pscustomobject]@{ Key = 'drivers'; Label = 'Sterowniki producentów'; Description = 'Eksport wszystkich sterowników spoza Windows z magazynu sterowników (karta graficzna, Wi-Fi, chipset, dźwięk..., także starsze wersje) - po reinstalacji wskażesz ten folder w Menedżerze urządzeń. Od kilkuset MB do kilku GB, kilka minut; program sprawdzi wcześniej miejsce na nośniku.'; Default = $true; Admin = $true; Sensitive = $false }
    [pscustomobject]@{ Key = 'programs'; Label = 'Lista zainstalowanych programów'; Description = 'Co zainstalować ponownie (nazwa, wersja, producent) - HTML do wydruku i CSV.'; Default = $true; Admin = $false; Sensitive = $false }
    [pscustomobject]@{ Key = 'system'; Label = 'Dane komputera i klucz Windows'; Description = 'Model, numer seryjny, podzespoły, wersja i aktywacja Windows, klucz zapisany w BIOS/UEFI, konta i drukarki.'; Default = $true; Admin = $false; Sensitive = $true }
    [pscustomobject]@{ Key = 'wifi'; Label = 'Profile Wi-Fi z hasłami'; Description = 'Zapisane sieci Wi-Fi razem z hasłami (jawny tekst) - klient nie musi ich pamiętać. Usuń je po przywróceniu.'; Default = $false; Admin = $true; Sensitive = $true }
    [pscustomobject]@{ Key = 'bitlocker'; Label = 'Klucze odzyskiwania BitLocker'; Description = 'Hasła odzyskiwania zaszyfrowanych dysków - potrzebne np. do odczytu dysku z danymi po wymianie płyty głównej. Dane bardzo wrażliwe.'; Default = $false; Admin = $true; Sensitive = $true }
)

function Get-SdBackupIncludeList {
    # 'drivers,wifi' -> lista kluczy; pusta wartość -> elementy domyślne. Nieznane nazwy pomija.
    param([string]$Text)
    $known = @($global:SdBackupParts | ForEach-Object { $_.Key })
    $sel = @($Text -split '[,;\s]+' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -and $known -contains $_ })
    if ($sel.Count -eq 0) { $sel = @($global:SdBackupParts | Where-Object { $_.Default } | ForEach-Object { $_.Key }) }
    return @($known | Where-Object { $sel -contains $_ })
}

function Get-SdBackupDirName {
    # Nazwa folderu kopii: <KOMPUTER>_<data>_kopia (krótka - eksport sterowników podlega limitowi długości ścieżki).
    param([datetime]$Now = (Get-Date))
    return (('{0}_{1}_kopia' -f $env:COMPUTERNAME, $Now.ToString('yyyyMMdd-HHmm')) -replace '[\\/:*?"<>|\s]+', '_')
}

function Get-SdDriverExportInfo {
    # Pakiety, które wyeksportuje DISM (wszystkie sterowniki spoza Windows w magazynie, także starsze wersje): liczba,
    # łączny rozmiar i najdłuższa ścieżka pliku względem FileRepository. DISM odtwarza te ścieżki w folderze eksportu,
    # a przekroczenie limitu 260 znaków przerywa eksport w połowie (błąd 206).
    # Pakiet producenta rozpoznajemy po tym, że jego plik INF ma kopię %windir%\INF\oemNN.inf (ten sam rozmiar
    # i suma SHA-256). Bez administratora i w kilka sekund - Get-WindowsDriver daje ten sam wynik w ok. minutę,
    # a rejestr (DriverDatabase) opisuje tylko część pakietów.
    Get-SdCached 'DriverExport' {
        $fr = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
        $hash = {
            param([string]$p)
            $s = [System.Security.Cryptography.SHA256]::Create()
            try { [BitConverter]::ToString($s.ComputeHash([System.IO.File]::ReadAllBytes($p))) } catch { '' } finally { $s.Dispose() }
        }
        # kopie INF producentów pogrupowane po rozmiarze; sumy liczone tylko przy zgodnym rozmiarze
        $bySize = @{}
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'INF') -Filter 'oem*.inf' -File -ErrorAction SilentlyContinue)) {
            if (-not $bySize.ContainsKey($f.Length)) { $bySize[$f.Length] = New-Object System.Collections.ArrayList }
            [void]$bySize[$f.Length].Add(@{ Path = $f.FullName; Hash = $null })
        }
        $r = [pscustomobject]@{ Count = 0; Bytes = 0.0; MaxRel = 0; Package = ''; Source = 'oem*.inf' }
        foreach ($d in @(Get-ChildItem -LiteralPath $fr -Directory -ErrorAction SilentlyContinue)) {
            $inf = Join-Path $d.FullName ((($d.Name -split '\.inf_')[0]) + '.inf')
            $fi = Get-Item -LiteralPath $inf -ErrorAction SilentlyContinue
            if (-not $fi -or -not $bySize.ContainsKey($fi.Length)) { continue }
            $h = & $hash $fi.FullName
            $hit = $false
            foreach ($o in $bySize[$fi.Length]) {
                if ($null -eq $o.Hash) { $o.Hash = & $hash $o.Path }
                if ($h -and $o.Hash -eq $h) { $hit = $true; break }
            }
            if (-not $hit) { continue }
            $r.Count++
            foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue)) {
                $r.Bytes += $f.Length
                $rel = $f.FullName.Length - $fr.Length - 1
                if ($rel -gt $r.MaxRel) { $r.MaxRel = $rel; $r.Package = ($d.Name -split '_')[0] }
            }
        }
        $r
    }
}

function Test-SdDriverExport {
    # Czy eksport sterowników zmieści się w folderze: limit długości ścieżki Windows (259 znaków) i wolne miejsce na
    # nośniku (gdy znany jest rozmiar eksportu). -Info: wynik Get-SdDriverExportInfo; -FreeBytes: wolne miejsce (testy).
    param([Parameter(Mandatory = $true)][string]$DriverDir, $Info = $null, [double]$FreeBytes = -1)
    if ($null -eq $Info) { $Info = Get-SdDriverExportInfo }
    $need = $DriverDir.TrimEnd('\').Length + 1 + [int]$Info.MaxRel
    if ($FreeBytes -lt 0) {
        try { $FreeBytes = [double](New-Object System.IO.DriveInfo([System.IO.Path]::GetPathRoot($DriverDir))).AvailableFreeSpace } catch { $FreeBytes = -1 }
    }
    $r = [pscustomobject]@{ Ok = $true; Need = $need; MaxRel = [int]$Info.MaxRel; Package = [string]$Info.Package; Bytes = [double]$Info.Bytes; Free = $FreeBytes; Message = '' }
    if ($need -gt 259) {
        $r.Ok = $false
        $r.Message = ('ścieżka folderu docelowego jest za długa: najdłuższy plik sterownika ({0}) wymagałby {1} znaków, a Windows pozwala na 259. Wybierz krótszy folder, np. główny katalog pendrive''a (E:\).' -f $(if ($r.Package) { $r.Package } else { 'pakiet producenta' }), $need)
    } elseif ($FreeBytes -ge 0 -and $r.Bytes -gt 0 -and $FreeBytes -lt ($r.Bytes * 1.05 + 100MB)) {
        $r.Ok = $false
        $r.Message = ('za mało miejsca: eksport zajmie ok. {0} ({1}, także starsze wersje sterowników), a na nośniku jest wolne {2}.' -f (Format-Size $r.Bytes 1), (Format-Count $Info.Count 'pakiet' 'pakiety' 'pakietów'), (Format-Size $FreeBytes 1))
    }
    return $r
}

function Get-SdDismExportError {
    # Kody wyjścia DISM przy eksporcie sterowników -> opis po polsku (bez parsowania zlokalizowanych komunikatów).
    param([int]$Code, [string]$Output = '')
    switch ($Code) {
        206 { return 'nazwa pliku sterownika jest za długa dla tego folderu (limit 260 znaków) - wybierz krótszy folder, np. główny katalog pendrive''a' }
        112 { return 'za mało miejsca na dysku docelowym' }
        5 { return 'odmowa dostępu - uruchom program jako administrator i sprawdź, czy nośnik nie jest zabezpieczony przed zapisem' }
        3 { return 'nie znaleziono folderu docelowego' }
        19 { return 'nośnik jest zabezpieczony przed zapisem' }
    }
    return ('DISM zakończył się kodem {0}: {1}' -f (Format-Hr $Code), (Get-SdLastLine $Output))
}

function Get-SdBitLockerVolumes {
    # Woluminy z włączoną ochroną BitLocker (wymaga administratora; bez niego - pusta lista).
    if (-not (Test-SdAdmin)) { return @() }
    return @(Get-Cim -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -Class Win32_EncryptableVolume | Where-Object { [int]$_.ProtectionStatus -eq 1 })
}

function ConvertTo-SdCimDate {
    param($Value)
    if ($Value -is [datetime]) { return $Value }
    try { return [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value) } catch { return $null }
}

function Get-SdBackupSystemText {
    # Dane komputera do pliku system.txt (bez zmian w systemie).
    $L = New-Object System.Collections.ArrayList
    $add = { param($k, $v) if (-not (Test-SdEmpty $v)) { [void]$L.Add(('{0,-28} {1}' -f ($k + ':'), $v)) } }
    $cs = Get-SdCs
    $bios = Get-Cim Win32_BIOS | Select-Object -First 1
    $bb = Get-Cim Win32_BaseBoard | Select-Object -First 1
    $os = Get-SdOs
    $w = Get-SdWinInfo
    [void]$L.Add('KOMPUTER')
    & $add 'Nazwa komputera' $env:COMPUTERNAME
    if ($cs) { & $add 'Producent i model' (Join-NonEmpty @((Get-SdCleanString $cs.Manufacturer ''), (Get-SdCleanString $cs.Model '')) ' ') }
    if ($bios) {
        & $add 'Numer seryjny' (Get-SdCleanString $bios.SerialNumber '')
        & $add 'BIOS / UEFI' ((Join-NonEmpty @($bios.Manufacturer, $bios.SMBIOSBIOSVersion) ' ') + ' (' + (Format-Dt (ConvertTo-SdCimDate $bios.ReleaseDate) -DateOnly) + ')')
    }
    if ($bb) { & $add 'Płyta główna' (Join-NonEmpty @((Get-SdCleanString $bb.Manufacturer ''), (Get-SdCleanString $bb.Product '')) ' ') }
    foreach ($p in @(Get-SdCpus)) { & $add 'Procesor' ([string]$p.Name).Trim() }
    if ($cs -and $cs.TotalPhysicalMemory) { & $add 'Pamięć RAM' (Format-Size $cs.TotalPhysicalMemory 1) }
    foreach ($d in @(Get-Cim Win32_DiskDrive)) { & $add 'Dysk' (Join-NonEmpty @(([string]$d.Model).Trim(), (Format-Size $d.Size 0), $d.InterfaceType)) }
    foreach ($g in @(Get-Cim Win32_VideoController)) { & $add 'Karta graficzna' ([string]$g.Name) }
    [void]$L.Add('')
    [void]$L.Add('WINDOWS')
    & $add 'System' (Join-NonEmpty @($w.Caption, $w.Version, ('kompilacja {0}.{1}' -f $w.Build, $w.Ubr), $w.Arch))
    & $add 'Edycja' $w.Edition
    if ($os) { & $add 'Data instalacji' (Format-Dt (ConvertTo-SdCimDate $os.InstallDate)) }
    $lic = @(Get-Cim SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f'") | Select-Object -First 1
    if ($lic) {
        $st = @{ 0 = 'nieaktywowany'; 1 = 'aktywowany'; 2 = 'okres prolongaty'; 3 = 'okres prolongaty'; 4 = 'okres prolongaty'; 5 = 'wymaga aktywacji'; 6 = 'okres prolongaty' }
        & $add 'Aktywacja' $st[[int]$lic.LicenseStatus]
        $ch = ''
        if ([string]$lic.Description -match ',\s*(\S+)\s+channel') { $ch = $Matches[1] }
        & $add 'Kanał licencji' $ch
        & $add 'Klucz (ostatnie znaki)' ('*****-*****-*****-*****-' + [string]$lic.PartialProductKey)
    }
    $svc = Get-Cim SoftwareLicensingService | Select-Object -First 1
    $oem = ''
    if ($svc -and $svc.PSObject.Properties['OA3xOriginalProductKey']) { $oem = [string]$svc.OA3xOriginalProductKey }
    & $add 'Klucz w BIOS/UEFI (OEM)' $(if ($oem) { $oem } else { 'brak (licencja cyfrowa, klucz detaliczny albo starszy komputer)' })
    [void]$L.Add('')
    [void]$L.Add('KONTA I URZĄDZENIA')
    foreach ($u in @(Get-Cim Win32_UserAccount -Filter 'LocalAccount=True' | Where-Object { -not $_.Disabled })) { & $add 'Konto lokalne' ([string]$u.Name) }
    foreach ($pr in @(Get-Cim Win32_Printer)) { & $add 'Drukarka' (Join-NonEmpty @([string]$pr.Name, ('sterownik: ' + [string]$pr.DriverName), ('port: ' + [string]$pr.PortName)) ' · ') }
    return ($L -join "`r`n")
}

function Write-SdCsv {
    # CSV dla polskiego Excela: średnik i UTF-8 z BOM.
    param([object[]]$Rows, [string]$Path)
    @($Rows) | Export-Csv -LiteralPath $Path -Delimiter ';' -NoTypeInformation -Encoding UTF8
}

function Invoke-SdBackup {
    # Tworzy kopię w <Dest>\<KOMPUTER>_<data>_kopia. Status (hashtable, w oknie synchronizowany) i OnStep - postęp.
    # Zwraca { Dir; Parts = wyniki elementów { Key; Label; Result = ok|warn|skip|error; Message }; Warnings }.
    param([Parameter(Mandatory = $true)][string]$Dest, [string[]]$Include = @('drivers', 'programs', 'system'), $Status = $null, [scriptblock]$OnStep = $null)
    $isAdmin = Test-SdAdmin
    $dir = Join-Path $Dest (Get-SdBackupDirName)
    [void](New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop)
    $out = [pscustomobject]@{ Dir = $dir; Parts = @(); Warnings = @() }
    $step = {
        param($t)
        if ($null -ne $Status) { $Status['Text'] = $t }
        if ($OnStep) { & $OnStep $t }
    }
    $part = { param($k, $res, $msg) $p = $global:SdBackupParts | Where-Object { $_.Key -eq $k } | Select-Object -First 1; [pscustomobject]@{ Key = $k; Label = $p.Label; Result = $res; Message = $msg } }
    $files = @()

    # ostrzeżenia ogólne: kopia na dysku systemowym, zaszyfrowane dyski bez zapisanego klucza
    $root = [System.IO.Path]::GetPathRoot($dir)
    if ($root -and $env:SystemDrive -and $root.TrimEnd('\').ToUpper() -eq ([string]$env:SystemDrive).ToUpper()) {
        $out.Warnings += 'Kopia leży na dysku systemowym - przed reinstalacją przenieś ją na pendrive albo inny dysk, bo zostanie usunięta razem z systemem.'
    }
    $bl = @(Get-SdBitLockerVolumes)
    if ($bl.Count -gt 0 -and $Include -notcontains 'bitlocker') {
        $out.Warnings += ('Zaszyfrowane BitLockerem: {0}. Przed zmianami zapisz klucz odzyskiwania (element „Klucze odzyskiwania BitLocker”) albo upewnij się, że klient ma go na koncie Microsoft (aka.ms/myrecoverykey).' -f ((@($bl | ForEach-Object { [string]$_.DriveLetter }) -join ', ')))
    }

    foreach ($k in @($global:SdBackupParts | ForEach-Object { $_.Key })) {
        if ($Include -notcontains $k) { continue }
        $meta = $global:SdBackupParts | Where-Object { $_.Key -eq $k } | Select-Object -First 1
        if ($meta.Admin -and -not $isAdmin) { $out.Parts += (& $part $k 'skip' 'wymaga uprawnień administratora'); continue }
        try {
            switch ($k) {
                'drivers' {
                    $w = Get-SdWinInfo
                    $rows = @(Get-Cim Win32_PnPSignedDriver -Filter "InfName LIKE 'oem%'" | Sort-Object DeviceClass, DeviceName | ForEach-Object {
                            [pscustomobject]@{ Urządzenie = [string]$_.DeviceName; Klasa = [string]$_.DeviceClass; 'Dostawca sterownika' = [string]$_.DriverProviderName; Wersja = [string]$_.DriverVersion; Data = (Format-Dt (ConvertTo-SdCimDate $_.DriverDate) -DateOnly); 'Plik INF' = [string]$_.InfName }
                        })
                    if ($rows.Count -gt 0) { Write-SdCsv $rows (Join-Path $dir 'sterowniki-lista.csv'); $files += 'sterowniki-lista.csv' }
                    if ($w.Build -gt 0 -and $w.Build -lt 9600) { $out.Parts += (& $part $k 'warn' 'eksport sterowników wymaga Windows 8.1 lub nowszego - zapisano tylko ich listę'); break }
                    $dd = Join-Path $dir 'sterowniki'
                    # zbyt długa ścieżka albo brak miejsca przerwałyby eksport w połowie - sprawdzamy przed startem
                    & $step 'Sprawdzanie sterowników do eksportu...'
                    $chk = Test-SdDriverExport -DriverDir $dd
                    if (-not $chk.Ok) { $out.Parts += (& $part $k 'error' ('nie wyeksportowano: ' + $chk.Message + ' Lista sterowników została zapisana.')); break }
                    & $step ('Eksport sterowników (ok. {0}, zwykle kilka minut)...' -f (Format-Size $chk.Bytes 1))
                    [void](New-Item -ItemType Directory -Path $dd -Force)
                    $r = Invoke-Native -File (Join-Path $env:SystemRoot 'System32\Dism.exe') -Arguments ('/Online /Export-Driver /Destination:' + (Format-SdCmdArg $dd)) -TimeoutSec 1800
                    $infs = @(Get-ChildItem -LiteralPath $dd -Recurse -Filter '*.inf' -ErrorAction SilentlyContinue)
                    $size = 0.0
                    foreach ($f in @(Get-ChildItem -LiteralPath $dd -Recurse -File -ErrorAction SilentlyContinue)) { $size += $f.Length }
                    $files += 'sterowniki\'
                    if ($r.ExitCode -ne 0) { $out.Parts += (& $part $k 'error' ('eksport niepełny (' + (Format-Count $infs.Count 'sterownik' 'sterowniki' 'sterowników') + '): ' + (Get-SdDismExportError $r.ExitCode ($r.StdOut + $r.StdErr)))) }
                    else { $out.Parts += (& $part $k 'ok' ('{0}, {1}' -f (Format-Count $infs.Count 'sterownik' 'sterowniki' 'sterowników'), (Format-Size $size 1))) }
                }
                'programs' {
                    & $step 'Lista zainstalowanych programów...'
                    $apps = @(Get-SdInstalledApps | ForEach-Object { [pscustomobject]@{ Nazwa = $_.Nazwa; Wersja = $_.Wersja; Producent = $_.Producent; Zainstalowano = (Format-Dt $_.Zainstalowano -DateOnly); Zakres = $_.Zakres } })
                    Write-SdCsv $apps (Join-Path $dir 'programy.csv')
                    $E = { param($t) ConvertTo-SdHtml $t }
                    $sb = New-Object System.Text.StringBuilder
                    [void]$sb.Append('<!DOCTYPE html><html lang="pl"><head><meta charset="utf-8"><title>Programy - ' + (& $E $env:COMPUTERNAME) + '</title><style>' + (Get-SdInlineCss) + '</style></head><body><div class="wrap"><section class="card">')
                    [void]$sb.Append('<h2>Zainstalowane programy: ' + (& $E $env:COMPUTERNAME) + ' (' + (Format-Dt (Get-Date)) + ')</h2><table><thead><tr><th>Nazwa</th><th>Wersja</th><th>Producent</th><th>Zainstalowano</th></tr></thead><tbody>')
                    foreach ($a in $apps) { [void]$sb.Append('<tr><td>' + (& $E $a.Nazwa) + '</td><td>' + (& $E $a.Wersja) + '</td><td>' + (& $E $a.Producent) + '</td><td>' + (& $E $a.Zainstalowano) + '</td></tr>') }
                    [void]$sb.Append('</tbody></table></section></div></body></html>')
                    [System.IO.File]::WriteAllText((Join-Path $dir 'programy.html'), $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
                    $files += 'programy.html', 'programy.csv'
                    $out.Parts += (& $part $k 'ok' (Format-Count $apps.Count 'program' 'programy' 'programów'))
                }
                'system' {
                    & $step 'Dane komputera i klucz Windows...'
                    $txt = 'DANE KOMPUTERA - SerwisDiag ' + $global:SdVersion + ' (' + (Format-Dt (Get-Date)) + ")`r`n`r`n" + (Get-SdBackupSystemText)
                    [System.IO.File]::WriteAllText((Join-Path $dir 'system.txt'), $txt, (New-Object System.Text.UTF8Encoding($true)))
                    $files += 'system.txt'
                    $out.Parts += (& $part $k 'ok' 'zapisano')
                }
                'wifi' {
                    & $step 'Profile Wi-Fi...'
                    $wd = Join-Path $dir 'wifi'
                    [void](New-Item -ItemType Directory -Path $wd -Force)
                    $r = Invoke-Native -File (Join-Path $env:SystemRoot 'System32\netsh.exe') -Arguments ('wlan export profile key=clear folder=' + (Format-SdCmdArg $wd)) -TimeoutSec 60
                    $xml = @(Get-ChildItem -LiteralPath $wd -Filter '*.xml' -ErrorAction SilentlyContinue)
                    if ($xml.Count -gt 0) { $files += 'wifi\'; $out.Parts += (& $part $k 'ok' (Format-Count $xml.Count 'profil' 'profile' 'profili')) }
                    else {
                        Remove-Item -LiteralPath $wd -Force -ErrorAction SilentlyContinue
                        $out.Parts += (& $part $k 'skip' $(if ($r.ExitCode -ne 0) { 'brak karty Wi-Fi albo usługa WLAN nie działa' } else { 'brak zapisanych sieci Wi-Fi' }))
                    }
                }
                'bitlocker' {
                    & $step 'Klucze odzyskiwania BitLocker...'
                    $lines = @()
                    foreach ($v in $bl) {
                        $kp = Invoke-CimMethod -InputObject $v -MethodName GetKeyProtectors -Arguments @{ KeyProtectorType = [uint32]3 } -ErrorAction Stop
                        foreach ($id in @($kp.VolumeKeyProtectorID)) {
                            $np = Invoke-CimMethod -InputObject $v -MethodName GetKeyProtectorNumericalPassword -Arguments @{ VolumeKeyProtectorID = $id } -ErrorAction Stop
                            $lines += ('Dysk {0}' -f $v.DriveLetter)
                            $lines += ('  identyfikator klucza: {0}' -f $id)
                            $lines += ('  klucz odzyskiwania:   {0}' -f $np.NumericalPassword)
                            $lines += ''
                        }
                    }
                    if ($lines.Count -eq 0) { $out.Parts += (& $part $k 'skip' $(if ($bl.Count -eq 0) { 'brak dysków zaszyfrowanych BitLockerem' } else { 'zaszyfrowane dyski nie mają klucza odzyskiwania w postaci hasła' })) }
                    else {
                        $head = @(('KLUCZE ODZYSKIWANIA BITLOCKER - ' + $env:COMPUTERNAME + ' (' + (Format-Dt (Get-Date)) + ')'), 'Dane bardzo wrażliwe: przekaż je klientowi i usuń ten plik z nośnika serwisowego.', '')
                        [System.IO.File]::WriteAllText((Join-Path $dir 'bitlocker-klucze.txt'), (($head + $lines) -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
                        $files += 'bitlocker-klucze.txt'
                        $out.Parts += (& $part $k 'ok' (Format-Count $bl.Count 'dysk' 'dyski' 'dysków'))
                    }
                }
            }
        } catch {
            $out.Parts += (& $part $k 'error' $_.Exception.Message)
        }
    }

    # instrukcja w folderze kopii
    $R = @(('KOPIA PRZED REINSTALACJĄ WINDOWS - SerwisDiag ' + $global:SdVersion), ('Komputer: {0}   Data: {1}' -f $env:COMPUTERNAME, (Format-Dt (Get-Date))), '', 'ZAWARTOŚĆ')
    $desc = @{
        'sterowniki\' = 'sterowniki zainstalowane spoza Windows (eksport DISM)'; 'sterowniki-lista.csv' = 'lista tych sterowników: urządzenie, dostawca, wersja, data'
        'programy.html' = 'zainstalowane programy - do ponownej instalacji (do wydruku)'; 'programy.csv' = 'to samo w formacie dla Excela'
        'system.txt' = 'dane komputera, wersja i aktywacja Windows, klucz z BIOS/UEFI, konta, drukarki'
        'wifi\' = 'profile Wi-Fi z hasłami (jawny tekst)'; 'bitlocker-klucze.txt' = 'klucze odzyskiwania BitLocker'
    }
    foreach ($f in $files) { $R += ('  {0,-22} {1}' -f $f, $desc[$f]) }
    $R += ''
    $R += 'PRZYWRACANIE PO REINSTALACJI'
    if ($files -contains 'sterowniki\') {
        $R += '  Sterowniki: Menedżer urządzeń > urządzenie > Aktualizuj sterownik > Przeglądaj mój komputer > wskaż folder'
        $R += '  "sterowniki" (z podfolderami), albo jako administrator: pnputil /add-driver "<folder>\sterowniki\*.inf" /subdirs /install'
    }
    if ($files -contains 'wifi\') { $R += '  Wi-Fi: netsh wlan add profile filename="<folder>\wifi\<plik>.xml"' }
    $R += '  Windows: komputer z kluczem w BIOS/UEFI aktywuje się sam po instalacji tej samej edycji (Home albo Pro).'
    if (@($global:SdBackupParts | Where-Object { $_.Sensitive -and $Include -contains $_.Key }).Count -gt 0) {
        $R += ''
        $R += 'UWAGA: folder zawiera dane wrażliwe (numer seryjny, klucz Windows' + $(if ($files -contains 'wifi\') { ', hasła Wi-Fi' } else { '' }) + $(if ($files -contains 'bitlocker-klucze.txt') { ', klucze BitLocker' } else { '' }) + ').'
        $R += 'Przechowuj go bezpiecznie i usuń z nośnika serwisowego po zakończeniu naprawy.'
    }
    foreach ($p in @($out.Parts | Where-Object { $_.Result -eq 'error' -or $_.Result -eq 'warn' })) { $R += ''; $R += ('{0}: {1} - {2}' -f $(if ($p.Result -eq 'error') { 'BŁĄD' } else { 'UWAGA' }), $p.Label, $p.Message) }
    foreach ($wn in $out.Warnings) { $R += ''; $R += ('UWAGA: ' + $wn) }
    [System.IO.File]::WriteAllText((Join-Path $dir 'CZYTAJ.txt'), ($R -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    & $step ''
    return $out
}
