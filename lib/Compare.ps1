# SerwisDiag - porównanie dwóch diagnostyk tego samego komputera: przed naprawą i po niej.
# Źródłem są raporty JSON zapisywane przy każdej diagnostyce (albo wynik bieżącego skanowania).
# Wynik: raport techniczny (wszystkie różnice) i raport dla klienta (bez danych prywatnych, z opisem wykonanych czynności).

$global:SdCompareKinds = [ordered]@{
    resolved     = 'Rozwiązane'
    nonew        = 'Bez nowych zdarzeń'
    improved     = 'Złagodzone'
    worsened     = 'Pogorszone'
    remaining    = 'Bez zmian'
    new          = 'Nowe'
    notrechecked = 'Nie sprawdzono ponownie'
}

function ConvertFrom-SdJsonDate {
    # Data z raportu JSON (format 's', czas lokalny) albo $null. Nowszy PowerShell sam zamienia taki napis na DateTime.
    param($Value)
    if ($Value -is [datetime]) { return $Value }
    $d = [datetime]::MinValue
    if ($Value -and [datetime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    return $null
}

function Get-SdFindingLastEvent {
    # Czas ostatniego zdarzenia wyniku z historii zdarzeń; $null dla pozostałych wyników i raportów sprzed wersji 1.3.
    param($Finding)
    if ($null -eq $Finding -or -not $Finding.PSObject.Properties['LastEvent']) { return $null }
    return (ConvertFrom-SdJsonDate $Finding.LastEvent)
}

function Import-SdReportJson {
    # Wczytuje raport JSON programu i zwraca obiekt zgodny z Get-SdResult (Meta, Findings, Level, IsAdmin, Generated, Started).
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('Nie znaleziono pliku: ' + $Path) }
    $o = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not $o -or [string]$o.tool -ne 'SerwisDiag' -or $null -eq $o.findings) { throw ('To nie jest raport JSON programu SerwisDiag: ' + $Path) }
    $meta = @{}
    if ($o.meta) { foreach ($p in $o.meta.PSObject.Properties) { $meta[$p.Name] = $p.Value } }
    $findings = @()
    foreach ($f in @($o.findings)) {
        if ($null -eq $f) { continue }
        $cust = $null
        if ($f.PSObject.Properties['customer'] -and $f.customer) {
            $cust = [pscustomobject]@{ Title = [string]$f.customer.title; Status = [string]$f.customer.status; Value = [string]$f.customer.value; Advice = [string]$f.customer.advice }
        }
        $findings += [pscustomobject]@{
            CheckId = [string]$f.id; Category = [string]$f.category; Title = [string]$f.title; Status = [string]$f.status
            Value = [string]$f.value; Details = [string]$f.details; Advice = [string]$f.advice; Private = [bool]$f.private; Customer = $cust; Time = ''
            LastEvent = $(if ($f.PSObject.Properties['lastEvent']) { ConvertFrom-SdJsonDate $f.lastEvent } else { $null })
        }
    }
    return [pscustomobject]@{
        Tool = 'SerwisDiag'; Version = [string]$o.version; Generated = (ConvertFrom-SdJsonDate $o.generated); Started = (ConvertFrom-SdJsonDate $o.started)
        Level = [string]$o.level; IsAdmin = [bool]$o.isAdmin; Meta = $meta; Findings = $findings; Path = $Path
    }
}

function Test-SdProblemStatus {
    param([string]$Status)
    return ($Status -eq 'crit' -or $Status -eq 'warn')
}

function Get-SdFindingKeys {
    # Klucz wyniku: Id testu + tytuł (bez wielkości liter); powtórzony tytuł w jednym teście dostaje numer wystąpienia.
    param($Findings)
    $seen = @{}
    $out = New-Object System.Collections.ArrayList
    foreach ($f in @($Findings)) {
        if ($null -eq $f) { continue }
        $k = ('{0}|{1}' -f $f.CheckId, $f.Title).ToLower()
        $n = [int]$seen[$k]
        $seen[$k] = $n + 1
        if ($n -gt 0) { $k = $k + '#' + $n }
        [void]$out.Add([pscustomobject]@{ Key = $k; F = $f })
    }
    return , $out
}

