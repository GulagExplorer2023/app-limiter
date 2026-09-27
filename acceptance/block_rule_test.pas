program block_rule_test;

{$mode objfpc}{$H+}

uses
  SysUtils, limiter_data, limiter_engine, windivert_api;

procedure Check(Value: Boolean; const Why: string);
begin
  if not Value then raise Exception.Create(Why);
end;

procedure Set16(var Packet: array of Byte; Offset, Value: Integer);
begin
  Packet[Offset] := (Value shr 8) and $ff;
  Packet[Offset + 1] := Value and $ff;
end;

procedure SetTcpDirection(var Packet: array of Byte;
  var Address: TDivertAddress; Outbound: Boolean);
begin
  if Outbound then
  begin
    Packet[12] := 10; Packet[13] := 1;
    Packet[14] := 1; Packet[15] := 1;
    Packet[16] := 8; Packet[17] := 8;
    Packet[18] := 8; Packet[19] := 8;
    Set16(Packet, 20, 54321);
    Set16(Packet, 22, 443);
    Address.Flags := 1 shl 17;
  end
  else
  begin
    Packet[12] := 8; Packet[13] := 8;
    Packet[14] := 8; Packet[15] := 8;
    Packet[16] := 10; Packet[17] := 1;
    Packet[18] := 1; Packet[19] := 1;
    Set16(Packet, 20, 443);
    Set16(Packet, 22, 54321);
    Address.Flags := 0;
  end;
end;

