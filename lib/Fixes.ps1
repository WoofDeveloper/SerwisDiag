# SerwisDiag - naprawy po diagnostyce: problemy, które program może usunąć sam, z wyborem technika.
# Zasady: nic nie dzieje się bez zaznaczenia i potwierdzenia; przed zmianami punkt przywracania; każda zmiana trafia
# do dziennika napraw z poprzednią wartością, a zmiany ustawień (rejestr, usługi, zapora) także do dziennika JSON,
# z którego program potrafi je cofnąć; usterek sprzętowych program nie "naprawia".
#  Detect: param($Ctx) - $Ctx = @{ Result (wynik diagnostyki); IsAdmin; Offline }. Tylko czyta stan systemu i zwraca
#          obiekty { Key; Title; Problem; Data; Default; CustomerTitle } (każdy = jedna pozycja na liście) albo nic.
#  Apply:  param($Data, $Log) - wykonuje naprawę; zwraca napis z wynikiem albo { Result = ok|warn; Message; Reboot };
#          wyjątek = niepowodzenie. Do $Log dopisuje każdą zmianę (poprzednia -> nowa wartość).

$global:SdFixes = New-Object System.Collections.ArrayList

function Register-Fix {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Group,
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Description = '',
        [Parameter(Mandatory = $true)][scriptblock]$Detect,
        [Parameter(Mandatory = $true)][scriptblock]$Apply,
        [int]$Order = 50,
        [ValidateSet('low', 'medium', 'high')][string]$Risk = 'low',
        [string[]]$Covers = @(),
        [switch]$NeedsAdmin, [switch]$NeedsInternet, [switch]$Reboot, [switch]$Long, [switch]$Interactive, [switch]$DefaultOff
    )
    [void]$global:SdFixes.Add([pscustomobject]@{
            Id = $Id; Group = $Group; Title = $Title; Description = $Description; Detect = $Detect; Apply = $Apply; Order = $Order
            Risk = $Risk; Covers = @($Covers); NeedsAdmin = [bool]$NeedsAdmin; NeedsInternet = [bool]$NeedsInternet; Reboot = [bool]$Reboot
            Long = [bool]$Long; Interactive = [bool]$Interactive; DefaultOff = [bool]$DefaultOff
        })
}

# ---------------------------------------------------------------- pomocnicze

function Get-SdCtxFindings {
    # Wyniki diagnostyki danego testu (opcjonalnie o tytule pasującym do wyrażenia).
    param($Ctx, [string]$CheckId, [string]$TitleRx = '')
    $all = @()
    if ($Ctx -and $Ctx.Result) { $all = @($Ctx.Result.Findings) }
    return @($all | Where-Object { $null -ne $_ -and [string]$_.CheckId -eq $CheckId -and (-not $TitleRx -or [string]$_.Title -match $TitleRx) })
}

function Test-SdCtxProblem {
    param($Ctx, [string]$CheckId, [string]$TitleRx = '')
    return (@(Get-SdCtxFindings $Ctx $CheckId $TitleRx | Where-Object { $_.Status -eq 'warn' -or $_.Status -eq 'crit' }).Count -gt 0)
}

function Format-SdLogValue {
    param($Value)
    if ($null -eq $Value) { return '(brak)' }
    if ($Value -is [byte[]]) { return ((@($Value) | ForEach-Object { $_.ToString('X2') }) -join ' ') }
    if ($Value -is [array]) { return ($Value -join '; ') }
    return [string]$Value
}

# Rekordy cofania: funkcje zmieniające system dopisują do $global:SdUndoSink (ustawia go Invoke-SdFixes na czas jednej
# naprawy) poprzedni stan. Kind = reg (wartość rejestru), svc (typ uruchamiania usługi), firewall (profile zapory).
$global:SdUndoSink = $null

function Add-SdUndoRecord {
    param([Parameter(Mandatory = $true)][hashtable]$Record)
    if ($null -ne $global:SdUndoSink) { [void]$global:SdUndoSink.Add([pscustomobject]$Record) }
}

function Get-SdRegRaw {
    # Wartość rejestru bez rozwijania zmiennych środowiskowych, z typem - do przywrócenia jej 1:1.
    param([string]$Path, [string]$Name)
    $r = [pscustomobject]@{ Exists = $false; Value = $null; Kind = '' }
    try {
        $k = Get-Item -LiteralPath $Path -ErrorAction Stop
        if (@($k.GetValueNames()) -contains $Name) {
            $r.Exists = $true
            $r.Value = $k.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $r.Kind = [string]$k.GetValueKind($Name)
        }
    } catch { }
    return $r
}

function Set-SdRegValueLogged {
    # Ustawia wartość w rejestrze i zapisuje w dzienniku poprzednią. Klucz tworzy tylko, gdy go brak
    # (New-Item -Force na istniejącym kluczu usunąłby jego zawartość).
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', $Log = $null)
    $old = Get-RegValue $Path $Name $null
    $raw = Get-SdRegRaw $Path $Name
    if (-not (Test-Path -LiteralPath $Path)) { [void](New-Item -Path $Path -Force -ErrorAction Stop) }
    [void](New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop)
    if ($null -ne $Log) { [void]$Log.Add(('{0} [{1}]: {2} -> {3}' -f $Path, $Name, (Format-SdLogValue $old), (Format-SdLogValue $Value))) }
    Add-SdUndoRecord @{ Kind = 'reg'; Path = $Path; Name = $Name; Existed = $raw.Exists; Old = $raw.Value; OldKind = $raw.Kind; New = $Value; NewKind = $Type; Deleted = $false }
}

function Remove-SdRegValueLogged {
    param([string]$Path, [string]$Name, $Log = $null)
    $old = Get-RegValue $Path $Name $null
    if ($null -eq $old) { return }
    $raw = Get-SdRegRaw $Path $Name
    Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop
    if ($null -ne $Log) { [void]$Log.Add(('{0} [{1}]: {2} -> (usunięto)' -f $Path, $Name, (Format-SdLogValue $old))) }
    if ($raw.Exists) { Add-SdUndoRecord @{ Kind = 'reg'; Path = $Path; Name = $Name; Existed = $true; Old = $raw.Value; OldKind = $raw.Kind; New = $null; NewKind = ''; Deleted = $true } }
}

function Get-SdRegSnapshot {
    # Stan kilku wartości jednego klucza - przed zmianą wykonywaną zewnętrznym poleceniem (fsutil, WMI, polecenia SMB).
    param([string]$Path, [string[]]$Names)
    $s = @{}
    foreach ($nm in $Names) { $s[$nm] = Get-SdRegRaw $Path $nm }
    return $s
}

function Add-SdRegSnapshotUndo {
    # Rekordy cofania dla wartości, które zewnętrzne polecenie zmieniło od chwili zrobienia migawki.
    param([string]$Path, [hashtable]$Before)
    foreach ($nm in @($Before.Keys)) {
        $a = $Before[$nm]
        $b = Get-SdRegRaw $Path $nm
        if ($a.Exists -eq $b.Exists -and (Format-SdLogValue $a.Value) -eq (Format-SdLogValue $b.Value)) { continue }
        Add-SdUndoRecord @{ Kind = 'reg'; Path = $Path; Name = $nm; Existed = $a.Exists; Old = $a.Value; OldKind = $a.Kind; New = $b.Value; NewKind = $b.Kind; Deleted = (-not $b.Exists) }
    }
}

function Get-SdLastLine {
    # Ostatni niepusty wiersz wyjścia programu (bez znaków NUL; postęp typu "45%" bywa nadpisywany samym znakiem CR).
    param([string]$Text)
    $lines = @(([string]$Text -replace "`0", '') -split "[`r`n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($lines.Count -eq 0) { return '' }
    return $lines[$lines.Count - 1]
}

function Set-SdServiceStartLogged {
    param([string]$Name, [string]$StartupType, $Log = $null)
    $svc = Get-Cim Win32_Service -Filter ("Name='{0}'" -f $Name) | Select-Object -First 1
    $old = $(if ($svc) { [string]$svc.StartMode } else { '?' })
    Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
    if ($null -ne $Log) { [void]$Log.Add(('Usługa {0}: {1} -> {2}' -f $Name, $old, $StartupType)) }
    Add-SdUndoRecord @{ Kind = 'svc'; Name = $Name; Old = $old; New = $StartupType }
}

function ConvertTo-SdUninstallCommand {
    # Polecenie deinstalacji z rejestru -> { File; Arguments }. MsiExec /I (zmiana/naprawa) zamieniamy na /X (usunięcie).
    param([string]$Command)
    $c = ([string]$Command).Trim()
    if (-not $c) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($c)
    if ($c -match '(?i)^"?(?:[^"]*\\)?msiexec(?:\.exe)?"?\s+(.*)$') {
        $rest = [regex]::Replace($Matches[1], '(?i)(^|\s)/I\s*(?=\{)', '$1/X ')
        return [pscustomobject]@{ File = 'msiexec.exe'; Arguments = $rest.Trim() }
    }
    if ($c.StartsWith('"')) {
        $e = $c.IndexOf('"', 1)
        if ($e -gt 1) { return [pscustomobject]@{ File = $c.Substring(1, $e - 1); Arguments = $c.Substring($e + 1).Trim() } }
    }
    $exe = Resolve-SdCommandPath $c
    if ($exe -and $c.StartsWith($exe, [System.StringComparison]::OrdinalIgnoreCase)) { return [pscustomobject]@{ File = $exe; Arguments = $c.Substring($exe.Length).Trim() } }
    $parts = $c -split '\s+', 2
    return [pscustomobject]@{ File = $parts[0]; Arguments = $(if ($parts.Count -gt 1) { $parts[1] } else { '' }) }
}

function Get-SdUninstallEntries {
    # Programy z poleceniem deinstalacji (komputer, 32-bit, załadowane profile użytkowników).
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($h in (Get-SdUserHives)) { $roots += ($h.Path + '\Software\Microsoft\Windows\CurrentVersion\Uninstall') }
    $out = @()
    foreach ($root in $roots) {
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p -or -not $p.PSObject.Properties['DisplayName'] -or -not $p.DisplayName) { continue }
            if ($p.PSObject.Properties['SystemComponent'] -and $p.SystemComponent -eq 1) { continue }
            $us = ''; $qs = ''
            if ($p.PSObject.Properties['UninstallString']) { $us = [string]$p.UninstallString }
            if ($p.PSObject.Properties['QuietUninstallString']) { $qs = [string]$p.QuietUninstallString }
            $out += [pscustomobject]@{ Name = [string]$p.DisplayName; UninstallString = $us; QuietUninstallString = $qs; KeyPath = [string]$k.PSPath }
        }
    }
    return $out
}