function Compare-SdFindingLists {
    # Klasyfikuje każdy wynik: resolved | nonew | improved (krytyczne -> ostrzeżenie) | worsened | remaining | new | notrechecked | unchanged.
    # Problem, którego wynik zniknął, uznajemy za rozwiązany tylko wtedy, gdy ten sam test wykonano ponownie.
    # Since: początek diagnostyki przed naprawą. Wynik z historii zdarzeń, którego ostatnie zdarzenie jest wcześniejsze,
    # zostaje w raporcie tylko dlatego, że mieści się w sprawdzanym okresie (np. 30 dni) - to nonew, a nie problem bez zmian.
    param($Before, $After, $Since = $null)
    $b = Get-SdFindingKeys $Before
    $a = Get-SdFindingKeys $After
    $aMap = @{}; foreach ($x in $a) { $aMap[$x.Key] = $x.F }
    $bMap = @{}; foreach ($x in $b) { $bMap[$x.Key] = $x.F }
    $aChecks = @{}; foreach ($x in $a) { $aChecks[[string]$x.F.CheckId] = $true }
    $bChecks = @{}; foreach ($x in $b) { $bChecks[[string]$x.F.CheckId] = $true }
    $items = New-Object System.Collections.ArrayList
    foreach ($x in $b) {
        $bf = $x.F
        $af = $null
        if ($aMap.ContainsKey($x.Key)) { $af = $aMap[$x.Key] }
        $kind = 'unchanged'
        if (Test-SdProblemStatus $bf.Status) {
            if (-not $af) { $kind = $(if ($aChecks.ContainsKey([string]$bf.CheckId)) { 'resolved' } else { 'notrechecked' }) }
            elseif ($af.Status -eq 'skip' -or $af.Status -eq 'error') { $kind = 'notrechecked' }
            elseif (-not (Test-SdProblemStatus $af.Status)) { $kind = 'resolved' }
            elseif ($bf.Status -eq 'crit' -and $af.Status -eq 'warn') { $kind = 'improved' }
            elseif ($bf.Status -eq 'warn' -and $af.Status -eq 'crit') { $kind = 'worsened' }
            else { $kind = 'remaining' }
            $le = Get-SdFindingLastEvent $af
            if ($Since -and $le -and $le -le $Since -and @('improved', 'worsened', 'remaining') -contains $kind) { $kind = 'nonew' }
        } elseif ($af -and (Test-SdProblemStatus $af.Status)) { $kind = 'new' }
        $ref = $(if ($af) { $af } else { $bf })
        [void]$items.Add([pscustomobject]@{ Key = $x.Key; Kind = $kind; Category = $ref.Category; Title = $ref.Title; Before = $bf; After = $af; NotCheckedBefore = $false })
    }
    foreach ($x in $a) {
        if ($bMap.ContainsKey($x.Key)) { continue }
        $af = $x.F
        $kind = $(if (Test-SdProblemStatus $af.Status) { 'new' } else { 'unchanged' })
        [void]$items.Add([pscustomobject]@{ Key = $x.Key; Kind = $kind; Category = $af.Category; Title = $af.Title; Before = $null; After = $af; NotCheckedBefore = (-not $bChecks.ContainsKey([string]$af.CheckId)) })
    }
    return , $items
}

function Get-SdComparisonCounts {
    param($Items)
    $c = [ordered]@{}
    foreach ($k in $global:SdCompareKinds.Keys) { $c[$k] = 0 }
    foreach ($i in @($Items)) { $k = [string]$i.Kind; if ($c.Contains($k)) { $c[$k] = $c[$k] + 1 } }
    return $c
}

function Get-SdComparisonSummaryText {
    param($Counts)
    $parts = @()
    foreach ($k in $global:SdCompareKinds.Keys) { if ($Counts[$k] -gt 0) { $parts += ('{0}: {1}' -f $global:SdCompareKinds[$k].ToLower(), $Counts[$k]) } }
    if ($parts.Count -eq 0) { return 'brak różnic w problemach' }
    return ($parts -join ', ')
}

