unit mainform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Menus, Dialogs, Graphics, ImgList, Windows, LCLType, Clipbrd,
  fpjson, jsonparser, CheckLst,
  limiter_data, startup_entry, activity_export, parental_pin,
  instance_control;

type
  TMainRow = record
    Path, DisplayName, LimitLabel: string;
    DownBps, UpBps, DownTotal, UpTotal, QuotaUsed: Int64;
    IsActive: Boolean;
  end;

  TActivityRow = record
    Day, Name, Address, Source, Seen: string;
    DownloadBytes, UploadBytes, SeenMs: Int64;
  end;

  TDestinationsForm = class(TForm)
  private
    FAppPath: string;
    FPathLabel, FStatusLabel: TLabel;
    FList: TListView;
    FToolbar: TPanel;
    FSearch: TEdit;
    FView: TComboBox;
    FCopy, FExport: TButton;
    FSaveDialog: TSaveDialog;
    FRows: array of TActivityRow;
    FSortColumn: Integer;
    FSortDescending: Boolean;
    FLayoutBusy: Boolean;
    FTimer: TTimer;
    procedure RefreshDestinations(Sender: TObject);
    procedure ViewChanged(Sender: TObject);
    procedure ColumnClick(Sender: TObject; Column: TListColumn);
    procedure CopyClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ActivityShown(Sender: TObject);
    procedure ActivityHidden(Sender: TObject);
    procedure ActivityResized(Sender: TObject);
    procedure FitToMonitor;
    function CompareRows(const A, B: TActivityRow): Integer;
    procedure SortRows(L, R: Integer);
    procedure AddActivityRow(const Row: TActivityRow);
  public
    constructor CreateForApp(TheOwner: TComponent; const AppPath: string);
    procedure SetAppPath(const AppPath: string);
    procedure ApplyTheme(DarkTheme: Boolean);
  end;

  TLimitDialog = class(TForm)
  private
    FContent: TScrollBox;
    FFooter: TPanel;
    FIntro, FUploadLabel, FDownloadLabel, FHint,
      FUploadEstimate, FDownloadEstimate: TLabel;
    FUploadSlider, FDownloadSlider: TTrackBar;
    FUploadValue, FDownloadValue: TEdit;
    FSaveButton, FCancelButton: TButton;
    FInitialDownBps, FInitialUpBps: Int64;
    FResultDownBps, FResultUpBps: Int64;
    FDownDirty, FUpDirty, FUpdating, FLayoutBusy: Boolean;
    procedure SliderChanged(Sender: TObject);
    procedure ValueEdited(Sender: TObject);
    procedure SaveClicked(Sender: TObject);
    procedure DialogShown(Sender: TObject);
    procedure DialogResized(Sender: TObject);
    procedure LayoutControls;
    procedure UpdateEstimates;
    procedure SetInitialRate(Slider: TTrackBar; ValueBox: TEdit;
      Bps: Int64);
  public
    constructor CreateForRates(TheOwner: TComponent; const AppName: string;
      DownBps, UpBps: Int64; DarkTheme: Boolean);
    procedure GetRates(out DownBps, UpBps: Int64);
  end;

  TMainForm = class(TForm)
  private
    FSettings: TSettings;
    FRules: TRules;
    FGlobalQuotaUsed: Int64;
    FRows: array of TMainRow;
    FSortColumn: Integer;
    FSortDescending: Boolean;
    FIconPaths: TStringList;
    FImages: TImageList;
    FDestinationsWindow: TDestinationsForm;
    FExiting, FCollapsed, FLayoutBusy, FOpenAfterStart,
      FPinPromptActive: Boolean;
    FHeader: TPanel;
    FBody: TScrollBox;
    FStatusContainer, FDetailsContainer: TPanel;
    FTitle, FStatus, FDetails: TLabel;
    FList: TListView;
    FPause, FPin, FEdit, FToggle, FRemove, FBlock, FSettingsButton,
      FDestinationsButton, FAdvancedButton,
      FCollapse, FClose, FTab: TButton;
    FTimer: TTimer;
    FTray: TTrayIcon;
    FTrayMenu: TPopupMenu;
    FAppMenu: TPopupMenu;
    FMenuPin, FMenuEdit, FMenuToggle, FMenuRemove, FMenuBlock,
      FMenuDestinations, FMenuAdvanced, FMenuSettings: TMenuItem;
    FTrayOpen, FTrayPause, FTrayExit: TMenuItem;
    FDialog: TOpenDialog;
    function MakeButton(ParentControl: TWinControl; const CaptionText: string;
      X, Y, W, H: Integer; Handler: TNotifyEvent): TButton;
    procedure DockRight;
    procedure LayoutMain;
    procedure MainResized(Sender: TObject);
    procedure FitModalDialog(Sender: TObject);
    procedure QuotaDialogShown(Sender: TObject);
    procedure FormShown(Sender: TObject);
    procedure SetCollapsed(Value: Boolean);
    function Save: Boolean;
    procedure RefreshState(Sender: TObject);
    procedure InstanceTick(Sender: TObject);
    function UnlockPanel: Boolean;
    procedure RefreshCaption;
    procedure AddRow(const Path, DisplayName: string; DownBps, UpBps,
      DownTotal, UpTotal, QuotaUsed: Int64; IsActive: Boolean);
    function CompareMainRows(const A, B: TMainRow): Integer;
    procedure SortMainRows(L, R: Integer);
    procedure MainColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure AppMenuPopup(Sender: TObject);
    function SelectedPath: string;
    function RuleIndex(const Path: string): Integer;
    function IconIndex(const Path: string): Integer;
    procedure PauseClick(Sender: TObject);
    procedure PinClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure ToggleClick(Sender: TObject);
    procedure BlockClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
    procedure DestinationsClick(Sender: TObject);
    procedure AdvancedClick(Sender: TObject);
    procedure CollapseClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure TrayOpenClick(Sender: TObject);
    procedure TrayExitClick(Sender: TObject);
    procedure ListSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
    procedure ListDoubleClick(Sender: TObject);
    procedure Closing(Sender: TObject; var CanClose: Boolean);
    procedure TrayDblClick(Sender: TObject);
    procedure RegisterShortcut;
    procedure EnsureServiceStarted;
    function StopAppService: Boolean;
    procedure ApplyTheme;
    procedure ShowPanel;
    procedure WMHotKey(var Message: TMessage); message WM_HOTKEY;
    procedure WMDisplayChange(var Message: TMessage); message WM_DISPLAYCHANGE;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainWindow: TMainForm;

implementation

const
  HotkeyId = 12031;
  ExpandedWidth = 460;
  CollapsedWidth = 30;
  SC_MANAGER_CONNECT = $0001;
  SERVICE_QUERY_STATUS = $0004;
  SERVICE_START = $0010;
  SERVICE_STOP = $0020;
  SERVICE_CONTROL_STOP = 1;
  SERVICE_STOPPED = 1;

type
  TPinDialogLayout = class
    Instruction, ConfirmLabel: TLabel;
    PinEdit, ConfirmEdit: TEdit;
    OkButton, CancelButton: TButton;
    procedure Shown(Sender: TObject);
  end;

  TQuotaSliders = class
    AmountSlider, SpeedSlider: TTrackBar;
    AmountEdit, SpeedEdit: TEdit;
    BlockBox: TCheckBox;
    Updating, AmountDirty, SpeedDirty: Boolean;
    procedure SliderChanged(Sender: TObject);
    procedure EditChanged(Sender: TObject);
    procedure BlockChanged(Sender: TObject);
  end;

procedure TPinDialogLayout.Shown(Sender: TObject);
var
  Dialog: TForm;
  Margin, Gap, FieldWidth, ButtonTop, LabelHeight: Integer;
begin
  Dialog := TForm(Sender);
  Margin := MulDiv(18, Dialog.PixelsPerInch, 96);
  Gap := MulDiv(10, Dialog.PixelsPerInch, 96);
  FieldWidth := Dialog.ClientWidth - 2 * Margin;
  Dialog.Canvas.Font.Assign(Instruction.Font);
  Instruction.SetBounds(Margin, Margin, FieldWidth,
    Max(MulDiv(32, Dialog.PixelsPerInch, 96),
      2 * Dialog.Canvas.TextHeight('Ag') + 4));
  PinEdit.SetBounds(Margin, Instruction.Top + Instruction.Height + Gap,
    FieldWidth, PinEdit.Height);
  ButtonTop := PinEdit.Top + PinEdit.Height + MulDiv(16,
    Dialog.PixelsPerInch, 96);
  if ConfirmEdit <> nil then
  begin
    LabelHeight := Dialog.Canvas.TextHeight('Ag') + 4;
    ConfirmLabel.SetBounds(Margin, PinEdit.Top + PinEdit.Height + Gap,
      FieldWidth, LabelHeight);
    ConfirmEdit.SetBounds(Margin, ConfirmLabel.Top + ConfirmLabel.Height + Gap,
      FieldWidth, ConfirmEdit.Height);
    ButtonTop := ConfirmEdit.Top + ConfirmEdit.Height + MulDiv(16,
      Dialog.PixelsPerInch, 96);
  end;
  Dialog.ClientHeight := ButtonTop + OkButton.Height + Gap;
  OkButton.Top := ButtonTop;
  CancelButton.Top := ButtonTop;
  CancelButton.Left := Dialog.ClientWidth - Margin - CancelButton.Width;
  OkButton.Left := CancelButton.Left - Gap - OkButton.Width;
end;

function AskPin(Creating: Boolean; out Pin: string): Boolean;
var
  Dialog: TForm;
  Layout: TPinDialogLayout;
  Instruction, ConfirmLabel: TLabel;
  PinEdit, ConfirmEdit: TEdit;
  OkButton, CancelButton: TButton;
  Area: TRect;
  DialogWidth: Integer;
begin
  Result := False;
  Pin := '';
  Dialog := TForm.CreateNew(nil, 1);
  Layout := TPinDialogLayout.Create;
  try
    Dialog.Caption := 'App Limiter parental PIN';
    Dialog.Position := poScreenCenter;
    Dialog.BorderStyle := bsDialog;
    Dialog.FormStyle := fsStayOnTop;
    Dialog.ShowInTaskBar := stAlways;
    Dialog.Font.Name := 'Segoe UI';
    Dialog.Font.Size := 9;
    Dialog.Color := clBtnFace;
    Area := Screen.PrimaryMonitor.WorkareaRect;
    DialogWidth := Min(370, Area.Right - Area.Left - 24);
    Dialog.ClientWidth := Max(250, DialogWidth);
    if Creating then Dialog.ClientHeight := 216
    else Dialog.ClientHeight := 136;
    Instruction := TLabel.Create(Dialog);
    Instruction.Parent := Dialog;
    Instruction.SetBounds(18, 16, Dialog.ClientWidth - 36, 32);
    Instruction.AutoSize := False;
    Instruction.WordWrap := True;
    Instruction.Font.Color := clWindowText;
    if Creating then
      Instruction.Caption := 'Choose a 6 to 12 digit parental PIN.'
    else
      Instruction.Caption := 'Enter the parental PIN to open App Limiter.';
    PinEdit := TEdit.Create(Dialog);
    PinEdit.Parent := Dialog;
    PinEdit.SetBounds(18, 55, Dialog.ClientWidth - 36, 28);
    PinEdit.PasswordChar := '*';
    PinEdit.MaxLength := 12;
    ConfirmEdit := nil;
    ConfirmLabel := nil;
    if Creating then
    begin
      ConfirmLabel := TLabel.Create(Dialog);
      ConfirmLabel.Parent := Dialog;
      ConfirmLabel.SetBounds(18, PinEdit.Top + PinEdit.Height + 13,
        Dialog.ClientWidth - 36, 20);
      ConfirmLabel.AutoSize := False;
      ConfirmLabel.Caption := 'Confirm PIN';
      ConfirmLabel.Font.Color := clWindowText;
      ConfirmEdit := TEdit.Create(Dialog);
      ConfirmEdit.Parent := Dialog;
      ConfirmEdit.SetBounds(18, ConfirmLabel.Top + ConfirmLabel.Height + 10,
        Dialog.ClientWidth - 36, 28);
      ConfirmEdit.PasswordChar := '*';
      ConfirmEdit.MaxLength := 12;
    end;
    OkButton := TButton.Create(Dialog);
    OkButton.Parent := Dialog;
    OkButton.Caption := 'OK';
    OkButton.SetBounds(Dialog.ClientWidth - 193,
      Dialog.ClientHeight - 37, 82, 28);
    OkButton.Default := True;
    OkButton.ModalResult := mrOk;
    CancelButton := TButton.Create(Dialog);
    CancelButton.Parent := Dialog;
    CancelButton.Caption := 'Cancel';
    CancelButton.SetBounds(Dialog.ClientWidth - 100,
      Dialog.ClientHeight - 37, 82, 28);
    CancelButton.Cancel := True;
    CancelButton.ModalResult := mrCancel;
    Layout.Instruction := Instruction;
    Layout.ConfirmLabel := ConfirmLabel;
    Layout.PinEdit := PinEdit;
    Layout.ConfirmEdit := ConfirmEdit;
    Layout.OkButton := OkButton;
    Layout.CancelButton := CancelButton;
    Dialog.OnShow := @Layout.Shown;
    Dialog.ActiveControl := PinEdit;
    repeat
      if Dialog.ShowModal <> mrOk then Exit;
      if not ValidPin(PinEdit.Text) then
      begin
        MessageDlg('PIN must contain 6 to 12 digits.', mtError, [mbOK], 0);
        Continue;
      end;
      if Creating and (PinEdit.Text <> ConfirmEdit.Text) then
      begin
        MessageDlg('The two PIN entries do not match.', mtError, [mbOK], 0);
        Continue;
      end;
      Pin := PinEdit.Text;
      Result := True;
      Exit;
    until False;
  finally
    Dialog.Free;
    Layout.Free;
  end;
end;

function CreateParentalVerifier(out Verifier: string): Boolean;
var
  Pin: string;
begin
  Verifier := '';
  Result := AskPin(True, Pin);
  if Result then
    try
      Verifier := NewPinVerifier(Pin);
    finally
      Pin := '';
    end;
end;

type
  TWinServiceStatus = record
    ServiceType, CurrentState, ControlsAccepted, Win32ExitCode,
      ServiceSpecificExitCode, CheckPoint, WaitHint: DWORD;
  end;
  PWinServiceStatus = ^TWinServiceStatus;
  PWinIcon = ^HICON;

function OpenSCManagerW(MachineName, DatabaseName: PWideChar;
  DesiredAccess: DWORD): THandle; stdcall; external 'advapi32.dll';
function OpenServiceW(Manager: THandle; Name: PWideChar;
  DesiredAccess: DWORD): THandle; stdcall; external 'advapi32.dll';
