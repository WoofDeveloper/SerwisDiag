# Znaczenie wybranych zdarzeń systemowych. Klucz: "Dostawca|Id" (lub "*|Id" dla dowolnego dostawcy).
# Sev: crit | warn | info | noise (noise = znany, zwykle nieszkodliwy komunikat)
@{
    Hints = @{
        'disk|7'     = @{ Sev = 'crit'; Text = 'Uszkodzony sektor na dysku (bad block). Sprawdź SMART i wykonaj kopię danych.' }
        'disk|9'     = @{ Sev = 'warn'; Text = 'Przekroczono czas operacji dyskowej (timeout).' }
        'disk|11'    = @{ Sev = 'warn'; Text = 'Kontroler dysku zgłosił błąd - kabel, kontroler lub dysk.' }
        'disk|15'    = @{ Sev = 'warn'; Text = 'Urządzenie dyskowe nie jest gotowe do dostępu.' }
        'disk|51'    = @{ Sev = 'crit'; Text = 'Błąd podczas stronicowania (odczyt/zapis pliku wymiany) - dysk lub kontroler.' }
        'disk|52'    = @{ Sev = 'crit'; Text = 'Dysk przewiduje awarię (SMART)! Natychmiast wykonaj kopię danych.' }
        'disk|153'   = @{ Sev = 'warn'; Text = 'Operacja I/O dysku została ponowiona - niestabilny dysk lub kabel.' }
        'Ntfs|55'    = @{ Sev = 'crit'; Text = 'Uszkodzona struktura systemu plików NTFS - uruchom chkdsk.' }
        'Ntfs|137'   = @{ Sev = 'warn'; Text = 'Nie można zainicjować transakcyjnego systemu plików.' }
        'Ntfs|140'   = @{ Sev = 'warn'; Text = 'Nie można zapisać danych w dzienniku transakcji NTFS.' }
        'Microsoft-Windows-Ntfs|55'  = @{ Sev = 'crit'; Text = 'Uszkodzona struktura systemu plików NTFS - uruchom chkdsk.' }
        'Microsoft-Windows-Ntfs|140' = @{ Sev = 'warn'; Text = 'Nie można zapisać danych w dzienniku transakcji NTFS.' }
        'volmgr|46'  = @{ Sev = 'warn'; Text = 'Nie można utworzyć zrzutu pamięci przy awarii (błąd dysku lub pliku wymiany).' }
        'volmgr|161' = @{ Sev = 'info'; Text = 'Nie można utworzyć zrzutu awaryjnego.' }
        # 129 = reset urządzenia; identyfikator 129 mają też niezwiązane zdarzenia (np. Hyper-V), więc tylko dla sterowników pamięci masowej
        'storahci|129'  = @{ Sev = 'warn'; Text = 'Reset urządzenia pamięci masowej (timeout kontrolera SATA) - firmware dysku, zasilanie, kabel lub sterownik.' }
        'stornvme|129'  = @{ Sev = 'warn'; Text = 'Reset kontrolera NVMe - firmware SSD, zasilanie lub sterownik.' }
        'iaStorA|129'   = @{ Sev = 'warn'; Text = 'Reset urządzenia (Intel RST) - firmware dysku, zasilanie, kabel lub sterownik.' }
        'iaStorAC|129'  = @{ Sev = 'warn'; Text = 'Reset urządzenia (Intel RST) - firmware dysku, zasilanie, kabel lub sterownik.' }
        'iaStorAVC|129' = @{ Sev = 'warn'; Text = 'Reset urządzenia (Intel RST/VMD) - firmware dysku, zasilanie lub sterownik.' }
        'nvstor|129'    = @{ Sev = 'warn'; Text = 'Reset urządzenia (NVIDIA nForce) - kabel, zasilanie lub sterownik.' }
        'amdsata|129'   = @{ Sev = 'warn'; Text = 'Reset urządzenia (AMD SATA) - kabel, zasilanie lub sterownik.' }
        'Microsoft-Windows-StorPort|129' = @{ Sev = 'warn'; Text = 'Reset urządzenia pamięci masowej (StorPort).' }
        'Microsoft-Windows-WHEA-Logger|1'  = @{ Sev = 'crit'; Text = 'Fatalny błąd sprzętowy (WHEA) - CPU, RAM, PCIe lub zasilanie.' }
        'Microsoft-Windows-WHEA-Logger|17' = @{ Sev = 'warn'; Text = 'Poprawiony błąd sprzętowy magistrali PCIe (WHEA).' }
        'Microsoft-Windows-WHEA-Logger|18' = @{ Sev = 'crit'; Text = 'Fatalny błąd sprzętowy maszyny (Machine Check) - CPU lub RAM.' }
        'Microsoft-Windows-WHEA-Logger|19' = @{ Sev = 'warn'; Text = 'Poprawiony błąd sprzętowy procesora lub pamięci (WHEA).' }
        'Microsoft-Windows-WHEA-Logger|20' = @{ Sev = 'warn'; Text = 'Poprawiony błąd sprzętowy PCIe (WHEA).' }
        'Microsoft-Windows-WHEA-Logger|47' = @{ Sev = 'warn'; Text = 'Poprawiony błąd sprzętowy (Corrected Machine Check).' }
        'Microsoft-Windows-Kernel-Power|41'  = @{ Sev = 'crit'; Text = 'Komputer uruchomił się ponownie bez prawidłowego zamknięcia (awaria, utrata zasilania, przegrzanie lub reset).' }
        'Microsoft-Windows-Kernel-Power|109' = @{ Sev = 'warn'; Text = 'Błąd zasilania jądra - wyłączenie awaryjne.' }
        'EventLog|6008' = @{ Sev = 'warn'; Text = 'Poprzednie zamknięcie systemu było nieoczekiwane.' }
        'Microsoft-Windows-Kernel-Processor-Power|37' = @{ Sev = 'warn'; Text = 'Procesor jest ograniczany przez firmware (throttling) - przegrzanie lub limity zasilania.' }
        'Microsoft-Windows-Kernel-PnP|219' = @{ Sev = 'warn'; Text = 'Nie można załadować sterownika urządzenia.' }
        'Display|4101' = @{ Sev = 'warn'; Text = 'Sterownik grafiki przestał odpowiadać i został zresetowany (TDR).' }
        'nvlddmkm|13'  = @{ Sev = 'warn'; Text = 'Błąd sterownika NVIDIA (zawieszenie GPU).' }
        'nvlddmkm|14'  = @{ Sev = 'warn'; Text = 'Błąd sterownika NVIDIA (zawieszenie GPU).' }
        'Service Control Manager|7000' = @{ Sev = 'warn'; Text = 'Usługa nie uruchomiła się (błąd konfiguracji lub logowania).' }
        'Service Control Manager|7001' = @{ Sev = 'warn'; Text = 'Usługa nie uruchomiła się z powodu usługi, od której zależy.' }
        'Service Control Manager|7009' = @{ Sev = 'warn'; Text = 'Przekroczono czas oczekiwania na uruchomienie usługi.' }
        'Service Control Manager|7011' = @{ Sev = 'warn'; Text = 'Przekroczono czas odpowiedzi usługi.' }
        'Service Control Manager|7023' = @{ Sev = 'warn'; Text = 'Usługa zakończyła się z błędem.' }
        'Service Control Manager|7024' = @{ Sev = 'warn'; Text = 'Usługa zakończyła się z błędem specyficznym dla usługi.' }
        'Service Control Manager|7031' = @{ Sev = 'warn'; Text = 'Usługa zakończyła się nieoczekiwanie.' }
        'Service Control Manager|7034' = @{ Sev = 'warn'; Text = 'Usługa zakończyła się nieoczekiwanie.' }
        'Application Error|1000' = @{ Sev = 'info'; Text = 'Awaria aplikacji.' }
        'Application Hang|1002'  = @{ Sev = 'info'; Text = 'Aplikacja przestała odpowiadać.' }
        '.NET Runtime|1026'      = @{ Sev = 'info'; Text = 'Nieobsłużony wyjątek w aplikacji .NET.' }
        'Microsoft-Windows-WindowsUpdateClient|20' = @{ Sev = 'warn'; Text = 'Instalacja aktualizacji nie powiodła się.' }
        'Microsoft-Windows-WindowsUpdateClient|31' = @{ Sev = 'warn'; Text = 'Pobieranie aktualizacji nie powiodło się.' }
        'Microsoft-Windows-DistributedCOM|10016' = @{ Sev = 'noise'; Text = 'Znany, nieszkodliwy komunikat uprawnień DCOM (można zignorować).' }
        'Microsoft-Windows-DistributedCOM|10010' = @{ Sev = 'noise'; Text = 'Serwer DCOM nie zarejestrował się w wymaganym czasie (zwykle nieszkodliwe).' }
        'Schannel|36887' = @{ Sev = 'noise'; Text = 'Odebrano alert TLS od zdalnego serwera (zwykle nieszkodliwe).' }
        'Schannel|36874' = @{ Sev = 'noise'; Text = 'Żądanie TLS nieobsługiwanej wersji protokołu (zwykle nieszkodliwe).' }
        'Microsoft-Windows-Time-Service|134' = @{ Sev = 'noise'; Text = 'Nie udało się zsynchronizować czasu z serwerem NTP (zwykle chwilowe).' }
    }
}
