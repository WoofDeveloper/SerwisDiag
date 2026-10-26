# SerwisDiag - buduje SerwisDiag.exe i SerwisDiagMonitor.exe (launchery) wbudowanym kompilatorem csc.exe z .NET Framework 4.x.
# Nie wymaga instalowania Visual Studio ani .NET SDK. Plik celowo wylacznie ASCII.
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'tools\launcher\Launcher.cs'
$icon = Join-Path $root 'assets\app.ico'

$csc = $null
foreach ($c in @((Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'), (Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe'))) {
    if (Test-Path -LiteralPath $c) { $csc = $c; break }
}
if (-not $csc) { Write-Host 'Nie znaleziono csc.exe (.NET Framework 4.x).' -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $icon)) { & (Join-Path $PSScriptRoot 'make-icon.ps1') }

# SerwisDiag.exe: okno programu z uprawnieniami administratora; SerwisDiagMonitor.exe: monitor w tle bez UAC
foreach ($t in @(@{ Out = 'SerwisDiag.exe'; Manifest = 'launcher.manifest'; Define = '' }, @{ Out = 'SerwisDiagMonitor.exe'; Manifest = 'monitor.manifest'; Define = 'MONITOR' })) {
    $out = Join-Path $root $t.Out
    $cscArgs = @('/nologo', '/target:winexe', '/optimize+', '/codepage:65001', "/out:$out", ('/win32manifest:' + (Join-Path $root ('tools\launcher\' + $t.Manifest))), '/reference:System.Windows.Forms.dll')
    if ($t.Define) { $cscArgs += ('/define:' + $t.Define) }
    if (Test-Path -LiteralPath $icon) { $cscArgs += "/win32icon:$icon" }
    $cscArgs += $src
    & $csc @cscArgs
    if ($LASTEXITCODE -ne 0) { Write-Host ('Kompilacja {0} nie powiodla sie.' -f $t.Out) -ForegroundColor Red; exit $LASTEXITCODE }
    Write-Host ("Zbudowano {0} ({1} KB)" -f $out, [math]::Round((Get-Item $out).Length / 1KB, 1)) -ForegroundColor Green
}
