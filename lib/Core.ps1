# SerwisDiag - rdzeń silnika diagnostycznego
# Zgodność: Windows PowerShell 3.0+ (Windows 8 i nowsze).
# Zasady: bez składni PS 5+ (class, ::new, .Where(), Import-PowerShellDataFile), bez parsowania zlokalizowanych komunikatów.

$global:SdVersion   = '1.4.0'
$global:SdAuthor    = 'Kacper Suliński - INDUSIP.PL'
$global:SdLicense   = 'MIT'
# Strona projektu na GitHubie - link w oknie „O programie” i źródło aktualizacji (wydania z instalatorem).
# Pusta: program nie sprawdza nowej wersji i nie łączy się w tej sprawie z internetem.
$global:SdProjectUrl = 'https://github.com/WoofDeveloper/SerwisDiag'
$global:SdChecks    = New-Object System.Collections.ArrayList
$global:SdCulturePl = [System.Globalization.CultureInfo]::GetCultureInfo('pl-PL')
$global:SdDataCache = @{}

$global:SdCategories = @(
    [pscustomobject]@{ Key = 'system';   Label = 'System' }
    [pscustomobject]@{ Key = 'hardware'; Label = 'Sprzęt' }
    [pscustomobject]@{ Key = 'storage';  Label = 'Dyski' }
    [pscustomobject]@{ Key = 'power';    Label = 'Zasilanie i bateria' }
    [pscustomobject]@{ Key = 'perf';     Label = 'Wydajność' }
    [pscustomobject]@{ Key = 'events';   Label = 'Awarie i zdarzenia' }
    [pscustomobject]@{ Key = 'drivers';  Label = 'Sterowniki i urządzenia' }
    [pscustomobject]@{ Key = 'security'; Label = 'Bezpieczeństwo' }
    [pscustomobject]@{ Key = 'updates';  Label = 'Aktualizacje i licencja' }
    [pscustomobject]@{ Key = 'network';  Label = 'Sieć' }
    [pscustomobject]@{ Key = 'software'; Label = 'Oprogramowanie i autostart' }
    [pscustomobject]@{ Key = 'tests';    Label = 'Testy obciążeniowe' }
)

# Ranga służy do sortowania i wyznaczania werdyktu (im wyżej, tym poważniej).
$global:SdStatusInfo = @{
    crit  = [pscustomobject]@{ Label = 'KRYTYCZNE'; Rank = 5 }
    warn  = [pscustomobject]@{ Label = 'UWAGA';     Rank = 4 }
    error = [pscustomobject]@{ Label = 'BŁĄD TESTU'; Rank = 3 }
    info  = [pscustomobject]@{ Label = 'INFO';      Rank = 2 }
    ok    = [pscustomobject]@{ Label = 'OK';        Rank = 1 }
    skip  = [pscustomobject]@{ Label = 'POMINIĘTO'; Rank = 0 }
}

function Get-SdCategoryLabel {
    param([string]$Key)
    foreach ($c in $global:SdCategories) { if ($c.Key -eq $Key) { return $c.Label } }
    return $Key
}

# ---------------------------------------------------------------- logowanie / uprawnienia

