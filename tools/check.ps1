# SerwisDiag - narzedzie developerskie (plik celowo wylacznie ASCII).
#  1) dopisuje BOM UTF-8 do *.ps1 / *.psd1 (Windows PowerShell 5.1 inaczej psuje polskie znaki)
#  2) sprawdza skladnie kazdego skryptu parserem PowerShell
#  3) szuka konstrukcji niedzialajacych w PowerShell 3.0 (Windows 8)
param([switch]$Quiet)

$root = Split-Path -Parent $PSScriptRoot
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$files = Get-ChildItem -Path $root -Recurse -Include *.ps1, *.psd1 | Where-Object { $_.FullName -notmatch '\\(raporty|logs|dist)\\' }

$fixed = 0
foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if (-not $hasBom) {
        $text = [System.IO.File]::ReadAllText($f.FullName, (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($f.FullName, $text, $utf8Bom)
        $fixed++
    }
}
if (-not $Quiet) { Write-Host ("BOM: poprawiono {0} z {1} plikow" -f $fixed, @($files).Count) }
# skrypt instalatora: Inno Setup czyta plik bez BOM jako ANSI (polskie znaki w kreatorze bylyby znieksztalcone)
foreach ($f in (Get-ChildItem -Path (Join-Path $root 'tools') -Recurse -Filter *.iss)) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
        [System.IO.File]::WriteAllText($f.FullName, [System.IO.File]::ReadAllText($f.FullName, (New-Object System.Text.UTF8Encoding($false))), $utf8Bom)
        if (-not $Quiet) { Write-Host ("BOM: poprawiono {0}" -f $f.Name) }
    }
}

# pliki .cmd: koncowki linii CRLF (LF powoduje problemy z etykietami i blokami) oraz tylko znaki ASCII
$cmdProblems = 0
foreach ($c in (Get-ChildItem -Path $root -Filter *.cmd)) {
    $raw = [System.IO.File]::ReadAllText($c.FullName, [System.Text.Encoding]::UTF8)
    if ($raw -match '[^\x00-\x7F]') { Write-Host ("[CMD] {0}: znaki spoza ASCII (zepsuja sie w cmd.exe)" -f $c.Name) -ForegroundColor Red; $cmdProblems++ }
    $norm = ($raw -replace "`r?`n", "`r`n")
    if ($norm -ne $raw) { [System.IO.File]::WriteAllText($c.FullName, $norm, (New-Object System.Text.ASCIIEncoding)); if (-not $Quiet) { Write-Host ("CRLF: poprawiono {0}" -f $c.Name) } }
}

# znane polecenia, ktore istnieja w PowerShell 3.0 / Windows 8 (reszta trafia na liste do recznej weryfikacji)
$known = @'
Add-Member Add-Type Clear-Host ConvertFrom-Json ConvertTo-Html ConvertTo-Json Compare-Object Copy-Item Export-Csv
ForEach-Object Format-List Format-Table Get-ChildItem Get-CimAssociatedInstance Get-CimInstance Get-Command Get-Content
Get-Date Get-HotFix Get-Item Get-ItemProperty Get-Location Get-Member Get-Process Get-PSDrive Get-Random Get-Service Get-Variable
Get-WinEvent Group-Object Import-Clixml Invoke-Command Invoke-Expression Invoke-WebRequest Join-Path Measure-Object
New-Item New-Object New-PSDrive New-TimeSpan Out-File Out-Null Out-String Remove-Item Remove-Variable Resolve-Path
Select-Object Select-String Set-Content Set-ItemProperty Set-Location Set-Variable Sort-Object Split-Path Start-Job
Start-Process Start-Sleep Stop-Job Stop-Process Test-Path Wait-Job Receive-Job Remove-Job Where-Object Write-Error Write-Host
Write-Output Write-Verbose Write-Warning Get-ComputerRestorePoint Checkpoint-Computer Get-NetAdapter Get-NetIPConfiguration
Get-NetTCPConnection Get-PhysicalDisk Get-Disk Get-Partition Get-Volume Get-ScheduledTask Get-AuthenticodeSignature
Repair-WindowsImage Repair-Volume Confirm-SecureBootUEFI Get-AppxPackage Get-MpComputerStatus Get-MpPreference Get-StorageReliabilityCounter
Resolve-DnsName Get-NetFirewallProfile Get-Culture Unblock-File Start-Transcript Stop-Transcript Get-EventLog Test-Connection
Set-StrictMode Set-ExecutionPolicy Select-Xml Register-ObjectEvent Unregister-Event Wait-Event Export-Clixml Rename-Item Get-Alias
Get-Help Get-History Read-Host Write-Progress ForEach Where Sort Select Add-Content Import-Module Get-Module Test-Json
Get-NetRoute Get-NetIPInterface Mount-DiskImage Dismount-DiskImage Get-DiskImage Get-WindowsImage Get-SmbServerConfiguration
'@ -split '\s+' | Where-Object { $_ }

