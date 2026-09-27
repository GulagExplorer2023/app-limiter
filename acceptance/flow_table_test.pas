program flow_table_test;

{$mode objfpc}{$H+}

uses
  SysUtils, Windows, limiter_engine, windivert_api;

function FlowAddress(Number: Integer): TDivertAddress;
var
  Data: TFlowData;
begin
  FillChar(Result, SizeOf(Result), 0);
  FillChar(Data, SizeOf(Data), 0);
  Data.ProcessId := GetCurrentProcessId;
  Data.EndpointId := QWord(Number) + 1;
  Data.LocalAddr[0] := $0a000001;
  Data.LocalAddr[1] := $0000ffff;
  Data.RemoteAddr[0] := $01010101;
  Data.RemoteAddr[1] := $0000ffff;
  Data.LocalPort := Number + 1000;
  Data.RemotePort := 443;
  Data.Protocol := 6;
  Move(Data, Result.Data[0], SizeOf(Data));
end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

var
  Engine: TLimiterEngine;
  Address: TDivertAddress;
  Tuple: TFlowTuple;
  I, Slot: Integer;
begin
  Engine := TLimiterEngine.Create('unused-config.json', 'unused-state.json');
  try
    for I := 0 to 4999 do
    begin
      Address := FlowAddress(I);
      Engine.AddFlow(Address);
      Tuple := windivert_api.FlowTuple(Address);
      Slot := Engine.FlowSlot(Tuple);
      Check((Slot >= 0) and (Engine.FFlows[Slot].EndpointId = QWord(I) + 1),
        'Inserted flow was not found');
    end;
    for I := 0 to 4095 do
    begin
      Address := FlowAddress(I);
      Engine.DeleteFlow(Address);
    end;
    Check(Engine.FFlowTableRebuilds = 1, 'Tombstones were not compacted');
    Check(Engine.FFlowTombstones = 0, 'Tombstones remained after compaction');
    for I := 4096 to 4999 do
    begin
      Address := FlowAddress(I);
      Slot := Engine.FlowSlot(windivert_api.FlowTuple(Address));
      Check((Slot >= 0) and (Engine.FFlows[Slot].EndpointId = QWord(I) + 1),
        'Live flow was lost during compaction');
    end;
    for I := 0 to 4095 do
    begin
      Address := FlowAddress(I);
      Check(Engine.FlowSlot(windivert_api.FlowTuple(Address)) < 0,
        'Deleted flow remained after compaction');
    end;
    for I := 5000 to 5999 do
    begin
      Address := FlowAddress(I);
      Engine.AddFlow(Address);
      Check(Engine.FlowSlot(windivert_api.FlowTuple(Address)) >= 0,
        'Insertion after compaction failed');
    end;
  finally
    Engine.Free;
  end;

  Engine := TLimiterEngine.Create('unused-config.json', 'unused-state.json');
  try
    for I := 0 to High(Engine.FFlows) do
    begin
      Engine.FFlows[I].Used := True;
      Engine.FFlows[I].EndpointId := QWord(I) + 1;
    end;
    Address := FlowAddress(7000);
    Engine.AddFlow(Address);
    Check(Engine.FFlowTableFull = 1, 'Full table was not reported');
    Check(Engine.FFlows[0].EndpointId = 1,
      'Full table insertion overwrote a live flow');
  finally
    Engine.Free;
  end;
  WriteLn('Flow table compaction and full-table behavior passed.');
end.
