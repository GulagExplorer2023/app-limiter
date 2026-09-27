program activity_export_test;

{$mode objfpc}{$H+}
{$codepage utf8}

uses
  SysUtils, activity_export;

var
  Rows: TActivityExportRows;
begin
  if ParamCount <> 1 then Halt(2);
  SetLength(Rows, 2);
  Rows[0].Day := '2026-09-27';
  Rows[0].Name := '=test<&" café';
  Rows[0].Address := '2001:db8::1';
  Rows[0].Source := 'TLS SNI';
  Rows[0].DownloadBytes := 4096;
  Rows[0].UploadBytes := 1024;
  Rows[1].Day := '2026-09-26';
  Rows[1].Name := 'example.org';
  Rows[1].Address := '192.0.2.1';
  Rows[1].Source := 'IP';
  Rows[1].DownloadBytes := 1234567890123456789;
  Rows[1].UploadBytes := 0;
  WriteActivityWorkbook(ParamStr(1), 'C:\Apps\firefox.exe', Rows);
  WriteLn('Excel activity workbook written.');
end.