# ---------------------------------------------------------------- katalog napraw: system

Register-Fix -Id 'fx.restoreon' -Group 'System' -Order 5 -NeedsAdmin -Covers @('sys.restore') `
    -Title 'Włącz ochronę systemu (punkty przywracania)' `
    -Description 'Włącza tworzenie punktów przywracania na dysku systemowym - pozwala cofnąć zmiany sterowników i ustawień (także te napraw).' `
    -Detect {
    param($Ctx)
    if (@(Get-SdCtxFindings $Ctx 'sys.restore' | Where-Object { [string]$_.Value -match 'Brak punktów' }).Count -eq 0) { return }
    if ([int](Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' 'DisableSR' 0) -eq 1) { return }
    [pscustomobject]@{ Problem = 'Brak punktów przywracania - ochrona systemu jest prawdopodobnie wyłączona.' }
} -Apply {
    param($Data, $Log)
    Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop
    [void]$Log.Add('Ochrona systemu włączona dla ' + $env:SystemDrive)
    'Ochrona systemu włączona.'
}

Register-Fix -Id 'fx.wmi' -Group 'System' -Order 10 -NeedsAdmin -Risk medium -Covers @('sys.wmi') `
    -Title 'Napraw repozytorium WMI' `
    -Description 'winmgmt /salvagerepository - sprawdza spójność repozytorium WMI i odbudowuje je, gdy jest uszkodzone.' `
    -Detect {
    param($Ctx)
    if (Test-SdCtxProblem $Ctx 'sys.wmi') { [pscustomobject]@{ Problem = 'WMI nie odpowiadało albo odpowiadało bardzo wolno podczas diagnostyki.' } }
} -Apply {
    param($Data, $Log)
    $r = Invoke-Native -File (Join-Path $env:SystemRoot 'System32\wbem\winmgmt.exe') -Arguments '/salvagerepository' -TimeoutSec 900
    [void]$Log.Add('winmgmt /salvagerepository: kod ' + $r.ExitCode)
    if ($r.ExitCode -ne 0) { throw ('winmgmt zakończył się kodem {0}: {1}' -f $r.ExitCode, (Get-SdLastLine ($r.StdOut + $r.StdErr))) }
    $t = Get-SdLastLine $r.StdOut
    $(if ($t) { $t } else { 'Repozytorium WMI sprawdzone i naprawione.' })
}

Register-Fix -Id 'fx.dism' -Group 'System' -Order 20 -NeedsAdmin -NeedsInternet -Long -Covers @('up.cbs', 'tt.dism') `
    -Title 'Napraw magazyn składników Windows (DISM)' `
    -Description 'DISM /Online /Cleanup-Image /RestoreHealth - pobiera z Windows Update i podmienia uszkodzone składniki systemu (15-30 min). Bez internetu użyj „DISM RestoreHealth z płyty/ISO” w Narzędziach serwisowych.' `
    -Detect {
    param($Ctx)
    if ((Test-SdCtxProblem $Ctx 'up.cbs') -or (Test-SdCtxProblem $Ctx 'tt.dism')) { [pscustomobject]@{ Problem = 'Diagnostyka DISM wykryła uszkodzenia magazynu składników Windows.' } }
} -Apply {
    param($Data, $Log)
    $r = Invoke-Native -File (Join-Path $env:SystemRoot 'System32\Dism.exe') -Arguments '/Online /Cleanup-Image /RestoreHealth' -TimeoutSec 3600
    [void]$Log.Add('DISM /RestoreHealth: kod ' + (Format-Hr $r.ExitCode))
    if ($r.TimedOut) { throw 'DISM nie zakończył pracy w ciągu 60 minut.' }
    if ($r.ExitCode -ne 0) {
        $code = Format-Hr $r.ExitCode
        $why = $(if ($global:SdWuErrors.ContainsKey($code.ToLower())) { $global:SdWuErrors[$code.ToLower()] } else { Get-SdLastLine $r.StdOut })
        throw ('DISM zakończył się kodem {0}: {1}' -f $code, $why)
    }
    'Magazyn składników naprawiony.'
}

Register-Fix -Id 'fx.sfc' -Group 'System' -Order 21 -NeedsAdmin -Long -Covers @('up.cbs') `
    -Title 'Sprawdź i napraw pliki systemowe (SFC)' `
    -Description 'sfc /scannow - porównuje pliki systemowe z wzorcem i przywraca uszkodzone (10-20 min). Wykonywane po naprawie DISM.' `
    -Detect {
    param($Ctx)
    if ((Test-SdCtxProblem $Ctx 'up.cbs') -or (Test-SdCtxProblem $Ctx 'tt.dism')) { return [pscustomobject]@{ Problem = 'Uszkodzony magazyn składników - po jego naprawie trzeba sprawdzić pliki systemowe.' } }
    if ((Test-SdCtxProblem $Ctx 'ev.crash' '^Niebieskie ekrany') -or (Test-SdCtxProblem $Ctx 'ev.apps')) { return [pscustomobject]@{ Problem = 'Awarie systemu lub aplikacji - jedną z przyczyn bywają uszkodzone pliki systemowe.'; Default = $false } }
} -Apply {
    param($Data, $Log)
    $r = Invoke-Native -File (Join-Path $env:SystemRoot 'System32\sfc.exe') -Arguments '/scannow' -TimeoutSec 3600 -Encoding ([System.Text.Encoding]::Unicode)
    if ($r.TimedOut) { throw 'SFC nie zakończył pracy w ciągu 60 minut.' }
    $t = Get-SdLastLine $r.StdOut
    [void]$Log.Add('sfc /scannow: ' + $t)
    $(if ($t) { $t } else { 'Sprawdzanie zakończone (kod ' + $r.ExitCode + ').' })
}

# ---------------------------------------------------------------- Windows Update

Register-Fix -Id 'fx.wusvc' -Group 'Windows Update' -Order 30 -NeedsAdmin -Covers @('up.history|^Usługa Windows Update \(wuauserv\)$') `
    -Title 'Włącz usługę Windows Update' `
    -Description 'Przywraca uruchamianie usługi wuauserv na żądanie (tryb „Ręczny”, jak domyślnie w Windows 10/11).' `
    -Detect {
    param($Ctx)
    $s = Get-Cim Win32_Service -Filter "Name='wuauserv'" | Select-Object -First 1
    if ($s -and [string]$s.StartMode -eq 'Disabled') { [pscustomobject]@{ Problem = 'Usługa Windows Update jest wyłączona - system nie otrzymuje poprawek.' } }
} -Apply {
    param($Data, $Log)
    Set-SdServiceStartLogged -Name 'wuauserv' -StartupType Manual -Log $Log
    'Usługa Windows Update będzie uruchamiana na żądanie.'
}

Register-Fix -Id 'fx.wupolicy' -Group 'Windows Update' -Order 31 -NeedsAdmin -Risk medium -Covers @('up.pending|^Zasady Windows Update$') `
    -Title 'Usuń zasady blokujące Windows Update' `
    -Description 'Usuwa z rejestru zasady NoAutoUpdate / DisableWindowsUpdateAccess (często ustawiane przez „optymalizatory”). Na komputerach w domenie nie jest proponowane.' `
    -Detect {
    param($Ctx)
    $cs = Get-SdCs
    if ($cs -and $cs.PartOfDomain) { return }
    $au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $vals = @()
    if ([int](Get-RegValue ($au + '\AU') 'NoAutoUpdate' 0) -eq 1) { $vals += [pscustomobject]@{ Path = $au + '\AU'; Name = 'NoAutoUpdate' } }
    if ([int](Get-RegValue $au 'DisableWindowsUpdateAccess' 0) -eq 1) { $vals += [pscustomobject]@{ Path = $au; Name = 'DisableWindowsUpdateAccess' } }
    if ($vals.Count -gt 0) { [pscustomobject]@{ Problem = 'Zasady wyłączają aktualizacje: ' + (($vals | ForEach-Object { $_.Name }) -join ', ') + '.'; Data = $vals } }
} -Apply {
    param($Data, $Log)
    foreach ($v in @($Data)) { Remove-SdRegValueLogged -Path $v.Path -Name $v.Name -Log $Log }
    'Usunięto zasady blokujące aktualizacje.'
}

