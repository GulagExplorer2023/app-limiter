program settings_smoke;

{$mode objfpc}{$H+}
{$R ..\panel\app_limiter.res}

uses
  SysUtils, Interfaces, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  mainform, startup_entry;

type
  TProbe = class
  private
    Timer: TTimer;
    procedure Tick(Sender: TObject);
  public
    Failure: string;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TProbe.Create;
begin
  inherited Create;
  Timer := TTimer.Create(nil);
  Timer.Interval := 250;
  Timer.OnTimer := @Tick;
  Timer.Enabled := True;
end;

destructor TProbe.Destroy;
begin
  Timer.Free;
  inherited Destroy;
end;

procedure TProbe.Tick(Sender: TObject);
var
  Dialog: TForm;
  Content: TScrollBox;
  Footer: TPanel;
  StartupBox, ParentalBox: TCheckBox;
  Control: TControl;
  Enabled, Exists: Boolean;
  ErrorText: string;
  I, Bottom: Integer;
begin
  try
  Dialog := nil;
  for I := 0 to Screen.FormCount - 1 do
    if Screen.Forms[I].Caption = 'App Limiter settings' then
      Dialog := Screen.Forms[I];
  if Dialog = nil then Exit;
  Content := nil;
  Footer := nil;
  StartupBox := nil;
  ParentalBox := nil;
  for I := 0 to Dialog.ComponentCount - 1 do
  begin
    if Dialog.Components[I] is TScrollBox then
      Content := TScrollBox(Dialog.Components[I]);
    if Dialog.Components[I] is TPanel then
      Footer := TPanel(Dialog.Components[I]);
    if (Dialog.Components[I] is TCheckBox) and
      (TCheckBox(Dialog.Components[I]).Caption = 'Start with Windows') then
      StartupBox := TCheckBox(Dialog.Components[I]);
    if (Dialog.Components[I] is TCheckBox) and
      (TCheckBox(Dialog.Components[I]).Caption = 'Parental mode (hide tray icon)') then
      ParentalBox := TCheckBox(Dialog.Components[I]);
  end;
  if (Content = nil) or (Footer = nil) or (StartupBox = nil) or
    (ParentalBox = nil) then
    raise Exception.Create('Settings controls missing');
  if Dialog.Color <> clBtnFace then
    raise Exception.Create('Settings has poor native control contrast');
  if not ReadStartupEntry(Application.ExeName, Enabled, Exists, ErrorText) then
    raise Exception.Create(ErrorText);
  if StartupBox.Checked <> Exists then
    raise Exception.Create('Startup checkbox does not reflect Windows');
  Dialog.OnShow(Dialog);
  Bottom := 0;
  for I := 0 to Content.ControlCount - 1 do
    if Content.Controls[I].Top + Content.Controls[I].Height > Bottom then
      Bottom := Content.Controls[I].Top + Content.Controls[I].Height;
  if Bottom + 16 > Content.ClientHeight then
    raise Exception.CreateFmt('Default Settings window clips controls: %d > %d',
      [Bottom + 16, Content.ClientHeight]);
  Dialog.ClientWidth := 300;
  Dialog.ClientHeight := 250;
  Dialog.OnShow(Dialog);
  for I := 0 to Content.ControlCount - 1 do
  begin
    Control := Content.Controls[I];
    if (Control.Left < 0) or
      (Control.Left + Control.Width > Content.ClientWidth) then
      raise Exception.CreateFmt('Settings control %d exceeds compact width: %d > %d',
        [I, Control.Left + Control.Width, Content.ClientWidth]);
  end;
  for I := 0 to Footer.ControlCount - 1 do
  begin
    Control := Footer.Controls[I];
    if (Control.Left < 0) or
      (Control.Left + Control.Width > Footer.ClientWidth) then
      raise Exception.Create('Settings button exceeds compact width');
  end;
  Dialog.ModalResult := mrCancel;
  Timer.Enabled := False;
  except
    on E: Exception do
    begin
      Failure := E.Message;
      if Dialog <> nil then Dialog.ModalResult := mrCancel;
      Timer.Enabled := False;
    end;
  end;
end;

var
  Form: TMainForm;
  Probe: TProbe;
  SettingsButton: TButton;
  I: Integer;
begin
  try
    Application.Scaled := True;
    Application.Initialize;
    Form := TMainForm.Create(nil);
    try
      Form.Show;
      Application.ProcessMessages;
      SettingsButton := nil;
      for I := 0 to Form.ComponentCount - 1 do
        if (Form.Components[I] is TButton) and
          (TButton(Form.Components[I]).Caption = 'Settings') then
          SettingsButton := TButton(Form.Components[I]);
      if SettingsButton = nil then
        raise Exception.Create('Settings button missing');
      Probe := TProbe.Create;
      try
        SettingsButton.Click;
        if Probe.Failure <> '' then raise Exception.Create(Probe.Failure);
      finally
        Probe.Free;
      end;
    finally
      Form.Free;
    end;
    WriteLn('Settings checkbox and compact layout checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Settings smoke failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
