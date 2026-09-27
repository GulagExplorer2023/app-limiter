unit windivert_api;

{$mode objfpc}{$H+}

interface

uses Windows, SysUtils;

const
  WD_NETWORK = 0;
  WD_FLOW = 2;
  WD_FLOW_ESTABLISHED = 1;
  WD_FLOW_DELETED = 2;
  WD_FLAG_SNIFF = 1;
  WD_FLAG_RECV_ONLY = 4;
  WD_SHUTDOWN_RECV = 1;

type
  TIPAddress = array[0..3] of LongWord;
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
    LocalAddr: TIPAddress;
    RemoteAddr: TIPAddress;
    LocalPort: Word;
    RemotePort: Word;
    Protocol: Byte;
  end;
  PFlowData = ^TFlowData;
  TFlowTuple = record
    LocalAddr, RemoteAddr: TIPAddress;
    LocalPort, RemotePort: Word;
    Protocol: Byte;
    IPv6: Boolean;
  end;
  TTrafficScope = (tsPublic, tsLocal, tsUnknown);

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

function EventCode(const Address: TDivertAddress): Byte;
function IsIPv6(const Address: TDivertAddress): Boolean;
function IsOutbound(const Address: TDivertAddress): Boolean;
function FlowTuple(const Address: TDivertAddress): TFlowTuple;
function PacketTuple(const Address: TDivertAddress; Packet: Pointer;
  PacketLength: LongWord; out Tuple: TFlowTuple): Boolean;
function EqualTuple(const A, B: TFlowTuple): Boolean;
function ScopeOf(const Tuple: TFlowTuple): TTrafficScope;

implementation

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

function FlowTuple(const Address: TDivertAddress): TFlowTuple;
var
  Flow: PFlowData;
begin
  Flow := PFlowData(@Address.Data[0]);
  Result.LocalAddr := Flow^.LocalAddr;
  Result.RemoteAddr := Flow^.RemoteAddr;
  Result.LocalPort := Flow^.LocalPort;
  Result.RemotePort := Flow^.RemotePort;
  Result.Protocol := Flow^.Protocol;
  Result.IPv6 := IsIPv6(Address);
end;

function BigEndian32(P: PByte): LongWord;
begin
  Result := (LongWord(P[0]) shl 24) or (LongWord(P[1]) shl 16) or
    (LongWord(P[2]) shl 8) or LongWord(P[3]);
end;

procedure ReadIP(IPv4, IPv6: Pointer; Source: Boolean; out IP: TIPAddress);
var
  P: PByte;
  I: Integer;
begin
  FillChar(IP, SizeOf(IP), 0);
  if IPv4 <> nil then
  begin
    P := PByte(IPv4);
    if Source then Inc(P, 12) else Inc(P, 16);
    IP[0] := BigEndian32(P);
    IP[1] := $0000ffff;
  end
  else if IPv6 <> nil then
  begin
    P := PByte(IPv6);
    if Source then Inc(P, 8) else Inc(P, 24);
    for I := 0 to 3 do IP[3 - I] := BigEndian32(P + I * 4);
  end;
end;

function PacketTuple(const Address: TDivertAddress; Packet: Pointer;
  PacketLength: LongWord; out Tuple: TFlowTuple): Boolean;
var
  IPv4, IPv6, TCP, UDP: Pointer;
  Header: PByte;
  Protocol: Byte;
  SourcePort, DestPort: Word;
begin
  FillChar(Tuple, SizeOf(Tuple), 0);
  IPv4 := nil; IPv6 := nil; TCP := nil; UDP := nil; Protocol := 0;
  Result := WinDivertHelperParsePacket(Packet, PacketLength, @IPv4, @IPv6,
    @Protocol, nil, nil, @TCP, @UDP, nil, nil, nil, nil);
  if not Result then Exit;
  if TCP <> nil then Header := PByte(TCP)
  else if UDP <> nil then Header := PByte(UDP)
  else Exit(False);
  SourcePort := (Word(Header[0]) shl 8) or Header[1];
  DestPort := (Word(Header[2]) shl 8) or Header[3];
  Tuple.Protocol := Protocol;
  Tuple.IPv6 := IPv6 <> nil;
  if IsOutbound(Address) then
  begin
    Tuple.LocalPort := SourcePort;
    Tuple.RemotePort := DestPort;
    ReadIP(IPv4, IPv6, True, Tuple.LocalAddr);
    ReadIP(IPv4, IPv6, False, Tuple.RemoteAddr);
  end
  else
  begin
    Tuple.LocalPort := DestPort;
    Tuple.RemotePort := SourcePort;
    ReadIP(IPv4, IPv6, False, Tuple.LocalAddr);
    ReadIP(IPv4, IPv6, True, Tuple.RemoteAddr);
  end;
end;

function EqualTuple(const A, B: TFlowTuple): Boolean;
begin
  Result := (A.LocalPort = B.LocalPort) and
    (A.RemotePort = B.RemotePort) and (A.Protocol = B.Protocol) and
    (A.IPv6 = B.IPv6) and
    CompareMem(@A.LocalAddr, @B.LocalAddr, SizeOf(TIPAddress)) and
    CompareMem(@A.RemoteAddr, @B.RemoteAddr, SizeOf(TIPAddress));
end;

function ScopeOf(const Tuple: TFlowTuple): TTrafficScope;
var
  IP, Top: LongWord;
begin
  Result := tsUnknown;
  if not Tuple.IPv6 then
  begin
    IP := Tuple.RemoteAddr[0];
    if (IP and $ff000000 = $0a000000) or       // 10/8
      (IP and $fff00000 = $ac100000) or       // 172.16/12
      (IP and $ffff0000 = $c0a80000) or       // 192.168/16
      (IP and $ffff0000 = $a9fe0000) or       // link local
      (IP and $ff000000 = $7f000000) or       // loopback
      (IP and $ffc00000 = $64400000) then     // carrier grade NAT
      Exit(tsLocal);
    if (IP and $f0000000 = $e0000000) or (IP = 0) then Exit;
    Exit(tsPublic);
  end;
  Top := Tuple.RemoteAddr[3];
  if (Top and $fe000000 = $fc000000) or       // unique local
    (Top and $ffc00000 = $fe800000) or       // link local
    (Top = 0) then Exit(tsLocal);
  if Top and $ff000000 = $ff000000 then Exit; // multicast
  Result := tsPublic;
end;

end.
