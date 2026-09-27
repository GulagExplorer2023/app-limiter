unit limiter_engine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, limiter_data, windivert_api, destination_names;

type
  TLimiterEngine = class;

  TEngineThread = class(TThread)
  protected
    Engine: TLimiterEngine;
  public
    constructor Create(AEngine: TLimiterEngine);
  end;

  TFlowThread = class(TEngineThread)
  protected
    procedure Execute; override;
  end;
  TNetworkThread = class(TEngineThread)
  protected
    procedure Execute; override;
  end;
  TSenderThread = class(TEngineThread)
  protected
    procedure Execute; override;
  end;
  TStatusThread = class(TEngineThread)
  protected
    procedure Execute; override;
  end;

  TAppEntry = record
    Path: string;
    DownloadBytes, UploadBytes: QWord;
    LocalDownloadBytes, LocalUploadBytes: QWord;
    WindowDown, WindowUp: QWord;
    RateDown, RateUp: QWord;
    LastPacketMs: QWord;
    RuleIndex: Integer;
    Uncertain: Boolean;
    QuotaUsed: QWord;
    QuotaKey: string;
    DayIndex: Integer;
  end;

  TAppProcess = record
    AppIndex: Integer;
    ProcessId: DWORD;
    StartTime: QWord;
    Handle: THandle;
  end;

  TFlowEntry = record
    Used, Tombstone: Boolean;
    EndpointId: QWord;
    Tuple: TFlowTuple;
    AppIndex: Integer;
    DestinationIndex: Integer;
    Scope: TTrafficScope;
    HistoryIndex: Integer;
  end;

  TDestinationEntry = record
    AppIndex: Integer;
    Name, Address, Source: string;
    Port: Word;
    Protocol: Byte;
    LastSeenMs: QWord;
    DownloadBytes, UploadBytes: QWord;
  end;

  TResolvedEntry = record
    Address, Name: string;
    ExpiresMs: QWord;
  end;

  TUsageDay = record
    Path, Day: string;
    DownloadBytes, UploadBytes: QWord;
  end;

  TUsageDestination = record
    Path, Day, Name, Address, Source: string;
    DownloadBytes, UploadBytes: QWord;
  end;

  PQueuedPacket = ^TQueuedPacket;
  TQueuedPacket = record
    Next: PQueuedPacket;
    AppIndex: Integer;
    Scope: TTrafficScope;
    DueUs: QWord;
    PacketLength: LongWord;
    Address: TDivertAddress;
    Packet: TBytes;
    Handle: THandle;
  end;

  TLimiterEngine = class
  {$ifdef LIMITER_TEST}
  public
  {$else}
  private
  {$endif}
    FConfigPath, FStatePath, FDestinationPath, FHistoryPath,
      FDiagnosticPath: string;
    FLock: TRTLCriticalSection;
    FLogLock: TRTLCriticalSection;
    FRunning: Boolean;
    FFlowHandle, FNetworkHandle: THandle;
    FFlowThread: TFlowThread;
    FNetworkThread: TNetworkThread;
    FSenderThread: TSenderThread;
    FStatusThread: TStatusThread;
    FSettings: TSettings;
    FActiveLimits: Boolean;
    FRules: TRules;
    FDueUs: array of array[0..1] of QWord;
    FGlobalDueUs: array[0..1] of QWord;
    FGlobalSessionDown, FGlobalSessionUp: QWord;
    FGlobalQuotaUsed: QWord;
    FGlobalQuotaKey: string;
    FGlobalDayIndex: Integer;
    FApps: array of TAppEntry;
    FAppProcesses: array of TAppProcess;
    FDestinations: array of TDestinationEntry;
    FResolved: array of TResolvedEntry;
    FUsageDays: array of TUsageDay;
    FUsageDestinations: array of TUsageDestination;
    FCurrentDay: string;
    FHistoryDirty: Boolean;
    FLastHistoryPublishMs: QWord;
    FDestinationsDropped: QWord;
    FDestinationsRevision, FPublishedDestinationsRevision: QWord;
    FLastDestinationsPublishMs: QWord;
    FFlows: array[0..32767] of TFlowEntry;
    FFlowTombstones: Integer;
    FFlowTableRebuilds, FFlowTableFull: QWord;
    FQueueHead, FQueueTail: array[0..1] of PQueuedPacket;
    FQueueEvent: THandle;
    FQueueBytes: LongWord;
    FSendInFlight: LongWord;
    FFlushQueue: Boolean;
    FLastStatus: string;
    FLastWindowMs: QWord;
    FUnattributedPackets, FDroppedPackets: QWord;
    FImmediatePackets, FQueuedPackets: QWord;
    function FindApp(const Path: string): Integer;
    function FindRule(const Path: string): Integer;
    function HasActiveLimits: Boolean;
    function EffectiveRate(AppIndex, RuleIndex, Direction: Integer): Int64;
    function GlobalEffectiveRate: Int64;
    function QuotaKey(const Rule: TRule): string;
    procedure UpdateQuota(AppIndex: Integer);
    procedure UpdateGlobalQuota;
    procedure PruneExitedProcesses;
    procedure RecordAppProcess(AppIndex: Integer; ProcessId: DWORD;
      ProcessHandle: THandle);
    function UsageDayIndex(const Path, Day: string): Integer;
    function UsageDestinationIndex(AppIndex, DestinationIndex: Integer): Integer;
    procedure LoadHistory;
    procedure PruneHistory;
    procedure LoadSessionCheckpoint;
    procedure WriteHistory(Force: Boolean);
    procedure RememberAnswers(const Answers: array of TDNSAnswer);
    function ResolvedName(const Address: string): string;
    function HashTuple(const Tuple: TFlowTuple): LongWord;
    function FlowSlot(const Tuple: TFlowTuple): Integer;
    procedure CompactFlows;
    function RecordDestination(AppIndex: Integer; const Name, Address,
      Source: string; Port: Word; Protocol: Byte): Integer;
    procedure AddFlow(const Address: TDivertAddress);
    procedure DeleteFlow(const Address: TDivertAddress);
    procedure ProcessPacket(const Address: TDivertAddress; Packet: Pointer;
      PacketLength: LongWord; Diverted: Boolean; Handle: THandle);
    function QueuePacket(RuleIndex, AppIndex, Direction: Integer;
      AppRate, GlobalRate: Int64;
      Scope: TTrafficScope; const Address: TDivertAddress; Packet: Pointer;
      PacketLength: LongWord; Handle: THandle): Boolean;
    procedure DrainQueue;
    procedure LoadRules;
    procedure WriteState;
    procedure WriteDestinations;
    procedure SetStatus(const Value: string);
    procedure LogDiagnostic(const Value: string);
  public
    constructor Create(const AConfigPath, AStatePath: string);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property Running: Boolean read FRunning;
  end;

implementation

uses
  fpjson, jsonparser;

const
  MaxApps = 1024;
  MaxDestinations = 16384;
  MaxResolved = 4096;
  MaxUsageDays = 30000;
  ReservedGlobalUsageDays = 100;
  MaxUsageDestinations = 20000;
  MaxQueueBytes = 4 * 1024 * 1024;
  MaxQueueDelayUs = 1500000;
  GlobalUsagePath = '<computer-wide>';
  ProcessSynchronize = $00100000;

  MaxFlowTombstones = 4096;
  CreateWaitableTimerHighResolution = 2;
  TimerAllAccess = $001F0003;
  ProcessQueryLimitedInformation = $1000;
  MoveFileReplaceExisting = 1;
  MoveFileWriteThrough = 8;

procedure AddCapped(var Value: QWord; Amount: QWord);
begin
  if (Value >= QWord(High(Int64))) or
    (Amount > QWord(High(Int64)) - Value) then
    Value := QWord(High(Int64))
  else Inc(Value, Amount);
end;

function QueryFullProcessImageNameW(Process: THandle; Flags: DWORD;
  Buffer: PWideChar; var Size: DWORD): BOOL; stdcall;
  external 'kernel32.dll';
function MoveFileExW(OldName, NewName: PWideChar; Flags: DWORD): BOOL;
  stdcall; external 'kernel32.dll';
function QueryPerformanceCounterRaw(var Count: Int64): BOOL;
  stdcall; external 'kernel32.dll' name 'QueryPerformanceCounter';
function QueryPerformanceFrequencyRaw(var Frequency: Int64): BOOL;
  stdcall; external 'kernel32.dll' name 'QueryPerformanceFrequency';
function CreateWaitableTimerExRaw(Attributes: Pointer; Name: PWideChar;
  Flags, DesiredAccess: DWORD): THandle;
  stdcall; external 'kernel32.dll' name 'CreateWaitableTimerExW';
function SetWaitableTimerRaw(Timer: THandle; DueTime: PInt64;
  Period: LongInt; CompletionRoutine, CompletionArgument: Pointer;
  Resume: BOOL): BOOL;
  stdcall; external 'kernel32.dll' name 'SetWaitableTimer';
function WaitForMultipleObjectsRaw(Count: DWORD; Handles: PHandle;
  WaitAll: BOOL; Milliseconds: DWORD): DWORD;
  stdcall; external 'kernel32.dll' name 'WaitForMultipleObjects';
function TimeBeginPeriodRaw(Period: LongWord): LongWord;
  stdcall; external 'winmm.dll' name 'timeBeginPeriod';
function TimeEndPeriodRaw(Period: LongWord): LongWord;
  stdcall; external 'winmm.dll' name 'timeEndPeriod';

function PublishTempFile(const TempPath, TargetPath: string;
  out ErrorCode: DWORD): Boolean;
var
  WideTemp, WideTarget: UnicodeString;
  Attempt: Integer;
begin
  WideTemp := UnicodeString(UTF8Decode(TempPath));
  WideTarget := UnicodeString(UTF8Decode(TargetPath));
  ErrorCode := 0;
  for Attempt := 1 to 12 do
  begin
    if MoveFileExW(PWideChar(WideTemp), PWideChar(WideTarget),
      MoveFileReplaceExisting or MoveFileWriteThrough) then Exit(True);
    ErrorCode := GetLastError;
    if (ErrorCode <> ERROR_SHARING_VIOLATION) and
      (ErrorCode <> ERROR_LOCK_VIOLATION) and
      (ErrorCode <> ERROR_ACCESS_DENIED) then Break;
    Sleep(25);
  end;
  Result := False;
end;

var
  PerformanceFrequency: Int64;

function NowUs: QWord;
var
  Counter: Int64;
begin
  if (PerformanceFrequency > 0) and QueryPerformanceCounterRaw(Counter) then
    Result := QWord(Counter div PerformanceFrequency) * 1000000 +
      QWord((Counter mod PerformanceFrequency) * 1000000 div
        PerformanceFrequency)
  else
    Result := GetTickCount64 * 1000;
end;

function ProcessPath(Pid: DWORD): string;
var
  Handle: THandle;
  Buffer: array[0..32767] of WideChar;
  Count: DWORD;
  WidePath: UnicodeString;