function StartServiceW(Service: THandle; ArgCount: DWORD; Args: Pointer): BOOL;
  stdcall; external 'advapi32.dll';
function ControlService(Service: THandle; Control: DWORD;
  Status: PWinServiceStatus): BOOL; stdcall; external 'advapi32.dll';
function QueryServiceStatus(Service: THandle; Status: PWinServiceStatus): BOOL;
  stdcall; external 'advapi32.dll';
function CloseServiceHandle(Service: THandle): BOOL;
  stdcall; external 'advapi32.dll';
function ExtractIconExW(FileName: PWideChar; IconIndex: LongInt;
  LargeIcons, SmallIcons: PWinIcon; Count: LongWord): LongWord;
  stdcall; external 'shell32.dll';

function RateText(Bps: Int64): string;
begin
  if Bps < 1024 then Result := Format('%d B/s', [Bps])
  else if Bps < 1024 * 1024 then
    Result := FormatFloat('0.0', Bps / 1024) + ' KB/s'
  else
    Result := FormatFloat('0.0', Bps / (1024 * 1024)) + ' MB/s';
end;

function BytesText(Bytes: Int64): string;
begin
  if Bytes < 1024 then Result := Format('%d B', [Bytes])
  else if Bytes < 1024 * 1024 then
    Result := FormatFloat('0.0', Bytes / 1024) + ' KB'
  else if Bytes < Int64(1024) * 1024 * 1024 then
    Result := FormatFloat('0.0', Bytes / (1024 * 1024)) + ' MB'
  else
    Result := FormatFloat('0.0', Bytes / (Int64(1024) * 1024 * 1024)) +
      ' GB';
end;

function LimitText(Bps: Int64): string;
begin
  if Bps = 0 then Result := 'Unlimited' else Result := RateText(Bps);
end;

function ParseLimit(const Value: string; out Bps: Int64): Boolean;
var
  S: string;
  Number: Double;
  Multiplier: Int64;
begin
  S := Trim(LowerCase(Value));
  if (S = '') or (S = 'unlimited') or (S = '∞') then
  begin
    Bps := 0;
    Exit(True);
  end;
  Multiplier := 1024;
  if RightStr(S, 4) = 'mb/s' then
  begin
    Multiplier := 1024 * 1024;
    Delete(S, Length(S) - 3, 4);
  end
  else if RightStr(S, 4) = 'kb/s' then
    Delete(S, Length(S) - 3, 4)
  else if RightStr(S, 2) = 'mb' then
  begin
    Multiplier := 1024 * 1024;
    Delete(S, Length(S) - 1, 2);
  end
  else if RightStr(S, 2) = 'kb' then
    Delete(S, Length(S) - 1, 2);
  Result := TryStrToFloat(Trim(S), Number) and (Number >= 1) and
    (Number <= 10240);
  if Result then Bps := Round(Number * Multiplier);
end;

function ParseQuota(const Value: string; out Bytes: Int64): Boolean;
var
  S: string;
  Number: Double;
  Multiplier: Int64;
begin
  S := Trim(LowerCase(Value));
  if (S = '') or (S = 'none') or (S = 'unlimited') or (S = '∞') then
  begin
    Bytes := 0;
    Exit(True);
  end;
  Multiplier := Int64(1024) * 1024 * 1024;
  if RightStr(S, 2) = 'gb' then
    Delete(S, Length(S) - 1, 2)
  else if RightStr(S, 2) = 'mb' then
  begin
    Multiplier := Int64(1024) * 1024;
    Delete(S, Length(S) - 1, 2);
  end;
  Result := TryStrToFloat(Trim(S), Number) and
    (Number > 0) and (Number <= 1000);
  if Result then Bytes := Round(Number * Multiplier);
end;

function QuotaSliderBytes(Position: Integer): Int64;
var
  MiB: Int64;
begin
  if Position <= 0 then Exit(0);
  if Position <= 500 then
    MiB := 1 + (Int64(Position - 1) * 1023 + 249) div 499
  else if Position <= 750 then
    MiB := 1024 + (Int64(Position - 500) * 49 * 1024 + 125) div 250
  else
    MiB := 50 * 1024 +
      (Int64(Position - 750) * 950 * 1024 + 125) div 250;
  Result := MiB * 1024 * 1024;
end;

function QuotaSliderPosition(Bytes: Int64): Integer;
var
  MiB: Double;
begin
  if Bytes <= 0 then Exit(0);
  MiB := Bytes / (1024 * 1024);
  if MiB <= 1024 then
    Result := 1 + Round((MiB - 1) * 499 / 1023)
  else if MiB <= 50 * 1024 then
    Result := 500 + Round((MiB - 1024) * 250 / (49 * 1024))
  else
    Result := 750 + Round((MiB - 50 * 1024) * 250 / (950 * 1024));
  Result := Max(1, Min(1000, Result));
end;

procedure TQuotaSliders.SliderChanged(Sender: TObject);
begin
  if Updating then Exit;
  if Sender = AmountSlider then AmountDirty := True
  else SpeedDirty := True;
  Updating := True;
  try
    if Sender = AmountSlider then
    begin
      if AmountSlider.Position = 0 then AmountEdit.Text := '∞'
      else AmountEdit.Text := BytesText(
        QuotaSliderBytes(AmountSlider.Position));
    end
    else if SpeedSlider.Position = 0 then SpeedEdit.Text := '∞'
    else SpeedEdit.Text := IntToStr(SpeedSlider.Position) + ' KB/s';
  finally
    Updating := False;
  end;
end;

procedure TQuotaSliders.EditChanged(Sender: TObject);
var
  Value: Int64;
begin
  if Updating then Exit;
  if Sender = AmountEdit then AmountDirty := True
  else SpeedDirty := True;
  Updating := True;
  try
    if Sender = AmountEdit then
    begin
      if ParseQuota(AmountEdit.Text, Value) then
        AmountSlider.Position := QuotaSliderPosition(Value);
    end
    else if ParseLimit(SpeedEdit.Text, Value) then
      SpeedSlider.Position := Min(10000, (Value + 512) div 1024);
  finally
    Updating := False;
  end;
end;

procedure TQuotaSliders.BlockChanged(Sender: TObject);
begin
  SpeedSlider.Enabled := not BlockBox.Checked;
  SpeedEdit.Enabled := not BlockBox.Checked;
end;

function ParseClock(const Value: string; out Minutes: Integer): Boolean;
var
  H, M: Integer;
begin
  Result := (Length(Value) = 5) and (Value[3] = ':') and
    TryStrToInt(Copy(Value, 1, 2), H) and
    TryStrToInt(Copy(Value, 4, 2), M) and
    (H >= 0) and (H <= 23) and (M >= 0) and (M <= 59);
  if Result then Minutes := H * 60 + M;
end;

function ClockText(Minutes: Integer): string;
begin
  Result := Format('%.2d:%.2d', [Minutes div 60, Minutes mod 60]);
end;

function ParseSliderKiB(const Value: string; out Bps: Int64): Boolean;
var
  S: string;
  KiB: Integer;
begin
  S := Trim(LowerCase(Value));
  if (S = '') or (S = '∞') or (S = 'unlimited') then
  begin
    Bps := 0;
    Exit(True);
  end;
  if RightStr(S, 5) = 'kib/s' then Delete(S, Length(S) - 4, 5)
  else if RightStr(S, 4) = 'kb/s' then Delete(S, Length(S) - 3, 4);
  Result := TryStrToInt(Trim(S), KiB) and (KiB >= 0) and
    (KiB <= 10000);
  if Result then Bps := Int64(KiB) * 1024;
end;

constructor TLimitDialog.CreateForRates(TheOwner: TComponent;
  const AppName: string; DownBps, UpBps: Int64; DarkTheme: Boolean);
var
  Back, Fore, FieldBack, Accent: TColor;
begin
  inherited CreateNew(TheOwner, 1);
  Caption := 'Speed limits - ' + AppName;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Icon.Assign(Application.Icon);
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  ClientWidth := MulDiv(540, Screen.PixelsPerInch, 96);
  ClientHeight := MulDiv(320, Screen.PixelsPerInch, 96);
  FInitialDownBps := DownBps;
  FInitialUpBps := UpBps;

  FContent := TScrollBox.Create(Self);
  FContent.Parent := Self;
  FContent.Align := alClient;
  FContent.BorderStyle := bsNone;
  FContent.AutoScroll := True;
  FContent.HorzScrollBar.Visible := False;
  FFooter := TPanel.Create(Self);
  FFooter.Parent := Self;
  FFooter.Align := alBottom;
  FFooter.BevelOuter := bvNone;

  FIntro := TLabel.Create(Self);
  FIntro.Parent := FContent;
  FIntro.AutoSize := False;
  FIntro.WordWrap := True;
  FIntro.Caption := 'Move a slider or type a value in KiB/s.';
  FUploadLabel := TLabel.Create(Self);
  FUploadLabel.Parent := FContent;
  FUploadLabel.Caption := 'Upload:';
  FDownloadLabel := TLabel.Create(Self);
  FDownloadLabel.Parent := FContent;
  FDownloadLabel.Caption := 'Download:';
  FUploadSlider := TTrackBar.Create(Self);
  FUploadSlider.Parent := FContent;
  FUploadSlider.Min := 0;
  FUploadSlider.Max := 10000;
  FUploadSlider.TickStyle := tsNone;
  FUploadSlider.LineSize := 1;
  FUploadSlider.PageSize := 100;
  FDownloadSlider := TTrackBar.Create(Self);
  FDownloadSlider.Parent := FContent;
  FDownloadSlider.Min := 0;
  FDownloadSlider.Max := 10000;
  FDownloadSlider.TickStyle := tsNone;
  FDownloadSlider.LineSize := 1;
  FDownloadSlider.PageSize := 100;
  FUploadValue := TEdit.Create(Self);
  FUploadValue.Parent := FContent;
  FDownloadValue := TEdit.Create(Self);
  FDownloadValue.Parent := FContent;
  FUploadEstimate := TLabel.Create(Self);
  FUploadEstimate.Parent := FContent;
  FUploadEstimate.AutoSize := False;
  FDownloadEstimate := TLabel.Create(Self);
  FDownloadEstimate.Parent := FContent;
  FDownloadEstimate.AutoSize := False;
  FHint := TLabel.Create(Self);
  FHint.Parent := FContent;
  FHint.AutoSize := False;
  FHint.WordWrap := True;
  FHint.Caption := '∞ means unlimited; slider maximum 10,000 KiB/s. ' +
    'Speed limits allow 25% headroom. Speed-test results can vary.';
  if (DownBps > Int64(10000) * 1024) or
    (UpBps > Int64(10000) * 1024) then
    FHint.Caption := FHint.Caption +
      ' Existing higher limits are kept until you change them.';
  FSaveButton := TButton.Create(Self);
  FSaveButton.Parent := FFooter;
  FSaveButton.Caption := 'Save';
  FSaveButton.Default := True;
  FSaveButton.OnClick := @SaveClicked;
  FCancelButton := TButton.Create(Self);
  FCancelButton.Parent := FFooter;
  FCancelButton.Caption := 'Cancel';
  FCancelButton.Cancel := True;
  FCancelButton.ModalResult := mrCancel;

  if DarkTheme then
  begin
    Back := RGBToColor(29, 32, 38);
    FieldBack := RGBToColor(39, 43, 50);
    Fore := clWhite;
    Accent := RGBToColor(98, 207, 255);
  end
  else
  begin
    Back := clBtnFace;
    FieldBack := clWindow;
    Fore := clWindowText;
    Accent := RGBToColor(0, 89, 150);
  end;
  Color := Back;
  FContent.Color := Back;
  FFooter.Color := Back;
  FIntro.Font.Color := Fore;
  FUploadLabel.Font.Color := Fore;
  FDownloadLabel.Font.Color := Fore;
  FHint.Font.Color := Fore;
  FUploadEstimate.Font.Color := Accent;
  FDownloadEstimate.Font.Color := Accent;
  FUploadSlider.Color := Back;
  FDownloadSlider.Color := Back;
  FUploadValue.Color := FieldBack;
  FDownloadValue.Color := FieldBack;
  FUploadValue.Font.Color := Fore;
  FDownloadValue.Font.Color := Fore;

  FUpdating := True;
  try
    SetInitialRate(FUploadSlider, FUploadValue, UpBps);
    SetInitialRate(FDownloadSlider, FDownloadValue, DownBps);
  finally
    FUpdating := False;
  end;
  FUploadSlider.OnChange := @SliderChanged;
  FDownloadSlider.OnChange := @SliderChanged;
  FUploadValue.OnChange := @ValueEdited;
  FDownloadValue.OnChange := @ValueEdited;
  UpdateEstimates;
  OnShow := @DialogShown;
  OnResize := @DialogResized;
  LayoutControls;
end;

procedure TLimitDialog.SetInitialRate(Slider: TTrackBar; ValueBox: TEdit;
  Bps: Int64);
var
  KiB: Int64;
begin
  if Bps = 0 then
  begin
    Slider.Position := 0;
    ValueBox.Text := '∞';
  end
  else
  begin
    KiB := (Bps + 512) div 1024;
    Slider.Position := Min(10000, KiB);
    ValueBox.Text := IntToStr(KiB) + ' KiB/s';
  end;
end;

procedure TLimitDialog.SliderChanged(Sender: TObject);
var
  Slider: TTrackBar;
  ValueBox: TEdit;
begin
  if FUpdating then Exit;
  Slider := TTrackBar(Sender);
  if Slider = FUploadSlider then
  begin
    ValueBox := FUploadValue;
    FUpDirty := True;
  end
  else
  begin
    ValueBox := FDownloadValue;
    FDownDirty := True;
  end;
  FUpdating := True;
  try
    if Slider.Position = 0 then ValueBox.Text := '∞'
    else ValueBox.Text := IntToStr(Slider.Position) + ' KiB/s';
  finally
    FUpdating := False;
  end;
  UpdateEstimates;
end;

procedure TLimitDialog.ValueEdited(Sender: TObject);
var
  Bps: Int64;
  Slider: TTrackBar;
begin
  if FUpdating then Exit;
  if Sender = FUploadValue then
  begin
    FUpDirty := True;
    Slider := FUploadSlider;
  end
  else
  begin
    FDownDirty := True;
    Slider := FDownloadSlider;
  end;
  if not ParseSliderKiB(TEdit(Sender).Text, Bps) then
  begin
    UpdateEstimates;
    Exit;
  end;
  FUpdating := True;
  try
    Slider.Position := Bps div 1024;
  finally
    FUpdating := False;
  end;
  UpdateEstimates;
end;

