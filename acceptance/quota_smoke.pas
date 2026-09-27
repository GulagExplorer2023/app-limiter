program quota_smoke;

{$mode objfpc}{$H+}
{$R ..\panel\app_limiter.res}

uses
  SysUtils, Interfaces, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  ComCtrls, mainform, limiter_data;

type
  TProbe = class
  private
    Timer: TTimer;
    Stage: Integer;
    procedure Tick(Sender: TObject);
  public
    Failure: string;
    SaveActions: Boolean;
    GlobalMode: Boolean;
    constructor Create(ASaveActions: Boolean = False;
      AGlobalMode: Boolean = False);
    destructor Destroy; override;
  end;

constructor TProbe.Create(ASaveActions: Boolean; AGlobalMode: Boolean);
begin
  inherited Create;
  SaveActions := ASaveActions;
  GlobalMode := AGlobalMode;
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
  I: Integer;
  Dialog: TForm;
  Content: TScrollBox;
  Footer: TPanel;
  Control: TControl;
  PreviousBottom: Integer;
  ScheduleBlockFound, QuotaBlockFound: Boolean;
  ScheduleBox, ScheduleBlockBox, QuotaBlockBox: TCheckBox;
  Edits: array[0..3] of TEdit;
  Sliders: array[0..1] of TTrackBar;
  EditCount, SliderCount: Integer;
  Snapshot: TBitmap;
begin
  Dialog := nil;
  try
  for I := 0 to Screen.FormCount - 1 do
    if Pos('Schedule and data quota - ', Screen.Forms[I].Caption) = 1 then
    begin
      Dialog := Screen.Forms[I];
      Break;
    end;
  if Dialog = nil then Exit;
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
  if (Content = nil) or (Footer = nil) then
    raise Exception.Create('Quota scroll area or footer missing');
  ScheduleBlockFound := False;
  QuotaBlockFound := False;
  ScheduleBox := nil;
  ScheduleBlockBox := nil;
  QuotaBlockBox := nil;
  EditCount := 0;
  SliderCount := 0;
  for I := 0 to Dialog.ComponentCount - 1 do
  begin
    if Dialog.Components[I] is TCheckBox then
    begin
      if TCheckBox(Dialog.Components[I]).Caption = 'Use a schedule' then
        ScheduleBox := TCheckBox(Dialog.Components[I]);
      if TCheckBox(Dialog.Components[I]).Caption =
        'Block outside hours' then
      begin
        ScheduleBlockBox := TCheckBox(Dialog.Components[I]);
        ScheduleBlockFound := True;
      end;
      if TCheckBox(Dialog.Components[I]).Caption =
        'Block after quota' then
      begin
        QuotaBlockBox := TCheckBox(Dialog.Components[I]);
        QuotaBlockFound := True;
      end;
    end;
    if Dialog.Components[I] is TEdit then
    begin
      if EditCount <= High(Edits) then
        Edits[EditCount] := TEdit(Dialog.Components[I]);
      Inc(EditCount);
    end;
    if Dialog.Components[I] is TTrackBar then
    begin
      if SliderCount <= High(Sliders) then
        Sliders[SliderCount] := TTrackBar(Dialog.Components[I]);
      Inc(SliderCount);
    end;
  end;
  if not ScheduleBlockFound or not QuotaBlockFound then
    raise Exception.Create('Scheduled or quota block option missing');
  if SaveActions then
  begin
    if (ScheduleBox = nil) or (EditCount <> 4) or (SliderCount <> 2) then
      raise Exception.Create('Schedule, quota, or slider fields missing');
    ScheduleBox.Checked := True;
    ScheduleBlockBox.Checked := True;
    Edits[0].Text := '08:00';
    Edits[1].Text := '20:00';
    if GlobalMode then
    begin
      if Pos('Whole computer', Dialog.Caption) = 0 then
        raise Exception.Create('Unselected app did not open computer-wide quota');
      Content.VertScrollBar.Position := Content.VertScrollBar.Range div 2;
      Application.ProcessMessages;
      Snapshot := Dialog.GetFormImage;
      try
        Snapshot.SaveToFile('acceptance\quota_sliders.bmp');
      finally
        Snapshot.Free;
      end;
      QuotaBlockBox.Checked := False;
      Sliders[0].Position := 0;
      if Edits[2].Text <> '∞' then
        raise Exception.Create('Quota slider did not show unlimited at zero');
      Sliders[0].Position := 500;
      Sliders[1].Position := 250;
      if (Edits[2].Text = '') or
        (Pos('250', Edits[3].Text) = 0) then
        raise Exception.Create('Quota sliders did not update their fields');
    end
    else
    begin
      QuotaBlockBox.Checked := True;
      Edits[2].Text := '500 MB';
      Edits[3].Text := '';
    end;
    Dialog.ModalResult := mrOk;
    Timer.Enabled := False;
    Exit;
  end;
  if Stage = 0 then
  begin
    if (Content.VertScrollBar.Range <= Content.ClientHeight) then
      raise Exception.Create('Quota form did not scroll');
    PreviousBottom := 0;
    for I := 0 to Content.ControlCount - 1 do
    begin
      Control := Content.Controls[I];
      if (Control.Left < 0) or
        (Control.Left + Control.Width > Content.ClientWidth) then
        raise Exception.CreateFmt('Quota control %d exceeds dialog width', [I]);
      if Control.Top < PreviousBottom then
        raise Exception.CreateFmt('Quota control %d overlaps previous field', [I]);
      PreviousBottom := Control.Top + Control.Height;
    end;
    Dialog.ClientWidth := 300;
    Dialog.OnShow(Dialog);
    for I := 0 to Content.ControlCount - 1 do
    begin
      Control := Content.Controls[I];
      if (Control.Left < 0) or
        (Control.Left + Control.Width > Content.ClientWidth) then
        raise Exception.CreateFmt('Compact quota control %d exceeds width', [I]);
    end;
    Dialog.Canvas.Font.Assign(ScheduleBlockBox.Font);
    if (Dialog.Canvas.TextWidth(ScheduleBlockBox.Caption) + 28 >
      ScheduleBlockBox.ClientWidth) or
      (Dialog.Canvas.TextWidth(QuotaBlockBox.Caption) + 28 >
      QuotaBlockBox.ClientWidth) then
      raise Exception.Create('Compact block option text is clipped');
    for I := 0 to Footer.ControlCount - 1 do
    begin
      Control := Footer.Controls[I];
      if (Control.Left < 0) or
        (Control.Left + Control.Width > Footer.ClientWidth) then
        raise Exception.Create('Quota footer button exceeds width');
    end;
    Content.VertScrollBar.Position := Content.VertScrollBar.Range;
    Inc(Stage);
  end
  else
  begin
    if Content.VertScrollBar.Position = 0 then
      raise Exception.Create('Quota form cannot reach bottom fields');
    Dialog.ModalResult := mrCancel;
    Timer.Enabled := False;
  end;
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
  I: Integer;
  List: TListView;
  Advanced: TButton;
  SelectedName: string;
  Settings: TSettings;
  Rules: TRules;
  ErrorText: string;