Register-Fix -Id 'fx.wureset' -Group 'Windows Update' -Order 32 -NeedsAdmin -Covers @('up.history|^Nieudane aktualizacje$', 'up.history|^Usługa Windows Update$') `
    -Title 'Zresetuj składniki Windows Update' `
    -Description 'Zatrzymuje usługi aktualizacji, zmienia nazwy folderów SoftwareDistribution i catroot2 na .old (pamięć podręczna pobierze się od nowa) i uruchamia usługi ponownie. Historia aktualizacji w Ustawieniach może się wyczyścić.' `
    -Detect {
    param($Ctx)
    if ((Test-SdCtxProblem $Ctx 'up.history' '^Nieudane aktualizacje$') -or (Test-SdCtxProblem $Ctx 'up.history' '^Usługa Windows Update$')) {
        [pscustomobject]@{ Problem = 'Aktualizacje kończą się błędami albo usługa Windows Update nie odpowiada.' }
    }
} -Apply {
    param($Data, $Log)
    $svcs = 'wuauserv', 'bits', 'cryptsvc'
    try {
        foreach ($s in $svcs) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
        foreach ($p in @(@((Join-Path $env:SystemRoot 'SoftwareDistribution'), 'SoftwareDistribution.old'), @((Join-Path $env:SystemRoot 'System32\catroot2'), 'catroot2.old'))) {
            $old = Join-Path (Split-Path $p[0] -Parent) $p[1]
            if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $p[0]) { Rename-Item -LiteralPath $p[0] -NewName $p[1] -ErrorAction Stop; [void]$Log.Add($p[0] + ' -> ' + $p[1]) }
        }
    } finally {
        foreach ($s in $svcs) { Start-Service -Name $s -ErrorAction SilentlyContinue }
    }
    'Składniki Windows Update zresetowane.'
}

Register-Fix -Id 'fx.drivers' -Group 'Sterowniki' -Order 35 -NeedsAdmin -NeedsInternet -Long -Covers @('dr.wu') `
    -Title 'Zainstaluj sterowniki z Windows Update' `
    -Description 'Pobiera i instaluje zalecane sterowniki oraz te, które naprawiają urządzenia z błędami (opcjonalne wybierzesz w Narzędziach > Sterowniki z Windows Update).' `
    -Detect {
    param($Ctx)
    $f = @(Get-SdCtxFindings $Ctx 'dr.wu' | Where-Object { $_.Status -eq 'warn' -or $_.Status -eq 'info' })
    if ($f.Count -gt 0) { [pscustomobject]@{ Problem = [string]$f[0].Value; Default = ($f[0].Status -eq 'warn') } }
} -Apply {
    param($Data, $Log)
    $found = & $global:SdWuDriverSearch -KeepResult
    if ($found.Error) { throw $found.Error }
    $sel = @(Select-SdDriversToInstall $found.Items)
    if ($sel.Count -eq 0) { return 'Brak zalecanych sterowników do zainstalowania.' }
    $ins = & $global:SdWuDriverInstall -UpdateIds @($sel | ForEach-Object { $_.UpdateId })
    if ($ins.Error) { throw $ins.Error }
    foreach ($x in @($ins.Results)) { [void]$Log.Add(('{0}: {1}' -f $x.Title, (Get-SdWuResultText $x.ResultCode))) }
    $ok = @($ins.Results | Where-Object { $_.ResultCode -eq 2 }).Count
    $all = @($ins.Results).Count
    [pscustomobject]@{ Result = $(if ($ok -eq $all) { 'ok' } else { 'warn' }); Message = ('Zainstalowano {0} z {1}.' -f $ok, $all); Reboot = [bool]$ins.RebootRequired }
}

# ---------------------------------------------------------------- bezpieczeństwo

Register-Fix -Id 'fx.defender' -Group 'Bezpieczeństwo' -Order 40 -NeedsAdmin -Covers @('se.av|^Microsoft Defender$', 'se.av|^Program antywirusowy$') `
    -Title 'Włącz ochronę Microsoft Defender' `
    -Description 'Usuwa zasady wyłączające Defendera i włącza ochronę w czasie rzeczywistym. Nie jest proponowane, gdy działa inny antywirus.' `
    -Detect {
    param($Ctx)
    $third = @(Get-Cim -Namespace 'root\SecurityCenter2' -Class AntivirusProduct | Where-Object { [string]$_.displayName -notmatch 'Defender' -and ((([uint32]$_.productState) -shr 12) -band 0xF) -eq 1 })
    if ($third.Count -gt 0) { return }
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    $vals = @()
    if ([int](Get-RegValue $pol 'DisableAntiSpyware' 0) -eq 1) { $vals += [pscustomobject]@{ Path = $pol; Name = 'DisableAntiSpyware' } }
    if ([int](Get-RegValue ($pol + '\Real-Time Protection') 'DisableRealtimeMonitoring' 0) -eq 1) { $vals += [pscustomobject]@{ Path = $pol + '\Real-Time Protection'; Name = 'DisableRealtimeMonitoring' } }
    $rtOff = $false
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try { $mp = Get-MpComputerStatus -ErrorAction Stop; if ($mp.RealTimeProtectionEnabled -eq $false) { $rtOff = $true } } catch { }
    }
    if ($vals.Count -eq 0 -and -not $rtOff) { return }
    $how = $(if ($vals.Count -gt 0) { ' (zasada w rejestrze: ' + (($vals | ForEach-Object { $_.Name }) -join ', ') + ')' } else { '' })
    [pscustomobject]@{ Problem = 'Ochrona Microsoft Defender jest wyłączona' + $how + '.'; Data = $vals }
} -Apply {
    param($Data, $Log)
    foreach ($v in @($Data)) { if ($v) { Remove-SdRegValueLogged -Path $v.Path -Name $v.Name -Log $Log } }
    try { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop; [void]$Log.Add('Defender: ochrona w czasie rzeczywistym -> włączona') } catch { }
    Start-Sleep -Seconds 2
    $mp = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { }
    if ($mp -and $mp.RealTimeProtectionEnabled -eq $false) {
        throw 'Ochrona nadal jest wyłączona - blokuje to ochrona przed manipulacją (Tamper Protection) albo złośliwe oprogramowanie. Włącz ją ręcznie w Zabezpieczeniach Windows i przeskanuj komputer.'
    }
    'Ochrona w czasie rzeczywistym włączona.'
}

Register-Fix -Id 'fx.defsig' -Group 'Bezpieczeństwo' -Order 41 -NeedsAdmin -NeedsInternet -Covers @('se.av|^Microsoft Defender$') `
    -Title 'Zaktualizuj definicje Microsoft Defender' `
    -Description 'Pobiera najnowsze definicje wirusów (Update-MpSignature).' `
    -Detect {
    param($Ctx)
    $f = @(Get-SdCtxFindings $Ctx 'se.av' '^Microsoft Defender$' | Where-Object { ($_.Status -eq 'warn' -or $_.Status -eq 'crit') -and [string]$_.Value -match 'Definicje' })
    if ($f.Count -gt 0) { [pscustomobject]@{ Problem = [string]$f[0].Value } }
} -Apply {
    param($Data, $Log)
    Update-MpSignature -ErrorAction Stop
    $age = $null
    try { $age = (Get-MpComputerStatus -ErrorAction Stop).AntivirusSignatureAge } catch { }
    [void]$Log.Add('Update-MpSignature: wykonano')
    'Definicje zaktualizowane' + $(if ($null -ne $age) { ' (wiek: ' + $age + ' dn.)' } else { '' }) + '.'
}

