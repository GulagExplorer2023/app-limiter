unit activity_export;

{$mode objfpc}{$H+}

interface

type
  TActivityExportRow = record
    Day, Name, Address, Source: string;
    DownloadBytes, UploadBytes: Int64;
  end;
  TActivityExportRows = array of TActivityExportRow;

procedure WriteActivityWorkbook(const FileName, AppPath: string;
  const Rows: TActivityExportRows);

implementation

uses
  Classes, SysUtils, Windows, Zipper;

const
  ContentTypesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
    '<Default Extension="xml" ContentType="application/xml"/>' +
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
    '</Types>';
  PackageRelsXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
    '</Relationships>';
  WorkbookXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' +
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
    '<sheets><sheet name="Activity" sheetId="1" r:id="rId1"/></sheets></workbook>';
  WorkbookRelsXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
    '</Relationships>';
  StylesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>' +
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
    '<fills count="2"><fill><patternFill patternType="none"/></fill>' +
    '<fill><patternFill patternType="gray125"/></fill></fills>' +
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
    '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>' +
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>' +
    '</styleSheet>';
  MoveFileReplaceExisting = 1;
  MoveFileWriteThrough = 8;

function MoveFileExW(OldName, NewName: PWideChar; Flags: DWORD): BOOL;
  stdcall; external 'kernel32.dll';

function DecodeText(const Value: string): UnicodeString;
var
  Count: Integer;
  CodePage, Flags: LongWord;
begin
  Result := '';
  if Value = '' then Exit;
  CodePage := CP_UTF8;
  Flags := MB_ERR_INVALID_CHARS;
  Count := MultiByteToWideChar(CodePage, Flags, PAnsiChar(Value),
    Length(Value), nil, 0);
  if Count = 0 then
  begin
    // Lazarus data is UTF-8, but a system-codepage string can enter from a
    // caller or an older config. Keep that text readable in the workbook.
    CodePage := CP_ACP;
    Flags := 0;
    Count := MultiByteToWideChar(CodePage, Flags, PAnsiChar(Value),
      Length(Value), nil, 0);
  end;
  if Count = 0 then Exit;
  SetLength(Result, Count);
  MultiByteToWideChar(CodePage, Flags, PAnsiChar(Value), Length(Value),
    PWideChar(Result), Count);
end;

function EscapeXml(const Value: string): UTF8String;
var
  Wide, Clean: UnicodeString;
  I: Integer;
  C: WideChar;
