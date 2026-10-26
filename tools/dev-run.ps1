# SerwisDiag - uruchamia silnik w konsoli i drukuje wyniki (do rozwoju / diagnozowania testow).
#   powershell -ExecutionPolicy Bypass -File tools\dev-run.ps1 -Only sys.os,sys.win11 -Details
param(
    [ValidateSet('Quick', 'Full')][string]$Level = 'Quick',
    [string]$Only = '',      # wzorce Id testow rozdzielone przecinkami, np. "sys.*,hw.cpu"
    [string]$TestIds = '',   # Id testow obciazeniowych (Level=Test) rozdzielone przecinkami
    [switch]$Details,
    [switch]$Tables,
    [switch]$Log,
    [switch]$ShowPrivate
)
$onlyList = @($Only -split ',' | Where-Object { $_ })
$testList = @($TestIds -split ',' | Where-Object { $_ })
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent $PSScriptRoot
$SdRoot = $root
. (Join-Path $SdRoot 'lib\Load.ps1')

$runLevel = $Level
if ($onlyList.Count -gt 0) {
    $keep = New-Object System.Collections.ArrayList
    foreach ($c in $global:SdChecks) {
        foreach ($o in $onlyList) { if ($c.Id -like $o) { [void]$keep.Add($c); break } }
    }
    $global:SdChecks = $keep
    $runLevel = 'Full'
    $testList = @($keep | ForEach-Object { $_.Id })
}

$global:SD = New-SdContext -Root $root -Level $runLevel -Tests $testList
Write-Host ("Admin: {0}; testow: {1}" -f $global:SD.IsAdmin, (Get-SdSelectedChecks -Level $runLevel -Tests $testList).Count)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Invoke-SdScan
$sw.Stop()

$colors = @{ crit = 'Red'; warn = 'Yellow'; ok = 'Green'; info = 'Cyan'; skip = 'DarkGray'; error = 'Magenta' }
foreach ($f in $global:SD.Findings) {
    $val = $f.Value
    if ($f.Private -and -not $ShowPrivate) { $val = '(dane prywatne - ukryte w konsoli)' }
    Write-Host ('[{0,-5}] {1,-9} {2}: {3}' -f $f.Status.ToUpper(), $f.Category, $f.Title, $val) -ForegroundColor $colors[$f.Status]
    if ($Details -and -not ($f.Private -and -not $ShowPrivate)) {
        if ($f.Details) { ($f.Details -split "`n") | ForEach-Object { Write-Host ('          | ' + $_) -ForegroundColor DarkGray } }
        if ($f.Advice) { Write-Host ('          > ' + $f.Advice) -ForegroundColor DarkYellow }
    }
}
if ($Tables) {
    foreach ($t in @($global:SD.Tables | Where-Object { $ShowPrivate -or -not $_.Private })) {
        Write-Host ("`n=== TABELA [{0}] {1} ({2} wierszy) ===" -f $t.Category, $t.Name, $t.Rows.Count) -ForegroundColor White
        $t.Rows | Select-Object -First 12 | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
    }
}
Write-Host "`n--- czasy (s) ---"
$global:SD.Timings | Sort-Object Seconds -Descending | Select-Object -First 12 | ForEach-Object { Write-Host ('{0,6} {1}' -f $_.Seconds, $_.Id) }
$showAllLog = [bool]$Log
$logLines = @($global:SD.Log | Where-Object { $showAllLog -or $_ -match '\[(WARN|ERROR)\]' })
if ($logLines.Count -gt 0) { Write-Host "`n--- log ---"; $logLines | ForEach-Object { Write-Host $_ -ForegroundColor DarkYellow } }
$s = @{}
foreach ($f in $global:SD.Findings) { $s[$f.Status] = 1 + [int]$s[$f.Status] }
Write-Host ("`nRazem: {0} wynikow w {1:N1} s  {2}" -f $global:SD.Findings.Count, $sw.Elapsed.TotalSeconds, (($s.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '))
