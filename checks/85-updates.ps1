# Testy kategorii: Aktualizacje i licencja

$global:SdWuErrors = @{
    '0x80070002' = 'Brak wymaganego pliku - zwykle uszkodzona pamięć podręczna aktualizacji (SoftwareDistribution).'
    '0x80070003' = 'Nie znaleziono ścieżki - uszkodzone komponenty Windows Update.'
    '0x80070005' = 'Odmowa dostępu - blokada przez antywirus lub uszkodzone uprawnienia.'
    '0x8007000d' = 'Dane są nieprawidłowe - uszkodzony pobrany pakiet lub magazyn składników.'
    '0x80070070' = 'Brak miejsca na dysku.'
    '0x80070490' = 'Nie znaleziono elementu - uszkodzony magazyn składników (DISM /RestoreHealth).'
    '0x80070643' = 'Błąd instalacji MSI - uszkodzona instalacja pakietu (.NET / Defender).'
    '0x80070bc2' = 'Wymagany restart komputera przed dalszą instalacją.'
    '0x800705b4' = 'Przekroczono czas operacji - problem z siecią lub usługą.'
    '0x80073712' = 'Uszkodzony magazyn składników - uruchom DISM /Online /Cleanup-Image /RestoreHealth oraz sfc /scannow.'
    '0x800f081f' = 'Nie znaleziono plików źródłowych - uszkodzony magazyn składników lub brak dostępu do źródła.'
    '0x800f0831' = 'Brakuje poprzedniego pakietu aktualizacji - uszkodzony magazyn składników.'
    '0x800f0922' = 'Błąd CBS - za mało miejsca w partycji systemowej/odzyskiwania, aktywny VPN lub uszkodzone składniki.'
    '0x80240034' = 'Pobieranie aktualizacji nie powiodło się.'
    '0x80244022' = 'Serwer Windows Update zwrócił błąd HTTP 503 - spróbuj ponownie później.'
    '0x8024402c' = 'Brak połączenia z serwerem aktualizacji - problem z siecią, proxy, DNS lub zaporą.'
    '0x80248007' = 'Brakuje metadanych aktualizacji - zresetuj komponenty Windows Update.'
    '0x8024a105' = 'Usługa aktualizacji nie działa poprawnie - zresetuj komponenty Windows Update.'
    '0xc1900101' = 'Błąd sterownika podczas aktualizacji funkcji - odłącz urządzenia USB, zaktualizuj sterowniki (grafika, dysk).'
}

function Format-Hr {
    param($Hr)
    try { return ('0x{0:X8}' -f [uint32]([int64]$Hr -band 0xFFFFFFFFL)) } catch { return [string]$Hr }
}

