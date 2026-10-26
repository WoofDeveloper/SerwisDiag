# SerwisDiag - monitorowanie w tle: ikona przy zegarze, co jakiś czas lekki zestaw testów i powiadomienie o nowych
# problemach. Tylko w wersji zainstalowanej: autostart przy logowaniu (zadanie Harmonogramu dla wszystkich użytkowników
# albo wpis Run bieżącego użytkownika). Nowy problem: nie było go przy poprzednim sprawdzeniu, pogorszył się
# (ostrzeżenie -> krytyczny) albo to wynik z historii zdarzeń z nowym zdarzeniem. Stan: %LOCALAPPDATA%\SerwisDiag\monitor.json.

$global:SdMonitorChecks = @('st.disks', 'st.volumes', 'ev.crash', 'ev.hardware', 'dr.problem', 'se.av', 'se.firewall', 'up.history')
$global:SdMonitorIntervals = @(60, 240, 1440)   # minuty: co godzinę, co 4 godziny, raz na dobę
$global:SdMonitorFirstDelaySec = 120            # pierwsze sprawdzenie chwilę po logowaniu, żeby nie spowalniać startu
$global:SdMonitorTaskName = 'SerwisDiag\Monitor'
$global:SdMonitorRunValue = 'SerwisDiag Monitor'
$global:SdMonitorMutexName = 'Local\SerwisDiag.Monitor'
$global:SdMonitorStopName = 'Local\SerwisDiag.Monitor.Stop'

# ---------------------------------------------------------------- sprawdzanie i porównanie z poprzednim stanem

function Get-SdMonitorKey {
    param($Finding)
    return ('{0}|{1}' -f $Finding.CheckId, $Finding.Title).ToLower()
}

function Invoke-SdMonitorScan {
    # Lekki zestaw testów monitorowania (kilka-kilkanaście sekund). Wynik: wyniki testów.
    param([string]$Root)
    $global:SD = New-SdContext -Root $Root -Level Quick -Only $global:SdMonitorChecks
    Invoke-SdScan
    return @($global:SD.Findings.ToArray())
}

function Get-SdMonitorChanges {
    # Previous: problemy z poprzedniego sprawdzenia (plik stanu). New: problemy nowe, pogorszone (ostrzeżenie -> krytyczny)
    # i z historii zdarzeń z nowym zdarzeniem po poprzednim sprawdzeniu; Problems: bieżące problemy; Resolved: tytuły ustąpionych.
    param($Previous, $Findings, $LastCheck = $null)
    $prev = @{}
    foreach ($p in @($Previous)) { if ($p) { $prev[[string]$p.key] = $p } }
    $problems = @($Findings | Where-Object { $_ -and ($_.Status -eq 'warn' -or $_.Status -eq 'crit') })
    $new = @()
    foreach ($f in $problems) {
        $p = $prev[(Get-SdMonitorKey $f)]
        $le = Get-SdFindingLastEvent $f
        if (-not $p) { $new += $f }
        elseif ([string]$p.status -eq 'warn' -and $f.Status -eq 'crit') { $new += $f }
        elseif ($le -and $LastCheck -and $le -gt $LastCheck) { $new += $f }
    }
    $nowKeys = @($problems | ForEach-Object { Get-SdMonitorKey $_ })
    $resolved = @($prev.GetEnumerator() | Where-Object { $nowKeys -notcontains $_.Key } | ForEach-Object { [string]$_.Value.title })
    return [pscustomobject]@{ New = $new; Problems = $problems; Resolved = $resolved }
}

function Get-SdMonitorLevel {
    # Kolor ikony: crit, gdy jest problem krytyczny, warn przy samych ostrzeżeniach, ok bez problemów.
    param($Problems)
    $st = @(@($Problems) | Where-Object { $_ } | ForEach-Object { [string]$_.Status })
    if ($st -contains 'crit') { return 'crit' }
    if ($st.Count -gt 0) { return 'warn' }
    return 'ok'
}

function Get-SdMonitorStatePath {
    if ($env:SERWISDIAG_MONITOR_STATE) { return $env:SERWISDIAG_MONITOR_STATE }   # testy: osobny plik stanu
    return (Join-Path (Get-SdUserDataDir) 'monitor.json')
}

function Read-SdMonitorState {
    # { LastCheck; Problems (key, title, status, value, lastEvent); Interval (minuty) } albo $null przed pierwszym sprawdzeniem.
    param([string]$Path = '')
    if (-not $Path) { $Path = Get-SdMonitorStatePath }
    $o = Read-SdJsonFile $Path
    if (-not $o) { return $null }
    $iv = 60
    if ($o.PSObject.Properties['interval'] -and [int]$o.interval -gt 0) { $iv = [int]$o.interval }
    $pr = @()
    if ($o.PSObject.Properties['problems']) { $pr = @($o.problems | Where-Object { $_ }) }
    return [pscustomobject]@{ LastCheck = (ConvertFrom-SdJsonDate $o.lastCheck); Problems = $pr; Interval = $iv }
}