begin
  Wide := DecodeText(Value);
  Clean := '';
  for I := 1 to Length(Wide) do
  begin
    C := Wide[I];
    case C of
      '&': Clean := Clean + '&amp;';
      '<': Clean := Clean + '&lt;';
      '>': Clean := Clean + '&gt;';
      '"': Clean := Clean + '&quot;';
      '''': Clean := Clean + '&apos;';
    else
      if (Ord(C) >= 32) or (C = #9) or (C = #10) or (C = #13) then
        Clean := Clean + C;
    end;
  end;
  Result := UTF8Encode(Clean);
end;

procedure WriteText(Stream: TStream; const Value: string);
begin
  if Value <> '' then Stream.WriteBuffer(Value[1], Length(Value));
end;

procedure WriteStringCell(Stream: TStream; const Column: Char;
  Row: Integer; const Value: string; Header: Boolean = False);
var
  Style: string;
  Escaped: UTF8String;
begin
  if Header then Style := ' s="1"' else Style := '';
  WriteText(Stream, '<c r="' + Column + IntToStr(Row) +
    '" t="inlineStr"' + Style + '><is><t xml:space="preserve">');
  Escaped := EscapeXml(Value);
  if Escaped <> '' then Stream.WriteBuffer(Escaped[1], Length(Escaped));
  WriteText(Stream, '</t></is></c>');
end;

procedure WriteNumberCell(Stream: TStream; const Column: Char;
  Row: Integer; Value: Int64);
begin
  // Excel stores numbers as doubles. Keep unusually large counters exact.
  if (Value > 999999999999999) or (Value < -999999999999999) then
    WriteStringCell(Stream, Column, Row, IntToStr(Value))
  else
    WriteText(Stream, '<c r="' + Column + IntToStr(Row) + '"><v>' +
      IntToStr(Value) + '</v></c>');
end;

function SheetStream(const AppPath: string;
  const Rows: TActivityExportRows): TMemoryStream;
const
  Headers: array[0..6] of string =
    ('App', 'Day', 'Domain or IP', 'Remote IP', 'Source',
     'Download bytes', 'Upload bytes');
var
  I, J, RowNumber: Integer;
begin
  Result := TMemoryStream.Create;
  try
    WriteText(Result, '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
      '<dimension ref="A1:G' + IntToStr(Length(Rows) + 1) + '"/>' +
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" ' +
      'topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' +
      '<sheetFormatPr defaultRowHeight="15"/>' +
      '<cols><col min="1" max="1" width="52" customWidth="1"/>' +
      '<col min="2" max="2" width="14" customWidth="1"/>' +
      '<col min="3" max="3" width="38" customWidth="1"/>' +
      '<col min="4" max="4" width="30" customWidth="1"/>' +
      '<col min="5" max="5" width="18" customWidth="1"/>' +
      '<col min="6" max="7" width="18" customWidth="1"/></cols><sheetData>' +
      '<row r="1">');
    for J := 0 to High(Headers) do
      WriteStringCell(Result, Chr(Ord('A') + J), 1, Headers[J], True);
    WriteText(Result, '</row>');
    for I := 0 to High(Rows) do
    begin
      RowNumber := I + 2;
      WriteText(Result, '<row r="' + IntToStr(RowNumber) + '">');
      WriteStringCell(Result, 'A', RowNumber, AppPath);
      WriteStringCell(Result, 'B', RowNumber, Rows[I].Day);
      WriteStringCell(Result, 'C', RowNumber, Rows[I].Name);
      WriteStringCell(Result, 'D', RowNumber, Rows[I].Address);
      WriteStringCell(Result, 'E', RowNumber, Rows[I].Source);
      WriteNumberCell(Result, 'F', RowNumber, Rows[I].DownloadBytes);
      WriteNumberCell(Result, 'G', RowNumber, Rows[I].UploadBytes);
      WriteText(Result, '</row>');
    end;
    WriteText(Result, '</sheetData><autoFilter ref="A1:G' +
      IntToStr(Length(Rows) + 1) + '"/></worksheet>');
    Result.Position := 0;
  except
    Result.Free;
    raise;
  end;
end;

procedure WriteActivityWorkbook(const FileName, AppPath: string;
  const Rows: TActivityExportRows);
var
  Parts: array[0..5] of TStream;
  Zip: TZipper;
  Output: TFileStream;
  TempName: string;
  WideTemp, WideTarget: UnicodeString;
  I: Integer;
begin
  if CompareText(ExtractFileExt(FileName), '.xlsx') <> 0 then
    raise Exception.Create('Choose an .xlsx file name');
  if Length(Rows) >= 1048576 then
    raise Exception.Create('Too many rows for an Excel worksheet');
  for I := 0 to High(Parts) do Parts[I] := nil;
  Zip := nil;
  TempName := FileName + '.tmp';
  try
    try
      Parts[0] := TStringStream.Create(ContentTypesXml);
      Parts[1] := TStringStream.Create(PackageRelsXml);
      Parts[2] := TStringStream.Create(WorkbookXml);
      Parts[3] := TStringStream.Create(WorkbookRelsXml);
      Parts[4] := TStringStream.Create(StylesXml);
      Parts[5] := SheetStream(AppPath, Rows);
      Zip := TZipper.Create;
      Zip.Entries.AddFileEntry(Parts[0], '[Content_Types].xml');
      Zip.Entries.AddFileEntry(Parts[1], '_rels/.rels');
      Zip.Entries.AddFileEntry(Parts[2], 'xl/workbook.xml');
      Zip.Entries.AddFileEntry(Parts[3], 'xl/_rels/workbook.xml.rels');
      Zip.Entries.AddFileEntry(Parts[4], 'xl/styles.xml');
      Zip.Entries.AddFileEntry(Parts[5], 'xl/worksheets/sheet1.xml');
      Output := TFileStream.Create(TempName, fmCreate);
      try
        Zip.SaveToStream(Output);
      finally
        Output.Free;
      end;
      WideTemp := DecodeText(TempName);
      WideTarget := DecodeText(FileName);
      if not MoveFileExW(PWideChar(WideTemp), PWideChar(WideTarget),
        MoveFileReplaceExisting or MoveFileWriteThrough) then
        raise Exception.CreateFmt('Could not save Excel workbook (%d)',
          [GetLastError]);
    except
      SysUtils.DeleteFile(TempName);
      raise;
    end;
  finally
    Zip.Free;
    for I := 0 to High(Parts) do Parts[I].Free;
  end;
end;

end.
