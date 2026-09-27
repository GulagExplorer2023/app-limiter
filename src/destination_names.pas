unit destination_names;

{$mode objfpc}{$H+}

interface

uses windivert_api;

type
  TDNSAnswer = record
    Name, Address: string;
    TTL: LongWord;
  end;
  TDNSAnswers = array of TDNSAnswer;

function IPText(const Address: TIPAddress; IPv6: Boolean): string;
function DNSQueryName(Data: PByte; DataLength: LongWord;
  IsTCP: Boolean): string;
function DNSResponseAnswers(Data: PByte; DataLength: LongWord;
  IsTCP: Boolean): TDNSAnswers;
function TLSHostName(Data: PByte; DataLength: LongWord): string;
function HTTPHostName(Data: PByte; DataLength: LongWord): string;

implementation

uses SysUtils;

function IPText(const Address: TIPAddress; IPv6: Boolean): string;
var
  I: Integer;
  Part: LongWord;
begin
  if not IPv6 then
    Exit(Format('%d.%d.%d.%d', [(Address[0] shr 24) and $ff,
      (Address[0] shr 16) and $ff, (Address[0] shr 8) and $ff,
      Address[0] and $ff]));
  Result := '';
  for I := 3 downto 0 do
  begin
    Part := Address[I];
    if Result <> '' then Result := Result + ':';
    Result := Result + LowerCase(IntToHex((Part shr 16) and $ffff, 4)) + ':' +
      LowerCase(IntToHex(Part and $ffff, 4));
  end;
end;

function Read16(Data: PByte; Offset: LongWord): LongWord;
begin
  Result := (LongWord(Data[Offset]) shl 8) or Data[Offset + 1];
end;

function ValidHost(const Value: string): Boolean;
var
  I: Integer;
begin
  Result := (Length(Value) > 0) and (Length(Value) <= 253) and
    (Value[1] <> '.') and (Value[Length(Value)] <> '.');
  if not Result then Exit;
  for I := 1 to Length(Value) do
    if not (Value[I] in ['a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_']) then
      Exit(False);
end;

function DNSQueryName(Data: PByte; DataLength: LongWord;
  IsTCP: Boolean): string;
var
  Offset, LabelLength, I, EndPos: LongWord;
  LabelText: string;
begin
  Result := '';
  if Data = nil then Exit;
  Offset := 0;
  if IsTCP then
  begin
    if DataLength < 14 then Exit;
    if Read16(Data, 0) + 2 > DataLength then Exit;
    Offset := 2;
  end;
  if DataLength - Offset < 17 then Exit;
  if (Data[Offset + 2] and $80 <> 0) or
    (Read16(Data, Offset + 4) = 0) then Exit;
  EndPos := DataLength;
  Inc(Offset, 12);
  while Offset < EndPos do
  begin
    LabelLength := Data[Offset];
    Inc(Offset);
    if LabelLength = 0 then
    begin
      if (Offset + 4 > EndPos) or not ValidHost(Result) then Result := '';
      Exit;
    end;
    if (LabelLength > 63) or (Offset + LabelLength > EndPos) or
      (Length(Result) + LabelLength + 1 > 253) then Exit('');
    SetLength(LabelText, LabelLength);
    for I := 0 to LabelLength - 1 do
      LabelText[I + 1] := Char(Data[Offset + I]);
    if Result <> '' then Result := Result + '.';
    Result := Result + LowerCase(LabelText);
    Inc(Offset, LabelLength);
  end;
  Result := '';
end;

function ReadDNSName(Data: PByte; DataLength, Base: LongWord;
  var Offset: LongWord): string;
var
  Posn, NextPos, Size, J, Hops: LongWord;
  LabelText: string;
