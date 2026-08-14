; ============================================================
;  VPN MASTER — Inno Setup Script
;  Version : 69.0.0
;  Requires: Inno Setup 6.2+
; ============================================================

#define AppName        "VPN MASTER"
#define AppVersion     "69.0.0"
#define AppPublisher   "VPN MASTER"
#define AppURL         "https://vpn.linkze.me"
#define AppExeName     "axe_vpn.exe"
#define AppMutex       "VPNMASTER_RunningInstance"
#define RegKey         "Software\VPNMASTER\VPNMASTER"
#define MinWinVer      "6.2"

; Build output
#define SourceBase "..\build\windows\x64\runner\Release"


; ============================================================
[Setup]
; ── Identity ─────────────────────────────────────────────────
AppId={{B7E4A9D2-6C31-4F8A-9E52-3D1C8A6B0F77}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/support
AppUpdatesURL={#AppURL}
AppCopyright=Copyright © 2026 {#AppPublisher}

; ── Paths ────────────────────────────────────────────────────
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=installer_output
OutputBaseFilename=VPNMASTERSetup_v{#AppVersion}
SetupIconFile=runner\resources\app_icon.ico

; ── Architecture ─────────────────────────────────────────────
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; ── Appearance ───────────────────────────────────────────────
WizardStyle=modern
WizardSizePercent=125
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=yes
DisableReadyMemo=no
DisableReadyPage=no

; ── Compression ──────────────────────────────────────────────
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4

; ── Behaviour ────────────────────────────────────────────────
; Elevation is required by default: OpenVPN/WireGuard need admin rights to
; create TUN adapters at *runtime* (handled per-connect by the app itself
; via UAC), but the installer also needs admin rights up front to register
; in HKLM-equivalent scope and to reliably taskkill any elevated, orphaned
; openvpn.exe/wireguard.exe left running from a previous session.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
UsePreviousAppDir=yes
UsePreviousGroup=yes
ShowLanguageDialog=auto
CloseApplications=yes
RestartApplications=yes
AppMutex={#AppMutex}

; ── Upgrade / uninstall ──────────────────────────────────────
CreateUninstallRegKey=yes
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName} {#AppVersion}

; ── Version info embedded in Setup.exe ───────────────────────
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Installer
VersionInfoCopyright=Copyright © 2026 {#AppPublisher}
VersionInfoProductName={#AppName}

; ── Minimum OS ───────────────────────────────────────────────
MinVersion={#MinWinVer}

; ── Signing (enable when certificate is available) ───────────
; SignTool=signtool sign /tr http://timestamp.digicert.com /td sha256 /fd sha256 /a $f
; SignedUninstaller=yes


; ============================================================
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"


; ============================================================
[Messages]
SetupAppTitle={#AppName} Setup
SetupWindowTitle={#AppName} Installer
WelcomeLabel1=Welcome to {#AppName}
WelcomeLabel2=This installer will install or upgrade {#AppName} on your computer.%n%nIncludes OpenVPN, WireGuard and V2Ray/Xray protocol support for Windows.
SelectDirLabel3=Choose where {#AppName} should be installed.
ReadyLabel1=Setup is now ready to install {#AppName} on your computer.
FinishedHeadingLabel=Installation complete
FinishedLabel={#AppName} was installed successfully.%n%nWhen you connect for the first time, Windows will show a UAC prompt — this is required to create the VPN network adapter (OpenVPN/WireGuard).
ConfirmUninstall=This will remove {#AppName} from your computer.


; ============================================================
[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "startupicon"; Description: "Launch {#AppName} on &Windows startup"; GroupDescription: "Startup:"; Flags: unchecked


; ============================================================
[Files]
; ── Main application (Flutter build output + bundled vpn_bin/) ───
Source: "{#SourceBase}\*"; \
  DestDir: "{app}"; \
  Excludes: "*.exp,*.lib,*.pdb"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

; ── Optional VC++ Redist (bundle if needed) ──────────────────
; Source: "redist\vc_redist.x64.exe"; \
;   DestDir: "{tmp}"; \
;   Flags: deleteafterinstall


; ============================================================
[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; \
  IconFilename: "{app}\{#AppExeName}"; Tasks: desktopicon

Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExeName}"; \
  Tasks: startupicon


; ============================================================
[Registry]
Root: HKA; Subkey: "{#RegKey}"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKA; Subkey: "{#RegKey}"; ValueType: string; ValueName: "Version";     ValueData: "{#AppVersion}"
Root: HKA; Subkey: "{#RegKey}"; ValueType: string; ValueName: "Publisher";   ValueData: "{#AppPublisher}"


; ============================================================
[Run]
; Optional bundled VC++ runtime
; Filename: "{tmp}\vc_redist.x64.exe"; \
;   Parameters: "/install /quiet /norestart"; \
;   StatusMsg: "Installing Visual C++ Runtime..."; \
;   Check: NeedsVCRedist; \
;   Flags: waituntilterminated runhidden

Filename: "{app}\{#AppExeName}"; \
  Description: "Launch {#AppName} now"; \
  Flags: nowait postinstall skipifsilent runasoriginaluser


; ============================================================
[UninstallRun]
; Clean up any elevated openvpn.exe / wireguard.exe left running from an
; active VPN session before removing files — an active tunnel would
; otherwise keep the Wintun adapter attached to a binary that's about to
; be deleted.
Filename: "{cmd}"; Parameters: "/C taskkill /IM openvpn.exe /F & taskkill /IM wireguard.exe /F & taskkill /IM wg.exe /F & taskkill /IM xray.exe /F"; \
  Flags: runhidden; RunOnceId: "KillVpnProcesses"


; ============================================================
[UninstallDelete]
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\cache"


; ============================================================
[Code]

const
  VC_REDIST_URL = 'https://aka.ms/vs/17/release/vc_redist.x64.exe';
  MIN_DISK_MB   = 400;

  clBrandBlue     = $00E5A03A;  // accent used by the app (BGR order)
  clBrandBlueDark = $00C67D18;
  clBrandGrayText = $00444444;

var
  PreviousInstallPath: String;
  InstalledVersion: String;
  IsUpgradeInstall: Boolean;
  IsSameVersionReinstall: Boolean;


function NeedsVCRedist: Boolean;
var
  Installed: Cardinal;
begin
  if RegQueryDWordValue(
       HKLM,
       'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64',
       'Installed',
       Installed) then
    Result := (Installed <> 1)
  else
    Result := True;
end;

function FormatMB(MB: Int64): String;
begin
  if MB >= 1024 then
    Result := IntToStr(MB div 1024) + '.' + IntToStr((MB mod 1024) * 10 div 1024) + ' GB'
  else
    Result := IntToStr(MB) + ' MB';
end;

function GetInstalledVersion(): String;
begin
  Result := '';
  RegQueryStringValue(HKA, ExpandConstant('{#RegKey}'), 'Version', Result);
end;

function GetPreviousInstallDir(): String;
begin
  Result := '';
  RegQueryStringValue(HKA, ExpandConstant('{#RegKey}'), 'InstallPath', Result);
end;

function CompareVersionPart(A, B: Integer): Integer;
begin
  if A < B then
    Result := -1
  else if A > B then
    Result := 1
  else
    Result := 0;
end;

function CompareVersionStrings(Version1, Version2: String): Integer;
var
  P1, P2: Integer;
  S1, S2: String;
  N1, N2: Integer;
begin
  Result := 0;

  while (Version1 <> '') or (Version2 <> '') do
  begin
    P1 := Pos('.', Version1);
    P2 := Pos('.', Version2);

    if P1 > 0 then
    begin
      S1 := Copy(Version1, 1, P1 - 1);
      Delete(Version1, 1, P1);
    end
    else
    begin
      S1 := Version1;
      Version1 := '';
    end;

    if P2 > 0 then
    begin
      S2 := Copy(Version2, 1, P2 - 1);
      Delete(Version2, 1, P2);
    end
    else
    begin
      S2 := Version2;
      Version2 := '';
    end;

    if S1 = '' then N1 := 0 else N1 := StrToIntDef(S1, 0);
    if S2 = '' then N2 := 0 else N2 := StrToIntDef(S2, 0);

    Result := CompareVersionPart(N1, N2);
    if Result <> 0 then
      Exit;
  end;
end;

function KillRunningApp(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;

  if CheckForMutexes('{#AppMutex}') then
    Log('{#AppName} is running. Attempting to close it.');

  { Also kill the elevated VPN backend processes the app spawns as
    detached subprocesses (they outlive the main exe's mutex). }
  Exec(ExpandConstant('{cmd}'), '/C taskkill /IM openvpn.exe /F & taskkill /IM wireguard.exe /F & taskkill /IM wg.exe /F & taskkill /IM xray.exe /F',
       '', SW_HIDE, ewNoWait, ResultCode);

  if Exec(
       ExpandConstant('{cmd}'),
       '/C taskkill /IM "{#AppExeName}" /T /F',
       '',
       SW_HIDE,
       ewWaitUntilTerminated,
       ResultCode) then
  begin
    Log('taskkill exit code: ' + IntToStr(ResultCode));
    Result := (ResultCode = 0) or (ResultCode = 128) or (ResultCode = 255);
  end
  else
  begin
    Log('Failed to execute taskkill.');
    Result := False;
  end;

  Sleep(1000);
end;

procedure ApplyPreviousInstallPath;
begin
  PreviousInstallPath := GetPreviousInstallDir();
  if (PreviousInstallPath <> '') and DirExists(PreviousInstallPath) then
    WizardForm.DirEdit.Text := PreviousInstallPath;
end;

function InitializeSetup(): Boolean;
var
  FreeBytes: Int64;
  TotalBytes: Int64;
  FreeMB: Int64;
  ErrorCode: Integer;
  CompareResult: Integer;
begin
  Result := True;
  IsUpgradeInstall := False;
  IsSameVersionReinstall := False;
  PreviousInstallPath := '';
  InstalledVersion := '';

  { 1) Require 64-bit Windows }
  if not IsWin64 then
  begin
    MsgBox(
      '{#AppName} requires a 64-bit version of Windows.' + #13#10#13#10 +
      'Please run this installer on a 64-bit Windows PC.',
      mbCriticalError, MB_OK);
    Result := False;
    Exit;
  end;

  { 2) Disk space check }
  GetSpaceOnDisk64(ExpandConstant('{autopf}'), FreeBytes, TotalBytes);
  FreeMB := FreeBytes div (1024 * 1024);
  if FreeMB < MIN_DISK_MB then
  begin
    MsgBox(
      'Not enough free disk space.' + #13#10#13#10 +
      'Required: ' + FormatMB(MIN_DISK_MB) + #13#10 +
      'Available: ' + FormatMB(FreeMB),
      mbCriticalError, MB_OK);
    Result := False;
    Exit;
  end;

  { 3) Existing install detection }
  InstalledVersion := GetInstalledVersion();
  PreviousInstallPath := GetPreviousInstallDir();

  if InstalledVersion <> '' then
  begin
    CompareResult := CompareVersionStrings(InstalledVersion, '{#AppVersion}');

    if CompareResult > 0 then
    begin
      if not WizardSilent then
      begin
        MsgBox(
          'A newer version of {#AppName} is already installed.' + #13#10#13#10 +
          'Installed version: ' + InstalledVersion + #13#10 +
          'This installer version: {#AppVersion}' + #13#10#13#10 +
          'Setup will now exit to prevent downgrading.',
          mbInformation, MB_OK);
      end;
      Log('Downgrade blocked. Installed=' + InstalledVersion + ', Setup={#AppVersion}');
      Result := False;
      Exit;
    end
    else if CompareResult = 0 then
    begin
      IsSameVersionReinstall := True;

      if not WizardSilent then
      begin
        if MsgBox(
             '{#AppName} version {#AppVersion} is already installed.' + #13#10#13#10 +
             'Do you want to reinstall or repair it?',
             mbConfirmation, MB_YESNO) = IDNO then
        begin
          Result := False;
          Exit;
        end;
      end;
    end
    else
    begin
      IsUpgradeInstall := True;

      if not WizardSilent then
      begin
        MsgBox(
          'Existing version detected: ' + InstalledVersion + #13#10 +
          'New version: {#AppVersion}' + #13#10#13#10 +
          '{#AppName} will now be upgraded.',
          mbInformation, MB_OK);
      end;
    end;
  end;

  { 4) Close running app (and any elevated VPN backend) before reinstall / upgrade }
  if IsUpgradeInstall or IsSameVersionReinstall then
  begin
    if not KillRunningApp() then
    begin
      if not WizardSilent then
      begin
        MsgBox(
          'The running {#AppName} process could not be closed automatically.' + #13#10#13#10 +
          'Please close the app manually and run setup again.',
          mbCriticalError, MB_OK);
      end;
      Result := False;
      Exit;
    end;
  end;

  { 5) VC++ runtime check }
  if NeedsVCRedist() and (not WizardSilent) then
  begin
    case MsgBox(
      'Visual C++ 2015–2022 Redistributable (x64) was not detected.' + #13#10#13#10 +
      '{#AppName} requires this runtime.' + #13#10#13#10 +
      'Yes    - Download it now and exit setup' + #13#10 +
      'No     - Continue anyway' + #13#10 +
      'Cancel - Abort setup',
      mbConfirmation, MB_YESNOCANCEL) of
      IDYES:
        begin
          ShellExec('open', VC_REDIST_URL, '', '', SW_SHOW, ewNoWait, ErrorCode);
          Result := False;
          Exit;
        end;
      IDCANCEL:
        begin
          Result := False;
          Exit;
        end;
    end;
  end;
end;

procedure InitializeWizard;
begin
  WizardForm.Color := clWhite;
  WizardForm.MainPanel.Color := clWhite;

  WizardForm.WelcomeLabel1.Font.Size := 18;
  WizardForm.WelcomeLabel1.Font.Style := [fsBold];
  WizardForm.WelcomeLabel1.Font.Color := clBrandBlue;

  WizardForm.WelcomeLabel2.Font.Color := clBrandGrayText;
  WizardForm.PageNameLabel.Font.Color := clBrandBlueDark;
  WizardForm.PageDescriptionLabel.Font.Color := clBrandGrayText;
  WizardForm.FinishedHeadingLabel.Font.Color := clBrandBlueDark;
  WizardForm.FinishedHeadingLabel.Font.Style := [fsBold];
  WizardForm.FinishedHeadingLabel.Font.Size := 14;

  WizardForm.NextButton.Caption := 'Next >';
  WizardForm.BackButton.Caption := '< Back';
  WizardForm.CancelButton.Caption := 'Cancel';

  ApplyPreviousInstallPath;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';

  if IsUpgradeInstall or IsSameVersionReinstall then
  begin
    if not KillRunningApp() then
    begin
      Result := 'Unable to stop the previous {#AppName} process.';
      Exit;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    Log('[VPNMASTERSetup] Post-install complete.');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RegDeleteKeyIncludingSubkeys(HKA, ExpandConstant('{#RegKey}'));
    Log('[VPNMASTERSetup] Registry cleaned.');
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = wpSelectProgramGroup);
end;
