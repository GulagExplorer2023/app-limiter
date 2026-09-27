program parental_mode_smoke;

{$mode objfpc}{$H+}
{$R ..\panel\app_limiter.res}

uses
  SysUtils, Windows, Interfaces, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  mainform, limiter_data, instance_control;

type
  TProbe = class
  private
    Timer: TTimer;
    procedure Tick(Sender: TObject);
  public
    Stage: Integer;
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
  Box: TCheckBox;
  Edits: array[0..1] of TEdit;
  EditCount: Integer;
  ConfirmLabel: TLabel;
  Snapshot: TBitmap;
  I: Integer;
begin
  Dialog := nil;
  try
    for I := 0 to Screen.FormCount - 1 do
      if ((Stage = 0) and
        (Screen.Forms[I].Caption = 'App Limiter settings')) or
        ((Stage in [1, 2]) and
        (Screen.Forms[I].Caption = 'App Limiter parental PIN')) then
        Dialog := Screen.Forms[I];
    if Dialog = nil then Exit;
    if Stage = 0 then
    begin
      Box := nil;
      for I := 0 to Dialog.ComponentCount - 1 do
        if (Dialog.Components[I] is TCheckBox) and
          (TCheckBox(Dialog.Components[I]).Caption =
            'Parental mode (hide tray icon)') then
          Box := TCheckBox(Dialog.Components[I]);
      if Box = nil then raise Exception.Create('Parental mode option missing');
      if Box.Checked then raise Exception.Create('Parental mode started enabled');
      Box.Checked := True;
      Dialog.ModalResult := mrOk;
      Stage := 1;
    end
    else
    begin
      if Stage = 1 then
      begin
        Snapshot := Dialog.GetFormImage;
        try
          Snapshot.SaveToFile('acceptance\pin_dialog.bmp');
        finally
          Snapshot.Free;
        end;
      end;
      EditCount := 0;
      ConfirmLabel := nil;
      for I := 0 to Dialog.ComponentCount - 1 do
      begin
        if (Dialog.Components[I] is TLabel) and
          (TLabel(Dialog.Components[I]).Caption = 'Confirm PIN') then
          ConfirmLabel := TLabel(Dialog.Components[I]);
        if Dialog.Components[I] is TEdit then
        begin
          if EditCount <= High(Edits) then
            Edits[EditCount] := TEdit(Dialog.Components[I]);
          Inc(EditCount);
        end;
      end;
      if ((Stage = 1) and (EditCount <> 2)) or
        ((Stage = 2) and (EditCount <> 1)) then
        raise Exception.Create('PIN fields are incorrect');
      if Stage = 1 then
      begin
        if (ConfirmLabel = nil) or
          (ConfirmLabel.Top < Edits[0].Top + Edits[0].Height + 8) or
          (Edits[1].Top < ConfirmLabel.Top + ConfirmLabel.Height + 8) then
          raise Exception.CreateFmt('PIN confirmation controls overlap (%d,%d; %d,%d; %d,%d)',
            [Edits[0].Top, Edits[0].Height, ConfirmLabel.Top,
             ConfirmLabel.Height, Edits[1].Top, Edits[1].Height]);
      end;
      Edits[0].Text := '123456';
      if Stage = 1 then Edits[1].Text := '123456';
      Dialog.ModalResult := mrOk;
      Timer.Enabled := False;
    end;
  except
    on E: Exception do
    begin
      Failure := E.Message;
      if Dialog <> nil then Dialog.ModalResult := mrCancel;
    end;
  end;
end;

procedure Check(Value: Boolean; const Failure: string);
begin
  if not Value then raise Exception.Create(Failure);
end;

var
  Settings, Reloaded: TSettings;
  Rules, LoadedRules: TRules;
  Form: TMainForm;
  Probe: TProbe;
  Tray: TTrayIcon;
  Button: TButton;
  ErrorText: string;
  FirstInstance: Boolean;
  I, Attempts: Integer;
begin
  try
    Settings := DefaultSettings;
    Settings.ParentalMode := False;
    SetLength(Rules, 0);
    Check(SaveConfig(ConfigPath, Settings, Rules, ErrorText), ErrorText);
    Application.Scaled := True;
    Application.Initialize;
    Form := TMainForm.Create(nil);
    try
      Form.Show;
      Application.ProcessMessages;
      Tray := nil;
      Button := nil;
      for I := 0 to Form.ComponentCount - 1 do
      begin
        if Form.Components[I] is TTrayIcon then
          Tray := TTrayIcon(Form.Components[I]);
        if (Form.Components[I] is TButton) and
          (TButton(Form.Components[I]).Caption = 'Settings') then
          Button := TButton(Form.Components[I]);
      end;
      Check(Tray <> nil, 'Tray icon control missing');
      Check(Button <> nil, 'Settings button missing');
      Probe := TProbe.Create;
      try
        Button.Click;
        Check(Probe.Failure = '', Probe.Failure);
      finally
        Probe.Free;
      end;
      Check(LoadConfig(ConfigPath, Reloaded, LoadedRules, ErrorText), ErrorText);
      Check(Reloaded.ParentalMode, 'Parental mode change was not saved');
      Check(Length(Reloaded.PinVerifier) = 96,
        'Parental PIN was not stored');
      Check(not Tray.Visible, 'Parental mode did not hide the tray icon');
      Form.Hide;
      Check(not Form.Visible and not Tray.Visible,
        'Closing parental mode left a visible panel or tray icon');
      Check(BeginPanelInstance(FirstInstance, ErrorText) and FirstInstance,
        'Could not start single-instance unlock test: ' + ErrorText);
      try
        Probe := TProbe.Create;
        try
          Probe.Stage := 2;
          Check(NotifyRunningPanel, 'Shortcut launch request was lost');
          for Attempts := 1 to 250 do
          begin
            Application.ProcessMessages;
            if Form.Visible or (Probe.Failure <> '') then Break;
            Sleep(20);
          end;
          Check(Probe.Failure = '', Probe.Failure);
          Check(Form.Visible, 'Correct PIN did not open the hidden panel');
        finally
          Probe.Free;
        end;
      finally
        EndPanelInstance;
      end;
    finally
      Form.Free;
    end;
    Application.ShowMainForm := True;
    Form := TMainForm.Create(nil);
    try
      Check(not Application.ShowMainForm,
        'Fresh parental launch did not start hidden');
      if (ParamCount > 0) and (ParamStr(1) = '--startup') then
      begin
        for Attempts := 1 to 75 do
        begin
          Application.ProcessMessages;
          Sleep(20);
        end;
        Check(not Form.Visible,
          'Windows startup opened the parental panel');
      end
      else
      begin
        Probe := TProbe.Create;
        try
          Probe.Stage := 2;
          for Attempts := 1 to 250 do
          begin
            Application.ProcessMessages;
            if Form.Visible or (Probe.Failure <> '') then Break;
            Sleep(20);
          end;
          Check(Probe.Failure = '', Probe.Failure);
          Check(Form.Visible, 'Fresh launch did not request the PIN');
        finally
          Probe.Free;
        end;
      end;
    finally
      Form.Free;
    end;
    WriteLn('Parental PIN save, hidden tray, reopen, and startup checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Parental mode smoke failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
