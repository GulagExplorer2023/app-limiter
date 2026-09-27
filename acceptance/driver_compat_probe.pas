program driver_compat_probe;

{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}

{ Opens the same two WinDivert layers used by the service, in sniff mode.
  This never captures packets or changes network traffic. }

uses
  Windows, SysUtils, windivert_api;

var
  FlowHandle, NetworkHandle: THandle;
  ErrorCode: DWORD;
  Failure: Integer;
begin
  FlowHandle := INVALID_HANDLE_VALUE;
  NetworkHandle := INVALID_HANDLE_VALUE;
  Failure := 0;
  try
    FlowHandle := WinDivertOpen('true', WD_FLOW, 0,
      WD_FLAG_SNIFF or WD_FLAG_RECV_ONLY);
    if FlowHandle = INVALID_HANDLE_VALUE then
    begin
      ErrorCode := GetLastError;
      Writeln('Flow layer failed: Windows error ', ErrorCode);
      Failure := 2;
    end;
    if Failure = 0 then
    begin
      NetworkHandle := WinDivertOpen('(tcp or udp) and !loopback',
        WD_NETWORK, 0, WD_FLAG_SNIFF);
      if NetworkHandle = INVALID_HANDLE_VALUE then
      begin
        ErrorCode := GetLastError;
        Writeln('Network layer failed: Windows error ', ErrorCode);
        Failure := 3;
      end;
    end;
    if Failure = 0 then
      Writeln('WinDivert flow and network layers opened successfully.');
  finally
    if NetworkHandle <> INVALID_HANDLE_VALUE then WinDivertClose(NetworkHandle);
    if FlowHandle <> INVALID_HANDLE_VALUE then WinDivertClose(FlowHandle);
  end;
  if Failure <> 0 then Halt(Failure);
end.
