program instance_control_test;

{$mode objfpc}{$H+}

uses
  SysUtils, Process, instance_control;

procedure Check(Condition: Boolean; const Failure: string);
begin
  if not Condition then raise Exception.Create(Failure);
end;

var
  FirstInstance: Boolean;
  ErrorText: string;
  Child: TProcess;
begin
  Check(BeginPanelInstance(FirstInstance, ErrorText), ErrorText);
  try
    if (ParamCount > 0) and (ParamStr(1) = 'child') then
    begin
      Check(not FirstInstance, 'Second process was allowed as primary');
      Check(NotifyRunningPanel, 'Second process could not notify first');
      Exit;
    end;
    Check(FirstInstance, 'Primary process was rejected');
    Child := TProcess.Create(nil);
    try
      Child.Executable := ParamStr(0);
      Child.Parameters.Add('child');
      Child.Options := [poWaitOnExit];
      Child.Execute;
      Check(Child.ExitStatus = 0, 'Second process failed');
    finally
      Child.Free;
    end;
    Check(OpenRequestPending, 'First process missed launch request');
    Check(not OpenRequestPending, 'Launch request was repeated');
    WriteLn('Single-instance launch request passed.');
  finally
    EndPanelInstance;
  end;
end.
