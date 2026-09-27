program parental_pin_test;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, parental_pin, limiter_data;

procedure Check(Condition: Boolean; const Failure: string);
begin
  if not Condition then raise Exception.Create(Failure);
end;

var
  First, Second, ErrorText: string;
  Settings, Reloaded: TSettings;
  Rules, LoadedRules: TRules;
  Text: TStringList;
begin
  if ParamCount <> 1 then Halt(2);
  Check(not ValidPin('1234'), 'Short PIN accepted');
  Check(not ValidPin('12345a'), 'Nonnumeric PIN accepted');
  Check(ValidPin('123456'), 'Six digit PIN rejected');
  First := NewPinVerifier('123456');
  Second := NewPinVerifier('123456');
  Check(ValidPinVerifier(First) and ValidPinVerifier(Second),
    'PIN verifier format is invalid');
  Check(First <> Second, 'Salt was not randomized');
  Check(VerifyPin('123456', First), 'Correct PIN rejected');
  Check(not VerifyPin('654321', First), 'Wrong PIN accepted');
  Check(not VerifyPin('123456', Copy(First, 1, Length(First) - 1) + 'g'),
    'Malformed verifier accepted');
  Settings := DefaultSettings;
  Settings.ParentalMode := True;
  SetLength(Rules, 0);
  Check(not SaveConfig(ParamStr(1), Settings, Rules, ErrorText),
    'Parental mode saved without a PIN');
  Settings.PinVerifier := First;
  Check(SaveConfig(ParamStr(1), Settings, Rules, ErrorText), ErrorText);
  Check(LoadConfig(ParamStr(1), Reloaded, LoadedRules, ErrorText), ErrorText);
  Check(Reloaded.ParentalMode and (Reloaded.PinVerifier = First),
    'PIN protection did not survive config reload');
  Check(VerifyPin('123456', Reloaded.PinVerifier), 'Reloaded PIN failed');
  Text := TStringList.Create;
  try
    Text.LoadFromFile(ParamStr(1));
    Check(Pos('123456', Text.Text) = 0, 'Plain PIN leaked into config');
    Text.Text := '{"version":1,"parentalMode":true,' +
      '"hotkey":"Ctrl+Alt+N","rules":[]}';
    Text.SaveToFile(ParamStr(1));
  finally
    Text.Free;
  end;
  Check(LoadConfig(ParamStr(1), Reloaded, LoadedRules, ErrorText), ErrorText);
  Check(not Reloaded.ParentalMode,
    'Legacy parental mode without PIN must require setup again');
  WriteLn('Parental PIN checks passed.');
end.
