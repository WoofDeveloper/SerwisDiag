# Testy kategorii: Bezpieczeństwo

Register-Check -Id 'se.av' -Category 'security' -Title 'Ochrona antywirusowa' -Script {
    $products = @(Get-Cim -Namespace 'root\SecurityCenter2' -Class AntivirusProduct)
    $mp = $null
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { Write-SdLog ('Get-MpComputerStatus: ' + $_.Exception.Message) 'INFO' }
    }
    $rows = @(); $active = @(); $outdated = @()
    foreach ($p in $products) {
        $state = [uint32]$p.productState
        $on = ($state -shr 12) -band 0xF
        $sig = ($state -shr 4) -band 0xF
        $stateTxt = switch ($on) { 0 { 'wyłączony' } 1 { 'włączony' } 2 { 'wstrzymany' } 3 { 'licencja wygasła' } default { 'nieznany' } }
        $sigTxt = if ($sig -eq 0) { 'aktualne' } else { 'NIEAKTUALNE' }
        $rows += [pscustomobject]@{ Produkt = [string]$p.displayName; Stan = $stateTxt; Definicje = $sigTxt; Ścieżka = [string]$p.pathToSignedProductExe }
        if ($on -eq 1) { $active += $p; if ($sig -ne 0) { $outdated += [string]$p.displayName } }
    }
    if ($rows.Count -gt 0) { Add-Table 'Produkty antywirusowe (Centrum zabezpieczeń)' -Rows $rows }

    $isDefender = { param($n) $n -match 'Defender|Windows Defender' }
    $thirdActive = @($active | Where-Object { -not (& $isDefender ([string]$_.displayName)) })
    $names = ($rows | ForEach-Object { '{0} ({1}, definicje {2})' -f $_.Produkt, $_.Stan, $_.Definicje }) -join '; '

    if ($products.Count -eq 0 -and -not $mp) {
        $w = Get-SdWinInfo
        if ($w.IsServer) { Add-Finding 'Program antywirusowy' -Status info -Value 'Wersja serwerowa - Centrum zabezpieczeń nie jest dostępne' }
        else {
            Add-Finding 'Program antywirusowy' -Status crit -Value 'Nie wykryto żadnego programu antywirusowego' `
                -Advice 'Komputer jest niechroniony. Włącz Microsoft Defender (Zabezpieczenia Windows) lub zainstaluj sprawdzony program antywirusowy; wykonaj pełne skanowanie.'
        }
    }
    elseif ($active.Count -eq 0) {
        Add-Finding 'Program antywirusowy' -Status crit -Value ('Żaden program nie jest aktywny: ' + $names) `
            -Advice 'Ochrona antywirusowa jest wyłączona lub licencja wygasła. Włącz Microsoft Defender lub odnów licencję programu; wykonaj pełne skanowanie systemu.'
    }
    elseif ($outdated.Count -gt 0) {
        Add-Finding 'Program antywirusowy' -Status warn -Value ('Nieaktualne definicje: ' + ($outdated -join ', ')) -Details $names `
            -Advice 'Zaktualizuj definicje wirusów (połączenie z internetem, usługa Windows Update / aktualizator programu).'
    }
    elseif ($thirdActive.Count -gt 1) {
        Add-Finding 'Program antywirusowy' -Status warn -Value ('Aktywnych kilka programów antywirusowych: ' + (($thirdActive | ForEach-Object { $_.displayName }) -join ', ')) -Details $names `
            -Advice 'Dwa aktywne programy antywirusowe konfliktują ze sobą i spowalniają system. Pozostaw jeden, drugi odinstaluj (zwykle dedykowanym narzędziem producenta).'
    }
    else {
        Add-Finding 'Program antywirusowy' -Status ok -Value $names
    }

    if ($mp) {
        $d = @()
        $d += "Usługa Defender: $(if ($mp.AMServiceEnabled) { 'działa' } else { 'zatrzymana' }); ochrona w czasie rzeczywistym: $(if ($mp.RealTimeProtectionEnabled) { 'włączona' } else { 'wyłączona' })"
        if ($mp.PSObject.Properties['AMRunningMode'] -and $mp.AMRunningMode) { $d += "Tryb pracy: $($mp.AMRunningMode)" }
        if ($mp.AntivirusSignatureLastUpdated) { $d += "Definicje zaktualizowano: $(Format-Dt $mp.AntivirusSignatureLastUpdated); wiek: $($mp.AntivirusSignatureAge) dn." }
        if ($null -ne $mp.QuickScanAge -and $mp.QuickScanAge -lt 4000) { $d += "Ostatnie szybkie skanowanie: $($mp.QuickScanAge) dn. temu" }
        if ($null -ne $mp.FullScanAge -and $mp.FullScanAge -lt 4000) { $d += "Ostatnie pełne skanowanie: $($mp.FullScanAge) dn. temu" } else { $d += 'Pełne skanowanie: nigdy nie wykonano' }
        if ($mp.PSObject.Properties['IsTamperProtected']) { $d += "Ochrona przed manipulacją: $(if ($mp.IsTamperProtected) { 'włączona' } else { 'wyłączona' })" }
        $passive = ($mp.PSObject.Properties['AMRunningMode'] -and [string]$mp.AMRunningMode -match 'Passive')
        $age = 0; if ($null -ne $mp.AntivirusSignatureAge) { $age = [int]$mp.AntivirusSignatureAge }
        if (-not $passive -and $mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled -eq $false) {
            Add-Finding 'Microsoft Defender' -Status crit -Value 'Ochrona w czasie rzeczywistym wyłączona' -Details ($d -join "`n") `
                -Advice 'Włącz ochronę w czasie rzeczywistym w Zabezpieczeniach Windows. Jeśli wyłącza się samoczynnie, sprawdź obecność złośliwego oprogramowania i zasady grupy.'
        }
        elseif (-not $passive -and $age -gt 30) {
            Add-Finding 'Microsoft Defender' -Status crit -Value "Definicje nieaktualne od $age dni" -Details ($d -join "`n") -Advice 'Zaktualizuj definicje (Zabezpieczenia Windows > Ochrona przed wirusami > Aktualizacje) i sprawdź Windows Update.'
        }
        elseif (-not $passive -and $age -gt 7) {
            Add-Finding 'Microsoft Defender' -Status warn -Value "Definicje mają $age dni" -Details ($d -join "`n") -Advice 'Zaktualizuj definicje (Zabezpieczenia Windows > Ochrona przed wirusami > Aktualizacje).'
        }
        elseif ($passive) {
            Add-Finding 'Microsoft Defender' -Status info -Value 'Tryb pasywny (aktywny jest inny program antywirusowy)' -Details ($d -join "`n")
        }
        else {
            $neverFull = ($null -eq $mp.FullScanAge -or $mp.FullScanAge -ge 4000)
            Add-Finding 'Microsoft Defender' -Status $(if ($neverFull) { 'info' } else { 'ok' }) -Value ('Aktywny; definicje {0} dn.; ochrona w czasie rzeczywistym {1}' -f $age, $(if ($mp.RealTimeProtectionEnabled) { 'włączona' } else { 'wyłączona' })) -Details ($d -join "`n") `
                -Advice $(if ($neverFull) { 'Nie wykonano jeszcze pełnego skanowania - przy diagnostyce podejrzanego komputera uruchom pełne skanowanie.' } else { '' })
        }
    }
}

Register-Check -Id 'se.defexcl' -Category 'security' -Title 'Wykluczenia Microsoft Defender' -NeedsAdmin -Script {
    if (-not (Get-Command Get-MpPreference -ErrorAction SilentlyContinue)) { return }
    $p = $null
    try { $p = Get-MpPreference -ErrorAction Stop } catch { return }
    $paths = @($p.ExclusionPath | Where-Object { $_ })
    $exts = @($p.ExclusionExtension | Where-Object { $_ })
    $procs = @($p.ExclusionProcess | Where-Object { $_ })
    $total = $paths.Count + $exts.Count + $procs.Count
    if ($total -eq 0) { Add-Finding 'Wykluczenia Defender' -Status ok -Value 'Brak wykluczeń'; return }
    $rows = @()
    foreach ($x in $paths) { $rows += [pscustomobject]@{ Rodzaj = 'Ścieżka'; Wartość = $x } }
    foreach ($x in $exts) { $rows += [pscustomobject]@{ Rodzaj = 'Rozszerzenie'; Wartość = $x } }
    foreach ($x in $procs) { $rows += [pscustomobject]@{ Rodzaj = 'Proces'; Wartość = $x } }
    Add-Table 'Wykluczenia Microsoft Defender' -Rows $rows -Private
    $risky = @($paths | Where-Object { $_ -match '^[A-Za-z]:\\?$|\\Users\\?$|\\Temp\\?$|\\AppData\\?$|\\Windows\\?$|\\Downloads\\?$' })
    if ($risky.Count -gt 0) {
        Add-Finding 'Wykluczenia Defender' -Status warn -Value ('Szerokie wykluczenia: ' + ($risky -join '; ')) `
            -Details 'Wykluczenie całego dysku lub katalogów użytkownika/temp wyłącza ochronę dla tych miejsc - często robią to cracki i złośliwe programy.' `
            -Advice 'Sprawdź, kto i po co dodał wykluczenia; usuń zbędne (Zabezpieczenia Windows > Wykluczenia).'
    } else {
        Add-Finding 'Wykluczenia Defender' -Status info -Value (Format-Count $total 'wykluczenie' 'wykluczenia' 'wykluczeń') -Details 'Lista w tabeli (widoczna tylko w raporcie technicznym).' `
            -Advice 'Upewnij się, że każde wykluczenie jest uzasadnione (np. katalog narzędzia deweloperskiego).'
    }
}

Register-Check -Id 'se.firewall' -Category 'security' -Title 'Zapora systemu Windows' -Script {
    $profiles = @(
        @{ Key = 'DomainProfile'; Label = 'domenowy' }
        @{ Key = 'StandardProfile'; Label = 'prywatny' }
        @{ Key = 'PublicProfile'; Label = 'publiczny' }
    )
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy'
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall'
    $states = @(); $off = @()
    foreach ($p in $profiles) {
        $v = Get-RegValue ($base + '\' + $p.Key) 'EnableFirewall' $null
        $pv = Get-RegValue ($pol + '\' + $p.Key) 'EnableFirewall' $null
        if ($null -ne $pv) { $v = $pv }
        if ($null -eq $v) { continue }
        $on = ([int]$v -eq 1)
        $states += ('{0}: {1}' -f $p.Label, $(if ($on) { 'włączona' } else { 'WYŁĄCZONA' }))
        if (-not $on) { $off += $p.Label }
    }
    if ($states.Count -eq 0) { return }
    $thirdFw = @(Get-Cim -Namespace 'root\SecurityCenter2' -Class FirewallProduct | Where-Object { $_.displayName -notmatch 'Windows' -and ((([uint32]$_.productState) -shr 12) -band 0xF) -eq 1 })
    if ($off.Count -eq 0) {
        Add-Finding 'Zapora systemu Windows' -Status ok -Value ($states -join '; ')
    } elseif ($thirdFw.Count -gt 0) {
        Add-Finding 'Zapora systemu Windows' -Status info -Value ($states -join '; ') -Details ('Aktywna zapora innego producenta: ' + (($thirdFw | ForEach-Object { $_.displayName }) -join ', '))
    } elseif ($off.Count -ge 3) {
        Add-Finding 'Zapora systemu Windows' -Status crit -Value ($states -join '; ') `
            -Advice 'Zapora jest wyłączona we wszystkich profilach. Włącz ją (Zabezpieczenia Windows > Zapora i ochrona sieci), chyba że działa zapora innego producenta.'
    } else {
        Add-Finding 'Zapora systemu Windows' -Status warn -Value ($states -join '; ') -Advice 'Włącz zaporę we wszystkich profilach sieciowych, zwłaszcza w publicznym.'
    }
}

Register-Check -Id 'se.uac' -Category 'security' -Title 'Kontrola konta użytkownika (UAC)' -Script {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $lua = Get-RegValue $key 'EnableLUA' 1
    $admin = Get-RegValue $key 'ConsentPromptBehaviorAdmin' 5
    if ([int]$lua -eq 0) {
        Add-Finding 'Kontrola konta użytkownika (UAC)' -Status crit -Value 'Wyłączona' `
            -Advice 'UAC jest wyłączone - programy mogą zmieniać system bez zgody użytkownika. Włącz UAC (Zmień ustawienia kontroli konta użytkownika) i uruchom ponownie komputer.'
    } elseif ([int]$admin -eq 0) {
        Add-Finding 'Kontrola konta użytkownika (UAC)' -Status warn -Value 'Włączona, ale administrator nie otrzymuje powiadomień' `
            -Advice 'Ustaw poziom UAC co najmniej „Powiadamiaj tylko, gdy aplikacje próbują wprowadzić zmiany”.'
    } else {
        Add-Finding 'Kontrola konta użytkownika (UAC)' -Status ok -Value 'Włączona'
    }
}

Register-Check -Id 'se.bitlocker' -Category 'security' -Title 'Szyfrowanie dysków (BitLocker)' -NeedsAdmin -Script {
    $vols = @(Get-Cim -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -Class Win32_EncryptableVolume)
    if ($vols.Count -eq 0) {
        Add-Finding 'Szyfrowanie dysków (BitLocker)' -Status info -Value 'Niedostępne w tej edycji systemu lub brak woluminów szyfrowanych'
        return
    }
    $on = @(); $rows = @()
    foreach ($v in $vols) {
        $ps = [int]$v.ProtectionStatus
        $txt = switch ($ps) { 0 { 'wyłączone' } 1 { 'WŁĄCZONE' } default { 'nieznane' } }
        $rows += [pscustomobject]@{ Wolumin = [string]$v.DriveLetter; 'Ochrona BitLocker' = $txt }
        if ($ps -eq 1) { $on += [string]$v.DriveLetter }
    }
    Add-Table 'BitLocker' -Rows $rows
    if ($on.Count -gt 0) {
        Add-Finding 'Szyfrowanie dysków (BitLocker)' -Status warn -Value ('Włączone na: ' + ($on -join ', ')) `
            -Details 'Dysk jest szyfrowany. Zmiana sprzętu (płyta główna, TPM), aktualizacja BIOS lub przeniesienie dysku może wymagać klucza odzyskiwania.' `
            -Advice 'UWAGA SERWISOWA: przed wymianą podzespołów, aktualizacją BIOS lub naprawą rozruchu upewnij się, że klient ma klucz odzyskiwania (konto Microsoft: aka.ms/myrecoverykey).' -Private
    } else {
        Add-Finding 'Szyfrowanie dysków (BitLocker)' -Status info -Value 'Wyłączone' `
            -Details 'Dane na dysku nie są szyfrowane - w razie kradzieży laptopa są dostępne dla osoby trzeciej.' `
            -Advice 'W laptopach rozważ włączenie szyfrowania (BitLocker / Szyfrowanie urządzenia), po zapisaniu klucza odzyskiwania.'
    }
}

Register-Check -Id 'se.platform' -Category 'security' -Title 'Secure Boot, TPM i zabezpieczenia wirtualizacyjne' -Script {
    $w = Get-SdWinInfo
    $sb = Get-SdSecureBoot
    $tpm = Get-SdTpm

    # Secure Boot
    if ($sb.Firmware -ne 'UEFI') {
        Add-Finding 'Secure Boot' -Status info -Value ('Niedostępny (tryb rozruchu: {0})' -f $sb.Firmware) `
            -Advice 'Secure Boot wymaga trybu UEFI. Windows 11 wymaga UEFI i Secure Boot; konwersja MBR→GPT (mbr2gpt) pozwala przejść z Legacy BIOS.'
    } elseif ($sb.Known -and $sb.Enabled) {
        Add-Finding 'Secure Boot' -Status ok -Value 'Włączony'
    } elseif ($sb.Known) {
        $st = if ($w.Build -ge 22000) { 'warn' } else { 'info' }
        Add-Finding 'Secure Boot' -Status $st -Value 'Wyłączony w BIOS/UEFI' `
            -Details 'Secure Boot chroni przed złośliwym oprogramowaniem ładowanym przed systemem; wymagany przez Windows 11 oraz część gier z zabezpieczeniami anty-cheat.' `
            -Advice 'Włącz Secure Boot w BIOS/UEFI (wymaga dysku GPT; jeśli system działa w trybie CSM/Legacy, najpierw konwersja).'
    } else {
        Add-Finding 'Secure Boot' -Status info -Value 'Nieobsługiwany przez firmware lub nie można ustalić'
    }

    # Certyfikaty Secure Boot 2023 (zastępują certyfikaty Microsoft z 2011 r., które wygasają w 2026 r.)
    if ($sb.Firmware -eq 'UEFI' -and $w.Build -ge 9600) {
        $svc = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing'
        $status = Get-RegValue $svc 'UEFICA2023Status' $null
        $capable = Get-RegValue $svc 'WindowsUEFICA2023Capable' $null
        $err = Get-RegValue $svc 'UEFICA2023Error' $null
        $d = 'Certyfikaty Microsoft Secure Boot z 2011 r. wygasają w 2026 r. Komputer musi otrzymać certyfikaty z 2023 r. (aktualizacja Windows + często BIOS producenta), aby nadal otrzymywać poprawki menedżera rozruchu.'
        if ($status -eq 'Updated') {
            Add-Finding 'Certyfikaty Secure Boot (CA 2023)' -Status ok -Value 'Zaktualizowane' -Details $d
        } elseif ($status -eq 'InProgress') {
            Add-Finding 'Certyfikaty Secure Boot (CA 2023)' -Status info -Value 'Aktualizacja w toku (wymagany restart)' -Details $d `
                -Advice 'Uruchom ponownie komputer i sprawdź ponownie.'
        } else {
            $stt = if ($sb.Known -and $sb.Enabled) { 'warn' } else { 'info' }
            $val = if ($status) { "Stan: $status" } else { 'Brak informacji o aktualizacji certyfikatów' }
            if ($null -ne $err -and [int]$err -ne 0) { $val += "; błąd aktualizacji: $err" }
            Add-Finding 'Certyfikaty Secure Boot (CA 2023)' -Status $stt -Value $val -Details $d `
                -Advice 'Zainstaluj wszystkie aktualizacje Windows i najnowszy BIOS od producenta; sprawdź komunikaty producenta komputera o aktualizacji certyfikatów Secure Boot.'
        }
    }

    # TPM
    if ($tpm.Present) {
        $en = if ($tpm.Enabled -eq $false) { 'wyłączony' } elseif ($tpm.Enabled -eq $true) { 'włączony' } else { 'stan nieznany' }
        $ver = if ($tpm.Version) { $tpm.Version } else { 'wersja nieustalona' }
        Add-Finding 'TPM' -Status $(if ($tpm.Enabled -eq $false) { 'warn' } else { 'ok' }) -Value ('TPM {0}, {1}{2}' -f $ver, $en, $(if ($tpm.Manufacturer) { ', producent ' + $tpm.Manufacturer } else { '' })) `
            -Advice $(if ($tpm.Enabled -eq $false) { 'Włącz TPM w BIOS/UEFI (fTPM / Intel PTT / AMD fTPM) - wymagany przez Windows 11 i BitLocker.' } else { '' })
    } else {
        Add-Finding 'TPM' -Status info -Value 'Nie wykryto modułu TPM' -Advice 'Sprawdź w BIOS/UEFI opcje fTPM / Intel PTT / AMD fTPM; Windows 11 wymaga TPM 2.0.'
    }

    # VBS / HVCI
    $dg = Get-Cim -Namespace 'root\Microsoft\Windows\DeviceGuard' -Class Win32_DeviceGuard | Select-Object -First 1
    if ($dg) {
        $running = @($dg.SecurityServicesRunning)
        $vbs = [int]$dg.VirtualizationBasedSecurityStatus
        $svcNames = @()
        if ($running -contains 1) { $svcNames += 'Credential Guard' }
        if ($running -contains 2) { $svcNames += 'Izolacja rdzenia (HVCI)' }
        $txt = switch ($vbs) { 2 { 'działa' } 1 { 'włączona, nieaktywna' } default { 'wyłączona' } }
        Add-Finding 'Zabezpieczenia oparte na wirtualizacji (VBS)' -Status info -Value ("$txt" + $(if ($svcNames.Count) { ': ' + ($svcNames -join ', ') } else { '' }))
    }
}

Register-Check -Id 'se.accounts' -Category 'security' -Title 'Konta użytkowników i administratorzy' -Script {
    $accts = @(Get-Cim Win32_UserAccount -Filter 'LocalAccount=True' -Timeout 30)
    if ($accts.Count -eq 0) { return }
    $admins = @()
    try {
        $sid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $grpName = ($sid.Translate([System.Security.Principal.NTAccount]).Value -split '\\')[-1]
        $g = [ADSI]("WinNT://./$grpName,group")
        foreach ($m in @($g.Invoke('Members'))) { $admins += [string]$m.GetType().InvokeMember('Name', 'GetProperty', $null, $m, $null) }
    } catch { Write-SdLog ('Administratorzy (ADSI): ' + $_.Exception.Message) 'WARN' }

    $rows = @(); $notes = @(); $worst = 'ok'
    foreach ($a in $accts) {
        $isAdm = ($admins -contains $a.Name)
        $enabled = -not $a.Disabled
        $rid = ([string]$a.SID -split '-')[-1]
        $rows += [pscustomobject]@{ Konto = $a.Name; Włączone = $(if ($enabled) { 'tak' } else { 'nie' }); Administrator = $(if ($isAdm) { 'tak' } else { '' }); 'Wymaga hasła' = $(if ($a.PasswordRequired) { 'tak' } else { 'NIE' }); Zablokowane = $(if ($a.Lockout) { 'tak' } else { '' }) }
        # Konta powiązane z kontem Microsoft / logowaniem PIN-em często mają tu "hasło nie jest wymagane" - dlatego tylko informacja.
        if ($enabled -and -not $a.PasswordRequired -and $isAdm) { $notes += ('Konto administratora „' + $a.Name + '” ma ustawione „hasło nie jest wymagane” (dla konta lokalnego ustaw hasło; konta Microsoft/PIN tak się czasem raportują)'); if ($worst -eq 'ok') { $worst = 'info' } }
        if ($enabled -and $rid -eq '501') { $notes += 'Konto Gość jest włączone'; if ($worst -eq 'ok') { $worst = 'info' } }
        if ($enabled -and $rid -eq '500') { $notes += 'Wbudowane konto Administrator jest włączone'; if ($worst -eq 'ok') { $worst = 'info' } }
    }
    Add-Table 'Konta lokalne' -Rows $rows -Private
    $enabledAdmins = @($admins | Where-Object { $n = $_; @($accts | Where-Object { $_.Name -eq $n -and -not $_.Disabled }).Count -gt 0 })
    if ($enabledAdmins.Count -gt 3) { $notes += ('Wielu administratorów lokalnych: ' + $enabledAdmins.Count); if ($worst -eq 'ok') { $worst = 'info' } }
    $val = ('Konta lokalne: {0}; administratorzy: {1}' -f $accts.Count, $admins.Count)
    if ($notes.Count -gt 0) {
        Add-Finding 'Konta użytkowników' -Status $worst -Value $val -Details ($notes -join "`n") `
            -Advice 'Ustaw hasła na kontach administratorów, wyłącz niepotrzebne konta (Gość, wbudowany Administrator) i ogranicz liczbę administratorów.'
    } else {
        Add-Finding 'Konta użytkowników' -Status ok -Value $val
    }
}

Register-Check -Id 'se.exposure' -Category 'security' -Title 'Usługi zdalnego dostępu i udostępnianie' -Script {
    $notes = @(); $worst = 'ok'
    $deny = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1
    $nla = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication' 1
    if ([int]$deny -eq 0) {
        if ([int]$nla -eq 0) { $notes += 'Pulpit zdalny (RDP) włączony BEZ uwierzytelniania na poziomie sieci (NLA)'; $worst = 'warn' }
        else { $notes += 'Pulpit zdalny (RDP) jest włączony'; if ($worst -eq 'ok') { $worst = 'info' } }
    }
    $smb1 = $null
    if ($global:SD.IsAdmin -and (Get-Command Get-SmbServerConfiguration -ErrorAction SilentlyContinue)) {
        try { $smb1 = [bool](Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol } catch { }
    }
    if ($null -eq $smb1) {
        $r = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1' $null
        if ($null -ne $r) { $smb1 = ([int]$r -ne 0) }
    }
    if ($smb1 -eq $true) { $notes += 'Włączony przestarzały protokół SMB1 (podatność wykorzystana przez WannaCry)'; $worst = 'warn' }
    $rr = Get-Service -Name RemoteRegistry -ErrorAction SilentlyContinue
    if ($rr -and $rr.Status -eq 'Running') { $notes += 'Działa usługa Zdalny rejestr'; $worst = 'warn' }
    $shares = @(Get-Cim Win32_Share | Where-Object { $_.Type -eq 0 -and $_.Name -notmatch '\$$' })
    if ($shares.Count -gt 0) {
        Add-Table 'Udostępnione foldery' -Rows @($shares | ForEach-Object { [pscustomobject]@{ Nazwa = $_.Name; Ścieżka = $_.Path; Opis = $_.Description } }) -Private
        $notes += ('Udostępnione foldery sieciowe: ' + $shares.Count)
        if (@($shares | Where-Object { $_.Path -match '^[A-Za-z]:\\?$' }).Count -gt 0) { $notes += 'Udostępniony jest cały dysk'; $worst = 'warn' }
        elseif ($worst -eq 'ok') { $worst = 'info' }
    }
    if ($notes.Count -eq 0) {
        Add-Finding 'Zdalny dostęp i udostępnianie' -Status ok -Value 'Brak wykrytych ryzykownych ustawień'
    } else {
        Add-Finding 'Zdalny dostęp i udostępnianie' -Status $worst -Value ($notes -join '; ') `
            -Advice 'Wyłącz funkcje, które nie są potrzebne (RDP, SMB1, Zdalny rejestr, udostępnione foldery). Jeśli RDP jest używany, wymagaj NLA i nie wystawiaj portu 3389 do internetu.'
    }
}

function Test-SdDefaultWinlogon {
    # Czy wartość Winlogon\Userinit lub Winlogon\Shell jest domyślna. Windows nie musi być na C:, a dopisanie po przecinku
    # drugiego programu ("...userinit.exe,C:\x\evil.exe") to typowy sposób na uruchamianie złośliwego kodu przy logowaniu.
    param([string]$Value, [ValidateSet('Userinit', 'Shell')][string]$Kind, [string]$SystemRoot = $env:SystemRoot)
    $items = @(([string]$Value).Split(',') | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })
    if ($items.Count -eq 0) { return $true }
    if ($items.Count -gt 1) { return $false }
    $v = [Environment]::ExpandEnvironmentVariables($items[0]) -replace '/', '\'
    if ($Kind -eq 'Userinit') { $ok = @('userinit.exe', 'userinit', ($SystemRoot + '\system32\userinit.exe'), ($SystemRoot + '\sysnative\userinit.exe')) }
    else { $ok = @('explorer.exe', 'explorer', ($SystemRoot + '\explorer.exe')) }
    foreach ($o in $ok) { if ($v -ieq $o) { return $true } }
    return $false
}

Register-Check -Id 'se.persistence' -Category 'security' -Title 'Ślady modyfikacji systemu (trwałość złośliwego oprogramowania)' -Script {
    $notes = @(); $crit = $false
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $shell = [string](Get-RegValue $wl 'Shell' 'explorer.exe')
    $uinit = [string](Get-RegValue $wl 'Userinit' '')
    if (-not (Test-SdDefaultWinlogon -Value $shell -Kind Shell)) { $notes += "Winlogon\Shell ma niestandardową wartość: $shell"; $crit = $true }
    if (-not (Test-SdDefaultWinlogon -Value $uinit -Kind Userinit)) { $notes += "Winlogon\Userinit ma niestandardową wartość: $uinit"; $crit = $true }
    if ((Get-RegValue $wl 'AutoAdminLogon' '0') -eq '1' -and (Get-RegValue $wl 'DefaultPassword' $null)) { $notes += 'Włączone automatyczne logowanie z hasłem zapisanym jawnym tekstem w rejestrze' }
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Windows') {
        $ai = [string](Get-RegValue $k 'AppInit_DLLs' '')
        if ($ai.Trim() -and ([int](Get-RegValue $k 'LoadAppInit_DLLs' 0)) -eq 1) { $notes += "AppInit_DLLs ładuje biblioteki do każdego procesu: $ai"; $crit = $true }
    }
    $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    $access = 'sethc.exe', 'utilman.exe', 'osk.exe', 'narrator.exe', 'magnify.exe', 'displayswitch.exe', 'atbroker.exe'
    foreach ($key in @(Get-ChildItem -LiteralPath $ifeo -ErrorAction SilentlyContinue)) {
        $dbg = Get-RegValue $key.PSPath 'Debugger' $null
        if ($dbg) {
            $nm = $key.PSChildName
            if ($access -contains $nm.ToLower()) { $notes += "Narzędzie ułatwień dostępu $nm podmienione (Debugger = $dbg) - typowa tylna furtka"; $crit = $true }
            elseif ($nm -match 'MsMpEng|MpCmdRun|NisSrv|mbam|avast|avg|kaspersky|eset|bdagent|taskmgr|regedit|cmd\.exe|powershell|mmc\.exe') { $notes += "Uruchomienie $nm jest przekierowane (Debugger = $dbg)"; $crit = $true }
        }
    }
    if ((Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'DisableAntiSpyware' 0) -eq 1) { $notes += 'Microsoft Defender wyłączony zasadą (DisableAntiSpyware)' }
    $be = @(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'BootExecute' @())
    if ($be.Count -gt 0 -and (($be -join ' ').Trim() -notmatch '^autocheck autochk \*$')) { $notes += ('BootExecute ma niestandardową wartość: ' + ($be -join ' ')) }

    if ($notes.Count -eq 0) {
        Add-Finding 'Ślady modyfikacji systemu' -Status ok -Value 'Nie wykryto typowych podmian (Winlogon, AppInit, IFEO, BootExecute)'
    } else {
        Add-Finding 'Ślady modyfikacji systemu' -Status $(if ($crit) { 'crit' } else { 'warn' }) -Value (Format-Count $notes.Count 'podejrzana zmiana' 'podejrzane zmiany' 'podejrzanych zmian') -Details ($notes -join "`n") `
            -Advice 'Takie wpisy w rejestrze są typowe dla złośliwego oprogramowania. Przeskanuj system (Defender offline, Malwarebytes, Autoruns) i przywróć domyślne wartości po upewnieniu się, że wpis nie pochodzi z legalnego programu.'
    }
}

Register-Check -Id 'se.logons' -Category 'security' -Title 'Nieudane logowania (ostatnie 24 godziny)' -Level Full -NeedsAdmin -Script {
    $since = (Get-Date).AddHours(-24)
    $ev = @(Get-SdEvents -Filter @{ LogName = 'Security'; Id = 4625; StartTime = $since } -Max 3000)
    if ($ev.Count -eq 0) {
        Add-Finding 'Nieudane logowania (24 h)' -Status ok -Value 'Brak nieudanych prób logowania'
        return
    }
    $ips = @{}; $users = @{}
    foreach ($e in $ev) {
        $d = Get-SdEventData $e
        $ip = $d['IpAddress']; if ($ip -and $ip -ne '-') { $ips[$ip] = 1 + [int]$ips[$ip] }
        $u = $d['TargetUserName']; if ($u) { $users[$u] = 1 + [int]$users[$u] }
    }
    $topIp = @($ips.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object { '{0} ×{1}' -f $_.Key, $_.Value })
    $topUser = @($users.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object { '{0} ×{1}' -f $_.Key, $_.Value })
    $d = @("Nieudanych prób: $($ev.Count)")
    if ($topIp.Count) { $d += 'Główne źródła (IP): ' + ($topIp -join ', ') }
    if ($topUser.Count) { $d += 'Najczęściej atakowane konta: ' + ($topUser -join ', ') }
    $st = if ($ev.Count -ge 500) { 'crit' } elseif ($ev.Count -ge 50) { 'warn' } else { 'info' }
    Add-Finding 'Nieudane logowania (24 h)' -Status $st -Value ('{0} w ciągu 24 godzin' -f (Format-Count $ev.Count 'próba' 'próby' 'prób')) -Details ($d -join "`n") -LastEvent (Get-SdLatestTime $ev) `
        -Advice 'Duża liczba nieudanych logowań z obcych adresów oznacza atak siłowy (zwykle na RDP/SMB wystawione do internetu). Wyłącz ekspozycję usługi, ustaw silne hasła i rozważ blokadę konta.' -Private
}
