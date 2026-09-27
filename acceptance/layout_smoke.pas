program layout_smoke;

{$mode objfpc}{$H+}
{$R ..\panel\app_limiter.res}

uses
  SysUtils, Windows, Interfaces, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  mainform;

procedure CheckButtonBounds(Form: TForm; Body: TWinControl;
  const Description: string);
var
  I: Integer;
  Control: TControl;
begin
  for I := 0 to Form.ComponentCount - 1 do
    if Form.Components[I] is TButton then
    begin
      Control := TControl(Form.Components[I]);
      if Control.Parent <> Body then Continue;
      if (Control.Left < 0) or
        (Control.Left + Control.Width > Body.ClientWidth) then
        raise Exception.CreateFmt('%s: %s outside width (%d > %d)',
          [Description, TButton(Control).Caption,
           Control.Left + Control.Width, Body.ClientWidth]);
    end;
end;

procedure CheckMain(WidthValue, HeightValue: Integer);
var
  Form: TMainForm;
  Body: TScrollBox;
  I, MaxBottom: Integer;
  Control: TControl;
  Snapshot: TBitmap;
  DetailTop, ActionBottom: Integer;
begin
  Form := TMainForm.Create(nil);
  try
    Body := nil;
    for I := 0 to Form.ComponentCount - 1 do
      if Form.Components[I] is TScrollBox then
      begin
        Body := TScrollBox(Form.Components[I]);
        Break;
      end;
    if Body = nil then raise Exception.Create('Main scroll area missing');
    Form.AlphaBlend := True;
    Form.AlphaBlendValue := 0;
    Form.Show;
    Form.SetBounds(0, 0,
      MulDiv(WidthValue, Form.PixelsPerInch, 96),
      MulDiv(HeightValue, Form.PixelsPerInch, 96));
    Application.ProcessMessages;
    CheckButtonBounds(Form, Body,
      Format('Main %dx%d', [WidthValue, HeightValue]));
    if not Body.AutoScroll then
      raise Exception.Create('Main area does not scroll on short displays');
    MaxBottom := 0;
    for I := 0 to Form.ComponentCount - 1 do
      if Form.Components[I] is TButton then
      begin
        Control := TControl(Form.Components[I]);
        if (Control.Parent = Body) and
          (Control.Top + Control.Height > MaxBottom) then
          MaxBottom := Control.Top + Control.Height;
      end;
    if (MaxBottom > Body.ClientHeight) and
      (Body.VertScrollBar.Range < MaxBottom) then
      raise Exception.CreateFmt('Main %dx%d: bottom controls not scrollable',
        [WidthValue, HeightValue]);
    if (WidthValue = 460) and (HeightValue >= 680) and
      (MaxBottom > Body.ClientHeight) then
      raise Exception.CreateFmt(
        'Main %dx%d: bottom controls require scrolling (%d > %d)',
        [WidthValue, HeightValue, MaxBottom, Body.ClientHeight]);
    DetailTop := -1;
    ActionBottom := 0;
    for I := 0 to Form.ComponentCount - 1 do
    begin
      if (Form.Components[I] is TLabel) and
        (Pos('Select an application', TLabel(Form.Components[I]).Caption) = 1) then
        DetailTop := TLabel(Form.Components[I]).Parent.Top;
      if (Form.Components[I] is TButton) and
        (TButton(Form.Components[I]).Caption = 'Block internet') then
        ActionBottom := TButton(Form.Components[I]).Top +
          TButton(Form.Components[I]).Height;
    end;
    if ActionBottom = 0 then
      raise Exception.Create('Block internet button missing');
    if (DetailTop >= 0) and (DetailTop < ActionBottom + 4) then
      raise Exception.CreateFmt(
        'Main %dx%d: details overlap buttons (%d < %d), PPI=%d, scroll=%d, body=%d',
        [WidthValue, HeightValue, DetailTop, ActionBottom,
         Form.PixelsPerInch, Body.VertScrollBar.Position, Body.ClientHeight]);
    if ((WidthValue = 320) and (HeightValue = 480)) or
      ((WidthValue = 460) and (HeightValue = 900)) then
    begin
      Snapshot := Form.GetFormImage;
      try
        if WidthValue = 320 then
          Snapshot.SaveToFile('acceptance\layout_panel_compact.bmp')
        else
          Snapshot.SaveToFile('acceptance\layout_panel_tall.bmp');
      finally
        Snapshot.Free;
      end;
    end;
  finally
    Form.Free;
  end;
end;

procedure CheckActivity(WidthValue, HeightValue: Integer);
var
  Form: TDestinationsForm;
  Toolbar: TPanel;
  I: Integer;
  Control: TControl;
  Snapshot: TBitmap;
begin
  Form := TDestinationsForm.CreateForApp(nil, 'C:\Windows\System32\curl.exe');
  try
    Toolbar := nil;
    for I := 0 to Form.ComponentCount - 1 do
      if (Form.Components[I] is TPanel) and
        (TPanel(Form.Components[I]).Align = alTop) then
      begin
        Toolbar := TPanel(Form.Components[I]);
        Break;
      end;
    if Toolbar = nil then raise Exception.Create('Activity toolbar missing');
    Form.AlphaBlend := True;
    Form.AlphaBlendValue := 0;
    Form.Show;
    Form.SetBounds(0, 0,
      MulDiv(WidthValue, Form.PixelsPerInch, 96),
      MulDiv(HeightValue, Form.PixelsPerInch, 96));
    Application.ProcessMessages;
    for I := 0 to Form.ComponentCount - 1 do
      if Form.Components[I] is TControl then
      begin
        Control := TControl(Form.Components[I]);
        if Control.Parent <> Toolbar then Continue;
        if (Control.Left < 0) or
          (Control.Left + Control.Width > Toolbar.ClientWidth) or
          (Control.Top < 0) or
          (Control.Top + Control.Height > Toolbar.ClientHeight) then
          raise Exception.CreateFmt(
            'Activity %dx%d: %s at (%d,%d,%d,%d) outside toolbar (%d,%d)',
            [WidthValue, HeightValue, Control.ClassName,
             Control.Left, Control.Top, Control.Width, Control.Height,
             Toolbar.ClientWidth, Toolbar.ClientHeight]);
      end;
    if (WidthValue = 500) and (HeightValue = 350) then
    begin
      Snapshot := Form.GetFormImage;
      try
        Snapshot.SaveToFile('acceptance\layout_activity_compact.bmp');
      finally
        Snapshot.Free;
      end;
    end;
  finally
    Form.Free;
  end;
end;

begin
  try
    Application.Scaled := True;
    Application.Initialize;
    WriteLn('DPI=', Screen.PixelsPerInch);
    CheckMain(460, 680);
    CheckMain(460, 900);
    CheckMain(320, 480);
    CheckMain(300, 320);
    CheckActivity(900, 560);
    CheckActivity(500, 350);
    CheckActivity(300, 250);
    WriteLn('Responsive layout geometry checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Layout failure: ', E.Message); Flush(Output);
      Halt(1);
    end;
  end;
end.