Register-Check -Id 'up.history' -Category 'updates' -Title 'Historia i stan Windows Update' -Script {
    $hist = Get-SdWuHistory
    $entries = @($hist.Entries)
    $err = $hist.Error
    $svc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $svcCim = Get-Cim Win32_Service -Filter "Name='wuauserv'" | Select-Object -First 1
    $startMode = if ($svcCim) { [string]$svcCim.StartMode } else { '' }

    if ($err) {
        Add-Finding 'Usługa Windows Update' -Status warn -Value ('Nie można odczytać historii: ' + (Limit-Text $err 120)) `
            -Details ('Usługa wuauserv: ' + $(if ($svc) { $svc.Status } else { 'brak' }) + ', tryb: ' + $startMode) `
            -Advice 'Uruchom narzędzie do rozwiązywania problemów z Windows Update; sprawdź usługi wuauserv, bits, cryptsvc i uprawnienia.'
    }
    # Liczą się tylko poprawki systemu (lista QFE i wpisy KB dla Windows). Definicje Defendera, MSRT, sterowniki
    # i aplikacje ze Sklepu instalują się niezależnie i nie świadczą o łataniu systemu.
    $last = Get-SdLastOsPatch
    $failed = @($entries | Where-Object { $_.Result -eq 4 -and $_.Date -ge (Get-Date).AddDays(-60) } | Sort-Object Date -Descending)
    $sup = Get-SdSupportInfo
    $noMorePatches = ($sup -and -not $sup.Result.Covered)
    if ($last) {
        $days = [int]((Get-Date) - $last.Date).TotalDays
        $d = "Ostatnia poprawka systemu: $(Format-Dt $last.Date) - $(Limit-Text $last.Title 110)"
        $d += "`nŹródło: " + $(if ($last.Source -eq 'QFE') { 'lista zainstalowanych poprawek (data bez godziny)' } else { 'historia Windows Update' })
        if ($entries.Count -gt 0) { $d += "`nWpisów w historii Windows Update: $($entries.Count)" }
        $val = '{0} ({1} dni temu)' -f (Format-Dt $last.Date -DateOnly), $days
        if ($days -gt 45 -and $noMorePatches) {
            Add-Finding 'Ostatnia aktualizacja systemu' -Status info -Value $val -Details $d `
                -Advice 'Ta wersja systemu nie otrzymuje już poprawek (zob. „Okres wsparcia systemu”) - brak nowych aktualizacji jest skutkiem końca wsparcia, a nie awarii Windows Update.'
        }
        elseif ($days -gt 120) { Add-Finding 'Ostatnia aktualizacja systemu' -Status crit -Value $val -Details $d -Advice 'System nie był aktualizowany od miesięcy - zainstaluj wszystkie aktualizacje (a jeśli się nie instalują, zob. błędy poniżej).' }
        elseif ($days -gt 45) { Add-Finding 'Ostatnia aktualizacja systemu' -Status warn -Value $val -Details $d -Advice 'Sprawdź Windows Update - poprawki zabezpieczeń ukazują się co miesiąc.' }
        else { Add-Finding 'Ostatnia aktualizacja systemu' -Status ok -Value $val -Details $d }
    } elseif (-not $err) {
        if ($entries.Count -eq 0) {
            Add-Finding 'Ostatnia aktualizacja systemu' -Status info -Value 'Historia aktualizacji jest pusta' -Details 'Historia mogła zostać wyczyszczona lub system został niedawno zainstalowany.' `
                -Advice 'Sprawdź ręcznie w Ustawieniach, czy dostępne są aktualizacje.'
        } else {
            Add-Finding 'Ostatnia aktualizacja systemu' -Status warn -Value 'Brak zainstalowanych poprawek systemu w historii' -Advice 'Sprawdź błędy Windows Update i uruchom narzędzie do rozwiązywania problemów.'
        }
    }
    if ($failed.Count -gt 0) {
        $rows = @($failed | Select-Object -First 15 | ForEach-Object {
                $code = Format-Hr $_.Hr
                [pscustomobject]@{ Data = (Format-Dt $_.Date); Aktualizacja = (Limit-Text $_.Title 90); Kod = $code; Znaczenie = $(if ($global:SdWuErrors.ContainsKey($code.ToLower())) { $global:SdWuErrors[$code.ToLower()] } else { '' }) }
            })
        Add-Table 'Nieudane aktualizacje (60 dni)' -Rows $rows
        $codes = $failed | Group-Object { Format-Hr $_.Hr } | Sort-Object Count -Descending
        $first = ($codes | Select-Object -First 1).Name
        $mean = if ($global:SdWuErrors.ContainsKey($first.ToLower())) { $global:SdWuErrors[$first.ToLower()] } else { '' }
        Add-Finding 'Nieudane aktualizacje' -Status warn -Value ('{0} w ciągu 60 dni; najczęstszy kod {1}' -f (Format-Count $failed.Count 'niepowodzenie' 'niepowodzenia' 'niepowodzeń'), $first) -Details $mean -LastEvent (Get-SdLatestTime $failed 'Date') `
            -Advice 'Uruchom DISM /Online /Cleanup-Image /RestoreHealth i sfc /scannow, a następnie zresetuj komponenty Windows Update lub zainstaluj aktualizację ręcznie z Katalogu Microsoft Update.'
    } elseif (-not $err -and $entries.Count -gt 0) {
        Add-Finding 'Nieudane aktualizacje' -Status ok -Value 'Brak niepowodzeń w ciągu 60 dni'
    }
    if ($svcCim) {
        if ($startMode -eq 'Disabled') {
            Add-Finding 'Usługa Windows Update (wuauserv)' -Status warn -Value 'Wyłączona (tryb uruchamiania: Disabled)' `
                -Advice 'Usługa Windows Update jest wyłączona - przywróć tryb „Ręczny” lub „Automatyczny (opóźniony)”. Często wyłączają ją „optymalizatory”.'
        }
    }
}

