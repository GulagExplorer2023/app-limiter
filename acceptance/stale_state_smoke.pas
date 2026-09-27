program stale_state_smoke;

{$mode objfpc}{$H+}
{$R ..\panel\app_limiter.res}

uses
  SysUtils, Classes, Interfaces, Forms, Controls, StdCtrls, ComCtrls,
  ExtCtrls, fpjson, limiter_data, mainform;

procedure Check(Value: Boolean; const Why: string);
begin
  if not Value then raise Exception.Create(Why);
end;

var
  Settings: TSettings;
  Rules: TRules;
  ErrorText: string;
  Root, App: TJSONObject;
  Apps: TJSONArray;
  Text: TStringList;
  Form: TMainForm;
  List: TListView;
  Timer: TTimer;
  LabelControl: TLabel;
  Tick: TNotifyEvent;
  I: Integer;
  StaleLabelFound: Boolean;
begin
  try
    Settings := DefaultSettings;
    SetLength(Rules, 0);
    Check(SaveConfig(ConfigPath, Settings, Rules, ErrorText), ErrorText);
    Root := TJSONObject.Create;
    Text := TStringList.Create;
    try
      Apps := TJSONArray.Create;
      Root.Add('apps', Apps);
      App := TJSONObject.Create;
      App.Add('path', 'C:\Program Files\Example\example.exe');
      App.Add('downloadBps', Int64(2048));
      App.Add('uploadBps', Int64(1024));
      App.Add('downloadBytes', Int64(123456));
      App.Add('uploadBytes', Int64(654321));
      App.Add('quotaUsedBytes', Int64(0));
      Apps.Add(App);
      Root.Add('status', 'Monitoring');
      Root.Add('globalQuotaUsedBytes', Int64(0));
      ForceDirectories(ExtractFileDir(StatePath));
      Text.Text := Root.AsJSON;
      Text.SaveToFile(StatePath);
    finally
      Text.Free;
      Root.Free;
    end;
    Application.Scaled := True;
    Application.Initialize;
    Form := TMainForm.Create(nil);
    try
      List := nil;
      Timer := nil;
      for I := 0 to Form.ComponentCount - 1 do
      begin
        if Form.Components[I] is TListView then
          List := TListView(Form.Components[I]);
        if Form.Components[I] is TTimer then
          Timer := TTimer(Form.Components[I]);
      end;
      Check((List <> nil) and (List.Items.Count = 1) and (Timer <> nil),
        'Fresh backend state did not populate the app list');
      Check(FileSetDate(StatePath,
        DateTimeToFileDate(Now - 1 / 1440)) = 0,
        'Could not age the test state file');
      Tick := Timer.OnTimer;
      Tick(Timer);
      Check(List.Items.Count = 1,
        'Temporary backend staleness erased the last-known app list');
      Check((List.Items[0].SubItems[0] = '—') and
        (List.Items[0].SubItems[1] = '—'),
        'Stale transfer rates still looked live');
      StaleLabelFound := False;
      for I := 0 to Form.ComponentCount - 1 do
        if Form.Components[I] is TLabel then
        begin
          LabelControl := TLabel(Form.Components[I]);
          if Pos('enforcement status unknown', LabelControl.Caption) > 0 then
            StaleLabelFound := True;
        end;
      Check(StaleLabelFound, 'Stale state did not disclose uncertainty');
    finally
      Form.Free;
    end;
    WriteLn('Stale backend state retained last-known usage with an honest status.');
  except
    on E: Exception do
    begin
      WriteLn('Stale state UI failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