function Save-SdMonitorState {
    # Zapis stanu po sprawdzeniu. Interval = 0: bez zmiany zapisanej częstotliwości.
    param([string]$Path = '', $Problems = @(), $When = $null, [int]$Interval = 0)
    if (-not $Path) { $Path = Get-SdMonitorStatePath }
    $old = Read-SdMonitorState $Path
    if ($Interval -le 0) { $Interval = $(if ($old) { $old.Interval } else { 60 }) }
    if ($null -eq $When -and $old) { $When = $old.LastCheck }
    $list = @(@($Problems) | Where-Object { $_ } | ForEach-Object {
            $le = Get-SdFindingLastEvent $_
            if (-not $_.PSObject.Properties['CheckId']) { $_ }   # wpis ze starego stanu (zmiana samej częstotliwości)
            else { [ordered]@{ key = (Get-SdMonitorKey $_); title = [string]$_.Title; status = [string]$_.Status; value = [string]$_.Value; advice = [string]$_.Advice; lastEvent = $(if ($le) { $le.ToString('s') } else { $null }) } }
        })
    Write-SdJsonFile $Path ([ordered]@{ lastCheck = $(if ($When) { ([datetime]$When).ToString('s') } else { $null }); interval = $Interval; problems = $list })
}

function Set-SdMonitorInterval {
    # Zmiana częstotliwości sprawdzania (menu ikony, ustawienia programu) bez utraty stanu.
    param([int]$Minutes, [string]$Path = '')
    $st = Read-SdMonitorState $Path
    Save-SdMonitorState -Path $Path -Problems $(if ($st) { @($st.Problems) } else { @() }) -Interval $Minutes
}

function Get-SdMonitorIntervalText {
    param([int]$Minutes)
    if ($Minutes -ge 1440) { return 'raz na dobę' }
    if ($Minutes -ge 60) { return $(if ($Minutes -eq 60) { 'co godzinę' } else { 'co ' + (Format-Count ($Minutes / 60) 'godzinę' 'godziny' 'godzin') }) }
    return 'co ' + (Format-Count $Minutes 'minutę' 'minuty' 'minut')
}

# ---------------------------------------------------------------- autostart, uruchamianie i zatrzymywanie

