unit parental_pin;

{$mode objfpc}{$H+}

interface

function ValidPin(const Pin: string): Boolean;
function ValidPinVerifier(const Verifier: string): Boolean;
function NewPinVerifier(const Pin: string): string;
function VerifyPin(const Pin, Verifier: string): Boolean;

implementation

uses
  SysUtils, Windows;

const
  SaltLength = 16;
  KeyLength = 32;
  Iterations = 100000;
  BCryptUseSystemPreferredRng = 2;
  BCryptAlgHandleHmacFlag = 8;

function BCryptOpenAlgorithmProvider(out Algorithm: THandle;
  AlgorithmId, ProviderName: PWideChar; Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll';
function BCryptCloseAlgorithmProvider(Algorithm: THandle;
  Flags: ULONG): LongInt; stdcall; external 'bcrypt.dll';
function BCryptGenRandom(Algorithm: THandle; Buffer: PByte;
  BufferLength, Flags: ULONG): LongInt; stdcall; external 'bcrypt.dll';
function BCryptDeriveKeyPBKDF2(Algorithm: THandle; Password: PByte;
  PasswordLength: ULONG; Salt: PByte; SaltSize: ULONG;
  IterationCount: QWord; DerivedKey: PByte; DerivedKeyLength,
  Flags: ULONG): LongInt; stdcall; external 'bcrypt.dll';

function ValidPin(const Pin: string): Boolean;
var
  I: Integer;
begin
  Result := (Length(Pin) >= 6) and (Length(Pin) <= 12);
  if not Result then Exit;
  for I := 1 to Length(Pin) do
    if not (Pin[I] in ['0'..'9']) then Exit(False);
end;

function HexNibble(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function ValidPinVerifier(const Verifier: string): Boolean;
var
  I: Integer;
begin
  Result := (Length(Verifier) = 2 * (SaltLength + KeyLength));
  if not Result then Exit;
  for I := 1 to Length(Verifier) do
    if HexNibble(Verifier[I]) < 0 then Exit(False);
end;

function ToHex(const Bytes; Count: Integer): string;
const
  Digits = '0123456789abcdef';
var
  I: Integer;
  P: PByte;
begin
  SetLength(Result, Count * 2);
  P := @Bytes;
  for I := 0 to Count - 1 do
  begin
    Result[I * 2 + 1] := Digits[(P[I] shr 4) + 1];
    Result[I * 2 + 2] := Digits[(P[I] and 15) + 1];
  end;
end;

procedure FromHex(const Value: string; var Bytes; Count: Integer);
var
  I: Integer;
  P: PByte;
begin
  P := @Bytes;
  for I := 0 to Count - 1 do
    P[I] := (HexNibble(Value[I * 2 + 1]) shl 4) or
      HexNibble(Value[I * 2 + 2]);
end;

procedure Derive(const Pin: string; const Salt: array of Byte;
  out Key: array of Byte);
var
  Algorithm: THandle;
  Status: LongInt;
begin
  Algorithm := 0;
  Status := BCryptOpenAlgorithmProvider(Algorithm, PWideChar(UnicodeString('SHA256')),
    nil, BCryptAlgHandleHmacFlag);
  if Status < 0 then raise Exception.Create('Cannot initialize PIN protection');
  try
    Status := BCryptDeriveKeyPBKDF2(Algorithm, PByte(PAnsiChar(Pin)),
      Length(Pin), @Salt[0], Length(Salt), Iterations, @Key[0],
      Length(Key), 0);
    if Status < 0 then raise Exception.Create('Cannot protect the PIN');
  finally
    BCryptCloseAlgorithmProvider(Algorithm, 0);
  end;
end;

function NewPinVerifier(const Pin: string): string;
var
  Salt: array[0..SaltLength - 1] of Byte;
  Key: array[0..KeyLength - 1] of Byte;
begin
  if not ValidPin(Pin) then
    raise Exception.Create('PIN must contain 6 to 12 digits');
  if BCryptGenRandom(0, @Salt[0], SizeOf(Salt),
    BCryptUseSystemPreferredRng) < 0 then
    raise Exception.Create('Cannot create a secure PIN salt');
  Derive(Pin, Salt, Key);
  Result := ToHex(Salt, SizeOf(Salt)) + ToHex(Key, SizeOf(Key));
  FillChar(Key, SizeOf(Key), 0);
end;

function VerifyPin(const Pin, Verifier: string): Boolean;
var
  Salt: array[0..SaltLength - 1] of Byte;
  Expected, Actual: array[0..KeyLength - 1] of Byte;
  I, Difference: Integer;
begin
  Result := False;
  if not ValidPin(Pin) or not ValidPinVerifier(Verifier) then Exit;
  FromHex(Copy(Verifier, 1, SaltLength * 2), Salt, SaltLength);
  FromHex(Copy(Verifier, SaltLength * 2 + 1, KeyLength * 2),
    Expected, KeyLength);
  Derive(Pin, Salt, Actual);
  Difference := 0;
  for I := 0 to High(Actual) do
    Difference := Difference or (Actual[I] xor Expected[I]);
  Result := Difference = 0;
  FillChar(Actual, SizeOf(Actual), 0);
end;

end.
