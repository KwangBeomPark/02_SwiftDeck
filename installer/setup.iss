; Script for SwiftDeck (PL Suite App02)
; Standard Per-User installer for PL Suite applications (App01 ~ App10).

#ifndef MyAppVersion
#define MyAppVersion "1.4.2"
#endif

#ifndef MyAppExeSource
#define MyAppExeSource "..\release\SwiftDeck.v" + MyAppVersion + ".exe"
#endif

#define MyAppName "SwiftDeck"
#define MyAppPublisher "KwangBeomPark"
#define MyAppURL "https://github.com/KwangBeomPark/02_SwiftDeck"
#define MyAppExeName "SwiftDeck.exe"

[Setup]
AppId={{131A33AA-3326-4372-8B18-562CCC01BA5E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\SwiftDeck
DefaultGroupName=SwiftDeck
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=App02_SwiftDeck_Setup_v{#MyAppVersion}
SetupIconFile=..\assets\SwiftDeck.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=SwiftDeck.exe
RestartApplications=no
UsePreviousAppDir=yes
VersionInfoVersion={#MyAppVersion}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startupicon"; Description: "Windows 시작 시 자동 실행 (Run at Windows startup)"; GroupDescription: "시작 옵션 (Startup):"

[Files]
; Main application executable
Source: "{#MyAppExeSource}"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion; BeforeInstall: EnsureUpgradeReady

[Dirs]
; UserSetting directory preservation (never deleted on uninstall)
Name: "{app}\UserSetting"; Flags: uninsneveruninstall

[InstallDelete]
; Clean up legacy shortcuts from older portable runs before installing new shortcuts
Type: files; Name: "{userstartup}\SwiftDeck.lnk"
Type: files; Name: "{userstartup}\App02_SwiftDeck.lnk"
Type: files; Name: "{userstartup}\FolderHotKey.lnk"
Type: files; Name: "{userstartup}\AHK_FolderHotKey.lnk"
Type: files; Name: "{userdesktop}\FolderHotKey.lnk"
Type: files; Name: "{userdesktop}\AHK_FolderHotKey.lnk"
Type: files; Name: "{userdesktop}\App02_SwiftDeck.lnk"
Type: files; Name: "{userprograms}\FolderHotKey.lnk"
Type: files; Name: "{userprograms}\AHK_FolderHotKey.lnk"
Type: files; Name: "{userprograms}\App02_SwiftDeck.lnk"

[Registry]
; Clean up legacy Run registry keys
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "SwiftDeck"; Flags: deletevalue uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "App02_SwiftDeck"; Flags: deletevalue uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "FolderHotKey"; Flags: deletevalue uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "AHK_FolderHotKey"; Flags: deletevalue uninsdeletevalue

[Icons]
Name: "{userprograms}\SwiftDeck\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
procedure EnsureUpgradeReady;
var
  ExistingExe: String;
  Probe: TFileStream;
begin
  { Restart Manager gets its normal-close opportunity before this callback. }
  ExistingExe := ExpandConstant('{app}\{#MyAppExeName}');
  if FileExists(ExistingExe) then
  begin
    try
      Probe := TFileStream.Create(ExistingExe, fmOpenReadWrite or fmShareExclusive);
      Probe.Free;
    except
      RaiseException('SwiftDeck is still in use or the executable cannot be replaced. Close SwiftDeck and retry. The existing executable and user settings have been preserved.');
    end;
  end;
end;
