program icon_probe;

{$mode objfpc}{$H+}
{$R ..\panel\AppLimiterIcon.res}
{$R ..\panel\app_limiter.res}

uses
  SysUtils, Interfaces, Forms, ExtCtrls, mainform;

var
  Form: TMainForm;
  I: Integer;
begin
  try
    Application.Title := 'App Limiter';
    Application.Scaled := True;
    Application.Initialize;
    Application.Icon.SaveToFile('acceptance\icon_runtime_application.ico');
    Form := TMainForm.Create(nil);
    try
      Form.Icon.SaveToFile('acceptance\icon_runtime_form.ico');
      for I := 0 to Form.ComponentCount - 1 do
        if Form.Components[I] is TTrayIcon then
          TTrayIcon(Form.Components[I]).Icon.SaveToFile(
            'acceptance\icon_runtime_tray.ico');
    finally
      Form.Free;
    end;
    WriteLn('Runtime icons captured.');
  except
    on E: Exception do
    begin
      WriteLn('Icon probe failed: ', E.Message);
      Halt(1);
    end;
  end;
end.