function Write-SdLog {
    param([string]$Message, [string]$Level = 'INFO')
    # Uwaga: pusta kolekcja jest w PowerShell "fałszywa", dlatego porównanie z $null.
    if ($null -ne $global:SD -and $null -ne $global:SD.Log) {
        [void]$global:SD.Log.Add(('{0} [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message))
    }
}

function Test-SdAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# ---------------------------------------------------------------- kontekst skanowania

function New-SdContext {
    param(
        [string]$Root,
        [string]$Level = 'Quick',
        [string[]]$Tests = @(),
        [switch]$Offline,
        [switch]$Synchronized,
        [string[]]$Only = @()          # tylko wskazane testy (monitorowanie w tle); puste = wszystkie z poziomu
    )
    $ctx = @{
        Root     = $Root
        Level    = $Level
        Tests    = @($Tests)
        Only     = @($Only)
        Offline  = [bool]$Offline     # tryb bez internetu: testy wymagające internetu są pomijane
        IsAdmin  = (Test-SdAdmin)
        Meta     = @{}
        Settings = @{}
        Findings = New-Object System.Collections.ArrayList
        Tables   = New-Object System.Collections.ArrayList
        Log      = New-Object System.Collections.ArrayList
        Timings  = New-Object System.Collections.ArrayList
        Progress = @{ Index = 0; Total = 0; Title = ''; Category = ''; Id = '' }
        Cur      = @{ Category = ''; Id = ''; Title = '' }
        Cache    = @{}
        Cancel   = $false
        Done     = $false
        Started  = $null
        Finished = $null
    }
    if ($Synchronized) {
        $ctx.Meta     = [hashtable]::Synchronized($ctx.Meta)
        $ctx.Findings = [System.Collections.ArrayList]::Synchronized($ctx.Findings)
        $ctx.Tables   = [System.Collections.ArrayList]::Synchronized($ctx.Tables)
        $ctx.Log      = [System.Collections.ArrayList]::Synchronized($ctx.Log)
        $ctx.Timings  = [System.Collections.ArrayList]::Synchronized($ctx.Timings)
        $ctx.Progress = [hashtable]::Synchronized($ctx.Progress)
        $ctx.Cur      = [hashtable]::Synchronized($ctx.Cur)
        $ctx          = [hashtable]::Synchronized($ctx)
    }
    return $ctx
}

function Set-SdMeta {
    param([string]$Key, $Value)
    $global:SD.Meta[$Key] = $Value
}

function Test-SdOffline {
    # Technik zaznaczył, że komputer celowo nie ma internetu (np. stanowisko serwisowe) - brak łączności to wtedy nie usterka.
    return [bool]($null -ne $global:SD -and $global:SD['Offline'])
}

$global:SdOfflineSkipText = 'Pominięto - diagnostyka w trybie bez internetu.'

# ---------------------------------------------------------------- wyniki

function Add-Finding {
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Title,
        [ValidateSet('ok', 'info', 'warn', 'crit', 'skip', 'error')][string]$Status = 'info',
        [string]$Value = '',
        [string]$Details = '',
        [string]$Advice = '',
        [string]$Category = '',
        [string]$Id = '',
        [switch]$Private,
        # Osobna, neutralna wersja wyniku dla raportu klienta (np. podejrzenie nielegalnej licencji technik omawia osobiście).
        # Raport techniczny pokazuje wynik pełny; raport klienta - te wartości i bez szczegółów technicznych.
        [string]$CustomerTitle = '',
        [string]$CustomerStatus = '',
        [string]$CustomerValue = '',
        [string]$CustomerAdvice = '',
        # Wynik z historii zdarzeń (np. restarty z 90 dni): czas ostatniego zdarzenia. Trafia do wartości („ostatnio …”),
        # a porównanie przed/po rozpoznaje po nim, że od poprzedniej diagnostyki nic się nie powtórzyło.
        $LastEvent = $null
    )
    $cat = if ($Category) { $Category } else { $global:SD.Cur.Category }
    $chk = if ($Id) { $Id } else { $global:SD.Cur.Id }
    $last = $null
    if ($null -ne $LastEvent) { try { $last = [datetime]$LastEvent } catch { } }
    if ($last) {
        $Value = Join-NonEmpty @($Value, ('ostatnio ' + (Format-Dt $last))) '; '
        if ($CustomerValue) { $CustomerValue = Join-NonEmpty @($CustomerValue, ('ostatnio ' + (Format-Dt $last))) '; ' }
    }
    $cust = $null
    if ($CustomerTitle -or $CustomerStatus -or $CustomerValue) {
        if ($CustomerStatus -and -not $global:SdStatusInfo.ContainsKey($CustomerStatus)) { $CustomerStatus = '' }
        $cust = [pscustomobject]@{ Title = $CustomerTitle; Status = $CustomerStatus; Value = $CustomerValue; Advice = $CustomerAdvice }
    }
    $obj = [pscustomobject]@{
        CheckId  = $chk
        Category = $cat
        Title    = $Title
        Status   = $Status
        Value    = $Value
        Details  = $Details
        Advice   = $Advice
        Private  = [bool]$Private
        Customer = $cust
        Time     = (Get-Date).ToString('HH:mm:ss')
        LastEvent = $last
    }
    [void]$global:SD.Findings.Add($obj)
}

function Add-Table {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [object[]]$Rows,
        [string]$Category = '',
        [string]$Note = '',
        [switch]$Private
    )
    $rows = @($Rows | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) { return }
    $cols = New-Object System.Collections.ArrayList
    foreach ($r in $rows) {
        foreach ($p in $r.PSObject.Properties) { if ($cols -notcontains $p.Name) { [void]$cols.Add($p.Name) } }
    }
    $cat = if ($Category) { $Category } else { $global:SD.Cur.Category }
    $t = [pscustomobject]@{
        Category = $cat
        Name     = $Name
        Columns  = @($cols)
        Rows     = $rows
        Note     = $Note
        Private  = [bool]$Private
    }
    [void]$global:SD.Tables.Add($t)
}

