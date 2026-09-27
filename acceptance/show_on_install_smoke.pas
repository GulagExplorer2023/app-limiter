program show_on_install_smoke;

{$mode objfpc}{$H+}
{$R ..\panel\app_limiter.res}

uses
  SysUtils, Interfaces, Forms, mainform, limiter_data;

var
  Settings: TSettings;
  Rules: TRules;
  Form: TMainForm;
  ErrorText: string;
  ShowRequested: Boolean;
begin
  try
    ShowRequested := (ParamCount = 1) and (ParamStr(1) = '--show');
    Settings := DefaultSettings;
    Settings.StartMinimized := True;
    SetLength(Rules, 0);
    if not SaveConfig(ConfigPath, Settings, Rules, ErrorText) then
      raise Exception.Create(ErrorText);
    Application.Scaled := True;
    Application.Initialize;
    Form := TMainForm.Create(nil);
    try
      if Application.ShowMainForm <> ShowRequested then
        raise Exception.Create('Installer show flag did not override startup minimization');
    finally
      Form.Free;
    end;
    WriteLn('Installer show override check passed.');
  except
    on E: Exception do
    begin
      WriteLn('Installer show override failure: ', E.Message);
      Halt(1);
    end;
  end;
end.
