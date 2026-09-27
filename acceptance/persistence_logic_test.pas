program persistence_logic_test;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, limiter_data, limiter_engine;

procedure Check(Condition: Boolean; const Why: string);
begin
  if not Condition then raise Exception.Create(Why);
end;

var
  ConfigFile, ErrorText, Day: string;
  Settings: TSettings;
  Rules: TRules;
  Engine: TLimiterEngine;
  History: TStringList;
begin
  try
    if ParamCount <> 1 then raise Exception.Create('Pass a test config path');
    ConfigFile := ParamStr(1);
    Settings := DefaultSettings;
    Settings.Paused := True;
    SetLength(Rules, 1);
    Rules[0].Path := 'C:\Windows\System32\curl.exe';
    Rules[0].Enabled := True;
    Rules[0].Blocked := True;
    Rules[0].QuotaBytes := 1000;
    Rules[0].QuotaSlowBps := 100;
    Check(SaveConfig(ConfigFile, Settings, Rules, ErrorText), ErrorText);

    SetLength(Rules, 2);
    Rules[1] := Rules[0];
    Rules[1].Path := 'C:\WINDOWS\SYSTEM32\CURL.EXE';
    Check(not SaveConfig(ConfigFile, Settings, Rules, ErrorText),
      'Duplicate Windows paths were saved');
    Check(ErrorText = 'Duplicate executable path',
      'Unexpected duplicate-path error');
    SetLength(Rules, 1);
    Settings.Hotkey := 'invalid';
    Check(not SaveConfig(ConfigFile, Settings, Rules, ErrorText),
      'Invalid shortcut was saved');
    Settings := DefaultSettings;
    Settings.Paused := True;

    Engine := TLimiterEngine.Create(ConfigFile, ConfigFile + '.state');
    try
      Day := FormatDateTime('yyyy-mm-dd', Date);
      History := TStringList.Create;
      try
        History.Text := '{"days":[{"path":"C:\\Windows\\System32\\curl.exe",' +
          '"day":"' + Day + '","downloadBytes":-1,"uploadBytes":-2}],' +
          '"destinations":[]}';
        History.SaveToFile(Engine.FHistoryPath);
      finally
        History.Free;
      end;
      Engine.LoadHistory;
      Check(Length(Engine.FUsageDays) = 1, 'History entry did not load');
      Check((Engine.FUsageDays[0].DownloadBytes = 0) and
        (Engine.FUsageDays[0].UploadBytes = 0),
        'Negative history counters wrapped around');
      Engine.LoadRules;
      Check((Length(Engine.FRules) = 1) and Engine.FRules[0].Blocked,
        'Saved block did not load');
      Check(Engine.FActiveLimits,
        'Saved block did not select the active network mode');
      Check(Engine.FindApp(Rules[0].Path) = 0, 'App did not register');
      Check(Engine.FApps[0].QuotaUsed = 0,
        'Damaged history falsely exhausted the quota');
      SetLength(Engine.FUsageDays, 2);
      Engine.FUsageDays[0].DownloadBytes := High(Int64);
      Engine.FUsageDays[0].UploadBytes := High(Int64);
      Engine.FUsageDays[1] := Engine.FUsageDays[0];
      Engine.FApps[0].QuotaKey := '';
      Engine.UpdateQuota(0);
      Check(Engine.FApps[0].QuotaUsed = QWord(High(Int64)),
        'Large history counters wrapped below the quota');
      // A failed worker creation can leave only some threads initialized.
      Engine.FRunning := True;
      Engine.Stop;
      Check(not Engine.FRunning, 'Partial startup did not stop cleanly');
    finally
      Engine.Free;
    end;
    WriteLn('Persistence and startup rule checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Persistence logic failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
