; SerwisDiag - skrypt instalatora dla Inno Setup 7 (https://jrsoftware.org). Plik w UTF-8 z BOM.
; Budowanie: powershell -ExecutionPolicy Bypass -File tools\Build-Release.ps1 - podaje wersję, folder z plikami programu
; i plik licencji, a gotowy SerwisDiag-<wersja>-setup.exe zapisuje w dist\ obok paczki ZIP.

#ifndef AppVersion
  #error Podaj wersję: /DAppVersion=x.y.z (robi to tools\Build-Release.ps1)
#endif
#ifndef SourceDir
  #error Podaj folder z plikami programu: /DSourceDir=... (robi to tools\Build-Release.ps1)
#endif
#ifndef LicensePath
  #define LicensePath SourceDir + "\LICENSE"
#endif
#ifndef OutDir
  #define OutDir "..\..\dist"
#endif
; AppId nie może się zmieniać między wersjami - po nim instalator rozpoznaje poprzednią instalację i ją aktualizuje.
; Inny identyfikator i nazwa tylko dla instalatora testowego (instaluje się obok prawdziwego programu).
#ifndef AppIdGuid
  #define AppIdGuid "AE0C12A0-8B14-4AB1-92F2-60F22A71E506"
#endif
#ifndef AppTitle
  #define AppTitle "SerwisDiag"
#endif

[Setup]
AppId={{{#AppIdGuid}}
AppName={#AppTitle}
AppVersion={#AppVersion}
AppPublisher=Kacper Suliński - INDUSIP.PL
AppCopyright=© 2026 Kacper Suliński - INDUSIP.PL
VersionInfoVersion={#AppVersion}
VersionInfoDescription=Instalator programu SerwisDiag
DefaultDirName={autopf}\{#AppTitle}
DisableProgramGroupPage=yes
; Domyślnie dla wszystkich użytkowników, w Program Files: program działa z uprawnieniami administratora, a tam
; jego plików nie podmieni proces bez tych uprawnień. „Tylko dla mnie” (okno wyboru albo /CURRENTUSER) nie wymaga UAC.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog commandline
MinVersion=6.2
ArchitecturesAllowed=x86compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile={#LicensePath}
SetupIconFile={#SourceDir}\assets\app.ico
UninstallDisplayIcon={app}\SerwisDiag.exe
UninstallDisplayName={#AppTitle}
OutputDir={#OutDir}
OutputBaseFilename=SerwisDiag-{#AppVersion}-setup
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "monitor"; Description: "Monitoruj system w tle (ikona przy zegarze, powiadomienia o nowych problemach)"; GroupDescription: "Monitorowanie:"

[InstallDelete]
; Aktualizacja: najpierw znikają pliki poprzedniej wersji. Plik, którego nowa wersja już nie ma, kontrola integralności
; uznałaby za dopisany i program by się nie uruchomił. Ustawienia (config) i raporty zostają.
Type: filesandordirs; Name: "{app}\lib"
Type: filesandordirs; Name: "{app}\checks"
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\assets"
Type: filesandordirs; Name: "{app}\tools"
Type: files; Name: "{app}\SerwisDiag*.cmd"
Type: files; Name: "{app}\SerwisDiag.ps1"
Type: files; Name: "{app}\SerwisDiag.exe"
Type: files; Name: "{app}\SerwisDiagMonitor.exe"
Type: files; Name: "{app}\manifest.sha256"

[Files]
; narzędzia programisty (tools) są tylko w paczce ZIP
Source: "{#SourceDir}\*"; Excludes: "\tools"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[INI]
; znacznik kopii zainstalowanej: program zapisuje wtedy raporty w Dokumenty\SerwisDiag, a nie obok siebie;
; tryb instalacji potrzebny przy aktualizacji (ten sam tryb, bez pytania)
Filename: "{app}\instalacja.ini"; Section: "SerwisDiag"; Key: "Wersja"; String: "{#AppVersion}"
Filename: "{app}\instalacja.ini"; Section: "SerwisDiag"; Key: "Tryb"; String: "wszyscy"; Check: IsAdminInstallMode
Filename: "{app}\instalacja.ini"; Section: "SerwisDiag"; Key: "Tryb"; String: "biezacy"; Check: not IsAdminInstallMode

[Icons]
Name: "{autoprograms}\{#AppTitle}"; Filename: "{app}\SerwisDiag.exe"; WorkingDir: "{app}"; Comment: "Diagnostyka i naprawa systemu Windows"
Name: "{autodesktop}\{#AppTitle}"; Filename: "{app}\SerwisDiag.exe"; WorkingDir: "{app}"; Comment: "Diagnostyka i naprawa systemu Windows"; Tasks: desktopicon

[Run]
; monitorowanie: autostart (instalacja dla wszystkich - zadanie Harmonogramu, wymaga uprawnień instalatora; dla mnie - wpis Run),
; poprzedni monitor kończy pracę, a nowy startuje jako użytkownik, który uruchomił instalator
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\SerwisDiag.ps1"" -EnableMonitor -NoStart"; Flags: runhidden waituntilterminated; Tasks: monitor; StatusMsg: "Włączanie monitorowania w tle..."
Filename: "{app}\SerwisDiagMonitor.exe"; Flags: nowait runasoriginaluser; Tasks: monitor
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\SerwisDiag.ps1"" -DisableMonitor"; Flags: runhidden waituntilterminated; Tasks: not monitor
; aktualizacja z programu (/RELAUNCH=1): po instalacji program uruchamia się ponownie
Filename: "{app}\SerwisDiag.exe"; Flags: nowait shellexec runasoriginaluser; Check: ShouldRelaunch
; shellexec: SerwisDiag.exe wymaga uprawnień administratora, więc Windows zapyta o nie (UAC)
Filename: "{app}\SerwisDiag.exe"; Description: "{cm:LaunchProgram,SerwisDiag}"; Flags: nowait postinstall skipifsilent shellexec

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\SerwisDiag.ps1"" -DisableMonitor -SkipIntegrity"; Flags: runhidden waituntilterminated; RunOnceId: "DisableMonitor"

[UninstallDelete]
; ustawienia serwisu i dzienniki błędów programu; raporty klientów w Dokumentach zostają
Type: files; Name: "{app}\instalacja.ini"
Type: filesandordirs; Name: "{app}\config"
Type: filesandordirs; Name: "{app}\logs"
Type: dirifempty; Name: "{app}\raporty"
Type: dirifempty; Name: "{app}"

[Code]
function ShouldRelaunch: Boolean;
begin
  Result := ExpandConstant('{param:RELAUNCH|0}') = '1';
end;