function Get-SdLevelText {
    param([string]$Level)
    if ($Level -eq 'Full') { return 'pełny' }
    return 'szybki'
}

function New-SdComparison {
    # Before / After: obiekty z Get-SdResult albo Import-SdReportJson.
    param([Parameter(Mandatory = $true)]$Before, [Parameter(Mandatory = $true)]$After, [string]$WorkDone = '')
    # zdarzenia „nowe” to te od początku diagnostyki przed naprawą (raport bez tej daty: czas jego zapisu)
    $since = $null
    if ($Before.PSObject.Properties['Started']) { $since = ConvertFrom-SdJsonDate $Before.Started }
    if (-not $since) { $since = ConvertFrom-SdJsonDate $Before.Generated }
    $tech = Compare-SdFindingLists -Before @($Before.Findings) -After @($After.Findings) -Since $since
    $cust = Compare-SdFindingLists -Before @(Get-SdCustomerFindings $Before.Findings) -After @(Get-SdCustomerFindings $After.Findings) -Since $since
    $bm = $Before.Meta; $am = $After.Meta
    $notes = @()
    $same = $null
    if ($bm['Serial'] -and $am['Serial']) { $same = ([string]$bm['Serial'] -eq [string]$am['Serial']) }
    elseif ($bm['ComputerName'] -and $am['ComputerName']) { $same = ([string]$bm['ComputerName'] -eq [string]$am['ComputerName']) }
    if ($same -eq $false) { $notes += 'Raporty pochodzą z różnych komputerów (inna nazwa lub numer seryjny) - sprawdź, czy wybrano właściwe pliki.' }
    if ($Before.Generated -and $After.Generated -and [datetime]$After.Generated -lt [datetime]$Before.Generated) { $notes += 'Raport „po naprawie” jest starszy niż raport „przed naprawą” - sprawdź kolejność plików.' }
    if ([string]$Before.Level -ne [string]$After.Level) { $notes += ('Inny tryb diagnostyki (przed: {0}, po: {1}) - część testów wykonano tylko w jednej z nich.' -f (Get-SdLevelText $Before.Level), (Get-SdLevelText $After.Level)) }
    if ([bool]$Before.IsAdmin -ne [bool]$After.IsAdmin) { $notes += 'Jedną z diagnostyk wykonano bez uprawnień administratora - część testów pominięto.' }
    if ([bool]$bm['Offline'] -ne [bool]$am['Offline']) { $notes += 'Jedną z diagnostyk wykonano w trybie bez internetu - testy łączności i wyszukiwanie sterowników pominięto.' }
    return [pscustomobject]@{
        Before = $Before; After = $After; WorkDone = $WorkDone; Generated = (Get-Date)
        Items = $tech; CustomerItems = $cust; Counts = (Get-SdComparisonCounts $tech); CustomerCounts = (Get-SdComparisonCounts $cust)
        SameComputer = $same; Notes = $notes
    }
}

