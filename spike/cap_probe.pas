program cap_probe;

{$mode objfpc}{$H+}

{ Feasibility probe only. Run elevated, against a controlled transfer. }

uses
  Classes, SysUtils, Windows;

const
  LayerNetwork = 0;
  LayerFlow = 2;
  FlagSniff = 1;
  FlagRecvOnly = 4;
  FlowEstablished = 1;
  FlowDeleted = 2;
  ShutdownRecv = 1;
  MaxFlows = 4096;
  MaxQueueBytes = 2 * 1024 * 1024;
  MaxQueueDelayUs = 1500000;
  ProcessQueryLimitedInformation = $1000;

type
  TDivertAddress = packed record
    Timestamp: Int64;
    Flags: LongWord;
    Reserved: LongWord;
    Data: array[0..63] of Byte;
  end;
  PDivertAddress = ^TDivertAddress;

  TFlowData = packed record
    EndpointId: QWord;
    ParentEndpointId: QWord;
    ProcessId: LongWord;
    LocalAddr: array[0..3] of LongWord;
    RemoteAddr: array[0..3] of LongWord;
    LocalPort: Word;
    RemotePort: Word;
    Protocol: Byte;
  end;
  PFlowData = ^TFlowData;

  TFlow = record
    EndpointId: QWord;
    LocalPort: Word;
    RemotePort: Word;
    Protocol: Byte;
    IPv6: Boolean;
    Active: Boolean;
  end;

  PQueuedPacket = ^TQueuedPacket;
  TQueuedPacket = record
    Next: PQueuedPacket;
    DueUs: QWord;
    Length: LongWord;
    Address: TDivertAddress;
    Bytes: TBytes;
  end;

function WinDivertOpen(Filter: PAnsiChar; Layer: LongInt;
  Priority: SmallInt; Flags: QWord): THandle; stdcall;
  external 'WinDivert.dll';
function WinDivertRecv(Handle: THandle; Packet: Pointer;
  PacketLength: LongWord; ReceivedLength: PLongWord;
  Address: PDivertAddress): LongBool; stdcall;
  external 'WinDivert.dll';
function WinDivertSend(Handle: THandle; Packet: Pointer;
  PacketLength: LongWord; SentLength: PLongWord;
  Address: PDivertAddress): LongBool; stdcall;
  external 'WinDivert.dll';
function WinDivertShutdown(Handle: THandle; How: LongInt): LongBool; stdcall;
  external 'WinDivert.dll';
function WinDivertClose(Handle: THandle): LongBool; stdcall;
  external 'WinDivert.dll';
function WinDivertHelperParsePacket(Packet: Pointer; PacketLength: LongWord;
  IPv4, IPv6: PPointer; Protocol: PByte; ICMP, ICMPv6, TCP, UDP,
  Data: PPointer; DataLength: PLongWord; Next: PPointer;
  NextLength: PLongWord): LongBool; stdcall;
  external 'WinDivert.dll';
function QueryFullProcessImageNameW(Process: THandle; Flags: DWORD;
  Buffer: PWideChar; var Size: DWORD): BOOL; stdcall;
  external 'kernel32.dll';
function CompareStringOrdinal(String1: PWideChar; Count1: LongInt;
  String2: PWideChar; Count2: LongInt; IgnoreCase: BOOL): LongInt; stdcall;
  external 'kernel32.dll';

var
  NetworkHandle, FlowHandle: THandle;
  FlowLock, QueueLock: TRTLCriticalSection;
  Flows: array[0..MaxFlows - 1] of TFlow;
  Heads, Tails: array[0..1] of PQueuedPacket;
  NextDueUs: array[0..1] of QWord;
  QueueBytes: LongWord = 0;
  CapturedBytes, SentBytes, DroppedPackets: array[0..1] of QWord;
  OtherPackets: QWord = 0;
  MatchedFlows: QWord = 0;
  ObservedFlows: QWord = 0;
  Running: Boolean = True;
  TargetPath: UnicodeString;
  RateBytes: array[0..1] of QWord;
  FlowsOnly: Boolean = False;

function NowUs: QWord;
begin
  Result := GetTickCount64 * 1000;
end;

function ProcessPath(Pid: DWORD): UnicodeString;
var
  Handle: THandle;
  Buffer: array[0..32767] of WideChar;
  Count: DWORD;