begin
  Result := '';
  Handle := OpenProcess(ProcessQueryLimitedInformation, False, Pid);
  if Handle = 0 then Exit;
  try
    Count := System.Length(Buffer);
    if QueryFullProcessImageNameW(Handle, 0, @Buffer[0], Count) then
    begin
      SetString(WidePath, PWideChar(@Buffer[0]), Count);
      Result := UTF8Encode(WidePath);
    end;
  finally
    CloseHandle(Handle);
  end;
end;

function ProcessStartTime(ProcessHandle: THandle): QWord;
var
  CreatedAt, ExitedAt, KernelTime, UserTime: TFileTime;
begin
  Result := 0;
  if (ProcessHandle <> 0) and GetProcessTimes(ProcessHandle,
    CreatedAt, ExitedAt, KernelTime, UserTime) then
    Result := (QWord(CreatedAt.dwHighDateTime) shl 32) or
      CreatedAt.dwLowDateTime;
end;

constructor TEngineThread.Create(AEngine: TLimiterEngine);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Engine := AEngine;
  Start;
end;

constructor TLimiterEngine.Create(const AConfigPath, AStatePath: string);
begin
  inherited Create;
  FConfigPath := AConfigPath;
  FStatePath := AStatePath;
  FDestinationPath := IncludeTrailingPathDelimiter(
    ExtractFileDir(AConfigPath)) + 'destinations.json';
  FHistoryPath := IncludeTrailingPathDelimiter(
    ExtractFileDir(AConfigPath)) + 'usage_history.json';
  FDiagnosticPath := IncludeTrailingPathDelimiter(
    ExtractFileDir(AStatePath)) + 'backend.log';
  FCurrentDay := FormatDateTime('yyyy-mm-dd', Date);
  FGlobalDayIndex := -1;
  FFlowHandle := INVALID_HANDLE_VALUE;
  FNetworkHandle := INVALID_HANDLE_VALUE;
  FSettings := DefaultSettings;
  FLastStatus := 'Starting backend';
  InitializeCriticalSection(FLock);
  InitializeCriticalSection(FLogLock);
  FQueueEvent := CreateEvent(nil, False, False, nil);
  if FQueueEvent = 0 then
  begin
    DoneCriticalSection(FLogLock);
    DoneCriticalSection(FLock);
    raise Exception.CreateFmt('Queue event error %d', [GetLastError]);
  end;
end;

destructor TLimiterEngine.Destroy;
var
  I: Integer;
begin
  Stop;
  for I := 0 to High(FAppProcesses) do
    CloseHandle(FAppProcesses[I].Handle);
  SetLength(FAppProcesses, 0);
  CloseHandle(FQueueEvent);
  DoneCriticalSection(FLogLock);
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TLimiterEngine.SetStatus(const Value: string);
begin
  EnterCriticalSection(FLock);
  try
    FLastStatus := Value;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLimiterEngine.LogDiagnostic(const Value: string);
var
  Stream: TFileStream;
  Line: UTF8String;
  OldPath, WideOld, WideNew: UnicodeString;
begin
  EnterCriticalSection(FLogLock);
  try
    try
      ForceDirectories(ExtractFileDir(FDiagnosticPath));
      if FileExists(FDiagnosticPath) then
        Stream := TFileStream.Create(FDiagnosticPath,
          fmOpenReadWrite or fmShareDenyNone)
      else
        Stream := TFileStream.Create(FDiagnosticPath, fmCreate);
      try
        if Stream.Size > 1024 * 1024 then
        begin
          Stream.Free;
          Stream := nil;
          OldPath := UnicodeString(UTF8Decode(FDiagnosticPath + '.1'));
          WideOld := UnicodeString(UTF8Decode(FDiagnosticPath));
          WideNew := OldPath;
          MoveFileExW(PWideChar(WideOld), PWideChar(WideNew),
            MoveFileReplaceExisting);
          Stream := TFileStream.Create(FDiagnosticPath, fmCreate);
        end;
        Stream.Position := Stream.Size;
        Line := UTF8String(FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) +
          ' [' + IntToStr(GetCurrentThreadId) + '] ' + Value + LineEnding);
        if Length(Line) > 0 then Stream.WriteBuffer(Line[1], Length(Line));
      finally
        Stream.Free;
      end;
    except
      // Logging must never take down a network worker.
    end;
  finally
    LeaveCriticalSection(FLogLock);
  end;
end;

function TLimiterEngine.FindRule(const Path: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FRules) do
    if SameWindowsPath(FRules[I].Path, Path) then Exit(I);
  Result := -1;
end;

function TLimiterEngine.FindApp(const Path: string): Integer;
var
  I, Victim: Integer;
  Busy: array[0..MaxApps - 1] of Boolean;
  NowMs: QWord;
begin
  for I := 0 to High(FApps) do
    if SameWindowsPath(FApps[I].Path, Path) then Exit(I);
  if Length(FApps) >= MaxApps then
  begin
    PruneExitedProcesses;
    if (FQueueHead[0] <> nil) or (FQueueHead[1] <> nil) or
      (FSendInFlight <> 0) then Exit(-1);
    FillChar(Busy, SizeOf(Busy), 0);
    for I := 0 to High(FAppProcesses) do
      Busy[FAppProcesses[I].AppIndex] := True;
    for I := 0 to High(FFlows) do
      if FFlows[I].Used then Busy[FFlows[I].AppIndex] := True;
    Victim := -1;
    NowMs := GetTickCount64;
    for I := 0 to High(FApps) do
      if not Busy[I] and ((FApps[I].LastPacketMs = 0) or
        (NowMs - FApps[I].LastPacketMs > 60000)) and
        ((Victim < 0) or
          (FApps[I].LastPacketMs < FApps[Victim].LastPacketMs)) then
        Victim := I;
    if Victim < 0 then Exit(-1);
    for I := 0 to High(FDestinations) do
      if FDestinations[I].AppIndex = Victim then
      begin
        FDestinations[I] := Default(TDestinationEntry);
        FDestinations[I].AppIndex := -1;
      end;
    Inc(FDestinationsRevision);
    Result := Victim;
    FApps[Result] := Default(TAppEntry);
  end
  else
  begin
    Result := Length(FApps);
    SetLength(FApps, Result + 1);
  end;
  FApps[Result].Path := Path;
  FApps[Result].RuleIndex := FindRule(Path);
  FApps[Result].QuotaKey := '';
  FApps[Result].DayIndex := -1;
  UpdateQuota(Result);
end;

function TLimiterEngine.QuotaKey(const Rule: TRule): string;
begin
  if Rule.QuotaPeriod = 'daily' then Result := FCurrentDay
  else Result := Copy(FCurrentDay, 1, 7);
end;

procedure TLimiterEngine.UpdateQuota(AppIndex: Integer);
var
  I, RuleIndex: Integer;
  Key: string;
  Bytes: QWord;
begin
  if AppIndex < 0 then Exit;
  RuleIndex := FApps[AppIndex].RuleIndex;
  if RuleIndex < 0 then
  begin
    FApps[AppIndex].QuotaKey := '';
    FApps[AppIndex].QuotaUsed := 0;
    Exit;
  end;
  Key := QuotaKey(FRules[RuleIndex]);
  if FApps[AppIndex].QuotaKey = Key then Exit;
  FApps[AppIndex].QuotaKey := Key;
  FApps[AppIndex].QuotaUsed := 0;
  for I := 0 to High(FUsageDays) do
    if SameWindowsPath(FUsageDays[I].Path, FApps[AppIndex].Path) and
      (Copy(FUsageDays[I].Day, 1, Length(Key)) = Key) then
    begin
      Bytes := FUsageDays[I].DownloadBytes + FUsageDays[I].UploadBytes;
      if (FApps[AppIndex].QuotaUsed >= QWord(High(Int64))) or
        (Bytes > QWord(High(Int64)) - FApps[AppIndex].QuotaUsed) then
        FApps[AppIndex].QuotaUsed := QWord(High(Int64))
      else
        Inc(FApps[AppIndex].QuotaUsed, Bytes);
    end;
end;

procedure TLimiterEngine.UpdateGlobalQuota;
var
  I: Integer;
  Key: string;
  Bytes: QWord;
begin
  Key := QuotaKey(FSettings.GlobalRule);
  if FGlobalQuotaKey = Key then Exit;
  FGlobalQuotaKey := Key;
  FGlobalQuotaUsed := 0;
  for I := 0 to High(FUsageDays) do
    if (FUsageDays[I].Path = GlobalUsagePath) and
      (Copy(FUsageDays[I].Day, 1, Length(Key)) = Key) then
    begin
      Bytes := FUsageDays[I].DownloadBytes + FUsageDays[I].UploadBytes;
      if (FGlobalQuotaUsed >= QWord(High(Int64))) or
        (Bytes > QWord(High(Int64)) - FGlobalQuotaUsed) then
        FGlobalQuotaUsed := QWord(High(Int64))
      else
        Inc(FGlobalQuotaUsed, Bytes);
    end;
end;

procedure TLimiterEngine.PruneExitedProcesses;
var
  I, Last: Integer;
begin
  I := 0;
  while I < Length(FAppProcesses) do
    if WaitForSingleObject(FAppProcesses[I].Handle, 0) = WAIT_OBJECT_0 then
    begin
      CloseHandle(FAppProcesses[I].Handle);
      Last := High(FAppProcesses);
      FAppProcesses[I] := FAppProcesses[Last];
      SetLength(FAppProcesses, Last);
    end
    else Inc(I);
end;

procedure TLimiterEngine.RecordAppProcess(AppIndex: Integer;
  ProcessId: DWORD; ProcessHandle: THandle);
var
  I, N: Integer;
  Existing: Boolean;
begin
  if ProcessHandle = 0 then Exit;
  PruneExitedProcesses;
  Existing := False;
  for I := 0 to High(FAppProcesses) do
    if FAppProcesses[I].AppIndex = AppIndex then
    begin
      Existing := True;
      if FAppProcesses[I].ProcessId = ProcessId then
      begin
        CloseHandle(ProcessHandle);
        Exit;
      end;
    end;
  if not Existing then
  begin
    FApps[AppIndex].DownloadBytes := 0;
    FApps[AppIndex].UploadBytes := 0;
    FApps[AppIndex].LocalDownloadBytes := 0;
    FApps[AppIndex].LocalUploadBytes := 0;
    FApps[AppIndex].WindowDown := 0;
    FApps[AppIndex].WindowUp := 0;
    FApps[AppIndex].RateDown := 0;
    FApps[AppIndex].RateUp := 0;
    FApps[AppIndex].Uncertain := False;
  end;
  N := Length(FAppProcesses);
  SetLength(FAppProcesses, N + 1);
  FAppProcesses[N].AppIndex := AppIndex;
  FAppProcesses[N].ProcessId := ProcessId;
  FAppProcesses[N].StartTime := ProcessStartTime(ProcessHandle);
  FAppProcesses[N].Handle := ProcessHandle;
end;

function TLimiterEngine.GlobalEffectiveRate: Int64;
begin
  Result := 0;
  if FSettings.Paused or not FSettings.GlobalRule.Enabled or
    FSettings.GlobalRule.BlockAfterQuota or
    (FSettings.GlobalRule.QuotaBytes <= 0) or
    (FGlobalQuotaUsed < QWord(FSettings.GlobalRule.QuotaBytes)) then Exit;
  Result := FSettings.GlobalRule.QuotaSlowBps;
