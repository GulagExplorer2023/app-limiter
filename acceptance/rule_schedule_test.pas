program rule_schedule_test;

{$mode objfpc}{$H+}

uses SysUtils, limiter_data;

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

var
  Rule: TRule;
  Rules, Loaded: TRules;
  Settings, LoadedSettings: TSettings;
  ErrorText, FileName: string;
begin
  Rule := Default(TRule);
  Rule.Path := 'C:\Windows\System32\curl.exe';
  Rule.Enabled := True;
  Rule.ScheduleEnabled := True;
  Rule.BlockOutsideSchedule := True;
  Rule.ScheduleStartMin := 9 * 60;
  Rule.ScheduleEndMin := 17 * 60;
  Rule.ScheduleDays := 31;
  Rule.QuotaBytes := Int64(5) * 1024 * 1024 * 1024;
  Rule.QuotaPeriod := 'monthly';
  Rule.QuotaSlowBps := 128 * 1024;
  Rule.BlockAfterQuota := True;
  Check(IsValidRule(Rule, ErrorText), ErrorText);
  Rule.ScheduleEnabled := False;
  Check(not IsValidRule(Rule, ErrorText),
    'Blocking outside a disabled schedule was accepted');
  Rule.ScheduleEnabled := True;
  Rule.QuotaBytes := 0;
  Check(not IsValidRule(Rule, ErrorText),
    'Blocking without a quota was accepted');
  Rule.QuotaBytes := Int64(5) * 1024 * 1024 * 1024;
  Rule.QuotaSlowBps := 0;
  Check(IsValidRule(Rule, ErrorText),
    'Quota blocking incorrectly requires a slow speed: ' + ErrorText);
  Check(ScheduleActive(Rule, EncodeDate(2026, 9, 28) + EncodeTime(9, 0, 0, 0)),
    'Monday start not active');
  Check(not ScheduleActive(Rule, EncodeDate(2026, 9, 28) + EncodeTime(17, 0, 0, 0)),
    'Monday end active');
  Check(not RuleBlocksTrafficAt(Rule,
    EncodeDate(2026, 9, 28) + EncodeTime(9, 0, 0, 0), 0),
    'Allowed hours were blocked before quota');
  Check(RuleBlocksTrafficAt(Rule,
    EncodeDate(2026, 9, 28) + EncodeTime(17, 0, 0, 0), 0),
    'Internet was not blocked after the allowed hours');
  Check(RuleBlocksTrafficAt(Rule,
    EncodeDate(2026, 9, 28) + EncodeTime(9, 0, 0, 0),
    QWord(Rule.QuotaBytes)), 'Used quota did not block during allowed hours');
  Check(not ScheduleActive(Rule, EncodeDate(2026, 10, 3) + EncodeTime(12, 0, 0, 0)),
    'Saturday active');
  Rule.ScheduleStartMin := 22 * 60;
  Rule.ScheduleEndMin := 6 * 60;
  Rule.ScheduleDays := 1;
  Check(ScheduleActive(Rule, EncodeDate(2026, 9, 29) + EncodeTime(2, 0, 0, 0)),
    'Overnight Tuesday morning inactive');
  Check(not ScheduleActive(Rule, EncodeDate(2026, 9, 30) + EncodeTime(2, 0, 0, 0)),
    'Overnight schedule lasted beyond Tuesday');
  SetLength(Rules, 1);
  Rules[0] := Rule;
  Settings := DefaultSettings;
  FileName := IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0))) +
    'rule_schedule_test.json';
  Check(SaveConfig(FileName, Settings, Rules, ErrorText), ErrorText);
  Check(LoadConfig(FileName, LoadedSettings, Loaded, ErrorText), ErrorText);
  Check((Length(Loaded) = 1) and
    (Loaded[0].QuotaBytes = Rule.QuotaBytes) and
    (Loaded[0].QuotaSlowBps = Rule.QuotaSlowBps) and
    Loaded[0].BlockOutsideSchedule and Loaded[0].BlockAfterQuota and
    (Loaded[0].ScheduleDays = Rule.ScheduleDays),
    'Rule round trip failed');
  DeleteFile(FileName);
  WriteLn('Schedule and quota config checks passed.');
end.
