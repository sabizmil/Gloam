; Inno Setup script for Gloam Windows installer
; Used by CI to create a self-installing .exe that WinSparkle can run
;
; When run as an update (gloam.exe already exists), the installer
; auto-applies /VERYSILENT mode so the user sees no wizard — the app
; closes, updates, and relaunches seamlessly.

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
; Launch after install — runs for both fresh installs and silent updates
Filename: "{app}\gloam.exe"; Description: "Launch Gloam"; Flags: nowait postinstall skipifsilent

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

function InitializeSetup: Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  // If Gloam is already installed, this is an update — run silently.
  // WinSparkle downloads and launches the installer; the user shouldn't
  // see a wizard for updates, just a seamless restart.
  if FileExists(ExpandConstant('{autopf}\Gloam\gloam.exe')) then
  begin
    if not WizardSilent then
    begin
      // Re-launch ourselves with /VERYSILENT and auto-restart the app
      Exec(ExpandConstant('{srcexe}'), '/VERYSILENT /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS', '', SW_HIDE, ewNoWait, ResultCode);
      Result := False; // Abort this (non-silent) instance
    end;
  end;
end;