function Get-SdMonitorLauncher {
    # Polecenie uruchamiające monitor: SerwisDiagMonitor.exe (bez okna konsoli i bez UAC), a bez niego PowerShell.
    param([string]$Root)
    $exe = Join-Path $Root 'SerwisDiagMonitor.exe'
    if (Test-Path -LiteralPath $exe -PathType Leaf) { return [pscustomobject]@{ File = $exe; Arguments = '' } }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    return [pscustomobject]@{ File = $ps; Arguments = ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ' + (Format-SdCmdArg (Join-Path $Root 'SerwisDiag.ps1')) + ' -Monitor') }
}

function New-SdMonitorTaskXml {
    # Zadanie Harmonogramu dla wszystkich użytkowników: start przy logowaniu każdego z nich, w jego sesji, z najwyższymi
    # dostępnymi uprawnieniami (administrator: pełne testy bez okna UAC; zwykły użytkownik: bez uprawnień).
    param([string]$Command, [string]$Arguments = '')
    $E = { param($t) [System.Security.SecurityElement]::Escape([string]$t) }
    $args1 = $(if ($Arguments) { '<Arguments>' + (& $E $Arguments) + '</Arguments>' } else { '' })
    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Author>SerwisDiag</Author><Description>SerwisDiag - monitorowanie systemu w tle (ikona przy zegarze).</Description></RegistrationInfo>
  <Triggers><LogonTrigger><Enabled>true</Enabled><Delay>PT30S</Delay></LogonTrigger></Triggers>
  <Principals><Principal id="Author"><GroupId>S-1-5-32-545</GroupId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author"><Exec><Command>$(& $E $Command)</Command>$args1</Exec></Actions>
</Task>
"@
}

function Get-SdSchtasksPath { return (Join-Path $env:SystemRoot 'System32\schtasks.exe') }

function Register-SdMonitorAutostart {
    # Autostart przy logowaniu: w instalacji dla wszystkich (z uprawnieniami administratora) zadanie Harmonogramu,
    # w pozostałych przypadkach wpis Run bieżącego użytkownika. Wynik: 'task' albo 'run'; błąd = wyjątek.
    param([Parameter(Mandatory = $true)][string]$Root)
    $l = Get-SdMonitorLauncher $Root
    if ((Get-SdInstallMode $Root) -eq 'allusers' -and (Test-SdAdmin)) {
        $xml = Join-Path ([System.IO.Path]::GetTempPath()) ('SerwisDiag-monitor-' + [guid]::NewGuid().ToString('N') + '.xml')
        [System.IO.File]::WriteAllText($xml, (New-SdMonitorTaskXml -Command $l.File -Arguments $l.Arguments), [System.Text.Encoding]::Unicode)
        try {
            $r = Invoke-Native -File (Get-SdSchtasksPath) -Arguments ('/Create /TN "{0}" /XML "{1}" /F' -f $global:SdMonitorTaskName, $xml) -TimeoutSec 60
            if ($r.ExitCode -ne 0) { throw ('Nie utworzono zadania Harmonogramu: ' + (Get-SdLastLine ($r.StdOut + $r.StdErr))) }
        } finally { Remove-Item -LiteralPath $xml -Force -ErrorAction SilentlyContinue }
        # wpis Run z wcześniejszej instalacji uruchamiałby drugi monitor
        Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $global:SdMonitorRunValue -ErrorAction SilentlyContinue
        return 'task'
    }
    $cmd = (Format-SdCmdArg $l.File) + $(if ($l.Arguments) { ' ' + $l.Arguments } else { '' })
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $global:SdMonitorRunValue -Value $cmd -ErrorAction Stop
    return 'run'
}

function Get-SdMonitorAutostart {
    # 'task' | 'run' | '' - jak monitor startuje przy logowaniu.
    $q = Invoke-Native -File (Get-SdSchtasksPath) -Arguments ('/Query /TN "{0}"' -f $global:SdMonitorTaskName) -TimeoutSec 30
    if ($q.ExitCode -eq 0) { return 'task' }
    if (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $global:SdMonitorRunValue -ErrorAction SilentlyContinue) { return 'run' }
    return ''
}

function Unregister-SdMonitorAutostart {
    # Usuwa autostart monitora (zadanie Harmonogramu wymaga uprawnień administratora). Wynik: lista usuniętych wpisów.
    $out = @()
    if ((Invoke-Native -File (Get-SdSchtasksPath) -Arguments ('/Query /TN "{0}"' -f $global:SdMonitorTaskName) -TimeoutSec 30).ExitCode -eq 0) {
        $d = Invoke-Native -File (Get-SdSchtasksPath) -Arguments ('/Delete /TN "{0}" /F' -f $global:SdMonitorTaskName) -TimeoutSec 30
        $out += $(if ($d.ExitCode -eq 0) { 'task' } else { 'task: brak uprawnień' })
    }
    if (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $global:SdMonitorRunValue -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $global:SdMonitorRunValue -ErrorAction SilentlyContinue
        $out += 'run'
    }
    return $out
}

function Start-SdMonitorProcess {
    param([Parameter(Mandatory = $true)][string]$Root)
    $l = Get-SdMonitorLauncher $Root
    if ($l.Arguments) { [void](Start-Process -FilePath $l.File -ArgumentList $l.Arguments -WindowStyle Hidden) }
    else { [void](Start-Process -FilePath $l.File) }
}

function Stop-SdMonitorProcess {
    # Prosi monitor działający w tej sesji o zakończenie (zdarzenie nazwane). -Wait: czeka (do 15 s), aż zwolni blokadę,
    # żeby odinstalowanie albo aktualizacja nie trafiły na działający proces. Wynik: $true, gdy jakiś monitor działał.
    param([switch]$Wait)
    $h = $null
    try { $h = [System.Threading.EventWaitHandle]::OpenExisting($global:SdMonitorStopName) } catch { return $false }
    try { [void]$h.Set() } finally { $h.Dispose() }
    if ($Wait) {
        $mx = $null
        try {
            $mx = [System.Threading.Mutex]::OpenExisting($global:SdMonitorMutexName)
            $got = $false
            try { $got = $mx.WaitOne(15000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
            if ($got) { $mx.ReleaseMutex() }
        } catch [System.Threading.WaitHandleCannotBeOpenedException] {
            # monitor już zakończył pracę
        } catch { Start-Sleep -Seconds 3 } finally { if ($mx) { $mx.Dispose() } }
    }
    return $true
}

function Write-SdMonitorLog {
    # Dziennik monitora (błędy, aktualizacje) w %LOCALAPPDATA%\SerwisDiag\monitor.log, najwyżej ok. 200 KB.
    param([string]$Message)
    try {
        $p = Join-Path (Get-SdUserDataDir) 'monitor.log'
        if ((Test-Path -LiteralPath $p) -and (Get-Item -LiteralPath $p).Length -gt 200KB) { Remove-Item -LiteralPath $p -Force }
        [System.IO.File]::AppendAllText($p, ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' ' + $Message + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

# ---------------------------------------------------------------- ikona przy zegarze i okno wyników

function New-SdMonitorIcons {
    # Ikony w zasobniku: ikona programu z kropką w kolorze stanu (bez kropki = wszystko w porządku).
    param([string]$Root)
    $size = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
    if ($size -lt 16) { $size = 16 }
    $ico = $null
    $p = Join-Path $Root 'assets\app.ico'
    try { if (Test-Path -LiteralPath $p) { $ico = New-Object System.Drawing.Icon($p, $size, $size) } } catch { }
    $colors = @{ ok = ''; busy = '#2E90FA'; warn = '#F79009'; crit = '#D92D20' }
    $out = @{}
    foreach ($st in 'ok', 'busy', 'warn', 'crit') {
        $bmp = New-Object System.Drawing.Bitmap($size, $size)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            if ($ico) { $g.DrawIcon($ico, (New-Object System.Drawing.Rectangle(0, 0, $size, $size))) }
            else { $g.FillEllipse([System.Drawing.Brushes]::SteelBlue, 1, 1, ($size - 2), ($size - 2)) }
            if ($colors[$st]) {
                $d = [int][math]::Round($size * 0.55)
                $x = $size - $d
                $g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($colors[$st]))), $x, $x, ($d - 1), ($d - 1))
                $g.DrawEllipse((New-Object System.Drawing.Pen([System.Drawing.Color]::White, [single][math]::Max($size / 16.0, 1.0))), $x, $x, ($d - 1), ($d - 1))
            }
        } finally { $g.Dispose() }
        $out[$st] = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    }
    return $out
}

$global:SdMonitorXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SerwisDiag - monitorowanie systemu" Width="620" Height="520" MinWidth="460" MinHeight="320" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9" ShowInTaskbar="True">
  <Grid Margin="20">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock x:Name="MTitle" FontSize="18" FontWeight="SemiBold" Foreground="#101828"/>
    <TextBlock x:Name="MStatus" Grid.Row="1" Margin="0,4,0,12" Foreground="#475467" TextWrapping="Wrap"/>
    <Border Grid.Row="2" Background="White" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="8">
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="14,10"><StackPanel x:Name="MList"/></ScrollViewer>
    </Border>
    <DockPanel Grid.Row="3" Margin="0,14,0,0">
      <Button x:Name="MClose" DockPanel.Dock="Right" Content="Zamknij" Width="100" Height="32" IsCancel="True"/>
      <Button x:Name="MOpen" DockPanel.Dock="Right" Content="Otwórz SerwisDiag" Padding="14,0" Height="32" Margin="0,0,8,0"/>
      <Button x:Name="MCheck" DockPanel.Dock="Left" Content="Sprawdź teraz" Padding="14,0" Height="32" HorizontalAlignment="Left"/>
    </DockPanel>
  </Grid>
</Window>
'@

function Add-SdMonitorText {
    # Akapit w oknie wyników: fragmenty { T = tekst; B = pogrubienie; C = kolor; NL = nowy wiersz przed }.
    param($Panel, [object[]]$Parts, [string]$Margin = '0,0,0,10')
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.TextWrapping = 'Wrap'
    $tb.Margin = (New-Object System.Windows.ThicknessConverter).ConvertFromInvariantString($Margin)
    foreach ($p in $Parts) {
        if ($p.NL) { [void]$tb.Inlines.Add((New-Object System.Windows.Documents.LineBreak)) }
        $r = New-Object System.Windows.Documents.Run([string]$p.T)
        if ($p.B) { $r.FontWeight = [System.Windows.FontWeights]::SemiBold }
        if ($p.C) { $r.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($p.C) }
        [void]$tb.Inlines.Add($r)
    }
    [void]$Panel.Children.Add($tb)
}

function Update-SdMonitorWindow {
    $m = $global:SdMon
    $w = $m.Window
    if (-not $w) { return }
    $n = $m.WinN
    $cnt = @($m.Problems).Count
    $n.MTitle.Text = $(if ($m.Busy -and -not $m.LastCheck) { 'Trwa pierwsze sprawdzanie...' } elseif ($cnt -eq 0) { 'Nie wykryto problemów' } else { 'Wykryto ' + (Format-Count $cnt 'problem' 'problemy' 'problemów') })
    $st = @()
    if ($m.LastCheck) { $st += ('Ostatnie sprawdzenie: ' + (Format-Dt $m.LastCheck)) }
    if ($m.Busy) { $st += 'trwa sprawdzanie...' } else { $st += ('następne: ' + (Format-Dt $m.NextCheck) + ' (' + (Get-SdMonitorIntervalText $m.Interval) + ')') }
    if (-not $m.IsAdmin) { $st += 'bez uprawnień administratora - część testów (np. SMART dysków SATA) pominięto' }
    $n.MStatus.Text = ($st -join ' · ')
    $n.MList.Children.Clear()
    if ($cnt -eq 0) {
        Add-SdMonitorText $n.MList @(@{ T = $(if ($m.LastCheck) { 'Sprawdzane: dyski (stan i miejsce), awarie i nieoczekiwane restarty, błędy sprzętu, urządzenia, antywirus, zapora i Windows Update.' } else { 'Wyniki pojawią się po pierwszym sprawdzeniu.' }); C = '#475467' })
        return
    }
    foreach ($f in @($m.Problems | Sort-Object @{ Expression = { if ($_.Status -eq 'crit') { 0 } else { 1 } } })) {
        $lab = $(if ($f.Status -eq 'crit') { @('KRYTYCZNE', '#B42318') } else { @('UWAGA', '#B54708') })
        $parts = @(@{ T = '[' + $lab[0] + '] '; B = $true; C = $lab[1] }, @{ T = [string]$f.Title; B = $true; C = '#101828' })
        if ($f.Value) { $parts += @{ T = [string]$f.Value; C = '#344054'; NL = $true } }
        if ($f.Advice) { $parts += @{ T = 'Zalecenie: ' + [string]$f.Advice; C = '#667085'; NL = $true } }
        Add-SdMonitorText $n.MList $parts
    }
}

function Show-SdMonitorWindow {
    $m = $global:SdMon
    if ($m.Window) { $m.Window.Activate(); return }
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$global:SdMonitorXaml)))
    $iconPath = Join-Path $m.Root 'assets\app.ico'
    if (Test-Path -LiteralPath $iconPath) { try { $w.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($iconPath))) } catch { } }
    $n = @{}
    foreach ($name in 'MTitle', 'MStatus', 'MList', 'MCheck', 'MOpen', 'MClose') { $n[$name] = $w.FindName($name) }
    $m.Window = $w; $m.WinN = $n
    $n.MCheck.Add_Click({ if (-not $global:SdMon.Busy) { Start-SdMonitorCheck; Update-SdMonitorWindow } })
    $n.MOpen.Add_Click({ Open-SdMonitorProgram })
    $n.MClose.Add_Click({ $global:SdMon.Window.Close() })
    $w.Add_Closed({ $global:SdMon.Window = $null; $global:SdMon.WinN = $null })
    Update-SdMonitorWindow
    $w.Show()
    [void]$w.Activate()
}