Register-Fix -Id 'fx.firewall' -Group 'Bezpieczeństwo' -Order 42 -NeedsAdmin -Covers @('se.firewall') `
    -Title 'Włącz zaporę systemu Windows' `
    -Description 'Włącza zaporę w profilach, w których jest wyłączona (i usuwa zasady, które ją wyłączają). Nie jest proponowane, gdy działa zapora innego producenta albo wyłącza ją zasada domeny.' `
    -Detect {
    param($Ctx)
    $third = @(Get-Cim -Namespace 'root\SecurityCenter2' -Class FirewallProduct | Where-Object { [string]$_.displayName -notmatch 'Windows' -and ((([uint32]$_.productState) -shr 12) -band 0xF) -eq 1 })
    if ($third.Count -gt 0) { return }
    $cs = Get-SdCs
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy'
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall'
    $off = @()
    foreach ($p in @(@('DomainProfile', 'Domain', 'domenowy'), @('StandardProfile', 'Private', 'prywatny'), @('PublicProfile', 'Public', 'publiczny'))) {
        $v = Get-RegValue ($base + '\' + $p[0]) 'EnableFirewall' $null
        $pv = Get-RegValue ($pol + '\' + $p[0]) 'EnableFirewall' $null
        $eff = $(if ($null -ne $pv) { $pv } else { $v })
        if ($null -eq $eff -or [int]$eff -ne 0) { continue }
        if ($null -ne $pv -and $cs -and $cs.PartOfDomain) { continue }
        $off += [pscustomobject]@{ Profile = $p[1]; Label = $p[2]; PolicyPath = $(if ($null -ne $pv) { $pol + '\' + $p[0] } else { '' }) }
    }
    if ($off.Count -gt 0) { [pscustomobject]@{ Problem = 'Zapora jest wyłączona w profilach: ' + (($off | ForEach-Object { $_.Label }) -join ', ') + '.'; Data = $off } }
} -Apply {
    param($Data, $Log)
    foreach ($o in @($Data)) { if ($o.PolicyPath) { Remove-SdRegValueLogged -Path $o.PolicyPath -Name 'EnableFirewall' -Log $Log } }
    $names = @($Data | ForEach-Object { [string]$_.Profile })
    Set-NetFirewallProfile -Profile $names -Enabled True -ErrorAction Stop
    [void]$Log.Add('Zapora: włączono profile ' + ($names -join ', '))
    Add-SdUndoRecord @{ Kind = 'firewall'; Profiles = $names }
    'Zapora włączona (' + (@($Data | ForEach-Object { $_.Label }) -join ', ') + ').'
}

Register-Fix -Id 'fx.uac' -Group 'Bezpieczeństwo' -Order 43 -NeedsAdmin -Covers @('se.uac') `
    -Title 'Włącz Kontrolę konta użytkownika (UAC)' `
    -Description 'Przywraca domyślny poziom UAC (powiadomienia o zmianach wprowadzanych przez programy). Po całkowitym wyłączeniu UAC potrzebny jest restart.' `
    -Detect {
    param($Ctx)
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $lua = [int](Get-RegValue $k 'EnableLUA' 1)
    $adm = [int](Get-RegValue $k 'ConsentPromptBehaviorAdmin' 5)
    if ($lua -eq 0) { return [pscustomobject]@{ Problem = 'UAC jest całkowicie wyłączone.' } }
    if ($adm -eq 0) { return [pscustomobject]@{ Problem = 'UAC nie pyta administratora o zgodę na zmiany.' } }
} -Apply {
    param($Data, $Log)
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $wasOff = ([int](Get-RegValue $k 'EnableLUA' 1) -eq 0)
    Set-SdRegValueLogged -Path $k -Name 'EnableLUA' -Value 1 -Log $Log
    Set-SdRegValueLogged -Path $k -Name 'ConsentPromptBehaviorAdmin' -Value 5 -Log $Log
    Set-SdRegValueLogged -Path $k -Name 'PromptOnSecureDesktop' -Value 1 -Log $Log
    [pscustomobject]@{ Result = 'ok'; Message = 'Przywrócono domyślny poziom UAC.'; Reboot = $wasOff }
}

Register-Fix -Id 'fx.smb1' -Group 'Bezpieczeństwo' -Order 44 -NeedsAdmin -DefaultOff -Risk medium `
    -Title 'Wyłącz przestarzały protokół SMB1' `
    -Description 'Wyłącza serwer SMB1 (podatność wykorzystana przez WannaCry). Uwaga: stare urządzenia (NAS, drukarki skanujące do folderu) mogą stracić dostęp do udostępnionych folderów tego komputera.' `
    -Detect {
    param($Ctx)
    $on = $null
    if ($Ctx.IsAdmin -and (Get-Command Get-SmbServerConfiguration -ErrorAction SilentlyContinue)) {
        try { $on = [bool](Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol } catch { }
    }
    if ($null -eq $on) { $r = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1' $null; if ($null -ne $r) { $on = ([int]$r -ne 0) } }
    if ($on -eq $true) { [pscustomobject]@{ Problem = 'Włączony jest serwer SMB1.' } }
} -Apply {
    param($Data, $Log)
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -Confirm:$false -ErrorAction Stop
    [void]$Log.Add('SMB1 (serwer): włączony -> wyłączony')
    Add-SdUndoRecord @{ Kind = 'smb1' }
    'Serwer SMB1 wyłączony.'
}

Register-Fix -Id 'fx.remotereg' -Group 'Bezpieczeństwo' -Order 45 -NeedsAdmin `
    -Title 'Zatrzymaj usługę Zdalny rejestr' `
    -Description 'Zatrzymuje i wyłącza usługę RemoteRegistry, która pozwala zmieniać rejestr tego komputera przez sieć. Na komputerach w domenie nie jest proponowane.' `
    -Detect {
    param($Ctx)
    $cs = Get-SdCs
    if ($cs -and $cs.PartOfDomain) { return }
    $s = Get-Service -Name RemoteRegistry -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq 'Running') { [pscustomobject]@{ Problem = 'Działa usługa Zdalny rejestr.' } }
} -Apply {
    param($Data, $Log)
    Stop-Service -Name RemoteRegistry -Force -ErrorAction Stop
    Set-SdServiceStartLogged -Name 'RemoteRegistry' -StartupType Disabled -Log $Log
    'Usługa Zdalny rejestr zatrzymana i wyłączona.'
}

