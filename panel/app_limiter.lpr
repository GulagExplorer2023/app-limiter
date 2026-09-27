program app_limiter;

{$mode objfpc}{$H+}
{$IFDEF WINDOWS}{$APPTYPE GUI}{$ENDIF}
{$R AppLimiterIcon.res}
{$R app_limiter.res}

uses
  Interfaces, Forms, Dialogs, SysUtils, mainform, limiter_data,
  instance_control;

var
  FirstInstance: Boolean;
  ErrorText: string;
  Settings: TSettings;
  Rules: TRules;

begin
  Application.Title := 'App Limiter';
  Application.Scaled := True;
  Application.Initialize;
  if not BeginPanelInstance(FirstInstance, ErrorText) then
  begin
    MessageDlg('App Limiter', ErrorText, mtError, [mbOK], 0);
    Exit;
  end;
  try
    if not FirstInstance then
    begin
      if CompareText(ParamStr(1), '--startup') = 0 then Exit;
      if not LoadConfig(ConfigPath, Settings, Rules, ErrorText) then
        MessageDlg('App Limiter',
          'App Limiter is already running, but its settings could not be read: ' +
          ErrorText, mtError, [mbOK], 0)
      else if Settings.ParentalMode then
      begin
        if not NotifyRunningPanel then
          MessageDlg('App Limiter',
            'App Limiter is running, but its PIN window could not be opened.',
            mtError, [mbOK], 0);
      end
      else
        MessageDlg('App Limiter',
          'App Limiter is already running. Parental mode is off.',
          mtInformation, [mbOK], 0);
      Exit;
    end;
    Application.CreateForm(TMainForm, MainWindow);
    Application.Run;
  finally
    EndPanelInstance;
  end;
end.
