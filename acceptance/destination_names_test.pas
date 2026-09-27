program destination_names_test;

{$mode objfpc}{$H+}

uses SysUtils, destination_names, windivert_api;

procedure Check(const Actual, Expected: string);
begin
  if Actual <> Expected then
    raise Exception.CreateFmt('Expected "%s", got "%s"', [Expected, Actual]);
end;

var
  DNS, TLS: TBytes;
  Answers: TDNSAnswers;
  HTTP: AnsiString;
  IP: TIPAddress;
  Host: AnsiString;
  I, N: Integer;
begin
  Host := 'google.com';
  N := Length(Host);
  SetLength(TLS, 61 + N);
  FillChar(TLS[0], Length(TLS), 0);
  TLS[0] := $16; TLS[1] := $03; TLS[2] := $01;
  TLS[3] := 0; TLS[4] := 56 + N;
  TLS[5] := $01; TLS[8] := 52 + N;
  TLS[9] := $03; TLS[10] := $03;
  TLS[44] := 0; TLS[45] := 2;
  TLS[46] := $13; TLS[47] := $01;
  TLS[48] := 1; TLS[49] := 0;
  TLS[50] := 0; TLS[51] := 9 + N;
  TLS[52] := 0; TLS[53] := 0;
  TLS[54] := 0; TLS[55] := 5 + N;
  TLS[56] := 0; TLS[57] := 3 + N;
  TLS[58] := 0; TLS[59] := 0; TLS[60] := N;
  for I := 1 to N do TLS[60 + I] := Ord(Host[I]);
  Check(TLSHostName(@TLS[0], Length(TLS)), 'google.com');
  Check(TLSHostName(@TLS[0], Length(TLS) - 1), '');

  SetLength(DNS, 12 + 1 + 6 + 1 + 3 + 1 + 2 + 1 + 4);
  FillChar(DNS[0], Length(DNS), 0);
  DNS[5] := 1;
  DNS[12] := 6;
  for I := 1 to 6 do DNS[12 + I] := Ord('google'[I]);
  DNS[19] := 3; DNS[20] := Ord('c'); DNS[21] := Ord('o');
  DNS[22] := Ord('m'); DNS[23] := 0;
  DNS[24] := 0; DNS[25] := 1; DNS[26] := 0; DNS[27] := 1;
  Check(DNSQueryName(@DNS[0], Length(DNS), False), 'google.com');
  Check(DNSQueryName(@DNS[0], 15, False), '');
  SetLength(DNS, 44);
  DNS[2] := $81; DNS[3] := $80; DNS[7] := 1;
  DNS[28] := $c0; DNS[29] := $0c;
  DNS[30] := 0; DNS[31] := 1;
  DNS[32] := 0; DNS[33] := 1;
  DNS[34] := 0; DNS[35] := 0; DNS[36] := 0; DNS[37] := 60;
  DNS[38] := 0; DNS[39] := 4;
  DNS[40] := 142; DNS[41] := 250; DNS[42] := 72; DNS[43] := 46;
  Answers := DNSResponseAnswers(@DNS[0], Length(DNS), False);
  if Length(Answers) <> 1 then
    raise Exception.Create('Expected one DNS answer');
  Check(Answers[0].Name, 'google.com');
  Check(Answers[0].Address, '142.250.72.46');
  Answers := DNSResponseAnswers(@DNS[0], Length(DNS) - 1, False);
  if Length(Answers) <> 0 then
    raise Exception.Create('Truncated DNS answer was accepted');

  HTTP := 'GET / HTTP/1.1'#13#10'Host: Google.com'#13#10#13#10;
  Check(HTTPHostName(PByte(@HTTP[1]), Length(HTTP)), 'google.com');
  HTTP := 'HTTP/1.1 200 OK'#13#10'Host: Google.com'#13#10#13#10;
  Check(HTTPHostName(PByte(@HTTP[1]), Length(HTTP)), '');

  FillChar(IP, SizeOf(IP), 0);
  IP[0] := $8eFA482E;
  Check(IPText(IP, False), '142.250.72.46');
  WriteLn('Destination name parser checks passed.');
end.
