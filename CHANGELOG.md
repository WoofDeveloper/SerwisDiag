# Historia zmian

## 1.4.0 (2026-10-26)

Nowe funkcje:
- **Aktualizacje z GitHuba.** Wersja zainstalowana raz na dobę sprawdza, czy jest nowe wydanie, i pokazuje baner „Dostępna nowa wersja” z opisem zmian. Po Twojej zgodzie pobiera instalator, sprawdza jego sumę SHA-256 i numer wersji, instaluje go w tym samym trybie i uruchamia program ponownie. W konsoli: `-Update`. Wersja przenośna prowadzi do strony wydania.
- **Monitorowanie w tle.** Ikona przy zegarze (bez kropki, żółta, czerwona), co godzinę lekki zestaw testów: dyski, awarie i restarty, sprzęt, urządzenia, antywirus, zapora, Windows Update. Powiadomienia tylko o nowych, pogorszonych lub powtórzonych problemach. Okno wyników z zaleceniami, menu: sprawdź teraz, częstotliwość, wyłącz. Startuje przy logowaniu (instalacja dla wszystkich: zadanie Harmonogramu z najwyższymi dostępnymi uprawnieniami; dla mnie: autostart użytkownika). Opcja w instalatorze i w ustawieniach, w konsoli `-EnableMonitor` / `-DisableMonitor`.
- `SerwisDiagMonitor.exe` uruchamia monitor bez okna konsoli i bez UAC.

Zmiany:
- Instalator zapisuje tryb instalacji (dla wszystkich / dla mnie) – aktualizacja go zachowuje. Odinstalowanie usuwa też autostart monitora i czeka na jego zakończenie.
- Ustawienia: sprawdzanie aktualizacji i monitorowanie (wersja zainstalowana).
- `Invoke-SdScan` może wykonać tylko wskazane testy (`New-SdContext -Only`).

## 1.3.0 (2026-10-26)

Nowe funkcje:
- **Data ostatniego zdarzenia w ostrzeżeniach z historii zdarzeń** (np. „2 w ciągu 90 dni; ostatnio 2026-10-14 20:08”). Dotyczy restartów, niebieskich ekranów, raportów awarii jądra, błędów dysku i sprzętu, błędów dziennika, awarii aplikacji, usług i sterowników, nieudanych aktualizacji i nieudanych logowań. Data trafia też do raportu JSON.
- **Porównanie przed/po: „Bez nowych zdarzeń”.** Takie ostrzeżenie zostaje w raporcie po naprawie, bo zdarzenia sprzed naprawy nadal mieszczą się w sprawdzanym okresie. Gdy od diagnostyki przed naprawą nic się nie powtórzyło, trafia do osobnej sekcji z wyjaśnieniem dla klienta, a nie do „Nadal wymagają uwagi”. Nagłówek podaje ich liczbę, np. „Rozwiązano 1 z 5 problemów, bez nowych zdarzeń: 3”.

Poprawki:
- Nagłówek raportu z naprawy dla klienta liczył także problemy niesprawdzone ponownie, których ten raport nie pokazuje (np. „z 5”, choć widać 4).

## 1.2.1 (2026-10-26)

Poprawki:
- **„Usuń pliki tymczasowe” kończyło się błędem**, gdy do usunięcia było ponad 2 GB („Cannot convert … to type System.Int32”). Pliki były usuwane, ale zamiast zwolnionego miejsca program pokazywał błąd.
- **„Dostępne aktualizacje” nie ostrzega o samych definicjach antywirusa.** Microsoft Defender dostaje je kilka razy dziennie i Windows instaluje je sam. Ostrzeżenie pojawia się tylko przy innych aktualizacjach.

Zmiany:
- `tools\check.ps1` wykrywa zapis `[math]::Max(0, $x)` i `[math]::Min(0, $x)`. PowerShell wybiera wtedy wersję dla liczb Int32, a wartości ponad 2 147 483 647 kończą się błędem.
- README wyjaśnia, dlaczego ostrzeżenia z historii zdarzeń (restarty, błędy dysków i usług) nie znikają po naprawie.

## 1.2.0 (2026-10-26)

Nowe funkcje:
- **Instalator** `SerwisDiag-<wersja>-setup.exe` (Inno Setup 7, kreator po polsku). Instaluje dla wszystkich użytkowników (Program Files, z UAC) albo tylko dla bieżącego (bez UAC). Tworzy skrót w menu Start i opcjonalnie na pulpicie oraz wpis w Ustawienia > Aplikacje. Aktualizacja zachowuje ustawienia. Instalację i odinstalowanie można przeprowadzić bez okien (`/VERYSILENT`). Wersja przenośna (ZIP) działa jak dotąd.
- Zainstalowany program zapisuje raporty w `Dokumenty\SerwisDiag` zamiast w folderze programu.

