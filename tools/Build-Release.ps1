# SerwisDiag - paczka ZIP i instalator do publikacji (plik celowo wylacznie ASCII).
#   powershell -ExecutionPolicy Bypass -File tools\Build-Release.ps1 [-OutDir <folder>] [-NoInstaller] [-Iscc <sciezka do ISCC.exe>]
# Do paczki trafiaja tylko pliki programu, dokumentacja i narzedzia. Nigdy: raporty, ustawienia serwisu, logi -
# raporty zawieraja dane komputerow (numery seryjne, klucze Windows, nazwy kont).
# Instalator (SerwisDiag-<wersja>-setup.exe) buduje Inno Setup 7 z tych samych plikow, bez narzedzi programisty.
param([string]$OutDir = '', [switch]$NoInstaller, [string]$Iscc = '')

$root = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
if (-not (Test-Path -LiteralPath $OutDir)) { [void](New-Item -ItemType Directory -Path $OutDir -Force) }
. (Join-Path $root 'lib\Integrity.ps1')

# 1) wersja z lib\Core.ps1
$core = [System.IO.File]::ReadAllText((Join-Path $root 'lib\Core.ps1'))
if ($core -notmatch "SdVersion\s*=\s*'([^']+)'") { Write-Host 'Nie znaleziono numeru wersji w lib\Core.ps1' -ForegroundColor Red; exit 1 }
$ver = $Matches[1]

# 2) pliki programu musza zgadzac sie z manifestem (po kazdej zmianie: tools\check.ps1)
$int = Test-SdIntegrity -Root $root
if ($int.Status -ne 'ok') { Write-Host ('Pliki nie zgadzaja sie z manifestem: ' + $int.Summary + "`nUruchom najpierw tools\check.ps1.") -ForegroundColor Red; exit 1 }

# 3) lista plikow: program (jak w manifescie), dokumentacja, licencja, ikona, narzedzia (z zrodlem programu EXE i instalatora)
$files = @(Get-SdProgramFiles $root) + @('manifest.sha256', 'README.md', 'LICENSE', 'CHANGELOG.md', 'assets\app.ico')
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $root 'tools') -Recurse -File | Sort-Object FullName)) { $files += $f.FullName.Substring($root.Length + 1) }
$missing = @($files | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf) })
if ($missing.Count -gt 0) { Write-Host ('Brak plikow: ' + ($missing -join ', ')) -ForegroundColor Red; exit 1 }

# 4) katalog roboczy w folderze tymczasowym (nie w dist - tam moze byc rozpakowana paczka uzytkownika) i ZIP
#    z folderem SerwisDiag-<wersja> w srodku
$name = 'SerwisDiag-' + $ver
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('sd-release-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $work $name
foreach ($rel in $files) {
    $dst = Join-Path $stage $rel
    $dd = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dd)) { [void](New-Item -ItemType Directory -Path $dd -Force) }
    Copy-Item -LiteralPath (Join-Path $root $rel) -Destination $dst
}
$zip = Join-Path $OutDir ($name + '.zip')
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)

# 5) kontrola zawartosci: komplet plikow programu i zadnych danych komputerow ani ustawien
$zf = [System.IO.Compression.ZipFile]::OpenRead($zip)
try { $entries = @($zf.Entries | ForEach-Object { $_.FullName -replace '/', '\' }) } finally { $zf.Dispose() }
$bad = @($entries | Where-Object { $_ -match '(^|\\)(raporty|logs|config|dist)\\' -or $_ -match '\.(json|txt|html|htm|pdf|csv|png|jpg)$' })
$absent = @($files | Where-Object { $entries -notcontains ($name + '\' + $_) })
if ($bad.Count -gt 0 -or $absent.Count -gt 0) {
    if ($bad.Count) { Write-Host ('W paczce sa pliki, ktorych nie powinno byc: ' + ($bad -join ', ')) -ForegroundColor Red }
    if ($absent.Count) { Write-Host ('W paczce brakuje: ' + ($absent -join ', ')) -ForegroundColor Red }
    Remove-Item -LiteralPath $zip -Force
    Remove-Item -LiteralPath $work -Recurse -Force
    exit 1
}

# 6) suma SHA-256 do opublikowania obok paczki
$hash = Get-SdFileSha256 $zip
[System.IO.File]::WriteAllText(($zip + '.sha256'), ('{0}  {1}' -f $hash, (Split-Path -Leaf $zip)) + "`r`n", (New-Object System.Text.ASCIIEncoding))
Write-Host ('Paczka: {0}' -f $zip) -ForegroundColor Green
Write-Host ('Plikow: {0}, rozmiar: {1:N0} KB' -f $entries.Count, ((Get-Item -LiteralPath $zip).Length / 1KB))
Write-Host ('SHA-256: {0}' -f $hash)

# 7) instalator z tych samych plikow (Inno Setup 7; bez niego tylko ostrzezenie - ZIP jest gotowy)
if (-not $NoInstaller) {
    if (-not $Iscc) {
        foreach ($c in @((Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'), (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'))) {
            if (Test-Path -LiteralPath $c) { $Iscc = $c; break }
        }
    }
    if (-not $Iscc) {
        Write-Host 'Instalator pominiety: nie znaleziono Inno Setup 7 (ISCC.exe). Pobierz go z https://jrsoftware.org/isdl.php albo podaj -Iscc.' -ForegroundColor Yellow
    } else {
        # licencja z BOM: bez niego kreator pokazalby polskie znaki jako tekst ANSI
        $lic = Join-Path $work 'LICENSE-instalator.txt'
        [System.IO.File]::WriteAllText($lic, [System.IO.File]::ReadAllText((Join-Path $stage 'LICENSE')), (New-Object System.Text.UTF8Encoding($true)))
        $setup = Join-Path $OutDir ($name + '-setup.exe')
        if (Test-Path -LiteralPath $setup) { Remove-Item -LiteralPath $setup -Force }
        & $Iscc '/Q' ('/DAppVersion=' + $ver) ('/DSourceDir=' + $stage) ('/DLicensePath=' + $lic) ('/DOutDir=' + $OutDir) (Join-Path $root 'tools\installer\SerwisDiag.iss')
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $setup)) {
            Write-Host ('Kompilacja instalatora nie powiodla sie (kod {0}).' -f $LASTEXITCODE) -ForegroundColor Red
            Remove-Item -LiteralPath $work -Recurse -Force
            exit 1
        }
        $sh = Get-SdFileSha256 $setup
        [System.IO.File]::WriteAllText(($setup + '.sha256'), ('{0}  {1}' -f $sh, (Split-Path -Leaf $setup)) + "`r`n", (New-Object System.Text.ASCIIEncoding))
        Write-Host ('Instalator: {0}' -f $setup) -ForegroundColor Green
        Write-Host ('Rozmiar: {0:N0} KB, SHA-256: {1}' -f ((Get-Item -LiteralPath $setup).Length / 1KB), $sh)
    }
}
Remove-Item -LiteralPath $work -Recurse -Force
exit 0
