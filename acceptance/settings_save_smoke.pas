program settings_save_smoke;

{$mode objfpc}{$H+}
{$R ..\panel\app_limiter.res}

uses
  SysUtils, Interfaces, Forms, Controls, StdCtrls, ExtCtrls,
  mainform, startup_entry;

type
  TProbe = class
  private
    Timer: TTimer;
    procedure Tick(Sender: TObject);
  public
    Desired, ExpectedInitial: Boolean;
    Failure: string;
    Ticks: Integer;
    constructor Create(ADesired, AExpectedInitial: Boolean);
    destructor Destroy; override;
  end;

constructor TProbe.Create(ADesired, AExpectedInitial: Boolean);
begin
  inherited Create;
  Desired := ADesired;
  ExpectedInitial := AExpectedInitial;
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
  StartupBox: TCheckBox;
  I: Integer;
begin
  Inc(Ticks);
  Dialog := nil;
  try
    for I := 0 to Screen.FormCount - 1 do
      if Screen.Forms[I].Caption = 'App Limiter settings' then
        Dialog := Screen.Forms[I];
    if Dialog = nil then
    begin
      if Ticks > 20 then
      begin
        Failure := 'Settings dialog did not appear';
        for I := 0 to Screen.FormCount - 1 do
          if Screen.Forms[I].Caption = 'Settings' then
            Screen.Forms[I].ModalResult := mrCancel;
        Timer.Enabled := False;
      end;
      Exit;
    end;
    StartupBox := nil;
    for I := 0 to Dialog.ComponentCount - 1 do
      if (Dialog.Components[I] is TCheckBox) and
        (TCheckBox(Dialog.Components[I]).Caption = 'Start with Windows') then
        StartupBox := TCheckBox(Dialog.Components[I]);
    if StartupBox = nil then raise Exception.Create('Startup checkbox missing');
    if StartupBox.Checked <> ExpectedInitial then
      raise Exception.Create('Startup checkbox did not retain its state');
    StartupBox.Checked := Desired;
    Dialog.ModalResult := mrOk;
    Timer.Enabled := False;
  except
    on E: Exception do
    begin
      Failure := E.Message;
      if Dialog <> nil then Dialog.ModalResult := mrCancel;
    end;
  end;
  Timer.Enabled := False;
end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

var
  Form: TMainForm;
  SettingsButton: TButton;
  Probe: TProbe;
  ErrorText: string;
  Enabled, Exists: Boolean;
  I: Integer;
begin
  try
    Application.Scaled := True;
    Application.Initialize;
    Check(SetStartupEntry(Application.ExeName, False, ErrorText), ErrorText);
    Form := TMainForm.Create(nil);
    try
      Form.Show;
      Application.ProcessMessages;
      SettingsButton := nil;
      for I := 0 to Form.ComponentCount - 1 do
        if (Form.Components[I] is TButton) and
          (TButton(Form.Components[I]).Caption = 'Settings') then
          SettingsButton := TButton(Form.Components[I]);
      Check(SettingsButton <> nil, 'Settings button missing');
      Probe := TProbe.Create(True, False);
      try
        SettingsButton.Click;
        Check(Probe.Failure = '', Probe.Failure);
      finally
        Probe.Free;
      end;
      Check(ReadStartupEntry(Application.ExeName, Enabled, Exists,
        ErrorText), ErrorText);
      Check(Enabled and Exists, 'Saving checked startup did not register it');
      Probe := TProbe.Create(False, True);
      try
        SettingsButton.Click;
        Check(Probe.Failure = '', Probe.Failure);
      finally
        Probe.Free;
      end;
      Check(ReadStartupEntry(Application.ExeName, Enabled, Exists,
        ErrorText), ErrorText);
      Check(not Enabled and not Exists,
        'Saving unchecked startup did not remove it');
    finally
      Form.Free;
      SetStartupEntry(Application.ExeName, False, ErrorText);
    end;
    WriteLn('Settings startup save and remove checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Settings save failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
