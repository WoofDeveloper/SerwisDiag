# SerwisDiag - aktualizacja programu z wydań na GitHubie: sprawdzenie (w wersji zainstalowanej raz na dobę), pobranie
# instalatora, kontrola sumy SHA-256 i numeru wersji w pliku, uruchomienie instalatora w trybie aktualizacji.
# Wersji przenośnej (pendrive, ZIP) program sam nie aktualizuje - pokazuje stronę wydania do pobrania.

$global:SdUpdateCheckHours = 24

function Get-SdUserDataDir {
    # Dane programu bieżącego użytkownika (stan monitorowania, ostatnie sprawdzenie aktualizacji): %LOCALAPPDATA%\SerwisDiag.
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if (-not $base) { $base = [System.IO.Path]::GetTempPath() }
    $d = Join-Path $base 'SerwisDiag'
    if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    return $d
}

function Read-SdJsonFile {
    # Mały plik stanu w JSON; brak albo uszkodzony plik: $null.
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}

function Write-SdJsonFile {
    param([string]$Path, $Object)
    [System.IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Object -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
}

function Get-SdUpdateStatePath { return (Join-Path (Get-SdUserDataDir) 'aktualizacje.json') }

function Test-SdUpdateCheckDue {
    # Czy pora na samoczynne sprawdzenie aktualizacji: wersja zainstalowana, włączone w ustawieniach, znany adres projektu
    # i co najmniej doba od poprzedniej próby (także nieudanej - bez internetu program nie próbuje co chwilę).
    param([string]$Root, [hashtable]$Settings, [string]$StatePath = '', [datetime]$Now = (Get-Date))
    if (-not (Test-SdInstalledCopy $Root) -or -not $Settings.AutoUpdateCheck -or -not (Get-SdGitHubRepo $global:SdProjectUrl)) { return $false }
    if (-not $StatePath) { $StatePath = Get-SdUpdateStatePath }
    $st = Read-SdJsonFile $StatePath
    $last = $null
    if ($st -and $st.PSObject.Properties['lastCheck']) { $last = ConvertFrom-SdJsonDate $st.lastCheck }
    # zegar cofnięty po poprzednim sprawdzeniu (data z przyszłości) - sprawdzamy od razu
    return (-not $last -or $last -gt $Now -or ($Now - $last).TotalHours -ge $global:SdUpdateCheckHours)
}

function Save-SdUpdateCheckState {
    # Notified: wersja, o której użytkownik już dostał powiadomienie (bez parametru - bez zmian)
    param($Release, [string]$StatePath = '', [string]$Notified = '')
    if (-not $StatePath) { $StatePath = Get-SdUpdateStatePath }
    $old = Read-SdJsonFile $StatePath
    if (-not $PSBoundParameters.ContainsKey('Notified')) { $Notified = $(if ($old -and $old.PSObject.Properties['notified']) { [string]$old.notified } else { '' }) }
    Write-SdJsonFile $StatePath ([ordered]@{ lastCheck = (Get-Date).ToString('s'); latest = [string]$Release.Latest; newer = [bool]$Release.Newer; notified = $Notified })
}

function Get-SdInstallMode {
    # 'allusers' | 'currentuser' dla kopii z instalatora, '' dla przenośnej. Instalator zapisuje tryb w instalacja.ini
    # (od wersji 1.4.0); wcześniejsze instalacje rozpoznajemy po folderze (Program Files = dla wszystkich użytkowników).
    param([string]$Root)
    $ini = Join-Path $Root 'instalacja.ini'
    if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) { return '' }
    $txt = [System.IO.File]::ReadAllText($ini)
    if ($txt -match '(?im)^\s*Tryb\s*=\s*wszyscy\s*$') { return 'allusers' }
    if ($txt -match '(?im)^\s*Tryb\s*=\s*biezacy\s*$') { return 'currentuser' }
    $full = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432)) {
        if ($pf -and $full.StartsWith(([System.IO.Path]::GetFullPath($pf).TrimEnd('\') + '\'), [System.StringComparison]::OrdinalIgnoreCase)) { return 'allusers' }
    }
    return 'currentuser'
}

function Save-SdWebFile {
    # Pobiera plik pod wskazaną ścieżkę: https:// (wydania na GitHubie) albo file:// (testy).
    param([string]$Url, [string]$Path)
    # TLS 1.2 nie jest domyślnie włączony w .NET 4.5 (Windows 8 / 8.1)
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    $wc = New-Object System.Net.WebClient
    if ($Url -match '^https?://') { $wc.Headers['User-Agent'] = 'SerwisDiag/' + $global:SdVersion }
    try { $wc.DownloadFile($Url, $Path) } finally { $wc.Dispose() }
}

function Get-SdUpdatePackage {
    # Pobiera instalator nowej wersji i sprawdza go: suma SHA-256 z pliku .sha256 wydania i numer wersji zapisany w pliku.
    # Wynik: ścieżka instalatora. Błąd = wyjątek z opisem po polsku; niesprawdzony plik nie zostaje uruchomiony.
    param([Parameter(Mandatory = $true)]$Release, [string]$Dir = '')
    if (-not $Release.Setup -or -not $Release.SetupSha) { throw 'Wydanie nie zawiera instalatora albo jego sumy kontrolnej - pobierz nową wersję ze strony projektu.' }
    if (-not $Dir) { $Dir = Join-Path ([System.IO.Path]::GetTempPath()) ('SerwisDiag-aktualizacja-' + $Release.Latest) }
    if (-not (Test-Path -LiteralPath $Dir)) { [void](New-Item -ItemType Directory -Path $Dir -Force) }
    $name = $(if ($Release.SetupName) { $Release.SetupName -replace '[\\/:*?"<>|]', '_' } else { 'SerwisDiag-setup.exe' })
    $setup = Join-Path $Dir $name
    $shaFile = $setup + '.sha256'
    try {
        Save-SdWebFile $Release.Setup $setup
        Save-SdWebFile $Release.SetupSha $shaFile
    } catch {
        $ex = $_.Exception
        while ($ex.InnerException) { $ex = $ex.InnerException }
        throw ('Nie udało się pobrać aktualizacji: ' + $ex.Message)
    }
    $expected = ''
    if (([System.IO.File]::ReadAllText($shaFile)).Trim() -match '^([0-9a-fA-F]{64})\b') { $expected = $Matches[1].ToLower() }
    if (-not $expected) { throw 'Plik sumy kontrolnej wydania jest nieprawidłowy - aktualizację przerwano.' }
    if ((Get-SdFileSha256 $setup) -ne $expected) {
        Remove-Item -LiteralPath $setup -Force -ErrorAction SilentlyContinue
        throw 'Suma kontrolna pobranego instalatora się nie zgadza (plik uszkodzony albo podmieniony) - aktualizację przerwano.'
    }
    $fv = ConvertTo-SdVersion ([string](Get-Item -LiteralPath $setup).VersionInfo.FileVersion)
    $rv = ConvertTo-SdVersion $Release.Latest
    if (-not $fv -or -not $rv -or $fv -ne $rv) { throw ('Pobrany instalator ma inny numer wersji ({0}) niż wydanie ({1}) - aktualizację przerwano.' -f $fv, $Release.Latest) }
    return $setup
}

function Get-SdUpdateArguments {
    # Parametry instalatora przy aktualizacji: okno postępu bez pytań, ten sam tryb instalacji co dotąd,
    # na życzenie ponowne uruchomienie programu (/RELAUNCH=1 odczytuje skrypt instalatora).
    param([string]$Mode, [switch]$Relaunch)
    $a = '/SILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL'
    if ($Mode -eq 'allusers') { $a += ' /ALLUSERS' } elseif ($Mode -eq 'currentuser') { $a += ' /CURRENTUSER' }
    if ($Relaunch) { $a += ' /RELAUNCH=1' }
    return $a
}

function Start-SdUpdateInstall {
    # Uruchamia sprawdzony instalator nowej wersji (bez czekania - program powinien się zaraz zamknąć).
    param([Parameter(Mandatory = $true)][string]$SetupPath, [Parameter(Mandatory = $true)][string]$Root, [switch]$Relaunch)
    $mode = Get-SdInstallMode $Root
    if (-not $mode) { throw 'Ta kopia programu nie pochodzi z instalatora - pobierz nową wersję ze strony projektu.' }
    return (Start-Process -FilePath $SetupPath -ArgumentList (Get-SdUpdateArguments -Mode $mode -Relaunch:$Relaunch) -PassThru)
}

function Invoke-SdUpdate {
    # Sprawdzenie, pobranie, kontrola i uruchomienie instalatora nowej wersji. Wynik: { Started; Release; Message }.
    param([Parameter(Mandatory = $true)][string]$Root, [switch]$Relaunch, [string]$ProjectUrl = $global:SdProjectUrl, [string]$Json = '', [string]$Dir = '')
    $rel = Get-SdLatestRelease -ProjectUrl $ProjectUrl -Json $Json
    if (-not $rel.Ok) { return [pscustomobject]@{ Started = $false; Release = $rel; Message = $rel.Error } }
    if (-not $rel.Newer) { return [pscustomobject]@{ Started = $false; Release = $rel; Message = (Get-SdLatestReleaseText $rel) } }
    if (-not (Get-SdInstallMode $Root)) { return [pscustomobject]@{ Started = $false; Release = $rel; Message = ('Wersja przenośna nie aktualizuje się sama. ' + (Get-SdLatestReleaseText $rel)) } }
    $setup = Get-SdUpdatePackage -Release $rel -Dir $Dir
    [void](Start-SdUpdateInstall -SetupPath $setup -Root $Root -Relaunch:$Relaunch)
    return [pscustomobject]@{ Started = $true; Release = $rel; Message = ('Instalowanie wersji {0}...' -f $rel.Latest) }
}

function Get-SdVersionOnDisk {
    # Numer wersji z pliku lib\Core.ps1 w folderze programu - monitor po aktualizacji uruchamia się w nowej wersji.
    param([string]$Root)
    $p = Join-Path $Root 'lib\Core.ps1'
    try { if ([System.IO.File]::ReadAllText($p) -match "SdVersion\s*=\s*'([^']+)'") { return $Matches[1] } } catch { }
    return ''
}
