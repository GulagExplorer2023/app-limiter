program service_stability_test;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Windows, fpjson, jsonparser, limiter_data,
  limiter_engine;

procedure Check(Value: Boolean; const Why: string);
begin
  if not Value then raise Exception.Create(Why);
end;

function StartStamp(Handle: THandle): QWord;
var
  CreatedAt, ExitedAt, KernelTime, UserTime: TFileTime;
begin
  Result := 0;
  if GetProcessTimes(Handle, CreatedAt, ExitedAt, KernelTime,
    UserTime) then
    Result := (QWord(CreatedAt.dwHighDateTime) shl 32) or
      CreatedAt.dwLowDateTime;
end;

var
  Settings: TSettings;
  Rules: TRules;
  Engine, Restored, Rejected, Eviction: TLimiterEngine;
  ConfigFile, StateFile, ErrorText, Path: string;
  AppIndex, I, VictimIndex: Integer;
  ProcessHandle: THandle;
  Reader: TFileStream;
  LockedFailure: Boolean;
  Text: TStringList;
  Root: TJSONData;
  Sessions, Processes: TJSONArray;
  ProcessItem: TJSONObject;
  Stamp: Int64;
begin
  try
    if ParamCount <> 1 then raise Exception.Create('Pass a test directory');
    ForceDirectories(ParamStr(1));
    ConfigFile := IncludeTrailingPathDelimiter(ParamStr(1)) + 'config.json';
    StateFile := IncludeTrailingPathDelimiter(ParamStr(1)) + 'state.json';
    Settings := DefaultSettings;
    SetLength(Rules, 0);
    Check(SaveConfig(ConfigFile, Settings, Rules, ErrorText), ErrorText);
    Engine := TLimiterEngine.Create(ConfigFile, StateFile);
    try
      Engine.LoadRules;
      Path := ExpandFileName(ParamStr(0));
      Check(Path <> '', 'Test executable path could not be read');
      AppIndex := Engine.FindApp(Path);
      ProcessHandle := OpenProcess($00101000, False,
        GetCurrentProcessId);
      Check(ProcessHandle <> 0, 'Test process handle could not be opened');
      Check(StartStamp(ProcessHandle) <> 0,
        'Test process start time could not be read');
      Engine.RecordAppProcess(AppIndex, GetCurrentProcessId,
        ProcessHandle);
      Engine.FApps[AppIndex].DownloadBytes := 123456789;
      Engine.FApps[AppIndex].UploadBytes := 9876543;
      Engine.FApps[AppIndex].LastPacketMs := GetTickCount64;
      Engine.WriteState;
      Restored := TLimiterEngine.Create(ConfigFile, StateFile);
      try
        Restored.LoadRules;
        Restored.LoadSessionCheckpoint;
        Check((Length(Restored.FAppProcesses) = 1) and
          (Length(Restored.FApps) = 1) and
          (Restored.FApps[0].DownloadBytes = 123456789) and
          (Restored.FApps[0].UploadBytes = 9876543),
          'Running-program totals did not survive backend restart');
      finally
        Restored.Free;
      end;
      Reader := TFileStream.Create(StateFile,
        fmOpenRead or fmShareDenyNone);
      try
        LockedFailure := False;
        try
          Engine.WriteState;
        except
          on E: Exception do LockedFailure := True;
        end;
      finally
        Reader.Free;
      end;
      Check(LockedFailure,
        'Locked state file did not exercise publication retry');
      Engine.WriteState;
      Text := TStringList.Create;
      Root := nil;
      try
        Text.LoadFromFile(StateFile);
        Root := GetJSON(Text.Text);
        Sessions := TJSONArray(TJSONObject(Root).Find('sessions'));
        Check((Sessions <> nil) and (Sessions.Count = 1),
          'Session checkpoint missing from recovered state file');
        Processes := TJSONArray(TJSONObject(Sessions[0]).Find('processes'));
        ProcessItem := TJSONObject(Processes[0]);
        Stamp := ProcessItem.Get('startTime', Int64(0));
        ProcessItem.Delete('startTime');
        ProcessItem.Add('startTime', Stamp + 1);
        Text.Text := Root.AsJSON;
        Text.SaveToFile(StateFile);
      finally
        Root.Free;
        Text.Free;
      end;
      Rejected := TLimiterEngine.Create(ConfigFile, StateFile);
      try
        Rejected.LoadRules;
        Rejected.LoadSessionCheckpoint;
        Check(Length(Rejected.FAppProcesses) = 0,
          'Stale process identity restored the wrong program run');
      finally
        Rejected.Free;
      end;
      for I := 1 to 5000 do Engine.WriteState;
    finally
      Engine.Free;
    end;
    Eviction := TLimiterEngine.Create(ConfigFile, StateFile);
    try
      SetLength(Eviction.FApps, 1024);
      for I := 0 to High(Eviction.FApps) do
        Eviction.FApps[I].Path := 'C:\stale\app' + IntToStr(I) + '.exe';
      SetLength(Eviction.FDestinations, 1);
      Eviction.FDestinations[0].AppIndex := 0;
      Eviction.FDestinations[0].Name := 'stale.example';
      VictimIndex := Eviction.FindApp('C:\fresh.exe');
      Check((VictimIndex = 0) and
        (Eviction.FApps[0].Path = 'C:\fresh.exe') and
        (Eviction.FDestinations[0].AppIndex = -1),
        'Long-running app cache did not recycle an inactive slot');
      Eviction.WriteDestinations;
      SetLength(Eviction.FDestinations, 16384);
      for I := 0 to High(Eviction.FDestinations) do
      begin
        Eviction.FDestinations[I].AppIndex := 1;
        Eviction.FDestinations[I].LastSeenMs := I;
      end;
      VictimIndex := Eviction.RecordDestination(0, 'fresh.example',
        '8.8.8.8', 'IP', 443, 6);
      Check((VictimIndex = 0) and
        (Eviction.FDestinations[0].Name = 'fresh.example'),
        'Full destination cache did not recycle an unreferenced entry');
      SetLength(Eviction.FUsageDays, 2);
      Eviction.FUsageDays[0].Day := FormatDateTime('yyyy-mm-dd', Date - 100);
      Eviction.FUsageDays[1].Day := FormatDateTime('yyyy-mm-dd', Date);
      SetLength(Eviction.FUsageDestinations, 2);
      Eviction.FUsageDestinations[0].Day :=
        FormatDateTime('yyyy-mm-dd', Date - 100);
      Eviction.FUsageDestinations[1].Day :=
        FormatDateTime('yyyy-mm-dd', Date);
      Eviction.PruneHistory;
      Check((Length(Eviction.FUsageDays) = 1) and
        (Length(Eviction.FUsageDestinations) = 1) and
        (Eviction.FUsageDays[0].Day = FormatDateTime('yyyy-mm-dd', Date)),
        'Old usage history was not pruned during uninterrupted operation');
    finally
      Eviction.Free;
    end;
    WriteLn('Backend checkpoint, locked-file recovery, and publication checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Backend stability failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