end;

function TLimiterEngine.EffectiveRate(AppIndex, RuleIndex,
  Direction: Integer): Int64;
begin
  Result := 0;
  if (RuleIndex < 0) or FSettings.Paused or
    not FRules[RuleIndex].Enabled then Exit;
  if ScheduleActive(FRules[RuleIndex], Now) then
  begin
    if Direction = 0 then
      Result := EnforcedLimitBps(FRules[RuleIndex].DownloadBps)
    else
      Result := EnforcedLimitBps(FRules[RuleIndex].UploadBps);
  end;
  if AppIndex >= 0 then
  begin
    UpdateQuota(AppIndex);
    if (FRules[RuleIndex].QuotaBytes > 0) and
      (FApps[AppIndex].QuotaUsed >= QWord(FRules[RuleIndex].QuotaBytes)) then
      if (Result = 0) or (Result > FRules[RuleIndex].QuotaSlowBps) then
        Result := FRules[RuleIndex].QuotaSlowBps;
  end;
end;

function TLimiterEngine.UsageDayIndex(const Path, Day: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FUsageDays) do
    if (FUsageDays[I].Day = Day) and
      SameWindowsPath(FUsageDays[I].Path, Path) then Exit(I);
  if (Length(FUsageDays) >= MaxUsageDays) or
    ((Path <> GlobalUsagePath) and
      (Length(FUsageDays) >= MaxUsageDays - ReservedGlobalUsageDays)) then
    Exit(-1);
  Result := Length(FUsageDays);
  SetLength(FUsageDays, Result + 1);
  FUsageDays[Result].Path := Path;
  FUsageDays[Result].Day := Day;
end;

function TLimiterEngine.UsageDestinationIndex(AppIndex,
  DestinationIndex: Integer): Integer;
var
  I: Integer;
  Path, Name: string;
begin
  Result := -1;
  if DestinationIndex < 0 then Exit;
  Path := FApps[AppIndex].Path;
  Name := FDestinations[DestinationIndex].Name;
  for I := 0 to High(FUsageDestinations) do
    if (FUsageDestinations[I].Day = FCurrentDay) and
      SameWindowsPath(FUsageDestinations[I].Path, Path) and
      (CompareText(FUsageDestinations[I].Name, Name) = 0) then
      Exit(I);
  if Length(FUsageDestinations) >= MaxUsageDestinations then Exit;
  Result := Length(FUsageDestinations);
  SetLength(FUsageDestinations, Result + 1);
  FUsageDestinations[Result].Path := Path;
  FUsageDestinations[Result].Day := FCurrentDay;
  FUsageDestinations[Result].Name := Name;
  FUsageDestinations[Result].Address :=
    FDestinations[DestinationIndex].Address;
  FUsageDestinations[Result].Source :=
    FDestinations[DestinationIndex].Source;
end;

procedure TLimiterEngine.LoadHistory;
var
  Content: TStringList;
  Stream: TFileStream;
  Root, Days, Destinations, Entry: TJSONData;
  I, N: Integer;
  Cutoff: string;

  function UsageBytes(const Item: TJSONData; const Name: string): QWord;
  var
    Value: Int64;
  begin
    Value := TJSONObject(Item).Get(Name, Int64(0));
    if Value < 0 then Result := 0 else Result := QWord(Value);
  end;