# ---------------------------------------------------------------- rejestr testów

function Register-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][scriptblock]$Script,
        [ValidateSet('Quick', 'Full', 'Test')][string]$Level = 'Quick',
        [switch]$NeedsAdmin,
        [switch]$NeedsInternet,
        [int]$MinBuild = 0
    )
    [void]$global:SdChecks.Add([pscustomobject]@{
            Id = $Id; Category = $Category; Title = $Title; Script = $Script
            Level = $Level; NeedsAdmin = [bool]$NeedsAdmin; NeedsInternet = [bool]$NeedsInternet; MinBuild = $MinBuild
        })
}

function Get-SdSelectedChecks {
    param([string]$Level, [string[]]$Tests, [string[]]$Only = @())
    $sel = New-Object System.Collections.ArrayList
    $only = @($Only | Where-Object { $_ })
    foreach ($c in $global:SdChecks) {
        $run = $false
        switch ($c.Level) {
            'Quick' { $run = ($Level -eq 'Quick' -or $Level -eq 'Full') }
            'Full'  { $run = ($Level -eq 'Full') }
            'Test'  { $run = (@($Tests) -contains $c.Id) }
        }
        if ($run -and $only.Count -gt 0 -and $only -notcontains $c.Id) { $run = $false }
        if ($run) { [void]$sel.Add($c) }
    }
    return , $sel
}

