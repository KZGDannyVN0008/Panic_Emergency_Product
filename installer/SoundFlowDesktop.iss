#define AppName "SoundFlow Desktop"
#define AppVersion "1.0.1"
#define AppPublisher "KZG"

[Setup]
AppId={{0B53DDDF-298D-4B2E-B87C-921A83E1654B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\SoundFlowDesktop
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=yes
DisableFinishedPage=no
PrivilegesRequired=lowest
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
VersionInfoDescription=Independent emergency scan and authorized cleanup application
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
Source: "staging\google-webapp-url.txt"; DestDir: "{tmp}"; DestName: "soundflow-google-webapp-url.txt"; Flags: ignoreversion skipifsourcedoesntexist deleteafterinstall
Source: "staging\lark-webhook.txt"; DestDir: "{tmp}"; DestName: "soundflow-lark-webhook.txt"; Flags: ignoreversion skipifsourcedoesntexist deleteafterinstall

[Icons]
Name: "{userdesktop}\SoundFlow Desktop"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\app\SoundFlowDesktop.ps1"" -ProgramDirectory ""{app}"" -DataDirectory ""{localappdata}\SoundFlowDesktop"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\SoundFlowDesktop.ico"; Comment: "SoundFlow Desktop emergency scan and authorized cleanup"

[InstallDelete]
Type: filesandordirs; Name: "{app}\app"; Check: IsUpdateMode
Type: filesandordirs; Name: "{app}\src"; Check: IsUpdateMode
Type: filesandordirs; Name: "{app}\config"; Check: IsUpdateMode
Type: filesandordirs; Name: "{app}\assets"; Check: IsUpdateMode

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\app\SoundFlowDesktop.Configure.ps1"" -FullName ""{code:GetFullName}"" -WorkEmail ""{code:GetWorkEmail}"" -Department ""{code:GetDepartment}"" -FinalAction ""{code:GetFinalAction}"" -GoogleWebAppUrlFile ""{tmp}\soundflow-google-webapp-url.txt"" -LarkWebhookFile ""{tmp}\soundflow-lark-webhook.txt"" -ProgramDirectory ""{app}"" -DataDirectory ""{localappdata}\SoundFlowDesktop"""; StatusMsg: "Configuring SoundFlow Desktop..."; Flags: runhidden waituntilterminated; Check: not IsUpdateMode
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\app\SoundFlowDesktop.ps1"" -ProgramDirectory ""{app}"" -DataDirectory ""{localappdata}\SoundFlowDesktop"""; Description: "Open SoundFlow Desktop"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\app\SoundFlowDesktop.Lifecycle.ps1"" -Action UNINSTALL -ProgramDirectory ""{app}"" -DataDirectory ""{localappdata}\SoundFlowDesktop"""; Flags: runhidden waituntilterminated

[Code]
var
  UpdateMode: Boolean;
  RemoveLocalData: Boolean;
  UserInfoPage: TInputQueryWizardPage;
  FinalActionPage: TInputOptionWizardPage;

procedure InitializeWizard;
begin
  UpdateMode := ExpandConstant('{param:UPDATE|0}') = '1';

  if not UpdateMode then
  begin
    UserInfoPage := CreateInputQueryPage(
      wpWelcome,
      'User Information',
      'Enter your information to configure SoundFlow Desktop.',
      'This information identifies your device in operational reports. The Lark webhook is pre-configured.');
    UserInfoPage.Add('Full Name:', False);
    UserInfoPage.Add('Work Email:', False);
    UserInfoPage.Add('Department:', False);

    FinalActionPage := CreateInputOptionPage(
      UserInfoPage.ID,
      'Post-Operation Action',
      'Select what should happen after a Production run completes.',
      'Post-operation action:',
      True, False);
    FinalActionPage.Add('No action — keep the session active (NONE)');
    FinalActionPage.Add('Log out the current user (LOGOUT)');
    FinalActionPage.Add('Shut down the computer (SHUTDOWN)');
    FinalActionPage.SelectedValueIndex := 0;
  end;
end;

function IsUpdateMode: Boolean;
begin
  Result := UpdateMode;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if UpdateMode then
  begin
    if Assigned(UserInfoPage) and (PageID = UserInfoPage.ID) then
      Result := True;
    if Assigned(FinalActionPage) and (PageID = FinalActionPage.ID) then
      Result := True;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Name, Email, Dept: String;
  AtPos: Integer;
begin
  Result := True;
  if Assigned(UserInfoPage) and (CurPageID = UserInfoPage.ID) then
  begin
    Name := Trim(UserInfoPage.Values[0]);
    Email := Trim(UserInfoPage.Values[1]);
    Dept := Trim(UserInfoPage.Values[2]);
    if Name = '' then
    begin
      MsgBox('Please enter your full name.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    if Email = '' then
    begin
      MsgBox('Please enter your work email address.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    AtPos := Pos('@', Email);
    if (AtPos = 0) or (Pos('.', Copy(Email, AtPos + 1, Length(Email))) = 0) then
    begin
      MsgBox('Please enter a valid work email address (e.g. name@company.com).', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    if Dept = '' then
    begin
      MsgBox('Please enter your department.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;
end;

function GetFullName(Param: String): String;
begin
  if Assigned(UserInfoPage) then
    Result := UserInfoPage.Values[0]
  else
    Result := '';
end;

function GetWorkEmail(Param: String): String;
begin
  if Assigned(UserInfoPage) then
    Result := UserInfoPage.Values[1]
  else
    Result := '';
end;

function GetDepartment(Param: String): String;
begin
  if Assigned(UserInfoPage) then
    Result := UserInfoPage.Values[2]
  else
    Result := '';
end;

function GetFinalAction(Param: String): String;
begin
  if Assigned(FinalActionPage) then
    case FinalActionPage.SelectedValueIndex of
      1: Result := 'LOGOUT';
      2: Result := 'SHUTDOWN';
    else
      Result := 'NONE';
    end
  else
    Result := 'NONE';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveLocalData := MsgBox(
      'Remove local SoundFlow Desktop reports, logs, configuration, credentials, and queued records?'#13#10#13#10 +
      'Choose No to retain them under the current Windows user profile.',
      mbConfirmation,
      MB_YESNO) = IDYES;
  if (CurUninstallStep = usPostUninstall) and RemoveLocalData then
    DelTree(ExpandConstant('{localappdata}\SoundFlowDesktop'), True, True, True);
end;
