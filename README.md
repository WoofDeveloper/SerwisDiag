# SerwisDiag — diagnostyka komputerów Windows 8 – 11

Zaawansowany program dla serwisu komputerowego. Sprawdza sprzęt, dyski (SMART/NVMe), baterię, awarie i błędy systemu, sterowniki, zabezpieczenia, aktualizacje, sieć oraz oprogramowanie i autostart, a następnie tworzy **raport techniczny** (dla serwisanta), **raport dla klienta** (HTML albo PDF, bez danych prywatnych) i na życzenie **raport anonimowy** do pokazania na forum. Naprawia wybrane problemy (z możliwością cofnięcia zmian) i robi **kopię przed reinstalacją Windows**. Działa z pendrive'a bez instalacji, a na stałe można go zainstalować instalatorem – wtedy może też monitorować system w tle i sam się aktualizuje.

Autor: Kacper Suliński - INDUSIP.PL. Licencja: MIT (plik `LICENSE`) - program można bezpłatnie używać, także w firmie, zmieniać i rozpowszechniać. Program jest udostępniany bez gwarancji. Historia zmian: `CHANGELOG.md`.

**Pobieranie:** [wydania na GitHubie](https://github.com/WoofDeveloper/SerwisDiag/releases) – instalator `SerwisDiag-<wersja>-setup.exe` albo wersja przenośna `SerwisDiag-<wersja>.zip`, każdy z sumą SHA-256 do sprawdzenia (`Get-FileHash <plik>`).

## Szybki start

Program ma dwie postacie: **instalator** `SerwisDiag-<wersja>-setup.exe` do stałej instalacji (np. na komputerze serwisanta, zob. „Instalator”) i **paczkę ZIP** `SerwisDiag-<wersja>.zip` – wersję przenośną na pendrive, bez instalacji.

1. **Instalator**: uruchom go, wybierz instalację dla wszystkich użytkowników (zalecane) albo tylko dla siebie, a potem uruchom SerwisDiag z menu Start. **Paczka ZIP**: najpierw ją **odblokuj**: prawy przycisk myszy > Właściwości > zaznacz „Odblokuj” > OK. Dopiero potem ją rozpakuj, bo inaczej Windows oznaczy każdy plik jako pobrany z internetu i może blokować skrypty. Skopiuj **cały folder** `SerwisDiag` na pendrive albo na komputer klienta i uruchom `SerwisDiag.exe` (albo `SerwisDiag.cmd`).
2. Zatwierdź okno UAC.
3. Wpisz numer zlecenia / klienta (opcjonalnie), wybierz tryb i kliknij **Rozpocznij diagnostykę**.
4. Po zakończeniu raporty zapiszą się automatycznie (przycisk „Folder raportów”): w wersji przenośnej w folderze `raporty\` obok programu, w zainstalowanej w `Dokumenty\SerwisDiag`.
5. Po naprawie wykonaj diagnostykę ponownie i kliknij **Porównaj przed/po** – powstanie raport z naprawy dla klienta.

| Plik | Do czego |
|---|---|
| `SerwisDiag.exe` | okno programu, żąda uprawnień administratora, bez okna konsoli |
| `SerwisDiag.cmd` | to samo bez `.exe` (jeśli antywirus blokuje nieznane pliki `.exe`); po odmowie w UAC program działa bez uprawnień |
| `SerwisDiag-konsola.cmd` | tryb konsolowy: skan + raporty, bez okna (np. przez zdalny pulpit); z uprawnieniami otwiera się w nowym oknie |
| `SerwisDiag-debug.cmd` | okno programu z widoczną konsolą – do szukania przyczyn problemów |

Parametry podane do plików `.cmd` trafiają do programu bez zmian (także z cudzysłowami i spacjami), np. `SerwisDiag.cmd -Ticket 2025-014 -Customer "Jan Kowalski"` – w oknie programu pola zlecenia będą już wypełnione.

## Instalator

`SerwisDiag-<wersja>-setup.exe` to kreator instalacji po polsku (Inno Setup), dla Windows 8 i nowszych.

- **Dla wszystkich użytkowników** (zalecane): folder `C:\Program Files\SerwisDiag`, instalacja wymaga zgody UAC. Program pracuje z uprawnieniami administratora, a w Program Files jego plików nie podmieni proces bez tych uprawnień.
- **Dla bieżącego użytkownika**: folder `%LOCALAPPDATA%\Programs\SerwisDiag`, bez UAC przy instalacji.
- Skrót w menu Start i opcjonalnie na pulpicie, wpis w Ustawienia > Aplikacje.
- Zainstalowany program zapisuje raporty w `Dokumenty\SerwisDiag` (inny folder wskażesz w Ustawieniach), a ustawienia serwisu w `config\` w folderze programu.
- **Monitorowanie w tle** (opcja kreatora, domyślnie włączona): ikona przy zegarze i powiadomienia o nowych problemach – zob. „Monitorowanie w tle”.
- **Aktualizacja**: program sam sprawdza raz na dobę, czy jest nowa wersja, i aktualizuje się po Twojej zgodzie (zob. „Aktualizacje programu”). Można też uruchomić instalator nowej wersji. Pliki poprzedniej wersji znikają przed skopiowaniem nowych, ustawienia zostają.
- **Odinstalowanie**: Ustawienia > Aplikacje > SerwisDiag. Usuwa program, skróty, ustawienia i autostart monitora. Raporty w `Dokumenty\SerwisDiag` zostają – zawierają dane klientów, więc usuń je sam, gdy nie są potrzebne.
- **Bez okien** (np. na kilku komputerach): `SerwisDiag-<wersja>-setup.exe /VERYSILENT /ALLUSERS` (z uprawnieniami administratora) albo `/VERYSILENT /CURRENTUSER`. Bez skrótu na pulpicie: `/MERGETASKS="!desktopicon"`, bez monitorowania: `/MERGETASKS="!monitor"`, inny folder: `/DIR="D:\Programy\SerwisDiag"`. Odinstalowanie: `unins000.exe /VERYSILENT` z folderu programu.
- Instalator nie ma podpisu cyfrowego: po pobraniu z internetu SmartScreen pokaże „Windows ochronił ten komputer” (Więcej informacji > Uruchom mimo to), a włączony Smart App Control go zablokuje – zob. „Publikacja”.

## Aktualizacje programu

Wersja zainstalowana raz na dobę sprawdza na GitHubie, czy jest nowsze wydanie (wyłączysz to w Ustawieniach). Gdy jest, w oknie programu pojawia się baner „Dostępna nowa wersja” z przyciskami **Co nowego** i **Zaktualizuj**. Aktualizacja:

1. pobiera z wydania instalator nowej wersji i plik z jego sumą SHA-256;
2. sprawdza sumę i numer wersji zapisany w pliku – przy niezgodności przerywa i niczego nie uruchamia;
3. uruchamia instalator w tym samym trybie co dotąd (dla wszystkich albo dla mnie), zamyka program i po instalacji uruchamia go ponownie. Ustawienia, raporty i monitorowanie zostają.

Na żądanie: **O programie > Sprawdź nową wersję**, w konsoli `SerwisDiag-konsola.cmd -Update`. Monitor w tle też powiadamia o nowej wersji (raz na wydanie). Wersja przenośna (ZIP) nie aktualizuje się sama – baner prowadzi do strony wydania. Żeby aktualizacja zadziałała, każda wersja musi być opublikowana na GitHubie jako wydanie z instalatorem – zob. „Publikacja”.

## Monitorowanie w tle

Wersja zainstalowana może działać w tle z ikoną przy zegarze (opcja w instalatorze, potem w Ustawieniach). Co godzinę – albo co 4 godziny lub raz na dobę, do wyboru w menu ikony – wykonuje lekki zestaw testów (ok. 10 s): stan i miejsce na dyskach, niebieskie ekrany i nieoczekiwane restarty, błędy sprzętu, urządzenia z błędami, antywirus, zapora i Windows Update. Pierwsze sprawdzenie odbywa się 2 minuty po zalogowaniu.

- **Ikona**: bez kropki – brak problemów, żółta kropka – ostrzeżenia, czerwona – problem krytyczny, niebieska – trwa sprawdzanie.
- **Powiadomienie Windows** pojawia się tylko przy **nowym** problemie: takim, którego nie było przy poprzednim sprawdzeniu, który się pogorszył albo przy nowym zdarzeniu w dziennikach (np. kolejny nieoczekiwany restart). Znane problemy nie wracają co godzinę.
- Dwuklik ikony albo kliknięcie powiadomienia otwiera okno wyników z zaleceniami, a z niego (i z menu) otworzysz pełny SerwisDiag.
- **Menu ikony**: Sprawdź teraz, częstotliwość, Zakończ (do następnego logowania), Wyłącz monitorowanie.
- **Instalacja dla wszystkich**: monitor startuje przy logowaniu każdego użytkownika (zadanie Harmonogramu `SerwisDiag\Monitor`). U administratora działa z pełnymi uprawnieniami, bez okna UAC; u zwykłego użytkownika bez nich, więc część testów (np. SMART dysków SATA) jest pomijana. **Instalacja dla mnie**: autostart bieżącego użytkownika (wpis Run), bez uprawnień administratora.
- Monitor zajmuje ok. 100 MB pamięci i kilka sekund pracy procesora na sprawdzenie. Wyniki trzyma lokalnie (`%LOCALAPPDATA%\SerwisDiag\monitor.json`, dziennik `monitor.log`) i niczego nie wysyła.
- Wersja przenośna (pendrive) nie monitoruje – niczego nie zostawia na komputerze klienta.

Konsola: `-EnableMonitor` / `-DisableMonitor`.

## Dlaczego PowerShell

Program musi działać na **Windows 8, 8.1, 10 i 11** bez niczego do doinstalowania. Windows PowerShell 3.0+ i .NET Framework 4.5+ są wbudowane we wszystkie te systemy. Dają bezpośredni dostęp do WMI/CIM, dzienników zdarzeń, rejestru i API systemu, a okno WPF jest częścią .NET.

Inne języki tu nie pasują. Go od wersji 1.21 i .NET 8 wymagają Windows 10, a Python trzeba by dołączać razem z interpreterem (takie pliki antywirusy często zgłaszają fałszywie). Jedyną realną alternatywą byłby C# na .NET Framework 4.x, czyli ta sama platforma, tylko skompilowana do jednego pliku `.exe`. Problemy z niepodpisanym programem (SmartScreen, Smart App Control, antywirusy) dotyczą jednak każdego języka i rozwiązuje je dopiero podpis cyfrowy. Za to skrypty może przeczytać każdy, zanim uruchomi je z uprawnieniami administratora.

Fragmenty wymagające natywnego kodu (odczyt zdrowia NVMe, liczniki wydajności PDH, test dysku, obciążenie CPU) są kompilowane w locie z małych wstawek C# (składnia C# 5 – kompilator jest w każdym Windows).

## Co sprawdza

| Kategoria | Najważniejsze testy |
|---|---|
| **System** | wersja, kompilacja i **okres wsparcia** (z bazy `data\lifecycle.psd1`) z **rozpoznaniem ESU** dla Windows 10 22H2, czas pracy i Fast Startup, model/BIOS/UEFI, **gotowość na Windows 11** (CPU, RAM, dysk, UEFI, Secure Boot, TPM), punkty przywracania, stan usługi WMI |
| **Sprzęt** | procesor (generacja, wirtualizacja), pamięć RAM (sloty, tryb jedno/dwukanałowy, XMP/EXPO, niedopasowane moduły), karty graficzne (VRAM, wiek sterownika, sterownik podstawowy), wyświetlacze (EDID), temperatury ACPI, drukarki |
| **Dyski** | **SMART** dysków SATA/HDD (atrybuty, progi, ocena), **zdrowie NVMe** (zużycie, zapas bloków, TBW, błędy nośnika, nieczyste wyłączenia – bez uprawnień administratora), wolne miejsce, bit „dirty”, wyrównanie partycji, tryb kontrolera (AHCI/IDE), TRIM, plik wymiany, miejsce do odzyskania |
| **Zasilanie i bateria** | kondycja baterii (pojemność fabryczna vs rzeczywista), cykle, plan zasilania |
| **Wydajność** | próbkowanie CPU/RAM/dysku (liczniki PDH), ranking procesów, pula nonpaged (wycieki sterowników), **czas uruchamiania systemu** i elementy go spowalniające |
| **Awarie i zdarzenia** | **BSOD** (kody STOP z opisem po polsku i wskazaniem grupy przyczyn), nieoczekiwane restarty (Kernel-Power 41 z klasyfikacją), zrzuty pamięci, raporty WER (z datą awarii, a nie ponownej wysyłki), **indeks stabilności** z Monitora niezawodności (wartość, minimum z 30 dni, trend), błędy dysków **przypisane do konkretnego nośnika** (dysk komputera / dysk USB / nośnik już odłączony), WHEA/GPU/throttling, awarie aplikacji i usług, wynik diagnostyki pamięci |
| **Sterowniki i urządzenia** | urządzenia z błędami (kody Menedżera urządzeń po polsku), **brakujące sterowniki z identyfikatorami sprzętu, producentem i linkiem do Katalogu Microsoft Update**, **nowsze sterowniki dostępne w Windows Update**, wersje/daty/podpisy sterowników |
| **Bezpieczeństwo** | antywirus i Defender (definicje, wykluczenia), zapora, UAC, BitLocker (uwaga o kluczu odzyskiwania), Secure Boot + certyfikaty 2023, TPM, VBS/HVCI, konta i administratorzy, RDP/SMB1/udziały, ślady podmian (Winlogon, AppInit, IFEO), nieudane logowania |
| **Aktualizacje i licencja** | **ostatnia poprawka systemu** (lista poprawek i historia WU – bez definicji Defendera, sterowników i aplikacji ze Sklepu), błędy Windows Update (z opisem kodów), oczekujący restart, zasady/WSUS, aktywacja i kanał licencji, klucz OEM z BIOS, integralność magazynu składników (DISM), wyszukiwanie dostępnych aktualizacji |
| **Sieć** | karty i IP (APIPA, prędkość łącza), Wi-Fi (sygnał, pasmo, prędkość), ping bramy/internetu, DNS, sonda HTTP/HTTPS, **różnica czasu zegara**, proxy, plik hosts, porty nasłuchujące |
| **Oprogramowanie i autostart** | lista programów (bez wolnego `Win32_Product`), reguły: PUP/optymalizatory, aktywatory, narzędzia zdalnego dostępu, **programy bez wsparcia (Office 2016/2019/2021, Flash, QuickTime…)**; autostart z podpisami (także plik uruchamiany przez `rundll32`, `wscript`, `powershell` itp.); usługi i zadania spoza Microsoft (także biblioteki usług w `svchost`); podejrzane procesy |
| **Testy obciążeniowe** (na żądanie) | szybkość dysku (sekwencyjna i losowa 4K), obciążenie CPU z wykrywaniem dławienia, prędkość pobierania, skan NTFS, DISM ScanHealth |

Dodatkowo okno ma stronę **Narzędzia serwisowe**: skróty do narzędzi systemowych, **sterowniki** (Windows Update, Katalog Microsoft, strona producenta), SFC, DISM (z internetu albo **z płyty/ISO**), CHKDSK, reset Windows Update, Winsock, punkt przywracania, czyszczenie plików tymczasowych oraz **test ekranu (martwe piksele)** i **test klawiatury**.

## Tryby

- **Szybka** (~1 min): wszystkie testy odczytowe.
- **Pełna** (kilka min): dodatkowo lista programów z sygnaturami, zadania harmonogramu, porty, miejsce do odzyskania, wyszukiwanie aktualizacji online, nieudane logowania, dłuższe okno analizy zdarzeń.
- **Testy dodatkowe** (pola wyboru): obciążają komputer, więc uruchamiasz je świadomie.
- **Tryb bez internetu** (pole w oknie albo parametr `-Offline`): gdy komputer celowo nie ma internetu (stanowisko serwisowe, klient bez sieci). Testy łączności z internetem, test prędkości, wyszukiwanie aktualizacji i sterowników są wtedy pomijane z adnotacją „pominięto – tryb bez internetu”, zamiast zgłaszać krytyczne błędy; sieć lokalna (karta, ping do routera) jest nadal sprawdzana, a raport dla klienta informuje, że internetu nie sprawdzano. Nie da się tego wykrywać automatycznie: gdy klient zgłasza „nie działa internet”, czerwony wynik testów łączności jest właśnie diagnozą. Uszkodzony magazyn składników naprawisz wtedy narzędziem **DISM RestoreHealth z płyty/ISO**: wskaż obraz ISO albo `install.wim` / `install.esd` z nośnika instalacyjnego tej samej wersji Windows – program sam zamontuje ISO, dobierze edycję i sprawdzi zgodność wersji, języka i architektury.

## Naprawa problemów po diagnostyce

Po diagnostyce kliknij **Napraw problemy...** (na dole okna). Program sprawdza, które z wykrytych problemów potrafi usunąć sam, i pokazuje listę z polami wyboru: co znalazł, co dokładnie zrobi, czy potrzebny jest restart, internet lub uprawnienia administratora, oraz ryzyko. Zalecane naprawy są zaznaczone, ryzykowniejsze (reset sieci, wyłączenie SMB1, deinstalacje, wyłączanie programów z autostartu) zaznaczasz sam. Na końcu listy jest sekcja „Tego program nie naprawi” – usterki sprzętowe i ustawienia BIOS, które zostają dla serwisanta.

Zasady bezpieczeństwa:
- nic nie dzieje się bez zaznaczenia i potwierdzenia;
- przed zmianami powstaje **punkt przywracania**;
- każda zmiana trafia do **dziennika napraw** (`…_naprawy.txt` i `…_naprawy.json` w folderze raportów) z poprzednią wartością, więc da się ją cofnąć;
- autostart wyłączany jest jak w Menedżerze zadań (bez usuwania plików).

Po naprawach kliknij „Diagnostyka ponownie”, a potem **Porównaj przed/po** – lista wykonanych napraw wpisze się sama do raportu dla klienta.

### Cofanie napraw

**Więcej > Cofnij naprawy z dziennika...** (albo Narzędzia serwisowe > Konserwacja) wczytuje najnowszy dziennik napraw tego komputera. Pokazuje zmiany ustawień z polami wyboru: wartości rejestru, typ uruchamiania usług, zaporę, SMB1, plik wymiany i TRIM. Cofnięcie przywraca wartości 1:1, łącznie z typem (np. `ExpandString` bez rozwijania zmiennych). Wartość, którą ktoś zmienił już po naprawie, jest pomijana. Dziennik z innego komputera jest odrzucany. Wynik trafia do `…_cofniecie_<data>.txt`.

Operacji typu DISM, SFC, czyszczenie plików, instalacja sterowników czy deinstalacja program nie cofa. Do tego służy przycisk **Przywracanie systemu...** w tym samym oknie (punkt sprzed napraw). Konsola: `-UndoRepair <plik_naprawy.json>` albo `-UndoRepair ostatni`. Cofanie wymaga uprawnień administratora.

| Grupa | Naprawy (proponowane tylko, gdy diagnostyka wykryła problem) |
|---|---|
| System | włączenie punktów przywracania, naprawa repozytorium WMI, **DISM RestoreHealth**, **SFC** |
| Windows Update | włączenie usługi, usunięcie zasad blokujących aktualizacje (poza domeną), reset składników Windows Update |
| Sterowniki | instalacja zalecanych sterowników z Windows Update |
| Bezpieczeństwo | włączenie Microsoft Defender i aktualizacja definicji, włączenie zapory, przywrócenie UAC, wyłączenie SMB1 i usługi Zdalny rejestr, przywrócenie Winlogon (Shell/Userinit), usunięcie przekierowań IFEO, wyłączenie AppInit_DLLs |
| Dysk i system | zrzuty pamięci po awarii, TRIM dla SSD, automatyczny plik wymiany, usunięcie plików tymczasowych |
| Sieć | czyszczenie pamięci DNS, synchronizacja zegara, wyłączenie proxy, reset Winsock/TCP-IP |
| Autostart, programy | wyłączenie podejrzanych wpisów autostartu, wyłączenie wybranych programów z autostartu, deinstalacja programów niechcianych / optymalizatorów / „aktywatorów” (okno deinstalatora przechodzisz ręcznie) |

Program **nie naprawia** usterek sprzętowych (dysk z błędami SMART, zużyta bateria, RAM, przegrzewanie), ustawień BIOS (Secure Boot, TPM) ani licencji – te pokazuje z zaleceniami. Tryb konsolowy: `-RepairList` (tylko lista), `-Repair` (zalecane naprawy), `-RepairIds fx.dism,fx.sfc` (wskazane naprawy).

Część ostrzeżeń opisuje zdarzenia z dzienników Windows, które już się wydarzyły: nieoczekiwane restarty i niebieskie ekrany (okres 90 dni), błędy dysków, sprzętu i awarie aplikacji (30 dni), błędy usług (14 dni) i nieudane aktualizacje (60 dni). Żadna naprawa ich nie usunie. Po usunięciu przyczyny zostają w raporcie, dopóki w tym okresie nie przestaną pojawiać się nowe zdarzenia. Wartość takiego wyniku kończy się datą ostatniego zdarzenia (np. „…; ostatnio 2026-10-14 20:08”), a porównanie przed/po pokazuje go jako „bez nowych zdarzeń”, gdy od diagnostyki przed naprawą nic się nie powtórzyło.

## Sterowniki

- **Diagnostyka** (z internetem) sprawdza w Windows Update, czy są nowsze sterowniki dla urządzeń tego komputera – zwykle kilkanaście sekund, wynik w kategorii „Sterowniki i urządzenia”. To oficjalne, podpisane sterowniki dopasowane do sprzętu, na Windows 8 – 11.
- **Narzędzia serwisowe > Sterowniki z Windows Update**: lista z polami wyboru (zaznaczone zalecane i te, które naprawiają urządzenia z błędem; opcjonalne zaznaczasz sam), przed instalacją punkt przywracania, potem pobranie i instalacja (wymaga administratora). Tryb konsolowy: `-InstallDrivers` instaluje zalecane sterowniki po diagnostyce.
- **Brakujące sterowniki (Katalog Microsoft)**: urządzenia z błędami i ich identyfikatory sprzętu; przycisk otwiera wyszukiwanie w Katalogu Microsoft Update (pobrany `.cab` rozpakuj i wskaż w Menedżerze urządzeń). W raporcie technicznym ten sam link jest w tabeli brakujących sterowników.
- **Strona sterowników producenta**: otwiera oficjalną stronę ze sterownikami (Lenovo, Dell, HP, ASUS, Acer, MSI, Gigabyte, ASRock, Dynabook, Samsung, Fujitsu, Surface; komputer składany – producent płyty głównej) i kopiuje do schowka numer seryjny lub model do wklejenia. Producenci nie publikują stałych adresów „po numerze seryjnym”, dlatego program nie zgaduje linku; nieznany producent – wyszukiwarka.
- Windows Update nie zawsze ma najnowsze sterowniki kart graficznych – NVIDIA / AMD / Intel bywają nowsze na stronach producentów. Program nie korzysta z nieoficjalnych baz sterowników („aktualizatorów”) – często instalują adware.

## Okres wsparcia i ESU (Windows 10)

Windows 10 22H2 stracił standardowe wsparcie 14.10.2025. Program sprawdza, czy komputer jest objęty **rozszerzonymi aktualizacjami zabezpieczeń (ESU)**: licencję ESU dla firm i szkół (rok 1 / 2 / 3), zapis do programu konsumenckiego (Microsoft przedłużył go do **12.10.2027**) oraz to, czy faktycznie zainstalowano poprawki wydane po zakończeniu wsparcia (kompilacja nowsza niż 19045.6456). Komputer objęty ESU dostaje ocenę informacyjną z datą końca programu zamiast „krytycznej”; bez ESU – ocenę krytyczną z radą, jak się zapisać. Daty i identyfikatory licencji są w `data\lifecycle.psd1` (sekcja `Esu`).

## Uprawnienia administratora

Program działa także bez nich (pomija to, co wymaga admina, i mówi o tym w raporcie), ale pełny obraz wymaga administratora: SMART dysków SATA/HDD, BitLocker, dokładne dane TPM, wykluczenia Defendera, dziennik rozruchu i zabezpieczeń, DISM, punkty przywracania, temperatury ACPI. Odczyt zdrowia **NVMe** i większość reszty działają bez uprawnień. Przycisk „Uruchom jako administrator” otwiera program ponownie z uprawnieniami i przenosi wpisane dane zlecenia.

Test szybkości dysku nie uruchomi się, gdy dysk systemowy ma objawy awarii (ocena SMART lub stan zgłaszany przez Windows) – intensywny zapis mógłby przyspieszyć awarię; najpierw zabezpiecz dane.

## Raporty

Zapisywane w `raporty\` obok programu, w wersji zainstalowanej w `Dokumenty\SerwisDiag`, albo w folderze z ustawień:

- `…_techniczny.html` – pełny raport z filtrem „tylko problemy”, szczegółami i tabelami (także prywatnymi).
- `…_klient.html` – czytelny werdykt i zalecenia, **bez** numerów seryjnych, kluczy, kont i surowych tabel; gotowy do wydrukowania lub przesłania klientowi.
- `….json` – wszystkie dane (do porównań i automatyzacji; zawiera dane prywatne).
- `…_podsumowanie.txt` – krótkie podsumowanie do wklejenia w zleceniu / SMS (Więcej > „Kopiuj podsumowanie do schowka”).
- `…_klient.pdf` – raport dla klienta w PDF (A4), do wysłania mailem albo wydruku. Tworzy go przycisk **Zapisz PDF**, opcja w ustawieniach (zapis po każdej diagnostyce) albo parametr `-Pdf`. Program drukuje raport do PDF przez Microsoft Edge (albo Chrome) w trybie bez okna, z osobnym, tymczasowym profilem. Bez tych przeglądarek wydrukujesz raport ręcznie: Ctrl+P, drukarka „Microsoft Print to PDF”.
- `raport-anonimowy_<data>.html` i `.txt` – **raport anonimowy** (Więcej > „Raport anonimowy”, parametr `-Anonymous`): pełny raport techniczny bez wyników prywatnych, nazwy komputera i kont, profili w ścieżkach `C:\Users\...`, numerów seryjnych, kluczy produktu, adresów IP, MAC i e-mail, SID, nazw sieci Wi-Fi, domeny ani danych klienta i zlecenia. Krótkie podsumowanie trafia do schowka – do wklejenia w poście na forum. Przed publikacją przejrzyj raport: program usuwa znane dane identyfikujące, ale nie gwarantuje, że wykryje wszystkie.

Dane wrażliwe (numery seryjne, klucz OEM, konta, wykluczenia antywirusa, udziały) są oznaczone jako *prywatne* i nie trafiają do raportu dla klienta ani do pliku TXT. Wątpliwości co do legalności licencji (aktywacja KMS spoza domeny, „aktywatory”) są tylko w raporcie technicznym – klient widzi neutralny opis („Aktywowany”, „programy wysokiego ryzyka”), a szczegóły omawia serwisant. Raport HTML jest pojedynczym plikiem i działa offline.

## Kopia przed reinstalacją Windows

Narzędzia serwisowe > Konserwacja > **Kopia przed reinstalacją Windows** (albo Więcej > ...) zapisuje w jednym folderze `<KOMPUTER>_<data>_kopia` to, co zwykle ginie przy reinstalacji:

| Element | Zawartość | Domyślnie |
|---|---|---|
| Sterowniki producentów | eksport wszystkich sterowników spoza Windows z magazynu sterowników, także starszych wersji (`DISM /Export-Driver`, Windows 8.1+), i lista sterowników używanych urządzeń (CSV) | tak (administrator) |
| Lista programów | zainstalowane programy: HTML do wydruku i CSV dla Excela | tak |
| Dane komputera i klucz Windows | model, numer seryjny, podzespoły, wersja i aktywacja Windows, klucz z BIOS/UEFI, konta lokalne, drukarki | tak |
| Profile Wi-Fi z hasłami | zapisane sieci z hasłami jawnym tekstem (`netsh wlan export`) | nie (administrator) |
| Klucze odzyskiwania BitLocker | hasła odzyskiwania zaszyfrowanych dysków | nie (administrator) |

Przed eksportem sterowników program sprawdza dwie rzeczy:
- **Długość ścieżek.** DISM odtwarza w kopii ścieżki z magazynu sterowników, a Windows dopuszcza 259 znaków. Zbyt głęboki folder przerwałby eksport w połowie (błąd 206), dlatego wybieraj krótkie foldery, np. główny katalog pendrive'a `E:\`.
- **Wolne miejsce na nośniku.** Eksport obejmuje wszystkie pakiety producentów, także stare wersje sterowników karty graficznej, więc zajmuje od kilkuset MB do kilku GB. Na komputerze testowym było to 110 pakietów, 8,2 GB i ok. 70 s.

Gdy coś się nie zmieści, program od razu podaje przyczynę i zapisuje resztę kopii. Pakiety rozpoznaje w ok. 1 s po kopiach `C:\Windows\INF\oem*.inf`.

W folderze powstaje też `CZYTAJ.txt` z instrukcją przywracania (sterowniki: Menedżer urządzeń albo `pnputil /add-driver ... /subdirs /install`, Wi-Fi: `netsh wlan add profile`). Program niczego nie zmienia na komputerze i nie kopiuje plików użytkownika. Ostrzega, gdy folder docelowy leży na dysku systemowym (zniknie przy reinstalacji) albo gdy dysk jest zaszyfrowany BitLockerem, a klucz nie jest zapisywany. Kopia zawiera dane wrażliwe – po naprawie usuń ją z nośnika serwisowego. Konsola: `-Backup E:\kopie [-BackupInclude drivers,programs,system,wifi,bitlocker]`.

## Raport z naprawy: porównanie przed / po

Każda diagnostyka zapisuje plik `.json`. Po naprawie wykonaj diagnostykę ponownie i kliknij **Porównaj przed/po**: program sam podpowie raport sprzed naprawy (najnowszy raport tego komputera, najpierw z tym samym numerem zlecenia) i bieżący raport jako „po”; dopisz **wykonane czynności** (np. „wymiana dysku na SSD, czyszczenie chłodzenia”). Powstają dwa pliki:

- `…_porownanie_klient.html` – „Rozwiązano X z Y problemów”, wykonane czynności, rozwiązane problemy (wartość przed → po), problemy, które nadal wymagają uwagi, i nowe zalecenia; bez danych prywatnych.
- `…_porownanie_techniczne.html` – to samo plus testy niewykonane ponownie, inne zmienione wyniki (np. wolne miejsce, wyniki testów wydajności) i ostrzeżenia, gdy raporty są z różnych komputerów lub z innego trybu.

Problem, którego wynik zniknął, liczy się jako rozwiązany tylko wtedy, gdy ten sam test wykonano ponownie (inaczej trafia do „nie sprawdzono ponownie”). Porównywać warto diagnostyki w tym samym trybie i z uprawnieniami administratora.

Ostrzeżenia z historii zdarzeń (restarty, błędy dysku, usług itp.) po naprawie zwykle zostają, bo zdarzenia sprzed naprawy nadal mieszczą się w sprawdzanym okresie. Jeśli ostatnie takie zdarzenie jest starsze niż diagnostyka przed naprawą, porównanie umieszcza wynik w osobnej sekcji **„Bez nowych zdarzeń od poprzedniej diagnostyki”** z wyjaśnieniem dla klienta, a nie wśród problemów bez zmian. Nagłówek podaje wtedy np. „Rozwiązano 1 z 5 problemów, bez nowych zdarzeń: 3”. Raporty z wersji starszych niż 1.3.0 nie zapisują daty ostatniego zdarzenia, więc jako raport „po naprawie” trzeba użyć diagnostyki z wersji 1.3.0 lub nowszej. Raport „przed naprawą” może pochodzić z dowolnej wersji.

## Tryb konsolowy

```
SerwisDiag-konsola.cmd
SerwisDiag-konsola.cmd -Level Full -Ticket 2025-014 -Customer "Jan Kowalski" -Note "wolno chodzi"
SerwisDiag-konsola.cmd -TestIds tt.disk,tt.cpu
SerwisDiag-konsola.cmd -CompareWith raporty\2025-014_PC_20261020-1000.json -WorkDone "Wymiana dysku na SSD"
SerwisDiag-konsola.cmd -CompareBefore przed.json -CompareAfter po.json -WorkDone "Czyszczenie, nowa pasta"
SerwisDiag-konsola.cmd -Pdf -Anonymous
SerwisDiag-konsola.cmd -Backup E:\kopie -BackupInclude drivers,programs,system,wifi
SerwisDiag-konsola.cmd -UndoRepair ostatni
```

Parametry:
- diagnostyka: `-Level Quick|Full`, `-TestIds`, `-OutDir`, `-Ticket`, `-Customer`, `-Technician`, `-Note`, `-Open`, `-Offline` (tryb bez internetu);
- raporty: `-Pdf` (raport dla klienta także jako PDF), `-Anonymous` (raport anonimowy);
- naprawy i sterowniki: `-InstallDrivers` (po diagnostyce zainstaluj zalecane sterowniki z Windows Update; wymaga administratora), `-RepairList` / `-Repair` / `-RepairIds` (naprawy po diagnostyce), `-UndoRepair <json>|ostatni` (cofnij zmiany ustawień z dziennika napraw, bez diagnostyki);
- kopia: `-Backup <folder>` (kopia przed reinstalacją Windows, bez diagnostyki), `-BackupInclude` (elementy kopii);
- porównanie: `-CompareWith <json>` (po diagnostyce porównaj z raportem sprzed naprawy), `-CompareBefore` / `-CompareAfter` (porównaj dwa zapisane raporty bez diagnostyki), `-WorkDone` (wykonane czynności);
- wersja zainstalowana: `-Update` (sprawdź, pobierz i zainstaluj nową wersję), `-EnableMonitor` / `-DisableMonitor` (monitorowanie w tle; `-NoStart`: bez uruchamiania monitora od razu), `-Monitor` (sam monitor – tak uruchamia go `SerwisDiagMonitor.exe`);
- uruchamianie: `-Elevate` (poproś o uprawnienia przez UAC), `-Pause` (czekaj na Enter na końcu), `-SkipIntegrity`.

Kody wyjścia:

| Kod | Znaczenie |
|---|---|
| `0` | bez zastrzeżeń |
| `1` | są ostrzeżenia (przy kopii i cofaniu: część elementów zakończyła się błędem) |
| `2` | są problemy krytyczne |
| `3` | błędne parametry albo brak pliku do porównania lub cofnięcia |
| `4` | pliki programu niezgodne z manifestem |
| `5` | PowerShell w trybie ograniczonym (blokada AppLocker, App Control lub Smart App Control) |

## Ustawienia

Przycisk **Ustawienia** pozwala ustawić:
- nazwę i dane kontaktowe serwisu, technika i logo (PNG/JPG/SVG do 400 KB);
- folder raportów;
- **co otworzyć po diagnostyce** – domyślnie nic, bo raport techniczny zawiera dane prywatne, a ekran często widzi klient; można wybrać raport dla klienta albo techniczny;
- **zapis PDF** raportu dla klienta po każdej diagnostyce;
- w wersji zainstalowanej: **sprawdzanie aktualizacji** raz na dobę i **monitorowanie w tle** z częstotliwością sprawdzania.

Ustawienia zapisują się w `config\settings.json` (częstotliwość monitorowania – osobno dla każdego użytkownika w `%LOCALAPPDATA%\SerwisDiag`). Przycisk **O programie** pokazuje wersję, autora, licencję, datę bazy wiedzy i wynik kontroli plików.

## Kontrola plików programu (pendrive)

Program zwykle pracuje z pendrive'a podłączanego do wielu, także zainfekowanych komputerów. Przy starcie porównuje sumy SHA-256 swoich plików z `manifest.sha256` – **zanim** wczyta testy. Gdy plik jest zmieniony, brakuje go albo pojawił się nowy (np. dopisany skrypt w `checks\`), okno pyta, czy mimo to uruchomić program, a tryb konsolowy przerywa (kod 4, pominięcie: `-SkipIntegrity`). Wynik kontroli jest w raporcie technicznym („Pliki programu”). Po świadomej zmianie plików uruchom `tools\check.ps1` – odświeża manifest. Kontrola wykrywa uszkodzony nośnik i przypadkowe lub prymitywne zmiany; celowy atak może podmienić także manifest, dlatego najlepszą ochroną jest pendrive z przełącznikiem blokady zapisu.

## Rozbudowa

**Baza wiedzy** (zwykłe pliki tekstowe w `data\`, można edytować bez znajomości programowania): okresy wsparcia Windows (`lifecycle.psd1` – aktualizuj ręcznie, źródło: learn.microsoft.com/lifecycle; po weryfikacji zmień datę `Verified` – ponad pół roku od niej program pokazuje baner „baza wiedzy nieaktualna”, a raport techniczny informację dla technika), kody STOP (`bugchecks.psd1`), kody Menedżera urządzeń (`pnp-errors.psd1`), producenci sprzętu (`pci-vendors.psd1`), reguły oprogramowania PUP/EOL (`software-flags.psd1`), znaczenie zdarzeń (`event-hints.psd1`).

**Nowy test** – dodaj plik do `checks\` (ładowane alfabetycznie) albo funkcję do istniejącego:

```powershell
Register-Check -Id 'moj.test' -Category 'system' -Title 'Mój test' -Level Quick -Script {
    $x = Get-Cim Win32_BIOS | Select-Object -First 1
    Add-Finding 'Wersja BIOS' -Status info -Value $x.SMBIOSBIOSVersion
    # Status: ok | info | warn | crit ; opcjonalnie -Details, -Advice, -Private
    # Osobna, neutralna wersja dla raportu klienta: -CustomerTitle, -CustomerStatus, -CustomerValue, -CustomerAdvice
    # Wynik z historii zdarzeń: -LastEvent <czas ostatniego zdarzenia> (np. Get-SdLatestTime $zdarzenia) - wartość dostaje
    # „ostatnio …”, a porównanie przed/po rozpozna, że od poprzedniej diagnostyki nic się nie powtórzyło
    # Add-Table 'Nazwa tabeli' -Rows $listaObiektow
}
```

Poziomy: `Quick` (zawsze), `Full` (tylko tryb pełny), `Test` (na żądanie); `-NeedsAdmin` pomija test bez uprawnień, `-NeedsInternet` – w trybie bez internetu. Zapytania WMI rób przez `Get-Cim` – ma limit czasu i bezpiecznik: gdy kilka zapytań z rzędu nie odpowiada (uszkodzone repozytorium WMI), kolejne są pomijane, a raport dostaje wynik „Usługa WMI”. Po każdej zmianie w kodzie uruchom `tools\check.ps1` (kodowanie, składnia, konstrukcje niedostępne w PowerShell 3.0, **odświeżenie manifestu**) i `tools\run-tests.ps1` (451 testów jednostkowych). `tools\check.ps1` wyłapuje też wyrażenia typu `'a' + $b, 'c'`: przecinek wiąże w PowerShell mocniej niż `+`, więc do napisu zostałaby doklejona cała tablica. `tools\dev-run.ps1 -Only "st.*" -Details` uruchamia wybrane testy w konsoli. `SerwisDiag.ps1 -SelfTest -ScreenshotPath <prefiks>` uruchamia okno poza ekranem, wykonuje szybki skan i zapisuje zrzuty kolejnych stron (test regresji interfejsu).

## Struktura

```
SerwisDiag.exe / .cmd / .ps1   uruchamianie i punkt wejścia
SerwisDiagMonitor.exe          uruchamianie monitorowania w tle (bez UAC i okna konsoli)
manifest.sha256                sumy kontrolne plików programu (generuje tools\check.ps1)
LICENSE, CHANGELOG.md          licencja MIT, historia zmian
instalacja.ini                 tylko w kopii zainstalowanej: znacznik i tryb instalacji (zapisuje instalator)
lib\      silnik (Core, Providers, Native, Report, Compare, Drivers, Repair, Fixes, Backup, AppInfo, Update, Monitor, Integrity, Settings, Gui, GuiTests)
checks\   testy diagnostyczne, jeden plik na kategorię
data\     baza wiedzy (edytowalna)
config\   settings.json (ustawienia serwisu - nie publikować)
raporty\  wygenerowane raporty (dane komputerów - nie publikować)
logs\     zapis błędów startu programu
tools\    check, run-tests, dev-run, Build-Exe (+ źródło launchera), Build-Release, make-icon, installer\ (skrypt instalatora)
dist\     paczki ZIP i instalatory do publikacji (tools\Build-Release.ps1)
```

## Publikacja

- **Paczka do pobrania**: `powershell -ExecutionPolicy Bypass -File tools\Build-Release.ps1`. Najpierw sprawdza, czy pliki zgadzają się z manifestem (po zmianach uruchom `tools\check.ps1`). Potem tworzy `dist\SerwisDiag-<wersja>.zip` tylko z plików programu, dokumentacji i narzędzi oraz sumę SHA-256 do opublikowania obok. Kontroluje też, czy w paczce nie ma raportów, ustawień ani logów. Nie pakuj folderu ręcznie: `raporty\` zawiera numery seryjne i klucze Windows komputerów, a `config\` ustawienia Twojego serwisu.
- **Instalator**: ten sam skrypt buduje z tych samych plików (bez narzędzi programisty) `dist\SerwisDiag-<wersja>-setup.exe` z sumą SHA-256. Potrzebny jest darmowy Inno Setup 7 (jrsoftware.org/isdl.php, wystarczy instalacja „dla bieżącego użytkownika”). Bez niego powstaje sam ZIP, a `-NoInstaller` pomija instalator celowo. Skrypt instalatora to `tools\installer\SerwisDiag.iss`. Jego `AppId` nie może się zmieniać, bo po nim instalator rozpoznaje poprzednią wersję i ją aktualizuje.
- **GitHub i aktualizacje**: `.gitignore` wyklucza `raporty\`, `logs\`, `config\settings.json` i `dist\`. Adres repozytorium wpisz w `lib\Core.ps1` (`$global:SdProjectUrl`) – od niego zależą aktualizacje i link w oknie „O programie”. Każdą wersję publikuj jako wydanie (Release) z tagiem `v<wersja>` (np. `v1.4.0`) i czterema plikami z `dist\`: `SerwisDiag-<wersja>-setup.exe`, `SerwisDiag-<wersja>-setup.exe.sha256`, `SerwisDiag-<wersja>.zip` i `SerwisDiag-<wersja>.zip.sha256`, np. `gh release create v1.4.0 dist\SerwisDiag-1.4.0* --title "SerwisDiag 1.4.0" --notes "..."`. Program pobiera instalator i plik `.sha256` z najnowszego wydania – bez nich aktualizacja się nie uruchomi, a opis wydania pokazuje przycisk „Co nowego”.
- **Wersja**: numer w `lib\Core.ps1` (`$global:SdVersion`), opis zmian w `CHANGELOG.md`. Przy aktualizacji bazy wiedzy zmień też datę `Verified` w `data\lifecycle.psd1`.
- **Podpis cyfrowy**: niepodpisany program z internetu zablokuje Smart App Control w Windows 11 (bez przycisku „Uruchom mimo to”), a SmartScreen i antywirusy będą ostrzegać. Rozwiązuje to podpis certyfikatem wystawcy z programu Microsoft Trusted Root, obejmujący `SerwisDiag.exe`, instalator (dyrektywa `SignTool` w Inno Setup) i wszystkie skrypty (`Set-AuthenticodeSignature`). Certyfikat jest płatny i odnawiany co rok; projekty open source mogą dostać darmowy podpis (np. SignPath Foundation). Po podpisaniu odśwież manifest. Przed publikacją warto sprawdzić paczkę na VirusTotal, a fałszywe alarmy zgłosić producentom antywirusów.

## Zgodność i ograniczenia

- Windows 8 / 8.1 / 10 / 11 (x86, x64, ARM64), Windows PowerShell 3.0+ (domyślny w tych systemach), .NET Framework 4.5+. Windows 7 nie jest obsługiwany (brak `Get-CimInstance`).
- Polskie znaki: wszystkie pliki `.ps1` są zapisane jako UTF-8 **z BOM** (wymóg Windows PowerShell 5.1) – po edycji uruchom `tools\check.ps1`, który to naprawia.
- Odczyty nie zależą od języka systemu (brak parsowania komunikatów tekstowych, nazwy liczników wydajności po angielsku przez PDH).
- Temperatury: ACPI nie jest temperaturą rdzeni procesora; do pomiaru CPU/GPU użyj HWiNFO. Zgodność z Windows 11 według nazwy procesora jest **szacunkiem** – rozstrzyga lista Microsoft.
- Skrypty uruchamiają się z `-ExecutionPolicy Bypass`. Zasady grupy (MachinePolicy/UserPolicy) mogą to blokować na komputerach firmowych.
- Na komputerach z blokadą uruchamiania programów (AppLocker, App Control, Smart App Control w Windows 11) PowerShell wykonuje niepodpisane skrypty w trybie ograniczonym. W nim nie działają wstawki C# ani okno WPF. Program wykrywa to od razu i zamiast błędu pokazuje komunikat z możliwymi rozwiązaniami (w trybie okna w Notatniku, kod wyjścia 5).
- Okna mieszczą się na małych ekranach (laptop 1366×768, powiększenie 125–150%). Program zmniejsza okno do obszaru roboczego ekranu i otwiera je zmaksymalizowane, a przyciski stopki zawijają się do drugiego wiersza.
- Antywirus może zgłosić nieznany `SerwisDiag.exe` albo `SerwisDiagMonitor.exe` (launchery uruchamiają PowerShell). Użyj `SerwisDiag.cmd` albo zbuduj pliki samodzielnie: `powershell -File tools\Build-Exe.ps1`.

## Rozwiązywanie problemów

| Objaw | Co zrobić |
|---|---|
| Okno się nie otwiera | `SerwisDiag-debug.cmd` – pokaże błąd w konsoli; szczegóły startu w `logs\blad-*.txt` |
| „Pliki programu nie zgadzają się z manifestem” | jeśli zmieniałeś pliki – `tools\check.ps1`; jeśli nie – skopiuj program od nowa z zaufanej kopii i sprawdź komputer, do którego był podłączony pendrive |
| „Brak danych” w kategoriach albo wynik „Usługa WMI nie odpowiada” | WMI uszkodzone: `winmgmt /verifyrepository`, `winmgmt /salvagerepository` (jako administrator) |
| Puste liczniki wydajności (próbkowanie) | `lodctr /R` (jako administrator) |
| Nie widać SMART dysku SATA | uruchom jako administrator; dyski USB zwykle nie udostępniają SMART przez mostek |
| Skrypt blokowany przez politykę wykonywania | skopiuj program lokalnie, `Unblock-File` na plikach, albo zmień zasady grupy |
| Komunikat „SerwisDiag nie może działać na tym komputerze” (tryb ograniczony, kod 5) | komputer firmowy – zgoda administratora IT; paczka z internetu – odblokuj ZIP przed rozpakowaniem; Smart App Control – program działa po jego wyłączeniu (tylko za zgodą właściciela, w starszych Windows 11 nie da się go włączyć ponownie bez reinstalacji) |
| „Windows ochronił ten komputer” (SmartScreen) | program i instalator nie mają podpisu cyfrowego: „Więcej informacji” > „Uruchom mimo to” albo `SerwisDiag.cmd` |
| PDF się nie zapisuje | brak Microsoft Edge / Chrome albo zablokowany tryb bez okna (zasady firmowe) – otwórz raport i wydrukuj do pliku: Ctrl+P, „Microsoft Print to PDF” |

## Prywatność

Program pracuje lokalnie. Poza testami łączności (ping 1.1.1.1/8.8.8.8, DNS, kilka zapytań HTTP/HTTPS do Microsoft/Cloudflare/Google), wyszukiwaniem sterowników i aktualizacji w Windows Update (tak jak robi to sam Windows) i opcjonalnym testem prędkości nie wysyła żadnych danych do internetu; nie ma telemetrii. Strony producentów i Katalog Microsoft otwierają się w przeglądarce dopiero po kliknięciu. Nową wersję program sprawdza na GitHubie: na żądanie („Sprawdź nową wersję”), a w wersji zainstalowanej także raz na dobę (wyłączysz to w Ustawieniach). Pobiera ją dopiero po Twojej zgodzie. Monitorowanie w tle działa lokalnie i niczego nie wysyła. W trybie bez internetu program nie łączy się z niczym. Poza folderem programu zapisuje tylko pliki tymczasowe testów, raporty i stan monitorowania (`%LOCALAPPDATA%\SerwisDiag`). Raporty, dzienniki napraw i kopie przed reinstalacją zawierają dane klientów – przechowuj nośnik serwisowy bezpiecznie i usuwaj niepotrzebne pliki. Do konsultacji na forum używaj raportu anonimowego.

## Stan weryfikacji

Zweryfikowane na rzeczywistym komputerze: Windows 11 Pro (kompilacja 26300, 26H2), Windows PowerShell 5.1 – szybki skan bez uprawnień administratora (50 testów, ~40 s), okno programu (automatyczny przebieg ze zrzutami stron, okna ustawień i porównania), raporty i porównanie przed/po (także tryb konsolowy i porównanie dwóch zapisanych plików), wykrycie podmienionego i dopisanego pliku testu przed jego wykonaniem, przypisanie błędów dysku do odłączonego dysku USB, przekazywanie parametrów z cudzysłowami do `powershell.exe`, tryb bez internetu (konsola i okno), wyszukiwanie sterowników w Windows Update (w diagnostyce i w oknie „Sterowniki z Windows Update”), okno brakujących sterowników (na przykładowych danych), wykrywanie napraw i okno „Napraw problemy” na wyniku prawdziwej diagnostyki, wykonanie nieszkodliwej naprawy (czyszczenie DNS) bezpośrednim wywołaniem silnika napraw – samo okno do wersji 1.1.0 nie wykonywało napraw (zob. 1.1.1), 326 testów jednostkowych (m.in. ocena ESU, wybór edycji z obrazu ISO, wybór i wykonanie napraw, dziennik zmian rejestru, parser SMART – na danych przykładowych). Ponowne uruchomienie przez UAC (`-Elevate`) sprawdzone w trybie konsolowym i w oknie programu: parametry z cudzysłowami, polskimi znakami i ukośnikiem na końcu dochodzą bez zmian, ścieżki względne nie trafiają do System32, skan z uprawnieniami – 0 pominiętych testów i 0 błędów. **Nieprzetestowane na żywym sprzęcie:** Windows 8/8.1/10 (w tym wykrywanie ESU – brak komputera z Windows 10), instalacja sterowników z Windows Update i naprawy zmieniające system (DISM, SFC, reset Windows Update, zmiany rejestru i usług – mechanizm sprawdzony na naprawach przykładowych, prawdziwe naprawy nie zostały wykonane na komputerze testowym), DISM z płyty/ISO (wymaga obrazu Windows), przycisk „Uruchom jako administrator” w oknie (ten sam mechanizm, nie kliknięty w teście), SMART dysków SATA/HDD (komputer testowy ma tylko NVMe; dysk USB odczytany przez liczniki niezawodności Windows). Kod ograniczono do konstrukcji PowerShell 3.0 / .NET 4.5 i sprawdzono statycznie (`tools\check.ps1`).

**Wersja 1.1.0 – sprawdzone na tym samym komputerze, bez uprawnień administratora:**
- wykrywanie trybu ograniczonego (symulowane ustawieniem trybu sesji; kod 5, komunikat);
- okno programu w zwykłym rozmiarze i jak na ekranie 1366×768 przy powiększeniu 125% (z banerem starej bazy wiedzy);
- nowe okna: „O programie”, „Cofanie napraw” z przykładowym dziennikiem, „Kopia przed reinstalacją”, ustawienia;
- zapis PDF przez Microsoft Edge: A4, 1,7 s, także ze ścieżki ze spacją;
- raport anonimowy z prawdziwej diagnostyki: nazwa komputera, konto, numer seryjny, profil, 3 adresy MAC i 28 adresów IP z pełnego raportu nie występują w wersji anonimowej;
- kopia przed reinstalacją: lista programów i dane systemu (bez uprawnień), a jako administrator eksport sterowników. Do folderu ze spacją i polskimi znakami wyeksportowało się 110 pakietów, 8,2 GB, w 70 s. Zbyt długi folder program wykrywa przed uruchomieniem DISM;
- cofanie zmian rejestru (DWORD, Binary, ExpandString, MultiString, usunięte i dodane wartości, wartość zmieniona po naprawie) na kluczu testowym w HKCU;
- paczka ZIP z `tools\Build-Release.ps1`;
- 390 testów jednostkowych.

**Wersja 1.1.0 – niesprawdzone:**
- cofanie zmian usług, zapory i SMB1 oraz eksport profili Wi-Fi i kluczy BitLocker (wymagają administratora), a także przywracanie wyeksportowanych sterowników po reinstalacji;
- zapis PDF na Windows 8.1 (ostatni Edge dla 8.1 to wersja 109) i na komputerze bez Edge;
- sprawdzanie nowej wersji na prawdziwym repozytorium (projekt nie jest jeszcze opublikowany; sprawdzone na przykładowej odpowiedzi GitHuba);
- zachowanie na komputerze z faktycznie włączonym Smart App Control albo AppLocker.

**Wersja 1.1.1 – sprawdzone:**
- prawdziwe okno „Napraw problemy” z dwiema naprawami przykładowymi i zastępczym punktem przywracania (bez zmian w systemie): lista, punkt przywracania, wykonanie, wynik „wykonano 2 z 2” i dziennik napraw;
- testy całej ścieżki okna napraw na naprawach przykładowych. Na kopii programu z przywróconym błędem 1.1.0 nowe testy kończą się niepowodzeniem;
- 405 testów jednostkowych.

**Wersja 1.1.1 – niesprawdzone:** prawdziwe naprawy uruchomione z okna (reset Windows Update, sterowniki, czyszczenie plików) – ich kod się nie zmienił, ale przez błąd okna nigdy nie zostały wykonane z jego poziomu.

**Wersja 1.2.0 – sprawdzone:**
- instalator „dla bieżącego użytkownika” bez okien: pliki zgodne z manifestem, skróty w menu Start i na pulpicie, wpis w Aplikacjach, diagnostyka uruchomiona z folderu instalacji, aktualizacja (plik poprzedniej wersji usunięty, ustawienia zachowane) i odinstalowanie (folder, skróty i wpis usunięte);
- instalacja dla wszystkich użytkowników (z UAC): folder `C:\Program Files\SerwisDiag`, wpis w Aplikacjach (HKLM), skróty w menu Start i na pulpicie dla wszystkich. Bez uprawnień administratora nie da się zapisać ani zmienić żadnego pliku programu;
- okno programu uruchomione ze skrótu w Program Files, z uprawnieniami administratora: diagnostyka, raporty w `Dokumenty\SerwisDiag`, bez błędów startu. Po odinstalowaniu raporty w Dokumentach zostają;
- okno wyboru typu instalacji i strona licencji z polskimi znakami (zrzuty ekranu);
- 410 testów jednostkowych.

**Wersja 1.2.0 – niesprawdzone:** przejście całego kreatora myszą, instalator na Windows 8/8.1/10 i zachowanie SmartScreen po pobraniu instalatora z internetu.

**Wersja 1.2.1 – sprawdzone:** test „Dostępne aktualizacje” uruchomiony na żywo – oczekująca aktualizacja definicji Microsoft Defender daje wynik OK zamiast ostrzeżenia; obliczenie zwolnionego miejsca dla 8,6 GB (samego czyszczenia nie uruchamiano ponownie); 412 testów jednostkowych.

**Wersja 1.3.0 – sprawdzone:**
- testy zdarzeń na żywo: restarty, błędy dysku, usługi i sterowniki pokazują datę ostatniego zdarzenia;
- porównanie prawdziwego raportu z wersji 1.2.0 (pełna diagnostyka) z nową diagnostyką: 3 ostrzeżenia z historii zdarzeń w sekcji „Bez nowych zdarzeń”, Secure Boot w „Nadal wymagają uwagi”, nagłówek „Rozwiązano 0 z 4 problemów, bez nowych zdarzeń: 3” (zrzut raportu dla klienta);
- 423 testy jednostkowe.

**Wersja 1.3.0 – niesprawdzone:** porównanie, w którym zdarzenie z historii powtórzyło się po naprawie, na prawdziwym komputerze (sprawdzone tylko na danych przykładowych).

**Wersja 1.4.0 – sprawdzone:**
- monitor w tle na żywo: pierwsze sprawdzenie (2 znane problemy, jedno powiadomienie zbiorcze, ikona z żółtą kropką, okno wyników), drugie bez powiadomienia o tych samych problemach;
- pełny cykl z prawdziwym instalatorem (wersja testowa obok programu, instalacja dla bieżącego użytkownika): instalacja z monitorem (autostart, monitor działa), aktualizacja z zainstalowanej kopii do wyższej wersji (pobranie, kontrola sumy i wersji, instalator w tym samym trybie, monitor uruchomiony ponownie w nowej wersji), odinstalowanie (folder, wpis w Aplikacjach i autostart usunięte, monitor zakończony);
- okno ustawień z nowymi opcjami i baner nowej wersji (zrzuty);
- 451 testów jednostkowych (m.in. kontrola sumy i numeru wersji pobranego instalatora, porównanie stanu monitora, zadanie Harmonogramu).

**Wersja 1.4.0 – niesprawdzone:** instalacja dla wszystkich użytkowników z zadaniem Harmonogramu (wymaga UAC), ponowne uruchomienie programu po aktualizacji z okna (/RELAUNCH), aktualizacja z prawdziwego wydania na GitHubie do nowszej wersji (1.4.0 to pierwsze wydanie – przed publikacją sprawdzone na plikach lokalnych o tym samym formacie).
