# SerwisDiag - naprawy wymagające przygotowania: DISM RestoreHealth z płyty / pendrive'a / obrazu ISO Windows.
# Bez internetu DISM nie pobierze plików z Windows Update - źródłem musi być install.wim / install.esd tej samej
# wersji Windows (ta sama kompilacja bazowa, edycja, język i architektura).

function Get-SdBuildFamily {
    # Wydania różniące się tylko pakietem aktywującym mają wspólne pliki systemu
    # (Windows 10 2004-22H2 = 19041, Windows 11 22H2/23H2 = 22621, 24H2/25H2/26H2 = 26100).
    param([int]$Build)
    $fam = @{ 18363 = 18362; 19042 = 19041; 19043 = 19041; 19044 = 19041; 19045 = 19041; 22631 = 22621; 26200 = 26100; 26300 = 26100 }
    if ($fam.ContainsKey($Build)) { return [int]$fam[$Build] }
    return $Build
}

function ConvertTo-SdArchName {
    # Architektura obrazu z Get-WindowsImage (liczba albo nazwa) -> x86 | x64 | ARM | ARM64.
    param($Value)
    switch -Regex ([string]$Value) {
        '^(9|x64|amd64)$' { return 'x64' }
        '^(0|x86)$' { return 'x86' }
        '^(12|arm64)$' { return 'ARM64' }
        '^(5|arm)$' { return 'ARM' }
    }
    return [string]$Value
}

function Select-SdImageIndex {
    # Wybiera z obrazu instalacyjnego edycję pasującą do zainstalowanego systemu (funkcja czysta - testy jednostkowe).
    # Images: { Index; Name; EditionId; Build; Arch; Languages }. Zwraca { Index (0 = nic nie pasuje); Image; Problems }.
    param([object[]]$Images, [string]$EditionId, [int]$Build, [string]$Arch, [string]$Language)
    $r = [pscustomobject]@{ Index = 0; Image = $null; Problems = @() }
    $all = @($Images | Where-Object { $null -ne $_ })
    if ($all.Count -eq 0) { $r.Problems += 'Obraz nie zawiera żadnej edycji Windows.'; return $r }
    $fam = Get-SdBuildFamily $Build
    $same = @($all | Where-Object { (Get-SdBuildFamily ([int]$_.Build)) -eq $fam })
    if ($same.Count -eq 0) {
        $have = (@($all | ForEach-Object { [string]$_.Build } | Select-Object -Unique) -join ', ')
        $r.Problems += ('Obraz jest z innej wersji Windows (kompilacja {0}), a zainstalowany system to kompilacja {1}. Potrzebny jest obraz tej samej wersji.' -f $have, $Build)
        return $r
    }
    if ($Arch) {
        $archOk = @($same | Where-Object { -not $_.Arch -or $_.Arch -eq $Arch })
        if ($archOk.Count -eq 0) { $r.Problems += ('Obraz jest dla architektury {0}, a system to {1}.' -f $same[0].Arch, $Arch); return $r }
        $same = $archOk
    }
    # edycja: dokładnie ta sama, a gdy jej brak - najbliższa (Home Single Language -> Home, Pro Education/Workstation -> Pro)
    $pref = @($EditionId)
    switch -Regex ($EditionId) {
        '^CoreSingleLanguage$' { $pref += 'Core' }
        '^CoreCountrySpecific$' { $pref += 'Core' }
        '^Professional(Education|Workstation)$' { $pref += 'Professional' }
        '^(Education|Enterprise)$' { $pref += 'Professional' }
        '^(Core|Professional)N$' { $pref += ($EditionId -replace 'N$', '') }
    }
    $pick = $null
    foreach ($e in $pref) {
        $pick = @($same | Where-Object { [string]$_.EditionId -eq $e }) | Select-Object -First 1
        if ($pick) { break }
    }
    if (-not $pick) {
        $pick = $same[0]
        $r.Problems += ('W obrazie nie ma edycji {0} - użyto „{1}”. Naprawa zwykle się uda, ale pliki właściwe tylko dla innej edycji mogą nie zostać odtworzone.' -f $EditionId, $pick.Name)
    } elseif ([string]$pick.EditionId -ne $EditionId) {
        $r.Problems += ('Użyto pokrewnej edycji „{0}” (zainstalowana: {1}).' -f $pick.Name, $EditionId)
    }
    if ($Language -and @($pick.Languages).Count -gt 0 -and @($pick.Languages) -notcontains $Language) {
        $r.Problems += ('Język obrazu ({0}) różni się od języka systemu ({1}) - DISM może nie znaleźć plików językowych.' -f (@($pick.Languages) -join ', '), $Language)
    }
    if ([int]$pick.Build -ne $Build) {
        $r.Problems += ('Obraz ma kompilację {0}, system {1} - to ta sama rodzina wydań, naprawa powinna działać.' -f $pick.Build, $Build)
    }
    $r.Index = [int]$pick.Index
    $r.Image = $pick
    return $r
}