function Invoke-SdScan {
    $sd = $global:SD
    $sd.Started = Get-Date
    $ErrorActionPreference = 'SilentlyContinue'
    $sd.Meta['ComputerName'] = $env:COMPUTERNAME
    $sd.Meta['UserName'] = $env:USERNAME
    $sd.Meta['IsAdmin'] = $sd.IsAdmin
    $sd.Meta['ToolVersion'] = $global:SdVersion
    $sd.Meta['PSVersion'] = $PSVersionTable.PSVersion.ToString()
    $sd.Meta['Offline'] = [bool]$sd['Offline']

    $build = 0
    try { $build = [int](Get-SdOs).BuildNumber } catch { }

    $sel = Get-SdSelectedChecks -Level $sd.Level -Tests $sd.Tests -Only @($sd['Only'])
    $sd.Progress.Total = $sel.Count
    $i = 0
    foreach ($c in $sel) {
        if ($sd.Cancel) { Write-SdLog 'Przerwano na żądanie użytkownika' 'WARN'; break }
        $i++
        $sd.Progress.Index = $i
        $sd.Progress.Title = $c.Title
        $sd.Progress.Category = $c.Category
        $sd.Progress.Id = $c.Id
        $sd.Cur.Category = $c.Category
        $sd.Cur.Id = $c.Id
        $sd.Cur.Title = $c.Title
        if ($sd.ContainsKey('OnProgress') -and $sd['OnProgress']) { try { & $sd['OnProgress'] $i $sel.Count $c } catch { } }

        if ($c.NeedsAdmin -and -not $sd.IsAdmin) {
            Add-Finding -Title $c.Title -Status skip -Value 'Wymaga uprawnień administratora (uruchom program jako administrator).'
            continue
        }
        if ($c.NeedsInternet -and $sd['Offline']) {
            Add-Finding -Title $c.Title -Status skip -Value $global:SdOfflineSkipText
            continue
        }
        if ($c.MinBuild -gt 0 -and $build -gt 0 -and $build -lt $c.MinBuild) {
            Add-Finding -Title $c.Title -Status skip -Value 'Niedostępne w tej wersji systemu.'
            continue
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            & $c.Script
        } catch {
            $msg = $_.Exception.Message
            Add-Finding -Title $c.Title -Status error -Value 'Test zakończył się błędem.' -Details ($msg + "`n" + $_.ScriptStackTrace)
            Write-SdLog ('{0}: {1}' -f $c.Id, $msg) 'ERROR'
        }
        $sw.Stop()
        [void]$sd.Timings.Add([pscustomobject]@{ Id = $c.Id; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) })
    }
    # aktualność bazy wiedzy programu (daty wsparcia Windows i ESU) - informacja tylko dla technika
    $kb = $null
    try { $kb = Get-SdKnowledgeInfo } catch { }
    if ($kb) {
        $sd.Meta['Knowledge'] = $kb.Text
        if ($kb.Stale) {
            Add-Finding -Title 'Baza wiedzy programu' -Category 'system' -Id 'sys.knowledge' -Status info -Private -Value $kb.Text `
                -Details 'Okresy wsparcia Windows i terminy ESU pochodzą z pliku data\lifecycle.psd1 dołączonego do tej wersji programu.' `
                -Advice 'Pobierz nową wersję programu - daty wsparcia i zalecenia w raporcie mogą być nieaktualne.'
        }
    }
    if ($sd.Cache['WmiSlow']) {
        $broken = [bool]$sd.Cache['WmiBroken']
        $det = 'Zapytania WMI przekraczające limit czasu lub trwające ponad {0} s: {1}' -f $global:SdWmiSlowSec, $sd.Cache['WmiSlow']
        if ($broken) { $det += "`n" + ('Pominięte zapytania (bezpiecznik): {0} - wyniki części testów są niepełne.' -f [int]$sd.Cache['WmiSkipped']) }
        Add-Finding -Title 'Usługa WMI (Instrumentacja zarządzania Windows)' -Category 'system' -Id 'sys.wmi' -Status $(if ($broken) { 'crit' } else { 'warn' }) `
            -Value $(if ($broken) { 'WMI nie odpowiada - część testów pominięto, ich wyniki mogą być niepełne' } else { 'WMI odpowiada bardzo wolno' }) -Details $det `
            -Advice 'Uszkodzone lub przeciążone repozytorium WMI spowalnia system i programy. Jako administrator: winmgmt /verifyrepository, a przy błędach winmgmt /salvagerepository; uruchom ponownie usługę Winmgmt lub komputer i powtórz diagnostykę.'
    } elseif ($sd.Cache['WmiCalls'] -and -not $sd.Cancel) {
        Add-Finding -Title 'Usługa WMI (Instrumentacja zarządzania Windows)' -Category 'system' -Id 'sys.wmi' -Status ok -Value ('Odpowiada poprawnie (zapytań: {0})' -f $sd.Cache['WmiCalls'])
    }
    $sd.Finished = Get-Date
    $sd.Done = $true
}

# ---------------------------------------------------------------- dane (baza wiedzy)

function Get-SdData {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($global:SdDataCache.ContainsKey($Name)) { return $global:SdDataCache[$Name] }
    $data = $null
    try {
        $path = [System.IO.Path]::Combine($global:SD.Root, 'data', ($Name + '.psd1'))
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $data = & ([scriptblock]::Create($text))
    } catch {
        Write-SdLog ('Dane {0}: {1}' -f $Name, $_.Exception.Message) 'WARN'
    }
    $global:SdDataCache[$Name] = $data
    return $data
}