begin
  Result := '';
  Posn := Offset;
  NextPos := 0;
  Hops := 0;
  while Posn < DataLength do
  begin
    Inc(Hops);
    if Hops > 128 then Exit('');
    Size := Data[Posn];
    if Size = 0 then
    begin
      if NextPos = 0 then Offset := Posn + 1 else Offset := NextPos;
      if not ValidHost(Result) then Result := '';
      Exit;
    end;
    if (Size and $C0) = $C0 then
    begin
      if Posn + 1 >= DataLength then Exit('');
      if NextPos = 0 then NextPos := Posn + 2;
      Posn := Base + (((Size and $3F) shl 8) or Data[Posn + 1]);
      Continue;
    end;
    if (Size > 63) or (Posn + 1 + Size > DataLength) or
      (Length(Result) + Size + 1 > 253) then Exit('');
    SetLength(LabelText, Size);
    for J := 0 to Size - 1 do
      LabelText[J + 1] := Char(Data[Posn + 1 + J]);
    if Result <> '' then Result := Result + '.';
    Result := Result + LowerCase(LabelText);
    Inc(Posn, 1 + Size);
  end;
  Result := '';
end;

function DNSResponseAnswers(Data: PByte; DataLength: LongWord;
  IsTCP: Boolean): TDNSAnswers;
var
  Base, Offset, Count, I, Kind, DataSize, J: LongWord;
  QueryName, CurrentName, AnswerName, AddressText: string;
  AliasOffset: LongWord;
begin
  Result := nil;
  if Data = nil then Exit;
  Base := 0;
  if IsTCP then
  begin
    if DataLength < 14 then Exit;
    if Read16(Data, 0) + 2 > DataLength then Exit;
    Base := 2;
  end;
  if DataLength < Base + 12 then Exit;
  if (Data[Base + 2] and $80 = 0) or
    (Data[Base + 3] and $0F <> 0) or
    (Read16(Data, Base + 4) = 0) then Exit;
  Count := Read16(Data, Base + 6);
  if Count > 128 then Count := 128;
  Offset := Base + 12;
  QueryName := ReadDNSName(Data, DataLength, Base, Offset);
  if (QueryName = '') or (Offset + 4 > DataLength) then Exit;
  CurrentName := QueryName;
  Inc(Offset, 4);
  for I := 0 to Count - 1 do
  begin
    AnswerName := ReadDNSName(Data, DataLength, Base, Offset);
    if (AnswerName = '') or (Offset + 10 > DataLength) then Exit;
    Kind := Read16(Data, Offset);
    DataSize := Read16(Data, Offset + 8);
    if Offset + 10 + DataSize > DataLength then Exit;
    AddressText := '';
    if (Read16(Data, Offset + 2) = 1) and
      (Kind = 5) and (AnswerName = CurrentName) then
    begin
      AliasOffset := Offset + 10;
      CurrentName := ReadDNSName(Data, DataLength, Base, AliasOffset);
    end;
    if (Read16(Data, Offset + 2) = 1) and
      (AnswerName = CurrentName) then
    begin
      if (Kind = 1) and (DataSize = 4) then
        AddressText := Format('%d.%d.%d.%d', [Data[Offset + 10],
          Data[Offset + 11], Data[Offset + 12], Data[Offset + 13]])
      else if (Kind = 28) and (DataSize = 16) then
        for J := 0 to 7 do
        begin
          if J > 0 then AddressText := AddressText + ':';
          AddressText := AddressText + LowerCase(IntToHex(
            Read16(Data, Offset + 10 + J * 2), 4));
        end;
    end;
    if AddressText <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Name := QueryName;
      Result[High(Result)].Address := AddressText;
      Result[High(Result)].TTL :=
        (LongWord(Read16(Data, Offset + 4)) shl 16) or
        Read16(Data, Offset + 6);
    end;
    Inc(Offset, 10 + DataSize);
  end;
end;

function TLSHostName(Data: PByte; DataLength: LongWord): string;
var
  Limit, HandshakeEnd, Posn, ExtensionEnd, NameEnd: LongWord;
  I: LongWord;
