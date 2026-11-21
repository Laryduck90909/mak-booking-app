; Inno Setup — مثبّت ويندوز (EXE). يُبنى تلقائياً من GitHub Actions.
#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif

[Setup]
AppId={{5A3037F3-D001-40A3-A1A6-EB079D681C63}
AppName=M.A.K Booking
AppVersion={#AppVersion}
AppPublisher=M.A.K
DefaultDirName={autopf}\M.A.K Booking
DefaultGroupName=M.A.K Booking
OutputDir=..\dist
OutputBaseFilename=MAK-Booking-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
DisableProgramGroupPage=yes
; ضع ملف أيقونة .ico هنا إن أردت أيقونة مخصصة للمثبّت:
; SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mak_booking.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\M.A.K Booking"; Filename: "{app}\mak_booking.exe"
Name: "{autodesktop}\M.A.K Booking"; Filename: "{app}\mak_booking.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\mak_booking.exe"; Description: "Launch M.A.K Booking"; Flags: nowait postinstall skipifsilent
