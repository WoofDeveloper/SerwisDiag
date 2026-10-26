# SerwisDiag - sterowniki: wyszukiwanie i instalacja przez Windows Update (oficjalne, podpisane sterowniki dopasowane
# do sprzętu), Katalog Microsoft Update dla brakujących sterowników i strony ze sterownikami producentów komputerów.

# Bloki wyszukiwania i instalacji są samodzielne (bez funkcji programu), bo działają też w zadaniu w tle (Start-Job)
# i w osobnym runspace okna. Do innego runspace przekazujemy ich tekst, nie obiekt bloku.
$global:SdWuDriverSearch = {
    param([string]$Criteria = "IsInstalled=0 and Type='Driver' and IsHidden=0", [switch]$KeepResult)
    $items = New-Object System.Collections.ArrayList
    $err = ''
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        try { $session.ClientApplicationID = 'SerwisDiag' } catch { }
        $result = $session.CreateUpdateSearcher().Search($Criteria)
        if ($KeepResult) { $global:SdWuSession = $session; $global:SdWuResult = $result }
        foreach ($u in $result.Updates) {
            $date = $null
            try { if ($u.DriverVerDate) { $date = [datetime]$u.DriverVerDate } } catch { }
            [void]$items.Add([pscustomobject]@{
                    UpdateId = [string]$u.Identity.UpdateID; Title = [string]$u.Title; Class = [string]$u.DriverClass
                    Manufacturer = [string]$u.DriverManufacturer; Model = [string]$u.DriverModel; Provider = [string]$u.DriverProvider
                    HardwareId = [string]$u.DriverHardwareID; Date = $date; SizeBytes = [double]$u.MaxDownloadSize
                    Optional = [bool]$u.BrowseOnly; DeviceProblem = [int]$u.DeviceProblemNumber
                })
        }
    } catch { $err = $_.Exception.Message }
    [pscustomobject]@{ Items = @($items); Error = $err }
}

$global:SdWuDriverInstall = {
    # Pobiera i instaluje wskazane sterowniki z wyniku wyszukiwania zapamiętanego w tym runspace (-KeepResult);
    # gdy go brak - wyszukuje ponownie. Wymaga uprawnień administratora. Status: hashtable na komunikaty postępu.
    param([string[]]$UpdateIds, $Status = $null)
    $say = { param($t) if ($null -ne $Status) { $Status['Text'] = $t } }
    $out = [pscustomobject]@{ Results = @(); RebootRequired = $false; Error = '' }
    try {
        if (-not $global:SdWuResult) {
            & $say 'Wyszukiwanie sterowników w Windows Update...'
            $global:SdWuSession = New-Object -ComObject Microsoft.Update.Session
            try { $global:SdWuSession.ClientApplicationID = 'SerwisDiag' } catch { }
            $global:SdWuResult = $global:SdWuSession.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
        }
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $global:SdWuResult.Updates) {
            if (@($UpdateIds) -contains [string]$u.Identity.UpdateID) {
                if (-not $u.EulaAccepted) { $u.AcceptEula() }
                [void]$coll.Add($u)
            }
        }
        if ($coll.Count -eq 0) { $out.Error = 'Wybrane sterowniki nie są już dostępne w Windows Update - wyszukaj ponownie.'; return $out }
        & $say ('Pobieranie sterowników ({0})...' -f $coll.Count)
        $dl = $global:SdWuSession.CreateUpdateDownloader()
        $dl.Updates = $coll
        [void]$dl.Download()
        & $say ('Instalowanie sterowników ({0})...' -f $coll.Count)
        $inst = $global:SdWuSession.CreateUpdateInstaller()
        $inst.Updates = $coll
        $ir = $inst.Install()
        $res = @()
        for ($i = 0; $i -lt $coll.Count; $i++) {
            $ur = $ir.GetUpdateResult($i)
            $res += [pscustomobject]@{ Title = [string]$coll.Item($i).Title; ResultCode = [int]$ur.ResultCode; HResult = [int]$ur.HResult }
        }
        $out.Results = $res
        $out.RebootRequired = [bool]$ir.RebootRequired
    } catch { $out.Error = $_.Exception.Message }
    return $out
}

