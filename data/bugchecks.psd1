# Kody STOP (BugCheck) - nazwa, kategoria przyczyny i wskazówka diagnostyczna.
# Klucz = kod szesnastkowy wielkimi literami, bez zer wiodących.
# Cause: driver | memory | disk | hardware | gpu | power | system
@{
    '1'        = @{ Name = 'APC_INDEX_MISMATCH'; Cause = 'driver'; Hint = 'Błąd sterownika urządzenia. Zaktualizuj lub usuń ostatnio zainstalowane sterowniki.' }
    'A'        = @{ Name = 'IRQL_NOT_LESS_OR_EQUAL'; Cause = 'driver'; Hint = 'Sterownik lub sprzęt odwołał się do pamięci przy zbyt wysokim poziomie IRQL. Najczęściej wadliwy sterownik, rzadziej uszkodzony RAM. Zaktualizuj sterowniki i przetestuj pamięć.' }
    '12'       = @{ Name = 'TRAP_CAUSE_UNKNOWN'; Cause = 'hardware'; Hint = 'Nieznana przyczyna pułapki procesora - podejrzewaj sprzęt (RAM, zasilanie, przegrzanie).' }
    '19'       = @{ Name = 'BAD_POOL_HEADER'; Cause = 'driver'; Hint = 'Uszkodzony nagłówek puli pamięci - zwykle sterownik lub RAM.' }
    '1A'       = @{ Name = 'MEMORY_MANAGEMENT'; Cause = 'memory'; Hint = 'Poważny błąd zarządzania pamięcią. Podejrzewaj kości RAM (MemTest86 / Diagnostyka pamięci Windows), potem dysk i sterowniki.' }
    '1E'       = @{ Name = 'KMODE_EXCEPTION_NOT_HANDLED'; Cause = 'driver'; Hint = 'Nieobsłużony wyjątek w trybie jądra - zwykle sterownik lub niezgodne oprogramowanie, czasem RAM.' }
    '24'       = @{ Name = 'NTFS_FILE_SYSTEM'; Cause = 'disk'; Hint = 'Błąd systemu plików NTFS. Sprawdź dysk (SMART, chkdsk), kabel SATA i kontroler.' }
    '2E'       = @{ Name = 'DATA_BUS_ERROR'; Cause = 'memory'; Hint = 'Błąd parzystości pamięci - uszkodzony RAM, płyta główna lub dysk.' }
    '3B'       = @{ Name = 'SYSTEM_SERVICE_EXCEPTION'; Cause = 'driver'; Hint = 'Wyjątek podczas wywołania usługi systemowej. Często sterownik grafiki, antywirus lub uszkodzone pliki systemu (sfc /scannow, DISM).' }
    '3F'       = @{ Name = 'NO_MORE_SYSTEM_PTES'; Cause = 'driver'; Hint = 'Wyczerpanie zasobów systemowych - zwykle wyciek w sterowniku.' }
    '41'       = @{ Name = 'MUST_SUCCEED_POOL_EMPTY'; Cause = 'driver'; Hint = 'Wyczerpanie puli pamięci jądra - wyciek w sterowniku.' }
    '4E'       = @{ Name = 'PFN_LIST_CORRUPT'; Cause = 'memory'; Hint = 'Uszkodzona lista ramek pamięci - RAM lub sterownik.' }
    '50'       = @{ Name = 'PAGE_FAULT_IN_NONPAGED_AREA'; Cause = 'memory'; Hint = 'Odwołanie do nieistniejącej pamięci. Najczęściej RAM lub sterownik; także antywirus i uszkodzony dysk.' }
    '51'       = @{ Name = 'REGISTRY_ERROR'; Cause = 'disk'; Hint = 'Błąd odczytu rejestru - problem z dyskiem lub uszkodzony plik rejestru.' }
    '6B'       = @{ Name = 'PROCESS1_INITIALIZATION_FAILED'; Cause = 'system'; Hint = 'Nie udało się zainicjować systemu - uszkodzona instalacja, uruchom naprawę rozruchu.' }
    '74'       = @{ Name = 'BAD_SYSTEM_CONFIG_INFO'; Cause = 'system'; Hint = 'Uszkodzony rejestr lub BCD - napraw rozruch / przywróć system.' }
    '77'       = @{ Name = 'KERNEL_STACK_INPAGE_ERROR'; Cause = 'disk'; Hint = 'Nie można odczytać stosu jądra z pliku wymiany - dysk, kontroler lub kabel SATA. Sprawdź SMART.' }
    '7A'       = @{ Name = 'KERNEL_DATA_INPAGE_ERROR'; Cause = 'disk'; Hint = 'Nie można odczytać strony danych z dysku - uszkodzony dysk, kabel lub kontroler, rzadziej RAM.' }
    '7B'       = @{ Name = 'INACCESSIBLE_BOOT_DEVICE'; Cause = 'disk'; Hint = 'System nie widzi dysku rozruchowego - tryb kontrolera w BIOS (AHCI/RAID/VMD), uszkodzony dysk lub brak sterownika kontrolera.' }
    '7E'       = @{ Name = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED'; Cause = 'driver'; Hint = 'Nieobsłużony wyjątek wątku systemowego - najczęściej sterownik.' }
    '7F'       = @{ Name = 'UNEXPECTED_KERNEL_MODE_TRAP'; Cause = 'hardware'; Hint = 'Nieoczekiwana pułapka procesora - RAM, przegrzanie, podkręcanie lub błąd sprzętowy.' }
    '8E'       = @{ Name = 'KERNEL_MODE_EXCEPTION_NOT_HANDLED_M'; Cause = 'driver'; Hint = 'Nieobsłużony wyjątek trybu jądra - sterownik lub RAM.' }
    '9C'       = @{ Name = 'MACHINE_CHECK_EXCEPTION'; Cause = 'hardware'; Hint = 'Błąd sprzętowy zgłoszony przez procesor (CPU, RAM, zasilanie, przegrzanie, podkręcanie).' }
    '9F'       = @{ Name = 'DRIVER_POWER_STATE_FAILURE'; Cause = 'driver'; Hint = 'Sterownik nie obsłużył zmiany stanu zasilania (uśpienie/hibernacja). Zaktualizuj sterowniki (sieć, grafika, chipset); wyłącz szybkie uruchamianie jako test.' }
    'A0'       = @{ Name = 'INTERNAL_POWER_ERROR'; Cause = 'power'; Hint = 'Wewnętrzny błąd zasilania - zaktualizuj BIOS i sterowniki chipsetu.' }
    'A5'       = @{ Name = 'ACPI_BIOS_ERROR'; Cause = 'hardware'; Hint = 'Błąd BIOS/ACPI - zaktualizuj BIOS lub zresetuj jego ustawienia.' }
    'BE'       = @{ Name = 'ATTEMPTED_WRITE_TO_READONLY_MEMORY'; Cause = 'driver'; Hint = 'Próba zapisu do pamięci tylko do odczytu - sterownik.' }
    'C1'       = @{ Name = 'SPECIAL_POOL_DETECTED_MEMORY_CORRUPTION'; Cause = 'driver'; Hint = 'Wykryto uszkodzenie pamięci przez sterownik.' }
    'C2'       = @{ Name = 'BAD_POOL_CALLER'; Cause = 'driver'; Hint = 'Błędne żądanie puli pamięci - sterownik.' }
    'C4'       = @{ Name = 'DRIVER_VERIFIER_DETECTED_VIOLATION'; Cause = 'driver'; Hint = 'Naruszenie wykryte przez Driver Verifier - wyłącz go (verifier /reset) i zaktualizuj wskazany sterownik.' }
    'C5'       = @{ Name = 'DRIVER_CORRUPTED_EXPOOL'; Cause = 'driver'; Hint = 'Uszkodzona pula pamięci - sterownik lub RAM.' }
    'C9'       = @{ Name = 'DRIVER_VERIFIER_IOMANAGER_VIOLATION'; Cause = 'driver'; Hint = 'Naruszenie wykryte przez Driver Verifier.' }
    'CE'       = @{ Name = 'DRIVER_UNLOADED_WITHOUT_CANCELLING_PENDING_OPERATIONS'; Cause = 'driver'; Hint = 'Sterownik zwolniony bez anulowania operacji - błąd sterownika.' }
    'D1'       = @{ Name = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL'; Cause = 'driver'; Hint = 'Sterownik odwołał się do pamięci przy zbyt wysokim IRQL. Najczęściej sterownik sieci/Wi-Fi, grafiki lub antywirus - zaktualizuj lub zainstaluj ponownie.' }
    'D3'       = @{ Name = 'DRIVER_PORTION_MUST_BE_NONPAGED'; Cause = 'driver'; Hint = 'Błąd sterownika.' }
    'D5'       = @{ Name = 'DRIVER_PAGE_FAULT_IN_FREED_SPECIAL_POOL'; Cause = 'driver'; Hint = 'Sterownik odwołał się do zwolnionej pamięci.' }
    'DA'       = @{ Name = 'SYSTEM_PTE_MISUSE'; Cause = 'driver'; Hint = 'Błąd sterownika.' }
    'DE'       = @{ Name = 'POOL_CORRUPTION_IN_FILE_AREA'; Cause = 'driver'; Hint = 'Uszkodzenie puli pamięci - sterownik lub RAM.' }
    'E2'       = @{ Name = 'MANUALLY_INITIATED_CRASH'; Cause = 'system'; Hint = 'Awaria wywołana ręcznie (np. Ctrl+Scroll Lock x2) - to nie usterka.' }
    'EA'       = @{ Name = 'THREAD_STUCK_IN_DEVICE_DRIVER'; Cause = 'gpu'; Hint = 'Sterownik urządzenia (zwykle grafiki) zawiesił się. Zaktualizuj sterownik GPU, sprawdź temperatury i zasilanie karty.' }
    'EF'       = @{ Name = 'CRITICAL_PROCESS_DIED'; Cause = 'system'; Hint = 'Zakończył się krytyczny proces systemowy - uszkodzone pliki systemowe, dysk lub sterownik. Uruchom sfc /scannow oraz DISM /RestoreHealth, sprawdź dysk.' }
    'F4'       = @{ Name = 'CRITICAL_OBJECT_TERMINATION'; Cause = 'disk'; Hint = 'Zakończono krytyczny proces - często dysk lub kontroler przestał odpowiadać. Sprawdź SMART i okablowanie.' }
    'F7'       = @{ Name = 'DRIVER_OVERRAN_STACK_BUFFER'; Cause = 'driver'; Hint = 'Przepełnienie bufora stosu w sterowniku.' }
    'FC'       = @{ Name = 'ATTEMPTED_EXECUTE_OF_NOEXECUTE_MEMORY'; Cause = 'driver'; Hint = 'Próba wykonania kodu z pamięci oznaczonej jako niewykonywalna - sterownik lub RAM.' }
    'FE'       = @{ Name = 'BUGCODE_USB_DRIVER'; Cause = 'driver'; Hint = 'Błąd sterownika USB - odłącz urządzenia USB, zaktualizuj sterowniki kontrolera.' }
    '101'      = @{ Name = 'CLOCK_WATCHDOG_TIMEOUT'; Cause = 'hardware'; Hint = 'Rdzeń procesora nie odpowiada. Przegrzanie, podkręcanie, zasilanie, BIOS lub uszkodzony CPU.' }
    '109'      = @{ Name = 'CRITICAL_STRUCTURE_CORRUPTION'; Cause = 'memory'; Hint = 'Wykryto modyfikację krytycznych struktur jądra - RAM, sterownik lub złośliwe oprogramowanie.' }
    '10E'      = @{ Name = 'VIDEO_MEMORY_MANAGEMENT_INTERNAL'; Cause = 'gpu'; Hint = 'Błąd pamięci karty graficznej - sterownik lub uszkodzona karta.' }
    '116'      = @{ Name = 'VIDEO_TDR_FAILURE'; Cause = 'gpu'; Hint = 'Sterownik grafiki nie odpowiedział i nie udało się go zresetować. Zainstaluj czysto sterownik GPU; sprawdź temperaturę, zasilanie i stabilność pamięci VRAM.' }
    '117'      = @{ Name = 'VIDEO_TDR_TIMEOUT_DETECTED'; Cause = 'gpu'; Hint = 'Przekroczono czas odpowiedzi sterownika grafiki.' }
    '119'      = @{ Name = 'VIDEO_SCHEDULER_INTERNAL_ERROR'; Cause = 'gpu'; Hint = 'Błąd harmonogramu grafiki - sterownik GPU lub sprzęt.' }
    '124'      = @{ Name = 'WHEA_UNCORRECTABLE_ERROR'; Cause = 'hardware'; Hint = 'Fatalny błąd sprzętowy zgłoszony przez WHEA (CPU, RAM, magistrala PCIe, zasilanie, przegrzanie, podkręcanie). Sprawdź temperatury, RAM i zasilacz; zresetuj OC/XMP.' }
    '133'      = @{ Name = 'DPC_WATCHDOG_VIOLATION'; Cause = 'driver'; Hint = 'Procedura DPC trwała zbyt długo. Zwykle sterownik kontrolera dysku (SATA/NVMe) lub firmware SSD, rzadziej sieć/dźwięk. Zaktualizuj firmware SSD i sterowniki chipsetu.' }
    '139'      = @{ Name = 'KERNEL_SECURITY_CHECK_FAILURE'; Cause = 'driver'; Hint = 'Naruszenie kontroli bezpieczeństwa jądra - sterownik, RAM lub dysk.' }
    '13A'      = @{ Name = 'KERNEL_MODE_HEAP_CORRUPTION'; Cause = 'driver'; Hint = 'Uszkodzenie sterty jądra - sterownik lub RAM.' }
    '141'      = @{ Name = 'VIDEO_ENGINE_TIMEOUT_DETECTED'; Cause = 'gpu'; Hint = 'Zawieszenie silnika graficznego - sterownik GPU, przegrzanie lub zasilanie.' }
    '144'      = @{ Name = 'BUGCODE_USB3_DRIVER'; Cause = 'driver'; Hint = 'Błąd sterownika USB 3 - zaktualizuj sterowniki kontrolera, odłącz urządzenia USB.' }
    '154'      = @{ Name = 'UNEXPECTED_STORE_EXCEPTION'; Cause = 'disk'; Hint = 'Błąd komponentu Store - często dysk/SSD, antywirus lub uszkodzone pliki. Sprawdź SMART i zaktualizuj firmware.' }
    'C000021A' = @{ Name = 'STATUS_SYSTEM_PROCESS_TERMINATED'; Cause = 'system'; Hint = 'Zakończono proces winlogon/csrss - uszkodzone pliki systemowe, nieudana aktualizacja lub niezgodny sterownik. Użyj środowiska odzyskiwania (WinRE).' }
    'C0000221' = @{ Name = 'STATUS_IMAGE_CHECKSUM_MISMATCH'; Cause = 'disk'; Hint = 'Uszkodzony plik systemowy lub błędy dysku. Sprawdź dysk, uruchom sfc /scannow i DISM.' }
}