Register-Fix -Id 'fx.winlogon' -Group 'Bezpieczeństwo' -Order 46 -NeedsAdmin -Risk medium `
    -Title 'Przywróć domyślne ustawienia logowania (Winlogon)' `
    -Description 'Przywraca wartości Shell = explorer.exe i Userinit = userinit.exe - złośliwe programy dopisują tam siebie, żeby uruchamiać się przy każdym logowaniu.' `
    -Detect {
    param($Ctx)
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $bad = @()
    $shell = [string](Get-RegValue $wl 'Shell' 'explorer.exe')
    $uinit = [string](Get-RegValue $wl 'Userinit' '')
    if (-not (Test-SdDefaultWinlogon -Value $shell -Kind Shell)) { $bad += ('Shell = ' + $shell) }
    if (-not (Test-SdDefaultWinlogon -Value $uinit -Kind Userinit)) { $bad += ('Userinit = ' + $uinit) }
    if ($bad.Count -gt 0) { [pscustomobject]@{ Problem = 'Niestandardowe wartości: ' + ($bad -join '; ') } }
} -Apply {
    param($Data, $Log)
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    if (-not (Test-SdDefaultWinlogon -Value ([string](Get-RegValue $wl 'Shell' 'explorer.exe')) -Kind Shell)) { Set-SdRegValueLogged -Path $wl -Name 'Shell' -Value 'explorer.exe' -Type String -Log $Log }
    if (-not (Test-SdDefaultWinlogon -Value ([string](Get-RegValue $wl 'Userinit' '')) -Kind Userinit)) { Set-SdRegValueLogged -Path $wl -Name 'Userinit' -Value ($env:SystemRoot + '\system32\userinit.exe,') -Type String -Log $Log }
    'Przywrócono domyślne wartości Winlogon - przeskanuj komputer programem antywirusowym.'
}

Register-Fix -Id 'fx.ifeo' -Group 'Bezpieczeństwo' -Order 47 -NeedsAdmin `
    -Title 'Usuń przekierowanie programu (IFEO)' `
    -Description 'Usuwa wartość Debugger, która zamiast właściwego programu uruchamia inny (typowa tylna furtka przez narzędzia ułatwień dostępu albo blokada antywirusa).' `
    -Detect {
    param($Ctx)
    $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    $access = 'sethc.exe', 'utilman.exe', 'osk.exe', 'narrator.exe', 'magnify.exe', 'displayswitch.exe', 'atbroker.exe'
    foreach ($key in @(Get-ChildItem -LiteralPath $ifeo -ErrorAction SilentlyContinue)) {
        $dbg = Get-RegValue $key.PSPath 'Debugger' $null
        if (-not $dbg) { continue }
        $nm = [string]$key.PSChildName
        if ($access -contains $nm.ToLower() -or $nm -match 'MsMpEng|MpCmdRun|NisSrv|mbam|avast|avg|kaspersky|eset|bdagent|taskmgr|regedit|cmd\.exe|powershell|mmc\.exe') {
            [pscustomobject]@{ Key = $nm; Title = 'Usuń przekierowanie programu: ' + $nm; Problem = ('Uruchomienie {0} jest przekierowane do: {1}' -f $nm, $dbg); Data = [pscustomobject]@{ Path = $ifeo + '\' + $nm } }
        }
    }
} -Apply {
    param($Data, $Log)
    Remove-SdRegValueLogged -Path $Data.Path -Name 'Debugger' -Log $Log
    'Usunięto przekierowanie.'
}

Register-Fix -Id 'fx.appinit' -Group 'Bezpieczeństwo' -Order 48 -NeedsAdmin `
    -Title 'Wyłącz ładowanie bibliotek AppInit_DLLs' `
    -Description 'Wyłącza mechanizm wstrzykiwania bibliotek do każdego programu (LoadAppInit_DLLs = 0); lista bibliotek zostaje w rejestrze do wglądu.' `
    -Detect {
    param($Ctx)
    $keys = @()
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Windows') {
        $ai = [string](Get-RegValue $k 'AppInit_DLLs' '')
        if ($ai.Trim() -and [int](Get-RegValue $k 'LoadAppInit_DLLs' 0) -eq 1) { $keys += [pscustomobject]@{ Path = $k; Dlls = $ai } }
    }
    if ($keys.Count -gt 0) { [pscustomobject]@{ Problem = 'AppInit_DLLs ładuje do każdego programu: ' + (($keys | ForEach-Object { $_.Dlls }) -join '; '); Data = $keys } }
} -Apply {
    param($Data, $Log)
    foreach ($k in @($Data)) { Set-SdRegValueLogged -Path $k.Path -Name 'LoadAppInit_DLLs' -Value 0 -Log $Log }
    'Ładowanie AppInit_DLLs wyłączone - przeskanuj komputer programem antywirusowym.'
}

# ---------------------------------------------------------------- dysk i system

Register-Fix -Id 'fx.dumps' -Group 'Dysk i system' -Order 50 -NeedsAdmin -Reboot -Covers @('ev.crash|^Zrzuty pamięci$') `
    -Title 'Włącz zapisywanie zrzutów pamięci po awarii' `
    -Description 'Ustawia automatyczny zrzut pamięci - przy kolejnym niebieskim ekranie powstanie plik do analizy przyczyny.' `
    -Detect {
    param($Ctx)
    $v = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'CrashDumpEnabled' $null
    if ($null -ne $v -and [int]$v -eq 0) { [pscustomobject]@{ Problem = 'Zapis zrzutów pamięci jest wyłączony - przyczyny niebieskich ekranów nie da się przeanalizować.' } }
} -Apply {
    param($Data, $Log)
    Set-SdRegValueLogged -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'CrashDumpEnabled' -Value 7 -Log $Log
    'Włączono automatyczny zrzut pamięci (działa po ponownym uruchomieniu).'
}

Register-Fix -Id 'fx.trim' -Group 'Dysk i system' -Order 51 -NeedsAdmin -Covers @('st.layout|^TRIM') `
    -Title 'Włącz TRIM dla dysków SSD' `
    -Description 'fsutil behavior set DisableDeleteNotify 0 - SSD dowiaduje się o usuniętych plikach, co utrzymuje jego wydajność i trwałość.' `
    -Detect {
    param($Ctx)
    $fs = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    if ([int](Get-RegValue $fs 'DisableDeleteNotification' 0) -ne 1 -and [int](Get-RegValue $fs 'NtfsDisableDeleteNotification' 0) -ne 1) { return }
    if (@(Get-SdDiskInventory | Where-Object { (Get-SdDiskTypeName $_) -match 'SSD' }).Count -eq 0) { return }
    [pscustomobject]@{ Problem = 'TRIM jest wyłączony, a komputer ma dysk SSD.' }
} -Apply {
    param($Data, $Log)
    $fsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    $before = Get-SdRegSnapshot $fsKey @('DisableDeleteNotification', 'NtfsDisableDeleteNotification', 'RefsDisableDeleteNotification')
    $r = Invoke-Native -File (Join-Path $env:SystemRoot 'System32\fsutil.exe') -Arguments 'behavior set DisableDeleteNotify 0' -TimeoutSec 30
    Add-SdRegSnapshotUndo $fsKey $before
    if ($r.ExitCode -ne 0) { throw ('fsutil zakończył się kodem {0}: {1}' -f $r.ExitCode, (Get-SdLastLine ($r.StdOut + $r.StdErr))) }
    [void]$Log.Add('fsutil behavior set DisableDeleteNotify 0')
    'TRIM włączony.'
}

Register-Fix -Id 'fx.pagefile' -Group 'Dysk i system' -Order 52 -NeedsAdmin -Reboot -Covers @('st.pagefile|^Plik wymiany') `
    -Title 'Przywróć automatyczny plik wymiany' `
    -Description 'Włącza plik wymiany zarządzany przez system - jego brak powoduje błędy braku pamięci i uniemożliwia zrzuty awaryjne.' `
    -Detect {
    param($Ctx)
    $f = @(Get-SdCtxFindings $Ctx 'st.pagefile' '^Plik wymiany' | Where-Object { $_.Status -eq 'warn' -and [string]$_.Value -match 'Wyłączony' })
    if ($f.Count -gt 0) { [pscustomobject]@{ Problem = 'Plik wymiany jest wyłączony.' } }
} -Apply {
    param($Data, $Log)
    $mmKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $before = Get-SdRegSnapshot $mmKey @('PagingFiles')
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
    Add-SdRegSnapshotUndo $mmKey $before
    [void]$Log.Add('Win32_ComputerSystem.AutomaticManagedPagefile: False -> True')
    'Plik wymiany będzie zarządzany przez system (po ponownym uruchomieniu).'
}

Register-Fix -Id 'fx.cleanup' -Group 'Dysk i system' -Order 55 -NeedsAdmin -Covers @(('st.volumes|^Wolumin ' + [regex]::Escape([string]$env:SystemDrive) + '$'), 'st.cleanup') `
    -Title 'Usuń pliki tymczasowe' `
    -Description 'Czyści foldery Temp (system i użytkownicy), raporty błędów Windows i pobrane pakiety Windows Update. Pliki używane przez programy zostaną pominięte.' `
    -Detect {
    param($Ctx)
    $sys = ([string]$env:SystemDrive).ToUpper()
    $low = @(Get-SdCtxFindings $Ctx 'st.volumes' ('^Wolumin ' + [regex]::Escape($sys) + '$') | Where-Object { $_.Status -eq 'warn' -or $_.Status -eq 'crit' })
    if ($low.Count -gt 0) { return [pscustomobject]@{ Problem = 'Mało miejsca na dysku systemowym: ' + [string]$low[0].Value } }
    $cl = @(Get-SdCtxFindings $Ctx 'st.cleanup' | Where-Object { $_.Status -eq 'info' })
    if ($cl.Count -gt 0) { return [pscustomobject]@{ Problem = [string]$cl[0].Value; Default = $false } }
    [pscustomobject]@{ Problem = 'Rutynowe porządki: pliki tymczasowe, raporty błędów i pamięć podręczna aktualizacji.'; Default = $false }
} -Apply {
    param($Data, $Log)
    $dirs = @((Join-Path $env:SystemRoot 'Temp'))
    foreach ($up in (Get-SdUserProfiles)) { $dirs += (Join-Path $up.LocalPath 'AppData\Local\Temp') }
    $wer = Join-Path $env:ProgramData 'Microsoft\Windows\WER'
    $dirs += (Join-Path $wer 'ReportArchive')
    $dirs += (Join-Path $wer 'ReportQueue')
    $swd = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
    $measure = { $t = 0.0; foreach ($d in ($dirs + $swd)) { if (Test-Path -LiteralPath $d) { $t += (Get-SdDirSize $d).Bytes } }; $t }
    $before = & $measure
    foreach ($d in $dirs) { Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wasRunning = ($wu -and $wu.Status -eq 'Running')
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $swd -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    if ($wasRunning) { Start-Service -Name wuauserv -ErrorAction SilentlyContinue }
    # 0.0, nie 0: PowerShell wybiera wersję Max według pierwszego argumentu, a Int32 nie zmieści ponad 2 GB
    $freed = [math]::Max(0.0, $before - (& $measure))
    [void]$Log.Add('Usunięto pliki tymczasowe: ' + (Format-Size $freed 1))
    'Zwolniono ' + (Format-Size $freed 1) + '.'
}

# ---------------------------------------------------------------- sieć

Register-Fix -Id 'fx.dns' -Group 'Sieć' -Order 60 -Covers @('nw.connectivity|DNS') `
    -Title 'Wyczyść pamięć podręczną DNS' `
    -Description 'ipconfig /flushdns - usuwa zapamiętane (także błędne) odpowiedzi serwerów nazw.' `
    -Detect {
    param($Ctx)
    if (Test-SdCtxProblem $Ctx 'nw.connectivity' 'DNS') { [pscustomobject]@{ Problem = 'Problemy z rozpoznawaniem nazw (DNS).' } }
} -Apply {
    param($Data, $Log)
    $r = Invoke-Native -File (Join-Path $env:SystemRoot 'System32\ipconfig.exe') -Arguments '/flushdns' -TimeoutSec 30
    if ($r.ExitCode -ne 0) { throw ('ipconfig zakończył się kodem ' + $r.ExitCode) }
    [void]$Log.Add('ipconfig /flushdns')
    'Pamięć podręczna DNS wyczyszczona.'
}

Register-Fix -Id 'fx.time' -Group 'Sieć' -Order 61 -NeedsAdmin -NeedsInternet -Covers @('nw.connectivity|^Zegar systemowy$') `
    -Title 'Zsynchronizuj zegar systemowy' `
    -Description 'Uruchamia usługę Czas systemu Windows i synchronizuje zegar z serwerem czasu (błędny czas psuje HTTPS, logowanie i aktualizacje).' `
    -Detect {
    param($Ctx)
    $f = @(Get-SdCtxFindings $Ctx 'nw.connectivity' '^Zegar systemowy$' | Where-Object { $_.Status -eq 'warn' -or $_.Status -eq 'crit' })
    if ($f.Count -gt 0) { [pscustomobject]@{ Problem = [string]$f[0].Value } }
} -Apply {
    param($Data, $Log)
    $svc = Get-Cim Win32_Service -Filter "Name='w32time'" | Select-Object -First 1
    if ($svc -and [string]$svc.StartMode -eq 'Disabled') { Set-SdServiceStartLogged -Name 'w32time' -StartupType Manual -Log $Log }
    Start-Service -Name w32time -ErrorAction SilentlyContinue
    $w = Join-Path $env:SystemRoot 'System32\w32tm.exe'
    $r = Invoke-Native -File $w -Arguments '/resync' -TimeoutSec 60
    if ($r.ExitCode -ne 0) {
        # komputer bez skonfigurowanego źródła czasu - ustawiamy serwer Microsoft i próbujemy ponownie
        [void](Invoke-Native -File $w -Arguments '/config /manualpeerlist:time.windows.com,0x9 /syncfromflags:manual /update' -TimeoutSec 30)
        [void]$Log.Add('w32tm: źródło czasu -> time.windows.com')
        $r = Invoke-Native -File $w -Arguments '/resync /rediscover' -TimeoutSec 60
    }
    if ($r.ExitCode -ne 0) { throw ('Synchronizacja nie powiodła się: ' + (Get-SdLastLine $r.StdOut)) }
    'Zegar zsynchronizowany z serwerem czasu.'
}

Register-Fix -Id 'fx.proxy' -Group 'Sieć' -Order 62 -Covers @('nw.config|[Pp]roxy') `
    -Title 'Wyłącz ręczne ustawienie serwera proxy' `
    -Description 'Wyłącza serwer proxy w ustawieniach internetowych użytkowników (adres zostaje zapisany w dzienniku). Proponowane tylko, gdy strony internetowe nie działają.' `
    -Detect {
    param($Ctx)
    if (-not ((Test-SdCtxProblem $Ctx 'nw.connectivity' 'HTTP'))) { return }
    $sub = '\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $targets = @('HKCU:' + $sub)
    foreach ($h in (Get-SdUserHives)) { $targets += ($h.Path + $sub) }
    $on = @($targets | Where-Object { [int](Get-RegValue $_ 'ProxyEnable' 0) -eq 1 })
    if ($on.Count -gt 0) { [pscustomobject]@{ Problem = 'Strony internetowe nie działają, a ustawiono serwer proxy: ' + [string](Get-RegValue $on[0] 'ProxyServer' '') + '.'; Data = $on } }
} -Apply {
    param($Data, $Log)
    foreach ($p in @($Data)) { Set-SdRegValueLogged -Path $p -Name 'ProxyEnable' -Value 0 -Log $Log }
    'Serwer proxy wyłączony.'
}

Register-Fix -Id 'fx.winsock' -Group 'Sieć' -Order 65 -NeedsAdmin -Reboot -DefaultOff -Risk medium -Covers @('nw.connectivity|^Ping do internetu', 'nw.connectivity|^Dostęp do internetu') `
    -Title 'Zresetuj Winsock i stos TCP/IP' `
    -Description 'netsh winsock reset oraz netsh int ip reset - naprawia uszkodzone ustawienia sieci. Uwaga: usuwa ręcznie ustawione adresy IP i może wymagać ponownej instalacji klienta VPN; potrzebny restart.' `
    -Detect {
    param($Ctx)
    if ($Ctx.Offline) { return }
    # tylko przy faktycznym braku internetu (utrata części pakietów to zwykle jakość Wi-Fi, nie uszkodzony stos sieciowy)
    $down = (@(Get-SdCtxFindings $Ctx 'nw.connectivity' '^Ping do internetu' | Where-Object { $_.Status -eq 'crit' }).Count -gt 0) -or
    (@(Get-SdCtxFindings $Ctx 'nw.connectivity' '^Dostęp do internetu \(HTTP\)$' | Where-Object { $_.Status -eq 'crit' }).Count -gt 0) -or
    (@(Get-SdCtxFindings $Ctx 'nw.connectivity' '^Dostęp do internetu \(HTTPS\)$' | Where-Object { [string]$_.Value -match '^Brak' }).Count -gt 0)
    if ($down) { [pscustomobject]@{ Problem = 'Brak łączności z internetem mimo aktywnego połączenia sieciowego.' } }
} -Apply {
    param($Data, $Log)
    $n = Join-Path $env:SystemRoot 'System32\netsh.exe'
    $a = Invoke-Native -File $n -Arguments 'winsock reset' -TimeoutSec 60
    $b = Invoke-Native -File $n -Arguments 'int ip reset' -TimeoutSec 60
    [void]$Log.Add('netsh winsock reset: kod ' + $a.ExitCode)
    [void]$Log.Add('netsh int ip reset: kod ' + $b.ExitCode)
    if ($a.ExitCode -ne 0) { throw ('netsh winsock reset: ' + (Get-SdLastLine $a.StdOut)) }
    'Zresetowano Winsock i TCP/IP - uruchom komputer ponownie.'
}

# ---------------------------------------------------------------- autostart i programy

Register-Fix -Id 'fx.startup' -Group 'Autostart' -Order 70 -NeedsAdmin -Covers @('sw.startup|^Autostart$') `
    -Title 'Wyłącz podejrzany wpis autostartu' `
    -Description 'Wyłącza wpis tak jak Menedżer zadań > Autostart (nie usuwa plików; można go włączyć z powrotem).' `
    -Detect {
    param($Ctx)
    foreach ($e in (Get-SdStartupEntries)) {
        if (-not $e.Enabled -or $e.Kind -eq 'RunOnce' -or -not $e.Approved) { continue }
        $why = Get-SdStartupSuspicion $e
        if ($why) { [pscustomobject]@{ Key = $e.Approved + '|' + $e.ApprovedName; Title = 'Wyłącz z autostartu: ' + $e.Name; Problem = $why + ' (' + $e.Source + ', ' + $e.Owner + ')'; Data = $e } }
    }
} -Apply {
    param($Data, $Log)
    Set-SdRegValueLogged -Path $Data.Approved -Name $Data.ApprovedName -Value (New-SdStartupDisabledValue) -Type Binary -Log $Log
    'Wyłączono z autostartu (można przywrócić w Menedżerze zadań > Autostart).'
}

Register-Fix -Id 'fx.startupopt' -Group 'Autostart (przyspieszenie startu)' -Order 71 -NeedsAdmin -DefaultOff -Covers @('sw.startup|^Autostart$') `
    -Title 'Wyłącz program z autostartu' `
    -Description 'Program nie będzie uruchamiał się razem z Windows (wyłączenie jak w Menedżerze zadań > Autostart; można cofnąć). Zaznacz te, których klient nie potrzebuje od razu po starcie.' `
    -Detect {
    param($Ctx)
    if (@(Get-SdCtxFindings $Ctx 'sw.startup' '^Autostart$' | Where-Object { $_.Status -eq 'warn' -or $_.Status -eq 'info' }).Count -eq 0) { return }
    foreach ($e in (Get-SdStartupEntries)) {
        if (-not $e.Enabled -or $e.Kind -eq 'RunOnce' -or -not $e.Approved) { continue }
        if (Get-SdStartupSuspicion $e) { continue }
        $exe = Resolve-SdCommandPath $e.Command
        if ($exe -and $exe.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $fi = Get-SdFileInfo $exe
        [pscustomobject]@{ Key = $e.Approved + '|' + $e.ApprovedName; Title = 'Wyłącz z autostartu: ' + $e.Name; Problem = (Join-NonEmpty @($fi.Company, (Limit-Text $e.Command 90)) ' · '); Data = $e; Default = $false }
    }
} -Apply {
    param($Data, $Log)
    Set-SdRegValueLogged -Path $Data.Approved -Name $Data.ApprovedName -Value (New-SdStartupDisabledValue) -Type Binary -Log $Log
    'Wyłączono z autostartu (można przywrócić w Menedżerze zadań > Autostart).'
}

Register-Fix -Id 'fx.uninstall' -Group 'Oprogramowanie' -Order 90 -NeedsAdmin -DefaultOff -Interactive -Risk medium `
    -Covers @('sw.installed|^Programy potencjalnie niechciane', 'sw.installed|^Optymalizatory', 'sw.installed|^Narzędzia do obchodzenia aktywacji') `
    -Title 'Odinstaluj program' `
    -Description 'Uruchamia deinstalator programu - jego okno trzeba przejść ręcznie. Deinstalacje wykonywane są na końcu, po pozostałych naprawach.' `
    -Detect {
    param($Ctx)
    $flags = Get-SdData 'software-flags'
    if (-not $flags) { return }
    $types = @{ pup = 'program potencjalnie niechciany'; optimizer = 'optymalizator lub aktualizator sterowników'; crack = 'narzędzie do obchodzenia aktywacji' }
    $seen = @{}
    foreach ($app in (Get-SdUninstallEntries)) {
        if ($seen.ContainsKey($app.KeyPath)) { continue }
        foreach ($f in $flags.Flags) {
            $t = [string]$f.Type
            if (-not $types.ContainsKey($t) -or $app.Name -notmatch $f.Pattern) { continue }
            $seen[$app.KeyPath] = $true
            if ($app.UninstallString -or $app.QuietUninstallString) {
                [pscustomobject]@{
                    Key = $app.KeyPath; Title = 'Odinstaluj: ' + $app.Name; Problem = $types[$t] + $(if ($f.Note) { ' - ' + $f.Note } else { '' }); Data = $app; Default = $false
                    CustomerTitle = $(if ($t -eq 'crack') { 'Usunięcie programu wysokiego ryzyka' } else { '' })
                }
            }
            break
        }
    }
} -Apply {
    param($Data, $Log)
    $cmd = ConvertTo-SdUninstallCommand $(if ($Data.UninstallString) { $Data.UninstallString } else { $Data.QuietUninstallString })
    if (-not $cmd) { throw 'Brak polecenia deinstalacji - usuń program w Programach i funkcjach.' }
    [void]$Log.Add(('Deinstalator: {0} {1}' -f $cmd.File, $cmd.Arguments).Trim())
    $sp = @{ FilePath = $cmd.File; PassThru = $true; ErrorAction = 'Stop' }
    if ($cmd.Arguments) { $sp['ArgumentList'] = $cmd.Arguments }
    $p = Start-Process @sp
    if (-not $p.WaitForExit(1800000)) { return [pscustomobject]@{ Result = 'warn'; Message = 'Deinstalator nadal działa - dokończ go ręcznie.' } }
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $Data.KeyPath) { return [pscustomobject]@{ Result = 'warn'; Message = ('Deinstalator zakończył się (kod {0}), ale program nadal jest na liście zainstalowanych - sprawdź ręcznie.' -f $p.ExitCode) } }
    'Program odinstalowany.'
}

# ---------------------------------------------------------------- wykrywanie, wykonanie, dziennik

function Get-SdFixCandidates {
    # Lista napraw dla bieżącego stanu komputera. Context: @{ Result; IsAdmin; Offline }.
    param($Context)
    $out = New-Object System.Collections.ArrayList
    foreach ($f in @($global:SdFixes | Sort-Object Order)) {
        $items = @()
        try { $items = @(& $f.Detect $Context) } catch { Write-SdLog ('Naprawa {0} - wykrywanie: {1}' -f $f.Id, $_.Exception.Message) 'WARN'; continue }
        foreach ($it in $items) {
            if ($null -eq $it) { continue }
            if ($it -is [string]) { $it = [pscustomobject]@{ Problem = $it } }
            $blocked = ''
            if ($f.NeedsAdmin -and -not $Context.IsAdmin) { $blocked = 'wymaga uprawnień administratora' }
            elseif ($f.NeedsInternet -and $Context.Offline) { $blocked = 'wymaga internetu (włączony tryb bez internetu)' }
            $def = -not $f.DefaultOff
            if ($it.PSObject.Properties['Default'] -and $null -ne $it.Default) { $def = [bool]$it.Default }
            $p = $it.PSObject.Properties
            [void]$out.Add([pscustomobject]@{
                    FixId = $f.Id; Key = $f.Id + '|' + $(if ($p['Key']) { [string]$it.Key } else { '' }); Group = $f.Group
                    Title = $(if ($p['Title'] -and $it.Title) { [string]$it.Title } else { $f.Title })
                    CustomerTitle = $(if ($p['CustomerTitle']) { [string]$it.CustomerTitle } else { '' })
                    Problem = $(if ($p['Problem']) { [string]$it.Problem } else { '' }); Description = $f.Description
                    Risk = $f.Risk; Reboot = $f.Reboot; Long = $f.Long; Interactive = $f.Interactive; NeedsAdmin = $f.NeedsAdmin; NeedsInternet = $f.NeedsInternet
                    Covers = @($f.Covers); Default = ($def -and -not $blocked); Blocked = $blocked; Order = $f.Order
                    Data = $(if ($p['Data']) { $it.Data } else { $null })
                })
        }
    }
    return @($out)
}

function Get-SdUnfixedProblems {
    # Problemy z diagnostyki (krytyczne i ostrzeżenia), których żadna proponowana naprawa nie obejmuje - wymagają serwisanta.
    param($Result, $Candidates)
    $covers = @()
    foreach ($c in @($Candidates)) { foreach ($cv in @($c.Covers)) { if ($cv) { $covers += [string]$cv } } }
    $out = @()
    foreach ($f in @($Result.Findings)) {
        if ($null -eq $f -or ($f.Status -ne 'crit' -and $f.Status -ne 'warn')) { continue }
        $hit = $false
        foreach ($cv in $covers) {
            $p = $cv -split '\|', 2
            if ([string]$f.CheckId -eq $p[0] -and ($p.Count -eq 1 -or [string]$f.Title -match $p[1])) { $hit = $true; break }
        }
        if (-not $hit) { $out += $f }
    }
    return $out
}

function New-SdRepairRestorePoint {
    # Punkt przywracania przed naprawami (okno i konsola). Windows tworzy najwyżej jeden taki punkt na 24 godziny.
    Checkpoint-Computer -Description 'SerwisDiag - przed naprawami' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
}

function Invoke-SdFixes {
    # Wykonuje wybrane naprawy po kolei (wg kolejności z katalogu). Status (hashtable; w oknie synchronizowany): Index, Total, Text.
    param($Candidates, $Status = $null, [scriptblock]$OnItem = $null)
    $list = @($Candidates | Where-Object { $null -ne $_ } | Sort-Object Order, Key)
    $results = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($c in $list) {
        $i++
        if ($null -ne $Status) { $Status['Index'] = $i; $Status['Total'] = $list.Count; $Status['Text'] = $c.Title }
        if ($OnItem) { & $OnItem $i $list.Count $c }
        $r = [pscustomobject]@{ Title = $c.Title; CustomerTitle = [string]$c.CustomerTitle; FixId = $c.FixId; Result = 'ok'; Message = ''; Reboot = $false; Changes = @(); Undo = @() }
        $fix = $null
        foreach ($f in $global:SdFixes) { if ($f.Id -eq $c.FixId) { $fix = $f; break } }
        if ($c.Blocked) { $r.Result = 'skip'; $r.Message = 'Pominięto: ' + $c.Blocked }
        elseif (-not $fix) { $r.Result = 'error'; $r.Message = 'Nieznana naprawa: ' + $c.FixId }
        else {
            $log = New-Object System.Collections.ArrayList
            # rekordy cofania zbieramy także wtedy, gdy naprawa przerwie się w połowie - zmiany sprzed błędu da się cofnąć
            $global:SdUndoSink = New-Object System.Collections.ArrayList
            try {
                $out = @(& $fix.Apply $c.Data $log)
                $last = $null
                if ($out.Count -gt 0) { $last = $out[$out.Count - 1] }
                $r.Reboot = [bool]$fix.Reboot
                if ($null -ne $last -and $last.PSObject.Properties['Result']) {
                    $r.Result = [string]$last.Result; $r.Message = [string]$last.Message
                    if ($last.PSObject.Properties['Reboot']) { $r.Reboot = [bool]$last.Reboot }
                } else { $r.Message = (@($out | ForEach-Object { [string]$_ }) -join ' ').Trim() }
            } catch {
                $r.Result = 'error'; $r.Message = $_.Exception.Message; $r.Reboot = $false
            } finally {
                $r.Undo = @($global:SdUndoSink)
                $global:SdUndoSink = $null
            }
            $r.Changes = @($log)
        }
        [void]$results.Add($r)
    }
    if ($null -ne $Status) { $Status['Index'] = $list.Count; $Status['Text'] = '' }
    return @($results)
}

function Save-SdRepairLog {
    # Dziennik napraw obok raportów: co zrobiono, z jakim wynikiem i jakie wartości zmieniono (poprzednia -> nowa).
    param([Parameter(Mandatory = $true)]$Results, $Meta = @{}, [Parameter(Mandatory = $true)][string]$OutDir)
    $ticket = ''; $tech = ''
    if ($Meta) { $ticket = [string]$Meta['Ticket']; $tech = [string]$Meta['Technician'] }
    $base = Join-NonEmpty @($ticket, $env:COMPUTERNAME, (Get-Date).ToString('yyyyMMdd-HHmm')) '_'
    $base = ($base -replace '[\\/:*?"<>|\s]+', '_') + '_naprawy.txt'
    $lines = @(('DZIENNIK NAPRAW - SerwisDiag ' + $global:SdVersion), ('Data: ' + (Format-Dt (Get-Date))), ('Komputer: ' + $env:COMPUTERNAME))
    if ($ticket) { $lines += 'Zlecenie: ' + $ticket }
    if ($tech) { $lines += 'Technik: ' + $tech }
    $lines += ''
    $labels = @{ ok = 'OK'; warn = 'UWAGA'; error = 'BŁĄD'; skip = 'POMINIĘTO' }
    foreach ($r in @($Results)) {
        $lines += ('[{0}] {1}{2}' -f $labels[[string]$r.Result], $r.Title, $(if ($r.Message) { ' - ' + $r.Message } else { '' }))
        foreach ($ch in @($r.Changes)) { $lines += ('    zmiana: ' + $ch) }
    }
    if (@($Results | Where-Object { $_.Reboot }).Count -gt 0) { $lines += ''; $lines += 'Część napraw zadziała po ponownym uruchomieniu komputera.' }
    $lines += ''
    $lines += 'Zmiany ustawień (rejestr, usługi, zapora) cofa program: Więcej > Cofnij naprawy z dziennika (plik .json obok tego dziennika).'
    $lines += 'Operacji takich jak DISM, SFC, czyszczenie plików czy instalacja sterowników program nie cofa - służy do tego punkt przywracania utworzony przed naprawami.'
    if (-not (Test-Path -LiteralPath $OutDir)) { [void](New-Item -ItemType Directory -Path $OutDir -Force) }
    $path = Join-Path $OutDir $base
    [System.IO.File]::WriteAllText($path, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    # wersja do odczytu przez program (cofanie zmian)
    $json = [ordered]@{
        tool = 'SerwisDiag'; version = $global:SdVersion; kind = 'repair-log'; created = (Get-Date).ToString('s'); computer = $env:COMPUTERNAME; ticket = $ticket
        results = @(@($Results) | ForEach-Object {
                [ordered]@{
                    fixId = [string]$_.FixId; title = [string]$_.Title; result = [string]$_.Result; message = [string]$_.Message
                    undo = $(if ($_.PSObject.Properties['Undo']) { @($_.Undo | Where-Object { $null -ne $_ }) } else { @() })
                }
            })
    }
    [System.IO.File]::WriteAllText([System.IO.Path]::ChangeExtension($path, '.json'), (ConvertTo-Json -InputObject $json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Get-SdRepairWorkText {
    # Opis wykonanych napraw do raportu „przed / po” (bez nazw „aktywatorów” - te w wersji neutralnej).
    param($Results)
    $done = @($Results | Where-Object { $_.Result -eq 'ok' -or $_.Result -eq 'warn' })
    if ($done.Count -eq 0) { return '' }
    $lines = @('Naprawy wykonane programem SerwisDiag:')
    foreach ($r in $done) { $lines += ('- ' + $(if ($r.CustomerTitle) { $r.CustomerTitle } else { $r.Title })) }
    return ($lines -join "`r`n")
}

# ---------------------------------------------------------------- cofanie napraw (z dziennika JSON)

function ConvertTo-SdRegTyped {
    # Wartość z dziennika JSON (liczby jako Int64, bajty jako tablica liczb) -> typ wymagany przez rejestr.
    # Tablice zwracamy przecinkiem: inaczej PowerShell rozwinąłby byte[] w pojedyncze bajty (Object[]).
    param($Value, [string]$Kind)
    if ($null -eq $Value) { return $null }
    switch ($Kind) {
        'Binary' { return , ([byte[]]@(@($Value) | ForEach-Object { [byte]$_ })) }
        'MultiString' { return , ([string[]]@(@($Value) | ForEach-Object { [string]$_ })) }
        'DWord' {
            $v = [int64]$Value
            if ($v -gt [int32]::MaxValue) { return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$v), 0) }
            return [int32]$v
        }
        'QWord' { return [int64]$Value }
        default { return [string]$Value }
    }
}

function Get-SdUndoText {
    # Opis zmiany do cofnięcia, zrozumiały dla technika.
    param($Rec)
    switch ([string]$Rec.Kind) {
        'reg' {
            $old = $(if ([bool]$Rec.Existed) { Format-SdLogValue (ConvertTo-SdRegTyped $Rec.Old ([string]$Rec.OldKind)) } else { '(brak - wartość zostanie usunięta)' })
            return ('Rejestr {0} [{1}]: przywróć {2}' -f $Rec.Path, $Rec.Name, $old)
        }
        'svc' { return ('Usługa {0}: przywróć typ uruchamiania {1}' -f $Rec.Name, $Rec.Old) }
        'firewall' { return ('Zapora Windows: wyłącz ponownie w profilach {0}' -f (@($Rec.Profiles) -join ', ')) }
        'smb1' { return 'Serwer SMB1: włącz ponownie (stare urządzenia sieciowe)' }
        default { return ('Nieznana zmiana: ' + [string]$Rec.Kind) }
    }
}

function Read-SdRepairJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    $o = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not $o -or -not $o.PSObject.Properties['kind'] -or [string]$o.kind -ne 'repair-log') { throw 'To nie jest dziennik napraw programu SerwisDiag (plik *_naprawy.json).' }
    return $o
}

function Find-SdRepairJson {
    # Dzienniki napraw tego komputera w folderze raportów, od najnowszego.
    param([string]$Dir, [string]$ComputerName = $env:COMPUTERNAME)
    $out = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter '*_naprawy.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try { $o = Read-SdRepairJson $f.FullName } catch { continue }
        if ([string]$o.computer -eq $ComputerName) { $out += $f.FullName }
    }
    return $out
}

function Get-SdUndoItems {
    # Zmiany do cofnięcia z dziennika - w odwrotnej kolejności niż je wprowadzano.
    param($RepairLog)
    $items = @()
    foreach ($res in @($RepairLog.results)) {
        foreach ($u in @($res.undo)) {
            if ($null -eq $u -or -not $u.PSObject.Properties['Kind']) { continue }
            $items += [pscustomobject]@{ FixId = [string]$res.fixId; FixTitle = [string]$res.title; Record = $u; Text = (Get-SdUndoText $u) }
        }
    }
    if ($items.Count -gt 1) { $items = $items[($items.Count - 1)..0] }
    return $items
}

function Get-SdNotUndoable {
    # Wykonane naprawy bez zmian ustawień do cofnięcia (DISM, SFC, czyszczenie, sterowniki...) - do informacji.
    param($RepairLog)
    return @(@($RepairLog.results) | Where-Object { ($_.result -eq 'ok' -or $_.result -eq 'warn') -and @(@($_.undo) | Where-Object { $null -ne $_ }).Count -eq 0 } | ForEach-Object { [string]$_.title })
}

function Invoke-SdUndoRecord {
    # Cofa jedną zmianę. Gdy stan zmienił się po naprawie (ktoś zmienił ustawienie ponownie), zmianę pomija.
    param($Rec)
    $res = { param($r, $m) [pscustomobject]@{ Result = $r; Message = $m } }
    switch ([string]$Rec.Kind) {
        'reg' {
            $cur = Get-SdRegRaw $Rec.Path $Rec.Name
            $deleted = [bool]$Rec.Deleted
            $expected = $(if ($deleted) { $null } else { ConvertTo-SdRegTyped $Rec.New ([string]$Rec.NewKind) })
            if ($cur.Exists -eq $deleted -or (-not $deleted -and (Format-SdLogValue $cur.Value) -ne (Format-SdLogValue $expected))) {
                return (& $res 'skip' ('wartość zmieniła się po naprawie (obecnie: ' + $(if ($cur.Exists) { Format-SdLogValue $cur.Value } else { 'brak' }) + ') - pominięto'))
            }
            if ([bool]$Rec.Existed) {
                $old = ConvertTo-SdRegTyped $Rec.Old ([string]$Rec.OldKind)
                if (-not (Test-Path -LiteralPath $Rec.Path)) { [void](New-Item -Path $Rec.Path -Force -ErrorAction Stop) }
                [void](New-ItemProperty -LiteralPath $Rec.Path -Name $Rec.Name -Value $old -PropertyType ([string]$Rec.OldKind) -Force -ErrorAction Stop)
                return (& $res 'ok' ('przywrócono: ' + (Format-SdLogValue $old)))
            }
            Remove-ItemProperty -LiteralPath $Rec.Path -Name $Rec.Name -Force -ErrorAction Stop
            return (& $res 'ok' 'usunięto wartość dodaną przez naprawę')
        }
        'svc' {
            $toParam = @{ Auto = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled' }
            $toMode = @{ Automatic = 'Auto'; Manual = 'Manual'; Disabled = 'Disabled' }
            $old = [string]$Rec.Old
            if (-not $toParam.ContainsKey($old)) { return (& $res 'skip' ('nieznany poprzedni typ uruchamiania: ' + $old)) }
            $svc = Get-Cim Win32_Service -Filter ("Name='{0}'" -f $Rec.Name) | Select-Object -First 1
            if (-not $svc) { return (& $res 'error' 'usługa nie istnieje') }
            if ([string]$svc.StartMode -ne [string]$toMode[[string]$Rec.New]) { return (& $res 'skip' ('typ uruchamiania zmienił się po naprawie (obecnie: ' + $svc.StartMode + ') - pominięto')) }
            Set-Service -Name $Rec.Name -StartupType $toParam[$old] -ErrorAction Stop
            return (& $res 'ok' ('typ uruchamiania: ' + $old))
        }
        'firewall' {
            $names = @($Rec.Profiles | ForEach-Object { [string]$_ })
            Set-NetFirewallProfile -Profile $names -Enabled False -ErrorAction Stop
            return (& $res 'ok' ('zapora wyłączona w profilach: ' + ($names -join ', ')))
        }
        'smb1' {
            Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -Confirm:$false -ErrorAction Stop
            return (& $res 'ok' 'serwer SMB1 włączony')
        }
    }
    return (& $res 'skip' ('nieznany rodzaj zmiany: ' + [string]$Rec.Kind))
}

function Invoke-SdUndo {
    # Cofa wskazane zmiany (pozycje z Get-SdUndoItems) i zwraca wynik każdej.
    param($Items)
    $out = @()
    foreach ($it in @($Items)) {
        $r = $null
        try { $r = Invoke-SdUndoRecord $it.Record } catch { $r = [pscustomobject]@{ Result = 'error'; Message = $_.Exception.Message } }
        $out += [pscustomobject]@{ FixTitle = $it.FixTitle; Text = $it.Text; Result = $r.Result; Message = $r.Message }
    }
    return $out
}

function Save-SdUndoLog {
    # Dziennik cofnięcia obok dziennika napraw: <dziennik>_cofniecie.txt.
    param([Parameter(Mandatory = $true)]$Results, [Parameter(Mandatory = $true)][string]$RepairJsonPath)
    $labels = @{ ok = 'OK'; skip = 'POMINIĘTO'; error = 'BŁĄD' }
    $lines = @(('COFNIĘCIE NAPRAW - SerwisDiag ' + $global:SdVersion), ('Data: ' + (Format-Dt (Get-Date))), ('Komputer: ' + $env:COMPUTERNAME), ('Dziennik napraw: ' + $RepairJsonPath), '')
    foreach ($r in @($Results)) { $lines += ('[{0}] {1}: {2}{3}' -f $labels[[string]$r.Result], $r.FixTitle, $r.Text, $(if ($r.Message) { ' - ' + $r.Message } else { '' })) }
    $suffix = '_cofniecie_' + (Get-Date).ToString('yyyyMMdd-HHmm') + '.txt'
    $path = $(if ($RepairJsonPath -match '_naprawy\.json$') { $RepairJsonPath -replace '_naprawy\.json$', $suffix } else { $RepairJsonPath -replace '\.json$', $suffix })
    [System.IO.File]::WriteAllText($path, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    return $path
}
