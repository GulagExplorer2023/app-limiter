program block_button_smoke;

{$mode objfpc}{$H+}
{$R ..\panel\app_limiter.res}

uses
  SysUtils, Interfaces, Forms, StdCtrls, ComCtrls,
  mainform, limiter_data;

procedure Check(Value: Boolean; const Why: string);
begin
  if not Value then raise Exception.Create(Why);
end;

var
  Settings, Loaded: TSettings;
  Rules, LoadedRules: TRules;
  Form: TMainForm;
  List: TListView;
  Button: TButton;
  ErrorText: string;
  I: Integer;
begin
  try
    Settings := DefaultSettings;
    SetLength(Rules, 1);
    Rules[0].Path := 'C:\Windows\System32\curl.exe';
    Rules[0].Enabled := True;
    Rules[0].DownloadBps := 1024;
    Rules[0].UploadBps := 2048;
    Check(SaveConfig(ConfigPath, Settings, Rules, ErrorText), ErrorText);
    Application.Scaled := True;
    Application.Initialize;
    Form := TMainForm.Create(nil);
    try
      List := nil;
      Button := nil;
      for I := 0 to Form.ComponentCount - 1 do
      begin
        if Form.Components[I] is TListView then
          List := TListView(Form.Components[I]);
        if (Form.Components[I] is TButton) and
          (TButton(Form.Components[I]).Caption = 'Block internet') then
          Button := TButton(Form.Components[I]);
      end;
      Check((List <> nil) and (List.Items.Count > 0), 'Pinned app row missing');
      Check(Button <> nil, 'Block internet button missing');
      List.Items[0].Selected := True;
      Button.Click;
      Check(LoadConfig(ConfigPath, Loaded, LoadedRules, ErrorText), ErrorText);
      Check((Length(LoadedRules) = 1) and LoadedRules[0].Blocked,
        'Block button did not save rule');
      Check((LoadedRules[0].DownloadBps = 1024) and
        (LoadedRules[0].UploadBps = 2048), 'Block erased speed limits');
      Check(Button.Caption = 'Unblock internet',
        'Block button did not change to Unblock');
      Button.Click;
      Check(LoadConfig(ConfigPath, Loaded, LoadedRules, ErrorText), ErrorText);
      Check(not LoadedRules[0].Blocked, 'Unblock button did not save rule');
    finally
      Form.Free;
    end;
    WriteLn('Block/unblock button and speed preservation checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Block button smoke failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
