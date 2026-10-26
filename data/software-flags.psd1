# Reguły oceny zainstalowanego oprogramowania. Pattern = wyrażenie regularne dopasowywane do nazwy programu.
# Type: optimizer | pup | remote | crack | eol | trial | av
# Severity: info | warn  (dla typu av ocena następuje w teście bezpieczeństwa)
# End = data końca wsparcia (dla typu eol; po tej dacie -> ostrzeżenie)
# To są wskazówki do weryfikacji przez technika, nie wyrok - dopasowanie po nazwie bywa mylące.
@{
    Flags = @(
        @{ Pattern = 'Driver Booster|Driver Easy|DriverPack|Driver Talent|DriverMax|Snappy Driver|Driver Updater|Driver Reviver|Driver Genius'; Type = 'optimizer'; Severity = 'warn'
           Note = 'Programy do „automatycznej aktualizacji sterowników" często instalują niewłaściwe sterowniki i wyświetlają reklamy. Sterowniki najlepiej pobierać od producenta sprzętu.' }
        @{ Pattern = 'Advanced SystemCare|IObit|Smart Defrag|Wise Care|Wise Registry|Registry Cleaner|Registry Mechanic|Auslogics|SlimCleaner|PC Optimizer|PC Cleaner|MyCleanPC|SpeedUpMyPC|Smart PC Fixer|Reimage|Restoro|Outbyte|PC Speed|System Mechanic|TuneUp Utilities|Glary'; Type = 'optimizer'; Severity = 'info'
           Note = 'Optymalizatory i „czyściciele rejestru" zwykle nie poprawiają wydajności, a bywają natrętne lub szkodliwe.' }
        @{ Pattern = 'Ask Toolbar|Babylon|Conduit|Delta Search|Search Protect|Wajam|Yontoo|OpenCandy|Crossrider|SweetIM|Mindspark|MyWebSearch|Genieo|Trovi|Snap\.do|PriceGong|WebDiscover|Spigot|Bandoo|iLivid|Linkury|SearchAwesome|Web Companion'; Type = 'pup'; Severity = 'warn'
           Note = 'Prawdopodobnie niechciane oprogramowanie (PUP): paski narzędzi lub program przejmujący przeglądarkę. Zalecane usunięcie.' }
        @{ Pattern = 'McAfee|Norton'; Type = 'trial'; Severity = 'info'
           Note = 'Często fabrycznie zainstalowana wersja próbna; po wygaśnięciu licencji ogranicza ochronę, spowalnia system i wyświetla powiadomienia.' }
        @{ Pattern = 'McAfee|Norton|Avast|AVG |Kaspersky|Bitdefender|ESET|Avira|Panda|Trend Micro|F-Secure|Sophos|Dr\.Web|360 Total|Comodo|G DATA|Webroot'; Type = 'av'; Severity = 'info'
           Note = 'Pakiet antywirusowy.' }
        @{ Pattern = 'AnyDesk|TeamViewer|UltraViewer|RustDesk|LogMeIn|Splashtop|ScreenConnect|ConnectWise|Chrome Remote Desktop|Ammyy|Supremo|Radmin|TightVNC|UltraVNC|RealVNC|NinjaRMM|Atera|Zoho Assist|RemotePC|DWService|AweSun|Lite Manager'; Type = 'remote'; Severity = 'info'
           Note = 'Narzędzie zdalnego dostępu. Upewnij się, że zostało zainstalowane świadomie - oszuści podszywający się pod „serwis" często proszą o instalację takiego programu.' }
        @{ Pattern = 'KMSpico|KMSAuto|KMS ?Pico|Microsoft Toolkit|AAct|HEU KMS|Re-?Loader|Windows Loader|Daz Loader|Chew-?WGA'; Type = 'crack'; Severity = 'warn'
           Note = 'Narzędzie do obchodzenia aktywacji - bardzo często zawiera złośliwe oprogramowanie. Zalecana weryfikacja systemu i legalna licencja.' }
        @{ Pattern = 'Adobe Flash Player'; Type = 'eol'; Severity = 'warn'; End = '2020-12-31'
           Note = 'Adobe Flash Player nie jest wspierany od 31.12.2020 - usuń.' }
        @{ Pattern = 'Microsoft Silverlight'; Type = 'eol'; Severity = 'info'; End = '2021-10-12'
           Note = 'Silverlight nie jest wspierany od października 2021.' }
        @{ Pattern = 'QuickTime'; Type = 'eol'; Severity = 'warn'; End = '2016-04-01'
           Note = 'Apple QuickTime dla Windows nie jest rozwijany od 2016 r. i ma niezałatane luki - usuń.' }
        @{ Pattern = 'Java\(TM\) (6|7)\b|Java 6|Java 7|J2SE'; Type = 'eol'; Severity = 'warn'; End = '2019-01-01'
           Note = 'Bardzo stara wersja Javy z niezałatanymi lukami - usuń lub zaktualizuj.' }
        @{ Pattern = 'Microsoft Office.*\b2007\b'; Type = 'eol'; Severity = 'warn'; End = '2017-10-10'
           Note = 'Office 2007 nie jest wspierany od 10.10.2017.' }
        @{ Pattern = 'Microsoft Office.*\b2010\b'; Type = 'eol'; Severity = 'warn'; End = '2020-10-13'
           Note = 'Office 2010 nie jest wspierany od 13.10.2020.' }
        @{ Pattern = 'Microsoft Office.*\b2013\b'; Type = 'eol'; Severity = 'warn'; End = '2023-04-11'
           Note = 'Office 2013 nie jest wspierany od 11.04.2023.' }
        @{ Pattern = 'Microsoft Office.*\b(2016|2019)\b'; Type = 'eol'; Severity = 'warn'; End = '2025-10-14'
           Note = 'Office 2016 i 2019 nie są wspierane od 14.10.2025.' }
        @{ Pattern = 'Microsoft Office.*\b2021\b|Office LTSC 2021'; Type = 'eol'; Severity = 'warn'; End = '2026-10-13'
           Note = 'Office 2021 nie jest wspierany od 13.10.2026.' }
    )
}
