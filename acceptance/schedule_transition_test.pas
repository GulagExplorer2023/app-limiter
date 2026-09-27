program schedule_transition_test;

{$mode objfpc}{$H+}

uses
  SysUtils, DateUtils, limiter_data, limiter_engine;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

var
  ConfigFile, ErrorText: string;
  Settings: TSettings;
  Rules: TRules;
  Engine: TLimiterEngine;
  TodayBit: Integer;
begin
  ConfigFile := ChangeFileExt(ParamStr(0), '.config.json');
  Settings := DefaultSettings;
  SetLength(Rules, 1);
  Rules[0].Path := ExpandFileName(ParamStr(0));
  Rules[0].DownloadBps := 1024;
  Rules[0].Enabled := True;
  Rules[0].ScheduleEnabled := True;
  Rules[0].ScheduleDays := 127;
  Rules[0].QuotaPeriod := 'monthly';
  Check(SaveConfig(ConfigFile, Settings, Rules, ErrorText), ErrorText);
  Engine := TLimiterEngine.Create(ConfigFile, ConfigFile + '.state');
  try
    Engine.LoadRules;
    Check(Engine.FActiveLimits, 'Full-day scheduled limit should be active');
    // Simulate the cached mode from the preceding schedule period. The
    // configuration file does not change when a schedule boundary passes.
    Engine.FActiveLimits := False;
    Engine.LoadRules;
    Check(Engine.FActiveLimits, 'Unchanged configuration did not activate');
    TodayBit := (DayOfWeek(Now) + 5) mod 7;
    Rules[0].ScheduleDays := 127 xor (1 shl TodayBit);
    Check(SaveConfig(ConfigFile, Settings, Rules, ErrorText), ErrorText);
    Engine.LoadRules;
    Check(not Engine.FActiveLimits, 'Inactive schedule should disable limit');
    Engine.FActiveLimits := True;
    Engine.LoadRules;
    Check(not Engine.FActiveLimits, 'Unchanged configuration did not disable');
  finally
    Engine.Free;
    DeleteFile(ConfigFile);
  end;
  WriteLn('Schedule mode transition checks passed.');
end.