procedure TLimitDialog.UpdateEstimates;
  function EstimateText(Bps: Int64): string;
  begin
    if Bps = 0 then Exit('Estimated speed test: unlimited');
    // Roughly discount packet headers from the generous wire-rate cap.
    Result := 'Estimated speed test: ~' +
      FormatFloat('0.#', EnforcedLimitBps(Bps) * 8 / 1024000) + ' Mbps';
  end;
var
  Bps: Int64;
begin
  if not FUpDirty then Bps := FInitialUpBps
  else if not ParseSliderKiB(FUploadValue.Text, Bps) then Bps := -1;
  if Bps < 0 then FUploadEstimate.Caption := 'Enter 0–10,000 KiB/s'
  else FUploadEstimate.Caption := EstimateText(Bps);
  if not FDownDirty then Bps := FInitialDownBps
  else if not ParseSliderKiB(FDownloadValue.Text, Bps) then Bps := -1;
  if Bps < 0 then FDownloadEstimate.Caption := 'Enter 0–10,000 KiB/s'
  else FDownloadEstimate.Caption := EstimateText(Bps);
end;

procedure TLimitDialog.SaveClicked(Sender: TObject);
begin
  if FUpDirty then
  begin
    if not ParseSliderKiB(FUploadValue.Text, FResultUpBps) then
    begin
      MessageDlg('Upload limit',
        'Enter ∞ or a whole number from 1 to 10,000 KiB/s.',
        mtError, [mbOK], 0);
      FUploadValue.SetFocus;
      Exit;
    end;
  end
  else FResultUpBps := FInitialUpBps;
  if FDownDirty then
  begin
    if not ParseSliderKiB(FDownloadValue.Text, FResultDownBps) then
    begin
      MessageDlg('Download limit',
        'Enter ∞ or a whole number from 1 to 10,000 KiB/s.',
        mtError, [mbOK], 0);
      FDownloadValue.SetFocus;
      Exit;
    end;
  end
  else FResultDownBps := FInitialDownBps;
  ModalResult := mrOk;
end;

procedure TLimitDialog.GetRates(out DownBps, UpBps: Int64);
begin
  DownBps := FResultDownBps;
  UpBps := FResultUpBps;
end;

procedure TLimitDialog.DialogShown(Sender: TObject);
var
  Area: TRect;
  Margin: Integer;
begin
  Area := Monitor.WorkareaRect;
  Margin := MulDiv(12, PixelsPerInch, 96);
  Width := Min(Width, Area.Right - Area.Left - 2 * Margin);
  Height := Min(Height, Area.Bottom - Area.Top - 2 * Margin);
  Left := Max(Area.Left + Margin,
    Min(Left, Area.Right - Margin - Width));
  Top := Max(Area.Top + Margin,
    Min(Top, Area.Bottom - Margin - Height));
  LayoutControls;
end;

procedure TLimitDialog.DialogResized(Sender: TObject);
begin
  LayoutControls;
end;

procedure TLimitDialog.LayoutControls;
var
  Scale, Pad, Gap, WidthInside, LabelWidth, ValueWidth, SliderWidth,
    FirstY, SecondY, HintY, ButtonWidth: Integer;
  function S(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, Scale, 96);
  end;
begin
  if FLayoutBusy or (FContent = nil) or (FFooter = nil) then Exit;
  FLayoutBusy := True;
  try
    Scale := PixelsPerInch;
    if Scale <= 0 then Scale := 96;
    Pad := S(18);
    Gap := S(8);
    FFooter.Height := S(55);
    WidthInside := Max(1, FContent.ClientWidth - 2 * Pad - S(18));
    FIntro.SetBounds(Pad, S(15), WidthInside, S(35));
    ValueWidth := S(145);
    LabelWidth := S(94);
    if WidthInside >= S(405) then
    begin
      SliderWidth := Max(S(100), WidthInside - LabelWidth -
        ValueWidth - 2 * Gap);
      FirstY := S(60);
      SecondY := S(132);
      FUploadLabel.SetBounds(Pad, FirstY + S(6), LabelWidth, S(30));
      FUploadSlider.SetBounds(Pad + LabelWidth + Gap, FirstY,
        SliderWidth, S(40));
      FUploadValue.SetBounds(FUploadSlider.Left + SliderWidth + Gap,
        FirstY + S(5), ValueWidth, S(30));
      FUploadEstimate.SetBounds(FUploadSlider.Left, FirstY + S(42),
        SliderWidth + Gap + ValueWidth, S(25));
      FDownloadLabel.SetBounds(Pad, SecondY + S(6), LabelWidth, S(30));
      FDownloadSlider.SetBounds(Pad + LabelWidth + Gap, SecondY,
        SliderWidth, S(40));
      FDownloadValue.SetBounds(FDownloadSlider.Left + SliderWidth + Gap,
        SecondY + S(5), ValueWidth, S(30));
      FDownloadEstimate.SetBounds(FDownloadSlider.Left,
        SecondY + S(42), SliderWidth + Gap + ValueWidth, S(25));
      HintY := S(206);
    end
    else
    begin
      ValueWidth := Min(S(145), WidthInside div 2);
      FirstY := S(58);
      SecondY := S(172);
      FUploadLabel.SetBounds(Pad, FirstY + S(4),
        WidthInside - ValueWidth - Gap, S(30));
      FUploadValue.SetBounds(Pad + WidthInside - ValueWidth,
        FirstY, ValueWidth, S(30));
      FUploadSlider.SetBounds(Pad, FirstY + S(34),
        WidthInside, S(40));
      FUploadEstimate.SetBounds(Pad, FirstY + S(77),
        WidthInside, S(25));
      FDownloadLabel.SetBounds(Pad, SecondY + S(4),
        WidthInside - ValueWidth - Gap, S(30));
      FDownloadValue.SetBounds(Pad + WidthInside - ValueWidth,
        SecondY, ValueWidth, S(30));
      FDownloadSlider.SetBounds(Pad, SecondY + S(34),
        WidthInside, S(40));
      FDownloadEstimate.SetBounds(Pad, SecondY + S(77),
        WidthInside, S(25));
      HintY := S(280);
    end;
    FHint.SetBounds(Pad, HintY, WidthInside, S(80));
    ButtonWidth := Min(S(86), Max(1,
      (FFooter.ClientWidth - 2 * Pad - Gap) div 2));
    FCancelButton.SetBounds(FFooter.ClientWidth - Pad - ButtonWidth,
      S(10), ButtonWidth, S(34));
    FSaveButton.SetBounds(FCancelButton.Left - Gap - ButtonWidth,
      S(10), ButtonWidth, S(34));
  finally
    FLayoutBusy := False;
  end;
end;

constructor TDestinationsForm.CreateForApp(TheOwner: TComponent;
  const AppPath: string);
begin
  inherited CreateNew(TheOwner, 1);
  Caption := 'Network activity';
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Icon.Assign(Application.Icon);
  Position := poScreenCenter;
  Width := 900;
  Height := 560;
  Constraints.MinWidth := 280;
  Constraints.MinHeight := 220;
  FPathLabel := TLabel.Create(Self);
  FPathLabel.Parent := Self;
  FPathLabel.Align := alTop;
  FPathLabel.BorderSpacing.Around := 12;
  FPathLabel.AutoSize := False;
  FPathLabel.Height := 44;
  FPathLabel.WordWrap := True;
  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.BorderSpacing.Around := 12;
  FStatusLabel.AutoSize := False;
  FStatusLabel.Height := 42;
  FStatusLabel.WordWrap := True;
  FToolbar := TPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := alTop;
  FToolbar.Height := 44;
  FToolbar.BevelOuter := bvNone;
  FToolbar.BorderSpacing.Left := 12;
  FToolbar.BorderSpacing.Right := 12;
  FView := TComboBox.Create(Self);
  FView.Parent := FToolbar;
  FView.Style := csDropDownList;
  FView.SetBounds(0, 7, 165, 30);
  FView.Items.Add('Live destinations');
  FView.Items.Add('Daily totals');
  FView.Items.Add('Domains by day');
  FView.ItemIndex := 0;
  FView.OnChange := @ViewChanged;
  FSearch := TEdit.Create(Self);
  FSearch.Parent := FToolbar;
  FSearch.SetBounds(175, 7, 290, 30);
  FSearch.TextHint := 'Search domain, IP, or date';
  FSearch.OnChange := @RefreshDestinations;
  FCopy := TButton.Create(Self);
  FCopy.Parent := FToolbar;
  FCopy.Caption := 'Copy';
  FCopy.SetBounds(475, 7, 75, 30);
  FCopy.OnClick := @CopyClick;
  FExport := TButton.Create(Self);
  FExport.Parent := FToolbar;
  FExport.Caption := 'Export Excel';
  FExport.SetBounds(560, 7, 100, 30);
  FExport.OnClick := @ExportClick;
  FSaveDialog := TSaveDialog.Create(Self);
  FSaveDialog.Filter := 'Excel workbook (*.xlsx)|*.xlsx';
  FSaveDialog.DefaultExt := 'xlsx';
  FSaveDialog.Options := FSaveDialog.Options + [ofOverwritePrompt];
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.BorderSpacing.Around := 12;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.Columns.Add.Caption := 'Domain or IP';
  FList.Columns[0].Width := 260;
  FList.Columns.Add.Caption := 'Remote IP';
  FList.Columns[1].Width := 200;
  FList.Columns.Add.Caption := 'Down';
  FList.Columns[2].Width := 90;
  FList.Columns.Add.Caption := 'Up';
  FList.Columns[3].Width := 90;
  FList.Columns.Add.Caption := 'Identified by';
  FList.Columns[4].Width := 105;
  FList.Columns.Add.Caption := 'Last seen';
  FList.Columns[5].Width := 95;
  FList.OnColumnClick := @ColumnClick;
  FList.OnKeyDown := @ListKeyDown;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1000;
  FTimer.OnTimer := @RefreshDestinations;
  FTimer.Enabled := False;
  FSortColumn := 0;
  OnShow := @ActivityShown;
  OnHide := @ActivityHidden;
  OnResize := @ActivityResized;
  SetAppPath(AppPath);
end;

procedure TDestinationsForm.ActivityShown(Sender: TObject);
begin
  FitToMonitor;
  ActivityResized(nil);
  FTimer.Enabled := True;
  RefreshDestinations(nil);
end;

procedure TDestinationsForm.ActivityHidden(Sender: TObject);
begin
  FTimer.Enabled := False;
end;

procedure TDestinationsForm.FitToMonitor;
var
  Area: TRect;
  Margin, NewWidth, NewHeight: Integer;
begin
  Area := Monitor.WorkareaRect;
  Margin := MulDiv(12, PixelsPerInch, 96);
  NewWidth := Area.Right - Area.Left - 2 * Margin;
  NewHeight := Area.Bottom - Area.Top - 2 * Margin;
  if (NewWidth < 1) or (NewHeight < 1) then Exit;
  if Constraints.MinWidth > NewWidth then Constraints.MinWidth := NewWidth;
  if Constraints.MinHeight > NewHeight then Constraints.MinHeight := NewHeight;
  if Width > NewWidth then Width := NewWidth;
  if Height > NewHeight then Height := NewHeight;
  if Left < Area.Left + Margin then Left := Area.Left + Margin;
  if Top < Area.Top + Margin then Top := Area.Top + Margin;
  if Left + Width > Area.Right - Margin then
    Left := Area.Right - Margin - Width;
  if Top + Height > Area.Bottom - Margin then
    Top := Area.Bottom - Margin - Height;
end;

procedure TDestinationsForm.ActivityResized(Sender: TObject);
var
  Scale, Pad, Gap, Inner, RowHeight, ViewWidth, SearchWidth,
    ButtonWidth: Integer;
begin
  if FLayoutBusy or (FToolbar = nil) or (FView = nil) then Exit;
  FLayoutBusy := True;
  try
    Scale := PixelsPerInch;
    if Scale <= 0 then Scale := 96;
    Pad := MulDiv(12, Scale, 96);
    Gap := MulDiv(8, Scale, 96);
    RowHeight := MulDiv(29, Scale, 96);
    Inner := FToolbar.ClientWidth - 2 * Pad;
    if Inner < 1 then Exit;
    if Inner >= MulDiv(680, Scale, 96) then
    begin
      FToolbar.Height := MulDiv(44, Scale, 96);
      ViewWidth := MulDiv(165, Scale, 96);
      FView.SetBounds(Pad, MulDiv(7, Scale, 96), ViewWidth, RowHeight);
      FExport.SetBounds(Pad + Inner - MulDiv(100, Scale, 96),
        MulDiv(7, Scale, 96), MulDiv(100, Scale, 96), RowHeight);
      FCopy.SetBounds(FExport.Left - Gap - MulDiv(75, Scale, 96),
        MulDiv(7, Scale, 96), MulDiv(75, Scale, 96), RowHeight);
      SearchWidth := FCopy.Left - Gap - (FView.Left + FView.Width);
      FSearch.SetBounds(FView.Left + FView.Width + Gap,
        MulDiv(7, Scale, 96), SearchWidth, RowHeight);
      FStatusLabel.Height := MulDiv(42, Scale, 96);
    end
    else
    begin
      FToolbar.Height := MulDiv(78, Scale, 96);
      ViewWidth := MulDiv(140, Scale, 96);
      if ViewWidth > Inner div 2 then ViewWidth := Inner div 2;
      FView.SetBounds(Pad, MulDiv(5, Scale, 96), ViewWidth, RowHeight);
      FSearch.SetBounds(FView.Left + FView.Width + Gap,
        MulDiv(5, Scale, 96), Inner - ViewWidth - Gap, RowHeight);
      ButtonWidth := (Inner - Gap) div 2;
      FCopy.SetBounds(Pad, MulDiv(42, Scale, 96), ButtonWidth, RowHeight);
      FExport.SetBounds(Pad + ButtonWidth + Gap,
        MulDiv(42, Scale, 96), Inner - ButtonWidth - Gap, RowHeight);
      FStatusLabel.Height := MulDiv(60, Scale, 96);
    end;
    FPathLabel.Height := MulDiv(34, Scale, 96);
  finally
    FLayoutBusy := False;
  end;
end;

procedure TDestinationsForm.ApplyTheme(DarkTheme: Boolean);
var
  Back, Fore: TColor;
begin
  if DarkTheme then
  begin
    Back := RGBToColor(29, 32, 38);
    Fore := clWhite;
    FList.Color := RGBToColor(39, 43, 50);
  end
  else
  begin
    Back := clBtnFace;
    Fore := clBlack;
    FList.Color := clWhite;
  end;
  Color := Back;
  FPathLabel.Font.Color := Fore;
  FStatusLabel.Font.Color := Fore;
  FList.Font.Color := Fore;
end;

