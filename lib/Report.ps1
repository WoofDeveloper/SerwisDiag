# SerwisDiag - generowanie raportów: HTML (techniczny i dla klienta), JSON, TXT

function ConvertTo-SdHtml {
    param($Text)
    if ($null -eq $Text) { return '' }
    $s = [System.Net.WebUtility]::HtmlEncode([string]$Text)
    # adresy https:// stają się linkami (np. Katalog Microsoft Update, strona producenta); tylko https, po zakodowaniu tekstu
    $s = [regex]::Replace($s, 'https://[^\s<>"]+', [System.Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $u = $m.Value; $tail = ''
            while ($u.Length -gt 8 -and '.,;:)'.Contains([string]$u[$u.Length - 1])) { $tail = [string]$u[$u.Length - 1] + $tail; $u = $u.Substring(0, $u.Length - 1) }
            '<a href="' + $u + '" target="_blank" rel="noopener noreferrer">' + $u + '</a>' + $tail
        })
    return ($s -replace "`r?`n", '<br>')
}

function ConvertTo-SdHtmlCell {
    # Komórka tabeli: sam adres https wyświetlamy jako krótki link „otwórz”.
    param($Value)
    if ($Value -is [string] -and $Value -match '^https://\S+$') {
        return ('<a href="' + [System.Net.WebUtility]::HtmlEncode($Value) + '" target="_blank" rel="noopener noreferrer">otwórz</a>')
    }
    return (ConvertTo-SdHtml $Value)
}

function Get-SdCounts {
    param($Findings)
    $c = [ordered]@{ crit = 0; warn = 0; info = 0; ok = 0; skip = 0; error = 0 }
    foreach ($f in $Findings) { if ($c.Contains([string]$f.Status)) { $c[[string]$f.Status] = $c[[string]$f.Status] + 1 } }
    return $c
}

function Get-SdVerdict {
    param($Counts)
    if ($Counts['crit'] -gt 0) {
        return [pscustomobject]@{ Level = 'crit'; Title = 'Wykryto poważne problemy'; Text = 'Komputer wymaga interwencji serwisowej - szczegóły i zalecenia poniżej.' }
    }
    if ($Counts['warn'] -gt 0) {
        return [pscustomobject]@{ Level = 'warn'; Title = 'Wykryto zalecenia do wykonania'; Text = 'Komputer działa, ale warto wykonać zalecone czynności serwisowe.' }
    }
    return [pscustomobject]@{ Level = 'ok'; Title = 'Nie wykryto problemów'; Text = 'Wszystkie wykonane testy zakończyły się pomyślnie.' }
}

function Get-SdCustomerFindings {
    # Wyniki w wersji dla klienta: bez danych prywatnych, a gdy test podał osobny opis dla klienta (Customer) -
    # z tym opisem zamiast technicznego i bez szczegółów.
    param($Findings)
    $out = @()
    foreach ($f in @($Findings)) {
        if ($null -eq $f -or $f.Private) { continue }
        $c = $null
        if ($f.PSObject.Properties['Customer']) { $c = $f.Customer }
        if ($c) {
            $ctitle = ''
            if ($c.PSObject.Properties['Title']) { $ctitle = [string]$c.Title }
            $out += [pscustomobject]@{
                CheckId = $f.CheckId; Category = $f.Category; Title = $(if ($ctitle) { $ctitle } else { $f.Title })
                Status = $(if ($c.Status) { [string]$c.Status } else { $f.Status }); Value = $(if ($c.Value) { [string]$c.Value } else { $f.Value })
                Details = ''; Advice = [string]$c.Advice; Private = $false; Customer = $null; Time = $f.Time
                LastEvent = $(if ($f.PSObject.Properties['LastEvent']) { $f.LastEvent } else { $null })
            }
        } else { $out += $f }
    }
    return $out
}

function Get-SdResult {
    $sd = $global:SD
    $findings = @($sd.Findings.ToArray())
    $tables = @($sd.Tables.ToArray())
    $counts = Get-SdCounts $findings
    # kopia metadanych pod blokadą (w GUI wątek skanujący może w tym czasie dopisywać wartości)
    $meta = @{}
    $root = $sd.Meta.SyncRoot
    [System.Threading.Monitor]::Enter($root)
    try { foreach ($k in @($sd.Meta.Keys)) { $meta[$k] = $sd.Meta[$k] } }
    finally { [System.Threading.Monitor]::Exit($root) }
    return [pscustomobject]@{
        Tool = 'SerwisDiag'; Version = $global:SdVersion; Generated = (Get-Date); Started = $sd.Started; Finished = $sd.Finished
        Level = $sd.Level; Tests = @($sd.Tests); IsAdmin = [bool]$sd.IsAdmin
        Meta = $meta; Counts = $counts; Verdict = (Get-SdVerdict $counts)
        Findings = $findings; Tables = $tables; Timings = @($sd.Timings.ToArray()); Log = @($sd.Log.ToArray())
    }
}

