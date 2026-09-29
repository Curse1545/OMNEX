[Setup]
AppId={{E8D76145-8E2F-4BDE-9200-64E8A857934D}
AppName=OMNEX
AppVersion=0.5.0
AppPublisher=OMNEX
DefaultDirName={code:GetInstallDir}
DefaultGroupName=OMNEX
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=OMNEX-0.5-Windows-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
UninstallDisplayIcon={app}\omnex.exe
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{userprograms}\OMNEX"; Filename: "{app}\omnex.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\OMNEX"; Filename: "{app}\omnex.exe"; WorkingDir: "{app}"
[Run]
Filename: "{app}\omnex.exe"; Description: "OMNEX'i ac"; Flags: nowait postinstall skipifsilent
[Code]
function GetInstallDir(Param: String): String;
begin
  if DirExists('D:\') then Result := 'D:\OMNEX'
  else Result := ExpandConstant('{localappdata}\Programs\OMNEX');
end;