begin
  Result := '';
  Handle := OpenProcess(ProcessQueryLimitedInformation, False, Pid);
  if Handle = 0 then Exit;
  try
    Count := Length(Buffer);
    if QueryFullProcessImageNameW(Handle, 0, @Buffer[0], Count) then
      SetString(Result, PWideChar(@Buffer[0]), Count);
  finally
    CloseHandle(Handle);
  end;
end;

function EventCode(const Address: TDivertAddress): Byte;
begin
  Result := (Address.Flags shr 8) and $ff;
end;

function IsIPv6(const Address: TDivertAddress): Boolean;
begin
  Result := (Address.Flags and (1 shl 20)) <> 0;
end;

function IsOutbound(const Address: TDivertAddress): Boolean;
begin
  Result := (Address.Flags and (1 shl 17)) <> 0;
end;

procedure AddFlow(const Address: TDivertAddress);
var
  Flow: PFlowData;
  I: Integer;
  ImagePath: UnicodeString;
  CompareResult: LongInt;
begin
  Flow := PFlowData(@Address.Data[0]);
  ImagePath := ProcessPath(Flow^.ProcessId);
  CompareResult := CompareStringOrdinal(PWideChar(ImagePath), Length(ImagePath),
    PWideChar(TargetPath), Length(TargetPath), BOOL(1));
  if Pos('curl.exe', LowerCase(string(ImagePath))) <> 0 then
  begin
    WriteLn('curl path compare=', CompareResult, ' image length=',
      Length(ImagePath), ' target length=', Length(TargetPath));
    Flush(Output);
  end;
  if CompareResult <> 2 then Exit;
  EnterCriticalSection(FlowLock);
  try
    for I := 0 to MaxFlows - 1 do
      if not Flows[I].Active then
      begin
        Flows[I].EndpointId := Flow^.EndpointId;
        Flows[I].LocalPort := Flow^.LocalPort;
        Flows[I].RemotePort := Flow^.RemotePort;
        Flows[I].Protocol := Flow^.Protocol;
        Flows[I].IPv6 := IsIPv6(Address);
        Flows[I].Active := True;
        Inc(MatchedFlows);
        WriteLn('flow pid=', Flow^.ProcessId, ' local=', Flow^.LocalPort,
          ' remote=', Flow^.RemotePort, ' protocol=', Flow^.Protocol);
        Flush(Output);
        Break;
      end;
  finally
    LeaveCriticalSection(FlowLock);
  end;
end;

procedure DeleteFlow(const Address: TDivertAddress);
var
  Flow: PFlowData;
  I: Integer;
begin
  Flow := PFlowData(@Address.Data[0]);
  EnterCriticalSection(FlowLock);
  try
    for I := 0 to MaxFlows - 1 do
      if Flows[I].Active and (Flows[I].EndpointId = Flow^.EndpointId) then
      begin
        Flows[I].Active := False;
        Break;
      end;
  finally
    LeaveCriticalSection(FlowLock);
  end;
end;

function MatchesFlow(const Address: TDivertAddress; Packet: Pointer;
  Length: LongWord): Boolean;
var
  IPv4, IPv6, TCP, UDP: Pointer;
  Protocol: Byte;
  LocalPort, RemotePort: Word;
  I: Integer;
  Header: PByte;
begin
  Result := False;
  IPv4 := nil; IPv6 := nil; TCP := nil; UDP := nil; Protocol := 0;
  if not WinDivertHelperParsePacket(Packet, Length, @IPv4, @IPv6,
    @Protocol, nil, nil, @TCP, @UDP, nil, nil, nil, nil) then Exit;
  if TCP <> nil then Header := PByte(TCP)
  else if UDP <> nil then Header := PByte(UDP)
  else Exit;
  if IsOutbound(Address) then
  begin
    LocalPort := (Word(Header[0]) shl 8) or Header[1];
    RemotePort := (Word(Header[2]) shl 8) or Header[3];
  end
  else
  begin
    RemotePort := (Word(Header[0]) shl 8) or Header[1];
    LocalPort := (Word(Header[2]) shl 8) or Header[3];
  end;
  EnterCriticalSection(FlowLock);
  try
    for I := 0 to MaxFlows - 1 do
      if Flows[I].Active and (Flows[I].LocalPort = LocalPort) and
        (Flows[I].RemotePort = RemotePort) and
        (Flows[I].Protocol = Protocol) and
        (Flows[I].IPv6 = IsIPv6(Address)) then
      begin
        Result := True;
        Break;
      end;
  finally
    LeaveCriticalSection(FlowLock);
  end;
end;

procedure QueuePacket(Direction: Integer; const Address: TDivertAddress;
  Packet: Pointer; Length: LongWord);
