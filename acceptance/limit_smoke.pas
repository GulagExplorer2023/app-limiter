program limit_smoke;

{$mode objfpc}{$H+}
{$R ..\panel\app_limiter.res}

uses
  SysUtils, Interfaces, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  mainform, limiter_data;

procedure CheckDialog(InitialDown, InitialUp: Int64;
  ChangeValues: Boolean);
var
  Dialog: TLimitDialog;
  UploadSlider, DownloadSlider: TTrackBar;
  UploadEdit, DownloadEdit: TEdit;
  SaveButton: TButton;
  Content: TScrollBox;
  Footer: TPanel;
  Control: TControl;
  DownBps, UpBps: Int64;
  I: Integer;
  FoundEstimate: Boolean;
begin
  Dialog := TLimitDialog.CreateForRates(nil, 'example.exe',
    InitialDown, InitialUp, True);
  try
    Dialog.Show;
    Application.ProcessMessages;
    UploadSlider := nil;
    DownloadSlider := nil;
    UploadEdit := nil;
    DownloadEdit := nil;
    SaveButton := nil;
    Content := nil;
    Footer := nil;
    for I := 0 to Dialog.ComponentCount - 1 do
    begin
      if Dialog.Components[I] is TTrackBar then
      begin
        if UploadSlider = nil then UploadSlider := TTrackBar(Dialog.Components[I])
        else DownloadSlider := TTrackBar(Dialog.Components[I]);
      end;
      if Dialog.Components[I] is TEdit then
      begin
        if UploadEdit = nil then UploadEdit := TEdit(Dialog.Components[I])
        else DownloadEdit := TEdit(Dialog.Components[I]);
      end;
      if (Dialog.Components[I] is TButton) and
        (TButton(Dialog.Components[I]).Caption = 'Save') then
        SaveButton := TButton(Dialog.Components[I]);
      if Dialog.Components[I] is TScrollBox then
        Content := TScrollBox(Dialog.Components[I]);
      if (Dialog.Components[I] is TPanel) and
        (TPanel(Dialog.Components[I]).Align = alBottom) then
        Footer := TPanel(Dialog.Components[I]);
    end;
    if (UploadSlider = nil) or (DownloadSlider = nil) or
      (UploadEdit = nil) or (DownloadEdit = nil) or
      (SaveButton = nil) or (Content = nil) or (Footer = nil) then
      raise Exception.Create('Speed dialog controls missing');
    if (UploadSlider.Max <> 10000) or (DownloadSlider.Max <> 10000) then
      raise Exception.Create('Slider maximum is not 10,000 KiB/s');
    if ChangeValues then
    begin
      if (UploadEdit.Text <> '∞') or (DownloadEdit.Text <> '∞') then
        raise Exception.Create('Zero is not displayed as infinity');
      UploadSlider.Position := 10000;
      if UploadEdit.Text <> '10000 KiB/s' then
        raise Exception.Create('Upload slider did not update value');
      DownloadEdit.Text := '3000';
      if DownloadSlider.Position <> 3000 then
        raise Exception.Create('Download value did not update slider');
      FoundEstimate := False;
      for I := 0 to Dialog.ComponentCount - 1 do
        if (Dialog.Components[I] is TLabel) and
          (TLabel(Dialog.Components[I]).Caption =
           'Estimated speed test: ~30 Mbps') then
          FoundEstimate := True;
      if not FoundEstimate then
        raise Exception.Create('Expected speed-test estimate missing');
    end
    else if (UploadSlider.Position <> 10000) or
      (UploadEdit.Text <> '20000 KiB/s') then
      raise Exception.Create('Existing high limit was not displayed');
    Dialog.ClientWidth := 320;
    Application.ProcessMessages;
    for I := 0 to Content.ControlCount - 1 do
    begin
      Control := Content.Controls[I];
      if (Control.Left < 0) or
        (Control.Left + Control.Width > Content.ClientWidth) then
        raise Exception.CreateFmt('Compact speed control %d exceeds width', [I]);
    end;
    for I := 0 to Footer.ControlCount - 1 do
    begin
      Control := Footer.Controls[I];
      if (Control.Left < 0) or
        (Control.Left + Control.Width > Footer.ClientWidth) then
        raise Exception.Create('Speed footer button exceeds width');
    end;
    SaveButton.Click;
    if Dialog.ModalResult <> mrOk then
      raise Exception.Create('Speed limit save failed');
    Dialog.GetRates(DownBps, UpBps);
    if ChangeValues then
    begin
      if (DownBps <> 3000 * 1024) or (UpBps <> 10000 * 1024) then
        raise Exception.Create('Speed limit byte conversion failed');
    end
    else if (DownBps <> InitialDown) or (UpBps <> InitialUp) then
      raise Exception.Create('Untouched high limit was changed');
  finally
    Dialog.Free;
  end;
end;

begin
  try
    Application.Scaled := True;
    Application.Initialize;
    if (EnforcedLimitBps(0) <> 0) or
      (EnforcedLimitBps(3000 * 1024) <> 3750 * 1024) or
      (EnforcedLimitBps(Int64(10) * 1024 * 1024 * 1024) <>
       Int64(10) * 1024 * 1024 * 1024) then
      raise Exception.Create('25% headroom calculation failed');
    CheckDialog(0, 0, True);
    CheckDialog(12345, 20000 * 1024, False);
    WriteLn('Speed dialog behavior and compact layout checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Speed dialog failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