# ---------------------------------------------------------------- CIM / rejestr / procesy

$global:SdWmiSlowSec = 20      # zapytanie WMI dłuższe niż tyle sekund uznajemy za objaw problemu
$global:SdWmiBreakAfter = 3    # po tylu takich zapytaniach kolejne są pomijane

function Register-SdWmiSlow {
    # Bezpiecznik WMI: uszkodzone repozytorium potrafi wstrzymać każde zapytanie do limitu czasu, a skanowanie
    # (ok. 150 zapytań) trwałoby wtedy godzinami. Po kilku takich zapytaniach pozostałe są pomijane.
    param([string]$What, [double]$Seconds)
    $sd = $global:SD
    if ($null -eq $sd -or $null -eq $sd.Cache) { return }
    $n = 1 + [int]$sd.Cache['WmiSlow']
    $sd.Cache['WmiSlow'] = $n
    Write-SdLog ('WMI odpowiada bardzo wolno: {0} ({1:N0} s)' -f $What, $Seconds) 'WARN'
    if ($n -ge $global:SdWmiBreakAfter -and -not $sd.Cache['WmiBroken']) {
        $sd.Cache['WmiBroken'] = $true
        Write-SdLog ('WMI: {0} zapytania przekroczyły limit czasu - kolejne zapytania WMI są pomijane.' -f $n) 'ERROR'
    }
}

function Get-Cim {
    param(
        [Parameter(Mandatory = $true)][string]$Class,
        [string]$Namespace = 'root\cimv2',
        [string]$Filter = '',
        [int]$Timeout = 40
    )
    $sd = $global:SD
    $hasCache = ($null -ne $sd -and $null -ne $sd.Cache)
    if ($hasCache) {
        $sd.Cache['WmiCalls'] = 1 + [int]$sd.Cache['WmiCalls']
        if ($sd.Cache['WmiBroken']) { $sd.Cache['WmiSkipped'] = 1 + [int]$sd.Cache['WmiSkipped']; return @() }
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $what = '{0}\{1}' -f $Namespace, $Class
    try {
        $p = @{ ClassName = $Class; Namespace = $Namespace; OperationTimeoutSec = $Timeout; ErrorAction = 'Stop' }
        if ($Filter) { $p['Filter'] = $Filter }
        $r = @(Get-CimInstance @p)
        if ($sw.Elapsed.TotalSeconds -ge [math]::Min($global:SdWmiSlowSec, $Timeout - 1)) { Register-SdWmiSlow $what $sw.Elapsed.TotalSeconds }
        return $r
    } catch {
        if ($sw.Elapsed.TotalSeconds -ge ($Timeout - 2)) { Register-SdWmiSlow $what $sw.Elapsed.TotalSeconds }
        Write-SdLog ('CIM {0}: {1}' -f $what, $_.Exception.Message) 'WARN'
        return @()
    }
}

function Format-SdCmdArg {
    # Cytuje argument wiersza poleceń według reguł Windows (CommandLineToArgvW): spacje i cudzysłowy w środku,
    # ukośniki przed cudzysłowem i na końcu. Potrzebne przy ponownym uruchamianiu programu z uprawnieniami administratora.
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    if ($Value -ne '' -and $Value -notmatch '[\s"]') { return $Value }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq [char]92) { $bs++; continue }
        if ($ch -eq [char]34) { [void]$sb.Append([char]92, 2 * $bs + 1); [void]$sb.Append([char]34); $bs = 0; continue }
        if ($bs -gt 0) { [void]$sb.Append([char]92, $bs); $bs = 0 }
        [void]$sb.Append($ch)
    }
    if ($bs -gt 0) { [void]$sb.Append([char]92, 2 * $bs) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Get-RegValue {
    param([string]$Path, [string]$Name, $Default = $null)
    try {
        $k = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
        $prop = $k.PSObject.Properties[$Name]
        if ($prop) { return $prop.Value }
    } catch { }
    return $Default
}

function Invoke-Native {
    # Uruchamia program i zwraca @{ ExitCode; StdOut; StdErr; TimedOut }. Wyjście dekodowane jako OEM (jak konsola),
    # chyba że podano -Encoding (np. sfc.exe zapisuje przekierowane wyjście w UTF-16).
    param([string]$File, [string]$Arguments = '', [int]$TimeoutSec = 60, [System.Text.Encoding]$Encoding = $null)
    $res = [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = ''; TimedOut = $false }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $File
        $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        try {
            $enc = $Encoding
            if (-not $enc) { $enc = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }
            $psi.StandardOutputEncoding = $enc
            $psi.StandardErrorEncoding = $enc
        } catch { }
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        $so = $p.StandardOutput.ReadToEndAsync()
        $se = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            $res.TimedOut = $true
            try { $p.Kill() } catch { }
        }
        [void]$so.Wait(3000)
        [void]$se.Wait(3000)
        if ($so.IsCompleted) { $res.StdOut = $so.Result }
        if ($se.IsCompleted) { $res.StdErr = $se.Result }
        if ($p.HasExited) { $res.ExitCode = $p.ExitCode }
    } catch {
        $res.StdErr = $_.Exception.Message
    }
    return $res
}