begin
  if not FileExists(FHistoryPath) then Exit;
  Content := TStringList.Create;
  Root := nil;
  try
    try
    Stream := TFileStream.Create(FHistoryPath, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size > 16 * 1024 * 1024 then Exit;
      Content.LoadFromStream(Stream);
    finally
      Stream.Free;
    end;
    Root := GetJSON(Content.Text);
    if Root.JSONType <> jtObject then Exit;
    Cutoff := FormatDateTime('yyyy-mm-dd', Date - 90);
    Days := TJSONObject(Root).Find('days');
    if (Days <> nil) and (Days.JSONType = jtArray) then
      for I := 0 to TJSONArray(Days).Count - 1 do
      begin
        Entry := TJSONArray(Days)[I];
        if Entry.JSONType <> jtObject then Continue;
        if TJSONObject(Entry).Get('day', '') < Cutoff then Continue;
        if Length(FUsageDays) >= MaxUsageDays then Break;
        if (TJSONObject(Entry).Get('path', '') <> GlobalUsagePath) and
          (Length(FUsageDays) >= MaxUsageDays - ReservedGlobalUsageDays) then
          Continue;
        N := Length(FUsageDays);
        SetLength(FUsageDays, N + 1);
        FUsageDays[N].Path := TJSONObject(Entry).Get('path', '');
        FUsageDays[N].Day := TJSONObject(Entry).Get('day', '');
        FUsageDays[N].DownloadBytes := UsageBytes(Entry, 'downloadBytes');
        FUsageDays[N].UploadBytes := UsageBytes(Entry, 'uploadBytes');
      end;
    Destinations := TJSONObject(Root).Find('destinations');
    if (Destinations <> nil) and (Destinations.JSONType = jtArray) then
      for I := 0 to TJSONArray(Destinations).Count - 1 do
      begin
        Entry := TJSONArray(Destinations)[I];
        if Entry.JSONType <> jtObject then Continue;
        if TJSONObject(Entry).Get('day', '') < Cutoff then Continue;
        if Length(FUsageDestinations) >= MaxUsageDestinations then Break;
        N := Length(FUsageDestinations);
        SetLength(FUsageDestinations, N + 1);
        FUsageDestinations[N].Path := TJSONObject(Entry).Get('path', '');
        FUsageDestinations[N].Day := TJSONObject(Entry).Get('day', '');
        FUsageDestinations[N].Name := TJSONObject(Entry).Get('name', '');
        FUsageDestinations[N].Address := TJSONObject(Entry).Get('address', '');
        FUsageDestinations[N].Source := TJSONObject(Entry).Get('source', 'IP');
        FUsageDestinations[N].DownloadBytes := UsageBytes(Entry,
          'downloadBytes');
        FUsageDestinations[N].UploadBytes := UsageBytes(Entry,
          'uploadBytes');
      end;
    except
      on E: Exception do FLastStatus := 'Usage history error: ' + E.Message;
    end;
  finally
    Root.Free;
    Content.Free;
  end;
end;

procedure TLimiterEngine.PruneHistory;
var
  I, Last: Integer;
  Cutoff: string;
begin
  Cutoff := FormatDateTime('yyyy-mm-dd', Date - 90);
  I := 0;
  while I < Length(FUsageDays) do
    if FUsageDays[I].Day < Cutoff then
    begin
      Last := High(FUsageDays);
      FUsageDays[I] := FUsageDays[Last];
      SetLength(FUsageDays, Last);
      FHistoryDirty := True;
    end
    else Inc(I);
  I := 0;
  while I < Length(FUsageDestinations) do
    if FUsageDestinations[I].Day < Cutoff then
    begin
      Last := High(FUsageDestinations);
      FUsageDestinations[I] := FUsageDestinations[Last];
      SetLength(FUsageDestinations, Last);
      FHistoryDirty := True;
    end
    else Inc(I);
end;

procedure TLimiterEngine.LoadSessionCheckpoint;
var
  Content: TStringList;
  Stream: TFileStream;
  Root, Sessions, Entry, Processes, ProcessEntry: TJSONData;
  Path: string;
  I, J, Index, N: Integer;
  PidValue, StampValue, ByteValue: Int64;
  Handle: THandle;

  function SavedBytes(const Item: TJSONData; const Name: string): QWord;
  begin
    ByteValue := TJSONObject(Item).Get(Name, Int64(0));
    if ByteValue < 0 then Result := 0 else Result := QWord(ByteValue);
  end;
begin
  if not FileExists(FStatePath) then Exit;
  Content := TStringList.Create;
  Root := nil;
  try
    try
      Stream := TFileStream.Create(FStatePath,
        fmOpenRead or fmShareDenyNone);
      try
        if Stream.Size > 8 * 1024 * 1024 then Exit;
        Content.LoadFromStream(Stream);
      finally
        Stream.Free;
      end;
      Root := GetJSON(Content.Text);
      if Root.JSONType <> jtObject then Exit;
      Sessions := TJSONObject(Root).Find('sessions');
      if (Sessions = nil) or (Sessions.JSONType <> jtArray) then Exit;
      for I := 0 to TJSONArray(Sessions).Count - 1 do
      begin
        if I >= MaxApps then Break;
        Entry := TJSONArray(Sessions)[I];
        if Entry.JSONType <> jtObject then Continue;
        Path := TJSONObject(Entry).Get('path', '');
        if Path = '' then Continue;
        Processes := TJSONObject(Entry).Find('processes');
        if (Processes = nil) or (Processes.JSONType <> jtArray) then Continue;
        Index := -1;
        for J := 0 to TJSONArray(Processes).Count - 1 do
        begin
          if J >= 4096 then Break;
          ProcessEntry := TJSONArray(Processes)[J];
          if ProcessEntry.JSONType <> jtObject then Continue;
          PidValue := TJSONObject(ProcessEntry).Get('pid', Int64(0));
          StampValue := TJSONObject(ProcessEntry).Get('startTime', Int64(0));
          if (PidValue <= 0) or (PidValue > High(DWORD)) or
            (StampValue <= 0) then Continue;
          Handle := OpenProcess(ProcessSynchronize or
            ProcessQueryLimitedInformation, False, DWORD(PidValue));
          if Handle = 0 then Continue;
          if (ProcessStartTime(Handle) <> QWord(StampValue)) or
            not SameWindowsPath(ProcessPath(DWORD(PidValue)), Path) then
          begin
            CloseHandle(Handle);
            Continue;
          end;
          if Index < 0 then Index := FindApp(Path);
          if Index < 0 then
          begin
            CloseHandle(Handle);
            Continue;
          end;
          N := Length(FAppProcesses);
          SetLength(FAppProcesses, N + 1);
          FAppProcesses[N].AppIndex := Index;
          FAppProcesses[N].ProcessId := DWORD(PidValue);
          FAppProcesses[N].StartTime := QWord(StampValue);
          FAppProcesses[N].Handle := Handle;
        end;
        if Index < 0 then Continue;
        FApps[Index].DownloadBytes := SavedBytes(Entry, 'downloadBytes');
        FApps[Index].UploadBytes := SavedBytes(Entry, 'uploadBytes');
        FApps[Index].LocalDownloadBytes :=
          SavedBytes(Entry, 'localDownloadBytes');
        FApps[Index].LocalUploadBytes :=
          SavedBytes(Entry, 'localUploadBytes');
        FApps[Index].Uncertain := TJSONObject(Entry).Get('uncertain', False);
        FApps[Index].LastPacketMs := GetTickCount64;
      end;
      if Length(FAppProcesses) > 0 then
        LogDiagnostic('Restored ' + IntToStr(Length(FAppProcesses)) +
          ' live process session(s) after backend restart');
    except
      on E: Exception do
        LogDiagnostic('Session checkpoint could not be read: ' + E.Message);
    end;
  finally
    Root.Free;
    Content.Free;
  end;
end;

procedure TLimiterEngine.WriteHistory(Force: Boolean);
var
  DaysCopy: array of TUsageDay;
  DestinationsCopy: array of TUsageDestination;
  Root, Entry: TJSONObject;
  Days, Destinations: TJSONArray;
  Content: TStringList;
  I: Integer;
  TempPath, Cutoff: string;
  PublishError: DWORD;
begin
  EnterCriticalSection(FLock);
  try
    if not FHistoryDirty or
      (not Force and (GetTickCount64 - FLastHistoryPublishMs < 15000)) then
      Exit;
    DaysCopy := Copy(FUsageDays);
    DestinationsCopy := Copy(FUsageDestinations);
    FHistoryDirty := False;
    FLastHistoryPublishMs := GetTickCount64;
  finally
    LeaveCriticalSection(FLock);
  end;
  Root := TJSONObject.Create;
  Content := TStringList.Create;
  try
    Cutoff := FormatDateTime('yyyy-mm-dd', Date - 90);
    Root.Add('version', 1);
    Days := TJSONArray.Create;
    Root.Add('days', Days);
    for I := 0 to High(DaysCopy) do
    begin
      if DaysCopy[I].Day < Cutoff then Continue;
      Entry := TJSONObject.Create;
      Entry.Add('path', DaysCopy[I].Path);
      Entry.Add('day', DaysCopy[I].Day);
      Entry.Add('downloadBytes', Int64(DaysCopy[I].DownloadBytes));
      Entry.Add('uploadBytes', Int64(DaysCopy[I].UploadBytes));
      Days.Add(Entry);
    end;
    Destinations := TJSONArray.Create;
    Root.Add('destinations', Destinations);
    for I := 0 to High(DestinationsCopy) do
    begin
      if DestinationsCopy[I].Day < Cutoff then Continue;
      Entry := TJSONObject.Create;
      Entry.Add('path', DestinationsCopy[I].Path);
      Entry.Add('day', DestinationsCopy[I].Day);
      Entry.Add('name', DestinationsCopy[I].Name);
      Entry.Add('address', DestinationsCopy[I].Address);
      Entry.Add('source', DestinationsCopy[I].Source);
      Entry.Add('downloadBytes', Int64(DestinationsCopy[I].DownloadBytes));
      Entry.Add('uploadBytes', Int64(DestinationsCopy[I].UploadBytes));
      Destinations.Add(Entry);
    end;
    Content.Text := Root.AsJSON;
    ForceDirectories(ExtractFileDir(FHistoryPath));
    TempPath := FHistoryPath + '.tmp';
    Content.SaveToFile(TempPath);
    if not PublishTempFile(TempPath, FHistoryPath, PublishError) then
      raise Exception.CreateFmt('Cannot publish history (%d)',
        [PublishError]);
  except
    on E: Exception do
    begin
      EnterCriticalSection(FLock);
      try
        FHistoryDirty := True;
        FLastStatus := 'Usage history error: ' + E.Message;
      finally
        LeaveCriticalSection(FLock);
      end;
      LogDiagnostic('Usage history publish failed: ' + E.Message);
    end;
  end;
  Content.Free;
  Root.Free;
end;

function TLimiterEngine.HasActiveLimits: Boolean;
var
  I: Integer;
begin
  Result := False;
  if RuleBlocksTraffic(FSettings.GlobalRule) or
    (FSettings.GlobalRule.Enabled and
      ((FSettings.GlobalRule.ScheduleEnabled and
        FSettings.GlobalRule.BlockOutsideSchedule) or
       (FSettings.GlobalRule.BlockAfterQuota and
        (FSettings.GlobalRule.QuotaBytes > 0)) or
       (not FSettings.Paused and
        (FSettings.GlobalRule.QuotaBytes > 0)))) then Exit(True);
  for I := 0 to High(FRules) do
    if RuleBlocksTraffic(FRules[I]) or
      (FRules[I].Enabled and
        ((FRules[I].BlockOutsideSchedule and FRules[I].ScheduleEnabled) or
         (FRules[I].BlockAfterQuota and (FRules[I].QuotaBytes > 0)))) or
      (not FSettings.Paused and FRules[I].Enabled and
        ((FRules[I].QuotaBytes > 0) or
         (ScheduleActive(FRules[I], Now) and
           ((FRules[I].DownloadBps > 0) or (FRules[I].UploadBps > 0))))) then
      Exit(True);
end;

procedure TLimiterEngine.RememberAnswers(const Answers: array of TDNSAnswer);
var
  I, J, Index: Integer;
  Expiry: QWord;
begin
  for I := 0 to High(Answers) do
  begin
    if (Answers[I].Name = '') or (Answers[I].Address = '') then Continue;
    Index := -1;
    for J := 0 to High(FResolved) do
      if FResolved[J].Address = Answers[I].Address then
      begin
        Index := J;
        Break;
      end;
    if Index < 0 then
    begin
      if Length(FResolved) >= MaxResolved then
      begin
        Index := 0;
        for J := 1 to High(FResolved) do
          if FResolved[J].ExpiresMs < FResolved[Index].ExpiresMs then
            Index := J;
      end
      else
      begin
        Index := Length(FResolved);
        SetLength(FResolved, Index + 1);
      end;
    end;
    Expiry := Answers[I].TTL;
    if Expiry > 300 then Expiry := 300;
    if Expiry = 0 then Expiry := 1;
    FResolved[Index].Address := Answers[I].Address;
    FResolved[Index].Name := Answers[I].Name;
    FResolved[Index].ExpiresMs := GetTickCount64 + Expiry * 1000;
  end;
end;

function TLimiterEngine.ResolvedName(const Address: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := High(FResolved) downto 0 do
    if (FResolved[I].Address = Address) and
      (FResolved[I].ExpiresMs > GetTickCount64) then
      Exit(FResolved[I].Name);
end;

{$push}{$R-}{$Q-}
function TLimiterEngine.HashTuple(const Tuple: TFlowTuple): LongWord;
var
  I: Integer;
begin
  Result := 2166136261;
  for I := 0 to 3 do
  begin
    Result := (Result xor Tuple.LocalAddr[I]) * 16777619;
    Result := (Result xor Tuple.RemoteAddr[I]) * 16777619;
  end;
  Result := (Result xor Tuple.LocalPort) * 16777619;
  Result := (Result xor Tuple.RemotePort) * 16777619;
  Result := (Result xor Tuple.Protocol) * 16777619;
  Result := Result xor Ord(Tuple.IPv6);
end;
{$pop}

function TLimiterEngine.FlowSlot(const Tuple: TFlowTuple): Integer;
var
  I, Index: Integer;
begin
  Index := HashTuple(Tuple) and High(FFlows);
  for I := 0 to High(FFlows) do
  begin
    if FFlows[Index].Used and EqualTuple(FFlows[Index].Tuple, Tuple) then
      Exit(Index);
    if not FFlows[Index].Used and not FFlows[Index].Tombstone then Break;
    Index := (Index + 1) and High(FFlows);
  end;
  Result := -1;
end;

procedure TLimiterEngine.CompactFlows;
var
  Previous: array of TFlowEntry;
  I, Slot: Integer;
begin
  // Called with FLock held. Long-lived services otherwise accumulate
  // tombstones until every miss has to scan the entire flow table.
  SetLength(Previous, Length(FFlows));
  Move(FFlows[0], Previous[0], SizeOf(FFlows));
  FillChar(FFlows, SizeOf(FFlows), 0);
  for I := 0 to High(Previous) do
    if Previous[I].Used then
    begin
      Slot := HashTuple(Previous[I].Tuple) and High(FFlows);
      while FFlows[Slot].Used do
        Slot := (Slot + 1) and High(FFlows);
      FFlows[Slot] := Previous[I];
    end;
  FFlowTombstones := 0;
  Inc(FFlowTableRebuilds);
end;

function TLimiterEngine.RecordDestination(AppIndex: Integer;
  const Name, Address, Source: string; Port: Word; Protocol: Byte): Integer;
var
  I: Integer;
  Referenced: array of Boolean;
begin
  Result := -1;
  if (AppIndex < 0) or (Name = '') then Exit;
  for I := 0 to High(FDestinations) do
    if (FDestinations[I].AppIndex = AppIndex) and
      (CompareText(FDestinations[I].Name, Name) = 0) then
    begin
      Result := I;
      Break;
    end;
  if Result < 0 then
  begin
    if Length(FDestinations) >= MaxDestinations then
    begin
      for I := 0 to High(FDestinations) do
        if FDestinations[I].AppIndex < 0 then
        begin
          Result := I;
          Break;
        end;
      if Result < 0 then
      begin
        SetLength(Referenced, Length(FDestinations));
        for I := 0 to High(FFlows) do
          if FFlows[I].Used and
            (FFlows[I].DestinationIndex >= 0) and
            (FFlows[I].DestinationIndex < Length(Referenced)) then
            Referenced[FFlows[I].DestinationIndex] := True;
        for I := 0 to High(FDestinations) do
          if not Referenced[I] and
            ((Result < 0) or
              (FDestinations[I].LastSeenMs <
                FDestinations[Result].LastSeenMs)) then
            Result := I;
        if Result < 0 then
        begin
          Inc(FDestinationsDropped);
          Exit;
        end;
      end;
    end;
    if Result < 0 then
    begin
      Result := Length(FDestinations);
      SetLength(FDestinations, Result + 1);
    end;
    FDestinations[Result] := Default(TDestinationEntry);
    FDestinations[Result].AppIndex := AppIndex;
    FDestinations[Result].Name := Name;
    FDestinations[Result].Source := Source;
    Inc(FDestinationsRevision);
  end;
  if (Address <> '') and (FDestinations[Result].Address <> Address) then
  begin
    FDestinations[Result].Address := Address;
    Inc(FDestinationsRevision);
  end;
  if (Port <> 0) and (FDestinations[Result].Port <> Port) then
  begin
    FDestinations[Result].Port := Port;
    Inc(FDestinationsRevision);
  end;
  if (Protocol <> 0) and (FDestinations[Result].Protocol <> Protocol) then
  begin
    FDestinations[Result].Protocol := Protocol;
    Inc(FDestinationsRevision);
  end;
  if (Source <> 'IP') and (FDestinations[Result].Source <> Source) then
  begin
    FDestinations[Result].Source := Source;
    Inc(FDestinationsRevision);
  end;
  FDestinations[Result].LastSeenMs := GetTickCount64;
end;

procedure TLimiterEngine.AddFlow(const Address: TDivertAddress);
var
  Flow: PFlowData;
  Path: string;
  Tuple: TFlowTuple;
  I, Index, FirstTombstone, Probe: Integer;
  SlotFound: Boolean;
  RemoteIP: string;
  ProcessHandle: THandle;
begin
  Flow := PFlowData(@Address.Data[0]);
  Path := ProcessPath(Flow^.ProcessId);
  if Path = '' then Exit;
  ProcessHandle := OpenProcess(ProcessSynchronize or
    ProcessQueryLimitedInformation, False, Flow^.ProcessId);
  if ProcessHandle = 0 then
    ProcessHandle := OpenProcess(ProcessSynchronize, False,
      Flow^.ProcessId);
  Tuple := windivert_api.FlowTuple(Address);
  RemoteIP := IPText(Tuple.RemoteAddr, Tuple.IPv6);
  EnterCriticalSection(FLock);
  try
    Index := FindApp(Path);
    if Index < 0 then
    begin
      if ProcessHandle <> 0 then CloseHandle(ProcessHandle);
      Exit;
    end;
    RecordAppProcess(Index, Flow^.ProcessId, ProcessHandle);
    I := HashTuple(Tuple) and High(FFlows);
    FirstTombstone := -1;
    SlotFound := False;
    for Probe := 0 to High(FFlows) do
    begin
      if FFlows[I].Used then
      begin
        if EqualTuple(FFlows[I].Tuple, Tuple) then
        begin
          SlotFound := True;
          Break;
        end;
      end
      else if FFlows[I].Tombstone then
      begin
        if FirstTombstone < 0 then FirstTombstone := I;
      end
      else
      begin
        if FirstTombstone >= 0 then I := FirstTombstone;
        SlotFound := True;
        Break;
      end;
      I := (I + 1) and High(FFlows);
    end;
    if not SlotFound then
    begin
      if FirstTombstone < 0 then
      begin
        Inc(FFlowTableFull);
        Exit;
      end;
      I := FirstTombstone;
    end;
    if FFlows[I].Tombstone then Dec(FFlowTombstones);
    FFlows[I].Used := True;
    FFlows[I].Tombstone := False;
    FFlows[I].EndpointId := Flow^.EndpointId;
    FFlows[I].Tuple := Tuple;
    FFlows[I].AppIndex := Index;
    Path := ResolvedName(RemoteIP);
    if Path <> '' then
      FFlows[I].DestinationIndex := RecordDestination(Index, Path,
        RemoteIP, 'DNS answer', Tuple.RemotePort, Tuple.Protocol)
    else
      FFlows[I].DestinationIndex := RecordDestination(Index, RemoteIP,
        RemoteIP, 'IP', Tuple.RemotePort, Tuple.Protocol);
    FFlows[I].HistoryIndex := -1;
    FFlows[I].Scope := ScopeOf(Tuple);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLimiterEngine.DeleteFlow(const Address: TDivertAddress);
var
  Flow: PFlowData;
  Tuple: TFlowTuple;
  Index: Integer;
begin
  Flow := PFlowData(@Address.Data[0]);
  Tuple := windivert_api.FlowTuple(Address);
  EnterCriticalSection(FLock);
  try
    Index := FlowSlot(Tuple);
    if (Index >= 0) and (FFlows[Index].EndpointId = Flow^.EndpointId) then
    begin
      FFlows[Index].Used := False;
      FFlows[Index].Tombstone := True;
      Inc(FFlowTombstones);
      if FFlowTombstones >= MaxFlowTombstones then CompactFlows;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TLimiterEngine.QueuePacket(RuleIndex, AppIndex, Direction: Integer;
  AppRate, GlobalRate: Int64;
  Scope: TTrafficScope; const Address: TDivertAddress; Packet: Pointer;
  PacketLength: LongWord; Handle: THandle): Boolean;
var
  Item: PQueuedPacket;
  Current: PQueuedPacket;
  Due, AppInterval, GlobalInterval, Now: QWord;
begin
  Result := False;
  if (AppRate <= 0) and (GlobalRate <= 0) then Exit;
  Now := NowUs;
  Due := Now;
  AppInterval := 0;
  GlobalInterval := 0;
  if AppRate > 0 then
  begin
    if FDueUs[RuleIndex][Direction] > Due then
      Due := FDueUs[RuleIndex][Direction];
    AppInterval := (QWord(PacketLength) * 1000000 + QWord(AppRate) - 1) div
      QWord(AppRate);
  end;
  if GlobalRate > 0 then
  begin
    if FGlobalDueUs[Direction] > Due then
      Due := FGlobalDueUs[Direction];
    GlobalInterval := (QWord(PacketLength) * 1000000 +
      QWord(GlobalRate) - 1) div QWord(GlobalRate);
  end;
  // The first packet in an idle direction is already due. Reinject it from
  // the receiver thread instead of waiting for the sender to wake up.
  if (Due = Now) and (FQueueHead[Direction] = nil) then
  begin
    if AppRate > 0 then
      FDueUs[RuleIndex][Direction] := Due + AppInterval;
    if GlobalRate > 0 then
      FGlobalDueUs[Direction] := Due + GlobalInterval;
    Inc(FImmediatePackets);
    Exit;
  end;
  Result := True;
  if (Due > Now + MaxQueueDelayUs) or
    (FQueueBytes + PacketLength > MaxQueueBytes) then
  begin
    Inc(FDroppedPackets);
    Exit;
  end;
  New(Item);
  Item^.Next := nil;
  Item^.AppIndex := AppIndex;
  Item^.Scope := Scope;
  Item^.DueUs := Due;
  Item^.PacketLength := PacketLength;
  Item^.Address := Address;
  Item^.Handle := Handle;
  SetLength(Item^.Packet, PacketLength);
  Move(Packet^, Item^.Packet[0], PacketLength);
  if (FQueueHead[Direction] = nil) or
    (Item^.DueUs < FQueueHead[Direction]^.DueUs) then
  begin
    Item^.Next := FQueueHead[Direction];
    FQueueHead[Direction] := Item;
    if FQueueTail[Direction] = nil then FQueueTail[Direction] := Item;
  end
  else
  begin
    Current := FQueueHead[Direction];
    while (Current^.Next <> nil) and
      (Current^.Next^.DueUs <= Item^.DueUs) do
      Current := Current^.Next;
    Item^.Next := Current^.Next;
    Current^.Next := Item;
    if Item^.Next = nil then FQueueTail[Direction] := Item;
  end;
  Inc(FQueueBytes, PacketLength);
  Inc(FQueuedPackets);
  if AppRate > 0 then
    FDueUs[RuleIndex][Direction] := Due + AppInterval;
  if GlobalRate > 0 then
    FGlobalDueUs[Direction] := Due + GlobalInterval;
  SetEvent(FQueueEvent);
end;

procedure TLimiterEngine.DrainQueue;
var
  Empty: Boolean;
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + 15000;
  EnterCriticalSection(FLock);
  try
    FFlushQueue := True;
    SetEvent(FQueueEvent);
  finally
    LeaveCriticalSection(FLock);
  end;
  repeat
    EnterCriticalSection(FLock);
    try
      Empty := (FQueueHead[0] = nil) and (FQueueHead[1] = nil) and
        (FSendInFlight = 0);
      if Empty then FFlushQueue := False;
    finally
      LeaveCriticalSection(FLock);
    end;
    if Empty then Exit;
    if GetTickCount64 > Deadline then
    begin
      LogDiagnostic('Packet queue did not drain within 15 seconds; '
        + 'restarting service');
      ExitProcess(1);
    end;
    Sleep(2);
  until False;
end;

procedure TLimiterEngine.ProcessPacket(const Address: TDivertAddress;
  Packet: Pointer; PacketLength: LongWord; Diverted: Boolean;
  Handle: THandle);
var
  Tuple: TFlowTuple;
  Slot, AppIndex, RuleIndex, Direction, DestinationIndex: Integer;
  AppRate, GlobalRate: Int64;
  QueueIt: Boolean;
  Parsed: Boolean;
  Scope: TTrafficScope;
  Sent: LongWord;
  Payload: Pointer;
  PayloadLength: LongWord;
  HostName, NameSource, RemoteIP: string;
  Answers: TDNSAnswers;
begin
  QueueIt := False;
  AppIndex := -1;
  RuleIndex := -1;
  SetLength(Answers, 0);
  if IsOutbound(Address) then Direction := 1 else Direction := 0;
  Parsed := PacketTuple(Address, Packet, PacketLength, Tuple);
  if Parsed then Scope := ScopeOf(Tuple) else Scope := tsUnknown;
  EnterCriticalSection(FLock);
  try
    if Diverted and (Scope <> tsLocal) and
      RuleBlocksTrafficAt(FSettings.GlobalRule, Now,
      FGlobalQuotaUsed) then
    begin
      Inc(FDroppedPackets);
      Exit;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
  if Parsed then
  begin
    HostName := '';
    NameSource := '';
    if (Direction = 1) or (Tuple.RemotePort = 53) then
    begin
      Payload := nil;
      PayloadLength := 0;
      if WinDivertHelperParsePacket(Packet, PacketLength, nil, nil,
        nil, nil, nil, nil, nil, @Payload, @PayloadLength, nil, nil) and
        (Payload <> nil) then
      begin
        if (Tuple.RemotePort = 53) and (Direction = 0) then
          Answers := DNSResponseAnswers(PByte(Payload), PayloadLength,
            Tuple.Protocol = 6);
        if (Tuple.RemotePort = 53) and (Direction = 1) then
        begin
          HostName := DNSQueryName(PByte(Payload), PayloadLength,
            Tuple.Protocol = 6);
          if HostName <> '' then NameSource := 'DNS query';
        end;
        if HostName = '' then
        begin
          HostName := TLSHostName(PByte(Payload), PayloadLength);
          if HostName <> '' then NameSource := 'TLS SNI';
        end;
        if HostName = '' then
        begin
          HostName := HTTPHostName(PByte(Payload), PayloadLength);
          if HostName <> '' then NameSource := 'HTTP Host';
        end;
      end;
    end;
    EnterCriticalSection(FLock);
    try
      if Length(Answers) > 0 then RememberAnswers(Answers);
      Slot := FlowSlot(Tuple);
      if Slot >= 0 then
      begin
        AppIndex := FFlows[Slot].AppIndex;
        RuleIndex := FApps[AppIndex].RuleIndex;
        FApps[AppIndex].LastPacketMs := GetTickCount64;
        if RuleIndex >= 0 then UpdateQuota(AppIndex);
        if Diverted and (RuleIndex >= 0) and
          RuleBlocksTrafficAt(FRules[RuleIndex], Now,
            FApps[AppIndex].QuotaUsed) then
        begin
          Inc(FDroppedPackets);
          Exit;
        end;
        DestinationIndex := FFlows[Slot].DestinationIndex;
        if DestinationIndex >= 0 then
          FDestinations[DestinationIndex].LastSeenMs := GetTickCount64;
        if HostName <> '' then
        begin
          if NameSource = 'DNS query' then
            RecordDestination(AppIndex, HostName, '', NameSource, 0, 0)
          else
          begin
            RemoteIP := IPText(Tuple.RemoteAddr, Tuple.IPv6);
            DestinationIndex := RecordDestination(AppIndex, HostName,
              RemoteIP, NameSource, Tuple.RemotePort, Tuple.Protocol);
            if DestinationIndex >= 0 then
            begin
              FFlows[Slot].DestinationIndex := DestinationIndex;
              FFlows[Slot].HistoryIndex := -1;
            end;
          end;
        end;
        if FFlows[Slot].Scope = tsLocal then
        begin
          if Direction = 0 then
            Inc(FApps[AppIndex].LocalDownloadBytes, PacketLength)
          else
            Inc(FApps[AppIndex].LocalUploadBytes, PacketLength);
        end
        else
        begin
          if Direction = 0 then
          begin
            Inc(FApps[AppIndex].DownloadBytes, PacketLength);
            Inc(FApps[AppIndex].WindowDown, PacketLength);
          end
          else
          begin
            Inc(FApps[AppIndex].UploadBytes, PacketLength);
            Inc(FApps[AppIndex].WindowUp, PacketLength);
          end;
          if FFlows[Slot].Scope = tsUnknown then
            FApps[AppIndex].Uncertain := True;
          if FApps[AppIndex].DayIndex < 0 then
            FApps[AppIndex].DayIndex := UsageDayIndex(
              FApps[AppIndex].Path, FCurrentDay);
          if FApps[AppIndex].DayIndex >= 0 then
          begin
            if Direction = 0 then
              Inc(FUsageDays[FApps[AppIndex].DayIndex].DownloadBytes,
                PacketLength)
            else
              Inc(FUsageDays[FApps[AppIndex].DayIndex].UploadBytes,
                PacketLength);
          end;
          DestinationIndex := FFlows[Slot].DestinationIndex;
          if DestinationIndex >= 0 then
          begin
            if Direction = 0 then
              Inc(FDestinations[DestinationIndex].DownloadBytes, PacketLength)
            else
              Inc(FDestinations[DestinationIndex].UploadBytes, PacketLength);
            if FFlows[Slot].HistoryIndex < 0 then
              FFlows[Slot].HistoryIndex := UsageDestinationIndex(
                AppIndex, DestinationIndex);
            if FFlows[Slot].HistoryIndex >= 0 then
            begin
              if Direction = 0 then
                Inc(FUsageDestinations[FFlows[Slot].HistoryIndex].DownloadBytes,
                  PacketLength)
              else
                Inc(FUsageDestinations[FFlows[Slot].HistoryIndex].UploadBytes,
                  PacketLength);
            end;
          end;
          FHistoryDirty := True;
        end;
        if RuleIndex >= 0 then
        begin
          if FFlows[Slot].Scope <> tsLocal then
          begin
            if (FApps[AppIndex].QuotaUsed >= QWord(High(Int64))) or
              (PacketLength > QWord(High(Int64)) -
                FApps[AppIndex].QuotaUsed) then
              FApps[AppIndex].QuotaUsed := QWord(High(Int64))
            else
              Inc(FApps[AppIndex].QuotaUsed, PacketLength);
          end;
        end;
      end
      else Inc(FUnattributedPackets);
    finally
      LeaveCriticalSection(FLock);
    end;
  end;
  EnterCriticalSection(FLock);
  try
    if Scope <> tsLocal then
    begin
      if Direction = 0 then AddCapped(FGlobalSessionDown, PacketLength)
      else AddCapped(FGlobalSessionUp, PacketLength);
      if FGlobalDayIndex < 0 then
        FGlobalDayIndex := UsageDayIndex(GlobalUsagePath, FCurrentDay);
      if FGlobalDayIndex >= 0 then
      begin
        if Direction = 0 then
          AddCapped(FUsageDays[FGlobalDayIndex].DownloadBytes, PacketLength)
        else AddCapped(FUsageDays[FGlobalDayIndex].UploadBytes, PacketLength);
        FHistoryDirty := True;
      end;
      AddCapped(FGlobalQuotaUsed, PacketLength);
    end;
    if Diverted then
    begin
      AppRate := 0;
      if RuleIndex >= 0 then
        AppRate := EffectiveRate(AppIndex, RuleIndex, Direction);
      GlobalRate := 0;
      if Scope <> tsLocal then GlobalRate := GlobalEffectiveRate;
      if (AppRate > 0) or (GlobalRate > 0) then
        QueueIt := QueuePacket(RuleIndex, AppIndex, Direction,
          AppRate, GlobalRate, Scope, Address, Packet, PacketLength, Handle);
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
  if Diverted and not QueueIt then
  begin
    Sent := 0;
    if not WinDivertSend(Handle, Packet, PacketLength, @Sent, @Address) or
      (Sent <> PacketLength) then
    begin
      EnterCriticalSection(FLock);
      try
        Inc(FDroppedPackets);
      finally
        LeaveCriticalSection(FLock);
      end;
    end;
  end;
end;

procedure TLimiterEngine.WriteDestinations;
var
  Root, Entry: TJSONObject;
  Items: TJSONArray;
  Text: TStringList;
  I: Integer;
  TempPath: string;
  PublishError: DWORD;
  PublishedRevision, DroppedCopy: QWord;
  AppsCopy: array of TAppEntry;
  DestinationsCopy: array of TDestinationEntry;
begin
  Root := TJSONObject.Create;
  Text := TStringList.Create;
  try
    Items := TJSONArray.Create;
    Root.Add('destinations', Items);
    EnterCriticalSection(FLock);
    try
      // A saturated table takes substantial CPU and disk I/O to publish.
      // Bound that work to once per five seconds while keeping small tables
      // responsive to new names.
      if (FLastDestinationsPublishMs <> 0) and
        (GetTickCount64 - FLastDestinationsPublishMs < 5000) and
        ((FDestinationsRevision = FPublishedDestinationsRevision) or
          (Length(FDestinations) >= 4096)) then Exit;
      PublishedRevision := FDestinationsRevision;
      AppsCopy := Copy(FApps);
      DestinationsCopy := Copy(FDestinations);
      DroppedCopy := FDestinationsDropped;
    finally
      LeaveCriticalSection(FLock);
    end;
    for I := 0 to High(DestinationsCopy) do
    begin
      if (DestinationsCopy[I].AppIndex < 0) or
        (DestinationsCopy[I].AppIndex >= Length(AppsCopy)) then Continue;
      Entry := TJSONObject.Create;
      Entry.Add('path', AppsCopy[DestinationsCopy[I].AppIndex].Path);
      Entry.Add('name', DestinationsCopy[I].Name);
      Entry.Add('address', DestinationsCopy[I].Address);
      Entry.Add('source', DestinationsCopy[I].Source);
      Entry.Add('port', Integer(DestinationsCopy[I].Port));
      Entry.Add('protocol', Integer(DestinationsCopy[I].Protocol));
      Entry.Add('lastSeenMs', Int64(DestinationsCopy[I].LastSeenMs));
      Entry.Add('downloadBytes', Int64(DestinationsCopy[I].DownloadBytes));
      Entry.Add('uploadBytes', Int64(DestinationsCopy[I].UploadBytes));
      Items.Add(Entry);
    end;
    Root.Add('dropped', Int64(DroppedCopy));
    Text.Text := Root.AsJSON;
    ForceDirectories(ExtractFileDir(FDestinationPath));
    TempPath := FDestinationPath + '.tmp';
    Text.SaveToFile(TempPath);
    if not PublishTempFile(TempPath, FDestinationPath,
      PublishError) then
      raise Exception.CreateFmt('Cannot publish destinations (%d)',
        [PublishError]);
    EnterCriticalSection(FLock);
    try
      FPublishedDestinationsRevision := PublishedRevision;
      FLastDestinationsPublishMs := GetTickCount64;
    finally
      LeaveCriticalSection(FLock);
    end;
  finally
    Text.Free;
    Root.Free;
  end;
end;

procedure TLimiterEngine.LoadRules;
var
  Settings: TSettings;
  Rules: TRules;
  ErrorText: string;
  I: Integer;
  OldActive, NewActive: Boolean;
  Changed: Boolean;
  Handle: THandle;
begin
  if not LoadConfig(FConfigPath, Settings, Rules, ErrorText) then
  begin
    SetStatus('Configuration error: ' + ErrorText);
    Exit;
  end;
  EnterCriticalSection(FLock);
  try
    // Compare against the mode last requested from the network worker.
    // Re-evaluating both sides at the current time misses schedule edges.
    OldActive := FActiveLimits;
    Changed := (FSettings.Paused <> Settings.Paused) or
      (FSettings.GlobalRule.Enabled <> Settings.GlobalRule.Enabled) or
      (FSettings.GlobalRule.Blocked <> Settings.GlobalRule.Blocked) or
      (FSettings.GlobalRule.ScheduleEnabled <>
        Settings.GlobalRule.ScheduleEnabled) or
      (FSettings.GlobalRule.BlockOutsideSchedule <>
        Settings.GlobalRule.BlockOutsideSchedule) or
      (FSettings.GlobalRule.ScheduleStartMin <>
        Settings.GlobalRule.ScheduleStartMin) or
      (FSettings.GlobalRule.ScheduleEndMin <>
        Settings.GlobalRule.ScheduleEndMin) or
      (FSettings.GlobalRule.ScheduleDays <>
        Settings.GlobalRule.ScheduleDays) or
      (FSettings.GlobalRule.QuotaBytes <> Settings.GlobalRule.QuotaBytes) or
      (FSettings.GlobalRule.QuotaPeriod <> Settings.GlobalRule.QuotaPeriod) or
      (FSettings.GlobalRule.QuotaSlowBps <>
        Settings.GlobalRule.QuotaSlowBps) or
      (FSettings.GlobalRule.BlockAfterQuota <>
        Settings.GlobalRule.BlockAfterQuota) or
      (Length(FRules) <> Length(Rules));
    if not Changed then
      for I := 0 to High(Rules) do
        if not SameWindowsPath(FRules[I].Path, Rules[I].Path) or
          (FRules[I].Enabled <> Rules[I].Enabled) or
          (FRules[I].Blocked <> Rules[I].Blocked) or
          (FRules[I].DownloadBps <> Rules[I].DownloadBps) or
          (FRules[I].UploadBps <> Rules[I].UploadBps) or
          (FRules[I].ScheduleEnabled <> Rules[I].ScheduleEnabled) or
          (FRules[I].BlockOutsideSchedule <> Rules[I].BlockOutsideSchedule) or
          (FRules[I].ScheduleStartMin <> Rules[I].ScheduleStartMin) or
          (FRules[I].ScheduleEndMin <> Rules[I].ScheduleEndMin) or
          (FRules[I].ScheduleDays <> Rules[I].ScheduleDays) or
          (FRules[I].QuotaBytes <> Rules[I].QuotaBytes) or
          (FRules[I].QuotaPeriod <> Rules[I].QuotaPeriod) or
          (FRules[I].QuotaSlowBps <> Rules[I].QuotaSlowBps) or
          (FRules[I].BlockAfterQuota <> Rules[I].BlockAfterQuota) then
        begin
          Changed := True;
          Break;
        end;
    FSettings := Settings;
    if Changed then FGlobalQuotaKey := '';
    UpdateGlobalQuota;
    if Changed then
    begin
      FGlobalDueUs[0] := 0;
      FGlobalDueUs[1] := 0;
      FRules := Rules;
      SetLength(FDueUs, Length(FRules));
      for I := 0 to High(FDueUs) do
      begin
        FDueUs[I][0] := 0;
        FDueUs[I][1] := 0;
      end;
      for I := 0 to High(FApps) do
      begin
        FApps[I].RuleIndex := FindRule(FApps[I].Path);
        FApps[I].QuotaKey := '';
        UpdateQuota(I);
      end;
    end;
    NewActive := HasActiveLimits;
    FActiveLimits := NewActive;
    Handle := FNetworkHandle;
  finally
    LeaveCriticalSection(FLock);
  end;
  if (OldActive <> NewActive) and (Handle <> INVALID_HANDLE_VALUE) then
    WinDivertShutdown(Handle, WD_SHUTDOWN_RECV);
end;

procedure TLimiterEngine.WriteState;
var
  Root, App, Session, ProcessItem: TJSONObject;
  Apps, Sessions, Processes: TJSONArray;
  Text: TStringList;
  I, J: Integer;
  ElapsedMs, NowMs: QWord;
  TempPath, StatusText: string;
  PublishError: DWORD;
begin
  Root := TJSONObject.Create;
  Text := TStringList.Create;
  try
    Apps := TJSONArray.Create;
    Root.Add('apps', Apps);
    Sessions := TJSONArray.Create;
    Root.Add('sessions', Sessions);
    EnterCriticalSection(FLock);
    try
      PruneExitedProcesses;
      NowMs := GetTickCount64;
      ElapsedMs := NowMs - FLastWindowMs;
      if ElapsedMs = 0 then ElapsedMs := 1;
      FLastWindowMs := NowMs;
      StatusText := FLastStatus;
      for I := 0 to High(FApps) do
      begin
        FApps[I].RateDown := FApps[I].WindowDown * 1000 div ElapsedMs;
        FApps[I].RateUp := FApps[I].WindowUp * 1000 div ElapsedMs;
        FApps[I].WindowDown := 0;
        FApps[I].WindowUp := 0;
        if NowMs - FApps[I].LastPacketMs > 60000 then Continue;
        App := TJSONObject.Create;
        App.Add('path', FApps[I].Path);
        App.Add('downloadBps', Int64(FApps[I].RateDown));
        App.Add('uploadBps', Int64(FApps[I].RateUp));
        App.Add('downloadBytes', Int64(FApps[I].DownloadBytes));
        App.Add('uploadBytes', Int64(FApps[I].UploadBytes));
        App.Add('quotaUsedBytes', Int64(FApps[I].QuotaUsed));
        App.Add('localDownloadBytes', Int64(FApps[I].LocalDownloadBytes));
        App.Add('localUploadBytes', Int64(FApps[I].LocalUploadBytes));
        if FApps[I].Uncertain then App.Add('scope', 'uncertain')
        else App.Add('scope', 'public IP');
        Apps.Add(App);
      end;
      for I := 0 to High(FApps) do
      begin
        Processes := TJSONArray.Create;
        for J := 0 to High(FAppProcesses) do
          if (FAppProcesses[J].AppIndex = I) and
            (FAppProcesses[J].StartTime <> 0) then
          begin
            ProcessItem := TJSONObject.Create;
            ProcessItem.Add('pid', Int64(FAppProcesses[J].ProcessId));
            ProcessItem.Add('startTime', Int64(FAppProcesses[J].StartTime));
            Processes.Add(ProcessItem);
          end;
        if Processes.Count = 0 then
        begin
          Processes.Free;
          Continue;
        end;
        Session := TJSONObject.Create;
        Session.Add('path', FApps[I].Path);
        Session.Add('downloadBytes', Int64(FApps[I].DownloadBytes));
        Session.Add('uploadBytes', Int64(FApps[I].UploadBytes));
        Session.Add('localDownloadBytes',
          Int64(FApps[I].LocalDownloadBytes));
        Session.Add('localUploadBytes', Int64(FApps[I].LocalUploadBytes));
        Session.Add('uncertain', FApps[I].Uncertain);
        Session.Add('processes', Processes);
        Sessions.Add(Session);
      end;
      Root.Add('status', StatusText);
      Root.Add('ruleCount', Length(FRules));
      Root.Add('unattributedPackets', Int64(FUnattributedPackets));
      Root.Add('flowTableRebuilds', Int64(FFlowTableRebuilds));
      Root.Add('flowTableFull', Int64(FFlowTableFull));
      Root.Add('droppedPackets', Int64(FDroppedPackets));
      Root.Add('immediatePackets', Int64(FImmediatePackets));
      Root.Add('queuedPackets', Int64(FQueuedPackets));
      Root.Add('paused', FSettings.Paused);
      Root.Add('sessionDownloadBytes', Int64(FGlobalSessionDown));
      Root.Add('sessionUploadBytes', Int64(FGlobalSessionUp));
      Root.Add('globalQuotaUsedBytes', Int64(FGlobalQuotaUsed));
    finally
      LeaveCriticalSection(FLock);
    end;
    Text.Text := Root.AsJSON;
    ForceDirectories(ExtractFileDir(FStatePath));
    TempPath := FStatePath + '.tmp';
    Text.SaveToFile(TempPath);
    if not PublishTempFile(TempPath, FStatePath, PublishError) then
      raise Exception.CreateFmt('Cannot publish state (%d)',
        [PublishError]);
  finally
    Text.Free;
    Root.Free;
  end;
end;

procedure TFlowThread.Execute;
var
  Address: TDivertAddress;
  Length: LongWord;
  OldHandle, NewHandle: THandle;
  ErrorCode: DWORD;
  FailedOpens: Integer;
begin
  try
    while Engine.FRunning do
    begin
      FillChar(Address, SizeOf(Address), 0);
      Length := 0;
      if not WinDivertRecv(Engine.FFlowHandle, nil, 0, @Length, @Address) then
      begin
        ErrorCode := GetLastError;
        EnterCriticalSection(Engine.FLock);
        try
          if not Engine.FRunning then Break;
          OldHandle := Engine.FFlowHandle;
          Engine.FFlowHandle := INVALID_HANDLE_VALUE;
        finally
          LeaveCriticalSection(Engine.FLock);
        end;
        Engine.LogDiagnostic('Flow receive failed (' +
          IntToStr(ErrorCode) + '); reopening backend');
        Engine.SetStatus('Reconnecting flow backend (' +
          IntToStr(ErrorCode) + ')');
        if OldHandle <> INVALID_HANDLE_VALUE then
          WinDivertClose(OldHandle);
        FailedOpens := 0;
        while Engine.FRunning do
        begin
          NewHandle := WinDivertOpen('true', WD_FLOW, 0,
            WD_FLAG_SNIFF or WD_FLAG_RECV_ONLY);
          if NewHandle <> INVALID_HANDLE_VALUE then
          begin
            EnterCriticalSection(Engine.FLock);
            try
              if Engine.FRunning then
              begin
                Engine.FFlowHandle := NewHandle;
                NewHandle := INVALID_HANDLE_VALUE;
              end;
            finally
              LeaveCriticalSection(Engine.FLock);
            end;
            if NewHandle <> INVALID_HANDLE_VALUE then
              WinDivertClose(NewHandle)
            else
            begin
              Engine.LogDiagnostic('Flow backend recovered');
              Engine.SetStatus('Flow backend recovered');
            end;
            Break;
          end;
          Inc(FailedOpens);
          if (FailedOpens = 1) or (FailedOpens mod 30 = 0) then
            Engine.LogDiagnostic('Flow backend reopen failed (' +
              IntToStr(GetLastError) + '), attempt ' +
              IntToStr(FailedOpens));
          Sleep(1000);
        end;
        Continue;
      end;
      case EventCode(Address) of
        WD_FLOW_ESTABLISHED: Engine.AddFlow(Address);
        WD_FLOW_DELETED: Engine.DeleteFlow(Address);
      end;
    end;
  except
    on E: Exception do
    begin
      Engine.SetStatus('Flow worker failed: ' + E.Message);
      Engine.LogDiagnostic('Fatal flow worker error: ' + E.Message);
      ExitProcess(1);
    end;
  end;
end;

procedure TNetworkThread.Execute;
var
  NetHandle: THandle;
  Diverted, Desired: Boolean;
  Address: TDivertAddress;
  Packet: array[0..65535] of Byte;
  Length: LongWord;
  Flags: QWord;
  ErrorCode, LastOpenError: DWORD;
  ConsecutiveReceiveErrors: Integer;
begin
  NetHandle := INVALID_HANDLE_VALUE;
  Diverted := False;
  LastOpenError := 0;
  ConsecutiveReceiveErrors := 0;
  try
    while Engine.FRunning do
    begin
    EnterCriticalSection(Engine.FLock);
    try
      Desired := Engine.HasActiveLimits;
    finally
      LeaveCriticalSection(Engine.FLock);
    end;
    if (NetHandle = INVALID_HANDLE_VALUE) or (Diverted <> Desired) then
    begin
      if NetHandle <> INVALID_HANDLE_VALUE then
      begin
        Engine.DrainQueue;
        WinDivertClose(NetHandle);
        NetHandle := INVALID_HANDLE_VALUE;
      end;
      Flags := 0;
      if not Desired then Flags := WD_FLAG_SNIFF;
      NetHandle := WinDivertOpen('(tcp or udp) and !loopback', WD_NETWORK,
        0, Flags);
      if NetHandle = INVALID_HANDLE_VALUE then
      begin
        ErrorCode := GetLastError;
        Engine.SetStatus('Network backend error ' + IntToStr(ErrorCode));
        if ErrorCode <> LastOpenError then
          Engine.LogDiagnostic('Network backend open failed (' +
            IntToStr(ErrorCode) + ')');
        LastOpenError := ErrorCode;
        Sleep(1000);
        Continue;
      end;
      if LastOpenError <> 0 then
        Engine.LogDiagnostic('Network backend recovered');
      LastOpenError := 0;
      Diverted := Desired;
      EnterCriticalSection(Engine.FLock);
      try
        Engine.FNetworkHandle := NetHandle;
        if Diverted then Engine.FLastStatus := 'Limits active'
        else Engine.FLastStatus := 'Monitoring (limits paused or unset)';
      finally
        LeaveCriticalSection(Engine.FLock);
      end;
    end;
    if not Engine.FRunning then Break;
    FillChar(Address, SizeOf(Address), 0);
    Length := 0;
    if WinDivertRecv(NetHandle, @Packet[0], SizeOf(Packet), @Length,
      @Address) then
    begin
      ConsecutiveReceiveErrors := 0;
      Engine.ProcessPacket(Address, @Packet[0], Length, Diverted, NetHandle);
    end
    else
    begin
      ErrorCode := GetLastError;
      if Engine.FRunning and (ErrorCode <> ERROR_NO_DATA) then
      begin
        if ConsecutiveReceiveErrors < High(Integer) then
          Inc(ConsecutiveReceiveErrors);
        if (ConsecutiveReceiveErrors = 1) or
          (ConsecutiveReceiveErrors mod 30 = 0) then
          Engine.LogDiagnostic('Network receive failed (' +
            IntToStr(ErrorCode) + '); reopening backend, attempt ' +
            IntToStr(ConsecutiveReceiveErrors));
      end;
      Engine.DrainQueue;
      WinDivertClose(NetHandle);
      NetHandle := INVALID_HANDLE_VALUE;
      EnterCriticalSection(Engine.FLock);
      try
        Engine.FNetworkHandle := INVALID_HANDLE_VALUE;
      finally
        LeaveCriticalSection(Engine.FLock);
      end;
      if Engine.FRunning and (ErrorCode <> ERROR_NO_DATA) then
        Sleep(1000);
    end;
    end;
  except
    on E: Exception do
    begin
      if NetHandle <> INVALID_HANDLE_VALUE then WinDivertClose(NetHandle);
      Engine.SetStatus('Network worker failed: ' + E.Message);
      Engine.LogDiagnostic('Fatal network worker error: ' + E.Message);
      ExitProcess(1);
    end;
  end;
  if NetHandle <> INVALID_HANDLE_VALUE then
  begin
    Engine.DrainQueue;
    WinDivertClose(NetHandle);
  end;
  EnterCriticalSection(Engine.FLock);
  try
    Engine.FNetworkHandle := INVALID_HANDLE_VALUE;
  finally
    LeaveCriticalSection(Engine.FLock);
  end;
end;

procedure TSenderThread.Execute;
var
  Item: PQueuedPacket;
  Direction: Integer;
  Sent: LongWord;
  Timer: THandle;
  Handles: array[0..1] of THandle;
  DelayUs, CurrentUs: QWord;
  DueTime: Int64;
  DoneSending: Boolean;
  DropQueued: Boolean;
  RuleIndex: Integer;
  HighResolutionTimer, ResolutionRaised: Boolean;
begin
  Timer := CreateWaitableTimerExRaw(nil, nil,
    CreateWaitableTimerHighResolution, TimerAllAccess);
  HighResolutionTimer := Timer <> 0;
  if Timer = 0 then
    Timer := CreateWaitableTimerExRaw(nil, nil, 0, TimerAllAccess);
  if Timer = 0 then
  begin
    Engine.SetStatus('Packet timer error ' + IntToStr(GetLastError));
    Engine.LogDiagnostic('Fatal packet timer creation error (' +
      IntToStr(GetLastError) + ')');
    ExitProcess(1);
  end;
  Handles[0] := Engine.FQueueEvent;
  Handles[1] := Timer;
  ResolutionRaised := False;
  try
    repeat
    Item := nil;
    DelayUs := 0;
    DoneSending := False;
    Direction := 0;
    EnterCriticalSection(Engine.FLock);
    try
      if (Engine.FQueueHead[0] = nil) or
        ((Engine.FQueueHead[1] <> nil) and
          (Engine.FQueueHead[1]^.DueUs < Engine.FQueueHead[0]^.DueUs)) then
        Direction := 1;
      CurrentUs := NowUs;
      if (Engine.FQueueHead[Direction] <> nil) and
        ((Engine.FQueueHead[Direction]^.DueUs <= CurrentUs) or
          not Engine.FRunning or Engine.FFlushQueue) then
      begin
        Item := Engine.FQueueHead[Direction];
        Engine.FQueueHead[Direction] := Item^.Next;
        if Engine.FQueueHead[Direction] = nil then
          Engine.FQueueTail[Direction] := nil;
        Dec(Engine.FQueueBytes, Item^.PacketLength);
        Inc(Engine.FSendInFlight);
      end;
      if Item = nil then
      begin
        DoneSending := not Engine.FRunning and
          (Engine.FQueueHead[0] = nil) and (Engine.FQueueHead[1] = nil);
        if Engine.FQueueHead[Direction] <> nil then
          DelayUs := Engine.FQueueHead[Direction]^.DueUs - CurrentUs;
      end;
    finally
      LeaveCriticalSection(Engine.FLock);
    end;
    if Item <> nil then
    begin
      EnterCriticalSection(Engine.FLock);
      try
        DropQueued := (Item^.Scope <> tsLocal) and
          RuleBlocksTrafficAt(Engine.FSettings.GlobalRule, Now,
            Engine.FGlobalQuotaUsed);
        if Item^.AppIndex >= 0 then
        begin
          RuleIndex := Engine.FApps[Item^.AppIndex].RuleIndex;
          if RuleIndex >= 0 then Engine.UpdateQuota(Item^.AppIndex);
          if (RuleIndex >= 0) and
            RuleBlocksTrafficAt(Engine.FRules[RuleIndex], Now,
              Engine.FApps[Item^.AppIndex].QuotaUsed) then
            DropQueued := True;
        end;
      finally
        LeaveCriticalSection(Engine.FLock);
      end;
      if not DropQueued then
      begin
        Sent := 0;
        if not WinDivertSend(Item^.Handle, @Item^.Packet[0],
          Item^.PacketLength, @Sent, @Item^.Address) or
          (Sent <> Item^.PacketLength) then
          DropQueued := True;
      end;
      if DropQueued then
      begin
        EnterCriticalSection(Engine.FLock);
        try
          Inc(Engine.FDroppedPackets);
        finally
          LeaveCriticalSection(Engine.FLock);
        end;
      end;
      EnterCriticalSection(Engine.FLock);
      try
        Dec(Engine.FSendInFlight);
      finally
        LeaveCriticalSection(Engine.FLock);
      end;
      Dispose(Item);
    end
    else if DoneSending then Break
    else if DelayUs = 0 then
    begin
      if ResolutionRaised then
      begin
        TimeEndPeriodRaw(1);
        ResolutionRaised := False;
      end;
      WaitForSingleObject(Engine.FQueueEvent, INFINITE)
    end
    else
    begin
      if not HighResolutionTimer and not ResolutionRaised then
        ResolutionRaised := TimeBeginPeriodRaw(1) = 0;
      DueTime := -Int64(DelayUs * 10);
      if not SetWaitableTimerRaw(Timer, @DueTime, 0, nil, nil, False) then
        raise Exception.CreateFmt('Packet timer scheduling error %d',
          [GetLastError]);
      WaitForMultipleObjectsRaw(2, @Handles[0], False, INFINITE);
    end;
    until False;
  except
    on E: Exception do
    begin
      Engine.SetStatus('Packet sender failed: ' + E.Message);
      Engine.LogDiagnostic('Fatal packet sender error: ' + E.Message);
      ExitProcess(1);
    end;
  end;
  if ResolutionRaised then TimeEndPeriodRaw(1);
  CloseHandle(Timer);
end;

procedure TStatusThread.Execute;
var
  I: Integer;
  Today, StateIssue, DestinationIssue: string;
begin
  StateIssue := '';
  DestinationIssue := '';
  try
    while Engine.FRunning do
    begin
      Today := FormatDateTime('yyyy-mm-dd', Date);
      EnterCriticalSection(Engine.FLock);
      try
        if Engine.FCurrentDay <> Today then
        begin
          Engine.FCurrentDay := Today;
          Engine.FGlobalDayIndex := -1;
          Engine.FGlobalQuotaKey := '';
          for I := 0 to High(Engine.FApps) do
          begin
            Engine.FApps[I].DayIndex := -1;
            Engine.FApps[I].QuotaKey := '';
          end;
          for I := 0 to High(Engine.FFlows) do
            if Engine.FFlows[I].Used then
              Engine.FFlows[I].HistoryIndex := -1;
          Engine.PruneHistory;
          Engine.UpdateGlobalQuota;
          for I := 0 to High(Engine.FApps) do
            Engine.UpdateQuota(I);
        end;
      finally
        LeaveCriticalSection(Engine.FLock);
      end;
      Engine.LoadRules;
      try
        Engine.WriteState;
        if StateIssue <> '' then
          Engine.LogDiagnostic('State publication recovered');
        StateIssue := '';
      except
        on E: Exception do
        begin
          if StateIssue <> E.Message then
            Engine.LogDiagnostic('State publication failed: ' + E.Message);
          StateIssue := E.Message;
        end;
      end;
      try
        Engine.WriteDestinations;
        if DestinationIssue <> '' then
          Engine.LogDiagnostic('Destination publication recovered');
        DestinationIssue := '';
      except
        on E: Exception do
        begin
          if DestinationIssue <> E.Message then
            Engine.LogDiagnostic('Destination publication failed: ' +
              E.Message);
          DestinationIssue := E.Message;
        end;
      end;
      Engine.WriteHistory(False);
      for I := 1 to 10 do
      begin
        if not Engine.FRunning then Break;
        Sleep(100);
      end;
    end;
  except
    on E: Exception do
    begin
      Engine.SetStatus('Status worker failed: ' + E.Message);
      Engine.LogDiagnostic('Fatal status worker error: ' + E.Message);
      ExitProcess(1);
    end;
  end;
end;

procedure TLimiterEngine.Start;
begin
  if FRunning then Exit;
  LoadHistory;
  // Load saved rules before either packet worker starts. In particular, a
  // saved block must select the diverting network mode from the first open.
  LoadRules;
  LoadSessionCheckpoint;
  FFlowHandle := WinDivertOpen('true', WD_FLOW, 0,
    WD_FLAG_SNIFF or WD_FLAG_RECV_ONLY);
  if FFlowHandle = INVALID_HANDLE_VALUE then
    raise Exception.CreateFmt('Flow backend error %d', [GetLastError]);
  FRunning := True;
  FLastWindowMs := GetTickCount64;
  try
    FFlowThread := TFlowThread.Create(Self);
    // The sender must exist before network capture can enqueue packets.
    FSenderThread := TSenderThread.Create(Self);
    FNetworkThread := TNetworkThread.Create(Self);
    FStatusThread := TStatusThread.Create(Self);
  except
    Stop;
    raise;
  end;
end;

procedure TLimiterEngine.Stop;
var
  Handle, FlowHandle: THandle;
  I: Integer;
begin
  if not FRunning then Exit;
  EnterCriticalSection(FLock);
  try
    FRunning := False;
    Handle := FNetworkHandle;
    FlowHandle := FFlowHandle;
    SetEvent(FQueueEvent);
  finally
    LeaveCriticalSection(FLock);
  end;
  if FlowHandle <> INVALID_HANDLE_VALUE then
    WinDivertShutdown(FlowHandle, WD_SHUTDOWN_RECV);
  if Handle <> INVALID_HANDLE_VALUE then
    WinDivertShutdown(Handle, WD_SHUTDOWN_RECV);
  if FFlowThread <> nil then FFlowThread.WaitFor;
  if FNetworkThread <> nil then FNetworkThread.WaitFor;
  if FSenderThread <> nil then FSenderThread.WaitFor;
  if FStatusThread <> nil then FStatusThread.WaitFor;
  FreeAndNil(FFlowThread);
  FreeAndNil(FNetworkThread);
  FreeAndNil(FSenderThread);
  FreeAndNil(FStatusThread);
  for I := 0 to High(FAppProcesses) do
    CloseHandle(FAppProcesses[I].Handle);
  SetLength(FAppProcesses, 0);
  WinDivertClose(FFlowHandle);
  FFlowHandle := INVALID_HANDLE_VALUE;
  SetStatus('Stopped');
  try WriteState; except end;
  WriteHistory(True);
end;

initialization
  PerformanceFrequency := 0;
  QueryPerformanceFrequencyRaw(PerformanceFrequency);

end.
