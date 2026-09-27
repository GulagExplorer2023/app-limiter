unit limiter_data;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TRule = record
    Path: string;                 // UTF-8, absolute executable path
    DownloadBps: Int64;          // 0 means unlimited
    UploadBps: Int64;            // 0 means unlimited
    Enabled: Boolean;
    Blocked: Boolean;            // drop both upload and download packets
    ScheduleEnabled: Boolean;
    BlockOutsideSchedule: Boolean;
    ScheduleStartMin, ScheduleEndMin: Integer;
    ScheduleDays: Integer;       // bit 0 = Monday, bit 6 = Sunday
    QuotaBytes: Int64;           // 0 disables the quota
    QuotaPeriod: string;         // daily or monthly
    QuotaSlowBps: Int64;         // both directions after quota
    BlockAfterQuota: Boolean;
  end;
  TRules = array of TRule;

  TSettings = record
    Paused: Boolean;
    StartMinimized: Boolean;
    ParentalMode: Boolean;
    PinVerifier: string;
    DarkTheme: Boolean;
    Hotkey: string;
    GlobalRule: TRule;
  end;

function UserDataDir: string;
function ConfigPath: string;
function StatePath: string;
function DestinationsPath: string;
function HistoryPath: string;
function ScheduleActive(const Rule: TRule; AtTime: TDateTime): Boolean;
function DefaultSettings: TSettings;
function LoadConfig(const FileName: string; out Settings: TSettings;
  out Rules: TRules; out ErrorText: string): Boolean;
function SaveConfig(const FileName: string; const Settings: TSettings;
  const Rules: TRules; out ErrorText: string): Boolean;
function IsValidRule(const Rule: TRule; out ErrorText: string): Boolean;
function IsValidGlobalRule(const Rule: TRule; out ErrorText: string): Boolean;
function SameWindowsPath(const A, B: string): Boolean;
function RuleBlocksTraffic(const Rule: TRule): Boolean;
function RuleBlocksTrafficAt(const Rule: TRule; AtTime: TDateTime;
  QuotaUsed: QWord): Boolean;
function EnforcedLimitBps(ConfiguredBps: Int64): Int64;

implementation

uses
  Windows, DateUtils, fpjson, jsonparser, parental_pin;

const
  MaxRules = 256;
  MaxRateBps = Int64(10) * 1024 * 1024 * 1024;
  MoveFileWriteThrough = 8;

function CompareStringOrdinal(String1: PWideChar; Count1: LongInt;
  String2: PWideChar; Count2: LongInt; IgnoreCase: BOOL): LongInt; stdcall;
  external 'kernel32.dll';

function SameWindowsPath(const A, B: string): Boolean;
var
  WA, WB: UnicodeString;
begin
  WA := UnicodeString(UTF8Decode(A));
  WB := UnicodeString(UTF8Decode(B));
  Result := CompareStringOrdinal(PWideChar(WA), Length(WA),
    PWideChar(WB), Length(WB), BOOL(1)) = 2;
end;

function ValidHotkey(const Hotkey: string): Boolean;
begin
  Result := (Length(Hotkey) = 10) and
    (CompareText(Copy(Hotkey, 1, 9), 'Ctrl+Alt+') = 0) and
    (UpCase(Hotkey[10]) in ['A'..'Z']);
end;

function EnforcedLimitBps(ConfiguredBps: Int64): Int64;
begin
  if ConfiguredBps <= 0 then Exit(0);
  // The slider is intentionally generous: 3,000 KiB/s allows 3,750 KiB/s
  // on the wire, which is about 30 Mbps of speed-test payload.
  if ConfiguredBps >= (MaxRateBps * 4) div 5 then Exit(MaxRateBps);
  Result := (ConfiguredBps * 5 + 3) div 4;
end;

function RuleBlocksTraffic(const Rule: TRule): Boolean;
begin
  Result := Rule.Enabled and Rule.Blocked;
end;

function RuleBlocksTrafficAt(const Rule: TRule; AtTime: TDateTime;
  QuotaUsed: QWord): Boolean;