procedure TDestinationsForm.SetAppPath(const AppPath: string);
begin
  FAppPath := AppPath;
  Caption := 'Network activity - ' + ExtractFileName(AppPath);
  FPathLabel.Caption := 'Network activity for ' + ExtractFileName(AppPath);
  FPathLabel.Hint := AppPath;
  FPathLabel.ShowHint := True;
  RefreshDestinations(nil);
end;

procedure TDestinationsForm.AddActivityRow(const Row: TActivityRow);
var
  Query: string;
begin
  Query := LowerCase(Trim(FSearch.Text));
  if (Query <> '') and
    (Pos(Query, LowerCase(Row.Name)) = 0) and
    (Pos(Query, LowerCase(Row.Address)) = 0) and
    (Pos(Query, LowerCase(Row.Day)) = 0) and
    (Pos(Query, LowerCase(Row.Source)) = 0) then Exit;
  SetLength(FRows, Length(FRows) + 1);
  FRows[High(FRows)] := Row;
end;

function TDestinationsForm.CompareRows(const A, B: TActivityRow): Integer;
var
  LeftText, RightText: string;
  LeftNumber, RightNumber: Int64;
begin
  Result := 0;
  LeftText := '';
  RightText := '';
  LeftNumber := 0;
  RightNumber := 0;
  if FView.ItemIndex = 0 then
    case FSortColumn of
      0: begin LeftText := A.Name; RightText := B.Name; end;
      1: begin LeftText := A.Address; RightText := B.Address; end;
      2: begin LeftNumber := A.DownloadBytes; RightNumber := B.DownloadBytes; end;
      3: begin LeftNumber := A.UploadBytes; RightNumber := B.UploadBytes; end;
      4: begin LeftText := A.Source; RightText := B.Source; end;
      5: begin LeftNumber := A.SeenMs; RightNumber := B.SeenMs; end;
    end
  else
    case FSortColumn of
      0: begin LeftText := A.Day; RightText := B.Day; end;
      1: begin LeftText := A.Name; RightText := B.Name; end;
      2: begin LeftText := A.Address; RightText := B.Address; end;
      3: begin LeftNumber := A.DownloadBytes; RightNumber := B.DownloadBytes; end;
      4: begin LeftNumber := A.UploadBytes; RightNumber := B.UploadBytes; end;
      5: begin LeftText := A.Source; RightText := B.Source; end;
    end;
  if (FSortColumn = 2) and (FView.ItemIndex = 0) or
    (FSortColumn = 3) or
    ((FSortColumn = 4) and (FView.ItemIndex <> 0)) or
    ((FSortColumn = 5) and (FView.ItemIndex = 0)) then
  begin
    if LeftNumber < RightNumber then Result := -1
    else if LeftNumber > RightNumber then Result := 1;
  end
  else Result := CompareText(LeftText, RightText);
  if FSortDescending then Result := -Result;
  if Result = 0 then Result := CompareText(A.Name, B.Name);
end;

procedure TDestinationsForm.SortRows(L, R: Integer);
var
  I, J: Integer;
  Pivot, Swap: TActivityRow;
begin
  if L >= R then Exit;
  I := L;
  J := R;
  Pivot := FRows[(L + R) div 2];
  repeat
    while CompareRows(FRows[I], Pivot) < 0 do Inc(I);
    while CompareRows(FRows[J], Pivot) > 0 do Dec(J);
    if I <= J then
    begin
      Swap := FRows[I];
      FRows[I] := FRows[J];
      FRows[J] := Swap;
      Inc(I);
      Dec(J);
    end;
  until I > J;
  if L < J then SortRows(L, J);
  if I < R then SortRows(I, R);
end;

procedure TDestinationsForm.ViewChanged(Sender: TObject);
begin
  FSortColumn := 0;
  FSortDescending := FView.ItemIndex <> 0;
  if FView.ItemIndex = 0 then
  begin
    FList.Columns[0].Caption := 'Domain or IP';
    FList.Columns[1].Caption := 'Remote IP';
    FList.Columns[2].Caption := 'Down';
    FList.Columns[3].Caption := 'Up';
    FList.Columns[4].Caption := 'Identified by';
    FList.Columns[5].Caption := 'Last seen';
    FList.Columns[0].Width := 260;
    FList.Columns[1].Width := 200;
    FList.Columns[2].Width := 90;
    FList.Columns[3].Width := 90;
    FList.Columns[4].Width := 105;
    FList.Columns[5].Width := 95;
  end
  else
  begin
    FList.Columns[0].Caption := 'Day';
    FList.Columns[1].Caption := 'Domain or IP';
    FList.Columns[2].Caption := 'Remote IP';
    FList.Columns[3].Caption := 'Down';
    FList.Columns[4].Caption := 'Up';
    FList.Columns[5].Caption := 'Identified by';
    FList.Columns[0].Width := 110;
    FList.Columns[1].Width := 250;
    FList.Columns[2].Width := 190;
    FList.Columns[3].Width := 90;
    FList.Columns[4].Width := 90;
    FList.Columns[5].Width := 110;
  end;
  RefreshDestinations(nil);
end;

procedure TDestinationsForm.ColumnClick(Sender: TObject;
  Column: TListColumn);
begin
  if FSortColumn = Column.Index then
    FSortDescending := not FSortDescending
  else
  begin
    FSortColumn := Column.Index;
    FSortDescending := False;
  end;
  RefreshDestinations(nil);
end;

procedure TDestinationsForm.RefreshDestinations(Sender: TObject);
var
  Content: TStringList;
  Root, Items, Entry: TJSONData;
  Row: TActivityRow;
  Item: TListItem;
  FileName, PreviousName: string;
  I, Age: Integer;
  AgeMs: QWord;
  TotalDown, TotalUp: Int64;
begin
  if FAppPath = '' then Exit;
  if FView.ItemIndex = 0 then FileName := DestinationsPath
  else FileName := HistoryPath;
  if FView.ItemIndex = 0 then
  begin
    Age := FileAge(StatePath);
    if (Age < 0) or ((Now - FileDateToDateTime(Age)) > 5 / 86400) then
    begin
      FStatusLabel.Caption := 'Waiting for the monitoring service.';
      Exit;
    end;
  end;
  if not FileExists(FileName) then
  begin
    FStatusLabel.Caption := 'Waiting for activity data.';
    Exit;
  end;
  Content := TStringList.Create;
  Root := nil;
  try
    Content.LoadFromFile(FileName);
    Root := GetJSON(Content.Text);
    if FView.ItemIndex = 1 then Items := TJSONObject(Root).Find('days')
    else Items := TJSONObject(Root).Find('destinations');
    if (Items = nil) or (Items.JSONType <> jtArray) then
      raise Exception.Create('Invalid activity data');
    SetLength(FRows, 0);
    for I := 0 to TJSONArray(Items).Count - 1 do
    begin
      Entry := TJSONArray(Items)[I];
      if (Entry.JSONType <> jtObject) or
        (CompareText(TJSONObject(Entry).Get('path', ''), FAppPath) <> 0) then
        Continue;
      Row.Day := TJSONObject(Entry).Get('day', '');
      Row.Name := TJSONObject(Entry).Get('name', '');
      Row.Address := TJSONObject(Entry).Get('address', '');
      Row.Source := TJSONObject(Entry).Get('source', '');
      if FView.ItemIndex = 1 then Row.Name := ExtractFileName(FAppPath);
      Row.DownloadBytes := TJSONObject(Entry).Get('downloadBytes', Int64(0));
      Row.UploadBytes := TJSONObject(Entry).Get('uploadBytes', Int64(0));
      Row.SeenMs := TJSONObject(Entry).Get('lastSeenMs', Int64(0));
      Row.Seen := '';
      if FView.ItemIndex = 0 then
      begin
        AgeMs := GetTickCount64 - QWord(Row.SeenMs);
        if AgeMs < 5000 then Row.Seen := 'now'
        else if AgeMs < 60000 then Row.Seen := IntToStr(AgeMs div 1000) + 's ago'
        else if AgeMs < 3600000 then
          Row.Seen := IntToStr(AgeMs div 60000) + 'm ago'
        else Row.Seen := IntToStr(AgeMs div 3600000) + 'h ago';
      end;
      AddActivityRow(Row);
    end;
    if Length(FRows) > 1 then SortRows(0, High(FRows));
    PreviousName := '';
    if FList.Selected <> nil then PreviousName := FList.Selected.Caption;
    TotalDown := 0;
    TotalUp := 0;
    FList.Items.BeginUpdate;
    try
      FList.Items.Clear;
      for I := 0 to High(FRows) do
      begin
        Row := FRows[I];
        Item := FList.Items.Add;
        if FView.ItemIndex = 0 then
        begin
          Item.Caption := Row.Name;
          Item.SubItems.Add(Row.Address);
          Item.SubItems.Add(BytesText(Row.DownloadBytes));
          Item.SubItems.Add(BytesText(Row.UploadBytes));
          Item.SubItems.Add(Row.Source);
          Item.SubItems.Add(Row.Seen);
        end
        else
        begin
          Item.Caption := Row.Day;
          Item.SubItems.Add(Row.Name);
          Item.SubItems.Add(Row.Address);
          Item.SubItems.Add(BytesText(Row.DownloadBytes));
          Item.SubItems.Add(BytesText(Row.UploadBytes));
          Item.SubItems.Add(Row.Source);
        end;
        Inc(TotalDown, Row.DownloadBytes);
        Inc(TotalUp, Row.UploadBytes);
        if (PreviousName <> '') and (Item.Caption = PreviousName) then
          Item.Selected := True;
      end;
    finally
      FList.Items.EndUpdate;
    end;
    FStatusLabel.Caption := IntToStr(Length(FRows)) + ' rows; down ' +
      BytesText(TotalDown) + ', up ' + BytesText(TotalUp) +
      '. DNS names from shared lookups are inferred; encrypted names may remain IPs.';
  except
    on E: Exception do
      FStatusLabel.Caption := 'Could not read activity: ' + E.Message;
  end;
  Root.Free;
  Content.Free;
end;

procedure TDestinationsForm.CopyClick(Sender: TObject);
var
  I: Integer;
  Item: TListItem;
  Value: string;
begin
  Item := FList.Selected;
  if Item = nil then Exit;
  Value := Item.Caption;
  for I := 0 to Item.SubItems.Count - 1 do
    Value := Value + #9 + Item.SubItems[I];
  Clipboard.AsText := Value;
end;

procedure TDestinationsForm.ListKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = Ord('C')) and (ssCtrl in Shift) then
  begin
    CopyClick(Sender);
    Key := 0;
  end;
end;

procedure TDestinationsForm.ExportClick(Sender: TObject);
var
  I: Integer;
  Rows: TActivityExportRows;
begin
  if Length(FRows) = 0 then Exit;
  FSaveDialog.FileName := 'app-limiter-' +
    FormatDateTime('yyyymmdd', Date) + '.xlsx';
  if not FSaveDialog.Execute then Exit;
  SetLength(Rows, Length(FRows));
  for I := 0 to High(FRows) do
  begin
    Rows[I].Day := FRows[I].Day;
    Rows[I].Name := FRows[I].Name;
    Rows[I].Address := FRows[I].Address;
    Rows[I].Source := FRows[I].Source;
    Rows[I].DownloadBytes := FRows[I].DownloadBytes;
    Rows[I].UploadBytes := FRows[I].UploadBytes;
  end;
  try
    WriteActivityWorkbook(FSaveDialog.FileName, FAppPath, Rows);
  except
    on E: Exception do
      MessageDlg('Excel export failed', E.Message, mtError, [mbOK], 0);
  end;
end;