$global:SdReportCss = @'
:root{--bg:#f3f5f9;--card:#fff;--text:#1b2433;--muted:#667085;--line:#e4e7ec;--accent:#0f6cbd;
--crit:#b42318;--critbg:#fee4e2;--warn:#93370d;--warnbg:#fef0c7;--ok:#067647;--okbg:#d1fadf;--info:#175cd3;--infobg:#e0eaff;--skip:#475467;--skipbg:#eaecf0;--err:#6941c6;--errbg:#ebe9fe}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:14px/1.5 "Segoe UI",system-ui,-apple-system,Roboto,Arial,sans-serif}
.wrap{max-width:1120px;margin:0 auto;padding:22px 18px 60px}
header.top{display:flex;gap:18px;align-items:center;justify-content:space-between;padding:20px 24px;background:linear-gradient(135deg,#0a3a66,#0f6cbd);color:#fff;border-radius:14px}
header.top h1{margin:0;font-size:22px;font-weight:650;letter-spacing:.2px}
header.top .sub{opacity:.85;font-size:13px;margin-top:2px}
header.top img{max-height:54px;max-width:160px;background:#fff;border-radius:8px;padding:4px}
.meta{font-size:12.5px;opacity:.92;text-align:right;line-height:1.55}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:18px 20px;margin-top:16px;box-shadow:0 1px 2px rgba(16,24,40,.04)}
.card h2{margin:0 0 12px;font-size:16px}
.verdict{display:flex;gap:18px;align-items:center;flex-wrap:wrap;border-left:8px solid var(--ok)}
.verdict.crit{border-left-color:var(--crit)}.verdict.warn{border-left-color:#f79009}
.verdict .big{font-size:22px;font-weight:700}.verdict.crit .big{color:var(--crit)}.verdict.warn .big{color:var(--warn)}.verdict.ok .big{color:var(--ok)}
.verdict .txt{color:var(--muted);margin-top:2px}
.counters{display:flex;gap:8px;flex-wrap:wrap;margin-left:auto}
.chip{padding:5px 12px;border-radius:999px;font-weight:600;font-size:12.5px;white-space:nowrap}
.chip.crit,.badge.crit{background:var(--critbg);color:var(--crit)}.chip.warn,.badge.warn{background:var(--warnbg);color:var(--warn)}
.chip.ok,.badge.ok{background:var(--okbg);color:var(--ok)}.chip.info,.badge.info{background:var(--infobg);color:var(--info)}
.chip.skip,.badge.skip{background:var(--skipbg);color:var(--skip)}.chip.error,.badge.error{background:var(--errbg);color:var(--err)}
.facts{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:2px 28px}
.facts div{display:flex;gap:10px;padding:6px 0;border-bottom:1px dashed var(--line)}
.facts b{min-width:130px;color:var(--muted);font-weight:600}.facts span{word-break:break-word}
.issue{border:1px solid var(--line);border-left:6px solid var(--warn);border-radius:10px;padding:12px 14px;margin:10px 0;background:#fff}
.issue.crit{border-left-color:var(--crit);background:#fffafa}.issue.warn{border-left-color:#f79009;background:#fffdf7}
.issue .h{display:flex;gap:10px;align-items:baseline;flex-wrap:wrap}.issue .h b{font-size:14.5px}
.issue .v{color:var(--muted);margin-top:3px}.adv{margin-top:6px;padding:7px 10px;background:#f4f8ff;border-radius:8px;border:1px solid #d6e4ff}
.badge{display:inline-block;padding:2px 9px;border-radius:6px;font-size:11px;font-weight:700;letter-spacing:.3px;white-space:nowrap}
nav.toc{display:flex;gap:8px;flex-wrap:wrap;margin-top:16px}
nav.toc a{text-decoration:none;color:var(--text);background:#fff;border:1px solid var(--line);padding:5px 12px;border-radius:999px;font-size:13px}
nav.toc a:hover{border-color:var(--accent);color:var(--accent)}
nav.toc i{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;background:var(--ok)}
nav.toc i.crit{background:var(--crit)}nav.toc i.warn{background:#f79009}nav.toc i.info{background:var(--info)}
.tools{display:flex;gap:8px;flex-wrap:wrap;margin-top:16px;align-items:center}
.tools button{font:inherit;padding:6px 12px;border:1px solid var(--line);background:#fff;border-radius:8px;cursor:pointer}
.tools button.on,.tools button:hover{border-color:var(--accent);color:var(--accent)}
table{width:100%;border-collapse:collapse;font-size:13px}
th{text-align:left;color:var(--muted);font-weight:600;padding:6px 8px;border-bottom:2px solid var(--line);background:#fafbfc;position:sticky;top:0}
td{padding:7px 8px;border-bottom:1px solid var(--line);vertical-align:top}
table.f td.st{width:98px}table.f td.t{width:27%;font-weight:600}table.f td.v{word-break:break-word}
details{margin-top:4px}summary{cursor:pointer;color:var(--accent);font-size:12.5px}
.det{margin-top:4px;padding:8px 10px;background:#f8f9fb;border-radius:8px;color:#344054;font-size:12.5px}
.tw{overflow:auto;max-height:420px;margin-top:6px;border:1px solid var(--line);border-radius:8px}
details.tbl{margin-top:10px}details.tbl>summary{font-weight:600;font-size:13px}
td.sm{font-size:12px}h3{margin:18px 0 6px;font-size:14px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px}
footer{margin-top:26px;color:var(--muted);font-size:12px}
.contact{margin-top:10px;font-size:13px;color:#fff;opacity:.95}
body[data-show=problems] tr.f.ok,body[data-show=problems] tr.f.info,body[data-show=problems] tr.f.skip{display:none}
body[data-show=crit] tr.f.ok,body[data-show=crit] tr.f.info,body[data-show=crit] tr.f.skip,body[data-show=crit] tr.f.warn{display:none}
ol.todo{padding-left:20px;margin:6px 0}ol.todo li{margin:6px 0}
@media (max-width:760px){.facts{grid-template-columns:1fr}.counters{margin-left:0}header.top{flex-direction:column;align-items:flex-start}.meta{text-align:left}}
@page{size:A4;margin:12mm}
@media print{body{background:#fff;-webkit-print-color-adjust:exact;print-color-adjust:exact}.wrap{padding:0}.card,.issue{box-shadow:none;break-inside:avoid}.tools,nav.toc{display:none}.tw{max-height:none;overflow:visible}tr{break-inside:avoid}}
'@

$global:SdReportJs = @'
(function(){
 var b=document.body;
 function setShow(v){b.setAttribute('data-show',v);var bs=document.querySelectorAll('.tools button[data-show]');for(var i=0;i<bs.length;i++){bs[i].className=(bs[i].getAttribute('data-show')===v)?'on':'';}}
 var bs=document.querySelectorAll('.tools button[data-show]');
 for(var i=0;i<bs.length;i++){bs[i].onclick=function(){setShow(this.getAttribute('data-show'));};}
 var ex=document.getElementById('expand');
 if(ex){ex.onclick=function(){var d=document.querySelectorAll('details');var open=ex.getAttribute('data-open')!=='1';for(var i=0;i<d.length;i++){d[i].open=open;}ex.setAttribute('data-open',open?'1':'0');ex.textContent=open?'Zwiń szczegóły':'Rozwiń szczegóły';};}
 window.addEventListener('beforeprint',function(){var d=document.querySelectorAll('.card details:not(.tbl)');for(var i=0;i<d.length;i++){d[i].open=true;}});
})();
'@

function Get-SdInlineCss {
    # Zmienne CSS (var(--x)) nie działają w IE11 (domyślna przeglądarka Windows 8.1) - wstawiamy ich wartości na stałe.
    $css = $global:SdReportCss
    if ($css -match ':root\{([^}]*)\}') {
        $rootBody = $Matches[1]
        foreach ($m in [regex]::Matches($rootBody, '--([a-z0-9-]+):([^;]+);?')) {
            $css = $css.Replace('var(--' + $m.Groups[1].Value + ')', $m.Groups[2].Value.Trim())
        }
    }
    return $css
}

function Get-SdLogoHtml {
    # Logo serwisu osadzone w raporcie (data URI), gdy plik istnieje i jest mniejszy niż 400 KB.
    param([hashtable]$Settings = @{})
    if (-not $Settings.LogoPath -or -not (Test-Path -LiteralPath $Settings.LogoPath)) { return '' }
    try {
        $fi = Get-Item -LiteralPath $Settings.LogoPath
        if ($fi.Length -ge 400KB) { return '' }
        $mime = switch ($fi.Extension.ToLower()) { '.png' { 'image/png' } '.jpg' { 'image/jpeg' } '.jpeg' { 'image/jpeg' } '.svg' { 'image/svg+xml' } '.gif' { 'image/gif' } default { '' } }
        if ($mime) { return ('<img alt="" src="data:' + $mime + ';base64,' + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fi.FullName)) + '">') }
    } catch { }
    return ''
}

function New-SdHtmlReport {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [ValidateSet('Technical', 'Customer')][string]$Mode = 'Technical',
        [hashtable]$Settings = @{}
    )
    $customer = ($Mode -eq 'Customer')
    $anon = [bool]($Result.PSObject.Properties['Anonymous'] -and $Result.Anonymous)
    $sb = New-Object System.Text.StringBuilder
    $E = { param($t) ConvertTo-SdHtml $t }
    $css = Get-SdInlineCss
    $meta = $Result.Meta

    $labels = @{ crit = 'KRYTYCZNE'; warn = 'UWAGA'; ok = 'OK'; info = 'INFO'; skip = 'POMINIĘTO'; error = 'BŁĄD TESTU' }
    if ($customer) { $labels = @{ crit = 'POWAŻNY PROBLEM'; warn = 'ZALECENIE'; ok = 'OK'; info = 'INFORMACJA'; skip = 'POMINIĘTO'; error = 'BŁĄD TESTU' } }

    # które wyniki pokazujemy
    $findings = @($Result.Findings)
    if ($customer) { $findings = @(Get-SdCustomerFindings $findings | Where-Object { $_.Status -ne 'error' -and $_.Status -ne 'skip' }) }
    $tables = @($Result.Tables | Where-Object { -not ($customer -and $_.Private) })
    $counts = Get-SdCounts $findings
    $verdict = Get-SdVerdict $counts
    $shop = if ($Settings.ShopName) { [string]$Settings.ShopName } else { 'Serwis komputerowy' }
    $title = if ($customer) { 'Raport z diagnostyki komputera' } else { 'Raport diagnostyczny komputera' }
    if ($anon) {
        $title = 'Raport diagnostyczny (anonimowy)'
        $shop = 'Bez nazwy komputera i kont, numerów seryjnych, kluczy, adresów IP/MAC i danych klienta'
        $Settings = @{}
    }
    $pcName = if ($meta['Model']) { [string]$meta['Model'] } else { [string]$meta['ComputerName'] }

    [void]$sb.Append('<!DOCTYPE html><html lang="pl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
    [void]$sb.Append('<title>' + (& $E ($title + ' - ' + $meta['ComputerName'])) + '</title><style>' + $css + '</style></head>')
    [void]$sb.Append('<body data-show="all"><div class="wrap">')

    # --- nagłówek
    $logo = Get-SdLogoHtml $Settings
    [void]$sb.Append('<header class="top"><div>' + $logo + '<h1>' + (& $E $title) + '</h1><div class="sub">' + (& $E $shop) + '</div>')
    $contact = Join-NonEmpty @($Settings.ShopPhone, $Settings.ShopEmail, $Settings.ShopAddress) ' · '
    if ($contact) { [void]$sb.Append('<div class="contact">' + (& $E $contact) + '</div>') }
    [void]$sb.Append('</div><div class="meta">')
    [void]$sb.Append('Data: ' + (Format-Dt $Result.Generated) + '<br>')
    if ($meta['Ticket']) { [void]$sb.Append('Zlecenie: ' + (& $E $meta['Ticket']) + '<br>') }
    if ($meta['Customer']) { [void]$sb.Append('Klient: ' + (& $E $meta['Customer']) + '<br>') }
    if ($meta['Technician']) { [void]$sb.Append('Technik: ' + (& $E $meta['Technician']) + '<br>') }
    [void]$sb.Append('</div></header>')

    # --- werdykt
    $cnt = $counts
    [void]$sb.Append('<section class="card verdict ' + $verdict.Level + '"><div><div class="big">' + (& $E $verdict.Title) + '</div><div class="txt">' + (& $E $verdict.Text) + '</div></div><div class="counters">')
    if ($cnt['crit'] -gt 0) {
        $t = $(if ($customer) { Format-Count $cnt['crit'] 'poważny problem' 'poważne problemy' 'poważnych problemów' } else { Format-Count $cnt['crit'] 'krytyczny' 'krytyczne' 'krytycznych' })
        [void]$sb.Append('<span class="chip crit">' + (& $E $t) + '</span>')
    }
    if ($cnt['warn'] -gt 0) {
        $t = $(if ($customer) { Format-Count $cnt['warn'] 'zalecenie' 'zalecenia' 'zaleceń' } else { Format-Count $cnt['warn'] 'ostrzeżenie' 'ostrzeżenia' 'ostrzeżeń' })
        [void]$sb.Append('<span class="chip warn">' + (& $E $t) + '</span>')
    }
    [void]$sb.Append('<span class="chip ok">' + $cnt['ok'] + ' w porządku</span>')
    if (-not $customer) {
        [void]$sb.Append('<span class="chip info">' + (& $E (Format-Count $cnt['info'] 'informacja' 'informacje' 'informacji')) + '</span>')
        if ($cnt['skip'] -gt 0) { [void]$sb.Append('<span class="chip skip">' + (& $E (Format-Count $cnt['skip'] 'pominięty' 'pominięte' 'pominiętych')) + '</span>') }
        if ($cnt['error'] -gt 0) { [void]$sb.Append('<span class="chip error">' + (& $E (Format-Count $cnt['error'] 'błąd testu' 'błędy testu' 'błędów testu')) + '</span>') }
    }
    [void]$sb.Append('</div></section>')

    # --- dane komputera
    $facts = New-Object System.Collections.ArrayList
    $addFact = { param($k, $v) if ($v) { [void]$facts.Add(@($k, [string]$v)) } }
    & $addFact 'Komputer' $meta['Model']
    & $addFact 'System' $meta['OS']
    & $addFact 'Procesor' $meta['Cpu']
    & $addFact 'Pamięć RAM' $meta['Ram']
    & $addFact 'Dyski' $meta['Disks']
    & $addFact 'Grafika' $meta['Gpu']
    if ($meta['BatteryHealth']) { & $addFact 'Kondycja baterii' ('{0}% pojemności fabrycznej' -f $meta['BatteryHealth']) }
    if ($meta['Stability']) { & $addFact 'Indeks stabilności' ('{0} / 10' -f $meta['Stability']) }
    & $addFact 'BIOS / UEFI' $meta['Bios']
    if (-not $customer) {
        & $addFact 'Nazwa komputera' $meta['ComputerName']
        & $addFact 'Numer seryjny' $meta['Serial']
        & $addFact 'Płyta główna' $meta['Board']
        & $addFact 'Typ obudowy' $meta['Chassis']
        & $addFact 'Użytkownik' $meta['UserName']
        $modeTxt = if ($Result.Level -eq 'Full') { 'pełna' } else { 'szybka' }
        if (@($Result.Tests).Count -gt 0) { $modeTxt += ' + testy obciążeniowe' }
        if ($meta['Offline']) { $modeTxt += ', bez internetu' }
        & $addFact 'Tryb diagnostyki' $modeTxt
        & $addFact 'Uprawnienia' $(if ($Result.IsAdmin) { 'administrator' } else { 'zwykły użytkownik (część testów pominięto)' })
        if ($Result.Started -and $Result.Finished) { & $addFact 'Czas skanowania' ((Format-Span ([datetime]$Result.Finished - [datetime]$Result.Started))) }
        & $addFact 'Pliki programu' $meta['Integrity']
    }
    if ($meta['DeviceNote']) { & $addFact 'Opis zgłoszenia' $meta['DeviceNote'] }
    if ($meta['Offline'] -and $customer) { & $addFact 'Internet' 'nie sprawdzano (diagnostyka bez dostępu do internetu)' }
    [void]$sb.Append('<section class="card"><h2>' + $(if ($customer -or $anon) { 'Dane komputera' } else { 'Dane komputera i zlecenia' }) + '</h2><div class="facts">')
    foreach ($f in $facts) { [void]$sb.Append('<div><b>' + (& $E $f[0]) + '</b><span>' + (& $E $f[1]) + '</span></div>') }
    [void]$sb.Append('</div>')
    if ($meta['Notes'] -and -not $customer) { [void]$sb.Append('<h3>Uwagi technika</h3><div class="det">' + (& $E $meta['Notes']) + '</div>') }
    [void]$sb.Append('</section>')

    # --- problemy i zalecenia
    $order = @{}; $i = 0
    foreach ($c in $global:SdCategories) { $order[$c.Key] = $i; $i++ }
    $issues = @($findings | Where-Object { $_.Status -eq 'crit' -or $_.Status -eq 'warn' } |
            Sort-Object @{ Expression = { if ($_.Status -eq 'crit') { 0 } else { 1 } } }, @{ Expression = { if ($order.ContainsKey($_.Category)) { $order[$_.Category] } else { 99 } } })
    [void]$sb.Append('<section class="card"><h2>' + $(if ($customer) { 'Co wykryto i co zalecamy' } else { 'Wykryte problemy i zalecenia' }) + '</h2>')
    if ($issues.Count -eq 0) {
        [void]$sb.Append('<div class="txt">Nie wykryto problemów wymagających działania.</div>')
    } else {
        foreach ($f in $issues) {
            [void]$sb.Append('<div class="issue ' + $f.Status + '"><div class="h"><span class="badge ' + $f.Status + '">' + $labels[[string]$f.Status] + '</span><b>' + (& $E $f.Title) + '</b><span class="sm" style="color:#667085;font-size:12px">' + (& $E (Get-SdCategoryLabel $f.Category)) + '</span></div>')
            if ($f.Value) { [void]$sb.Append('<div class="v">' + (& $E $f.Value) + '</div>') }
            if ($f.Advice) { [void]$sb.Append('<div class="adv"><b>Zalecenie:</b> ' + (& $E $f.Advice) + '</div>') }
            if ($f.Details -and -not $customer) { [void]$sb.Append('<details><summary>szczegóły</summary><div class="det">' + (& $E $f.Details) + '</div></details>') }
            [void]$sb.Append('</div>')
        }
    }
    [void]$sb.Append('</section>')

    if ($customer) {
        # --- zakres kontroli (dla klienta)
        [void]$sb.Append('<section class="card"><h2>Co sprawdziliśmy</h2><table><thead><tr><th>Obszar</th><th>Liczba testów</th><th>Wynik</th></tr></thead><tbody>')
        foreach ($c in $global:SdCategories) {
            $cf = @($findings | Where-Object { $_.Category -eq $c.Key })
            if ($cf.Count -eq 0) { continue }
            $w = 'ok'
            if (@($cf | Where-Object { $_.Status -eq 'crit' }).Count -gt 0) { $w = 'crit' } elseif (@($cf | Where-Object { $_.Status -eq 'warn' }).Count -gt 0) { $w = 'warn' }
            $wl = switch ($w) { 'crit' { 'wymaga działania' } 'warn' { 'zalecenia' } default { 'w porządku' } }
            [void]$sb.Append('<tr><td>' + (& $E $c.Label) + '</td><td>' + $cf.Count + '</td><td><span class="badge ' + $w + '">' + $wl + '</span></td></tr>')
        }
        [void]$sb.Append('</tbody></table></section>')
        [void]$sb.Append('<footer>Raport ma charakter diagnostyczny i opiera się na odczytach systemu w chwili badania. Przed wykonaniem napraw zalecamy kopię zapasową danych. ')
        [void]$sb.Append('Wygenerowano programem SerwisDiag ' + (& $E $Result.Version) + '.</footer>')
    } else {
        # --- spis kategorii
        [void]$sb.Append('<nav class="toc">')
        foreach ($c in $global:SdCategories) {
            $cf = @($findings | Where-Object { $_.Category -eq $c.Key })
            $ct = @($tables | Where-Object { $_.Category -eq $c.Key })
            if ($cf.Count -eq 0 -and $ct.Count -eq 0) { continue }
            $w = 'ok'
            if (@($cf | Where-Object { $_.Status -eq 'crit' }).Count -gt 0) { $w = 'crit' } elseif (@($cf | Where-Object { $_.Status -eq 'warn' }).Count -gt 0) { $w = 'warn' }
            [void]$sb.Append('<a href="#cat-' + $c.Key + '"><i class="' + $w + '"></i>' + (& $E $c.Label) + '</a>')
        }
        [void]$sb.Append('</nav><div class="tools"><span style="color:#667085">Pokaż:</span><button class="on" data-show="all">wszystko</button><button data-show="problems">tylko problemy</button><button data-show="crit">tylko krytyczne</button><button id="expand" data-open="0">Rozwiń szczegóły</button></div>')

        # --- kategorie
        foreach ($c in $global:SdCategories) {
            $cf = @($findings | Where-Object { $_.Category -eq $c.Key })
            $ct = @($tables | Where-Object { $_.Category -eq $c.Key })
            if ($cf.Count -eq 0 -and $ct.Count -eq 0) { continue }
            [void]$sb.Append('<section class="card" id="cat-' + $c.Key + '"><h2>' + (& $E $c.Label) + '</h2>')
            if ($cf.Count -gt 0) {
                [void]$sb.Append('<table class="f"><tbody>')
                foreach ($f in $cf) {
                    [void]$sb.Append('<tr class="f ' + $f.Status + '"><td class="st"><span class="badge ' + $f.Status + '">' + $labels[[string]$f.Status] + '</span></td><td class="t">' + (& $E $f.Title) + $(if ($f.Private) { ' <span class="badge skip" title="Dane widoczne tylko w raporcie technicznym">prywatne</span>' } else { '' }) + '</td><td class="v">' + (& $E $f.Value))
                    if ($f.Advice -and ($f.Status -eq 'crit' -or $f.Status -eq 'warn')) { [void]$sb.Append('<div class="adv"><b>Zalecenie:</b> ' + (& $E $f.Advice) + '</div>') }
                    elseif ($f.Advice) { [void]$sb.Append('<details><summary>zalecenie</summary><div class="det">' + (& $E $f.Advice) + '</div></details>') }
                    if ($f.Details) { [void]$sb.Append('<details><summary>szczegóły</summary><div class="det">' + (& $E $f.Details) + '</div></details>') }
                    [void]$sb.Append('</td></tr>')
                }
                [void]$sb.Append('</tbody></table>')
            }
            foreach ($t in $ct) {
                [void]$sb.Append('<details class="tbl"><summary>' + (& $E $t.Name) + ' (' + $t.Rows.Count + ')' + $(if ($t.Private) { ' <span class="badge skip" title="Dane widoczne tylko w raporcie technicznym">prywatne</span>' } else { '' }) + '</summary>')
                if ($t.Note) { [void]$sb.Append('<div class="det">' + (& $E $t.Note) + '</div>') }
                [void]$sb.Append('<div class="tw"><table><thead><tr>')
                foreach ($col in $t.Columns) { [void]$sb.Append('<th>' + (& $E $col) + '</th>') }
                [void]$sb.Append('</tr></thead><tbody>')
                foreach ($row in $t.Rows) {
                    [void]$sb.Append('<tr>')
                    foreach ($col in $t.Columns) {
                        $p = $row.PSObject.Properties[$col]
                        $val = if ($p) { $p.Value } else { '' }
                        [void]$sb.Append('<td class="sm">' + (ConvertTo-SdHtmlCell $val) + '</td>')
                    }
                    [void]$sb.Append('</tr>')
                }
                [void]$sb.Append('</tbody></table></div></details>')
            }
            [void]$sb.Append('</section>')
        }

        # --- stopka techniczna
        [void]$sb.Append('<section class="card"><h2>Informacje o programie</h2><div class="det">')
        [void]$sb.Append('SerwisDiag ' + (& $E $Result.Version) + ' (licencja MIT) · PowerShell ' + (& $E $meta['PSVersion']) + ' · wygenerowano ' + (Format-Dt $Result.Generated) + '<br>')
        if ($meta['Knowledge']) { [void]$sb.Append('Baza wiedzy programu (okresy wsparcia Windows i ESU): ' + (& $E $meta['Knowledge']) + '<br>') }
        [void]$sb.Append('Program pracuje lokalnie. Poza testami łączności (ping, DNS, kilka zapytań HTTP/HTTPS) nie wysyła żadnych danych do internetu.<br>')
        if ($anon) { [void]$sb.Append('Raport anonimowy: bez wyników prywatnych, nazwy komputera i kont, numerów seryjnych, kluczy, adresów IP i MAC, nazw sieci Wi-Fi oraz danych klienta. Program usuwa znane dane identyfikujące, ale przed publikacją przejrzyj raport.') }
        else { [void]$sb.Append('Dane wrażliwe (numery seryjne, klucz OEM, konta, wykluczenia antywirusa) oznaczono jako <i>prywatne</i> - nie ma ich w raporcie dla klienta.') }
        [void]$sb.Append('</div>')
        $errs = @($Result.Log | Where-Object { $_ -match '\[(WARN|ERROR)\]' } | Select-Object -First 60)
        if ($errs.Count -gt 0) { [void]$sb.Append('<details class="tbl"><summary>Dziennik programu: ostrzeżenia i błędy (' + $errs.Count + ')</summary><div class="det">' + (& $E ($errs -join "`n")) + '</div></details>') }
        $tm = @($Result.Timings | Sort-Object Seconds -Descending | Select-Object -First 12)
        if ($tm.Count -gt 0) { [void]$sb.Append('<details class="tbl"><summary>Czasy wykonania testów</summary><div class="det">' + (& $E (($tm | ForEach-Object { '{0,6} s  {1}' -f $_.Seconds, $_.Id }) -join "`n")) + '</div></details>') }
        [void]$sb.Append('</section>')
    }

    [void]$sb.Append('</div><script>' + $global:SdReportJs + '</script></body></html>')
    return $sb.ToString()
}

function New-SdTextReport {
    param([Parameter(Mandatory = $true)]$Result, [hashtable]$Settings = @{}, [switch]$IncludePrivate)
    $m = $Result.Meta
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('RAPORT DIAGNOSTYCZNY - ' + $(if ($Settings.ShopName) { $Settings.ShopName } else { 'SerwisDiag' }))
    [void]$lines.Add('Data: ' + (Format-Dt $Result.Generated))
    foreach ($p in @(@('Zlecenie', 'Ticket'), @('Klient', 'Customer'), @('Technik', 'Technician'), @('Komputer', 'Model'), @('System', 'OS'), @('Procesor', 'Cpu'), @('RAM', 'Ram'), @('Dyski', 'Disks'), @('Grafika', 'Gpu'))) {
        if ($m[$p[1]]) { [void]$lines.Add(('{0}: {1}' -f $p[0], $m[$p[1]])) }
    }
    # bez -IncludePrivate podsumowanie nadaje się do przekazania klientowi: wersja wyników dla klienta
    $fs = if ($IncludePrivate) { @($Result.Findings) } else { @(Get-SdCustomerFindings $Result.Findings) }
    $counts = Get-SdCounts $fs
    $verdict = Get-SdVerdict $counts
    [void]$lines.Add('')
    [void]$lines.Add('WYNIK: ' + $verdict.Title.ToUpper() + ' (krytyczne: ' + $counts['crit'] + ', ostrzeżenia: ' + $counts['warn'] + ')')
    [void]$lines.Add('')
    $labels = @{ crit = 'KRYTYCZNE'; warn = 'UWAGA' }
    $issues = @($fs | Where-Object { $_.Status -eq 'crit' -or $_.Status -eq 'warn' } | Sort-Object @{ Expression = { if ($_.Status -eq 'crit') { 0 } else { 1 } } })
    foreach ($f in $issues) {
        [void]$lines.Add(('[{0}] {1}: {2}' -f $labels[[string]$f.Status], $f.Title, $f.Value))
        if ($f.Advice) { [void]$lines.Add('    Zalecenie: ' + $f.Advice) }
    }
    if ($issues.Count -eq 0) { [void]$lines.Add('Nie wykryto problemów.') }
    [void]$lines.Add('')
    [void]$lines.Add('Wygenerowano: SerwisDiag ' + $Result.Version)
    return ($lines -join "`r`n")
}

function ConvertTo-SdJsonReport {
    param([Parameter(Mandatory = $true)]$Result, [switch]$IncludePrivate)
    $meta = [ordered]@{}
    foreach ($k in ($Result.Meta.Keys | Sort-Object)) { if ($IncludePrivate -or @('Serial') -notcontains $k) { $meta[$k] = $Result.Meta[$k] } }
    $obj = [ordered]@{
        tool = $Result.Tool; version = $Result.Version; generated = $Result.Generated.ToString('s')
        started = $(if ($Result.Started) { ([datetime]$Result.Started).ToString('s') } else { $null })
        finished = $(if ($Result.Finished) { ([datetime]$Result.Finished).ToString('s') } else { $null })
        level = $Result.Level; isAdmin = $Result.IsAdmin; meta = $meta
        verdict = $Result.Verdict.Level; counts = $Result.Counts
        findings = @($Result.Findings | Where-Object { $IncludePrivate -or -not $_.Private } | ForEach-Object {
                $cust = $null
                if ($_.PSObject.Properties['Customer'] -and $_.Customer) { $cust = [ordered]@{ title = $_.Customer.Title; status = $_.Customer.Status; value = $_.Customer.Value; advice = $_.Customer.Advice } }
                $fo = [ordered]@{ id = $_.CheckId; category = $_.Category; title = $_.Title; status = $_.Status; value = $_.Value; details = $_.Details; advice = $_.Advice; private = $_.Private; customer = $cust }
                if ($_.PSObject.Properties['LastEvent'] -and $_.LastEvent) { $fo['lastEvent'] = ([datetime]$_.LastEvent).ToString('s') }
                $fo
            })
        tables = @($Result.Tables | Where-Object { $IncludePrivate -or -not $_.Private } | ForEach-Object {
                [ordered]@{ category = $_.Category; name = $_.Name; columns = @($_.Columns); rows = @($_.Rows) }
            })
    }
    return (ConvertTo-Json -InputObject $obj -Depth 6)
}

# ---------------------------------------------------------------- raport anonimowy (do pokazania na forum)

$global:SdGenericNames = @('administrator', 'admin', 'user', 'użytkownik', 'uzytkownik', 'gość', 'guest', 'owner', 'właściciel', 'pc', 'windows', 'microsoft', 'default', 'public', 'workgroup', 'serwis')

function Get-SdSensitiveTokens {
    # Napisy identyfikujące komputer, konta, sieć firmową i klienta - w raporcie anonimowym zastępowane znacznikiem.
    param($Result)
    $t = @()
    $m = $Result.Meta
    foreach ($k in 'ComputerName', 'UserName', 'Serial', 'Ticket', 'Customer', 'Technician') { if ($m.ContainsKey($k)) { $t += [string]$m[$k] } }
    $t += @($env:COMPUTERNAME, $env:USERNAME, $env:USERDOMAIN, $env:USERDNSDOMAIN)
    try { $cs = Get-SdCs; if ($cs -and $cs.PartOfDomain) { $t += [string]$cs.Domain } } catch { }
    foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $env:SystemDrive 'Users') -Directory -ErrorAction SilentlyContinue)) { $t += $d.Name }
    # numery seryjne z tabel (kolumny „Numer seryjny”, „Serial”...)
    foreach ($tb in @($Result.Tables)) {
        $cols = @($tb.Columns | Where-Object { [string]$_ -match '(?i)seryjn|serial' })
        foreach ($r in @($tb.Rows)) { foreach ($c in $cols) { $p = $r.PSObject.Properties[[string]$c]; if ($p) { $t += [string]$p.Value } } }
    }
    $out = @($t | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_.Length -ge 3 -and $global:SdGenericNames -notcontains $_.ToLower() -and -not (Test-SdJunkString $_) } | Select-Object -Unique)
    # najpierw dłuższe: „Jan Kowalski” przed „Jan”
    return @($out | Sort-Object Length -Descending)
}

function ConvertTo-SdAnonymousText {
    # Usuwa z tekstu dane identyfikujące: podane napisy (całe wyrazy), nazwy profili w ścieżkach, SID, klucze produktu,
    # adresy e-mail, MAC i IP (bez znanych adresów publicznych używanych w testach), nazwy sieci Wi-Fi.
    param([string]$Text, [string[]]$Tokens = @())
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $s = $Text
    foreach ($tk in $Tokens) {
        if ($tk) { $s = [regex]::Replace($s, ('(?<![\p{L}\p{N}])' + [regex]::Escape($tk) + '(?![\p{L}\p{N}])'), '<ukryte>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    }
    # nazwa profilu może zawierać spacje („Jan Kowalski”) - do najbliższego ukośnika; profile wspólne i już ukryte zostają
    $s = [regex]::Replace($s, '(?i)(\\Users\\)(?!(?:Public|Default|All Users)(?:[\\"\r\n]|$)|<)[^\\"\r\n<>]+', '$1<użytkownik>')
    $s = [regex]::Replace($s, 'S-1-5-21(?:-\d+){3,4}', 'S-1-5-21-<ukryte>')
    $s = [regex]::Replace($s, '\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}\b', 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX')
    $s = [regex]::Replace($s, '[\w.+-]+@[\w-]+(?:\.[\w-]+)+', '<e-mail>')
    $s = [regex]::Replace($s, '(?i)\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b', 'XX-XX-XX-XX-XX-XX')
    $s = [regex]::Replace($s, '(?i)(?<![\w:])(?:[0-9a-f]{1,4}:){1,6}:(?:[0-9a-f]{1,4}(?::[0-9a-f]{1,4}){0,5})?(?:%\w+)?(?![\w:])', '<IPv6>')
    $s = [regex]::Replace($s, '(?i)(?<![\w:])(?:[0-9a-f]{1,4}:){4,7}[0-9a-f]{1,4}(?:%\w+)?(?![\w:])', '<IPv6>')
    $s = [regex]::Replace($s, '(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\d.])', [System.Text.RegularExpressions.MatchEvaluator] {
            param($mm)
            $v = $mm.Value
            # adresy testowe (publiczne DNS), pętla zwrotna i maski podsieci niczego nie zdradzają
            if (@('1.1.1.1', '1.0.0.1', '8.8.8.8', '8.8.4.4', '9.9.9.9', '127.0.0.1', '0.0.0.0') -contains $v -or $v.StartsWith('255.')) { return $v }
            return 'x.x.x.x'
        })
    $s = [regex]::Replace($s, '(?im)(SSID[^:\r\n]*:[ \t]*)\S[^\r\n]*', '$1<ukryte>')
    return $s
}

function New-SdAnonymousResult {
    # Kopia wyniku diagnostyki bez danych identyfikujących komputer, użytkowników i klienta oraz bez wyników
    # oznaczonych jako prywatne - do pokazania na forum albo przesłania komuś do konsultacji.
    param([Parameter(Mandatory = $true)]$Result)
    $tokens = @(Get-SdSensitiveTokens $Result)
    $A = { param($x) if ($x -is [string]) { ConvertTo-SdAnonymousText $x $tokens } else { $x } }
    $meta = @{}
    foreach ($k in 'Model', 'OS', 'Cpu', 'Ram', 'Disks', 'Gpu', 'Bios', 'Board', 'Chassis', 'BatteryHealth', 'Stability', 'PSVersion', 'ToolVersion', 'Offline', 'IsAdmin', 'Knowledge', 'Integrity') {
        if ($Result.Meta.ContainsKey($k)) { $meta[$k] = & $A $Result.Meta[$k] }
    }
    $findings = @(@($Result.Findings) | Where-Object { $null -ne $_ -and -not $_.Private } | ForEach-Object {
            [pscustomobject]@{ CheckId = $_.CheckId; Category = $_.Category; Title = (& $A $_.Title); Status = $_.Status; Value = (& $A $_.Value); Details = (& $A $_.Details); Advice = (& $A $_.Advice); Private = $false; Customer = $null; Time = $_.Time
                LastEvent = $(if ($_.PSObject.Properties['LastEvent']) { $_.LastEvent } else { $null }) }
        })
    $tables = @(@($Result.Tables) | Where-Object { $null -ne $_ -and -not $_.Private } | ForEach-Object {
            $tb = $_
            $rows = @(@($tb.Rows) | ForEach-Object {
                    $r = $_
                    $o = [ordered]@{}
                    foreach ($c in $tb.Columns) { $p = $r.PSObject.Properties[[string]$c]; $o[[string]$c] = & $A $(if ($p) { $p.Value } else { '' }) }
                    [pscustomobject]$o
                })
            [pscustomobject]@{ Category = $tb.Category; Name = (& $A $tb.Name); Columns = @($tb.Columns); Rows = $rows; Note = (& $A $tb.Note); Private = $false }
        })
    $counts = Get-SdCounts $findings
    return [pscustomobject]@{
        Tool = $Result.Tool; Version = $Result.Version; Generated = $Result.Generated; Started = $Result.Started; Finished = $Result.Finished
        Level = $Result.Level; Tests = @($Result.Tests); IsAdmin = $Result.IsAdmin; Meta = $meta; Counts = $counts; Verdict = (Get-SdVerdict $counts)
        Findings = $findings; Tables = $tables; Timings = @(); Log = @(); Anonymous = $true
    }
}

function Save-SdAnonymousReports {
    # Raport anonimowy: HTML (pełny, techniczny) i krótkie podsumowanie tekstowe do wklejenia w poście.
    # Nazwa pliku bez nazwy komputera i numeru zlecenia.
    param([Parameter(Mandatory = $true)]$Result, [Parameter(Mandatory = $true)][string]$OutDir)
    $anon = New-SdAnonymousResult $Result
    if (-not (Test-Path -LiteralPath $OutDir)) { [void](New-Item -ItemType Directory -Path $OutDir -Force) }
    $base = Join-Path $OutDir ('raport-anonimowy_' + (Get-Date).ToString('yyyyMMdd-HHmm'))
    $p = [ordered]@{ Html = $base + '.html'; Text = $base + '.txt' }
    $bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($p.Html, (New-SdHtmlReport -Result $anon -Mode Technical -Settings @{}), $bom)
    [System.IO.File]::WriteAllText($p.Text, (New-SdTextReport -Result $anon -Settings @{ ShopName = 'raport anonimowy' } -IncludePrivate), $bom)
    return $p
}

function Find-SdPdfBrowser {
    # Przeglądarka, która zapisze stronę jako PDF bez otwierania okna: Microsoft Edge (Windows 10/11), ewentualnie Chrome.
    $cands = @()
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA)) { if ($base) { $cands += (Join-Path $base 'Microsoft\Edge\Application\msedge.exe') } }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) { if ($base) { $cands += (Join-Path $base 'Google\Chrome\Application\chrome.exe') } }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c -PathType Leaf) { return $c } }
    return ''
}

function ConvertTo-SdPdf {
    # Zapisuje raport HTML jako PDF (A4) przeglądarką w trybie bez okna. Zwraca { Ok; Path; Error }.
    # Osobny, tymczasowy profil przeglądarki: nie miesza się z otwartym Edge użytkownika i niczego w nim nie zmienia.
    param([Parameter(Mandatory = $true)][string]$HtmlPath, [string]$PdfPath = '', [int]$TimeoutSec = 90)
    if (-not $PdfPath) { $PdfPath = [System.IO.Path]::ChangeExtension($HtmlPath, '.pdf') }
    $res = [pscustomobject]@{ Ok = $false; Path = $PdfPath; Error = '' }
    $browser = Find-SdPdfBrowser
    if (-not $browser) {
        $res.Error = 'Nie znaleziono przeglądarki Microsoft Edge ani Google Chrome. Otwórz raport i wydrukuj go do pliku: Ctrl+P, drukarka „Microsoft Print to PDF”.'
        return $res
    }
    $profileDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sd-pdf-' + [guid]::NewGuid().ToString('N'))
    try {
        if (Test-Path -LiteralPath $PdfPath) { Remove-Item -LiteralPath $PdfPath -Force -ErrorAction Stop }
        $url = (New-Object System.Uri($HtmlPath)).AbsoluteUri
        # --no-pdf-header-footer (nowsze wersje) i --print-to-pdf-no-header (starsze): bez daty i adresu pliku na stronach
        $a = @('--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--disable-sync',
            '--no-pdf-header-footer', '--print-to-pdf-no-header', (Format-SdCmdArg ('--user-data-dir=' + $profileDir)), (Format-SdCmdArg ('--print-to-pdf=' + $PdfPath)), (Format-SdCmdArg $url))
        $r = Invoke-Native -File $browser -Arguments ($a -join ' ') -TimeoutSec $TimeoutSec -Encoding ([System.Text.Encoding]::UTF8)
        if (Test-Path -LiteralPath $PdfPath) {
            if ((Get-Item -LiteralPath $PdfPath).Length -gt 0) { $res.Ok = $true }
        }
        if (-not $res.Ok) {
            $res.Error = $(if ($r.TimedOut) { 'Przeglądarka nie zapisała PDF w ciągu ' + $TimeoutSec + ' s.' } else { 'Przeglądarka nie zapisała pliku PDF (kod ' + $r.ExitCode + ').' }) +
            ' Otwórz raport i wydrukuj go do pliku: Ctrl+P, drukarka „Microsoft Print to PDF”.'
        }
    } catch {
        $res.Error = $_.Exception.Message
    } finally {
        # profil bywa jeszcze chwilę zablokowany przez kończące się procesy przeglądarki
        for ($i = 0; $i -lt 5 -and (Test-Path -LiteralPath $profileDir); $i++) {
            Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $profileDir) { Start-Sleep -Milliseconds 400 }
        }
    }
    return $res
}

function Save-SdReports {
    # Zapisuje raporty i zwraca słownik: Technical, Customer, Json, Text (ścieżki).
    param(
        [Parameter(Mandatory = $true)]$Result,
        [hashtable]$Settings = @{},
        [string]$OutDir
    )
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmm')
    $meta = $Result.Meta
    $base = Join-NonEmpty @($meta['Ticket'], $meta['ComputerName'], $stamp) '_'
    $base = $base -replace '[\\/:*?"<>|\s]+', '_'
    if (-not (Test-Path -LiteralPath $OutDir)) { [void](New-Item -ItemType Directory -Path $OutDir -Force) }
    $bom = New-Object System.Text.UTF8Encoding($true)
    $nobom = New-Object System.Text.UTF8Encoding($false)
    $paths = [ordered]@{}
    $paths['Technical'] = Join-Path $OutDir ($base + '_techniczny.html')
    [System.IO.File]::WriteAllText($paths['Technical'], (New-SdHtmlReport -Result $Result -Mode Technical -Settings $Settings), $bom)
    $paths['Customer'] = Join-Path $OutDir ($base + '_klient.html')
    [System.IO.File]::WriteAllText($paths['Customer'], (New-SdHtmlReport -Result $Result -Mode Customer -Settings $Settings), $bom)
    $paths['Json'] = Join-Path $OutDir ($base + '.json')
    [System.IO.File]::WriteAllText($paths['Json'], (ConvertTo-SdJsonReport -Result $Result -IncludePrivate), $nobom)
    $paths['Text'] = Join-Path $OutDir ($base + '_podsumowanie.txt')
    [System.IO.File]::WriteAllText($paths['Text'], (New-SdTextReport -Result $Result -Settings $Settings), $bom)
    return $paths
}
