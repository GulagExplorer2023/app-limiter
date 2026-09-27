program performance_sanity_test;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Windows, limiter_engine, windivert_api;

type
  TLockProbe = class(TThread)
  public
    Engine: TLimiterEngine;
    MaxWaitMs: QWord;
    constructor Create(AEngine: TLimiterEngine);
    procedure Execute; override;
  end;

constructor TLockProbe.Create(AEngine: TLimiterEngine);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Engine := AEngine;
  Start;
end;

procedure TLockProbe.Execute;
var
  Started, WaitMs: QWord;
begin
  while not Terminated do
  begin
    Started := GetTickCount64;
    EnterCriticalSection(Engine.FLock);
    WaitMs := GetTickCount64 - Started;
    LeaveCriticalSection(Engine.FLock);
    if WaitMs > MaxWaitMs then MaxWaitMs := WaitMs;
    Sleep(1);
  end;
end;

var
  Engine: TLimiterEngine;
  I, Queued, Dropped: Integer;
  Started, StateMs, DestinationMs, QueueMs, LockWaitMs,
    CalibrationMs: QWord;
  Address: TDivertAddress;
  Packet: array[0..1499] of Byte;
  Item, NextItem: PQueuedPacket;
  BasePath: string;
  Probe: TLockProbe;
begin
  if ParamCount <> 1 then Halt(2);
  BasePath := IncludeTrailingPathDelimiter(ParamStr(1));
  ForceDirectories(BasePath);
  Engine := TLimiterEngine.Create(BasePath + 'config.json',
    BasePath + 'state.json');
  try
    SetLength(Engine.FApps, 1024);
    for I := 0 to High(Engine.FApps) do
    begin
      Engine.FApps[I].Path := 'C:\Apps\app' + IntToStr(I) + '.exe';
      Engine.FApps[I].LastPacketMs := GetTickCount64;
      Engine.FApps[I].RuleIndex := -1;
    end;
    SetLength(Engine.FDestinations, 16384);
    for I := 0 to High(Engine.FDestinations) do
    begin
      Engine.FDestinations[I].AppIndex := I mod Length(Engine.FApps);
      Engine.FDestinations[I].Name := 'host' + IntToStr(I) + '.example';
      Engine.FDestinations[I].Address := '203.0.113.1';
      Engine.FDestinations[I].Source := 'IP';
      Engine.FDestinations[I].LastSeenMs := GetTickCount64;
    end;
    Engine.FDestinationsRevision := 1;
    Started := GetTickCount64;
    Engine.WriteState;
    StateMs := GetTickCount64 - Started;
    Probe := TLockProbe.Create(Engine);
    try
      Sleep(10);
      EnterCriticalSection(Engine.FLock);
      try
        Sleep(100);
      finally
        LeaveCriticalSection(Engine.FLock);
      end;
      Sleep(10);
    finally
      Probe.Terminate;
      Probe.WaitFor;
      CalibrationMs := Probe.MaxWaitMs;
      Probe.Free;
    end;
    if CalibrationMs < 50 then
      raise Exception.Create('Lock probe did not detect a known stall');
    Probe := TLockProbe.Create(Engine);
    try
      Sleep(10);
      Started := GetTickCount64;
      Engine.WriteDestinations;
      DestinationMs := GetTickCount64 - Started;
    finally
      Probe.Terminate;
      Probe.WaitFor;
      LockWaitMs := Probe.MaxWaitMs;
      Probe.Free;
    end;
    if LockWaitMs > 100 then
      raise Exception.CreateFmt('Destination publication stalled packets for %d ms',
        [LockWaitMs]);
    Engine.FDestinationsRevision := 2;
    Engine.WriteDestinations;
    if Engine.FPublishedDestinationsRevision <> 1 then
      raise Exception.Create('Full destination table republished too soon');
    Engine.FLastDestinationsPublishMs := GetTickCount64 - 5000;
    Engine.WriteDestinations;
    if Engine.FPublishedDestinationsRevision <> 2 then
      raise Exception.Create('Deferred destination update was not published');

    SetLength(Engine.FDueUs, 1);
    FillChar(Address, SizeOf(Address), 0);
    FillChar(Packet, SizeOf(Packet), 0);
    Queued := 0;
    Dropped := 0;
    Started := GetTickCount64;
    for I := 1 to 2000 do
      if Engine.QueuePacket(0, 0, 0, 2 * 1024 * 1024, 0, tsPublic,
        Address, @Packet[0], SizeOf(Packet), INVALID_HANDLE_VALUE) then
        Inc(Queued)
      else if I > 1 then
        Inc(Dropped);
    QueueMs := GetTickCount64 - Started;
    Item := Engine.FQueueHead[0];
    while Item <> nil do
    begin
      NextItem := Item^.Next;
      Dispose(Item);
      Item := NextItem;
    end;
    Engine.FQueueHead[0] := nil;
    Engine.FQueueTail[0] := nil;
    WriteLn('apps=1024 destinations=16384 stateMs=', StateMs,
      ' destinationsMs=', DestinationMs, ' maxLockWaitMs=', LockWaitMs,
      ' probeCalibrationMs=', CalibrationMs,
      ' queueMs=', QueueMs,
      ' queued=', Queued, ' dropped=', Dropped);
  finally
    Engine.Free;
  end;
end.