function Get-SdComparisonVerdict {
    # Tytuł i poziom karty podsumowania: ile problemów sprzed naprawy rozwiązano i czy coś zostało.
    # Customer: raport dla klienta nie pokazuje wyników niesprawdzonych ponownie, więc nie liczy ich też w tytule.
    param($Items, $Counts, [switch]$Customer)
    $total = 0
    $kinds = @('resolved', 'nonew', 'improved', 'worsened', 'remaining')
    if (-not $Customer) { $kinds += 'notrechecked' }
    foreach ($k in $kinds) { $total += [int]$Counts[$k] }
    $level = 'ok'
    foreach ($i in @($Items | Where-Object { @('improved', 'worsened', 'remaining', 'new') -contains $_.Kind })) {
        if ($i.After -and $i.After.Status -eq 'crit') { $level = 'crit'; break }
        $level = 'warn'
    }
    if ($total -eq 0) { $title = 'Przed naprawą nie wykryto problemów' }
    else {
        $title = 'Rozwiązano {0} z {1} {2}' -f $Counts['resolved'], $total, $(if ($total -eq 1) { 'problemu' } else { 'problemów' })
        if ([int]$Counts['nonew'] -gt 0) { $title += ', bez nowych zdarzeń: ' + $Counts['nonew'] }
    }
    $text = switch ($level) {
        'crit' { 'Część problemów nadal wymaga pilnej interwencji - szczegóły poniżej.' }
        'warn' { 'Pozostały zalecenia do wykonania - szczegóły poniżej.' }
        default { 'Po naprawie nie wykryto problemów wymagających działania.' }
    }
    if ([int]$Counts['nonew'] -gt 0) { $text += ' Zdarzenia zapisane w dziennikach Windows przed naprawą (np. restarty, błędy dysku) od tamtej pory się nie powtórzyły.' }
    return [pscustomobject]@{ Level = $level; Title = $title; Text = $text; Total = $total }
}