var
  Item: PQueuedPacket;
  Due, Interval, Now: QWord;
begin
  Now := NowUs;
  EnterCriticalSection(QueueLock);
  try
    Due := NextDueUs[Direction];
    if Due < Now then Due := Now;
    if (Due > Now + MaxQueueDelayUs) or
      (QueueBytes + Length > MaxQueueBytes) then
    begin
      Inc(DroppedPackets[Direction]);
      Exit;
    end;
    New(Item);
    Item^.Next := nil;
    Item^.DueUs := Due;
    Item^.Length := Length;
    Item^.Address := Address;
    SetLength(Item^.Bytes, Length);
    Move(Packet^, Item^.Bytes[0], Length);
    if Tails[Direction] = nil then Heads[Direction] := Item
    else Tails[Direction]^.Next := Item;
    Tails[Direction] := Item;
    Inc(QueueBytes, Length);
    Inc(CapturedBytes[Direction], Length);
    Interval := (QWord(Length) * 1000000 + RateBytes[Direction] - 1)
      div RateBytes[Direction];
    NextDueUs[Direction] := Due + Interval;
  finally
    LeaveCriticalSection(QueueLock);
  end;
end;

type
  TFlowThread = class(TThread)
  protected
    procedure Execute; override;
  end;
  TSenderThread = class(TThread)
  protected
    procedure Execute; override;
  end;
  TStopThread = class(TThread)
  private
    FSeconds: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(Seconds: Integer);
  end;

procedure TFlowThread.Execute;
var
  Address: TDivertAddress;
  Length: LongWord;
  Flow: PFlowData;
begin
  while Running do
  begin
    FillChar(Address, SizeOf(Address), 0);
    Length := 0;
    if not WinDivertRecv(FlowHandle, nil, 0, @Length, @Address) then
    begin
      WriteLn('Flow receive stopped: ', GetLastError);
      Flush(Output);
      Break;
    end;
    Inc(ObservedFlows);
    if ObservedFlows <= 20 then
    begin
      Flow := PFlowData(@Address.Data[0]);
      WriteLn('observed flow event=', EventCode(Address),
        ' pid=', Flow^.ProcessId, ' path=', string(ProcessPath(Flow^.ProcessId)),
        ' local=', Flow^.LocalPort, ' remote=', Flow^.RemotePort,
        ' flags=', Address.Flags);
      Flush(Output);
    end;
    case EventCode(Address) of
      FlowEstablished: AddFlow(Address);
      FlowDeleted: DeleteFlow(Address);
    end;
  end;
end;

procedure TSenderThread.Execute;
var
  Item: PQueuedPacket;
  Direction, Other: Integer;
  Sent: LongWord;
  Now: QWord;
begin
  repeat
    Item := nil;
    EnterCriticalSection(QueueLock);
    try
      Direction := 0;
      if (Heads[0] = nil) or
        ((Heads[1] <> nil) and (Heads[1]^.DueUs < Heads[0]^.DueUs)) then
        Direction := 1;
      Other := 1 - Direction;
      if Heads[Direction] <> nil then
      begin
        Now := NowUs;
        if (Heads[Direction]^.DueUs <= Now) or not Running then
        begin
          Item := Heads[Direction];
          Heads[Direction] := Item^.Next;
          if Heads[Direction] = nil then Tails[Direction] := nil;
          Dec(QueueBytes, Item^.Length);
        end;
      end
      else if Heads[Other] <> nil then
        Direction := Other;
    finally
      LeaveCriticalSection(QueueLock);
    end;
    if Item <> nil then
    begin
      Sent := 0;
      if WinDivertSend(NetworkHandle, @Item^.Bytes[0], Item^.Length,
        @Sent, @Item^.Address) then
        Inc(SentBytes[Direction], Sent)
      else
        Inc(DroppedPackets[Direction]);
      Dispose(Item);
    end
    else
      Sleep(2);
  until not Running and (Heads[0] = nil) and (Heads[1] = nil);
end;