begin
  Result := Rule.Enabled and
    (Rule.Blocked or
     (Rule.ScheduleEnabled and Rule.BlockOutsideSchedule and
      not ScheduleActive(Rule, AtTime)) or
     (Rule.BlockAfterQuota and (Rule.QuotaBytes > 0) and
      (QuotaUsed >= QWord(Rule.QuotaBytes))));
end;

function UserDataDir: string;
begin
  Result := IncludeTrailingPathDelimiter(
    SysUtils.GetEnvironmentVariable('PROGRAMDATA')) +
    'AppLimiter' + PathDelim + 'Users' + PathDelim +
    SysUtils.GetEnvironmentVariable('USERNAME');
end;

function ConfigPath: string;
begin
  Result := IncludeTrailingPathDelimiter(UserDataDir) + 'config.json';
end;

function StatePath: string;
begin
  Result := IncludeTrailingPathDelimiter(
    SysUtils.GetEnvironmentVariable('PROGRAMDATA')) +
    'AppLimiter' + PathDelim + 'state.json';
end;

function DestinationsPath: string;
begin
  Result := IncludeTrailingPathDelimiter(UserDataDir) +
    'destinations.json';
end;

function HistoryPath: string;
begin
  Result := IncludeTrailingPathDelimiter(UserDataDir) + 'usage_history.json';
end;

function ScheduleActive(const Rule: TRule; AtTime: TDateTime): Boolean;
var
  MinuteOfDay, DayBit: Integer;
  PreviousDay: TDateTime;
  Hour, Minute, Second, MilliSecond: Word;
begin
  if not Rule.ScheduleEnabled then Exit(True);
  DecodeTime(AtTime, Hour, Minute, Second, MilliSecond);
  MinuteOfDay := Hour * 60 + Minute;
  DayBit := (DayOfWeek(AtTime) + 5) mod 7;
  if Rule.ScheduleStartMin = Rule.ScheduleEndMin then
    Exit((Rule.ScheduleDays and (1 shl DayBit)) <> 0);
  if Rule.ScheduleStartMin < Rule.ScheduleEndMin then
    Exit((MinuteOfDay >= Rule.ScheduleStartMin) and
      (MinuteOfDay < Rule.ScheduleEndMin) and
      ((Rule.ScheduleDays and (1 shl DayBit)) <> 0));
  if MinuteOfDay >= Rule.ScheduleStartMin then
    Exit((Rule.ScheduleDays and (1 shl DayBit)) <> 0);
  PreviousDay := AtTime - 1;
  DayBit := (DayOfWeek(PreviousDay) + 5) mod 7;
  Result := (MinuteOfDay < Rule.ScheduleEndMin) and
    ((Rule.ScheduleDays and (1 shl DayBit)) <> 0);
end;

function DefaultSettings: TSettings;
begin
  Result.Paused := False;
  Result.StartMinimized := False;
  Result.ParentalMode := False;
  Result.PinVerifier := '';
  Result.DarkTheme := True;
  Result.Hotkey := 'Ctrl+Alt+N';
  Result.GlobalRule := Default(TRule);
  Result.GlobalRule.ScheduleDays := 127;
  Result.GlobalRule.QuotaPeriod := 'monthly';
end;

function ValidateRule(const Rule: TRule; RequirePath: Boolean;
  out ErrorText: string): Boolean;
var
  P: string;