begin
  try
    Application.Scaled := True;
    Application.Initialize;
    Form := TMainForm.Create(nil);
    try
      Form.Show;
      Application.ProcessMessages;
      List := nil;
      Advanced := nil;
      for I := 0 to Form.ComponentCount - 1 do
      begin
        if Form.Components[I] is TListView then
          List := TListView(Form.Components[I]);
        if (Form.Components[I] is TButton) and
          (TButton(Form.Components[I]).Caption = 'Schedule / quota') then
          Advanced := TButton(Form.Components[I]);
      end;
      if (List = nil) or (Advanced = nil) or (List.Items.Count = 0) then
        raise Exception.Create('Main list or quota button unavailable');
      if (List.PopupMenu = nil) or (List.PopupMenu.Items.Count < 6) then
        raise Exception.Create('App right-click actions unavailable');
      List.Items[0].Selected := True;
      SelectedName := List.Selected.Caption;
      List.OnColumnClick(List, List.Columns[0]);
      for I := 1 to List.Items.Count - 1 do
        if CompareText(List.Items[I - 1].Caption,
          List.Items[I].Caption) < 0 then
          raise Exception.Create('Main list descending sort failed');
      if (List.Selected = nil) or (List.Selected.Caption <> SelectedName) then
        raise Exception.Create('Main list selection lost after sort');
      List.OnColumnClick(List, List.Columns[0]);
      for I := 1 to List.Items.Count - 1 do
        if CompareText(List.Items[I - 1].Caption,
          List.Items[I].Caption) > 0 then
          raise Exception.Create('Main list ascending sort failed');
      Probe := TProbe.Create;
      try
        Advanced.Click;
        if Probe.Failure <> '' then raise Exception.Create(Probe.Failure);
      finally
        Probe.Free;
      end;
      Probe := TProbe.Create(True);
      try
        Advanced.Click;
        if Probe.Failure <> '' then raise Exception.Create(Probe.Failure);
      finally
        Probe.Free;
      end;
      if not LoadConfig(ConfigPath, Settings, Rules, ErrorText) then
        raise Exception.Create(ErrorText);
      if (Length(Rules) = 0) or not Rules[0].BlockOutsideSchedule or
        not Rules[0].BlockAfterQuota or (Rules[0].QuotaBytes = 0) then
        raise Exception.Create('Block options were not saved');
      List.Selected := nil;
      Probe := TProbe.Create(True, True);
      try
        Advanced.Click;
        if Probe.Failure <> '' then raise Exception.Create(Probe.Failure);
      finally
        Probe.Free;
      end;
      if not LoadConfig(ConfigPath, Settings, Rules, ErrorText) then
        raise Exception.Create(ErrorText);
      if not Settings.GlobalRule.Enabled or
        not Settings.GlobalRule.BlockOutsideSchedule or
        Settings.GlobalRule.BlockAfterQuota or
        (Settings.GlobalRule.QuotaBytes <> Int64(1024) * 1024 * 1024) or
        (Settings.GlobalRule.QuotaSlowBps <> 250 * 1024) then
        raise Exception.Create('Computer-wide quota/sliders were not saved');
    finally
      Form.Free;
    end;
    WriteLn('Per-app and computer-wide quota/sliders and layout checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Quota failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