function Get-SdEvents {
    # Bezpieczny wrapper na Get-WinEvent. Przyjmuje te same klucze co -FilterHashtable
    # (LogName, ProviderName, Id, Level, StartTime), ale buduje filtr XPath. Dzięki temu nieistniejący dostawca
    # zdarzeń (np. brak sterownika) nie unieważnia całego zapytania - FilterHashtable zgłasza wtedy błąd
    # i zwraca zero wyników, co dawałoby fałszywe "brak awarii".
    param([hashtable]$Filter, [int]$Max = 1000)
    $conds = New-Object System.Collections.ArrayList
    if ($Filter.ContainsKey('ProviderName')) {
        [void]$conds.Add('(' + ((@($Filter.ProviderName) | ForEach-Object { "Provider[@Name='$_']" }) -join ' or ') + ')')
    }
    if ($Filter.ContainsKey('Id')) {
        [void]$conds.Add('(' + ((@($Filter.Id) | ForEach-Object { "EventID=$_" }) -join ' or ') + ')')
    }
    if ($Filter.ContainsKey('Level')) {
        [void]$conds.Add('(' + ((@($Filter.Level) | ForEach-Object { "Level=$_" }) -join ' or ') + ')')
    }
    if ($Filter.ContainsKey('StartTime')) {
        $t = ([datetime]$Filter.StartTime).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
        [void]$conds.Add("TimeCreated[@SystemTime>='$t']")
    }
    $xp = '*'
    if ($conds.Count -gt 0) { $xp = '*[System[' + ($conds -join ' and ') + ']]' }

    $all = New-Object System.Collections.ArrayList
    $logs = @($Filter.LogName)
    foreach ($log in $logs) {
        try {
            foreach ($e in @(Get-WinEvent -LogName $log -FilterXPath $xp -MaxEvents $Max -ErrorAction Stop)) { [void]$all.Add($e) }
        } catch {
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                Write-SdLog ('Dziennik {0}: {1}' -f $log, $_.Exception.Message) 'WARN'
            }
        }
    }
    if ($logs.Count -gt 1) { return @($all | Sort-Object TimeCreated -Descending | Select-Object -First $Max) }
    return @($all)
}

function Get-SdLatestTime {
    # Najpóźniejszy czas z listy: zdarzeń (TimeCreated) albo obiektów z innym polem czasu (np. Time). Pusta lista: $null.
    param($Items, [string]$Property = 'TimeCreated')
    $t = $null
    foreach ($i in @($Items)) {
        if ($null -eq $i) { continue }
        $v = $i.$Property
        if ($v -and (-not $t -or $v -gt $t)) { $t = $v }
    }
    return $t
}