Register-Check -Id 'up.pending' -Category 'updates' -Title 'Oczekujący restart i zasady aktualizacji' -Script {
    $reasons = @()
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons += 'oczekujące zmiany komponentów systemu (CBS)' }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons += 'Windows Update wymaga restartu' }
    $pfr = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations' $null
    $pfrOnly = $false
    if ($pfr) { $reasons += 'oczekujące operacje na plikach (PendingFileRenameOperations)'; if ($reasons.Count -eq 1) { $pfrOnly = $true } }
    $a = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' 'ComputerName' ''
    $b = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' 'ComputerName' ''
    if ($a -and $b -and $a -ne $b) { $reasons += 'zmieniono nazwę komputera' }
    if ($a -and $b -and $a -ne $b) { $pfrOnly = $false }
    if ($reasons.Count -gt 0) {
        # sam wpis PendingFileRenameOperations bywa pozostałością po instalatorach - traktujemy go jako informację
        Add-Finding 'Oczekujący restart' -Status $(if ($pfrOnly) { 'info' } else { 'warn' }) -Value ('Wymagane ponowne uruchomienie: ' + ($reasons -join '; ')) `
            -Advice 'Uruchom ponownie komputer (opcja „Uruchom ponownie”, a nie „Zamknij”) przed dalszą diagnostyką i instalacją aktualizacji.'
    } else {
        Add-Finding 'Oczekujący restart' -Status ok -Value 'Brak oczekujących restartów'
    }

    $notes = @(); $st = 'ok'
    $au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if ((Get-RegValue ($au + '\AU') 'NoAutoUpdate' 0) -eq 1) { $notes += 'Zasady wyłączają automatyczne aktualizacje (NoAutoUpdate)'; $st = 'warn' }
    if ((Get-RegValue $au 'DisableWindowsUpdateAccess' 0) -eq 1) { $notes += 'Zasady blokują dostęp do Windows Update'; $st = 'warn' }
    $wsus = Get-RegValue $au 'WUServer' $null
    if ($wsus) { $notes += "Aktualizacje pobierane z serwera WSUS: $wsus (przy braku dostępu do serwera aktualizacje nie będą działać)"; if ($st -eq 'ok') { $st = 'info' } }
    $ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    foreach ($n in 'PauseUpdatesExpiryTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime') {
        $v = Get-RegValue $ux $n $null
        if ($v) {
            $dt = [datetime]::MinValue
            if ([datetime]::TryParse([string]$v, [ref]$dt) -and $dt -gt (Get-Date)) { $notes += ('Aktualizacje wstrzymane do ' + (Format-Dt $dt -DateOnly)); if ($st -eq 'ok') { $st = 'info' }; break }
        }
    }
    if ($notes.Count -gt 0) {
        Add-Finding 'Zasady Windows Update' -Status $st -Value ($notes -join '; ') `
            -Advice 'Sprawdź, czy ograniczenia są zamierzone. Zasady wyłączające aktualizacje (np. po „optymalizacji” systemu) narażają komputer na luki.'
    }
}

