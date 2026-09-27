unit instance_control;

{$mode objfpc}{$H+}

interface

function BeginPanelInstance(out FirstInstance: Boolean;
  out ErrorText: string): Boolean;
function NotifyRunningPanel: Boolean;
function OpenRequestPending: Boolean;
procedure EndPanelInstance;

implementation

uses
  Windows, SysUtils;

const
  {$ifdef STARTUP_TEST}
  InstanceName: UnicodeString =
    'Local\AppLimiter.Panel.Acceptance.3d9f4b14-c1e7-4818-a75f-b109cd787c0e';
  RequestName: UnicodeString =
    'Local\AppLimiter.OpenRequest.Acceptance.3d9f4b14-c1e7-4818-a75f-b109cd787c0e';
  {$else}
  InstanceName: UnicodeString =
    'Local\AppLimiter.Panel.3d9f4b14-c1e7-4818-a75f-b109cd787c0e';
  RequestName: UnicodeString =
    'Local\AppLimiter.OpenRequest.3d9f4b14-c1e7-4818-a75f-b109cd787c0e';
  {$endif}

var
  InstanceMutex: THandle = 0;
  RequestEvent: THandle = 0;

function BeginPanelInstance(out FirstInstance: Boolean;
  out ErrorText: string): Boolean;
var
  AlreadyExists: Boolean;
begin
  Result := False;
  FirstInstance := False;
  ErrorText := '';
  InstanceMutex := CreateMutexW(nil, False, PWideChar(InstanceName));
  if InstanceMutex = 0 then
  begin
    ErrorText := 'Could not check whether App Limiter is running.';
    Exit;
  end;
  AlreadyExists := GetLastError = ERROR_ALREADY_EXISTS;
  FirstInstance := not AlreadyExists;
  if FirstInstance then
  begin
    RequestEvent := CreateEventW(nil, False, False, PWideChar(RequestName));
    if RequestEvent = 0 then
    begin
      ErrorText := 'Could not set up App Limiter launch requests.';
      EndPanelInstance;
      Exit;
    end;
  end;
  Result := True;
end;

function NotifyRunningPanel: Boolean;
var
  EventHandle: THandle;
  I: Integer;
begin
  Result := False;
  for I := 1 to 50 do
  begin
    EventHandle := OpenEventW(EVENT_MODIFY_STATE, False,
      PWideChar(RequestName));
    if EventHandle <> 0 then
    begin
      try
        Result := SetEvent(EventHandle);
      finally
        CloseHandle(EventHandle);
      end;
      Exit;
    end;
    Sleep(100);
  end;
end;

function OpenRequestPending: Boolean;
begin
  Result := (RequestEvent <> 0) and
    (WaitForSingleObject(RequestEvent, 0) = WAIT_OBJECT_0);
end;

procedure EndPanelInstance;
begin
  if RequestEvent <> 0 then CloseHandle(RequestEvent);
  if InstanceMutex <> 0 then CloseHandle(InstanceMutex);
  RequestEvent := 0;
  InstanceMutex := 0;
end;

end.
