# SerwisDiag - dostawcy danych z pamięcią podręczną (współdzieleni przez wiele testów)
# Każdy dostawca odpytuje system co najwyżej raz w trakcie skanowania.

function Get-SdCached {
    param([Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][scriptblock]$Factory)
    $c = $global:SD.Cache
    if (-not $c.ContainsKey($Key)) { $c[$Key] = @{ V = (& $Factory) } }
    return $c[$Key].V
}

function Get-SdOs  { Get-SdCached 'Os'  { Get-Cim Win32_OperatingSystem | Select-Object -First 1 } }
function Get-SdCs  { Get-SdCached 'Cs'  { Get-Cim Win32_ComputerSystem | Select-Object -First 1 } }
function Get-SdCpus { Get-SdCached 'Cpu' { Get-Cim Win32_Processor } }
function Get-SdPnp { Get-SdCached 'Pnp' { Get-Cim Win32_PnPEntity } }

function Get-SdFirmwareType {
    Get-SdCached 'Fw' {
        $t = 0
        if (Initialize-SdNative) { $t = [SdNative]::FirmwareType() }
        if ($t -eq 0 -and (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State')) { $t = 2 }
        if ($t -eq 2) { 'UEFI' } elseif ($t -eq 1) { 'BIOS' } else { 'nieznany' }
    }
}

function Get-SdWinInfo {
    Get-SdCached 'WinInfo' {
        $os = Get-SdOs
        $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        $build = 0
        if ($os) { [void][int]::TryParse([string]$os.BuildNumber, [ref]$build) }
        $ubr = 0
        if ($cv -and $cv.PSObject.Properties['UBR']) { $ubr = [int]$cv.UBR }
        $dv = ''
        if ($cv -and $cv.PSObject.Properties['DisplayVersion'] -and $cv.DisplayVersion) { $dv = [string]$cv.DisplayVersion }
        elseif ($cv -and $cv.PSObject.Properties['ReleaseId'] -and $cv.ReleaseId) { $dv = [string]$cv.ReleaseId }
        $edition = ''
        if ($cv -and $cv.PSObject.Properties['EditionID']) { $edition = [string]$cv.EditionID }
        $isServer = $false
        if ($os -and $os.ProductType -and [int]$os.ProductType -ne 1) { $isServer = $true }
        $caption = 'Windows'
        if ($os -and $os.Caption) { $caption = ([string]$os.Caption) -replace '^Microsoft\s+', '' }
        $family = 'Windows'
        if ($isServer) { $family = $caption }
        elseif ($build -ge 22000) { $family = 'Windows 11' }
        elseif ($build -ge 10240) { $family = 'Windows 10' }
        elseif ($build -eq 9600) { $family = 'Windows 8.1' }
        elseif ($build -eq 9200) { $family = 'Windows 8' }
        elseif ($build -gt 0 -and $build -lt 9200) { $family = 'Windows (starszy niż 8)' }
        $cpu = Get-SdCpus | Select-Object -First 1
        $arch = 'x86'
        if ($cpu) {
            switch ([int]$cpu.Architecture) {
                9  { $arch = 'x64' }
                12 { $arch = 'ARM64' }
                5  { $arch = 'ARM' }
                0  { $arch = 'x86' }
                default { if ([Environment]::Is64BitOperatingSystem) { $arch = 'x64' } }
            }
        } elseif ([Environment]::Is64BitOperatingSystem) { $arch = 'x64' }
        [pscustomobject]@{
            Build = $build; Ubr = $ubr; Version = $dv; Edition = $edition; Family = $family
            Caption = $caption; IsServer = $isServer; Arch = $arch
            IsLtsc = [bool]($edition -match '^(EnterpriseS|IoTEnterpriseS|EnterpriseSN)')
            IsIot = [bool]($edition -match '^IoT')
            IsEntEdu = [bool]($edition -match '^(Enterprise|Education|IoTEnterprise|EnterpriseN|EducationN)')
        }
    }
}

function Test-SdLaptop {
    Get-SdCached 'IsLaptop' {
        $enc = Get-Cim Win32_SystemEnclosure | Select-Object -First 1
        $types = @()
        if ($enc -and $enc.ChassisTypes) { $types = @($enc.ChassisTypes | ForEach-Object { [int]$_ }) }
        $laptopTypes = @(8, 9, 10, 11, 14, 30, 31, 32)
        $deskTypes = @(3, 4, 5, 6, 7, 13, 15, 16, 17, 23, 24, 35, 36)
        $lap = $false; $desk = $false
        foreach ($t in $types) {
            if ($laptopTypes -contains $t) { $lap = $true }
            if ($deskTypes -contains $t) { $desk = $true }
        }
        if ($lap) { $true }
        elseif ($desk) { $false }
        else { (@(Get-Cim Win32_Battery).Count -gt 0) }
    }
}

function Test-SdVm {
    Get-SdCached 'IsVM' {
        $cs = Get-SdCs
        $s = ''
        if ($cs) { $s = (Join-NonEmpty @($cs.Manufacturer, $cs.Model)) }
        [bool]($s -match 'VMware|VirtualBox|Virtual Machine|KVM|QEMU|Xen|Parallels|Bochs|innotek|Hyper-V')
    }
}

function Get-SdTpm {
    Get-SdCached 'Tpm' {
        $r = [pscustomobject]@{ Present = $false; Enabled = $null; Activated = $null; Version = ''; Manufacturer = ''; Source = '' }
        if ($global:SD.IsAdmin) {
            $t = Get-Cim -Namespace 'root\cimv2\Security\MicrosoftTpm' -Class Win32_Tpm | Select-Object -First 1
            if ($t) {
                $r.Present = $true
                $r.Source = 'Win32_Tpm'
                $r.Enabled = [bool]$t.IsEnabled_InitialValue
                $r.Activated = [bool]$t.IsActivated_InitialValue
                $spec = [string]$t.SpecVersion
                if ($spec) { $r.Version = ($spec -split ',')[0].Trim() }
                $r.Manufacturer = [string]$t.ManufacturerIdTxt
                return $r
            }
        }
        # Bez uprawnień administratora: rozpoznanie po urządzeniu ACPI w Menedżerze urządzeń.
        $dev = @(Get-SdPnp | Where-Object {
                $_.PNPDeviceID -match '^ACPI\\(MSFT0101|PNP0C31|IFX0|INTC0102|NTC0|ATM12|BCM01|SMO0|STM0|WEC0|SNP0|NSC0)' -or
                ($_.PNPClass -eq 'SecurityDevices' -and $_.Name -match 'Trusted Platform|\bTPM\b')
            }) | Select-Object -First 1
        if ($dev) {
            $r.Present = $true
            $r.Source = 'PnP'
            if ($dev.PNPDeviceID -match 'MSFT0101' -or $dev.Name -match '2\.0') { $r.Version = '2.0' }
            elseif ($dev.PNPDeviceID -match 'PNP0C31' -or $dev.Name -match '1\.2') { $r.Version = '1.2' }
            $r.Enabled = ($dev.ConfigManagerErrorCode -eq 0)
        }
        $r
    }
}

function Get-SdSecureBoot {
    Get-SdCached 'SecureBoot' {
        $r = [pscustomobject]@{ Firmware = (Get-SdFirmwareType); Enabled = $null; Known = $false }
        if ($r.Firmware -eq 'UEFI') {
            $v = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 'UEFISecureBootEnabled'
            if ($null -ne $v) { $r.Enabled = ([int]$v -eq 1); $r.Known = $true }
            elseif ($global:SD.IsAdmin) {
                try { $r.Enabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop); $r.Known = $true } catch { }
            }
        }
        $r
    }
}

# ---------------------------------------------------------------- heurystyka procesora (generacja, rok, zgodność z Windows 11)
# To szacunek na podstawie nazwy procesora; oficjalna lista Microsoft jest rozstrzygająca.

function Get-SdCpuInfo {
    param([string]$Name)
    $r = [pscustomobject]@{ Vendor = ''; Gen = ''; Year = $null; Win11 = $null; Note = '' }
    if (-not $Name) { return $r }
    $intelYears = @{ 1 = 2010; 2 = 2011; 3 = 2012; 4 = 2013; 5 = 2015; 6 = 2015; 7 = 2017; 8 = 2017; 9 = 2018; 10 = 2019; 11 = 2020; 12 = 2021; 13 = 2022; 14 = 2023 }
    $ryzenYears = @{ 1 = 2017; 2 = 2018; 3 = 2019; 4 = 2020; 5 = 2021; 6 = 2022; 7 = 2023; 8 = 2024; 9 = 2024 }

    if ($Name -match 'Intel') {
        $r.Vendor = 'Intel'
        $gen = 0
        if ($Name -match 'Core\(TM\) Ultra|Core Ultra') {
            $r.Gen = 'Core Ultra'; $r.Year = 2023; $r.Win11 = $true
        }
        elseif ($Name -match 'Core\(TM\)\s+i[3579]-N\d{3}|Intel\(R\)\s+N\d{2,3}\b') {
            $r.Gen = 'Alder Lake-N'; $r.Year = 2023; $r.Win11 = $true
        }
        elseif ($Name -match '(Pentium|Celeron)\(R\)\s+(?:CPU\s+)?(?:(?:Gold|Silver)\s+)?([GNJ])\s?(\d{4,5})') {
            $isPentium = ($Matches[1] -eq 'Pentium'); $series = $Matches[2]; $num = [int]$Matches[3]
            $r.Gen = $Matches[1]
            if ($isPentium) { if ($series -eq 'G') { $r.Win11 = ($num -ge 5000) } else { $r.Win11 = ($num -ge 4000) } }
            else { if ($series -eq 'G') { $r.Win11 = ($num -ge 4900) } else { $r.Win11 = ($num -ge 4000) } }
        }
        elseif ($Name -match 'Core\(TM\)\s+i[3579](?:\s+CPU)?[\s-]+(\d{3,5})') {
            $digits = $Matches[1]
            switch ($digits.Length) {
                3 { $gen = 1 }
                4 { if ($digits.Substring(0, 1) -eq '1') { $gen = [int]$digits.Substring(0, 2) } else { $gen = [int]$digits.Substring(0, 1) } }
                5 { $gen = [int]$digits.Substring(0, 2) }
            }
        }
        elseif ($Name -match 'Core\(TM\)\s+i[3579]\s+CPU\s+[MUL]\s+\d{3}') { $gen = 1 }
        elseif ($Name -match 'Core\(TM\)\s+m[3579]-(\d)') { $gen = [int]$Matches[1]; $r.Gen = 'Core M' }
        elseif ($Name -match 'Core\(TM\)\s?2|Core2|Atom|Pentium|Celeron') {
            $r.Gen = 'Starsza architektura'; $r.Year = 2009; $r.Win11 = $false
        }
        elseif ($Name -match 'Xeon') { $r.Gen = 'Xeon'; $r.Note = 'Zgodność procesorów Xeon należy sprawdzić na liście Microsoft.' }

        # Nazwa w Windows 11 zawiera często prefiks "12th Gen" - jest dokładniejszy niż numer modelu.
        if ($Name -match '(\d{1,2})(?:st|nd|rd|th) Gen') { $gen = [int]$Matches[1] }
        if ($gen -gt 0) {
            if (-not $r.Gen) { $r.Gen = "$gen. generacja Core" }
            if ($intelYears.ContainsKey($gen)) { $r.Year = $intelYears[$gen] } elseif ($gen -gt 14) { $r.Year = 2024 }
            $r.Win11 = ($gen -ge 8)
            if ($gen -eq 7) { $r.Note = 'Generacja 7 jest zgodna tylko w nielicznych wyjątkach (np. i7-7820HQ w Surface Studio 2).' }
        }
    }
    elseif ($Name -match 'AMD') {
        $r.Vendor = 'AMD'
        if ($Name -match 'Ryzen\s+AI') { $r.Gen = 'Ryzen AI'; $r.Year = 2024; $r.Win11 = $true }
        elseif ($Name -match 'Ryzen\s+(?:Threadripper\s+)?(?:PRO\s+)?[3579]?\s*(?:PRO\s+)?(\d)(\d{3})') {
            $series = [int]$Matches[1]
            $r.Gen = "Ryzen serii ${series}000"
            if ($ryzenYears.ContainsKey($series)) { $r.Year = $ryzenYears[$series] }
            $r.Win11 = ($series -ge 2)
        }
        elseif ($Name -match 'Athlon') {
            $r.Gen = 'Athlon'
            $r.Win11 = [bool]($Name -match 'Athlon.*(3\d{3}|4\d{3}|300U)')
        }
        elseif ($Name -match 'FX\(tm\)|FX-|A\d+-\d|Phenom|Sempron|Turion|E-\d{3}|C-\d{2}') {
            $r.Gen = 'Starsza architektura'; $r.Year = 2012; $r.Win11 = $false
        }
        elseif ($Name -match 'EPYC') { $r.Gen = 'EPYC' }
    }
    elseif ($Name -match 'Snapdragon|Qualcomm|Microsoft SQ|Apple|ARM') {
        $r.Vendor = 'ARM'; $r.Gen = 'ARM64'; $r.Win11 = $true
    }
    return $r
}

# ---------------------------------------------------------------- wyszukiwanie w bazie wiedzy

function Get-SdVendorName {
    # Z identyfikatora sprzętu (PCI\VEN_8086&DEV_... lub USB\VID_8087&PID_...) zwraca nazwę producenta.
    param([string]$HardwareId)
    if (-not $HardwareId) { return '' }
    $d = Get-SdData 'pci-vendors'
    if (-not $d) { return '' }
    if ($HardwareId -match 'VEN_([0-9A-Fa-f]{4})') {
        $k = $Matches[1].ToUpper()
        if ($d.Pci.ContainsKey($k)) { return $d.Pci[$k] }
    }
    if ($HardwareId -match 'VID_([0-9A-Fa-f]{4})') {
        $k = $Matches[1].ToUpper()
        if ($d.Usb.ContainsKey($k)) { return $d.Usb[$k] }
        if ($d.Pci.ContainsKey($k)) { return $d.Pci[$k] }
    }
    return ''
}

function Get-SdBugcheckInfo {
    # Przyjmuje kod w postaci "0x000000d1" lub liczby; zwraca @{ Code; Name; Cause; Hint }.
    param($Code)
    $num = 0
    try {
        if ($Code -is [string]) { $num = [Convert]::ToInt64(($Code -replace '^0x', ''), 16) } else { $num = [int64]$Code }
    } catch { return $null }
    $key = $num.ToString('X')
    $d = Get-SdData 'bugchecks'
    $info = $null
    if ($d -and $d.ContainsKey($key)) { $info = $d[$key] }
    return [pscustomobject]@{
        Code  = ('0x' + $num.ToString('X8'))
        Name  = if ($info) { $info.Name } else { 'Nieznany kod' }
        Cause = if ($info) { $info.Cause } else { 'unknown' }
        Hint  = if ($info) { $info.Hint } else { 'Brak opisu w lokalnej bazie – wyszukaj kod STOP w dokumentacji Microsoft.' }
    }
}

function Get-SdPnpErrorText {
    param([int]$Code)
    $d = Get-SdData 'pnp-errors'
    if ($d -and $d.ContainsKey([string]$Code)) { return $d[[string]$Code] }
    return "Kod błędu $Code"
}

# ---------------------------------------------------------------- aktualizacje: historia Windows Update, ostatnia poprawka systemu, ESU

# Wpisy historii WU, które nie są poprawkami systemu: definicje i platforma Defendera, MSRT, komponenty usługi aktualizacji.
$global:SdNotOsPatch = 'KB2267602|KB4052623|KB890830|KB915597|KB2461484|KB2310138|KB5007651|KB4023057|KB5001716|KB5005463|Defender|Security Intelligence|analizy zabezpieczeń|Definition Update|usuwania złośliwego|Malicious Software Removal'

function ConvertTo-SdLocalTime {
    # Interfejs COM Windows Update zwraca daty w UTC (bez oznaczenia strefy).
    param($Date)
    if ($null -eq $Date) { return $null }
    try {
        $d = [datetime]$Date
        if ($d.Kind -eq [System.DateTimeKind]::Local) { return $d }
        return ([datetime]::SpecifyKind($d, [System.DateTimeKind]::Utc)).ToLocalTime()
    } catch { return $null }
}

function ConvertFrom-SdQfeDate {
    # Win32_QuickFixEngineering.InstalledOn: data (PowerShell sam ją konwertuje), tekst "M/d/yyyy" niezależnie
    # od języka systemu, a w starszych systemach 16 cyfr szesnastkowych (FILETIME).
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { if ($Value.Year -gt 1601) { return $Value } else { return $null } }
    $t = ([string]$Value).Trim()
    if (-not $t) { return $null }
    if ($t -match '^[0-9A-Fa-f]{16}$') {
        try { return [datetime]::FromFileTime([Convert]::ToInt64($t, 16)) } catch { return $null }
    }
    $d = [datetime]::MinValue
    $fmts = [string[]]@('M/d/yyyy', 'M/d/yyyy H:mm:ss', 'M/d/yyyy h:mm:ss tt', 'yyyyMMdd', 'yyyy-MM-dd')
    if ([datetime]::TryParseExact($t, $fmts, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    return $null
}

function Test-SdOsPatchTitle {
    # Czy wpis historii WU to poprawka systemu: numer KB oraz Windows, .NET Framework albo nowy format tytułu
    # Windows 11 "(KB...) (26100.1234)". Bez Defendera, MSRT, sterowników, Office i aplikacji ze Sklepu -
    # te aktualizują się niezależnie od łatania systemu.
    param([string]$Title)
    if (-not $Title) { return $false }
    return ($Title -match '\bKB\d{6,7}\b' -and $Title -match 'Windows|\.NET Framework|\(KB\d{6,7}\)\s*\(\d{5}\.\d+\)' -and $Title -notmatch $global:SdNotOsPatch)
}

function Get-SdWuHistory {
    # Historia Windows Update (COM) z datami w czasie lokalnym; Error = komunikat, gdy interfejs jest niedostępny.
    Get-SdCached 'WuHistory' {
        $entries = @(); $err = ''
        try {
            $session = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            $n = $searcher.GetTotalHistoryCount()
            if ($n -gt 0) {
                $h = $searcher.QueryHistory(0, [math]::Min($n, 300))
                foreach ($e in $h) { $entries += [pscustomobject]@{ Date = (ConvertTo-SdLocalTime $e.Date); Title = [string]$e.Title; Result = [int]$e.ResultCode; Hr = [int]$e.HResult; Op = [int]$e.Operation } }
            }
        } catch {
            $err = $_.Exception.Message
            Write-SdLog ('Windows Update COM: ' + $err) 'WARN'
        }
        [pscustomobject]@{ Entries = $entries; Error = $err }
    }
}

function Get-SdLastOsPatch {
    # Ostatnia poprawka systemu: lista zainstalowanych poprawek (QFE) i udane instalacje KB z historii WU.
    Get-SdCached 'LastOsPatch' {
        $best = $null
        $limit = (Get-Date).AddDays(1)
        foreach ($q in (Get-Cim Win32_QuickFixEngineering)) {
            $d = ConvertFrom-SdQfeDate $q.InstalledOn
            if ($d -and $d -le $limit -and (-not $best -or $d -gt $best.Date)) {
                $best = [pscustomobject]@{ Date = $d; Title = (Join-NonEmpty @($q.HotFixID, $q.Description) ' - '); Source = 'QFE' }
            }
        }
        foreach ($e in (Get-SdWuHistory).Entries) {
            if ($e.Result -ne 2 -or $e.Op -ne 1 -or -not $e.Date -or $e.Date -gt $limit -or -not (Test-SdOsPatchTitle $e.Title)) { continue }
            # QFE podaje sam dzień - wpis WU z godziną jest dokładniejszy
            if (-not $best -or $e.Date -gt $best.Date) { $best = [pscustomobject]@{ Date = $e.Date; Title = $e.Title; Source = 'WU' } }
        }
        $best
    }
}

function Get-SdEsuState {
    # Rozszerzone aktualizacje zabezpieczeń (ESU) - obecnie tylko Windows 10 22H2 (poza LTSC). Źródła:
    #  - licencja ESU (firmy/edukacja): produkt licencyjny z identyfikatorem aktywacji roku 1/2/3,
    #  - program konsumencki: ESUEligibility w kluczu ConsumerESU profilu użytkownika (3 = urządzenie zapisane, 5 = zapisane kontem Microsoft),
    #  - dowód działania: zainstalowana kompilacja nowsza niż ostatnia bezpłatna (UBR > LastFreeUbr).
    Get-SdCached 'Esu' {
        $w = Get-SdWinInfo
        $lc = Get-SdData 'lifecycle'
        $r = [pscustomobject]@{ Applies = $false; LicenseYear = 0; LicenseUntil = $null; ConsumerCode = $null; ConsumerUntil = $null; UbrAfterEos = $false; LastFreeUbr = 0; Ubr = $w.Ubr }
        $key = [string]$w.Build
        if (-not $lc -or -not $lc.Esu -or -not $lc.Esu.ContainsKey($key) -or $w.IsLtsc -or $w.IsServer) { return $r }
        $e = $lc.Esu[$key]
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $r.Applies = $true
        $r.LastFreeUbr = [int]$e.LastFreeUbr
        $r.UbrAfterEos = ($w.Ubr -gt $r.LastFreeUbr)

        $ids = @($e.ActivationIds.Keys)
        $filter = '(' + (($ids | ForEach-Object { "ID='$_'" }) -join ' OR ') + ') AND PartialProductKey IS NOT NULL'
        foreach ($p in (Get-Cim SoftwareLicensingProduct -Filter $filter)) {
            $y = [int]$e.ActivationIds[([string]$p.ID).ToLower()]
            if ($y -gt 0 -and [int]$p.LicenseStatus -eq 1 -and $y -gt $r.LicenseYear) { $r.LicenseYear = $y }
        }
        if ($r.LicenseYear -gt 0) { $r.LicenseUntil = [datetime]::ParseExact($e.Years[$r.LicenseYear], 'yyyy-MM-dd', $inv) }

        $sub = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\ConsumerESU'
        $paths = @(('HKCU:\' + $sub), ('HKLM:\' + $sub))   # nawiasy: przecinek wiąże mocniej niż +
        foreach ($k in @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue)) {
            if ($k.PSChildName -match '^S-1-5-21-[\d-]+$') { $paths += ('Registry::HKEY_USERS\' + $k.PSChildName + '\' + $sub) }
        }
        foreach ($p in $paths) {
            $v = Get-RegValue $p 'ESUEligibility' $null
            if ($null -eq $v) { continue }
            $v = [int]$v
            if ($null -eq $r.ConsumerCode -or $v -eq 3 -or $v -eq 5) { $r.ConsumerCode = $v }
            if ($v -eq 3 -or $v -eq 5) { break }
        }
        if ($r.ConsumerCode -eq 3 -or $r.ConsumerCode -eq 5) { $r.ConsumerUntil = [datetime]::ParseExact($e.Consumer, 'yyyy-MM-dd', $inv) }
        $r
    }
}

function Get-SdEsuConsumerText {
    param($Code)
    if ($null -eq $Code) { return '' }
    switch ([int]$Code) {
        1 { return 'urządzenie nie kwalifikuje się' }
        2 { return 'kwalifikuje się, ale nie jest zapisane' }
        3 { return 'urządzenie zapisane' }
        5 { return 'zapisane (konto Microsoft)' }
        8 { return 'wymaga zalogowania kontem głównym, aby się zapisać' }
        default { return ('stan nieustalony (kod {0})' -f $Code) }
    }
}

function Resolve-SdSupportStatus {
    # Ocena okresu wsparcia z uwzględnieniem ESU (funkcja czysta - testy jednostkowe).
    # Zwraca: Status, Value, Advice oraz Covered = czy system otrzymuje jeszcze poprawki bezpieczeństwa.
    param([datetime]$EndDate, [datetime]$Today, [int]$Build, [string]$VerName, [string]$LatestWin11 = '', $Esu = $null, $LastPatch = $null)
    $days = [int]($EndDate.Date - $Today.Date).TotalDays
    $endTxt = Format-Dt $EndDate -DateOnly
    $r = [pscustomobject]@{ Status = 'ok'; Value = ''; Advice = ''; Covered = $true }
    if ($days -gt 180) { $r.Value = '{0}: wsparcie do {1}' -f $VerName, $endTxt; return $r }
    if ($days -ge 0) {
        $r.Status = 'warn'
        $r.Value = '{0}: wsparcie kończy się {1} (za {2} dni)' -f $VerName, $endTxt, $days
        $r.Advice = 'Zaplanuj aktualizację systemu do nowszej wersji, zanim skończy się okres wsparcia.'
        return $r
    }
    $past = [math]::Abs($days)
    $migrate = 'Zaktualizuj do Windows 11 (jeśli sprzęt spełnia wymagania - patrz test „Gotowość na Windows 11”) albo wymień komputer.'

    # --- Windows 10 22H2 po zakończeniu wsparcia: czy komputer jest objęty ESU?
    if ($Esu -and $Esu.Applies) {
        $until = $null; $program = ''
        if ($Esu.ConsumerUntil) { $until = [datetime]$Esu.ConsumerUntil; $program = 'program konsumencki' }
        if ($Esu.LicenseUntil -and (-not $until -or [datetime]$Esu.LicenseUntil -gt $until)) { $until = [datetime]$Esu.LicenseUntil; $program = 'licencja ESU, rok ' + $Esu.LicenseYear }
        $sincePatch = $(if ($null -ne $LastPatch) { ($Today - [datetime]$LastPatch).TotalDays } else { [double]::MaxValue })
        $stale = ($sincePatch -gt 60)
        $base = '{0}: standardowe wsparcie zakończone {1}' -f $VerName, $endTxt
        if ($until -and $until.Date -ge $Today.Date) {
            $left = [int]($until.Date - $Today.Date).TotalDays
            $r.Value = '{0}; komputer jest objęty ESU ({1}) do {2}' -f $base, $program, (Format-Dt $until -DateOnly)
            $r.Status = 'info'
            $r.Advice = 'ESU to rozwiązanie przejściowe - zaplanuj przejście na nowszy system przed ' + (Format-Dt $until -DateOnly) + '. ' + $migrate
            if (-not $Esu.UbrAfterEos) {
                $r.Status = 'warn'
                $r.Value += ', ale nie zainstalowano jeszcze żadnej poprawki ESU'
                $r.Advice = 'Komputer jest zapisany do ESU, ale nie ma poprawek wydanych po zakończeniu wsparcia - uruchom Windows Update i zainstaluj aktualizacje zbiorcze. ' + $r.Advice
            } elseif ($stale) {
                $r.Status = 'warn'
                $r.Value += '; brak nowych poprawek od ponad 60 dni'
                $r.Advice = 'Sprawdź Windows Update - komputer objęty ESU powinien co miesiąc otrzymywać poprawki. ' + $r.Advice
            } elseif ($left -le 90) {
                $r.Status = 'warn'
                $r.Value += (' (zostało {0} dni)' -f $left)
            }
            return $r
        }
        if ($until) {
            # Data instalacji nie dowodzi licencji na kolejny rok (poprawkę z ostatniego miesiąca można zainstalować później),
            # więc świeża poprawka tylko łagodzi ocenę do ostrzeżenia.
            $r.Covered = $false
            $r.Value = '{0}; okres ESU ({1}) zakończył się {2}' -f $base, $program, (Format-Dt $until -DateOnly)
            $r.Advice = 'Komputer firmowy: zainstaluj klucz ESU na kolejny rok; domowy: sprawdź zapis do programu w Ustawieniach > Windows Update. ' + $migrate
            if ($Esu.UbrAfterEos -and $sincePatch -le 45) {
                $r.Status = 'warn'
                $r.Value += ('; ostatnia poprawka: {0}' -f (Format-Dt $LastPatch -DateOnly))
            } else {
                $r.Status = 'crit'
                $r.Advice = 'Komputer nie otrzymuje już poprawek. ' + $r.Advice
            }
            return $r
        }
        if ($Esu.UbrAfterEos) {
            $r.Value = '{0}; zainstalowano poprawki ESU (kompilacja {1}.{2})' -f $base, $Build, $Esu.Ubr
            if ($stale) {
                $r.Status = 'warn'
                $r.Value += ', ale od ponad 60 dni brak nowych'
                $r.Advice = 'Komputer otrzymywał poprawki ESU, ale od dawna nie ma nowych - sprawdź zapis do programu ESU i Windows Update. ' + $migrate
            } else {
                $r.Status = 'info'
                $r.Advice = 'Komputer otrzymuje rozszerzone aktualizacje zabezpieczeń (nie ustalono, w ramach którego programu). Zaplanuj przejście na nowszy system. ' + $migrate
            }
            return $r
        }
    }

    # --- brak wsparcia i brak ESU
    $r.Covered = $false
    $r.Status = $(if ($past -gt 180 -or $Build -lt 19045) { 'crit' } else { 'warn' })
    $r.Value = '{0}: wsparcie zakończone {1} ({2} dni temu)' -f $VerName, $endTxt, $past
    if ($Build -lt 10240) {
        $r.Advice = 'System nie otrzymuje aktualizacji bezpieczeństwa od lat. Zalecana instalacja nowszego systemu (Windows 10/11) albo wymiana komputera; do czasu migracji ogranicz korzystanie z internetu i poczty.'
    } elseif ($Build -lt 22000) {
        $r.Advice = 'Windows 10 nie otrzymuje już standardowych aktualizacji bezpieczeństwa. ' + $migrate
        if ($Esu -and $Esu.Applies) {
            $r.Advice += ' Na przejściowo: zapisz komputer do programu rozszerzonych aktualizacji (ESU) w Ustawieniach > Windows Update (użytkownicy domowi do 12.10.2027) lub kup klucz ESU dla firmy.'
            $ct = Get-SdEsuConsumerText $Esu.ConsumerCode
            if ($ct) { $r.Value += '; ESU: ' + $ct }
        } else {
            $r.Advice += ' Ta kompilacja jest starsza niż 22H2 - najpierw zainstaluj aktualizację funkcji (program ESU obejmuje tylko 22H2).'
        }
    } else {
        $latest = $(if ($LatestWin11) { $LatestWin11 } else { 'najnowszej' })
        $r.Advice = "Zaktualizuj Windows 11 do najnowszej wersji ($latest) przez Windows Update - ta wersja nie otrzymuje już poprawek bezpieczeństwa."
    }
    return $r
}

function Get-SdSupportInfo {
    # Okres wsparcia bieżącej kompilacji (data\lifecycle.psd1) z oceną ESU; $null, gdy brak danych lub system serwerowy.
    Get-SdCached 'Support' {
        $w = Get-SdWinInfo
        $lc = Get-SdData 'lifecycle'
        $res = $null
        if ($lc -and -not $w.IsServer) {
            $key = [string]$w.Build
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            $end = $null; $name = ''; $note = ''
            if ($w.IsLtsc) {
                $map = $(if ($w.IsIot) { $lc.IotLtsc } else { $lc.Ltsc })
                if ($map -and $map.ContainsKey($key)) { $end = [datetime]::ParseExact($map[$key], 'yyyy-MM-dd', $inv); $name = $w.Caption }
            } elseif ($lc.Builds.ContainsKey($key)) {
                $b = $lc.Builds[$key]
                $name = $b.Name; $note = $b.Note
                $end = [datetime]::ParseExact($(if ($w.IsEntEdu) { $b.Ent } else { $b.Home }), 'yyyy-MM-dd', $inv)
            }
            if ($end) {
                $esu = $null; $last = $null
                if ($end -lt (Get-Date)) { $esu = Get-SdEsuState; $last = Get-SdLastOsPatch }
                $lastDate = $null
                if ($last) { $lastDate = $last.Date }
                $st = Resolve-SdSupportStatus -EndDate $end -Today (Get-Date) -Build $w.Build -VerName $name -LatestWin11 ([string]$lc.LatestWin11) -Esu $esu -LastPatch $lastDate
                $res = [pscustomobject]@{ EndDate = $end; Name = $name; Note = $note; Esu = $esu; LastPatch = $last; Result = $st }
            }
        }
        $res
    }
}