function Find-SdWuDrivers {
    # Wyszukiwanie w osobnym procesie z limitem czasu - zawieszona usługa Windows Update nie blokuje diagnostyki.
    # Zwraca { Items; Error; TimedOut }.
    param([int]$TimeoutSec = 120)
    $res = [pscustomobject]@{ Items = @(); Error = ''; TimedOut = $false }
    $job = Start-Job -ScriptBlock ([scriptblock]::Create($global:SdWuDriverSearch.ToString()))
    $done = Wait-Job -Job $job -Timeout $TimeoutSec
    if (-not $done) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $res.TimedOut = $true
        return $res
    }
    $o = @(Receive-Job -Job $job -ErrorAction SilentlyContinue) | Select-Object -Last 1
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    if (-not $o) { $res.Error = 'Wyszukiwanie nie zwróciło wyniku.'; return $res }
    $res.Error = [string]$o.Error
    $res.Items = @($o.Items | Where-Object { $null -ne $_ -and $_.UpdateId })
    return $res
}

function Select-SdDriversToInstall {
    # Domyślny wybór do instalacji: sterowniki zalecane oraz każdy, który naprawia urządzenie z błędem.
    # Opcjonalne (BrowseOnly) technik zaznacza sam.
    param($Items)
    return @($Items | Where-Object { $null -ne $_ -and (-not $_.Optional -or [int]$_.DeviceProblem -ne 0) })
}

