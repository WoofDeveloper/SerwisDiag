# Testy kategorii: Oprogramowanie i autostart

$global:SdSuspiciousPath = '\\(Temp|Tmp)\\|\\AppData\\Local\\Temp|\\Users\\Public\\|\\\$Recycle\.Bin|\\Downloads\\|\\ProgramData\\[^\\]+\.(exe|bat|cmd|vbs|ps1)$'
# Tylko silne wskaźniki: zakodowane polecenia i pobieranie/wykonywanie kodu. Samo "-WindowStyle Hidden" czy "cmd /c start" stosuje wielu legalnych producentów.
$global:SdSuspiciousCommand = '(?i)-enc(odedcommand)?\s|frombase64string|downloadstring|downloadfile|invoke-expression|\biex\b|mshta(\.exe)?\s+(http|vbscript|javascript)|certutil.*-urlcache|bitsadmin.*/transfer|regsvr32.*/i:http'

function Get-SdFileInfo {
    # Informacje o pliku wykonywalnym: producent, opis, wystawca podpisu osadzonego. Wyniki są zapamiętywane.
    param([string]$Path, [switch]$Signature)
    if (-not $Path) { return [pscustomobject]@{ Exists = $false; Company = ''; Description = ''; Signer = ''; Signed = $false } }
    $key = 'FI|' + $Path.ToLower() + '|' + [bool]$Signature
    $c = $global:SD.Cache
    if ($c.ContainsKey($key)) { return $c[$key] }
    $res = [pscustomobject]@{ Exists = $false; Company = ''; Description = ''; Signer = ''; Signed = $false }
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $res.Exists = $true
            try {
                $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
                $res.Company = [string]$vi.CompanyName
                $res.Description = [string]$vi.FileDescription
            } catch { }
            if ($Signature) {
                try {
                    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($Path)
                    if ($cert) {
                        $res.Signed = $true
                        if ($cert.Subject -match 'CN=("[^"]+"|[^,]+)') { $res.Signer = $Matches[1].Trim('"') } else { $res.Signer = $cert.Subject }
                    }
                } catch { }
            }
        }
    } catch { }
    $c[$key] = $res
    return $res
}

function Resolve-SdCommandPath {
    # Z polecenia (np. "C:\Program Files\X\x.exe" /silent) wyciąga ścieżkę pliku wykonywalnego.
    param([string]$Command)
    if (-not $Command) { return '' }
    $c = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    if ($c.StartsWith('"')) {
        $e = $c.IndexOf('"', 1)
        if ($e -gt 1) { return $c.Substring(1, $e - 1) }
    }
    $parts = $c -split ' '
    for ($n = $parts.Count; $n -ge 1; $n--) {
        $cand = ($parts[0..($n - 1)] -join ' ').Trim()
        if ($cand -match '\.(exe|bat|cmd|com|lnk|vbs|ps1|msc|scr|dll|js)$' -and (Test-Path -LiteralPath $cand -PathType Leaf -ErrorAction SilentlyContinue)) { return $cand }
    }
    return $parts[0]
}

function Get-SdHostPayload {
    # Gdy autostart uruchamia program-pośrednika z Windows (rundll32, regsvr32, wscript, mshta, powershell, cmd...),
    # właściwy kod jest w argumentach. Zwraca pełne ścieżki plików (DLL, skrypty, EXE) wskazanych w poleceniu.
    param([string]$Command, [string]$HostPath)
    $leaf = [System.IO.Path]::GetFileNameWithoutExtension([string]$HostPath)
    if ($leaf -notmatch '^(rundll32|regsvr32|wscript|cscript|mshta|powershell|pwsh|cmd|conhost|msiexec|forfiles)$') { return @() }
    $c = [Environment]::ExpandEnvironmentVariables([string]$Command)
    $i = $c.IndexOf($leaf, [System.StringComparison]::OrdinalIgnoreCase)
    $rest = $c
    if ($i -ge 0) { $rest = $c.Substring($i + $leaf.Length) }
    $out = @()
    foreach ($m in [regex]::Matches($rest, '(?i)(?:\b[a-z]:|\\\\)[^"*?<>|,;]*?\.(?:dll|ocx|cpl|exe|scr|com|bat|cmd|vbs|vbe|js|jse|wsf|wsh|hta|ps1|psm1)(?=$|[\s",;])')) {
        $p = $m.Value.Trim()
        if ($out -notcontains $p) { $out += $p }
    }
    return $out
}