function Get-SdDismSourceArg {
    # Parametr /Source dla DISM: /Source:wim:E:\sources\install.wim:6 (albo esd:...).
    param([string]$ImagePath, [int]$Index)
    $kind = $(if ($ImagePath -match '\.esd$') { 'esd' } else { 'wim' })
    $a = '/Source:{0}:{1}:{2}' -f $kind, $ImagePath, $Index
    if ($a -match '\s') { $a = '"' + $a + '"' }
    return $a
}

function Resolve-SdInstallImage {
    # Ścieżka wybrana przez technika (obraz ISO, install.wim / install.esd albo katalog / litera nośnika) -> plik obrazu.
    # Obraz ISO jest montowany jako napęd (MountedIso - do odłączenia po naprawie).
    param([Parameter(Mandatory = $true)][string]$Path)
    $r = [pscustomobject]@{ ImagePath = ''; MountedIso = ''; Error = '' }
    if ($Path -match '\.(wim|esd)$') {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { $r.ImagePath = $Path } else { $r.Error = 'Nie znaleziono pliku: ' + $Path }
        return $r
    }
    $root = $Path
    if ($Path -match '\.iso$') {
        try {
            $di = Get-DiskImage -ImagePath $Path -ErrorAction Stop
            if (-not $di.Attached) { $di = Mount-DiskImage -ImagePath $Path -PassThru -ErrorAction Stop; $r.MountedIso = $Path }
            $letter = ''
            for ($i = 0; $i -lt 20 -and -not $letter; $i++) {
                $vol = Get-DiskImage -ImagePath $Path | Get-Volume -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($vol -and $vol.DriveLetter) { $letter = [string]$vol.DriveLetter } else { Start-Sleep -Milliseconds 300 }
            }
            if (-not $letter) { $r.Error = 'Obraz ISO zamontowano, ale nie otrzymał litery dysku.'; return $r }
            $root = $letter + ':\'
        } catch {
            $r.Error = 'Nie udało się zamontować obrazu ISO: ' + $_.Exception.Message
            return $r
        }
    }
    foreach ($n in 'sources\install.wim', 'sources\install.esd') {
        $p = Join-Path $root $n
        if (Test-Path -LiteralPath $p -PathType Leaf) { $r.ImagePath = $p; return $r }
    }
    $r.Error = 'Na nośniku nie ma pliku sources\install.wim ani sources\install.esd - to nie jest nośnik instalacyjny Windows (albo obraz jest podzielony na pliki .swm, których DISM nie użyje do naprawy).'
    return $r
}

function Get-SdImageEditions {
    # Edycje w install.wim / install.esd (Get-WindowsImage z modułu DISM, wymaga administratora).
    param([Parameter(Mandatory = $true)][string]$ImagePath)
    $out = @()
    foreach ($i in @(Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop)) {
        $d = $null
        try { $d = Get-WindowsImage -ImagePath $ImagePath -Index $i.ImageIndex -ErrorAction Stop } catch { }
        $build = 0; $arch = ''; $langs = @(); $ed = ''
        if ($d) {
            if ([string]$d.Version -match '^\d+\.\d+\.(\d+)') { $build = [int]$Matches[1] }
            $arch = ConvertTo-SdArchName $d.Architecture
            $langs = @($d.Languages | ForEach-Object { (([string]$_) -replace '\s*\(.*\)\s*$', '').Trim() })
            $ed = [string]$d.EditionId
        }
        $out += [pscustomobject]@{ Index = [int]$i.ImageIndex; Name = [string]$i.ImageName; EditionId = $ed; Build = $build; Arch = $arch; Languages = $langs }
    }
    return $out
}