$problems = 0
$unknown = @{}
foreach ($f in $files) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    foreach ($e in $errors) {
        Write-Host ("[SKLADNIA] {0}:{1}: {2}" -f $f.Name, $e.Extent.StartLineNumber, $e.Message) -ForegroundColor Red
        $problems++
    }
    if ($errors.Count -gt 0) { continue }

    # klasy / enumy / using (PowerShell 5+)
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TypeDefinitionAst] -or $n -is [System.Management.Automation.Language.UsingStatementAst] }, $true) | ForEach-Object {
        Write-Host ("[PS5+] {0}:{1}: class/enum/using nie dziala w PS 3.0" -f $f.Name, $_.Extent.StartLineNumber) -ForegroundColor Yellow; $problems++
    }
    # [Typ]::new(...) oraz .Where( / .ForEach( (PS 4+/5+)
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true) | ForEach-Object {
        $m = $_.Member.Extent.Text
        if ($_.Static -and $m -eq 'new') {
            Write-Host ("[PS5+] {0}:{1}: ::new() nie dziala w PS 3.0/4.0" -f $f.Name, $_.Extent.StartLineNumber) -ForegroundColor Yellow; $problems++
        }
        if (-not $_.Static -and ($m -eq 'Where' -or $m -eq 'ForEach')) {
            Write-Host ("[PS4+] {0}:{1}: .{2}() - metoda kolekcji PS 4.0+ (ok tylko dla typow .NET jak List[T].ForEach)" -f $f.Name, $_.Extent.StartLineNumber, $m) -ForegroundColor Yellow
        }
    }
    # "napis" + $x, "y" - przecinek wiaze mocniej niz +: do napisu doklejana jest cala tablica (trzeba nawiasow)
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.BinaryExpressionAst] -and $n.Operator -eq 'Plus' -and ($n.Left -is [System.Management.Automation.Language.ArrayLiteralAst] -or $n.Right -is [System.Management.Automation.Language.ArrayLiteralAst]) }, $true) | ForEach-Object {
        Write-Host ("[PRZECINEK] {0}:{1}: wyrazenie 'a + b, c' - przecinek wiaze mocniej niz +, dodaj nawiasy" -f $f.Name, $_.Extent.StartLineNumber) -ForegroundColor Yellow; $problems++
    }
    # [math]::Max(0, $x) - PowerShell wybiera wersje Max/Min wg typu pierwszego argumentu; przy liczbie calkowitej to Int32,
    # wiec wartosc ponad 2 147 483 647 (np. liczba bajtow) konczy sie bledem (tak psulo sie czyszczenie plikow)
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Static -and $n.Expression -is [System.Management.Automation.Language.TypeExpressionAst] }, $true) | ForEach-Object {
        $m = $_.Member.Extent.Text
        if ($_.Expression.TypeName.FullName -match '^(System\.)?Math$' -and ($m -eq 'Max' -or $m -eq 'Min') -and @($_.Arguments).Count -eq 2) {
            $a0 = $_.Arguments[0]
            if ($a0 -is [System.Management.Automation.Language.ConstantExpressionAst] -and $a0.Value -is [int] -and $_.Arguments[1] -isnot [System.Management.Automation.Language.ConstantExpressionAst]) {
                Write-Host ("[MATH] {0}:{1}: [math]::{2}(liczba calkowita, ...) - PowerShell wybierze wersje Int32 i wartosc ponad 2^31 da blad; pierwszy argument 0.0 albo zmienna" -f $f.Name, $_.Extent.StartLineNumber, $m) -ForegroundColor Yellow; $problems++
            }
        }
    }
    # @{ Keys = ... } - w tablicy z kluczem Keys/Values/Count zapis $h.Keys zwraca wartosc tego klucza zamiast listy kluczy
    # (tak ginely naprawy zaznaczone w oknie); w [pscustomobject]@{ } takie nazwy sa bezpieczne
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true) | ForEach-Object {
        $p = $_.Parent
        if ($p -is [System.Management.Automation.Language.ConvertExpressionAst] -and $p.Type.TypeName.FullName -match '^(pscustomobject|psobject)$') { return }
        foreach ($kp in $_.KeyValuePairs) {
            $kn = $kp.Item1.Extent.Text.Trim([char[]]"'`"")
            if (@('Keys', 'Values', 'Count') -contains $kn) {
                Write-Host ("[KLUCZ] {0}:{1}: klucz '{2}' w tablicy @{{}} - zapis `$tablica.{2} zwroci jego wartosc, zmien nazwe klucza" -f $f.Name, $kp.Item1.Extent.StartLineNumber, $kn) -ForegroundColor Yellow; $problems++
            }
        }
    }
    # Join-Path z wiecej niz 2 argumentami pozycyjnymi (PS 6+)
    $cmds = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $cmds) {
        $name = $c.GetCommandName()
        if (-not $name) { continue }
        if ($name -eq 'Join-Path') {
            $pos = @($c.CommandElements | Select-Object -Skip 1 | Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] })
            $named = @($c.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] })
            if (($pos.Count - $named.Count) -gt 2) {
                Write-Host ("[PS6+] {0}:{1}: Join-Path z >2 argumentami" -f $f.Name, $c.Extent.StartLineNumber) -ForegroundColor Yellow; $problems++
            }
        }
        if ($known -notcontains $name) {
            $isFunc = $false
            if (-not $unknown.ContainsKey($name)) { $unknown[$name] = New-Object System.Collections.ArrayList }
            [void]$unknown[$name].Add($f.Name)
        }
    }
}

# polecenia zdefiniowane lokalnie (function X) nie sa "nieznane"
$defined = @{}
foreach ($f in $files) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $defined[$_.Name] = $true }
}
$review = $unknown.Keys | Where-Object { -not $defined.ContainsKey($_) } | Sort-Object
if ($review -and -not $Quiet) {
    Write-Host "Polecenia do recznej weryfikacji pod katem Windows 8 / PS 3.0:" -ForegroundColor Cyan
    foreach ($r in $review) { Write-Host ("  {0}  ({1})" -f $r, (($unknown[$r] | Select-Object -Unique) -join ', ')) }
}
if ($problems -ne 0) { Write-Host "check: $problems problem(ow)" -ForegroundColor Red; exit 1 }

# manifest sum SHA-256 (kontrola integralnosci przy starcie programu) - na koncu, po poprawkach BOM i CRLF
. (Join-Path $root 'lib\Integrity.ps1')
New-SdManifest -Root $root
if (-not $Quiet) { Write-Host ("Manifest: {0} plikow" -f @(Get-SdProgramFiles $root).Count) }
Write-Host "check: OK (brak bledow skladni i konstrukcji PS5+)" -ForegroundColor Green