function TMainForm.MakeButton(ParentControl: TWinControl;
  const CaptionText: string; X, Y, W, H: Integer;
  Handler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := ParentControl;
  Result.Caption := CaptionText;
  Result.SetBounds(X, Y, W, H);
  Result.OnClick := Handler;
end;

constructor TMainForm.Create(TheOwner: TComponent);
var
  ErrorText: string;
begin
  inherited CreateNew(TheOwner, 1);
  Caption := 'App Limiter';
  Icon.Assign(Application.Icon);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  BorderStyle := bsNone;
  Position := poDesigned;
  Width := ExpandedWidth;
  Height := 680;
  FSortColumn := 0;
  FIconPaths := TStringList.Create;
  FIconPaths.CaseSensitive := False;
  FImages := TImageList.Create(Self);
  FImages.Width := 16;
  FImages.Height := 16;
  if not LoadConfig(ConfigPath, FSettings, FRules, ErrorText) then
  begin
    FSettings := DefaultSettings;
    SetLength(FRules, 0);
    MessageDlg('App Limiter', 'Configuration error: ' + ErrorText,
      mtWarning, [mbOK], 0);
  end;

  FHeader := TPanel.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.Height := 48;
  FHeader.BevelOuter := bvNone;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := FHeader;
  FTitle.Caption := 'App Limiter';
  FTitle.Font.Size := 14;
  FTitle.Font.Style := [fsBold];
  FTitle.SetBounds(14, 13, 190, 26);
  FCollapse := MakeButton(FHeader, '<', 384, 8, 30, 31, @CollapseClick);
  FClose := MakeButton(FHeader, 'x', 420, 8, 30, 31, @CloseClick);

  FBody := TScrollBox.Create(Self);
  FBody.Parent := Self;
  FBody.Align := alClient;
  FBody.BorderStyle := bsNone;
  FBody.AutoScroll := True;
  FBody.HorzScrollBar.Visible := False;
  FPause := MakeButton(FBody, 'Pause all limits', 12, 10, 436, 36,
    @PauseClick);
  FStatusContainer := TPanel.Create(Self);
  FStatusContainer.Parent := FBody;
  FStatusContainer.BevelOuter := bvNone;
  FStatusContainer.SetBounds(14, 55, 430, 24);
  FStatus := TLabel.Create(Self);
  FStatus.Parent := FStatusContainer;
  FStatus.Caption := 'Waiting for backend status';
  FStatus.Align := alClient;
  FList := TListView.Create(Self);
  FList.Parent := FBody;
  FList.SetBounds(12, 82, 436, 385);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.SmallImages := FImages;
  FList.Columns.Add.Caption := 'Application';
  FList.Columns[0].Width := 150;
  FList.Columns.Add.Caption := 'Down';
  FList.Columns[1].Width := 86;
  FList.Columns.Add.Caption := 'Up';
  FList.Columns[2].Width := 86;
  FList.Columns.Add.Caption := 'Limit';
  FList.Columns[3].Width := 108;
  FList.OnSelectItem := @ListSelectItem;
  FList.OnDblClick := @ListDoubleClick;
  FList.OnColumnClick := @MainColumnClick;
  FList.OnMouseDown := @ListMouseDown;
  FPin := MakeButton(FBody, 'Pin / Browse', 12, 477, 105, 33, @PinClick);
  FEdit := MakeButton(FBody, 'Edit limits', 122, 477, 105, 33, @EditClick);
  FToggle := MakeButton(FBody, 'On / Off', 232, 477, 105, 33, @ToggleClick);
  FRemove := MakeButton(FBody, 'Remove', 342, 477, 106, 33, @RemoveClick);
  FBlock := MakeButton(FBody, 'Block internet', 12, 515, 436, 33,
    @BlockClick);
  FDetailsContainer := TPanel.Create(Self);
  FDetailsContainer.Parent := FBody;
  FDetailsContainer.BevelOuter := bvNone;
  FDetailsContainer.SetBounds(14, 519, 430, 88);
  FDetails := TLabel.Create(Self);
  FDetails.Parent := FDetailsContainer;
  FDetails.Align := alClient;
  FDetails.AutoSize := False;
  FDetails.WordWrap := True;
  FDetails.Caption := 'Select an application to see its path and totals.';
  FSettingsButton := MakeButton(FBody, 'Settings', 342, 581, 106, 30,
    @SettingsClick);
  FDestinationsButton := MakeButton(FBody, 'Network activity',
    12, 581, 150, 30, @DestinationsClick);
  FAdvancedButton := MakeButton(FBody, 'Schedule / quota',
    170, 581, 164, 30, @AdvancedClick);

  FAppMenu := TPopupMenu.Create(Self);
  FAppMenu.OnPopup := @AppMenuPopup;
  FMenuPin := TMenuItem.Create(FAppMenu);
  FMenuPin.Caption := 'Pin app';
  FMenuPin.OnClick := @PinClick;
  FAppMenu.Items.Add(FMenuPin);
  FMenuEdit := TMenuItem.Create(FAppMenu);
  FMenuEdit.Caption := 'Edit limits';
  FMenuEdit.OnClick := @EditClick;
  FAppMenu.Items.Add(FMenuEdit);
  FMenuToggle := TMenuItem.Create(FAppMenu);
  FMenuToggle.Caption := 'Turn on / off';
  FMenuToggle.OnClick := @ToggleClick;
  FAppMenu.Items.Add(FMenuToggle);
  FMenuRemove := TMenuItem.Create(FAppMenu);
  FMenuRemove.Caption := 'Remove rule';
  FMenuRemove.OnClick := @RemoveClick;
  FAppMenu.Items.Add(FMenuRemove);
  FMenuBlock := TMenuItem.Create(FAppMenu);
  FMenuBlock.Caption := 'Block internet';
  FMenuBlock.OnClick := @BlockClick;
  FAppMenu.Items.Add(FMenuBlock);
  FMenuDestinations := TMenuItem.Create(FAppMenu);
  FMenuDestinations.Caption := 'Network activity';
  FMenuDestinations.OnClick := @DestinationsClick;
  FAppMenu.Items.Add(FMenuDestinations);
  FMenuAdvanced := TMenuItem.Create(FAppMenu);
  FMenuAdvanced.Caption := 'Schedule / quota';
  FMenuAdvanced.OnClick := @AdvancedClick;
  FAppMenu.Items.Add(FMenuAdvanced);
  FMenuSettings := TMenuItem.Create(FAppMenu);
  FMenuSettings.Caption := 'Settings';
  FMenuSettings.OnClick := @SettingsClick;
  FAppMenu.Items.Add(FMenuSettings);
  FList.PopupMenu := FAppMenu;

  FTab := MakeButton(Self, '>', 0, 0, CollapsedWidth, 80, @CollapseClick);
  FTab.Visible := False;
  FTab.AnchorSideTop.Control := Self;

  FTrayMenu := TPopupMenu.Create(Self);
  FTrayOpen := TMenuItem.Create(FTrayMenu);
  FTrayOpen.Caption := 'Open';
  FTrayOpen.OnClick := @TrayOpenClick;
  FTrayMenu.Items.Add(FTrayOpen);
  FTrayPause := TMenuItem.Create(FTrayMenu);
  FTrayPause.Caption := 'Pause all limits';
  FTrayPause.OnClick := @PauseClick;
  FTrayMenu.Items.Add(FTrayPause);
  FTrayExit := TMenuItem.Create(FTrayMenu);
  FTrayExit.Caption := 'Exit';
  FTrayExit.OnClick := @TrayExitClick;
  FTrayMenu.Items.Add(FTrayExit);
  FTray := TTrayIcon.Create(Self);
  FTray.Hint := 'App Limiter';
  FTray.PopUpMenu := FTrayMenu;
  FTray.OnDblClick := @TrayDblClick;
  FTray.Icon.Assign(Application.Icon);
  FTray.Visible := not FSettings.ParentalMode;
  FDialog := TOpenDialog.Create(Self);
  FDialog.Filter := 'Windows applications|*.exe';
  FDialog.Options := [ofFileMustExist, ofPathMustExist];
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1000;
  FTimer.OnTimer := @InstanceTick;
  FTimer.Enabled := True;
  OnCloseQuery := @Closing;
  OnShow := @FormShown;
  OnResize := @MainResized;
  DockRight;
  RegisterShortcut;
  ApplyTheme;
  RefreshCaption;
  EnsureServiceStarted;
  RefreshState(nil);
  if FSettings.ParentalMode then
  begin
    Application.ShowMainForm := False;
    FOpenAfterStart := CompareText(ParamStr(1), '--startup') <> 0;
  end
  else if FSettings.StartMinimized and
    (CompareText(ParamStr(1), '--show') <> 0) then
    Application.ShowMainForm := False;
end;

destructor TMainForm.Destroy;
begin
  UnregisterHotKey(Handle, HotkeyId);
  SetLength(FRows, 0);
  FIconPaths.Free;
  inherited Destroy;
end;

procedure TMainForm.DockRight;
var
  R: TRect;
  Scale, WorkWidth, WorkHeight, NewWidth, NewHeight: Integer;
begin
  if Monitor <> nil then R := Monitor.WorkareaRect
  else R := Screen.WorkAreaRect;
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
  begin
    R.Left := 0;
    R.Top := 0;
    R.Right := Screen.Width;
    R.Bottom := Screen.Height;
  end;
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
  begin
    R.Right := 1024;
    R.Bottom := 768;
  end;
  Scale := PixelsPerInch;
  if Scale <= 0 then Scale := 96;
  WorkWidth := R.Right - R.Left;
  WorkHeight := R.Bottom - R.Top;
  if FCollapsed then
  begin
    NewWidth := Min(MulDiv(CollapsedWidth, Scale, 96), WorkWidth);
    NewHeight := Min(MulDiv(80, Scale, 96), WorkHeight);
  end
  else
  begin
    NewWidth := Min(MulDiv(ExpandedWidth, Scale, 96), WorkWidth);
    NewHeight := Max(MulDiv(680, Scale, 96), WorkHeight * 3 div 4);
    NewHeight := Min(NewHeight, WorkHeight);
  end;
  SetBounds(R.Right - NewWidth, R.Top, NewWidth, NewHeight);
  LayoutMain;
end;

procedure TMainForm.LayoutMain;
var
  Scale, Pad, Gap, InnerWidth, BodyHeight, ListHeight, RowY,
    ButtonWidth, ButtonHeight, DetailsY, BottomY, FirstWidth,
    SmallWidth, LimitWidth: Integer;
  Wide: Boolean;
  function S(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, Scale, 96);
  end;
begin
  if FLayoutBusy or (FBody = nil) or (FHeader = nil) then Exit;
  FLayoutBusy := True;
  try
    Scale := PixelsPerInch;
    if Scale <= 0 then Scale := 96;
    Pad := S(12);
    Gap := S(6);
    FHeader.Height := S(48);
    FTitle.SetBounds(S(14), S(13), Max(S(80), Width - S(105)), S(26));
    FClose.SetBounds(Width - S(40), S(8), S(30), S(31));
    FCollapse.SetBounds(FClose.Left - S(36), S(8), S(30), S(31));
    FTab.SetBounds(0, 0, Width, Height);
    if FCollapsed or not FBody.Visible then Exit;
    InnerWidth := Max(1, FBody.ClientWidth - 2 * Pad - S(18));
    BodyHeight := FBody.ClientHeight;
    if BodyHeight <= 0 then Exit;
    Wide := InnerWidth >= S(370);
    FPause.SetBounds(Pad, S(10), InnerWidth, S(36));
    FStatusContainer.SetBounds(Pad + S(2), S(54),
      InnerWidth - S(4), S(26));
    // Reserve the full action and details area below the list. The old
    // height calculation let the last row fall below the work area at high DPI.
    if Wide then
      ListHeight := Max(S(170), BodyHeight - S(310))
    else
      ListHeight := Max(S(170), BodyHeight - S(387));
    FList.SetBounds(Pad, S(82), InnerWidth, ListHeight);
    FirstWidth := Max(S(110), InnerWidth * 35 div 100);
    SmallWidth := Max(S(62), InnerWidth * 18 div 100);
    LimitWidth := Max(S(90), InnerWidth - FirstWidth - 2 * SmallWidth);
    FList.Columns[0].Width := FirstWidth;
    FList.Columns[1].Width := SmallWidth;
    FList.Columns[2].Width := SmallWidth;
    FList.Columns[3].Width := LimitWidth;
    RowY := FList.Top + FList.Height + S(10);
    ButtonHeight := S(33);
    if Wide then
    begin
      ButtonWidth := (InnerWidth - 3 * Gap) div 4;
      FPin.SetBounds(Pad, RowY, ButtonWidth, ButtonHeight);
      FEdit.SetBounds(FPin.Left + FPin.Width + Gap, RowY,
        ButtonWidth, ButtonHeight);
      FToggle.SetBounds(FEdit.Left + FEdit.Width + Gap, RowY,
        ButtonWidth, ButtonHeight);
      FRemove.SetBounds(FToggle.Left + FToggle.Width + Gap, RowY,
        InnerWidth - 3 * ButtonWidth - 3 * Gap, ButtonHeight);
      FBlock.SetBounds(Pad, RowY + ButtonHeight + Gap,
        InnerWidth, ButtonHeight);
      DetailsY := FBlock.Top + FBlock.Height + S(8);
    end
    else
    begin
      ButtonWidth := (InnerWidth - Gap) div 2;
      FPin.SetBounds(Pad, RowY, ButtonWidth, ButtonHeight);
      FEdit.SetBounds(Pad + ButtonWidth + Gap, RowY,
        InnerWidth - ButtonWidth - Gap, ButtonHeight);
      FToggle.SetBounds(Pad, RowY + ButtonHeight + Gap,
        ButtonWidth, ButtonHeight);
      FRemove.SetBounds(Pad + ButtonWidth + Gap,
        RowY + ButtonHeight + Gap,
        InnerWidth - ButtonWidth - Gap, ButtonHeight);
      FBlock.SetBounds(Pad, RowY + 2 * ButtonHeight + 2 * Gap,
        InnerWidth, ButtonHeight);
      DetailsY := FBlock.Top + FBlock.Height + S(8);
    end;
    FDetailsContainer.SetBounds(Pad + S(2), DetailsY,
      InnerWidth - S(4), S(88));
    BottomY := DetailsY + FDetailsContainer.Height + S(6);
    if Wide then
    begin
      FDestinationsButton.SetBounds(Pad, BottomY,
        (InnerWidth - 2 * Gap) * 34 div 100, S(32));
      FAdvancedButton.SetBounds(FDestinationsButton.Left +
        FDestinationsButton.Width + Gap, BottomY,
        (InnerWidth - 2 * Gap) * 40 div 100, S(32));
      FSettingsButton.SetBounds(FAdvancedButton.Left +
        FAdvancedButton.Width + Gap, BottomY,
        Pad + InnerWidth - (FAdvancedButton.Left +
        FAdvancedButton.Width + Gap), S(32));
    end
    else
    begin
      ButtonWidth := (InnerWidth - Gap) div 2;
      FDestinationsButton.SetBounds(Pad, BottomY, ButtonWidth, S(32));
      FAdvancedButton.SetBounds(Pad + ButtonWidth + Gap, BottomY,
        InnerWidth - ButtonWidth - Gap, S(32));
      FSettingsButton.SetBounds(Pad, BottomY + S(32) + Gap,
        InnerWidth, S(32));
    end;
  finally
    FLayoutBusy := False;
  end;
end;

procedure TMainForm.MainResized(Sender: TObject);
begin
  LayoutMain;
end;

procedure TMainForm.FormShown(Sender: TObject);
begin
  DockRight;
end;

procedure TMainForm.WMDisplayChange(var Message: TMessage);
begin
  inherited;
  if FBody <> nil then DockRight;
end;

procedure TMainForm.EnsureServiceStarted;
var
  Manager, Service: THandle;
  ServiceNameWide: UnicodeString;
begin
  Manager := OpenSCManagerW(nil, nil, SC_MANAGER_CONNECT);
  if Manager = 0 then Exit;
  try
    ServiceNameWide := 'AppLimiterService';
    Service := OpenServiceW(Manager, PWideChar(ServiceNameWide), SERVICE_START);
    if Service = 0 then Exit;
    try
      StartServiceW(Service, 0, nil);
    finally
      CloseServiceHandle(Service);
    end;
  finally
    CloseServiceHandle(Manager);
  end;
end;

function TMainForm.StopAppService: Boolean;
var
  Manager, Service: THandle;
  ServiceNameWide: UnicodeString;
  Status: TWinServiceStatus;
  I: Integer;
begin
  Result := False;
  Manager := OpenSCManagerW(nil, nil, SC_MANAGER_CONNECT);
  if Manager = 0 then Exit;
  try
    ServiceNameWide := 'AppLimiterService';
    Service := OpenServiceW(Manager, PWideChar(ServiceNameWide),
      SERVICE_STOP or SERVICE_QUERY_STATUS);
    if Service = 0 then Exit;
    try
      FillChar(Status, SizeOf(Status), 0);
      if not ControlService(Service, SERVICE_CONTROL_STOP, @Status) and
        (GetLastError <> ERROR_SERVICE_NOT_ACTIVE) then Exit;
      for I := 1 to 50 do
      begin
        if QueryServiceStatus(Service, @Status) and
          (Status.CurrentState = SERVICE_STOPPED) then Exit(True);
        Sleep(100);
      end;
    finally
      CloseServiceHandle(Service);
    end;
  finally
    CloseServiceHandle(Manager);
  end;
end;

procedure TMainForm.SetCollapsed(Value: Boolean);
begin
  FCollapsed := Value;
  FHeader.Visible := not Value;
  FBody.Visible := not Value;
  FTab.Visible := Value;
  DockRight;
end;

function TMainForm.Save: Boolean;
var
  ErrorText, ReloadError: string;
begin
  Result := SaveConfig(ConfigPath, FSettings, FRules, ErrorText);
  if not Result then
  begin
    // Actions edit the in-memory copy first. Restore the last persisted
    // settings so the controls never imply that an unsaved limit is active.
    if LoadConfig(ConfigPath, FSettings, FRules, ReloadError) then
    begin
      FTray.Visible := not FSettings.ParentalMode;
      ApplyTheme;
      RegisterShortcut;
    end;
    MessageDlg('App Limiter', 'Could not save settings: ' + ErrorText,
      mtError, [mbOK], 0);
  end;
  RefreshCaption;
  RefreshState(nil);
end;

procedure TMainForm.RefreshCaption;
begin
  if FSettings.Paused then
  begin
    FPause.Caption := 'Resume limits';
    FTrayPause.Caption := 'Resume limits';
  end
  else
  begin
    FPause.Caption := 'Pause all limits';
    FTrayPause.Caption := 'Pause all limits';
  end;
end;

function TMainForm.RuleIndex(const Path: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FRules) do
    if SameWindowsPath(FRules[I].Path, Path) then Exit(I);
  Result := -1;
end;

function TMainForm.IconIndex(const Path: string): Integer;
var
  I: Integer;
  LargeIcon, SmallIcon: HICON;
  AppIcon: TIcon;
  WidePath: UnicodeString;
begin
  I := FIconPaths.IndexOf(Path);
  if I >= 0 then Exit(PtrInt(FIconPaths.Objects[I]) - 1);
  Result := -1;
  LargeIcon := 0;
  SmallIcon := 0;
  WidePath := UnicodeString(UTF8Decode(Path));
  if ExtractIconExW(PWideChar(WidePath), 0, @LargeIcon, @SmallIcon, 1) > 0 then
  begin
    if SmallIcon <> 0 then
    begin
      AppIcon := TIcon.Create;
      try
        AppIcon.Handle := SmallIcon;
        Result := FImages.AddIcon(AppIcon);
      finally
        AppIcon.Free;
      end;
    end;
    if LargeIcon <> 0 then DestroyIcon(LargeIcon);
  end;
  FIconPaths.AddObject(Path, TObject(PtrInt(Result + 1)));
end;

procedure TMainForm.AddRow(const Path, DisplayName: string; DownBps,
  UpBps, DownTotal, UpTotal, QuotaUsed: Int64; IsActive: Boolean);
var
  Index: Integer;
begin
  SetLength(FRows, Length(FRows) + 1);
  Index := High(FRows);
  FRows[Index].Path := Path;
  FRows[Index].DisplayName := DisplayName;
  FRows[Index].DownBps := DownBps;
  FRows[Index].UpBps := UpBps;
  FRows[Index].DownTotal := DownTotal;
  FRows[Index].UpTotal := UpTotal;
  FRows[Index].QuotaUsed := QuotaUsed;
  FRows[Index].IsActive := IsActive;
  Index := RuleIndex(Path);
  if Index < 0 then FRows[High(FRows)].LimitLabel := '—'
  else if not FRules[Index].Enabled then FRows[High(FRows)].LimitLabel := 'Off'
  else if FRules[Index].Blocked then FRows[High(FRows)].LimitLabel := 'Blocked'
  else if FRules[Index].ScheduleEnabled and
    FRules[Index].BlockOutsideSchedule and
    not ScheduleActive(FRules[Index], Now) then
    FRows[High(FRows)].LimitLabel := 'Schedule blocked'
  else if FRules[Index].BlockAfterQuota and
    (FRules[Index].QuotaBytes > 0) and
    (QuotaUsed >= FRules[Index].QuotaBytes) then
    FRows[High(FRows)].LimitLabel := 'Quota blocked'
  else if FSettings.Paused then FRows[High(FRows)].LimitLabel := 'Paused'
  else if FRules[Index].ScheduleEnabled and
    not ScheduleActive(FRules[Index], Now) then
    FRows[High(FRows)].LimitLabel := 'Scheduled'
  else FRows[High(FRows)].LimitLabel := LimitText(FRules[Index].DownloadBps) + ' / ' +
    LimitText(FRules[Index].UploadBps);
end;

function TMainForm.CompareMainRows(const A, B: TMainRow): Integer;
begin
  case FSortColumn of
    1: if A.DownBps < B.DownBps then Result := -1
       else if A.DownBps > B.DownBps then Result := 1 else Result := 0;
    2: if A.UpBps < B.UpBps then Result := -1
       else if A.UpBps > B.UpBps then Result := 1 else Result := 0;
    3: Result := CompareText(A.LimitLabel, B.LimitLabel);
  else
    Result := CompareText(A.DisplayName, B.DisplayName);
  end;
  if FSortDescending then Result := -Result;
  if Result = 0 then Result := CompareText(A.Path, B.Path);
end;

procedure TMainForm.SortMainRows(L, R: Integer);
var
  I, J: Integer;
  Pivot, Swap: TMainRow;
begin
  I := L;
  J := R;
  Pivot := FRows[(L + R) div 2];
  repeat
    while CompareMainRows(FRows[I], Pivot) < 0 do Inc(I);
    while CompareMainRows(FRows[J], Pivot) > 0 do Dec(J);
    if I <= J then
    begin
      Swap := FRows[I];
      FRows[I] := FRows[J];
      FRows[J] := Swap;
      Inc(I);
      Dec(J);
    end;
  until I > J;
  if L < J then SortMainRows(L, J);
  if I < R then SortMainRows(I, R);
end;

procedure TMainForm.MainColumnClick(Sender: TObject; Column: TListColumn);
begin
  if FSortColumn = Column.Index then FSortDescending := not FSortDescending
  else
  begin
    FSortColumn := Column.Index;
    FSortDescending := False;
  end;
  RefreshState(nil);
end;

procedure TMainForm.ListMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Item: TListItem;
begin
  Item := FList.GetItemAt(X, Y);
  if (Button = mbLeft) and (Item = nil) then
  begin
    FList.Selected := nil;
    FDetails.Caption := 'No app selected. Schedule / quota applies to the whole computer.';
    Exit;
  end;
  if Button <> mbRight then Exit;
  if Item <> nil then
  begin
    Item.Selected := True;
    Item.Focused := True;
  end
  else FList.Selected := nil;
end;

procedure TMainForm.AppMenuPopup(Sender: TObject);
var
  Path: string;
  Rule: Integer;
begin
  Path := SelectedPath;
  Rule := RuleIndex(Path);
  FMenuPin.Enabled := (Path <> '') and (Rule < 0);
  FMenuEdit.Enabled := Path <> '';
  FMenuToggle.Enabled := Rule >= 0;
  FMenuRemove.Enabled := Rule >= 0;
  FMenuBlock.Enabled := Path <> '';
  FMenuDestinations.Enabled := Path <> '';
  FMenuAdvanced.Enabled := Path <> '';
  if Rule >= 0 then
  begin
    if FRules[Rule].Enabled then FMenuToggle.Caption := 'Turn off'
    else FMenuToggle.Caption := 'Turn on';
    if FRules[Rule].Blocked then
      FMenuBlock.Caption := 'Unblock internet'
    else FMenuBlock.Caption := 'Block internet';
  end
  else
  begin
    FMenuToggle.Caption := 'Turn on / off';
    FMenuBlock.Caption := 'Block internet';
  end;
end;

procedure TMainForm.RefreshState(Sender: TObject);
var
  StateText: TStringList;
  Root, Apps, App: TJSONData;
  Path, NameText, ErrorText, PreviousSelection: string;
  I, J, StateAge: Integer;
  StateFresh: Boolean;
  Seen: array of Boolean;
  Item: TListItem;
begin
  StateAge := FileAge(StatePath);
  StateFresh := (StateAge >= 0) and
    (Abs(Now - FileDateToDateTime(StateAge)) < 5 / 86400);
  if not StateFresh then
  begin
    FStatus.Caption := 'Backend state is stale — enforcement status unknown';
    for I := 0 to FList.Items.Count - 1 do
      if FList.Items[I].SubItems.Count >= 2 then
      begin
        FList.Items[I].SubItems[0] := '—';
        FList.Items[I].SubItems[1] := '—';
      end;
    Exit;
  end;
  PreviousSelection := SelectedPath;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    SetLength(FRows, 0);
    FGlobalQuotaUsed := 0;
    SetLength(Seen, Length(FRules));
    if StateFresh then
    begin
      StateText := TStringList.Create;
      Root := nil;
      try
        StateText.LoadFromFile(StatePath);
        Root := GetJSON(StateText.Text);
        FGlobalQuotaUsed := TJSONObject(Root).Get('globalQuotaUsedBytes',
          Int64(0));
        Apps := TJSONObject(Root).Find('apps');
        if (Apps <> nil) and (Apps.JSONType = jtArray) then
          for I := 0 to TJSONArray(Apps).Count - 1 do
          begin
            App := TJSONArray(Apps)[I];
            Path := TJSONObject(App).Get('path', '');
            if Path = '' then Continue;
            NameText := ExtractFileName(Path);
            AddRow(Path, NameText,
              TJSONObject(App).Get('downloadBps', Int64(0)),
              TJSONObject(App).Get('uploadBps', Int64(0)),
              TJSONObject(App).Get('downloadBytes', Int64(0)),
              TJSONObject(App).Get('uploadBytes', Int64(0)),
              TJSONObject(App).Get('quotaUsedBytes', Int64(0)), True);
            J := RuleIndex(Path);
            if J >= 0 then Seen[J] := True;
          end;
        FStatus.Caption := TJSONObject(Root).Get('status', 'Backend connected');
      except
        on E: Exception do
        begin
          ErrorText := E.Message;
          FStatus.Caption := 'Backend state unavailable: ' + ErrorText;
        end;
      end;
      Root.Free;
      StateText.Free;
    end
    else
      FStatus.Caption := 'Backend state is stale — enforcement status unknown';
    for I := 0 to High(FRules) do
      if not Seen[I] then
        AddRow(FRules[I].Path, ExtractFileName(FRules[I].Path),
          0, 0, 0, 0, 0, False);
    if Length(FRows) > 1 then SortMainRows(0, High(FRows));
    for I := 0 to High(FRows) do
    begin
      Item := FList.Items.Add;
      Item.Caption := FRows[I].DisplayName;
      Item.ImageIndex := IconIndex(FRows[I].Path);
      if FRows[I].IsActive then
      begin
        Item.SubItems.Add(RateText(FRows[I].DownBps));
        Item.SubItems.Add(RateText(FRows[I].UpBps));
      end
      else
      begin
        Item.SubItems.Add('—');
        Item.SubItems.Add('—');
      end;
      Item.SubItems.Add(FRows[I].LimitLabel);
      if (PreviousSelection <> '') and
        (CompareText(FRows[I].Path, PreviousSelection) = 0) then
      begin
        Item.Selected := True;
        Item.Focused := True;
        ListSelectItem(FList, Item, True);
      end;
    end;
    if FList.Selected = nil then
      FDetails.Caption := 'No app selected. Schedule / quota applies to the whole computer.' +
        LineEnding + 'Computer-wide quota used: ' +
        BytesText(FGlobalQuotaUsed);
  finally
    FList.Items.EndUpdate;
  end;
end;

function TMainForm.SelectedPath: string;
begin
  Result := '';
  if (FList.Selected = nil) or (FList.Selected.Index >= Length(FRows)) then Exit;
  Result := FRows[FList.Selected.Index].Path;
end;

procedure TMainForm.ListSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
var
  Rule: Integer;
  Row: TMainRow;
  AfterQuotaText: string;
begin
  if not Selected or (Item.Index >= Length(FRows)) then Exit;
  Row := FRows[Item.Index];
  FDetails.Caption := Row.Path + LineEnding +
    'This run: ' + BytesText(Row.DownTotal + Row.UpTotal) +
    ' (down ' + BytesText(Row.DownTotal) +
    ', up ' + BytesText(Row.UpTotal) + ')';
  if not Row.IsActive then
    FDetails.Caption := FDetails.Caption + LineEnding +
      'No matching network-active process';
  Rule := RuleIndex(Row.Path);
  if Rule >= 0 then
  begin
    if FRules[Rule].BlockAfterQuota then
      AfterQuotaText := 'block internet'
    else
      AfterQuotaText := LimitText(FRules[Rule].QuotaSlowBps);
    if (FRules[Rule].QuotaBytes > 0) and Row.IsActive then
      FDetails.Caption := FDetails.Caption + LineEnding +
        'Quota: ' + BytesText(Row.QuotaUsed) + ' / ' +
        BytesText(FRules[Rule].QuotaBytes) + '; then ' +
        AfterQuotaText;
    if FRules[Rule].Enabled then FToggle.Caption := 'Turn off'
    else FToggle.Caption := 'Turn on';
    if FRules[Rule].Blocked then
      FBlock.Caption := 'Unblock internet'
    else FBlock.Caption := 'Block internet';
  end;
  if Rule < 0 then
  begin
    FToggle.Caption := 'On / Off';
    FBlock.Caption := 'Block internet';
  end;
end;

procedure TMainForm.PauseClick(Sender: TObject);
begin
  FSettings.Paused := not FSettings.Paused;
  Save;
end;

procedure TMainForm.PinClick(Sender: TObject);
var
  Path: string;
  I: Integer;
begin
  Path := SelectedPath;
  if Path = '' then
  begin
    if not FDialog.Execute then Exit;
    Path := ExpandFileName(FDialog.FileName);
  end;
  I := RuleIndex(Path);
  if I >= 0 then Exit;
  SetLength(FRules, Length(FRules) + 1);
  I := High(FRules);
  FRules[I].Path := Path;
  FRules[I].DownloadBps := 0;
  FRules[I].UploadBps := 0;
  FRules[I].Enabled := True;
  Save;
end;

procedure TMainForm.EditClick(Sender: TObject);
var
  Path: string;
  I: Integer;
  DownBps, UpBps: Int64;
  Dialog: TLimitDialog;
begin
  Path := SelectedPath;
  if Path = '' then
  begin
    if not FDialog.Execute then Exit;
    Path := ExpandFileName(FDialog.FileName);
  end;
  I := RuleIndex(Path);
  if I < 0 then
  begin
    DownBps := 0;
    UpBps := 0;
  end;
  if I >= 0 then
  begin
    DownBps := FRules[I].DownloadBps;
    UpBps := FRules[I].UploadBps;
  end;
  Dialog := TLimitDialog.CreateForRates(Self, ExtractFileName(Path),
    DownBps, UpBps, FSettings.DarkTheme);
  try
    if Dialog.ShowModal <> mrOk then Exit;
    Dialog.GetRates(DownBps, UpBps);
  finally
    Dialog.Free;
  end;
  if I < 0 then
  begin
    SetLength(FRules, Length(FRules) + 1);
    I := High(FRules);
    FRules[I].Path := Path;
  end;
  FRules[I].DownloadBps := DownBps;
  FRules[I].UploadBps := UpBps;
  FRules[I].Enabled := True;
  Save;
end;

procedure TMainForm.ToggleClick(Sender: TObject);
var
  I: Integer;
begin
  I := RuleIndex(SelectedPath);
  if I < 0 then Exit;
  FRules[I].Enabled := not FRules[I].Enabled;
  Save;
end;

procedure TMainForm.BlockClick(Sender: TObject);
var
  Path: string;
  I: Integer;
begin
  Path := SelectedPath;
  if Path = '' then
  begin
    if not FDialog.Execute then Exit;
    Path := ExpandFileName(FDialog.FileName);
  end;
  I := RuleIndex(Path);
  if I < 0 then
  begin
    SetLength(FRules, Length(FRules) + 1);
    I := High(FRules);
    FRules[I].Path := Path;
    FRules[I].Enabled := True;
    FRules[I].Blocked := True;
  end
  else if FRules[I].Blocked then
    FRules[I].Blocked := False
  else
  begin
    FRules[I].Enabled := True;
    FRules[I].Blocked := True;
  end;
  Save;
end;

procedure TMainForm.RemoveClick(Sender: TObject);
var
  I, J: Integer;
begin
  I := RuleIndex(SelectedPath);
  if I < 0 then Exit;
  for J := I to High(FRules) - 1 do FRules[J] := FRules[J + 1];
  SetLength(FRules, Length(FRules) - 1);
  Save;
end;

procedure TMainForm.SettingsClick(Sender: TObject);
var
  Dialog: TForm;
  Content: TScrollBox;
  Footer: TPanel;
  StartupBox, MinimizedBox, ParentalBox, DarkBox: TCheckBox;
  IntroLabel, HotkeyLabel: TLabel;
  HotkeyEdit: TEdit;
  SaveButton, CancelButton: TButton;
  Candidate: TSettings;
  StartupMatches, StartupExists, DesiredStartup, StartupChanged: Boolean;
  ErrorText, RollbackError, HotkeyText, Pin: string;
begin
  if not ReadStartupEntry(Application.ExeName, StartupMatches,
    StartupExists, ErrorText) then
  begin
    MessageDlg('Settings', ErrorText, mtError, [mbOK], 0);
    Exit;
  end;
  Dialog := TForm.CreateNew(Self, 1);
  try
    Dialog.Caption := 'App Limiter settings';
    Dialog.Font.Name := 'Segoe UI';
    Dialog.Font.Size := 9;
    Dialog.Position := poScreenCenter;
    Dialog.BorderStyle := bsDialog;
    Dialog.ClientWidth := 480;
    Dialog.ClientHeight := 460;
    Dialog.OnShow := @QuotaDialogShown;
    Dialog.Color := clBtnFace;
    Content := TScrollBox.Create(Dialog);
    Content.Parent := Dialog;
    Content.Align := alClient;
    Content.BorderStyle := bsNone;
    Content.AutoScroll := True;
    Content.HorzScrollBar.Visible := False;
    Content.Color := clBtnFace;
    Footer := TPanel.Create(Dialog);
    Footer.Parent := Dialog;
    Footer.Align := alBottom;
    Footer.Height := 58;
    Footer.BevelOuter := bvNone;
    Footer.Color := clBtnFace;
    IntroLabel := TLabel.Create(Dialog);
    IntroLabel.Parent := Content;
    IntroLabel.AutoSize := False;
    IntroLabel.Caption := 'Choose how App Limiter behaves for your Windows account.';
    IntroLabel.Font.Color := clWindowText;
    IntroLabel.WordWrap := True;
    StartupBox := TCheckBox.Create(Dialog);
    StartupBox.Parent := Content;
    StartupBox.AutoSize := False;
    StartupBox.Caption := 'Start with Windows';
    StartupBox.Checked := StartupExists;
    StartupBox.Font.Color := clWindowText;
    MinimizedBox := TCheckBox.Create(Dialog);
    MinimizedBox.Parent := Content;
    MinimizedBox.AutoSize := False;
    MinimizedBox.Caption := 'Start minimized to the tray';
    MinimizedBox.Checked := FSettings.StartMinimized;
    MinimizedBox.Font.Color := clWindowText;
    ParentalBox := TCheckBox.Create(Dialog);
    ParentalBox.Parent := Content;
    ParentalBox.AutoSize := False;
    ParentalBox.Caption := 'Parental mode (hide tray icon)';
    ParentalBox.Checked := FSettings.ParentalMode;
    ParentalBox.Font.Color := clWindowText;
    DarkBox := TCheckBox.Create(Dialog);
    DarkBox.Parent := Content;
    DarkBox.AutoSize := False;
    DarkBox.Caption := 'Use dark theme';
    DarkBox.Checked := FSettings.DarkTheme;
    DarkBox.Font.Color := clWindowText;
    HotkeyLabel := TLabel.Create(Dialog);
    HotkeyLabel.Parent := Content;
    HotkeyLabel.AutoSize := False;
    HotkeyLabel.Caption := 'Shortcut (Ctrl+Alt+letter)';
    HotkeyLabel.Font.Color := clWindowText;
    HotkeyEdit := TEdit.Create(Dialog);
    HotkeyEdit.Parent := Content;
    HotkeyEdit.Text := FSettings.Hotkey;
    SaveButton := TButton.Create(Dialog);
    SaveButton.Parent := Footer;
    SaveButton.Caption := 'Save';
    SaveButton.ModalResult := mrOk;
    SaveButton.Default := True;
    CancelButton := TButton.Create(Dialog);
    CancelButton.Parent := Footer;
    CancelButton.Caption := 'Cancel';
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;
    repeat
      if Dialog.ShowModal <> mrOk then Exit;
      HotkeyText := Trim(HotkeyEdit.Text);
      if (Length(HotkeyText) = Length('Ctrl+Alt+N')) and
        (CompareText(Copy(HotkeyText, 1, 9), 'Ctrl+Alt+') = 0) and
        (UpCase(HotkeyText[10]) in ['A'..'Z']) then Break;
      MessageDlg('Settings', 'Enter a shortcut such as Ctrl+Alt+N.',
        mtError, [mbOK], 0);
    until False;
    Candidate := FSettings;
    Candidate.StartMinimized := MinimizedBox.Checked;
    Candidate.ParentalMode := ParentalBox.Checked;
    if Candidate.ParentalMode and not FSettings.ParentalMode then
    begin
      if not CreateParentalVerifier(Candidate.PinVerifier) then Exit;
    end
    else if not Candidate.ParentalMode and FSettings.ParentalMode then
    begin
      if not AskPin(False, Pin) then Exit;
      if not VerifyPin(Pin, FSettings.PinVerifier) then
      begin
        MessageDlg('Incorrect parental PIN.', mtError, [mbOK], 0);
        Exit;
      end;
      Pin := '';
      Candidate.PinVerifier := '';
    end;
    Candidate.DarkTheme := DarkBox.Checked;
    Candidate.Hotkey := 'Ctrl+Alt+' + UpCase(HotkeyText[10]);
    DesiredStartup := StartupBox.Checked;
    StartupChanged := (DesiredStartup <> StartupExists) or
      (DesiredStartup and not StartupMatches);
    if StartupChanged and not SetStartupEntry(Application.ExeName,
      DesiredStartup, ErrorText) then
    begin
      MessageDlg('Settings', ErrorText, mtError, [mbOK], 0);
      Exit;
    end;
    FSettings := Candidate;
    if not Save then
    begin
      if StartupChanged and not SetStartupEntry(Application.ExeName,
        StartupExists, RollbackError) then
        MessageDlg('Settings', 'Could not restore the previous Windows ' +
          'startup setting: ' + RollbackError, mtError, [mbOK], 0);
      Exit;
    end;
    ApplyTheme;
    RegisterShortcut;
    FTray.Visible := not FSettings.ParentalMode;
  finally
    Dialog.Free;
  end;
end;

procedure TMainForm.DestinationsClick(Sender: TObject);
var
  Path: string;
begin
  Path := SelectedPath;
  if Path = '' then
  begin
    MessageDlg('Select an application first', mtInformation, [mbOK], 0);
    Exit;
  end;
  if FDestinationsWindow = nil then
    FDestinationsWindow := TDestinationsForm.CreateForApp(Self, Path)
  else
    FDestinationsWindow.SetAppPath(Path);
  FDestinationsWindow.ApplyTheme(FSettings.DarkTheme);
  FDestinationsWindow.Show;
  FDestinationsWindow.BringToFront;
end;

procedure TMainForm.AdvancedClick(Sender: TObject);
var
  Path, ErrorText, UsageText: string;
  Rule, Candidate: TRule;
  Index, Day, DaysMask, StartMinute, EndMinute, I: Integer;
  GlobalMode: Boolean;
  Dialog: TForm;
  Sliders: TQuotaSliders;
  Content: TScrollBox;
  Footer: TPanel;
  ScheduleBox, ScheduleBlockBox, QuotaBlockBox: TCheckBox;
  Days: TCheckListBox;
  StartEdit, EndEdit, QuotaEdit, SlowEdit: TEdit;
  QuotaSlider, SlowSlider: TTrackBar;
  PeriodBox: TComboBox;
  SaveButton, CancelButton: TButton;
  function ReadQuota(out Bytes: Int64): Boolean;
  begin
    if not Sliders.AmountDirty then
    begin
      Bytes := Rule.QuotaBytes;
      Exit(True);
    end;
    Result := ParseQuota(QuotaEdit.Text, Bytes);
  end;
  function ReadSlowSpeed(out Bps: Int64): Boolean;
  begin
    if not Sliders.SpeedDirty and (Rule.QuotaSlowBps > 0) then
    begin
      Bps := Rule.QuotaSlowBps;
      Exit(True);
    end;
    Result := ParseLimit(SlowEdit.Text, Bps);
  end;
  function AddLabel(const Text: string; X, Y, W: Integer): TLabel;
  begin
    Result := TLabel.Create(Dialog);
    Result.Parent := Content;
    Result.Caption := Text;
    Result.AutoSize := False;
    Result.WordWrap := True;
    Result.Font.Color := clWindowText;
    Result.SetBounds(X, Y, W, 34);
    Result.Anchors := [akLeft, akTop];
  end;
  function AddEdit(const Value: string; X, Y, W: Integer): TEdit;
  begin
    Result := TEdit.Create(Dialog);
    Result.Parent := Content;
    Result.Text := Value;
    Result.SetBounds(X, Y, W, 29);
    Result.Anchors := [akLeft, akTop];
  end;
begin
  Path := SelectedPath;
  GlobalMode := Path = '';
  Index := -1;
  if GlobalMode then
  begin
    Rule := FSettings.GlobalRule;
    Rule.Enabled := True;
    UsageText := 'Computer-wide quota used this period: ' +
      BytesText(FGlobalQuotaUsed);
  end;
  if not GlobalMode then
  begin
    Index := RuleIndex(Path);
    if Index >= 0 then Rule := FRules[Index]
    else
    begin
      Rule := Default(TRule);
      Rule.Path := Path;
      Rule.Enabled := True;
      Rule.ScheduleDays := 127;
      Rule.QuotaPeriod := 'monthly';
    end;
    UsageText := 'This run: no network usage yet.';
    for I := 0 to High(FRows) do
      if SameWindowsPath(FRows[I].Path, Path) and FRows[I].IsActive then
      begin
        UsageText := 'This run: ' + BytesText(FRows[I].DownTotal +
          FRows[I].UpTotal) + '; quota used this period: ' +
          BytesText(FRows[I].QuotaUsed);
        Break;
      end;
  end;
  if Rule.ScheduleDays = 0 then Rule.ScheduleDays := 127;
  if Rule.QuotaPeriod = '' then Rule.QuotaPeriod := 'monthly';
  Dialog := TForm.CreateNew(Self, 1);
  Sliders := TQuotaSliders.Create;
  try
    if GlobalMode then
      Dialog.Caption := 'Schedule and data quota - Whole computer'
    else
      Dialog.Caption := 'Schedule and data quota - ' + ExtractFileName(Path);
    Dialog.Font.Name := 'Segoe UI';
    Dialog.Font.Size := 9;
    Dialog.Font.Color := clWindowText;
    Dialog.Color := clBtnFace;
    Dialog.Position := poScreenCenter;
    Dialog.BorderStyle := bsDialog;
    Dialog.ClientWidth := 540;
    Dialog.ClientHeight := 690;
    Dialog.OnShow := @QuotaDialogShown;
    Content := TScrollBox.Create(Dialog);
    Content.Parent := Dialog;
    Content.Align := alClient;
    Content.BorderStyle := bsNone;
    Content.AutoScroll := True;
    Content.HorzScrollBar.Visible := False;
    Footer := TPanel.Create(Dialog);
    Footer.Parent := Dialog;
    Footer.Align := alBottom;
    Footer.Height := 58;
    Footer.BevelOuter := bvNone;
    if GlobalMode then
      AddLabel('No app selected: these rules apply to the whole computer. Select allowed hours below to block access outside them.',
        16, 16, 508)
    else AddLabel('Choose when speed limits apply. Tick the blocking option below to deny internet outside these hours.',
      16, 16, 508);
    ScheduleBox := TCheckBox.Create(Dialog);
    ScheduleBox.Parent := Content;
    ScheduleBox.Caption := 'Use a schedule';
    ScheduleBox.Checked := Rule.ScheduleEnabled;
    ScheduleBox.SetBounds(16, 60, 300, 30);
    AddLabel('Days', 16, 104, 508);
    Days := TCheckListBox.Create(Dialog);
    Days.Parent := Content;
    Days.SetBounds(16, 142, 508, 157);
    Days.Anchors := [akLeft, akTop];
    Days.Items.Add('Monday');
    Days.Items.Add('Tuesday');
    Days.Items.Add('Wednesday');
    Days.Items.Add('Thursday');
    Days.Items.Add('Friday');
    Days.Items.Add('Saturday');
    Days.Items.Add('Sunday');
    for Day := 0 to 6 do
      Days.Checked[Day] := (Rule.ScheduleDays and (1 shl Day)) <> 0;
    AddLabel('Start time (HH:MM)', 16, 312, 508);
    StartEdit := AddEdit(ClockText(Rule.ScheduleStartMin), 16, 352, 508);
    AddLabel('End time (HH:MM)', 16, 394, 508);
    EndEdit := AddEdit(ClockText(Rule.ScheduleEndMin), 16, 434, 508);
    AddLabel('Equal times cover the full selected day. Overnight ranges continue into the next day.',
      16, 476, 508).Height := 48;
    ScheduleBlockBox := TCheckBox.Create(Dialog);
    ScheduleBlockBox.Parent := Content;
    ScheduleBlockBox.AutoSize := False;
    ScheduleBlockBox.Caption := 'Block outside hours';
    ScheduleBlockBox.Checked := Rule.BlockOutsideSchedule;
    ScheduleBlockBox.SetBounds(16, 536, 508, 30);
    ScheduleBlockBox.Anchors := [akLeft, akTop];
    AddLabel('Data quota (download + upload, public traffic)', 16, 582, 508);
    AddLabel(UsageText, 16, 603, 508);
    AddLabel('Quota amount (∞ = no quota)', 16, 624, 508);
    QuotaSlider := TTrackBar.Create(Dialog);
    QuotaSlider.Parent := Content;
    QuotaSlider.SetBounds(16, 652, 508, 40);
    QuotaSlider.Min := 0;
    QuotaSlider.Max := 1000;
    QuotaSlider.Frequency := 100;
    QuotaSlider.Position := QuotaSliderPosition(Rule.QuotaBytes);
    if Rule.QuotaBytes > 0 then
      QuotaEdit := AddEdit(BytesText(Rule.QuotaBytes), 16, 664, 508)
    else QuotaEdit := AddEdit('∞', 16, 664, 508);
    AddLabel('Reset period', 16, 706, 508);
    PeriodBox := TComboBox.Create(Dialog);
    PeriodBox.Parent := Content;
    PeriodBox.Style := csDropDownList;
    PeriodBox.SetBounds(16, 746, 508, 29);
    PeriodBox.Anchors := [akLeft, akTop];
    PeriodBox.Items.Add('Daily');
    PeriodBox.Items.Add('Monthly');
    if Rule.QuotaPeriod = 'daily' then PeriodBox.ItemIndex := 0
    else PeriodBox.ItemIndex := 1;
    QuotaBlockBox := TCheckBox.Create(Dialog);
    QuotaBlockBox.Parent := Content;
    QuotaBlockBox.AutoSize := False;
    QuotaBlockBox.Caption := 'Block after quota';
    QuotaBlockBox.Checked := Rule.BlockAfterQuota;
    QuotaBlockBox.SetBounds(16, 788, 508, 30);
    QuotaBlockBox.Anchors := [akLeft, akTop];
    AddLabel('Speed after quota (download and upload)', 16, 830, 508);
    SlowSlider := TTrackBar.Create(Dialog);
    SlowSlider.Parent := Content;
    SlowSlider.SetBounds(16, 854, 508, 40);
    SlowSlider.Min := 0;
    SlowSlider.Max := 10000;
    SlowSlider.Frequency := 1000;
    SlowSlider.Position := Min(10000,
      (Rule.QuotaSlowBps + 512) div 1024);
    if Rule.QuotaSlowBps > 0 then
      SlowEdit := AddEdit(LimitText(Rule.QuotaSlowBps), 16, 870, 508)
    else SlowEdit := AddEdit('100 KB/s', 16, 870, 508);
    AddLabel('If blocking is off, this speed applies to both download and upload.',
      16, 911, 508);
    Sliders.AmountSlider := QuotaSlider;
    Sliders.SpeedSlider := SlowSlider;
    Sliders.AmountEdit := QuotaEdit;
    Sliders.SpeedEdit := SlowEdit;
    Sliders.BlockBox := QuotaBlockBox;
    QuotaSlider.OnChange := @Sliders.SliderChanged;
    SlowSlider.OnChange := @Sliders.SliderChanged;
    QuotaEdit.OnChange := @Sliders.EditChanged;
    SlowEdit.OnChange := @Sliders.EditChanged;
    QuotaBlockBox.OnChange := @Sliders.BlockChanged;
    Sliders.BlockChanged(nil);
    SaveButton := TButton.Create(Dialog);
    SaveButton.Parent := Footer;
    SaveButton.Caption := 'Save';
    SaveButton.ModalResult := mrOk;
    SaveButton.Default := True;
    SaveButton.SetBounds(338, 12, 85, 34);
    SaveButton.Anchors := [akRight, akBottom];
    CancelButton := TButton.Create(Dialog);
    CancelButton.Parent := Footer;
    CancelButton.Caption := 'Cancel';
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;
    CancelButton.SetBounds(433, 12, 85, 34);
    CancelButton.Anchors := [akRight, akBottom];
    repeat
      if Dialog.ShowModal <> mrOk then Exit;
      Candidate := Rule;
      Candidate.ScheduleEnabled := ScheduleBox.Checked;
      Candidate.BlockOutsideSchedule := ScheduleBlockBox.Checked;
      Candidate.BlockAfterQuota := QuotaBlockBox.Checked;
      DaysMask := 0;
      for Day := 0 to 6 do
        if Days.Checked[Day] then DaysMask := DaysMask or (1 shl Day);
      Candidate.ScheduleDays := DaysMask;
      if not ParseClock(StartEdit.Text, StartMinute) or
        not ParseClock(EndEdit.Text, EndMinute) then
        ErrorText := 'Enter times as HH:MM on a 24-hour clock.'
      else if Candidate.ScheduleEnabled and (DaysMask = 0) then
        ErrorText := 'Select at least one day.'
      else if Candidate.BlockOutsideSchedule and
        not Candidate.ScheduleEnabled then
        ErrorText := 'Enable the schedule to block internet outside its hours.'
      else if not ReadQuota(Candidate.QuotaBytes) then
        ErrorText := 'Enter a quota such as 500 MB or 5 GB.'
      else if Candidate.BlockAfterQuota and (Candidate.QuotaBytes = 0) then
        ErrorText := 'Enter a data quota to block internet when it is reached.'
      else if not Candidate.BlockAfterQuota and
        not ReadSlowSpeed(Candidate.QuotaSlowBps) then
        ErrorText := 'Enter a slower speed such as 100 KB/s or 1 MB/s.'
      else
      begin
        ErrorText := '';
        if Candidate.BlockAfterQuota then Candidate.QuotaSlowBps := 0;
        Candidate.ScheduleStartMin := StartMinute;
        Candidate.ScheduleEndMin := EndMinute;
        if PeriodBox.ItemIndex = 0 then Candidate.QuotaPeriod := 'daily'
        else Candidate.QuotaPeriod := 'monthly';
        if Candidate.QuotaBytes = 0 then Candidate.QuotaSlowBps := 0;
        if (Candidate.QuotaBytes > 0) and
          not Candidate.BlockAfterQuota and
          (Candidate.QuotaSlowBps = 0) then
          ErrorText := 'Choose a slower speed for after the quota.';
        if ErrorText = '' then
        begin
          if GlobalMode then
          begin
            if not IsValidGlobalRule(Candidate, ErrorText) then
              ErrorText := 'Invalid computer-wide rule: ' + ErrorText;
          end
          else if not IsValidRule(Candidate, ErrorText) then
            ErrorText := 'Invalid rule: ' + ErrorText;
        end;
      end;
      if ErrorText <> '' then
        MessageDlg('Schedule and quota', ErrorText, mtError, [mbOK], 0);
    until ErrorText = '';
    if GlobalMode then FSettings.GlobalRule := Candidate
    else
    begin
      if Index < 0 then
      begin
        SetLength(FRules, Length(FRules) + 1);
        Index := High(FRules);
      end;
      FRules[Index] := Candidate;
    end;
    Save;
  finally
    Dialog.Free;
    Sliders.Free;
  end;
end;

procedure TMainForm.FitModalDialog(Sender: TObject);
var
  Dialog: TForm;
  Area: TRect;
  Margin, AvailableWidth, AvailableHeight: Integer;
begin
  if not (Sender is TForm) then Exit;
  Dialog := TForm(Sender);
  Area := Dialog.Monitor.WorkareaRect;
  Margin := MulDiv(12, Dialog.PixelsPerInch, 96);
  AvailableWidth := Area.Right - Area.Left - 2 * Margin;
  AvailableHeight := Area.Bottom - Area.Top - 2 * Margin;
  if (AvailableWidth < 1) or (AvailableHeight < 1) then Exit;
  if Dialog.Width > AvailableWidth then Dialog.Width := AvailableWidth;
  if Dialog.Height > AvailableHeight then Dialog.Height := AvailableHeight;
  Dialog.Left := Max(Area.Left + Margin,
    Min(Dialog.Left, Area.Right - Margin - Dialog.Width));
  Dialog.Top := Max(Area.Top + Margin,
    Min(Dialog.Top, Area.Bottom - Margin - Dialog.Height));
end;

procedure TMainForm.QuotaDialogShown(Sender: TObject);
var
  Dialog: TForm;
  Content: TScrollBox;
  Footer: TPanel;
  Control: TControl;
  LabelControl: TLabel;
  I, Y, AvailableWidth, Lines, LineHeight, TextWidth: Integer;
begin
  FitModalDialog(Sender);
  Dialog := TForm(Sender);
  Content := nil;
  Footer := nil;
  for I := 0 to Dialog.ComponentCount - 1 do
  begin
    if Dialog.Components[I] is TScrollBox then
      Content := TScrollBox(Dialog.Components[I]);
    if (Dialog.Components[I] is TPanel) and
      (TPanel(Dialog.Components[I]).Align = alBottom) then
      Footer := TPanel(Dialog.Components[I]);
  end;
  if (Content = nil) or (Footer = nil) then Exit;
  Content.VertScrollBar.Position := 0;
  AvailableWidth := Max(1, Content.ClientWidth - 40);
  Y := 16;
  for I := 0 to Content.ControlCount - 1 do
  begin
    Control := Content.Controls[I];
    Control.Anchors := [akLeft, akTop];
    Control.Left := 16;
    Control.Width := AvailableWidth;
    if Control is TLabel then
    begin
      LabelControl := TLabel(Control);
      Dialog.Canvas.Font.Assign(LabelControl.Font);
      TextWidth := Dialog.Canvas.TextWidth(LabelControl.Caption);
      LineHeight := Dialog.Canvas.TextHeight('Ag') + 4;
      Lines := Max(1, (TextWidth + AvailableWidth - 1) div AvailableWidth);
      if Lines > 1 then Inc(Lines);
      Control.Height := Max(30, Lines * LineHeight + 4);
    end
    else if Control is TCheckListBox then
      Control.Height := Max(165, TCheckListBox(Control).ItemHeight * 7 + 10)
    else if Control is TTrackBar then
      Control.Height := 42
    else if Control is TCheckBox then
      Control.Height := 30
    else
      Control.Height := 30;
    Control.Top := Y;
    Y := Y + Control.Height + 8;
  end;
  for I := 0 to Footer.ControlCount - 1 do
    if Footer.Controls[I] is TButton then
    begin
      Control := Footer.Controls[I];
      Control.Anchors := [akRight, akTop];
      if TButton(Control).ModalResult = mrOk then
        Control.Left := Max(8, Footer.ClientWidth - 200)
      else
        Control.Left := Max(8, Footer.ClientWidth - 105);
      Control.Top := 12;
      Control.Width := 90;
      Control.Height := 34;
    end;
end;

procedure TMainForm.ListDoubleClick(Sender: TObject);
begin
  DestinationsClick(Sender);
end;

procedure TMainForm.CollapseClick(Sender: TObject);
begin
  SetCollapsed(not FCollapsed);
end;

procedure TMainForm.CloseClick(Sender: TObject);
begin
  Hide;
end;

procedure TMainForm.TrayOpenClick(Sender: TObject);
begin
  if not FSettings.ParentalMode or UnlockPanel then ShowPanel;
end;

procedure TMainForm.TrayDblClick(Sender: TObject);
begin
  TrayOpenClick(Sender);
end;

procedure TMainForm.TrayExitClick(Sender: TObject);
begin
  if not StopAppService then
  begin
    FSettings.Paused := True;
    if not Save then Exit;
  end;
  FExiting := True;
  Close;
end;

procedure TMainForm.Closing(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := FExiting;
  if not CanClose then Hide;
end;

procedure TMainForm.ShowPanel;
begin
  Show;
  WindowState := wsNormal;
  BringToFront;
end;

function TMainForm.UnlockPanel: Boolean;
var
  Pin: string;
  Attempts: Integer;
begin
  if not FSettings.ParentalMode then Exit(True);
  if FPinPromptActive then Exit(False);
  FPinPromptActive := True;
  try
    Result := False;
    for Attempts := 1 to 3 do
    begin
      if not AskPin(False, Pin) then Exit;
      if VerifyPin(Pin, FSettings.PinVerifier) then
      begin
        Pin := '';
        Exit(True);
      end;
      Pin := '';
      MessageDlg('Incorrect parental PIN.', mtError, [mbOK], 0);
    end;
  finally
    FPinPromptActive := False;
  end;
end;

procedure TMainForm.InstanceTick(Sender: TObject);
var
  OpenRequested: Boolean;
begin
  OpenRequested := OpenRequestPending;
  if FOpenAfterStart or OpenRequested then
  begin
    FOpenAfterStart := False;
    if not FSettings.ParentalMode or UnlockPanel then
      ShowPanel;
  end;
  RefreshState(Sender);
end;

procedure TMainForm.RegisterShortcut;
var
  KeyChar: Char;
begin
  UnregisterHotKey(Handle, HotkeyId);
  KeyChar := UpCase(FSettings.Hotkey[Length(FSettings.Hotkey)]);
  if not RegisterHotKey(Handle, HotkeyId, MOD_CONTROL or MOD_ALT,
    Ord(KeyChar)) then
    FStatus.Caption := 'Shortcut unavailable; choose another in Settings';
end;

procedure TMainForm.WMHotKey(var Message: TMessage);
begin
  if Message.WParam = HotkeyId then
  begin
    if Visible and not FCollapsed then SetCollapsed(True)
    else
    begin
      if FSettings.ParentalMode and not UnlockPanel then Exit;
      SetCollapsed(False);
      ShowPanel;
    end;
  end;
  inherited;
end;

procedure TMainForm.ApplyTheme;
var
  Back, Fore: TColor;
begin
  if FSettings.DarkTheme then
  begin
    Back := RGBToColor(29, 32, 38);
    Fore := clWhite;
    FList.Color := RGBToColor(39, 43, 50);
  end
  else
  begin
    Back := clBtnFace;
    Fore := clBlack;
    FList.Color := clWhite;
  end;
  Color := Back;
  FHeader.Color := Back;
  FBody.Color := Back;
  FStatusContainer.Color := Back;
  FDetailsContainer.Color := Back;
  FTitle.Font.Color := Fore;
  FStatus.Font.Color := Fore;
  FDetails.Font.Color := Fore;
  FList.Font.Color := Fore;
  if FDestinationsWindow <> nil then
    FDestinationsWindow.ApplyTheme(FSettings.DarkTheme);
end;

end.