begin
  ErrorText := '';
  P := Rule.Path;
  if RequirePath and ((Length(P) < 4) or (Length(P) > 32767) or
    (ExtractFileDrive(P) = '') or (Pos('*', P) <> 0) or
    (Pos('?', P) <> 0) or (CompareText(ExtractFileExt(P), '.exe') <> 0) or
    (ExpandFileName(P) <> P)) then
    ErrorText := 'Rule path must be a normalized, absolute .exe path';
  if (Rule.DownloadBps < 0) or (Rule.DownloadBps > MaxRateBps) or
    (Rule.UploadBps < 0) or (Rule.UploadBps > MaxRateBps) then
    ErrorText := 'Rate must be between Unlimited and 10 GiB/s';
  if Rule.ScheduleEnabled and
    ((Rule.ScheduleStartMin < 0) or (Rule.ScheduleStartMin > 1439) or
    (Rule.ScheduleEndMin < 0) or (Rule.ScheduleEndMin > 1439) or
    (Rule.ScheduleDays < 1) or (Rule.ScheduleDays > 127)) then
    ErrorText := 'Invalid weekly schedule';
  if Rule.BlockOutsideSchedule and not Rule.ScheduleEnabled then
    ErrorText := 'Scheduled blocking requires an enabled schedule';
  if (Rule.QuotaBytes < 0) or (Rule.QuotaBytes > Int64(1000) * 1024 * 1024 * 1024) or
    ((Rule.QuotaPeriod <> '') and (Rule.QuotaPeriod <> 'daily') and
      (Rule.QuotaPeriod <> 'monthly')) or
    (Rule.QuotaSlowBps < 0) or (Rule.QuotaSlowBps > MaxRateBps) or
    ((Rule.QuotaBytes > 0) and not Rule.BlockAfterQuota and
      (Rule.QuotaSlowBps = 0)) or
    (Rule.BlockAfterQuota and (Rule.QuotaBytes = 0)) then
    ErrorText := 'Invalid quota or post-quota speed';
  Result := ErrorText = '';
end;

function IsValidRule(const Rule: TRule; out ErrorText: string): Boolean;
begin
  Result := ValidateRule(Rule, True, ErrorText);
end;

function IsValidGlobalRule(const Rule: TRule; out ErrorText: string): Boolean;
begin
  Result := ValidateRule(Rule, False, ErrorText);
end;

function LoadConfig(const FileName: string; out Settings: TSettings;
  out Rules: TRules; out ErrorText: string): Boolean;
var
  Text: TStringList;
  Stream: TFileStream;
  Root, Item: TJSONData;
  ObjectRoot, ObjectItem: TJSONObject;
  ArrayRules: TJSONArray;
  I, J: Integer;
  RuleError: string;