Zmiany:
- `tools\Build-Release.ps1` buduje paczkę ZIP i instalator z tych samych plików, każde z sumą SHA-256. Pliki robocze trzyma w folderze tymczasowym. Wcześniej usuwał folder `dist\SerwisDiag-<wersja>`, w tym rozpakowaną tam paczkę.

## 1.1.1 (2026-10-26)

Poprawki:
- **Okno „Napraw problemy” nie wykonywało zaznaczonych napraw** (błąd od wersji 1.0.0). Zaznaczone pozycje nie docierały do zadania w tle. Okno kończyło się komunikatem „wykonano 0 z 0”, a dziennik napraw był pusty. Naprawy w trybie konsolowym (`-Repair`, `-RepairIds`) działały poprawnie. Z tego samego powodu przed punktem przywracania nie włączała się ochrona systemu, nawet gdy była zaznaczona.
- Gdy któraś z zaznaczonych napraw nie zwróci wyniku, okno pokazuje błąd zamiast przemilczeć ją. Błędy zadań w tle trafiają do dziennika programu.

Zmiany:
- Nowe testy obejmują całą ścieżkę okna napraw: wykrywanie, punkt przywracania, wykonanie, wynik i dziennik. Sprawdzają też, czy naprawy używają wyłącznie poleceń dostępnych w zadaniu w tle.
- `tools\check.ps1` wykrywa tablice `@{}` z kluczem `Keys`, `Values` lub `Count`. Dla takiej tablicy zapis `$tablica.Keys` zwraca wartość tego klucza zamiast listy kluczy – od tego wziął się powyższy błąd.

## 1.1.0 (2026-10-24)

Nowe funkcje:
- **Cofanie napraw.** Każda zmiana ustawień (rejestr, typ uruchamiania usług, zapora, SMB1, plik wymiany, TRIM) trafia do dziennika `*_naprawy.json` z poprzednim stanem. Program przywraca ją oknem „Cofnij naprawy” albo parametrem `-UndoRepair`. Ustawienia zmienione po naprawie pomija.
- **Raport PDF** dla klienta: przycisk „Zapisz PDF”, opcja w ustawieniach i parametr `-Pdf`. Zapis przez Microsoft Edge albo Chrome, format A4.
- **Kopia przed reinstalacją Windows**: sterowniki producentów, lista programów, dane komputera i klucz Windows z BIOS/UEFI. Na życzenie także profile Wi-Fi z hasłami i klucze odzyskiwania BitLocker. Przed eksportem sterowników program sprawdza długość ścieżek (limit Windows 260 znaków) i wolne miejsce na nośniku. Dostępna w narzędziach serwisowych i przez parametr `-Backup`.
- **Raport anonimowy** do pokazania na forum: bez nazw komputera i kont, numerów seryjnych, kluczy, adresów IP i MAC, nazw sieci Wi-Fi i danych klienta. Krótkie podsumowanie trafia do schowka. Parametr `-Anonymous`.
- **Okno „O programie”**: wersja, autor, licencja, data bazy wiedzy i sprawdzanie nowej wersji (gdy ustawiono adres projektu).
- **Ostrzeżenie o nieaktualnej bazie wiedzy**, gdy dane o okresach wsparcia Windows i ESU są starsze niż pół roku.

Zmiany:
- Program wykrywa tryb ograniczony PowerShell (AppLocker, App Control, Smart App Control) i zamiast błędu pokazuje, co zrobić. Kod wyjścia 5.
- Okna mieszczą się na małych ekranach (1366×768, powiększenie 125–150%), a przyciski w stopce zawijają się.
- Ostrzeżenie przed naprawami: program jest udostępniany bez gwarancji.
- Licencja MIT. Skrypt `tools\Build-Release.ps1` buduje paczkę do publikacji bez raportów i ustawień.
- `tools\check.ps1` wykrywa wyrażenia typu `'a' + $b, 'c'`, w których przecinek wiąże mocniej niż `+`.

Poprawki:
- Odczyt konsumenckiego ESU z gałęzi HKLM: przez błąd w ścieżce nie był wykonywany.
- Pierwszy wiersz dziennika napraw sklejał wersję, datę i nazwę komputera.
- Odmiana liczebników w raportach („1 zalecenie”, „5 ostrzeżeń”).

## 1.0.0 (2026-10-22)

Pierwsza wersja: diagnostyka Windows 8–11, raport techniczny i raport dla klienta, porównanie przed/po naprawie, naprawy z wyborem, sterowniki z Windows Update, tryb bez internetu i kontrola plików programu.
