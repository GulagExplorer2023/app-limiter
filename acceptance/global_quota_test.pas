program global_quota_test;

{$mode objfpc}{$H+}

uses
  SysUtils, Windows, limiter_data, limiter_engine, windivert_api;

procedure Check(Value: Boolean; const Why: string);
begin
  if not Value then raise Exception.Create(Why);
end;

procedure Set16(var Packet: array of Byte; Offset, Value: Integer);
begin
  Packet[Offset] := (Value shr 8) and $ff;
  Packet[Offset + 1] := Value and $ff;
end;

var
  Settings, Loaded: TSettings;
  Rules, LoadedRules: TRules;
  Engine, Restored: TLimiterEngine;
  Address: TDivertAddress;
  Packet: array[0..27] of Byte;
  ConfigFile, ErrorText: string;
  Hour, Minute, Second, MilliSecond: Word;
  CurrentMinute: Integer;
  FirstProcess, SecondProcess, ThirdProcess: THandle;
begin
  try
    if ParamCount <> 1 then raise Exception.Create('Pass a test config path');
    ConfigFile := ParamStr(1);
    Settings := DefaultSettings;
    Settings.Paused := True;
    Settings.GlobalRule.Enabled := True;
    Settings.GlobalRule.QuotaBytes := 100;
    Settings.GlobalRule.QuotaPeriod := 'daily';
    Settings.GlobalRule.BlockAfterQuota := True;
    SetLength(Rules, 0);
    Check(SaveConfig(ConfigFile, Settings, Rules, ErrorText), ErrorText);
    Check(LoadConfig(ConfigFile, Loaded, LoadedRules, ErrorText), ErrorText);
    Check(Loaded.GlobalRule.BlockAfterQuota and
      (Loaded.GlobalRule.QuotaBytes = 100),
      'Computer-wide quota did not round-trip');
    Engine := TLimiterEngine.Create(ConfigFile, ConfigFile + '.state');
    try
      Engine.FSettings := Loaded;
      Engine.UpdateGlobalQuota;
      Check(Engine.HasActiveLimits,
        'Computer-wide block did not keep interception active while paused');
      FillChar(Packet, SizeOf(Packet), 0);
      Packet[0] := $45;
      Set16(Packet, 2, SizeOf(Packet));
      Packet[8] := 64;
      Packet[9] := 17;
      Packet[12] := 10; Packet[13] := 1;
      Packet[14] := 1; Packet[15] := 1;
      Packet[16] := 8; Packet[17] := 8;
      Packet[18] := 8; Packet[19] := 8;
      Set16(Packet, 20, 54321);
      Set16(Packet, 22, 443);
      Set16(Packet, 24, 8);
      FillChar(Address, SizeOf(Address), 0);
      Address.Flags := 1 shl 17;
      Engine.ProcessPacket(Address, @Packet[0], SizeOf(Packet), False, 0);
      Check((Engine.FGlobalSessionUp = SizeOf(Packet)) and
        (Engine.FGlobalQuotaUsed = SizeOf(Packet)) and
        (Length(Engine.FUsageDays) = 1),
        'Unattributed upload was omitted from computer-wide usage');
      Engine.WriteHistory(True);
      Restored := TLimiterEngine.Create(ConfigFile, ConfigFile + '.state');
      try
        Restored.FSettings := Loaded;
        Restored.LoadHistory;
        Restored.UpdateGlobalQuota;
        Check(Restored.FGlobalQuotaUsed = SizeOf(Packet),
          'Computer-wide quota history was not restored');
      finally
        Restored.Free;
      end;
      Packet[16] := 192; Packet[17] := 168;
      Packet[18] := 1; Packet[19] := 1;
      Engine.ProcessPacket(Address, @Packet[0], SizeOf(Packet), False, 0);
      Check((Engine.FGlobalSessionUp = SizeOf(Packet)) and
        (Engine.FGlobalQuotaUsed = SizeOf(Packet)),
        'Local-network traffic was counted toward the computer-wide quota');
      Packet[16] := 8; Packet[17] := 8;
      Packet[18] := 8; Packet[19] := 8;
      Engine.FGlobalQuotaUsed := 100;
      Engine.ProcessPacket(Address, @Packet[0], SizeOf(Packet), True, 0);
      Check((Engine.FDroppedPackets = 1) and
        (Engine.FGlobalSessionUp = SizeOf(Packet)),
        'Computer-wide quota did not block unattributed upload');
      Packet[12] := 8; Packet[13] := 8;
      Packet[14] := 8; Packet[15] := 8;
      Packet[16] := 10; Packet[17] := 1;
      Packet[18] := 1; Packet[19] := 1;
      Set16(Packet, 20, 443);
      Set16(Packet, 22, 54321);
      Address.Flags := 0;
      Engine.ProcessPacket(Address, @Packet[0], SizeOf(Packet), True, 0);
      Check((Engine.FDroppedPackets = 2) and
        (Engine.FGlobalSessionDown = 0),
        'Computer-wide quota did not block unattributed download');
      Engine.FSettings.GlobalRule.BlockAfterQuota := False;
      Engine.FSettings.GlobalRule.QuotaBytes := 0;
      Engine.FSettings.GlobalRule.ScheduleEnabled := True;
      Engine.FSettings.GlobalRule.BlockOutsideSchedule := True;
      DecodeTime(Now, Hour, Minute, Second, MilliSecond);
      CurrentMinute := Hour * 60 + Minute;
      Engine.FSettings.GlobalRule.ScheduleStartMin :=
        (CurrentMinute + 1) mod 1440;
      Engine.FSettings.GlobalRule.ScheduleEndMin :=
        (CurrentMinute + 2) mod 1440;
      Engine.ProcessPacket(Address, @Packet[0], SizeOf(Packet), True, 0);
      Check(Engine.FDroppedPackets = 3,
        'Computer-wide schedule did not block outside hours');
      Engine.FSettings.GlobalRule.ScheduleEnabled := False;
      Engine.FSettings.GlobalRule.BlockOutsideSchedule := False;
      Engine.FSettings.GlobalRule.QuotaBytes := 100;
      Engine.FSettings.GlobalRule.QuotaSlowBps := 1024;
      Engine.FSettings.Paused := False;
      Check(Engine.GlobalEffectiveRate = 1024,
        'Computer-wide quota did not select slower speed');
      Check(not Engine.QueuePacket(-1, -1, 1, 0, 1024,
        tsPublic, Address, @Packet[0], SizeOf(Packet), 0) and
        (Engine.FGlobalDueUs[1] > 0),
        'Computer-wide throttle did not pace an unattributed packet');
      FirstProcess := CreateEvent(nil, True, False, nil);
      SecondProcess := CreateEvent(nil, True, False, nil);
      ThirdProcess := CreateEvent(nil, True, False, nil);
      Check((FirstProcess <> 0) and (SecondProcess <> 0) and
        (ThirdProcess <> 0), 'Could not create process lifetime probes');
      SetLength(Engine.FApps, 1);
      Engine.FApps[0].DownloadBytes := 123;
      Engine.RecordAppProcess(0, 111, FirstProcess);
      Check(Engine.FApps[0].DownloadBytes = 0,
        'First observed process did not start a new usage total');
      Engine.FApps[0].DownloadBytes := 456;
      Engine.RecordAppProcess(0, 222, SecondProcess);
      Check(Engine.FApps[0].DownloadBytes = 456,
        'Concurrent processes did not share the running total');
      SetEvent(FirstProcess);
      SetEvent(SecondProcess);
      Engine.RecordAppProcess(0, 333, ThirdProcess);
      Check(Engine.FApps[0].DownloadBytes = 0,
        'Relaunched program did not reset its running total');
      CloseHandle(ThirdProcess);
      SetLength(Engine.FAppProcesses, 0);
    finally
      Engine.Free;
    end;
    WriteLn('Computer-wide block/throttle, usage history, and program-session checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Computer-wide quota failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