var
  Settings, Loaded: TSettings;
  Rules, LoadedRules: TRules;
  Engine: TLimiterEngine;
  Address: TDivertAddress;
  Packet: array[0..27] of Byte;
  TcpPacket: array[0..39] of Byte;
  Tuple: TFlowTuple;
  Slot: Integer;
  ErrorText, ConfigFile: string;
  Hour, Minute, Second, MilliSecond: Word;
  CurrentMinute: Integer;
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
    Check(SaveConfig(ConfigFile, Settings, Rules, ErrorText), ErrorText);
    Check(LoadConfig(ConfigFile, Loaded, LoadedRules, ErrorText), ErrorText);
    Check((Length(LoadedRules) = 1) and
      RuleBlocksTraffic(LoadedRules[0]), 'Block flag did not round-trip');
    Engine := TLimiterEngine.Create(ConfigFile, ConfigFile + '.state');
    try
      Engine.FSettings := Loaded;
      Engine.FRules := LoadedRules;
      Check(Engine.HasActiveLimits,
        'Blocked app did not activate packet interception while paused');
      SetLength(Engine.FApps, 1);
      Engine.FApps[0].Path := LoadedRules[0].Path;
      Engine.FApps[0].RuleIndex := 0;
      Engine.FApps[0].DayIndex := -1;
      FillChar(Packet, SizeOf(Packet), 0);
      Packet[0] := $45;
      Set16(Packet, 2, SizeOf(Packet));
      Packet[8] := 64;
      Packet[9] := 17; // UDP
      Packet[12] := 10; Packet[13] := 1; Packet[14] := 1; Packet[15] := 1;
      Packet[16] := 8; Packet[17] := 8; Packet[18] := 8; Packet[19] := 8;
      Set16(Packet, 20, 54321);
      Set16(Packet, 22, 443);
      Set16(Packet, 24, 8);
      FillChar(Address, SizeOf(Address), 0);
      Address.Flags := 1 shl 17; // outbound
      Check(PacketTuple(Address, @Packet[0], SizeOf(Packet), Tuple),
        'Could not parse outbound test packet');
      Slot := Engine.HashTuple(Tuple) and High(Engine.FFlows);
      Engine.FFlows[Slot].Used := True;
      Engine.FFlows[Slot].Tuple := Tuple;
      Engine.FFlows[Slot].AppIndex := 0;
      Engine.ProcessPacket(Address, @Packet[0], SizeOf(Packet), True, 0);
      Check((Engine.FDroppedPackets = 1) and
        (Engine.FApps[0].UploadBytes = 0),
        'Outbound packet was not blocked before accounting');
      Packet[12] := 8; Packet[13] := 8; Packet[14] := 8; Packet[15] := 8;
      Packet[16] := 10; Packet[17] := 1; Packet[18] := 1; Packet[19] := 1;
      Set16(Packet, 20, 443);
      Set16(Packet, 22, 54321);
      Address.Flags := 0; // inbound
      Check(PacketTuple(Address, @Packet[0], SizeOf(Packet), Tuple),
        'Could not parse inbound test packet');
      Check(Engine.FlowSlot(Tuple) = Slot, 'Inbound flow did not match');
      Engine.ProcessPacket(Address, @Packet[0], SizeOf(Packet), True, 0);
      Check((Engine.FDroppedPackets = 2) and
        (Engine.FApps[0].DownloadBytes = 0),
        'Inbound packet was not blocked before accounting');
      FillChar(TcpPacket, SizeOf(TcpPacket), 0);
      TcpPacket[0] := $45;
      Set16(TcpPacket, 2, SizeOf(TcpPacket));
      TcpPacket[8] := 64;
      TcpPacket[9] := 6; // TCP
      TcpPacket[12] := 10; TcpPacket[13] := 1;
      TcpPacket[14] := 1; TcpPacket[15] := 1;
      TcpPacket[16] := 8; TcpPacket[17] := 8;
      TcpPacket[18] := 8; TcpPacket[19] := 8;
      Set16(TcpPacket, 20, 54321);
      Set16(TcpPacket, 22, 443);
      TcpPacket[32] := $50; // 20-byte TCP header
      Address.Flags := 1 shl 17;
      Check(PacketTuple(Address, @TcpPacket[0], SizeOf(TcpPacket), Tuple),
        'Could not parse outbound TCP packet');
      Slot := Engine.HashTuple(Tuple) and High(Engine.FFlows);
      Engine.FFlows[Slot].Used := True;
      Engine.FFlows[Slot].Tuple := Tuple;
      Engine.FFlows[Slot].AppIndex := 0;
      Engine.ProcessPacket(Address, @TcpPacket[0], SizeOf(TcpPacket), True, 0);
      Check((Engine.FDroppedPackets = 3) and
        (Engine.FApps[0].UploadBytes = 0),
        'Outbound TCP packet was not blocked');
      TcpPacket[12] := 8; TcpPacket[13] := 8;
      TcpPacket[14] := 8; TcpPacket[15] := 8;
      TcpPacket[16] := 10; TcpPacket[17] := 1;
      TcpPacket[18] := 1; TcpPacket[19] := 1;
      Set16(TcpPacket, 20, 443);
      Set16(TcpPacket, 22, 54321);
      Address.Flags := 0;
      Check(PacketTuple(Address, @TcpPacket[0], SizeOf(TcpPacket), Tuple),
        'Could not parse inbound TCP packet');
      Check(Engine.FlowSlot(Tuple) = Slot,
        'Inbound TCP flow did not match');
      Engine.ProcessPacket(Address, @TcpPacket[0], SizeOf(TcpPacket), True, 0);
      Check((Engine.FDroppedPackets = 4) and
        (Engine.FApps[0].DownloadBytes = 0),
        'Inbound TCP packet was not blocked');
      Engine.FRules[0].Blocked := False;
      Check(not Engine.HasActiveLimits,
        'Unblocked unlimited app still intercepted packets while paused');
      DecodeTime(Now, Hour, Minute, Second, MilliSecond);
      CurrentMinute := Hour * 60 + Minute;
      Engine.FRules[0].ScheduleEnabled := True;
      Engine.FRules[0].BlockOutsideSchedule := True;
      Engine.FRules[0].ScheduleDays := 127;
      Engine.FRules[0].ScheduleStartMin := (CurrentMinute + 1) mod 1440;
      Engine.FRules[0].ScheduleEndMin := (CurrentMinute + 2) mod 1440;
      Check(Engine.HasActiveLimits,
        'Scheduled block did not keep interception active while paused');
      Check(RuleBlocksTrafficAt(Engine.FRules[0], Now, 0),
        'Outside-hours traffic was not blocked');
      Engine.ProcessPacket(Address, @TcpPacket[0], SizeOf(TcpPacket), True, 0);
      Check((Engine.FDroppedPackets = 5) and
        (Engine.FApps[0].DownloadBytes = 0),
        'Scheduled block did not drop inbound traffic');
      SetTcpDirection(TcpPacket, Address, True);
      Check(PacketTuple(Address, @TcpPacket[0], SizeOf(TcpPacket), Tuple),
        'Scheduled outbound packet could not be parsed');
      Check(Engine.FlowSlot(Tuple) = Slot,
        'Scheduled outbound packet did not match the flow');
      Engine.ProcessPacket(Address, @TcpPacket[0], SizeOf(TcpPacket), True, 0);
      Check((Engine.FDroppedPackets = 6) and
        (Engine.FApps[0].UploadBytes = 0),
        'Scheduled block did not drop outbound traffic');
      Engine.FRules[0].ScheduleEnabled := False;
      Engine.FRules[0].BlockOutsideSchedule := False;
      Engine.FRules[0].BlockAfterQuota := True;
      Engine.FRules[0].QuotaBytes := 100;
      Engine.FRules[0].QuotaPeriod := 'daily';
      Engine.FRules[0].QuotaSlowBps := 0;
      Engine.FApps[0].QuotaKey := Engine.QuotaKey(Engine.FRules[0]);
      Engine.FApps[0].QuotaUsed := 100;
      Check(Engine.HasActiveLimits,
        'Quota block did not keep interception active while paused');
      Check(not RuleBlocksTrafficAt(Engine.FRules[0], Now, 99) and
        RuleBlocksTrafficAt(Engine.FRules[0], Now, 100),
        'Quota block threshold was incorrect');
      SetTcpDirection(TcpPacket, Address, False);
      Engine.ProcessPacket(Address, @TcpPacket[0], SizeOf(TcpPacket), True, 0);
      Check((Engine.FDroppedPackets = 7) and
        (Engine.FApps[0].DownloadBytes = 0),
        'Quota block did not drop inbound traffic');
      SetTcpDirection(TcpPacket, Address, True);
      Engine.ProcessPacket(Address, @TcpPacket[0], SizeOf(TcpPacket), True, 0);
      Check((Engine.FDroppedPackets = 8) and
        (Engine.FApps[0].UploadBytes = 0),
        'Quota block did not drop outbound traffic');
      Rules[0] := Engine.FRules[0];
      Check(SaveConfig(ConfigFile, Settings, Rules, ErrorText), ErrorText);
      Check(LoadConfig(ConfigFile, Loaded, LoadedRules, ErrorText), ErrorText);
      Check(LoadedRules[0].BlockAfterQuota and
        (LoadedRules[0].QuotaBytes = 100),
        'Quota block settings did not round-trip');
    finally
      Engine.Free;
    end;
    WriteLn('Manual, scheduled, and quota block packet/config checks passed.');
  except
    on E: Exception do
    begin
      WriteLn('Block rule failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