constructor TStopThread.Create(Seconds: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FSeconds := Seconds;
  Start;
end;

procedure TStopThread.Execute;
var
  I: Integer;
begin
  for I := 1 to FSeconds * 10 do
  begin
    if not Running then Exit;
    Sleep(100);
  end;
  Running := False;
  WinDivertShutdown(NetworkHandle, ShutdownRecv);
  WinDivertShutdown(FlowHandle, ShutdownRecv);
end;

var
  FlowThread: TFlowThread;
  SenderThread: TSenderThread;
  StopThread: TStopThread;
  Packet: array[0..65535] of Byte;
  Address: TDivertAddress;
  Length, Sent: LongWord;
  Direction, Seconds: Integer;
begin
  if (ParamCount <> 4) and (ParamCount <> 5) then
  begin
    WriteLn('Usage: cap_probe.exe <full-exe-path> <download-KBps> ',
      '<upload-KBps> <seconds> [--flows-only]');
    Halt(2);
  end;
  FlowsOnly := (ParamCount = 5) and (ParamStr(5) = '--flows-only');
  if (ParamCount = 5) and not FlowsOnly then
    raise Exception.Create('Unknown option: ' + ParamStr(5));
  TargetPath := UnicodeString(ExpandFileName(ParamStr(1)));
  RateBytes[0] := StrToQWord(ParamStr(2)) * 1024;
  RateBytes[1] := StrToQWord(ParamStr(3)) * 1024;
  Seconds := StrToInt(ParamStr(4));
  if (RateBytes[0] = 0) or (RateBytes[1] = 0) or
    (Seconds < 1) or (Seconds > 600) then
    raise Exception.Create('Rates must be positive and seconds 1..600');
  if not FileExists(TargetPath) then
    raise Exception.Create('Executable not found: ' + string(TargetPath));
  WriteLn('Self path compare=', CompareStringOrdinal(PWideChar(TargetPath),
    System.Length(TargetPath), PWideChar(TargetPath),
    System.Length(TargetPath), BOOL(1)), ' last error=', GetLastError);
  Flush(Output);
  InitializeCriticalSection(FlowLock);
  InitializeCriticalSection(QueueLock);
  FlowHandle := WinDivertOpen('true', LayerFlow, 0,
    FlagSniff or FlagRecvOnly);
  if FlowHandle = INVALID_HANDLE_VALUE then
    raise Exception.CreateFmt('Flow WinDivertOpen failed: %d', [GetLastError]);
  if FlowsOnly then
    NetworkHandle := WinDivertOpen('false', LayerNetwork, 0, 0)
  else
    NetworkHandle := WinDivertOpen('(tcp or udp) and !loopback',
      LayerNetwork, 0, 0);
  if NetworkHandle = INVALID_HANDLE_VALUE then
  begin
    WinDivertClose(FlowHandle);
    raise Exception.CreateFmt('Network WinDivertOpen failed: %d', [GetLastError]);
  end;
  WriteLn('Target: ', string(TargetPath));
  WriteLn('Limits: download=', RateBytes[0], ' B/s upload=',
    RateBytes[1], ' B/s for ', Seconds, ' s');
  if FlowsOnly then WriteLn('Flow diagnostic mode: no packets diverted');
  Flush(Output);
  FlowThread := TFlowThread.Create(False);
  SenderThread := TSenderThread.Create(False);
  StopThread := TStopThread.Create(Seconds);
  try
    while Running do
    begin
      FillChar(Address, SizeOf(Address), 0);
      Length := 0;
      if not WinDivertRecv(NetworkHandle, @Packet[0], SizeOf(Packet),
        @Length, @Address) then Break;
      if MatchesFlow(Address, @Packet[0], Length) then
      begin
        if IsOutbound(Address) then Direction := 1 else Direction := 0;
        QueuePacket(Direction, Address, @Packet[0], Length);
      end
      else
      begin
        Sent := 0;
        WinDivertSend(NetworkHandle, @Packet[0], Length, @Sent, @Address);
        Inc(OtherPackets);
      end;
    end;
  finally
    Running := False;
    WinDivertShutdown(FlowHandle, ShutdownRecv);
    FlowThread.WaitFor;
    SenderThread.WaitFor;
    StopThread.WaitFor;
    FlowThread.Free;
    SenderThread.Free;
    StopThread.Free;
    WinDivertClose(NetworkHandle);
    WinDivertClose(FlowHandle);
    DoneCriticalSection(QueueLock);
    DoneCriticalSection(FlowLock);
    WriteLn('Observed flows=', ObservedFlows, ' matched flows=', MatchedFlows,
      ' other packets=', OtherPackets);
    WriteLn('Download queued=', CapturedBytes[0], ' sent=', SentBytes[0],
      ' dropped=', DroppedPackets[0]);
    WriteLn('Upload queued=', CapturedBytes[1], ' sent=', SentBytes[1],
      ' dropped=', DroppedPackets[1]);
    Flush(Output);
  end;
end.