Register-Check -Id 'up.activation' -Category 'updates' -Title 'Aktywacja i licencja Windows' -Script {
    $lic = @(Get-Cim SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f'")
    $svc = Get-Cim SoftwareLicensingService | Select-Object -First 1
    $cs = Get-SdCs
    if ($lic.Count -eq 0) {
        Add-Finding 'Aktywacja Windows' -Status warn -Value 'Nie wykryto zainstalowanego klucza produktu' -Advice 'Sprawdź stan aktywacji (Ustawienia > System > Aktywacja).'
    } else {
        $l = $lic[0]
        $statusMap = @{ 0 = 'Nieaktywowany'; 1 = 'Aktywowany'; 2 = 'Okres prolongaty (OOB)'; 3 = 'Okres prolongaty (OOT)'; 4 = 'Niezgodny z oryginałem (okres prolongaty)'; 5 = 'Powiadomienie o braku aktywacji'; 6 = 'Rozszerzony okres prolongaty' }
        $ls = [int]$l.LicenseStatus
        $channel = ''
        if ($l.PSObject.Properties['ProductKeyChannel'] -and $l.ProductKeyChannel) { $channel = [string]$l.ProductKeyChannel }
        $kms = ''
        if ($l.PSObject.Properties['KeyManagementServiceMachine'] -and $l.KeyManagementServiceMachine) { $kms = [string]$l.KeyManagementServiceMachine }
        $d = @("Produkt: $($l.Name)", "Stan: $($statusMap[$ls])")
        if ($channel) { $d += "Kanał licencji: $channel" }
        if ($l.Description) { $d += "Typ: $($l.Description)" }
        if ($kms) { $d += "Serwer KMS: $kms" }
        $d += "Końcówka klucza: $($l.PartialProductKey)"
        if ($ls -eq 1) {
            $domain = ($cs -and $cs.PartOfDomain)
            $isKms = ($channel -match 'GVLK' -or $l.Description -match 'VOLUME_KMSCLIENT')
            $isMak = ($channel -match 'MAK' -or $l.Description -match 'VOLUME_MAK')
            # Wątpliwości co do legalności licencji są tylko w raporcie technicznym - technik wyjaśnia je z klientem
            # osobiście; raport dla klienta podaje jedynie, że system jest aktywowany.
            if ($isKms -and -not $domain) {
                Add-Finding 'Aktywacja Windows' -Status warn -Value ('Aktywowany zbiorczo (KMS)' + $(if ($kms) { ' przez ' + $kms } else { '' })) -Details ($d -join "`n") `
                    -Advice 'Aktywacja zbiorcza (KMS) na komputerze spoza domeny jest częstym objawem nielegalnej aktywacji (zewnętrzne serwery KMS, aktywatory). Zweryfikuj legalność licencji z klientem.' `
                    -CustomerStatus info -CustomerValue 'Aktywowany'
            } elseif ($isMak -and -not $domain) {
                Add-Finding 'Aktywacja Windows' -Status info -Value 'Aktywowany (licencja zbiorcza MAK)' -Details ($d -join "`n") `
                    -Advice 'Licencja zbiorcza (MAK) pochodzi zwykle z umowy firmowej lub edukacyjnej. Upewnij się, że klient ma prawo jej używać.' `
                    -CustomerStatus info -CustomerValue 'Aktywowany (licencja zbiorcza)'
            } else {
                Add-Finding 'Aktywacja Windows' -Status ok -Value ('Aktywowany' + $(if ($channel) { " (kanał: $channel)" } else { '' })) -Details ($d -join "`n")
            }
        } else {
            Add-Finding 'Aktywacja Windows' -Status crit -Value $statusMap[$ls] -Details ($d -join "`n") `
                -Advice 'Windows nie jest aktywowany: ogranicza personalizację i może wyświetlać komunikaty. Aktywuj kluczem cyfrowym/OEM z BIOS lub zakup licencję.'
        }
    }
    if ($svc -and $svc.PSObject.Properties['OA3xOriginalProductKey'] -and $svc.OA3xOriginalProductKey) {
        Add-Finding 'Klucz OEM zapisany w BIOS/UEFI' -Status info -Value ([string]$svc.OA3xOriginalProductKey) `
            -Details 'Klucz fabryczny zapisany w firmware płyty - pozwala ponownie aktywować Windows po reinstalacji bez wpisywania klucza.' -Private
    }
}

Register-Check -Id 'up.cbs' -Category 'updates' -Title 'Integralność magazynu składników Windows (DISM)' -NeedsAdmin -Script {
    if (-not (Get-Command Repair-WindowsImage -ErrorAction SilentlyContinue)) { return }
    $r = $null
    try { $r = Repair-WindowsImage -Online -CheckHealth -ErrorAction Stop } catch { Write-SdLog ('DISM CheckHealth: ' + $_.Exception.Message) 'WARN' }
    if (-not $r) {
        Add-Finding 'Magazyn składników (DISM CheckHealth)' -Status skip -Value 'Nie udało się odczytać stanu (DISM niedostępny).'
        return
    }
    $s = [string]$r.ImageHealthState
    if ($s -eq 'Healthy') { Add-Finding 'Magazyn składników (DISM CheckHealth)' -Status ok -Value 'Zdrowy - brak wykrytych uszkodzeń' }
    elseif ($s -eq 'Repairable') {
        Add-Finding 'Magazyn składników (DISM CheckHealth)' -Status warn -Value 'Uszkodzony, ale możliwy do naprawy' `
            -Advice 'Uruchom jako administrator: DISM /Online /Cleanup-Image /RestoreHealth, a następnie sfc /scannow, po czym uruchom ponownie komputer.'
    }
    else {
        Add-Finding 'Magazyn składników (DISM CheckHealth)' -Status crit -Value "Stan: $s" `
            -Advice 'Magazyn składników jest uszkodzony i nie można go naprawić online. Użyj naprawy za pomocą źródła (DISM /RestoreHealth /Source:...) lub zainstaluj system z zachowaniem plików.'
    }
}

function Get-SdPendingUpdateVerdict {
    # Oczekujące aktualizacje (wiersze: Aktualizacja, Definicje) -> { Status; Value; Advice }. Same definicje antywirusa
    # nie są problemem: ukazują się kilka razy dziennie i Windows instaluje je sam.
    param($Rows)
    $all = @($Rows | Where-Object { $null -ne $_ })
    $other = @($all | Where-Object { -not $_.Definicje })
    $defN = $all.Count - $other.Count
    $defTxt = $(if ($defN -gt 0) { 'definicje antywirusa Windows instaluje sam (oczekuje: ' + $defN + ')' } else { '' })
    if ($other.Count -eq 0) {
        return [pscustomobject]@{ Status = 'ok'; Value = ('Brak oczekujących aktualizacji systemu' + $(if ($defTxt) { '; ' + $defTxt } else { '' })); Advice = '' }
    }
    $v = Format-Count $other.Count 'aktualizacja oczekuje' 'aktualizacje oczekują' 'aktualizacji oczekuje'
    if ($defTxt) { $v += '; ' + $defTxt }
    return [pscustomobject]@{ Status = 'warn'; Value = $v; Advice = 'Zainstaluj oczekujące aktualizacje (po wykonaniu kopii danych), a następnie uruchom ponownie komputer.' }
}

Register-Check -Id 'up.pendingsearch' -Category 'updates' -Title 'Dostępne aktualizacje (wyszukiwanie online)' -Level Full -NeedsInternet -Script {
    $job = Start-Job -ScriptBlock {
        try {
            $s = New-Object -ComObject Microsoft.Update.Session
            # sterowniki wyszukuje osobny test (kategoria Sterowniki) - tu tylko oprogramowanie
            $r = $s.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
            $out = @()
            foreach ($u in $r.Updates) {
                $cat = ''
                $def = 0
                foreach ($c in $u.Categories) {
                    if (-not $cat) { $cat = [string]$c.Name }
                    # klasyfikacja „Definition Updates” - stały identyfikator Windows Update, niezależny od języka
                    if ([string]$c.CategoryID -eq 'e0789628-ce08-4437-be74-2495b842f43b') { $def = 1 }
                }
                # tytuł na końcu: może zawierać znak |
                $out += ('{0}|{1}|{2}|{3}' -f $def, [math]::Round([double]$u.MaxDownloadSize / 1MB, 0), $cat, $u.Title)
            }
            return $out
        } catch { return @('ERR|' + $_.Exception.Message) }
    }
    $done = Wait-Job -Job $job -Timeout 120
    if (-not $done) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue; Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Add-Finding 'Dostępne aktualizacje' -Status info -Value 'Wyszukiwanie przerwane po 120 s (brak sieci lub bardzo wolne połączenie)'
        return
    }
    $res = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    if ($res.Count -gt 0 -and [string]$res[0] -like 'ERR|*') {
        Add-Finding 'Dostępne aktualizacje' -Status info -Value ('Nie udało się wyszukać: ' + (Limit-Text ([string]$res[0]).Substring(4) 120)) `
            -Advice 'Brak połączenia z serwerem aktualizacji lub uszkodzone komponenty Windows Update.'
        return
    }
    if ($res.Count -eq 0) { Add-Finding 'Dostępne aktualizacje' -Status ok -Value 'Brak oczekujących aktualizacji'; return }
    $rows = @($res | ForEach-Object { $p = ([string]$_) -split '\|', 4; [pscustomobject]@{ Aktualizacja = $p[3]; Kategoria = $p[2]; 'Rozmiar (MB)' = $p[1]; Definicje = ($p[0] -eq '1') } })
    Add-Table 'Dostępne aktualizacje' -Rows @($rows | Select-Object Aktualizacja, Kategoria, 'Rozmiar (MB)')
    $v = Get-SdPendingUpdateVerdict $rows
    Add-Finding 'Dostępne aktualizacje' -Status $v.Status -Value $v.Value -Details 'Lista w tabeli „Dostępne aktualizacje”.' -Advice $v.Advice
}

Register-Check -Id 'up.dotnet' -Category 'updates' -Title 'Wersje .NET Framework' -Script {
    $rel = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release' $null
    $map = [ordered]@{ 533320 = '4.8.1'; 528040 = '4.8'; 461808 = '4.7.2'; 461308 = '4.7.1'; 460798 = '4.7'; 394802 = '4.6.2'; 394254 = '4.6.1'; 393295 = '4.6'; 379893 = '4.5.2'; 378675 = '4.5.1'; 378389 = '4.5' }
    $ver = ''
    if ($rel) { foreach ($k in $map.Keys) { if ([int]$rel -ge [int]$k) { $ver = $map[$k]; break } } }
    $net35 = (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5' 'Install' 0) -eq 1
    if ($ver) {
        Add-Finding '.NET Framework' -Status info -Value (".NET Framework $ver" + $(if ($net35) { '; włączony .NET 3.5' } else { '; .NET 3.5 wyłączony' })) `
            -Details 'Starsze programy wymagają funkcji .NET Framework 3.5 (włączanie: Funkcje systemu Windows).'
    }
}
