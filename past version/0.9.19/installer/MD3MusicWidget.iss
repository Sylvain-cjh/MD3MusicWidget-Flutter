#define MyAppName "MD3 Music Widget"
#define MyAppVersion "0.9.19"
#define MyAppPublisher "syj"
#define MyAppExeName "music_widget_flutter.exe"

[Setup]
AppId={{9AE75D30-8D61-4D66-B474-70F6FCFC25C8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\MD3MusicWidget
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=output
OutputBaseFilename=MD3MusicWidget-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "english"

[Tasks]
Name: "desktopicon"

[Files]
Source: "..\build\windows\x64\runner\Release\*"

[Icons]
Name: "{autoprograms}\{#MyAppName}"
Name: "{autodesktop}\{#MyAppName}"

[Run]
Filename: "{app}\{#MyAppExeName}"