begin
  Result := '';
  if (Data = nil) or (DataLength < 52) then Exit;
  if (Data[0] <> $16) or (Data[1] <> $03) or (Data[5] <> $01) then Exit;
  Limit := 5 + Read16(Data, 3);
  if Limit > DataLength then Exit;
  HandshakeEnd := 9 + (LongWord(Data[6]) shl 16) +
    (LongWord(Data[7]) shl 8) + Data[8];
  if HandshakeEnd > Limit then Exit;
  Posn := 9 + 2 + 32;
  if Posn + 1 > HandshakeEnd then Exit;
  Inc(Posn, 1 + Data[Posn]); // session ID
  if Posn + 2 > HandshakeEnd then Exit;
  Inc(Posn, 2 + Read16(Data, Posn)); // cipher suites
  if Posn + 1 > HandshakeEnd then Exit;
  Inc(Posn, 1 + Data[Posn]); // compression methods
  if Posn + 2 > HandshakeEnd then Exit;
  ExtensionEnd := Posn + 2 + Read16(Data, Posn);
  Inc(Posn, 2);
  if ExtensionEnd > HandshakeEnd then Exit;
  while Posn + 4 <= ExtensionEnd do
  begin
    NameEnd := Posn + 4 + Read16(Data, Posn + 2);
    if NameEnd > ExtensionEnd then Exit;
    if (Read16(Data, Posn) = 0) and (NameEnd >= Posn + 9) then
    begin
      Inc(Posn, 6); // extension header and server-name list length
      if (Data[Posn] <> 0) or (Posn + 3 > NameEnd) then Exit;
      Limit := Read16(Data, Posn + 1);
      Inc(Posn, 3);
      if (Limit = 0) or (Posn + Limit > NameEnd) or (Limit > 253) then Exit;
      SetLength(Result, Limit);
      for I := 0 to Limit - 1 do Result[I + 1] := Char(Data[Posn + I]);
      Result := LowerCase(Result);
      if not ValidHost(Result) then Result := '';
      Exit;
    end;
    Posn := NameEnd;
  end;
end;

function HTTPHostName(Data: PByte; DataLength: LongWord): string;
var
  Text, Line: string;
  I, P, LineEnd: Integer;
begin
  Result := '';
  if (Data = nil) or (DataLength < 16) then Exit;
  if not (Char(Data[0]) in ['G', 'P', 'H', 'D', 'O']) then Exit;
  if DataLength > 8192 then DataLength := 8192;
  SetLength(Text, DataLength);
  for I := 0 to DataLength - 1 do Text[I + 1] := Char(Data[I]);
  P := Pos(#13#10, Text);
  if P = 0 then Exit;
  Line := UpperCase(Copy(Text, 1, P - 1));
  if (Pos('GET ', Line) <> 1) and (Pos('POST ', Line) <> 1) and
    (Pos('HEAD ', Line) <> 1) and (Pos('PUT ', Line) <> 1) and
    (Pos('PATCH ', Line) <> 1) and (Pos('DELETE ', Line) <> 1) and
    (Pos('OPTIONS ', Line) <> 1) then Exit;
  Inc(P, 2);
  while P <= Length(Text) do
  begin
    LineEnd := Pos(#13#10, Copy(Text, P, MaxInt));
    if LineEnd = 0 then Exit;
    Line := Copy(Text, P, LineEnd - 1);
    if Line = '' then Exit;
    if CompareText(Copy(Line, 1, 5), 'Host:') = 0 then
    begin
      Result := Trim(Copy(Line, 6, MaxInt));
      if Pos(':', Result) > 0 then
        Result := Copy(Result, 1, Pos(':', Result) - 1);
      Result := LowerCase(Result);
      if not ValidHost(Result) then Result := '';
      Exit;
    end;
    Inc(P, LineEnd + 1);
  end;
end;

end.