# Polskie formy liczby mnogiej: 1 zdarzenie, 2 zdarzenia, 5 zdarzeń, 22 zdarzenia, 12 zdarzeń.
function Get-SdPlural {
    param([int64]$N, [string]$One, [string]$Few, [string]$Many)
    $n = [math]::Abs($N)
    if ($n -eq 1) { return $One }
    $m10 = $n % 10
    $m100 = $n % 100
    if ($m10 -ge 2 -and $m10 -le 4 -and -not ($m100 -ge 12 -and $m100 -le 14)) { return $Few }
    return $Many
}

function Format-Count {
    param([int64]$N, [string]$One, [string]$Few, [string]$Many)
    return ('{0} {1}' -f $N, (Get-SdPlural $N $One $Few $Many))
}

# ---------------------------------------------------------------- formatowanie (zawsze po polsku, niezależnie od ustawień systemu)

function Test-SdEmpty {
    # Uwaga: w PowerShell "0 -eq ''" daje True, dlatego puste wartości rozpoznajemy po typie.
    param($Value)
    return ($null -eq $Value -or ($Value -is [string] -and $Value.Trim() -eq ''))
}

function Format-Num {
    param($Value, [int]$Digits = 0)
    if (Test-SdEmpty $Value) { return '-' }
    try { return ([double]$Value).ToString("N$Digits", $global:SdCulturePl) } catch { return [string]$Value }
}

function Format-Size {
    param($Bytes, [int]$Digits = 1)
    if (Test-SdEmpty $Bytes) { return '-' }
    $b = [double]$Bytes
    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $i = 0
    while ([math]::Abs($b) -ge 1024 -and $i -lt ($units.Count - 1)) { $b = $b / 1024; $i++ }
    if ($i -eq 0) { return ($b.ToString('N0', $global:SdCulturePl) + ' B') }
    return ($b.ToString("N$Digits", $global:SdCulturePl) + ' ' + $units[$i])
}

function Format-Dt {
    param($Date, [switch]$DateOnly)
    if ($null -eq $Date) { return '-' }
    try {
        $d = [datetime]$Date
        if ($d.Year -le 1601) { return '-' }
        if ($DateOnly) { return $d.ToString('yyyy-MM-dd') }
        return $d.ToString('yyyy-MM-dd HH:mm')
    } catch { return [string]$Date }
}

function Format-Span {
    param([timespan]$Span)
    if ($Span.TotalDays -ge 1) { return ('{0} d {1} h' -f [int][math]::Floor($Span.TotalDays), $Span.Hours) }
    if ($Span.TotalHours -ge 1) { return ('{0} h {1} min' -f [int][math]::Floor($Span.TotalHours), $Span.Minutes) }
    if ($Span.TotalMinutes -lt 1) { return ('{0} s' -f [int][math]::Round($Span.TotalSeconds)) }
    return ('{0} min {1} s' -f [int][math]::Floor($Span.TotalMinutes), $Span.Seconds)
}

function Join-NonEmpty {
    param([object[]]$Items, [string]$Separator = ', ')
    return (@($Items | Where-Object { $null -ne $_ -and ([string]$_).Trim() -ne '' } | ForEach-Object { ([string]$_).Trim() }) -join $Separator)
}

function Limit-Text {
    param([string]$Text, [int]$Max = 200)
    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $Max) { return $Text }
    return ($Text.Substring(0, $Max - 1) + '…')
}

# Wartości-śmieci wpisywane przez producentów płyt / BIOS-ów.
function Test-SdJunkString {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }
    return ($Text -match '^(to be filled by o\.?e\.?m\.?|default string|system serial number|system product name|system manufacturer|system version|not specified|not applicable|none|n/a|0+|o\.e\.m\.?|123456789|unknown|ffffffff.*)$')
}

function Get-SdCleanString {
    param([string]$Text, [string]$Fallback = '-')
    if (Test-SdJunkString $Text) { return $Fallback }
    return $Text.Trim()
}
