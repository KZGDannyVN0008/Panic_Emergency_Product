#define AppName "SoundFlow Desktop"
#define AppVersion "1.0.0"
#define AppPublisher "KZG"
#define AppExeName "SoundFlowDesktop.ps1"

[Setup]
AppId={{0B53DDDF-298D-4B2E-B87C-921A83E1654B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\SoundFlowDesktop
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=yes
DisableFinishedPage=no
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=output
OutputBaseFilename=SoundFlowDesktop-Setup
SetupIconFile=..\assets\SoundFlowDesktop.ico
UninstallDisplayIcon={app}\assets\SoundFlowDesktop.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=no
UsePreviousGroup=no
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription=Company-authorized emergency scan and cleanup application
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}

[Files]
Source: "..\app\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\src\*"; DestDir: "{app}\src"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\config\targets.windows.v1.json"; DestDir: "{app}\config"; Flags: ignoreversion
Source: "..\config\protected-paths.json"; DestDir: "{app}\config"; Flags: ignoreversion
Source: "..\config\uninstall-allowlist.json"; DestDir: "{app}\config"; Flags: ignoreversion
Source: "..\assets\SoundFlowDesktop.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\assets\soundflow-icon.png"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "staging\google-oauth-client.json"; DestDir: "{commonappdata}\SoundFlowDesktop\config"; Flags: ignoreversion skipifsourcedoesntexist uninsneveruninstall

[Icons]
Name: "{commondesktop}\SoundFlow Desktop"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\app\SoundFlowDesktop.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\SoundFlowDesktop.ico"; Comment: "Company-authorized emergency scan and cleanup"

[InstallDelete]
Type: filesandordirs; Name: "{app}\app"; Check: IsUpdateMode
Type: filesandordirs; Name: "{app}\src"; Check: IsUpdateMode
Type: filesandordirs; Name: "{app}\config"; Check: IsUpdateMode
Type: filesandordirs; Name: "{app}\assets"; Check: IsUpdateMode

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\app\SoundFlowDesktop.Configure.ps1"" -FullName ""{code:GetFullName}"" -WorkEmail ""{code:GetWorkEmail}"" -Department ""{code:GetDepartment}"" -FinalAction ""{code:GetFinalAction}"" {code:GetWebhookArgument} {code:GetGoogleArgument}"; StatusMsg: "Protecting configuration and connecting integrations..."; Flags: runhidden waituntilterminated; Check: not IsUpdateMode
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\app\SoundFlowDesktop.Worker.ps1"" -Mode DRY_RUN -ProgramDirectory ""{app}"" -DataDirectory ""{commonappdata}\SoundFlowDesktop"""; Description: "Run a non-destructive DRY RUN now"; Flags: postinstall nowait skipifsilent unchecked; Check: not IsUpdateMode

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\app\SoundFlowDesktop.Lifecycle.ps1"" -Action UNINSTALL -ProgramDirectory ""{app}"" -DataDirectory ""{commonappdata}\SoundFlowDesktop"""; Flags: runhidden waituntilterminated

[Code]
var
  OperationPage: TInputOptionWizardPage;
  IdentityPage: TInputQueryWizardPage;
  OptionsPage: TInputOptionWizardPage;
  WebhookPage: TInputQueryWizardPage;
  UpdateMode: Boolean;
  RemoveLocalData: Boolean;

procedure InitializeWizard;
begin
  UpdateMode := ExpandConstant('{param:UPDATE|0}') = '1';
  if UpdateMode then
    exit;

  OperationPage := CreateInputOptionPage(
    wpWelcome,
    'SoundFlow Desktop Setup',
    'Choose an operation',
    'Setup provides only the two supported operations.',
    True,
    False);
  OperationPage.Add('Install');
  OperationPage.Add('Uninstall');
  OperationPage.SelectedValueIndex := 0;

  IdentityPage := CreateInputQueryPage(
    OperationPage.ID,
    'Employee information',
    'Identify this authorized installation',
    'Enter the employee fields used on every operational event.');
  IdentityPage.Add('Full name:', False);
  IdentityPage.Add('Work email:', False);
  IdentityPage.Add('Department:', False);

  OptionsPage := CreateInputOptionPage(
    IdentityPage.ID,
    'Installation options',
    'Select the final Production action',
    'DRY RUN never performs this action. Production performs it only after reports and queues are persisted.',
    True,
    False);
  OptionsPage.Add('Log out');
  OptionsPage.Add('Shut down');
  OptionsPage.Add('No system action');
  OptionsPage.SelectedValueIndex := 0;

  WebhookPage := CreateInputQueryPage(
    OptionsPage.ID,
    'Protected integrations',
    'Configure optional operational delivery',
    'The Lark webhook is encrypted for this Windows user and is never written to reports or logs. Leave it blank to install disconnected.');
  WebhookPage.Add('Lark webhook:', True);
  WebhookPage.Add('Connect Google Sheets after files are installed (YES/NO):', False);
  WebhookPage.Values[1] := 'YES';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  UninstallCommand: String;
  ResultCode: Integer;
begin
  Result := True;
  if UpdateMode then
    exit;
  if (CurPageID = OperationPage.ID) and (OperationPage.SelectedValueIndex = 1) then
  begin
    if not RegQueryStringValue(
      HKLM64,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall\{0B53DDDF-298D-4B2E-B87C-921A83E1654B}_is1',
      'UninstallString',
      UninstallCommand) then
    begin
      MsgBox('SoundFlow Desktop is not installed.', mbInformation, MB_OK);
      Result := False;
      exit;
    end;
    if not Exec(RemoveQuotes(UninstallCommand), '', '', SW_SHOW, ewNoWait, ResultCode) then
      MsgBox('The installed uninstaller could not be started.', mbError, MB_OK);
    WizardForm.Close;
    Result := False;
    exit;
  end;
  if CurPageID = IdentityPage.ID then
  begin
    if (Trim(IdentityPage.Values[0]) = '') or
       (Trim(IdentityPage.Values[1]) = '') or
       (Trim(IdentityPage.Values[2]) = '') then
    begin
      MsgBox('Full name, work email, and department are required.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function IsUpdateMode: Boolean;
begin
  Result := UpdateMode;
end;

function GetFullName(Param: String): String;
begin
  Result := IdentityPage.Values[0];
end;

function GetWorkEmail(Param: String): String;
begin
  Result := IdentityPage.Values[1];
end;

function GetDepartment(Param: String): String;
begin
  Result := IdentityPage.Values[2];
end;

function GetFinalAction(Param: String): String;
begin
  case OptionsPage.SelectedValueIndex of
    1: Result := 'SHUTDOWN';
    2: Result := 'NONE';
  else
    Result := 'LOGOUT';
  end;
end;

function GetWebhookArgument(Param: String): String;
begin
  if Trim(WebhookPage.Values[0]) = '' then
    Result := ''
  else
    Result := '-LarkWebhook "' + WebhookPage.Values[0] + '"';
end;

function GetGoogleArgument(Param: String): String;
begin
  if CompareText(Trim(WebhookPage.Values[1]), 'YES') = 0 then
    Result := '-ConnectGoogleSheets'
  else
    Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveLocalData := MsgBox(
      'Remove protected local reports, logs, configuration, credentials, and queued records?'#13#10#13#10 +
      'Choose No to retain them under C:\ProgramData\SoundFlowDesktop.',
      mbConfirmation,
      MB_YESNO) = IDYES;
  if (CurUninstallStep = usPostUninstall) and RemoveLocalData then
    DelTree(ExpandConstant('{commonappdata}\SoundFlowDesktop'), True, True, True);
end;
