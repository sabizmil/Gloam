; Inno Setup script for Gloam Windows installer
; Used by CI to create a self-installing .exe that WinSparkle can run

#ifndef AppVersion
#define AppVersion "0.0.0"
#endif

[Setup]
AppName=Gloam
AppVersion={#AppVersion}
AppPublisher=Liminal Studio
AppPublisherURL=https://liminalstudio.io/gloam
DefaultDirName={autopf}\Gloam
DefaultGroupName=Gloam
OutputBaseFilename=Gloam-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\gloam.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
WizardStyle=modern

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Gloam"; Filename: "{app}\gloam.exe"
Name: "{autodesktop}\Gloam"; Filename: "{app}\gloam.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional options:"; Flags: unchecked

[Run]
Filename: "{app}\gloam.exe"; Description: "Launch Gloam"; Flags: nowait postinstall skipifsilent