function Get-SdDriverUpdateStatus {
    # ok - nic do zainstalowania; info - są nowsze sterowniki; warn - jest sterownik dla urządzenia z błędem.
    param($Items)
    $list = @($Items | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { return 'ok' }
    if (@($list | Where-Object { [int]$_.DeviceProblem -ne 0 }).Count -gt 0) { return 'warn' }
    return 'info'
}

function ConvertTo-SdDriverRows {
    param($Items)
    return @($Items | Where-Object { $null -ne $_ } | Sort-Object @{ Expression = { if ([int]$_.DeviceProblem -ne 0) { 0 } else { 1 } } }, Class, Title | ForEach-Object {
            [pscustomobject]@{
                Sterownik = $_.Title; Klasa = $_.Class; Producent = $(if ($_.Manufacturer) { $_.Manufacturer } else { $_.Provider })
                'Data wersji' = (Format-Dt $_.Date -DateOnly); Rozmiar = (Format-Size $_.SizeBytes 1)
                Uwagi = (Join-NonEmpty @($(if ([int]$_.DeviceProblem -ne 0) { 'urządzenie z błędem (kod ' + $_.DeviceProblem + ')' }), $(if ($_.Optional) { 'opcjonalny' })) '; ')
            }
        })
}

function Get-SdWuResultText {
    # OperationResultCode z Windows Update -> opis.
    param([int]$Code)
    switch ($Code) { 2 { return 'zainstalowano' } 3 { return 'zainstalowano z błędami' } 4 { return 'niepowodzenie' } 5 { return 'przerwano' } default { return 'nie rozpoczęto' } }
}

# ---------------------------------------------------------------- brakujące sterowniki: Katalog Microsoft Update

function Get-SdCatalogQuery {
    # Identyfikator sprzętu skrócony do producenta i modelu układu - Katalog Microsoft Update źle znajduje pełne ID z SUBSYS/REV.
    # PCI\VEN_8086&DEV_A0F0&SUBSYS_...&REV_20 -> PCI\VEN_8086&DEV_A0F0; USB\VID_0BDA&PID_8153&REV_3000 -> USB\VID_0BDA&PID_8153.
    param([string]$HardwareId)
    $h = ([string]$HardwareId).Trim()
    if (-not $h) { return '' }
    $parts = $h -split '&'
    if ($parts.Count -ge 2 -and $parts[1] -match '^(DEV|PID)_') { return ($parts[0] + '&' + $parts[1]) }
    return $parts[0]
}

function Get-SdCatalogUrl {
    param([string]$HardwareId)
    $q = Get-SdCatalogQuery $HardwareId
    if (-not $q) { return '' }
    return ('https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($q))
}

# ---------------------------------------------------------------- strona ze sterownikami producenta komputera

# Producenci nie publikują stałych adresów "po numerze seryjnym", więc otwieramy oficjalną stronę wyszukiwania
# sterowników, a do schowka trafia to, co trzeba w niej wpisać (numer seryjny albo model).
$global:SdVendorSupport = @(
    @{ Match = '^LENOVO'; Name = 'Lenovo'; Url = 'https://pcsupport.lenovo.com/'; Copy = 'Serial' }
    @{ Match = '^Dell'; Name = 'Dell'; Url = 'https://www.dell.com/support/home/'; Copy = 'Serial' }
    @{ Match = '^(HP|Hewlett)'; Name = 'HP'; Url = 'https://support.hp.com/drivers'; Copy = 'Serial' }
    @{ Match = '^ASUS'; Name = 'ASUS'; Url = 'https://www.asus.com/support/'; Copy = 'Model' }
    @{ Match = '^Acer'; Name = 'Acer'; Url = 'https://www.acer.com/us-en/support/drivers-and-manuals'; Copy = 'Serial' }
    @{ Match = '^(Micro-Star|MSI)'; Name = 'MSI'; Url = 'https://www.msi.com/support'; Copy = 'Model' }
    @{ Match = '^(Gigabyte|GIGA-BYTE)'; Name = 'Gigabyte'; Url = 'https://www.gigabyte.com/Support'; Copy = 'Model' }
    @{ Match = '^ASRock'; Name = 'ASRock'; Url = 'https://www.asrock.com/support/index.asp'; Copy = 'Model' }
    @{ Match = '^(TOSHIBA|Dynabook)'; Name = 'Dynabook (Toshiba)'; Url = 'https://support.dynabook.com/'; Copy = 'Model' }
    @{ Match = '^SAMSUNG'; Name = 'Samsung'; Url = 'https://www.samsung.com/support/'; Copy = 'Model' }
    @{ Match = '^FUJITSU'; Name = 'Fujitsu'; Url = 'https://support.ts.fujitsu.com/'; Copy = 'Serial' }
    @{ Match = '^Microsoft'; Name = 'Microsoft Surface'; Url = 'https://support.microsoft.com/surface'; Copy = 'Model' }
)

function Get-SdVendorSupportInfo {
    # Strona ze sterownikami dla tego komputera (funkcja czysta). Komputer składany (producent "System manufacturer" itp.)
    # -> strona producenta płyty głównej. Nieznany producent -> wyszukiwarka.
    param([string]$Manufacturer, [string]$Model, [string]$Serial, [string]$BoardManufacturer = '', [string]$BoardProduct = '')
    $find = { param($m) foreach ($v in $global:SdVendorSupport) { if ($m -and $m -match $v.Match) { return $v } }; return $null }
    $mfr = Get-SdCleanString $Manufacturer ''
    $mdl = Get-SdCleanString $Model ''
    $sn = Get-SdCleanString $Serial ''
    $board = $false
    $v = & $find $mfr
    if (-not $v -or -not $mdl) {
        $bm = Get-SdCleanString $BoardManufacturer ''
        $bv = & $find $bm
        if ($bv -and $bv.Name -ne 'Microsoft Surface') { $v = $bv; $mfr = $bm; $mdl = Get-SdCleanString $BoardProduct ''; $sn = ''; $board = $true }
    }
    if ($v) {
        $useSerial = ($v.Copy -eq 'Serial' -and $sn)
        return [pscustomobject]@{
            Vendor = $v.Name; Url = $v.Url; IsSearch = $false; Board = $board
            CopyText = $(if ($useSerial) { $sn } else { $mdl }); CopyLabel = $(if ($useSerial) { 'numer seryjny' } elseif ($board) { 'model płyty głównej' } else { 'model' })
        }
    }
    $q = Join-NonEmpty @($mfr, $mdl, 'sterowniki') ' '
    return [pscustomobject]@{
        Vendor = $(if ($mfr) { $mfr } else { 'nieznany producent' }); Url = ('https://www.bing.com/search?q=' + [uri]::EscapeDataString($q)); IsSearch = $true; Board = $board
        CopyText = $mdl; CopyLabel = 'model'
    }
}

function Get-SdComputerSupportInfo {
    # Dane z WMI do Get-SdVendorSupportInfo. Lenovo podaje w Win32_ComputerSystem.Model numer typu (np. 83GS),
    # a nazwę handlową (np. LOQ 15IAX9) w Win32_ComputerSystemProduct.Version.
    $cs = Get-SdCs
    $csp = Get-Cim Win32_ComputerSystemProduct | Select-Object -First 1
    $bios = Get-Cim Win32_BIOS | Select-Object -First 1
    $bb = Get-Cim Win32_BaseBoard | Select-Object -First 1
    $mfr = ''; $model = ''
    if ($cs) { $mfr = [string]$cs.Manufacturer; $model = [string]$cs.Model }
    if ($mfr -match '^LENOVO' -and $csp -and (Get-SdCleanString ([string]$csp.Version) '')) { $model = [string]$csp.Version }
    $serial = ''
    if ($bios) { $serial = Get-SdCleanString ([string]$bios.SerialNumber) '' }
    if (-not $serial -and $csp) { $serial = Get-SdCleanString ([string]$csp.IdentifyingNumber) '' }
    $bm = ''; $bp = ''
    if ($bb) { $bm = [string]$bb.Manufacturer; $bp = [string]$bb.Product }
    return (Get-SdVendorSupportInfo -Manufacturer $mfr -Model $model -Serial $serial -BoardManufacturer $bm -BoardProduct $bp)
}
