program app_limiter_service;

{$mode objfpc}{$H+}
{$R AppLimiterVersion.res}

uses
  Classes, SysUtils, Windows, limiter_engine;

const
  ServiceName: UnicodeString = 'AppLimiterService';
  SERVICE_WIN32_OWN_PROCESS = $10;
  SERVICE_STOPPED = 1;
  SERVICE_START_PENDING = 2;
  SERVICE_STOP_PENDING = 3;
  SERVICE_RUNNING = 4;
  SERVICE_ACCEPT_STOP = 1;
  SERVICE_CONTROL_STOP = 1;

type
  TServiceStatus = record
    ServiceType: DWORD;
    CurrentState: DWORD;
    ControlsAccepted: DWORD;
    Win32ExitCode: DWORD;
    ServiceSpecificExitCode: DWORD;
    CheckPoint: DWORD;
    WaitHint: DWORD;
  end;
  PServiceStatus = ^TServiceStatus;

  TServiceMain = procedure(ArgCount: DWORD; Argv: PPWideChar); stdcall;
  TServiceTableEntry = record
    Name: PWideChar;
    Main: TServiceMain;
  end;
  PServiceTableEntry = ^TServiceTableEntry;

function StartServiceCtrlDispatcherW(Table: PServiceTableEntry): BOOL;
  stdcall; external 'advapi32.dll';
function RegisterServiceCtrlHandlerW(Name: PWideChar;
  Handler: Pointer): THandle; stdcall; external 'advapi32.dll';
function SetServiceStatus(StatusHandle: THandle;
  Status: PServiceStatus): BOOL; stdcall; external 'advapi32.dll';

var
  StopEvent: THandle = 0;
  StatusHandle: THandle = 0;
  Status: TServiceStatus;

procedure ReportStatus(State, Accepted, ExitCode: DWORD);
begin
  Status.ServiceType := SERVICE_WIN32_OWN_PROCESS;
  Status.CurrentState := State;
  Status.ControlsAccepted := Accepted;
  Status.Win32ExitCode := ExitCode;
  Status.ServiceSpecificExitCode := 0;
  Status.CheckPoint := 0;
  Status.WaitHint := 5000;
  if StatusHandle <> 0 then SetServiceStatus(StatusHandle, @Status);
end;

procedure ServiceControl(Control: DWORD); stdcall;
begin
  if Control = SERVICE_CONTROL_STOP then
  begin
    ReportStatus(SERVICE_STOP_PENDING, 0, 0);
    if StopEvent <> 0 then SetEvent(StopEvent);
  end;
end;

function ReadPaths(out ConfigFile, StateFile: string): Boolean;
begin
  Result := (ParamCount = 4) and (ParamStr(1) = '--config') and
    (ParamStr(3) = '--state');
  if not Result then Exit;
  ConfigFile := ParamStr(2);
  StateFile := ParamStr(4);
  Result := (ConfigFile <> '') and (StateFile <> '');
end;

procedure ServiceEntry(ArgCount: DWORD; Argv: PPWideChar); stdcall;
var
  ConfigFile, StateFile: string;
  Engine: TLimiterEngine;
begin
  StatusHandle := RegisterServiceCtrlHandlerW(PWideChar(ServiceName),
    @ServiceControl);
  if StatusHandle = 0 then Exit;
  ReportStatus(SERVICE_START_PENDING, 0, 0);
  StopEvent := CreateEvent(nil, True, False, nil);
  if StopEvent = 0 then
  begin
    ReportStatus(SERVICE_STOPPED, 0, GetLastError);
    Exit;
  end;
  Engine := nil;
  try
    if not ReadPaths(ConfigFile, StateFile) then
      raise Exception.Create('Missing service configuration paths');
    Engine := TLimiterEngine.Create(ConfigFile, StateFile);
    Engine.Start;
    ReportStatus(SERVICE_RUNNING, SERVICE_ACCEPT_STOP, 0);
    WaitForSingleObject(StopEvent, INFINITE);
    ReportStatus(SERVICE_STOP_PENDING, 0, 0);
    Engine.Stop;
    ReportStatus(SERVICE_STOPPED, 0, 0);
  except
    on E: Exception do
      ReportStatus(SERVICE_STOPPED, 0, ERROR_SERVICE_SPECIFIC_ERROR);
  end;
  Engine.Free;
  CloseHandle(StopEvent);
  StopEvent := 0;
end;

procedure RunConsole;
var
  Engine: TLimiterEngine;
  I, Duration: Integer;
begin
  if ParamCount <> 4 then
  begin
    WriteLn('Usage: app_limiter_service.exe --console ',
      '<config.json> <state.json> <seconds>');
    Halt(2);
  end;
  Duration := StrToInt(ParamStr(4));
  if (Duration < 1) or (Duration > 600) then Halt(2);
  Engine := TLimiterEngine.Create(ParamStr(2), ParamStr(3));
  try
    Engine.Start;
    WriteLn('Backend running for ', Duration, ' seconds');
    Flush(Output);
    for I := 1 to Duration * 10 do Sleep(100);
    Engine.Stop;
  finally
    Engine.Free;
  end;
end;

var
  Table: array[0..1] of TServiceTableEntry;
begin
  if (ParamCount > 0) and (ParamStr(1) = '--console') then
    RunConsole
  else
  begin
    FillChar(Table, SizeOf(Table), 0);
    Table[0].Name := PWideChar(ServiceName);
    Table[0].Main := @ServiceEntry;
    if not StartServiceCtrlDispatcherW(@Table[0]) then
      Halt(GetLastError);
  end;
end.