function Get-SdServiceDll {
    # Usługi współdzielone (svchost.exe -k ...) ładują bibliotekę z wartości ServiceDll - to ona jest właściwym kodem usługi.
    param([string]$Name)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $Name
    $v = Get-RegValue ($base + '\Parameters') 'ServiceDll' $null
    if (-not $v) { $v = Get-RegValue $base 'ServiceDll' $null }
    if (-not $v) { return '' }
    return [Environment]::ExpandEnvironmentVariables([string]$v)
}

function Get-SdUserHives {
    # Załadowane gałęzie użytkowników (HKU) wraz z nazwą konta - pozwala zajrzeć do profilu klienta, gdy uruchomiono narzędzie z innego konta administratora.
    Get-SdCached 'UserHives' {
        $out = @()
        foreach ($k in (Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue)) {
            if ($k.PSChildName -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { continue }
            $name = $k.PSChildName
            try { $name = (New-Object System.Security.Principal.SecurityIdentifier($k.PSChildName)).Translate([System.Security.Principal.NTAccount]).Value } catch { }
            $out += [pscustomobject]@{ Sid = $k.PSChildName; Name = $name; Path = 'Registry::HKEY_USERS\' + $k.PSChildName }
        }
        $out
    }
}

function Get-SdInstalledApps {
    # Zainstalowane programy z rejestru: komputer (64- i 32-bit) i załadowane profile użytkowników, bez aktualizacji
    # i składników systemu. Używa go test sw.installed i kopia przed reinstalacją Windows.
    $paths = @(
        @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'komputer' }
        @{ P = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'komputer (32-bit)' }
    )
    foreach ($h in (Get-SdUserHives)) { $paths += @{ P = $h.Path + '\Software\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'użytkownik ' + $h.Name } }

    $apps = @{}
    foreach ($src in $paths) {
        foreach ($k in (Get-ChildItem -LiteralPath $src.P -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p -or -not $p.PSObject.Properties['DisplayName'] -or -not $p.DisplayName) { continue }
            if ($p.PSObject.Properties['SystemComponent'] -and $p.SystemComponent -eq 1) { continue }
            if ($p.PSObject.Properties['ParentKeyName'] -and $p.ParentKeyName) { continue }
            if ($p.PSObject.Properties['ReleaseType'] -and $p.ReleaseType -match 'Update|Hotfix|Security') { continue }
            if ([string]$p.DisplayName -match '^(KB\d+|Security Update for|Update for|Hotfix for)') { continue }
            $date = $null
            if ($p.PSObject.Properties['InstallDate'] -and [string]$p.InstallDate -match '^\d{8}$') {
                $dt = [datetime]::MinValue
                if ([datetime]::TryParseExact([string]$p.InstallDate, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { $date = $dt }
            }
            $size = $null
            if ($p.PSObject.Properties['EstimatedSize'] -and $p.EstimatedSize) { $size = [double]$p.EstimatedSize * 1KB }
            $id = ('{0}|{1}' -f $p.DisplayName, $(if ($p.PSObject.Properties['DisplayVersion']) { $p.DisplayVersion } else { '' }))
            if (-not $apps.ContainsKey($id)) {
                $apps[$id] = [pscustomobject]@{
                    Nazwa = [string]$p.DisplayName; Wersja = $(if ($p.PSObject.Properties['DisplayVersion']) { [string]$p.DisplayVersion } else { '' })
                    Producent = $(if ($p.PSObject.Properties['Publisher']) { [string]$p.Publisher } else { '' }); Zainstalowano = $date; Rozmiar = $size; Zakres = $src.Scope
                }
            }
        }
    }
    return @($apps.Values | Sort-Object Nazwa)
}

Register-Check -Id 'sw.installed' -Category 'software' -Title 'Zainstalowane programy' -Script {
    $list = @(Get-SdInstalledApps)
    if ($list.Count -eq 0) { Add-Finding 'Zainstalowane programy' -Status info -Value 'Nie odczytano listy programów'; return }

    $rows = @($list | ForEach-Object {
            [pscustomobject]@{ Nazwa = $_.Nazwa; Wersja = $_.Wersja; Producent = $_.Producent; Zainstalowano = (Format-Dt $_.Zainstalowano -DateOnly); Rozmiar = $(if ($_.Rozmiar) { Format-Size $_.Rozmiar 0 } else { '' }); Zakres = $_.Zakres }
        })
    Add-Table 'Zainstalowane programy' -Rows $rows
    $recent = @($list | Where-Object { $_.Zainstalowano -and $_.Zainstalowano -ge (Get-Date).AddDays(-30) } | Sort-Object Zainstalowano -Descending)
    if ($recent.Count -gt 0) {
        Add-Table 'Programy zainstalowane w ostatnich 30 dniach' -Rows @($recent | ForEach-Object { [pscustomobject]@{ Zainstalowano = (Format-Dt $_.Zainstalowano -DateOnly); Nazwa = $_.Nazwa; Wersja = $_.Wersja; Producent = $_.Producent } })
    }
    $many = $list.Count -gt 150
    Add-Finding 'Zainstalowane programy' -Status $(if ($many) { 'info' } else { 'ok' }) -Value ('Liczba programów: {0}{1}' -f $list.Count, $(if ($recent.Count) { '; w ostatnich 30 dniach: ' + $recent.Count } else { '' })) `
        -Advice $(if ($many) { 'Bardzo dużo zainstalowanych programów - warto usunąć nieużywane, co odciąża system i autostart.' } else { '' })

    # --- reguły oceny
    $flags = Get-SdData 'software-flags'
    if (-not $flags) { return }
    $today = Get-Date
    $byType = @{}
    foreach ($app in $list) {
        foreach ($f in $flags.Flags) {
            if ($app.Nazwa -match $f.Pattern) {
                $t = [string]$f.Type
                if ($t -eq 'eol') {
                    $end = [datetime]::ParseExact([string]$f.End, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                    if ($end -gt $today) { continue }
                }
                if (-not $byType.ContainsKey($t)) { $byType[$t] = @() }
                $byType[$t] += [pscustomobject]@{ App = $app.Nazwa; Ver = $app.Wersja; Note = $f.Note; Sev = $f.Severity; End = $f.End }
            }
        }
    }
    $titles = @{
        optimizer = 'Optymalizatory i aktualizatory sterowników'; pup = 'Programy potencjalnie niechciane (PUP)'; crack = 'Narzędzia do obchodzenia aktywacji'
        remote = 'Narzędzia zdalnego dostępu'; eol = 'Programy bez wsparcia producenta'; trial = 'Fabryczne wersje próbne'
    }
    foreach ($t in 'crack', 'pup', 'optimizer', 'eol', 'remote', 'trial') {
        if (-not $byType.ContainsKey($t)) { continue }
        $items = @($byType[$t] | Sort-Object App -Unique)
        $sev = if (@($items | Where-Object { $_.Sev -eq 'warn' }).Count -gt 0) { 'warn' } else { 'info' }
        if ($t -eq 'remote' -or $t -eq 'trial') { $sev = 'info' }
        $det = ($items | ForEach-Object { '{0} {1} - {2}' -f $_.App, $_.Ver, $_.Note }) -join "`n"
        $adv = ''
        switch ($t) {
            'crack'     { $adv = 'Zweryfikuj legalność oprogramowania i przeskanuj system; usuń narzędzie po uzyskaniu legalnej licencji.' }
            'pup'       { $adv = 'Odinstaluj wskazane programy i przeskanuj system oraz przeglądarki (AdwCleaner / Malwarebytes).' }
            'optimizer' { $adv = 'Rozważ odinstalowanie - takie programy rzadko poprawiają wydajność, a bywają przyczyną problemów.' }
            'eol'       { $adv = 'Zaktualizuj lub usuń oprogramowanie bez wsparcia - nie otrzymuje poprawek bezpieczeństwa.' }
            'remote'    { $adv = 'Potwierdź z klientem, że narzędzie zdalnego dostępu zostało zainstalowane świadomie (oszustwa „na wsparcie techniczne”). Zablokuj nieużywane.' }
            'trial'     { $adv = 'Jeśli licencja wygasła, odinstaluj program próbny (dedykowanym narzędziem producenta) i pozostaw jeden aktywny program antywirusowy.' }
        }
        $val = ($items | Select-Object -First 5 | ForEach-Object { $_.App }) -join '; '
        if ($t -eq 'crack') {
            # raport dla klienta bez nazw "aktywatorów" - technik omawia temat osobiście; ryzyko bezpieczeństwa zostaje wskazane
            Add-Finding $titles[$t] -Status $sev -Value $val -Details $det -Advice $adv `
                -CustomerTitle 'Programy wysokiego ryzyka' -CustomerStatus $sev -CustomerValue 'Wykryto programy, które często zawierają złośliwe oprogramowanie - szczegóły omówi serwisant.' `
                -CustomerAdvice 'Zalecamy usunięcie tych programów i skanowanie antywirusowe systemu.'
        } else {
            Add-Finding $titles[$t] -Status $sev -Value $val -Details $det -Advice $adv
        }
    }
    if ($byType.ContainsKey('av')) {
        $avs = @($byType['av'] | ForEach-Object { $_.App -replace '\s+\d.*$', '' } | Select-Object -Unique)
        if ($avs.Count -gt 1) {
            Add-Finding 'Zainstalowane pakiety antywirusowe' -Status info -Value ($avs -join '; ') `
                -Advice 'Kilka zainstalowanych pakietów AV (nawet nieaktywnych) to często pozostałości po poprzednich - usuń nieużywane dedykowanymi narzędziami producentów.'
        }
    }
}

function Test-SdStartupApprovedEnabled {
    # Wartość StartupApproved (Menedżer zadań > Autostart): brak wartości = włączony; ustawiony bit 0 pierwszego bajtu = wyłączony.
    param($Bytes)
    if ($Bytes -is [byte[]] -and $Bytes.Length -gt 0 -and ($Bytes[0] -band 1) -eq 1) { return $false }
    return $true
}

function New-SdStartupDisabledValue {
    # 12 bajtów jak w Menedżerze zadań: 03 00 00 00 + czas wyłączenia (FILETIME UTC).
    param([datetime]$When = (Get-Date))
    $b = New-Object byte[] 12
    $b[0] = 3
    [BitConverter]::GetBytes($When.ToFileTimeUtc()).CopyTo($b, 4)
    return , $b
}

function Get-SdStartupEntries {
    # Wpisy autostartu: rejestr Run / RunOnce (komputer, 32-bit, użytkownicy) i foldery Autostart.
    # Approved + ApprovedName - wartość StartupApproved, którą Windows (Menedżer zadań) włącza i wyłącza wpis.
    $entries = New-Object System.Collections.ArrayList
    $addEntry = {
        param($name, $cmd, $source, $enabled, $owner, $approved, $approvedName, $kind)
        [void]$entries.Add([pscustomobject]@{ Name = $name; Command = $cmd; Source = $source; Enabled = $enabled; Owner = $owner; Approved = $approved; ApprovedName = $approvedName; Kind = $kind })
    }
    $sa = '\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\'
    $regTargets = @(
        @{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Src = 'Rejestr: Run (komputer)'; Approved = 'HKLM:' + $sa + 'Run'; Owner = 'wszyscy'; Kind = 'Run' }
        @{ Key = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'; Src = 'Rejestr: Run (komputer, 32-bit)'; Approved = 'HKLM:' + $sa + 'Run32'; Owner = 'wszyscy'; Kind = 'Run' }
        @{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Src = 'Rejestr: RunOnce (komputer)'; Approved = ''; Owner = 'wszyscy'; Kind = 'RunOnce' }
    )
    foreach ($h in (Get-SdUserHives)) {
        $regTargets += @{ Key = $h.Path + '\Software\Microsoft\Windows\CurrentVersion\Run'; Src = 'Rejestr: Run (użytkownik)'; Approved = $h.Path + $sa + 'Run'; Owner = $h.Name; Kind = 'Run' }
        $regTargets += @{ Key = $h.Path + '\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Src = 'Rejestr: RunOnce (użytkownik)'; Approved = ''; Owner = $h.Name; Kind = 'RunOnce' }
    }
    foreach ($t in $regTargets) {
        $p = Get-ItemProperty -LiteralPath $t.Key -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        $approved = $null
        if ($t.Approved) { $approved = Get-ItemProperty -LiteralPath $t.Approved -ErrorAction SilentlyContinue }
        foreach ($prop in $p.PSObject.Properties) {
            if ($prop.Name -match '^PS(Path|ParentPath|ChildName|Drive|Provider)$') { continue }
            $enabled = $true
            if ($approved -and $approved.PSObject.Properties[$prop.Name]) { $enabled = Test-SdStartupApprovedEnabled $approved.PSObject.Properties[$prop.Name].Value }
            & $addEntry $prop.Name ([string]$prop.Value) $t.Src $enabled $t.Owner $t.Approved $prop.Name $t.Kind
        }
    }
    # foldery Autostart (wspólny i użytkowników; stan włączenia w StartupApproved\StartupFolder)
    $folders = @(@{ P = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'); Owner = 'wszyscy'; Approved = 'HKLM:' + $sa + 'StartupFolder' })
    foreach ($up in (Get-SdUserProfiles)) {
        $hive = ''
        if ($up.SID -and (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $up.SID))) { $hive = 'Registry::HKEY_USERS\' + $up.SID + $sa + 'StartupFolder' }
        $folders += @{ P = (Join-Path $up.LocalPath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'); Owner = (Split-Path $up.LocalPath -Leaf); Approved = $hive }
    }
    foreach ($f in $folders) {
        $approved = $null
        if ($f.Approved) { $approved = Get-ItemProperty -LiteralPath $f.Approved -ErrorAction SilentlyContinue }
        foreach ($i in @(Get-ChildItem -LiteralPath $f.P -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
            $target = $i.FullName
            if ($i.Extension -eq '.lnk') { try { $target = (New-Object -ComObject WScript.Shell).CreateShortcut($i.FullName).TargetPath } catch { } }
            $enabled = $true
            if ($approved -and $approved.PSObject.Properties[$i.Name]) { $enabled = Test-SdStartupApprovedEnabled $approved.PSObject.Properties[$i.Name].Value }
            & $addEntry ($i.BaseName) ('"' + $target + '"') 'Folder Autostart' $enabled $f.Owner $f.Approved $i.Name 'Folder'
        }
    }
    return , $entries
}

function Get-SdStartupSuspicion {
    # Powód, dla którego wpis autostartu wygląda na złośliwy (te same reguły co test sw.startup); pusty napis = brak.
    param($Entry)
    $exe = Resolve-SdCommandPath $Entry.Command
    if ($exe -match $global:SdSuspiciousPath) { return ('uruchamia plik z podejrzanej lokalizacji: ' + $exe) }
    if ([string]$Entry.Command -match $global:SdSuspiciousCommand) { return 'polecenie typowe dla złośliwego oprogramowania (zakodowany lub pobierany kod)' }
    foreach ($pl in @(Get-SdHostPayload -Command $Entry.Command -HostPath $exe)) {
        if ($pl -match $global:SdSuspiciousPath -or $pl -match '\\AppData\\') { return ('{0} uruchamia plik z podejrzanej lokalizacji: {1}' -f (Split-Path $exe -Leaf), $pl) }
    }
    return ''
}

Register-Check -Id 'sw.startup' -Category 'software' -Title 'Programy uruchamiane z systemem (autostart)' -Script {
    $entries = Get-SdStartupEntries
    $suspRx = $global:SdSuspiciousPath
    if ($entries.Count -eq 0) { Add-Finding 'Autostart' -Status ok -Value 'Brak wpisów autostartu'; return }

    $rows = @(); $susp = @(); $unsigned = @(); $missing = @(); $sigChecked = 0
    foreach ($e in $entries) {
        $exe = Resolve-SdCommandPath $e.Command
        $sys = ($exe -and $exe.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase))
        $fi = $null
        $wantSig = (-not $sys) -and $e.Enabled -and ($sigChecked -lt 70)
        if ($exe) { $fi = Get-SdFileInfo $exe -Signature:$wantSig; if ($wantSig) { $sigChecked++ } }
        $note = @()
        if ($exe -and $fi -and -not $fi.Exists -and $exe -notmatch '^(cmd|rundll32|wscript|cscript|powershell|mshta|regsvr32)') { $note += 'plik nie istnieje'; if ($e.Enabled) { $missing += $e.Name } }
        if ($exe -match $suspRx) { $note += 'podejrzana lokalizacja'; if ($e.Enabled) { $susp += ('{0} ({1})' -f $e.Name, $exe) } }
        if ($wantSig -and $fi -and $fi.Exists -and -not $fi.Signed -and $fi.Company -eq '') { $note += 'brak podpisu i producenta'; $unsigned += $e.Name }
        if ($e.Command -match $global:SdSuspiciousCommand) { $note += 'polecenie typowe dla złośliwego oprogramowania'; if ($e.Enabled) { $susp += ('{0} (polecenie: {1})' -f $e.Name, (Limit-Text $e.Command 80)) } }
        $maker = ''
        if ($fi) { $maker = Join-NonEmpty @($(if ($fi.Signer) { $fi.Signer } else { $fi.Company })) }
        # program-pośrednik Windows (rundll32, wscript, powershell...) - oceniamy plik, który faktycznie uruchamia
        foreach ($pl in @(Get-SdHostPayload -Command $e.Command -HostPath $exe)) {
            $plSys = $pl.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase)
            $plSig = (-not $plSys) -and $e.Enabled -and ($sigChecked -lt 70)
            $pfi = Get-SdFileInfo $pl -Signature:$plSig
            if ($plSig) { $sigChecked++ }
            $hostName = Split-Path $exe -Leaf
            if ($pl -match $suspRx -or $pl -match '\\AppData\\') {
                $note += ('{0} uruchamia plik z podejrzanej lokalizacji' -f $hostName)
                if ($e.Enabled) { $susp += ('{0} ({1} -> {2})' -f $e.Name, $hostName, $pl) }
            } elseif (-not $pfi.Exists) {
                $note += 'plik wskazany w poleceniu nie istnieje'
                if ($e.Enabled) { $missing += $e.Name }
            } elseif ($plSig -and -not $pfi.Signed -and $pfi.Company -eq '') {
                $note += 'plik uruchamiany przez ' + $hostName + ' nie ma podpisu ani producenta'
                $unsigned += $e.Name
            }
            if ($pfi.Exists) { $maker = Join-NonEmpty @($(if ($pfi.Signer) { $pfi.Signer } else { $pfi.Company })) }
        }
        $rows += [pscustomobject]@{
            Nazwa = $e.Name; Stan = $(if ($e.Enabled) { 'włączony' } else { 'wyłączony' }); Producent = $maker; Polecenie = (Limit-Text $e.Command 110)
            Źródło = $e.Source; Użytkownik = $e.Owner; Uwagi = ($note -join '; ')
        }
    }
    Add-Table 'Programy w autostarcie' -Rows @($rows | Sort-Object @{ Expression = { if ($_.Stan -eq 'włączony') { 0 } else { 1 } } }, Nazwa)
    $active = @($rows | Where-Object { $_.Stan -eq 'włączony' })
    $d = @("Włączone wpisy: $($active.Count) (łącznie wpisów: $($rows.Count))")
    if ($susp.Count -gt 0) { $d += 'Podejrzane: ' + ($susp -join '; ') }
    if ($missing.Count -gt 0) { $d += 'Wskazują na nieistniejący plik: ' + ($missing -join ', ') }
    if ($susp.Count -gt 0) {
        Add-Finding 'Autostart' -Status warn -Value ('Włączone wpisy: {0}; podejrzane: {1}' -f $active.Count, $susp.Count) -Details ($d -join "`n") `
            -Advice 'Sprawdź podejrzane wpisy (Autoruns / Menedżer zadań > Autostart): pliki uruchamiane z katalogów tymczasowych lub z ukrywanymi poleceniami są typowe dla złośliwego oprogramowania.'
    } elseif ($active.Count -gt 15) {
        Add-Finding 'Autostart' -Status warn -Value ('Włączone wpisy: {0}' -f $active.Count) -Details ($d -join "`n") `
            -Advice 'Bardzo wiele programów startuje z systemem - spowalnia to uruchamianie. Wyłącz zbędne (Menedżer zadań > Autostart).'
    } elseif ($active.Count -gt 8) {
        Add-Finding 'Autostart' -Status info -Value ('Włączone wpisy: {0}' -f $active.Count) -Details ($d -join "`n") `
            -Advice 'Przejrzyj listę i wyłącz programy, które nie muszą startować z systemem (Menedżer zadań > Autostart).'
    } else {
        Add-Finding 'Autostart' -Status ok -Value ('Włączone wpisy: {0}' -f $active.Count) -Details ($d -join "`n")
    }
    if ($unsigned.Count -gt 0) {
        Add-Finding 'Autostart: pliki bez podpisu' -Status info -Value ($unsigned -join ', ') -Details 'Brak podpisu cyfrowego i informacji o producencie w pliku wykonywalnym.' `
            -Advice 'Zweryfikuj pochodzenie tych programów (nazwa pliku w wyszukiwarce, skan VirusTotal).'
    }
}

Register-Check -Id 'sw.services' -Category 'software' -Title 'Usługi spoza systemu Windows' -Script {
    $svc = @(Get-Cim Win32_Service -Timeout 60)
    if ($svc.Count -eq 0) { return }
    $rows = @(); $susp = @()
    foreach ($s in $svc) {
        $path = Resolve-SdCommandPath ([string]$s.PathName)
        if (-not $path) { continue }
        $isDll = $false
        if ($path -match '\\svchost\.exe$') {
            # usługa w svchost.exe: oceniamy bibliotekę ServiceDll - złośliwa biblioteka spoza Windows ukryłaby się za svchost
            $dll = Get-SdServiceDll ([string]$s.Name)
            if ($dll -and -not $dll.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase)) { $path = $dll; $isDll = $true }
        }
        if (-not $isDll -and $path.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $fi = Get-SdFileInfo $path -Signature:$isDll
        if ($fi.Company -match 'Microsoft' -and -not $isDll) { continue }
        $note = @()
        $active = ($s.State -eq 'Running' -or $s.StartMode -eq 'Auto')
        if ($isDll) {
            $note += 'biblioteka usługi svchost spoza katalogu Windows'
            if ($fi.Exists -and -not $fi.Signed -and $fi.Company -eq '' -and $active) { $susp += ('{0} (svchost, biblioteka bez podpisu i producenta: {1})' -f $s.Name, $path) }
        }
        if ($path -match $global:SdSuspiciousPath -or $path -match '\\AppData\\') { $note += 'podejrzana lokalizacja'; if ($active) { $susp += ('{0} ({1})' -f $s.Name, $path) } }
        if (-not $fi.Exists) { $note += 'plik nie istnieje' }
        $rows += [pscustomobject]@{
            Usługa = [string]$s.DisplayName; Nazwa = [string]$s.Name; Stan = [string]$s.State; Uruchamianie = [string]$s.StartMode
            Konto = [string]$s.StartName; Producent = $fi.Company; Ścieżka = (Limit-Text $path 100); Uwagi = ($note -join '; ')
        }
    }
    if ($rows.Count -eq 0) { Add-Finding 'Usługi firm trzecich' -Status ok -Value 'Brak usług spoza Windows'; return }
    Add-Table 'Usługi spoza systemu Windows' -Rows @($rows | Sort-Object Usługa)
    $running = @($rows | Where-Object { $_.Stan -eq 'Running' }).Count
    if ($susp.Count -gt 0) {
        Add-Finding 'Usługi firm trzecich' -Status warn -Value ('Usług: {0} (działa: {1}); podejrzane: {2}' -f $rows.Count, $running, $susp.Count) -Details ($susp -join "`n") `
            -Advice 'Usługi uruchamiane z katalogów użytkownika lub tymczasowych są podejrzane - zweryfikuj ich pochodzenie (services.msc, Autoruns).'
    } else {
        Add-Finding 'Usługi firm trzecich' -Status info -Value ('Usług: {0} (działa: {1})' -f $rows.Count, $running) -Details 'Pełna lista w tabeli „Usługi spoza systemu Windows”.'
    }
}

Register-Check -Id 'sw.tasks' -Category 'software' -Title 'Zadania harmonogramu spoza systemu Windows' -Level Full -Script {
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return }
    $tasks = @()
    try { $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' }) } catch { Write-SdLog ('Get-ScheduledTask: ' + $_.Exception.Message) 'WARN'; return }
    $rows = @(); $susp = @()
    foreach ($t in $tasks) {
        $act = @($t.Actions | Where-Object { $_.PSObject.Properties['Execute'] })
        $cmd = ''
        if ($act.Count -gt 0) { $cmd = ('{0} {1}' -f $act[0].Execute, $act[0].Arguments).Trim() }
        $trig = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName -replace '^MSFT_Task|Trigger$', '' } | Select-Object -Unique) -join ', '
        $note = @()
        $exe = Resolve-SdCommandPath $cmd
        if ($exe -match $global:SdSuspiciousPath) { $note += 'podejrzana lokalizacja' }
        if ($cmd -match $global:SdSuspiciousCommand) { $note += 'polecenie typowe dla złośliwego oprogramowania' }
        if ($note.Count -gt 0) { $susp += ('{0}{1} - {2}: {3}' -f $t.TaskPath, $t.TaskName, ($note -join '; '), (Limit-Text $cmd 140)) }
        $rows += [pscustomobject]@{ Zadanie = $t.TaskName; Ścieżka = $t.TaskPath; Stan = [string]$t.State; Wyzwalacze = $trig; Polecenie = (Limit-Text $cmd 110); Uwagi = ($note -join '; ') }
    }
    if ($rows.Count -eq 0) { return }
    Add-Table 'Zadania harmonogramu (spoza Microsoft)' -Rows @($rows | Sort-Object Zadanie)
    if ($susp.Count -gt 0) {
        Add-Finding 'Zadania harmonogramu' -Status warn -Value ('Zadań: {0}; podejrzane: {1}' -f $rows.Count, $susp.Count) -Details ($susp -join "`n") `
            -Advice 'Zweryfikuj podejrzane zadania (taskschd.msc) - złośliwe oprogramowanie często zapewnia sobie trwałość przez harmonogram zadań.'
    } else {
        Add-Finding 'Zadania harmonogramu' -Status info -Value ('Zadania spoza Microsoft: {0}' -f $rows.Count) -Details 'Lista w tabeli „Zadania harmonogramu (spoza Microsoft)”.'
    }
}

Register-Check -Id 'sw.processes' -Category 'software' -Title 'Podejrzane procesy' -Script {
    $procs = @(Get-Cim Win32_Process)
    $miners = 'xmrig|minerd|cpuminer|nicehash|nbminer|phoenixminer|claymore|t-rex|lolminer|cgminer|bfgminer|ethminer|cryptonight|monero|kdevtmpfsi'
    $tools = 'mimikatz|meterpreter|beacon\.exe|cobaltstrike|netcat|ncat\.exe|^nc\.exe'
    $rows = @()
    foreach ($p in $procs) {
        $name = [string]$p.Name; $path = [string]$p.ExecutablePath
        $why = @()
        if ($name -match $miners) { $why += 'nazwa typowa dla koparki kryptowalut' }
        if ($name -match $tools) { $why += 'narzędzie ofensywne / backdoor' }
        if ($path -and $path -match $global:SdSuspiciousPath) { $why += 'uruchomiony z katalogu tymczasowego/publicznego' }
        if ($path -and $name -match '^(svchost|lsass|csrss|winlogon|services|smss|wininit|explorer)\.exe$' -and $path -notlike ($env:SystemRoot + '\*')) { $why += 'nazwa procesu systemowego, ale poza katalogiem Windows' }
        if ($why.Count -gt 0) { $rows += [pscustomobject]@{ Proces = $name; PID = $p.ProcessId; Powód = ($why -join '; '); Ścieżka = $path } }
    }
    if ($rows.Count -eq 0) {
        Add-Finding 'Podejrzane procesy' -Status ok -Value ('Nie wykryto (sprawdzono procesów: {0})' -f $procs.Count)
        return
    }
    Add-Table 'Podejrzane procesy' -Rows $rows
    $st = if (@($rows | Where-Object { $_.Powód -match 'koparki|ofensywne|poza katalogiem Windows' }).Count -gt 0) { 'crit' } else { 'warn' }
    Add-Finding 'Podejrzane procesy' -Status $st -Value ((($rows | Select-Object -First 4 | ForEach-Object { $_.Proces }) -join ', ')) -Details (($rows | ForEach-Object { '{0} (PID {1}): {2} - {3}' -f $_.Proces, $_.PID, $_.Powód, $_.Ścieżka }) -join "`n") `
        -Advice 'Wskazane procesy należy zweryfikować (ścieżka, podpis, VirusTotal) i w razie potrzeby przeskanować system. Dopasowanie po nazwie bywa mylące - to wskazówka, nie wyrok.'
}