begin
  Settings := DefaultSettings;
  SetLength(Rules, 0);
  ErrorText := '';
  if not FileExists(FileName) then Exit(True);
  Result := False;
  Text := TStringList.Create;
  Root := nil;
  Stream := nil;
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    if Stream.Size > 1024 * 1024 then
      raise Exception.Create('Configuration exceeds 1 MiB');
    Text.LoadFromStream(Stream);
    Root := GetJSON(Text.Text);
    if Root.JSONType <> jtObject then
      raise Exception.Create('Configuration root must be an object');
    ObjectRoot := TJSONObject(Root);
    if ObjectRoot.Get('version', 0) <> 1 then
      raise Exception.Create('Unsupported configuration version');
    Settings.Paused := ObjectRoot.Get('paused', False);
    Settings.StartMinimized := ObjectRoot.Get('startMinimized', False);
    Settings.ParentalMode := ObjectRoot.Get('parentalMode', False);
    Settings.PinVerifier := ObjectRoot.Get('pinVerifier', '');
    // Older configurations could enable parental mode without a PIN. Keep
    // the panel reachable until the owner enables the protected mode.
    if Settings.ParentalMode and
      not ValidPinVerifier(Settings.PinVerifier) then
      Settings.ParentalMode := False;
    Settings.DarkTheme := ObjectRoot.Get('darkTheme', True);
    Settings.Hotkey := ObjectRoot.Get('hotkey', 'Ctrl+Alt+N');
    if not ValidHotkey(Settings.Hotkey) then
      raise Exception.Create('Hotkey must be Ctrl+Alt+letter');
    Item := ObjectRoot.Find('rules');
    if (Item = nil) or (Item.JSONType <> jtArray) then
      raise Exception.Create('Rules must be an array');
    ArrayRules := TJSONArray(Item);
    if ArrayRules.Count > MaxRules then
      raise Exception.Create('Too many rules');
    SetLength(Rules, ArrayRules.Count);
    for I := 0 to ArrayRules.Count - 1 do
    begin
      if ArrayRules[I].JSONType <> jtObject then
        raise Exception.CreateFmt('Rule %d must be an object', [I]);
      ObjectItem := TJSONObject(ArrayRules[I]);
      Rules[I].Path := ObjectItem.Get('path', '');
      Rules[I].DownloadBps := ObjectItem.Get('downloadBps', Int64(0));
      Rules[I].UploadBps := ObjectItem.Get('uploadBps', Int64(0));
      Rules[I].Enabled := ObjectItem.Get('enabled', True);
      Rules[I].Blocked := ObjectItem.Get('blocked', False);
      Rules[I].ScheduleEnabled := ObjectItem.Get('scheduleEnabled', False);
      Rules[I].BlockOutsideSchedule :=
        ObjectItem.Get('blockOutsideSchedule', False);
      Rules[I].ScheduleStartMin := ObjectItem.Get('scheduleStartMin', 0);
      Rules[I].ScheduleEndMin := ObjectItem.Get('scheduleEndMin', 0);
      Rules[I].ScheduleDays := ObjectItem.Get('scheduleDays', 127);
      Rules[I].QuotaBytes := ObjectItem.Get('quotaBytes', Int64(0));
      Rules[I].QuotaPeriod := ObjectItem.Get('quotaPeriod', 'monthly');
      Rules[I].QuotaSlowBps := ObjectItem.Get('quotaSlowBps', Int64(0));
      Rules[I].BlockAfterQuota := ObjectItem.Get('blockAfterQuota', False);
      if not IsValidRule(Rules[I], RuleError) then
        raise Exception.CreateFmt('Rule %d: %s', [I, RuleError]);
      for J := 0 to I - 1 do
        if SameWindowsPath(Rules[J].Path, Rules[I].Path) then
          raise Exception.Create('Duplicate executable path');
    end;
    Item := ObjectRoot.Find('globalRule');
    if Item <> nil then
    begin
      if Item.JSONType <> jtObject then
        raise Exception.Create('Computer-wide rule must be an object');
      ObjectItem := TJSONObject(Item);
      Settings.GlobalRule.Enabled := ObjectItem.Get('enabled', False);
      Settings.GlobalRule.Blocked := ObjectItem.Get('blocked', False);
      Settings.GlobalRule.ScheduleEnabled :=
        ObjectItem.Get('scheduleEnabled', False);
      Settings.GlobalRule.BlockOutsideSchedule :=
        ObjectItem.Get('blockOutsideSchedule', False);
      Settings.GlobalRule.ScheduleStartMin :=
        ObjectItem.Get('scheduleStartMin', 0);
      Settings.GlobalRule.ScheduleEndMin :=
        ObjectItem.Get('scheduleEndMin', 0);
      Settings.GlobalRule.ScheduleDays :=
        ObjectItem.Get('scheduleDays', 127);
      Settings.GlobalRule.QuotaBytes :=
        ObjectItem.Get('quotaBytes', Int64(0));
      Settings.GlobalRule.QuotaPeriod :=
        ObjectItem.Get('quotaPeriod', 'monthly');
      Settings.GlobalRule.QuotaSlowBps :=
        ObjectItem.Get('quotaSlowBps', Int64(0));
      Settings.GlobalRule.BlockAfterQuota :=
        ObjectItem.Get('blockAfterQuota', False);
      if not IsValidGlobalRule(Settings.GlobalRule, RuleError) then
        raise Exception.Create('Computer-wide rule: ' + RuleError);
    end;
    Result := True;
  except
    on E: Exception do ErrorText := E.Message;
  end;
  Stream.Free;
  Root.Free;
  Text.Free;
  if not Result then
  begin
    Settings := DefaultSettings;
    SetLength(Rules, 0);
  end;
end;

function SaveConfig(const FileName: string; const Settings: TSettings;
  const Rules: TRules; out ErrorText: string): Boolean;
var
  Root, Item: TJSONObject;
  ArrayRules: TJSONArray;
  Text: TStringList;
  TempName, RuleError: string;
  WideTemp, WideTarget: UnicodeString;
  I, J: Integer;