function Open-SdMonitorProgram {
    # Pełny program (SerwisDiag.exe prosi o uprawnienia administratora; z monitora z uprawnieniami - bez pytania).
    $m = $global:SdMon
    $exe = Join-Path $m.Root 'SerwisDiag.exe'
    try {
        if (Test-Path -LiteralPath $exe) { [void](Start-Process -FilePath $exe) }
        else { [void](Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ' + (Format-SdCmdArg (Join-Path $m.Root 'SerwisDiag.ps1')) + ' -Elevate') -WindowStyle Hidden) }
    } catch { Write-SdMonitorLog ('Otwieranie programu: ' + $_.Exception.Message) }
}

function Set-SdMonitorTip {
    $m = $global:SdMon
    $cnt = @($m.Problems).Count
    $t = $(if ($m.Busy) { 'SerwisDiag: sprawdzanie...' } elseif (-not $m.LastCheck) { 'SerwisDiag: monitorowanie' } elseif ($cnt -eq 0) { 'SerwisDiag: brak problemów' } else { 'SerwisDiag: ' + (Format-Count $cnt 'problem' 'problemy' 'problemów') })
    if ($m.LastCheck -and -not $m.Busy) { $t += ' (' + ([datetime]$m.LastCheck).ToString('HH:mm') + ')' }
    $m.Tray.Text = Limit-Text $t 63   # NotifyIcon.Text: najwyżej 63 znaki
}

function Show-SdMonitorBalloon {
    param([string]$Title, [string]$Text, [string]$Kind = 'problems', [string]$Icon = 'Warning')
    $m = $global:SdMon
    $m.BalloonKind = $Kind
    $m.Tray.ShowBalloonTip(15000, (Limit-Text $Title 63), (Limit-Text $Text 250), [System.Windows.Forms.ToolTipIcon]$Icon)
    $m.LastBalloon = $Title + ': ' + $Text
}

$global:SdMonitorScript = @'
param($Root, $CheckUpdate)
if (-not $global:SdMonLoaded) { $SdRoot = $Root; . (Join-Path $Root 'lib\Load.ps1'); $global:SdMonLoaded = $true }
$f = @(Invoke-SdMonitorScan -Root $Root)
$rel = $null
if ($CheckUpdate) { try { $rel = Get-SdLatestRelease; Save-SdUpdateCheckState $rel } catch { } }
[pscustomobject]@{ Findings = $f; Release = $rel; IsAdmin = (Test-SdAdmin) }
'@

function Start-SdMonitorCheck {
    $m = $global:SdMon
    if ($m.Busy) { return }
    $st = Read-SdMonitorState $m.StatePath
    if ($st) { $m.Interval = $st.Interval }
    $ps = [powershell]::Create()
    $ps.Runspace = $m.Rs
    [void]$ps.AddScript($global:SdMonitorScript)
    [void]$ps.AddParameter('Root', $m.Root)
    [void]$ps.AddParameter('CheckUpdate', [bool](Test-SdUpdateCheckDue -Root $m.Root -Settings $m.Settings))
    $m.Ps = $ps
    $m.Busy = $true
    $m.Async = $ps.BeginInvoke()
    $m.Tray.Icon = $m.Icons['busy']
    Set-SdMonitorTip
}

function Complete-SdMonitorCheck {
    $m = $global:SdMon
    $out = $null
    try { $out = @($m.Ps.EndInvoke($m.Async)) | Select-Object -Last 1 } catch { Write-SdMonitorLog ('Sprawdzanie: ' + $_.Exception.Message) }
    try { foreach ($e in $m.Ps.Streams.Error) { Write-SdMonitorLog ('Sprawdzanie: ' + [string]$e) } } catch { }
    try { $m.Ps.Dispose() } catch { }
    $m.Ps = $null; $m.Async = $null; $m.Busy = $false
    $now = Get-Date
    $st = Read-SdMonitorState $m.StatePath
    if ($st) { $m.Interval = $st.Interval }
    $m.NextCheck = $now.AddMinutes($m.Interval)
    if (-not $out -or -not $out.PSObject.Properties['Findings']) {
        $m.Tray.Icon = $m.Icons[(Get-SdMonitorLevel $m.Problems)]
        Set-SdMonitorTip
        return
    }
    $baseline = (-not $st -or -not $st.LastCheck)
    $ch = Get-SdMonitorChanges -Previous $(if ($st) { $st.Problems } else { @() }) -Findings $out.Findings -LastCheck $(if ($st) { $st.LastCheck } else { $null })
    try { Save-SdMonitorState -Path $m.StatePath -Problems $ch.Problems -When $now -Interval $m.Interval } catch { Write-SdMonitorLog ('Zapis stanu: ' + $_.Exception.Message) }
    $m.Problems = @($ch.Problems); $m.LastCheck = $now; $m.IsAdmin = [bool]$out.IsAdmin; $m.Checks++
    $m.Tray.Icon = $m.Icons[(Get-SdMonitorLevel $m.Problems)]
    Set-SdMonitorTip
    if ($baseline) {
        if ($m.Problems.Count -gt 0) { Show-SdMonitorBalloon 'SerwisDiag monitoruje system' ('Znane problemy: ' + $m.Problems.Count + ' (' + ((@($m.Problems | Select-Object -First 3 | ForEach-Object { $_.Title })) -join ', ') + '). Kliknij, aby zobaczyć szczegóły.') 'problems' 'Info' }
    } elseif (@($ch.New).Count -gt 0) {
        $first = @($ch.New)[0]
        $title = $(if (@($ch.New).Count -eq 1) { 'SerwisDiag: nowy problem' } else { 'SerwisDiag: nowe problemy (' + @($ch.New).Count + ')' })
        $text = $(if (@($ch.New).Count -eq 1) { [string]$first.Title + ': ' + [string]$first.Value } else { (@($ch.New | ForEach-Object { $_.Title }) -join ', ') })
        Show-SdMonitorBalloon $title ($text + ' Kliknij, aby zobaczyć szczegóły.') 'problems' $(if (@($ch.New | Where-Object { $_.Status -eq 'crit' }).Count) { 'Error' } else { 'Warning' })
    }
    if ($m.Window) { Update-SdMonitorWindow }
    $rel = $out.Release
    if ($rel -and $rel.Ok -and $rel.Newer) {
        $m.UpdateRel = $rel
        $m.MenuUpdate.Text = 'Dostępna wersja ' + $rel.Latest + ' - otwórz SerwisDiag, aby zaktualizować'
        $m.MenuUpdate.Visible = $true
        $us = Read-SdJsonFile (Get-SdUpdateStatePath)
        if (-not ($us -and [string]$us.notified -eq [string]$rel.Latest)) {
            Show-SdMonitorBalloon 'SerwisDiag: dostępna nowa wersja' ('Wersja ' + $rel.Latest + ' (masz ' + $global:SdVersion + '). Kliknij, aby otworzyć program i zaktualizować.') 'update' 'Info'
            try { Save-SdUpdateCheckState $rel -Notified $rel.Latest } catch { }
        }
    }
    if ($m.TestPrefix) { Complete-SdMonitorSelfTest }
}

function Complete-SdMonitorSelfTest {
    # Test automatyczny (SERWISDIAG_MONITOR_TEST=<prefiks>): okno wyników, zrzut okna i ikony, podsumowanie, koniec.
    $m = $global:SdMon
    Show-SdMonitorWindow
    $w = $m.Window
    $w.UpdateLayout()
    [void]$w.Dispatcher.Invoke([Action]{ }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$w.ActualWidth, [int]$w.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($w)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($m.TestPrefix + '-okno.png')
    try { $enc.Save($fs) } finally { $fs.Close() }
    $m.Tray.Icon.ToBitmap().Save($m.TestPrefix + '-ikona.png', [System.Drawing.Imaging.ImageFormat]::Png)
    $lines = @(('problemy: ' + @($m.Problems).Count), ('podpowiedz: ' + $m.Tray.Text), ('powiadomienie: ' + $m.LastBalloon), ('administrator: ' + $m.IsAdmin))
    foreach ($p in $m.Problems) { $lines += ('  ' + $p.Status + ' | ' + $p.Title + ' | ' + $p.Value) }
    [System.IO.File]::WriteAllText($m.TestPrefix + '-wynik.txt', ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    Stop-SdMonitorUi
}

function Stop-SdMonitorUi {
    $m = $global:SdMon
    try { $m.Timer.Stop() } catch { }
    try { if ($m.Window) { $m.Window.Close() } } catch { }
    try { $m.Tray.Visible = $false; $m.Tray.Dispose() } catch { }
    $m.Dispatcher.InvokeShutdown()
}

function Start-SdMonitor {
    # Monitorowanie w tle (tryb -Monitor): ikona przy zegarze i pętla komunikatów do zakończenia (menu, wyłączenie,
    # aktualizacja programu). Jeden monitor na sesję użytkownika.
    param([Parameter(Mandatory = $true)][string]$Root, [hashtable]$Settings = @{})
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing, PresentationFramework, PresentationCore, WindowsBase
    $mutex = New-Object System.Threading.Mutex($false, $global:SdMonitorMutexName)
    $owned = $false
    # po aktualizacji poprzedni monitor kończy pracę chwilę po uruchomieniu nowego
    try { $owned = $mutex.WaitOne(20000) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { $mutex.Dispose(); return }
    $created = $false
    $stop = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $global:SdMonitorStopName, [ref]$created)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
    $rs.Open()
    $statePath = Get-SdMonitorStatePath
    $st = Read-SdMonitorState $statePath
    $m = @{
        Root = $Root; Settings = $Settings; Rs = $rs; Ps = $null; Async = $null; Busy = $false; Stop = $stop
        Problems = @(); LastCheck = $null; Interval = $(if ($st) { $st.Interval } else { 60 }); IsAdmin = (Test-SdAdmin); Checks = 0
        NextCheck = (Get-Date).AddSeconds($global:SdMonitorFirstDelaySec); LastVersionCheck = (Get-Date); StatePath = $statePath
        Window = $null; WinN = $null; UpdateRel = $null; BalloonKind = ''; LastBalloon = ''; TestPrefix = [string]$env:SERWISDIAG_MONITOR_TEST
        Dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher; Icons = (New-SdMonitorIcons $Root)
    }
    # poprzednie problemy od razu w oknie i w kolorze ikony - do czasu pierwszego sprawdzenia w tej sesji
    if ($st -and $st.LastCheck) {
        $m.Problems = @($st.Problems | ForEach-Object { [pscustomobject]@{ CheckId = ''; Title = [string]$_.title; Status = [string]$_.status; Value = [string]$_.value; Advice = [string]$_.advice } })
        $m.LastCheck = $st.LastCheck
    }
    if ($m.TestPrefix) { $m.NextCheck = (Get-Date).AddSeconds(2) }
    $global:SdMon = $m

    $tray = New-Object System.Windows.Forms.NotifyIcon
    $m.Tray = $tray
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $miShow = $menu.Items.Add('Pokaż wyniki monitorowania')
    $miShow.Font = New-Object System.Drawing.Font($miShow.Font, [System.Drawing.FontStyle]::Bold)
    $miCheck = $menu.Items.Add('Sprawdź teraz')
    $miOpen = $menu.Items.Add('Otwórz SerwisDiag')
    $m.MenuUpdate = $menu.Items.Add('Dostępna nowa wersja')
    $m.MenuUpdate.Visible = $false
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $miInt = New-Object System.Windows.Forms.ToolStripMenuItem('Sprawdzaj')
    foreach ($iv in $global:SdMonitorIntervals) {
        $it = New-Object System.Windows.Forms.ToolStripMenuItem((Get-SdMonitorIntervalText $iv))
        $it.Tag = $iv
        $it.Checked = ($iv -eq $m.Interval)
        $it.Add_Click({
                param($s, $e)
                $mm = $global:SdMon
                $mm.Interval = [int]$s.Tag
                foreach ($x in $s.Owner.Items) { $x.Checked = ([int]$x.Tag -eq $mm.Interval) }
                try { Set-SdMonitorInterval -Minutes $mm.Interval -Path $mm.StatePath } catch { Write-SdMonitorLog ('Zapis częstotliwości: ' + $_.Exception.Message) }
                if ($mm.LastCheck -and -not $mm.Busy) { $mm.NextCheck = ([datetime]$mm.LastCheck).AddMinutes($mm.Interval) }
                if ($mm.Window) { Update-SdMonitorWindow }
            })
        [void]$miInt.DropDownItems.Add($it)
    }
    [void]$menu.Items.Add($miInt)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $miExit = $menu.Items.Add('Zakończ (do następnego logowania)')
    $miOff = $menu.Items.Add('Wyłącz monitorowanie')
    $miShow.Add_Click({ Show-SdMonitorWindow })
    $miCheck.Add_Click({ Start-SdMonitorCheck; if ($global:SdMon.Window) { Update-SdMonitorWindow } })
    $miOpen.Add_Click({ Open-SdMonitorProgram })
    $m.MenuUpdate.Add_Click({ Open-SdMonitorProgram })
    $miExit.Add_Click({ Stop-SdMonitorUi })
    $miOff.Add_Click({
            $ans = [System.Windows.MessageBox]::Show('Wyłączyć monitorowanie w tle? Nie uruchomi się też przy następnym logowaniu. Włączysz je ponownie w ustawieniach programu SerwisDiag.', 'SerwisDiag', 'YesNo', 'Question')
            if ([string]$ans -ne 'Yes') { return }
            $u = @(Unregister-SdMonitorAutostart)
            if ($u -contains 'task: brak uprawnień') { [void][System.Windows.MessageBox]::Show('Monitorowanie dla wszystkich użytkowników wyłączysz w ustawieniach programu SerwisDiag (wymaga uprawnień administratora). Teraz monitor zakończy pracę do następnego logowania.', 'SerwisDiag', 'OK', 'Information') }
            Stop-SdMonitorUi
        })
    $tray.ContextMenuStrip = $menu
    $tray.Add_DoubleClick({ Show-SdMonitorWindow })
    $tray.Add_BalloonTipClicked({ if ($global:SdMon.BalloonKind -eq 'update') { Open-SdMonitorProgram } else { Show-SdMonitorWindow } })
    $tray.Icon = $m.Icons[(Get-SdMonitorLevel $m.Problems)]
    Set-SdMonitorTip
    $tray.Visible = $true

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(2)
    $timer.Add_Tick({
            $mm = $global:SdMon
            try {
                if ($mm.Stop.WaitOne(0)) { Stop-SdMonitorUi; return }
                if ($mm.Busy) { if ($mm.Async.IsCompleted) { Complete-SdMonitorCheck }; return }
                $now = Get-Date
                if (($now - $mm.LastVersionCheck).TotalSeconds -ge 60) {
                    $mm.LastVersionCheck = $now
                    if (-not (Test-Path -LiteralPath (Join-Path $mm.Root 'SerwisDiag.ps1'))) { Stop-SdMonitorUi; return }   # program odinstalowany
                    $v = Get-SdVersionOnDisk $mm.Root
                    if ($v -and $v -ne $global:SdVersion) {
                        # po aktualizacji: nowy monitor w nowej wersji (czeka, aż ten zwolni blokadę)
                        Write-SdMonitorLog ('Nowa wersja programu ' + $v + ' - ponowne uruchomienie monitora.')
                        Start-SdMonitorProcess -Root $mm.Root
                        Stop-SdMonitorUi
                        return
                    }
                }
                if ($now -ge $mm.NextCheck) { Start-SdMonitorCheck }
            } catch { Write-SdMonitorLog ('Monitor: ' + $_.Exception.Message) }
        })
    $m.Timer = $timer
    $timer.Start()
    Write-SdMonitorLog ('Start monitora ' + $global:SdVersion + $(if ($m.IsAdmin) { ' (administrator)' } else { '' }))
    try { [System.Windows.Threading.Dispatcher]::Run() }
    finally {
        try { $tray.Visible = $false; $tray.Dispose() } catch { }
        if ($m.Busy -and $m.Ps) { try { [void]$m.Ps.BeginStop($null, $null) } catch { } } else { try { $rs.Dispose() } catch { } }
        $stop.Dispose()
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
}