function New-SdComparisonHtml {
    param([Parameter(Mandatory = $true)]$Comparison, [ValidateSet('Technical', 'Customer')][string]$Mode = 'Technical', [hashtable]$Settings = @{})
    $customer = ($Mode -eq 'Customer')
    $cmp = $Comparison
    $E = { param($t) ConvertTo-SdHtml $t }
    $items = @($(if ($customer) { $cmp.CustomerItems } else { $cmp.Items }))
    $counts = $(if ($customer) { $cmp.CustomerCounts } else { $cmp.Counts })
    $am = $cmp.After.Meta; $bm = $cmp.Before.Meta
    $mv = { param($k) if ($am[$k]) { [string]$am[$k] } elseif ($bm[$k]) { [string]$bm[$k] } else { '' } }
    $labels = @{ crit = 'KRYTYCZNE'; warn = 'UWAGA'; ok = 'OK'; info = 'INFO'; skip = 'POMINIĘTO'; error = 'BŁĄD TESTU' }
    if ($customer) { $labels = @{ crit = 'POWAŻNY PROBLEM'; warn = 'ZALECENIE'; ok = 'OK'; info = 'INFORMACJA'; skip = 'POMINIĘTO'; error = 'BŁĄD TESTU' } }
    $verdict = Get-SdComparisonVerdict -Items $items -Counts $counts -Customer:$customer
    $shop = $(if ($Settings.ShopName) { [string]$Settings.ShopName } else { 'Serwis komputerowy' })
    $title = $(if ($customer) { 'Raport z naprawy komputera' } else { 'Porównanie diagnostyki przed i po naprawie' })
    $order = @{}; $i = 0
    foreach ($c in $global:SdCategories) { $order[$c.Key] = $i; $i++ }
    $sortItems = { param($list) @($list | Sort-Object @{ Expression = { if ($_.After -and $_.After.Status -eq 'crit') { 0 } else { 1 } } }, @{ Expression = { if ($order.ContainsKey([string]$_.Category)) { $order[[string]$_.Category] } else { 99 } } }) }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!DOCTYPE html><html lang="pl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
    [void]$sb.Append('<title>' + (& $E ($title + ' - ' + (& $mv 'ComputerName'))) + '</title><style>' + (Get-SdInlineCss))
    [void]$sb.Append('.ba{display:grid;grid-template-columns:1fr 1fr;gap:6px 14px;margin-top:6px;font-size:13px}.ba div{padding:6px 9px;border-radius:7px;background:#f8f9fb}.ba b{display:block;color:#667085;font-size:11.5px;font-weight:600}')
    [void]$sb.Append('.issue.resolved{border-left-color:#12b76a;background:#fbfffc}.issue.info{border-left-color:#2e90fa}.work{white-space:pre-wrap}@media (max-width:760px){.ba{grid-template-columns:1fr}}')
    [void]$sb.Append('</style></head><body data-show="all"><div class="wrap">')

    # --- nagłówek
    [void]$sb.Append('<header class="top"><div>' + (Get-SdLogoHtml $Settings) + '<h1>' + (& $E $title) + '</h1><div class="sub">' + (& $E $shop) + '</div>')
    $contact = Join-NonEmpty @($Settings.ShopPhone, $Settings.ShopEmail, $Settings.ShopAddress) ' · '
    if ($contact) { [void]$sb.Append('<div class="contact">' + (& $E $contact) + '</div>') }
    [void]$sb.Append('</div><div class="meta">')
    [void]$sb.Append('Data: ' + (Format-Dt $cmp.Generated) + '<br>')
    foreach ($p in @(@('Zlecenie', 'Ticket'), @('Klient', 'Customer'), @('Technik', 'Technician'))) {
        $v = & $mv $p[1]
        if ($v) { [void]$sb.Append($p[0] + ': ' + (& $E $v) + '<br>') }
    }
    [void]$sb.Append('</div></header>')

    # --- podsumowanie
    [void]$sb.Append('<section class="card verdict ' + $verdict.Level + '"><div><div class="big">' + (& $E $verdict.Title) + '</div><div class="txt">' + (& $E $verdict.Text) + '</div></div><div class="counters">')
    $chips = @(@('resolved', 'ok', 'rozwiązane'), @('nonew', 'info', 'bez nowych zdarzeń'), @('improved', 'info', 'złagodzone'), @('remaining', 'warn', 'bez zmian'), @('worsened', 'crit', 'pogorszone'), @('new', 'warn', 'nowe'))
    if (-not $customer) { $chips += , @('notrechecked', 'skip', 'nie sprawdzono ponownie') }
    foreach ($ch in $chips) { if ($counts[$ch[0]] -gt 0) { [void]$sb.Append('<span class="chip ' + $ch[1] + '">' + $counts[$ch[0]] + ' ' + $ch[2] + '</span>') } }
    [void]$sb.Append('</div></section>')

    # --- wykonane czynności i uwagi
    if ($cmp.WorkDone) { [void]$sb.Append('<section class="card"><h2>Wykonane czynności</h2><div class="work">' + (& $E $cmp.WorkDone) + '</div></section>') }
    if (-not $customer -and @($cmp.Notes).Count -gt 0) {
        [void]$sb.Append('<section class="card"><h2>Uwagi do porównania</h2><ul>')
        foreach ($n in $cmp.Notes) { [void]$sb.Append('<li>' + (& $E $n) + '</li>') }
        [void]$sb.Append('</ul></section>')
    }

    # --- dane komputera i daty diagnostyk
    [void]$sb.Append('<section class="card"><h2>Komputer</h2><div class="facts">')
    $facts = @(@('Komputer', (& $mv 'Model')), @('System', (& $mv 'OS')), @('Procesor', (& $mv 'Cpu')), @('Pamięć RAM', (& $mv 'Ram')), @('Dyski', (& $mv 'Disks')))
    $facts += , @('Diagnostyka przed naprawą', (Format-Dt $cmp.Before.Generated))
    $facts += , @('Diagnostyka po naprawie', (Format-Dt $cmp.After.Generated))
    if (-not $customer) {
        $facts += , @('Nazwa komputera', (& $mv 'ComputerName'))
        $facts += , @('Tryb (przed / po)', ('{0} / {1}' -f (Get-SdLevelText $cmp.Before.Level), (Get-SdLevelText $cmp.After.Level)))
    }
    foreach ($f in $facts) { if ($f[1] -and $f[1] -ne '-') { [void]$sb.Append('<div><b>' + (& $E $f[0]) + '</b><span>' + (& $E $f[1]) + '</span></div>') } }
    [void]$sb.Append('</div></section>')

    # --- sekcje z problemami
    $card = {
        param($it, [string]$cls, [bool]$showAdvice)
        $st = $(if ($it.After) { [string]$it.After.Status } else { [string]$it.Before.Status })
        $badgeSt = $(if ($cls -eq 'resolved') { 'ok' } elseif ($cls -eq 'nonew') { 'info' } else { $st })
        $badge = $(if ($cls -eq 'resolved') { 'ROZWIĄZANE' } elseif ($cls -eq 'nonew') { 'BEZ NOWYCH ZDARZEŃ' } else { $labels[$st] })
        $h = '<div class="issue ' + $(if ($cls -eq 'resolved') { 'resolved' } elseif ($cls -eq 'nonew') { 'info' } else { $st }) + '"><div class="h"><span class="badge ' + $badgeSt + '">' + $badge + '</span><b>' + (& $E $it.Title) + '</b><span style="color:#667085;font-size:12px">' + (& $E (Get-SdCategoryLabel $it.Category)) + '</span></div>'
        $bv = $(if ($it.Before) { [string]$it.Before.Value } elseif ($it.NotCheckedBefore) { 'nie sprawdzano' } else { 'bez problemu' })
        $av = $(if ($it.After) { [string]$it.After.Value } elseif ($cls -eq 'resolved') { 'problem nie występuje' } else { 'nie sprawdzono' })
        $h += '<div class="ba"><div><b>Przed naprawą</b>' + (& $E $bv) + '</div><div><b>Po naprawie</b>' + (& $E $av) + '</div></div>'
        if ($showAdvice -and $it.After -and $it.After.Advice) { $h += '<div class="adv"><b>Zalecenie:</b> ' + (& $E $it.After.Advice) + '</div>' }
        if (-not $customer -and $it.After -and $it.After.Details -and $cls -ne 'resolved') { $h += '<details><summary>szczegóły</summary><div class="det">' + (& $E $it.After.Details) + '</div></details>' }
        return ($h + '</div>')
    }
    $sections = @(
        @{ Kinds = @('resolved'); Title = 'Rozwiązane problemy'; Cls = 'resolved'; Advice = $false }
        @{ Kinds = @('nonew'); Title = 'Bez nowych zdarzeń od poprzedniej diagnostyki'; Cls = 'nonew'; Advice = $false
           Note = 'Te wyniki opisują zdarzenia zapisane w dziennikach Windows przed naprawą. Zostają w raporcie przez okres, który sprawdza program (np. 30 dni), ale od diagnostyki przed naprawą nie wystąpiły ponownie.' }
        @{ Kinds = @('improved'); Title = 'Złagodzone problemy'; Cls = 'improved'; Advice = $true }
        @{ Kinds = @('worsened', 'remaining'); Title = $(if ($customer) { 'Nadal wymagają uwagi' } else { 'Bez poprawy (nadal wymagają uwagi)' }); Cls = 'remaining'; Advice = $true }
        @{ Kinds = @('new'); Title = $(if ($customer) { 'Wykryte podczas kontroli po naprawie' } else { 'Nowe problemy (nie było ich przed naprawą)' }); Cls = 'new'; Advice = $true }
    )
    if (-not $customer) { $sections += @{ Kinds = @('notrechecked'); Title = 'Nie sprawdzono ponownie (test pominięty lub niewykonany po naprawie)'; Cls = 'notrechecked'; Advice = $false } }
    foreach ($s in $sections) {
        $list = @(& $sortItems @($items | Where-Object { $s.Kinds -contains $_.Kind }))
        if ($list.Count -eq 0) { continue }
        [void]$sb.Append('<section class="card"><h2>' + (& $E $s.Title) + ' (' + $list.Count + ')</h2>')
        if ($s.Note) { [void]$sb.Append('<div class="txt">' + (& $E $s.Note) + '</div>') }
        foreach ($it in $list) { [void]$sb.Append((& $card $it $s.Cls $s.Advice)) }
        [void]$sb.Append('</section>')
    }
    if (@($items | Where-Object { $_.Kind -ne 'unchanged' }).Count -eq 0) {
        [void]$sb.Append('<section class="card"><div class="txt">Ani przed, ani po naprawie nie wykryto problemów wymagających działania.</div></section>')
    }

    # --- technik: pozostałe zmiany wartości (np. wolne miejsce, wyniki testów wydajności)
    if (-not $customer) {
        $changed = @($items | Where-Object { $_.Kind -eq 'unchanged' -and $_.Before -and $_.After -and [string]$_.Before.Value -ne [string]$_.After.Value } | Select-Object -First 120)
        if ($changed.Count -gt 0) {
            [void]$sb.Append('<section class="card"><details class="tbl"><summary>Inne zmienione wyniki (' + $changed.Count + ')</summary><div class="tw"><table><thead><tr><th>Test</th><th>Przed</th><th>Po</th></tr></thead><tbody>')
            foreach ($it in $changed) { [void]$sb.Append('<tr><td class="sm">' + (& $E $it.Title) + '</td><td class="sm">' + (& $E $it.Before.Value) + '</td><td class="sm">' + (& $E $it.After.Value) + '</td></tr>') }
            [void]$sb.Append('</tbody></table></div></details></section>')
        }
    }
    $foot = $(if ($customer) { 'Raport porównuje wyniki diagnostyki wykonanej przed naprawą i po niej. Opiera się na odczytach systemu w chwili badania.' } else { 'Porównanie: ' + (Get-SdComparisonSummaryText $counts) + '.' })
    [void]$sb.Append('<footer>' + (& $E $foot) + ' Wygenerowano programem SerwisDiag ' + (& $E $global:SdVersion) + '.</footer>')
    [void]$sb.Append('</div><script>' + $global:SdReportJs + '</script></body></html>')
    return $sb.ToString()
}