begin
  Result := False;
  ErrorText := '';
  if not ValidHotkey(Settings.Hotkey) then
  begin
    ErrorText := 'Hotkey must be Ctrl+Alt+letter';
    Exit;
  end;
  if Settings.ParentalMode and
    not ValidPinVerifier(Settings.PinVerifier) then
  begin
    ErrorText := 'Set a parental PIN before enabling parental mode';
    Exit;
  end;
  if not IsValidGlobalRule(Settings.GlobalRule, ErrorText) then Exit;
  if Length(Rules) > MaxRules then
  begin
    ErrorText := 'Too many rules';
    Exit;
  end;
  for I := 0 to High(Rules) do
  begin
    if not IsValidRule(Rules[I], RuleError) then
    begin
      ErrorText := RuleError;
      Exit;
    end;
    for J := 0 to I - 1 do
      if SameWindowsPath(Rules[J].Path, Rules[I].Path) then
      begin
        ErrorText := 'Duplicate executable path';
        Exit;
      end;
  end;
  Root := TJSONObject.Create;
  Text := TStringList.Create;
  try
    Root.Add('version', 1);
    Root.Add('paused', Settings.Paused);
    Root.Add('startMinimized', Settings.StartMinimized);
    Root.Add('parentalMode', Settings.ParentalMode);
    Root.Add('pinVerifier', Settings.PinVerifier);
    Root.Add('darkTheme', Settings.DarkTheme);
    Root.Add('hotkey', Settings.Hotkey);
    Item := TJSONObject.Create;
    Root.Add('globalRule', Item);
    Item.Add('enabled', Settings.GlobalRule.Enabled);
    Item.Add('blocked', Settings.GlobalRule.Blocked);
    Item.Add('scheduleEnabled', Settings.GlobalRule.ScheduleEnabled);
    Item.Add('blockOutsideSchedule',
      Settings.GlobalRule.BlockOutsideSchedule);
    Item.Add('scheduleStartMin', Settings.GlobalRule.ScheduleStartMin);
    Item.Add('scheduleEndMin', Settings.GlobalRule.ScheduleEndMin);
    Item.Add('scheduleDays', Settings.GlobalRule.ScheduleDays);
    Item.Add('quotaBytes', Settings.GlobalRule.QuotaBytes);
    Item.Add('quotaPeriod', Settings.GlobalRule.QuotaPeriod);
    Item.Add('quotaSlowBps', Settings.GlobalRule.QuotaSlowBps);
    Item.Add('blockAfterQuota', Settings.GlobalRule.BlockAfterQuota);
    ArrayRules := TJSONArray.Create;
    Root.Add('rules', ArrayRules);
    for I := 0 to High(Rules) do
    begin
      Item := TJSONObject.Create;
      Item.Add('path', Rules[I].Path);
      Item.Add('downloadBps', Rules[I].DownloadBps);
      Item.Add('uploadBps', Rules[I].UploadBps);
      Item.Add('enabled', Rules[I].Enabled);
      Item.Add('blocked', Rules[I].Blocked);
      Item.Add('scheduleEnabled', Rules[I].ScheduleEnabled);
      Item.Add('blockOutsideSchedule', Rules[I].BlockOutsideSchedule);
      Item.Add('scheduleStartMin', Rules[I].ScheduleStartMin);
      Item.Add('scheduleEndMin', Rules[I].ScheduleEndMin);
      Item.Add('scheduleDays', Rules[I].ScheduleDays);
      Item.Add('quotaBytes', Rules[I].QuotaBytes);
      Item.Add('quotaPeriod', Rules[I].QuotaPeriod);
      Item.Add('quotaSlowBps', Rules[I].QuotaSlowBps);
      Item.Add('blockAfterQuota', Rules[I].BlockAfterQuota);
      ArrayRules.Add(Item);
    end;
    ForceDirectories(ExtractFileDir(FileName));
    Text.Text := Root.FormatJSON;
    TempName := FileName + '.tmp';
    Text.SaveToFile(TempName);
    WideTemp := UnicodeString(UTF8Decode(TempName));
    WideTarget := UnicodeString(UTF8Decode(FileName));
    if not MoveFileExW(PWideChar(WideTemp), PWideChar(WideTarget),
      MOVEFILE_REPLACE_EXISTING or MoveFileWriteThrough) then
      raise Exception.Create('Cannot publish configuration');
    Result := True;
  except
    on E: Exception do ErrorText := E.Message;
  end;
  Text.Free;
  Root.Free;
end;

end.
