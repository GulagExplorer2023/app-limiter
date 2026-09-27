program startup_entry_test;

{$mode objfpc}{$H+}

uses
  SysUtils, startup_entry;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

var
  Path, OtherPath, ErrorText: string;
  Enabled, Exists: Boolean;
begin
  Path := 'C:\Program Files\AppLimiter\AppLimiter.exe';
  OtherPath := 'C:\Other Folder\AppLimiter.exe';
  Check(SetStartupEntry(Path, False, ErrorText), ErrorText);
  try
    Check(ReadStartupEntry(Path, Enabled, Exists, ErrorText), ErrorText);
    Check(not Enabled and not Exists, 'Startup entry should begin absent');
    Check(SetStartupEntry(Path, True, ErrorText), ErrorText);
    Check(ReadStartupEntry(Path, Enabled, Exists, ErrorText), ErrorText);
    Check(Enabled and Exists, 'Expected matching startup entry');
    Check(ReadStartupEntry(OtherPath, Enabled, Exists, ErrorText), ErrorText);
    Check(not Enabled and Exists, 'Different executable path was accepted');
    Check(SetStartupEntry(Path, False, ErrorText), ErrorText);
    Check(ReadStartupEntry(Path, Enabled, Exists, ErrorText), ErrorText);
    Check(not Enabled and not Exists, 'Startup entry was not removed');
  finally
    SetStartupEntry(Path, False, ErrorText);
  end;
  WriteLn('Per-user startup registry checks passed.');
end.
