# Cykl wsparcia Windows według numeru kompilacji (build).
# Home = Home/Pro/Pro Education/Pro for Workstations, Ent = Enterprise/Education/IoT Enterprise.
# Dane zweryfikowano 2026-10-22. Aktualizuj ręcznie: https://learn.microsoft.com/lifecycle
@{
    Verified    = '2026-10-22'
    LatestWin11 = '26H2'
    Builds      = @{
        '9200'  = @{ Name = 'Windows 8';        Home = '2016-01-12'; Ent = '2016-01-12'; Note = 'Wsparcie zakończyło się 12.01.2016 (należało przejść na Windows 8.1).' }
        '9600'  = @{ Name = 'Windows 8.1';      Home = '2023-01-10'; Ent = '2023-01-10'; Note = '' }
        '10240' = @{ Name = 'Windows 10 1507';  Home = '2017-05-09'; Ent = '2017-05-09'; Note = '' }
        '10586' = @{ Name = 'Windows 10 1511';  Home = '2017-10-10'; Ent = '2017-10-10'; Note = '' }
        '14393' = @{ Name = 'Windows 10 1607';  Home = '2018-04-10'; Ent = '2019-04-09'; Note = '' }
        '15063' = @{ Name = 'Windows 10 1703';  Home = '2018-10-09'; Ent = '2019-10-08'; Note = '' }
        '16299' = @{ Name = 'Windows 10 1709';  Home = '2019-04-09'; Ent = '2020-10-13'; Note = '' }
        '17134' = @{ Name = 'Windows 10 1803';  Home = '2019-11-12'; Ent = '2021-05-11'; Note = '' }
        '17763' = @{ Name = 'Windows 10 1809';  Home = '2020-11-10'; Ent = '2021-05-11'; Note = '' }
        '18362' = @{ Name = 'Windows 10 1903';  Home = '2020-12-08'; Ent = '2020-12-08'; Note = '' }
        '18363' = @{ Name = 'Windows 10 1909';  Home = '2021-05-11'; Ent = '2022-05-10'; Note = '' }
        '19041' = @{ Name = 'Windows 10 2004';  Home = '2021-12-14'; Ent = '2021-12-14'; Note = '' }
        '19042' = @{ Name = 'Windows 10 20H2';  Home = '2022-05-10'; Ent = '2023-05-09'; Note = '' }
        '19043' = @{ Name = 'Windows 10 21H1';  Home = '2022-12-13'; Ent = '2022-12-13'; Note = '' }
        '19044' = @{ Name = 'Windows 10 21H2';  Home = '2023-06-13'; Ent = '2024-06-11'; Note = '' }
        '19045' = @{ Name = 'Windows 10 22H2';  Home = '2025-10-14'; Ent = '2025-10-14'; Note = 'Ostatnia wersja Windows 10. Dalsze poprawki bezpieczeństwa tylko w programie rozszerzonych aktualizacji (ESU).' }
        '22000' = @{ Name = 'Windows 11 21H2';  Home = '2023-10-10'; Ent = '2024-10-08'; Note = '' }
        '22621' = @{ Name = 'Windows 11 22H2';  Home = '2024-10-08'; Ent = '2025-10-14'; Note = '' }
        '22631' = @{ Name = 'Windows 11 23H2';  Home = '2025-11-11'; Ent = '2026-11-10'; Note = '' }
        '26100' = @{ Name = 'Windows 11 24H2';  Home = '2026-10-13'; Ent = '2027-10-12'; Note = '' }
        '26200' = @{ Name = 'Windows 11 25H2';  Home = '2027-10-12'; Ent = '2028-10-10'; Note = '' }
        '26300' = @{ Name = 'Windows 11 26H2';  Home = '2028-10-10'; Ent = '2029-10-09'; Note = '' }
    }
    # Rozszerzone aktualizacje zabezpieczeń (ESU) dla Windows 10 22H2 (zweryfikowano 2026-10-22):
    #  - program konsumencki (Home/Pro) przedłużony do 12.10.2027; zapisane urządzenia przechodzą automatycznie,
    #  - firmy i edukacja (klucz ESU): rok 1 do 13.10.2026, rok 2 do 12.10.2027, rok 3 do 10.10.2028.
    # LastFreeUbr: KB5066791 (19045.6456, 14.10.2025) - ostatnia aktualizacja zbiorcza bez ESU; wyższy numer = zainstalowano poprawkę ESU.
    Esu         = @{
        '19045' = @{
            LastFreeUbr   = 6456
            Consumer      = '2027-10-12'
            Years         = @{ 1 = '2026-10-13'; 2 = '2027-10-12'; 3 = '2028-10-10' }
            ActivationIds = @{ 'f520e45e-7413-4a34-a497-d2765967d094' = 1; '1043add5-23b1-4afb-9a0f-64343c8f3f8d' = 2; '83d49986-add3-41d7-ba33-87c7bfb5c0fb' = 3 }
        }
    }
    # Edycje LTSC / LTSB mają odrębny, dłuższy cykl.
    Ltsc        = @{ '10240' = '2025-10-14'; '14393' = '2026-10-13'; '17763' = '2029-01-09'; '19044' = '2027-01-12'; '26100' = '2029-10-09' }
    IotLtsc     = @{ '10240' = '2025-10-14'; '14393' = '2026-10-13'; '17763' = '2029-01-09'; '19044' = '2032-01-13'; '26100' = '2034-10-10' }
}