function Save-SdComparisonReports {
    # Zapisuje porównanie (techniczne i dla klienta); zwraca ścieżki: Technical, Customer.
    param([Parameter(Mandatory = $true)]$Comparison, [hashtable]$Settings = @{}, [Parameter(Mandatory = $true)][string]$OutDir)
    $m = $Comparison.After.Meta
    $base = Join-NonEmpty @($m['Ticket'], $m['ComputerName'], (Get-Date).ToString('yyyyMMdd-HHmm')) '_'
    $base = ($base -replace '[\\/:*?"<>|\s]+', '_') + '_porownanie'
    if (-not (Test-Path -LiteralPath $OutDir)) { [void](New-Item -ItemType Directory -Path $OutDir -Force) }
    $bom = New-Object System.Text.UTF8Encoding($true)
    $paths = [ordered]@{}
    $paths['Technical'] = Join-Path $OutDir ($base + '_techniczne.html')
    [System.IO.File]::WriteAllText($paths['Technical'], (New-SdComparisonHtml -Comparison $Comparison -Mode Technical -Settings $Settings), $bom)
    $paths['Customer'] = Join-Path $OutDir ($base + '_klient.html')
    [System.IO.File]::WriteAllText($paths['Customer'], (New-SdComparisonHtml -Comparison $Comparison -Mode Customer -Settings $Settings), $bom)
    return $paths
}

function Find-SdReportJson {
    # Najnowszy raport JSON tego komputera w folderze raportów (najpierw z tym samym numerem zlecenia), inny niż $Exclude.
    # Nazwy plików mają postać [zlecenie_]komputer_rrrrMMdd-ggmm.json - wystarczy dopasować nazwę, bez czytania plików.
    param([string]$Dir, [string]$ComputerName, [string]$Ticket = '', [string[]]$Exclude = @())
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return '' }
    $pc = ([string]$ComputerName) -replace '[\\/:*?"<>|\s]+', '_'
    $ex = @($Exclude | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLower() })
    $files = @(Get-ChildItem -LiteralPath $Dir -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object {
            $ex -notcontains $_.FullName.ToLower() -and ($_.BaseName -like ($pc + '_*') -or $_.BaseName -like ('*_' + $pc + '_*'))
        } | Sort-Object LastWriteTime -Descending)
    if ($files.Count -eq 0) { return '' }
    if ($Ticket) {
        $t = $Ticket -replace '[\\/:*?"<>|\s]+', '_'
        $same = @($files | Where-Object { $_.BaseName -like ($t + '_*') })
        if ($same.Count -gt 0) { return $same[0].FullName }
    }
    return $files[0].FullName
}
