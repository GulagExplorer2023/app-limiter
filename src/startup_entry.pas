unit startup_entry;

{$mode objfpc}{$H+}

interface

function ReadStartupEntry(const ExecutablePath: string;
  out Enabled, EntryExists: Boolean; out ErrorText: string): Boolean;
function SetStartupEntry(const ExecutablePath: string; Enabled: Boolean;
  out ErrorText: string): Boolean;

implementation

uses
  SysUtils, Windows;

const
  RunKeyPath: UnicodeString =
    'Software\Microsoft\Windows\CurrentVersion\Run';
  {$ifdef STARTUP_TEST}
  RunValueName: UnicodeString = 'AppLimiter.AcceptanceTest';
  {$else}
  RunValueName: UnicodeString = 'AppLimiter';
  {$endif}

function RegOpenKeyExWide(Key: HKEY; SubKey: PWideChar; Options,
  DesiredAccess: DWORD; out OpenedKey: HKEY): LongInt; stdcall;
  external 'advapi32.dll' name 'RegOpenKeyExW';
function RegCreateKeyExWide(Key: HKEY; SubKey: PWideChar;
  Reserved: DWORD; ClassName: PWideChar; Options, DesiredAccess: DWORD;
  SecurityAttributes: Pointer; out OpenedKey: HKEY;
  Disposition: PDWORD): LongInt; stdcall;
  external 'advapi32.dll' name 'RegCreateKeyExW';
function RegQueryValueExWide(Key: HKEY; ValueName: PWideChar;
  Reserved, ValueType: PDWORD; Data: PByte; var DataSize: DWORD): LongInt;
  stdcall; external 'advapi32.dll' name 'RegQueryValueExW';
function RegSetValueExWide(Key: HKEY; ValueName: PWideChar;
  Reserved, ValueType: DWORD; Data: PByte; DataSize: DWORD): LongInt;
  stdcall; external 'advapi32.dll' name 'RegSetValueExW';
function RegDeleteValueWide(Key: HKEY; ValueName: PWideChar): LongInt;
  stdcall; external 'advapi32.dll' name 'RegDeleteValueW';
function RegCloseKeyRaw(Key: HKEY): LongInt; stdcall;
  external 'advapi32.dll' name 'RegCloseKey';

function StartupCommand(const ExecutablePath: string): UnicodeString;
begin
  Result := UnicodeString(UTF8Decode('"' +
    ExpandFileName(ExecutablePath) + '" --startup'));
end;

function RegistryError(const Operation: string; Code: LongInt): string;
begin
  Result := Operation + ': ' + SysErrorMessage(Code) +
    ' (' + IntToStr(Code) + ')';
end;

function ReadStartupEntry(const ExecutablePath: string;
  out Enabled, EntryExists: Boolean; out ErrorText: string): Boolean;
var
  Key: HKEY;
  Buffer: array[0..4095] of WideChar;
  DataSize, ValueType: DWORD;
  Status: LongInt;
  Command: UnicodeString;
begin
  Result := False;
  Enabled := False;
  EntryExists := False;
  ErrorText := '';
  Status := RegOpenKeyExWide(HKEY_CURRENT_USER, PWideChar(RunKeyPath),
    0, KEY_QUERY_VALUE, Key);
  if Status = ERROR_FILE_NOT_FOUND then Exit(True);
  if Status <> ERROR_SUCCESS then
  begin
    ErrorText := RegistryError('Cannot read Windows startup settings', Status);
    Exit;
  end;
  try
    DataSize := SizeOf(Buffer);
    ValueType := 0;
    Status := RegQueryValueExWide(Key, PWideChar(RunValueName), nil,
      @ValueType, PByte(@Buffer[0]), DataSize);
    if Status = ERROR_FILE_NOT_FOUND then Exit(True);
    if Status <> ERROR_SUCCESS then
    begin
      ErrorText := RegistryError('Cannot read App Limiter startup entry', Status);
      Exit;
    end;
    EntryExists := True;
    if (ValueType <> REG_SZ) and (ValueType <> REG_EXPAND_SZ) then
      Exit(True);
    if (DataSize mod SizeOf(WideChar)) <> 0 then
      Exit(True);
    SetString(Command, PWideChar(@Buffer[0]), DataSize div SizeOf(WideChar));
    while (Length(Command) > 0) and (Command[Length(Command)] = #0) do
      SetLength(Command, Length(Command) - 1);
    Enabled := CompareText(UTF8Encode(Command),
      UTF8Encode(StartupCommand(ExecutablePath))) = 0;
    Result := True;
  finally
    RegCloseKeyRaw(Key);
  end;
end;

function SetStartupEntry(const ExecutablePath: string; Enabled: Boolean;
  out ErrorText: string): Boolean;
var
  Key: HKEY;
  Command: UnicodeString;
  Status: LongInt;
begin
  Result := False;
  ErrorText := '';
  if Enabled then
    Status := RegCreateKeyExWide(HKEY_CURRENT_USER, PWideChar(RunKeyPath),
      0, nil, 0, KEY_SET_VALUE, nil, Key, nil)
  else
    Status := RegOpenKeyExWide(HKEY_CURRENT_USER, PWideChar(RunKeyPath),
      0, KEY_SET_VALUE, Key);
  if not Enabled and (Status = ERROR_FILE_NOT_FOUND) then Exit(True);
  if Status <> ERROR_SUCCESS then
  begin
    ErrorText := RegistryError('Cannot update Windows startup settings', Status);
    Exit;
  end;
  try
    if Enabled then
    begin
      Command := StartupCommand(ExecutablePath);
      Status := RegSetValueExWide(Key, PWideChar(RunValueName), 0,
        REG_SZ, PByte(PWideChar(Command)),
        (Length(Command) + 1) * SizeOf(WideChar));
    end
    else
      Status := RegDeleteValueWide(Key, PWideChar(RunValueName));
    if not Enabled and (Status = ERROR_FILE_NOT_FOUND) then Status := ERROR_SUCCESS;
    if Status <> ERROR_SUCCESS then
    begin
      ErrorText := RegistryError('Cannot update App Limiter startup entry', Status);
      Exit;
    end;
    Result := True;
  finally
    RegCloseKeyRaw(Key);
  end;
end;

end.
