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
UninstallDisplayIcon={app}\gloam.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
WizardStyle=modern
CloseApplications=force
CloseApplicationsFilter=gloam.exe
; Skip pages for updates — just show progress bar
DisableWelcomePage=yes
DisableDirPage=auto
DisableReadyPage=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
; VC++ Redistributable bundled for machines that don't have it
Source: "..\build\vcredist_x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: not VCRedistInstalled

[Icons]
Name: "{group}\Gloam"; Filename: "{app}\gloam.exe"
Name: "{autodesktop}\Gloam"; Filename: "{app}\gloam.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional options:"; Flags: unchecked

[Run]
; Install VC++ Redistributable silently if needed (before launching app)
Filename: "{tmp}\vcredist_x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Visual C++ Runtime..."; Flags: waituntilterminated; Check: not VCRedistInstalled
; Launch after install
Filename: "{app}\gloam.exe"; Description: "Launch Gloam"; Flags: nowait postinstall

[Code]
function VCRedistInstalled: Boolean;
var
  Version: String;
begin
  // Check for VC++ 2015-2022 Redistributable (14.x) in registry
  Result :=
    RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Version', Version) or
    RegQueryStringValue(HKLM, 'SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Version', Version);
end;
