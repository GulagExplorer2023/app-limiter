param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
)
$ErrorActionPreference = 'Stop'
$runDir = Join-Path $Root 'acceptance\latency_run'
$config = Join-Path $runDir 'config.json'
$state = Join-Path $runDir 'state.json'
$serviceExe = Join-Path $Root 'dist\AppLimiter\app_limiter_service.exe'
$curl = (Get-Command curl.exe -ErrorAction Stop).Source
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'The latency test must run from an administrator PowerShell session so WinDivert can open its FLOW layer.'
}
$serviceStopped = $false
$probe = $null

function Wait-ServiceState([string]$wanted) {
    for ($i = 0; $i -lt 100; $i++) {
        if ((Get-Service AppLimiterService).Status.ToString() -eq $wanted) { return }
        Start-Sleep -Milliseconds 100
    }
    throw "AppLimiterService did not reach $wanted"
}

function Save-TestConfig([bool]$limited) {
    $rules = @()
    if ($limited) {
        $rules = @(@{
            path = $curl
            downloadBps = 3 * 1024 * 1024
            uploadBps = 3 * 1024 * 1024
            enabled = $true
        })
    }
    $body = @{
        version = 1
        paused = $false
        rules = $rules
    } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($config, $body)
}

function Measure-Requests([int]$count) {
    $times = @()
    for ($i = 0; $i -lt $count; $i++) {
        $measurement = & $curl -sS -o NUL --max-time 10 -w '%{time_total}' -I 'https://example.com'
        if ($LASTEXITCODE -ne 0) { throw "curl latency probe failed: $measurement" }
        $times += [double]::Parse($measurement, [Globalization.CultureInfo]::InvariantCulture) * 1000
    }
    return $times
}

function Median([double[]]$numbers) {
    $sorted = @($numbers | Sort-Object)
    return $sorted[[int][Math]::Floor($sorted.Count / 2)]
}

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Save-TestConfig $false
try {
    & sc.exe stop AppLimiterService | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop installed limiter service' }
    Wait-ServiceState 'Stopped'
    $serviceStopped = $true

    $probe = Start-Process -FilePath $serviceExe -ArgumentList @('--console', "`"$config`"", "`"$state`"", '30') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runDir 'console.out') -RedirectStandardError (Join-Path $runDir 'console.err')
    Start-Sleep -Seconds 3
    if ($probe.HasExited) { throw "Test backend exited early: $($probe.ExitCode)" }

    $baseline = @(Measure-Requests 12)
    Save-TestConfig $true
    Start-Sleep -Seconds 2
    $limited = @(Measure-Requests 12)
    $transfer = & $curl -sS -o NUL --max-time 20 -w 'bytes=%{size_download} seconds=%{time_total} code=%{http_code}' 'https://speed.cloudflare.com/__down?bytes=4194304'
    if ($LASTEXITCODE -ne 0) { throw "curl transfer failed: $transfer" }
    Start-Sleep -Seconds 2
    $backendState = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
    if ($backendState.ruleCount -ne 1) { throw 'The test rate was not loaded' }
    if ($backendState.immediatePackets -lt 1) { throw 'No packets used the immediate send path' }
    $result = [ordered]@{
        baselineMs = $baseline
        limitedMs = $limited
        baselineMedianMs = (Median $baseline)
        limitedMedianMs = (Median $limited)
        medianAddedMs = ((Median $limited) - (Median $baseline))
        transfer = $transfer
        immediatePackets = $backendState.immediatePackets
        queuedPackets = $backendState.queuedPackets
        droppedPackets = $backendState.droppedPackets
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'result.json')
    $result | ConvertTo-Json -Depth 5
} finally {
    if ($probe -and !$probe.HasExited) {
        $probe.WaitForExit(35000) | Out-Null
        if (!$probe.HasExited) { Stop-Process -Id $probe.Id -Force }
    }
    if ($serviceStopped) {
        & sc.exe start AppLimiterService | Out-Null
        Wait-ServiceState 'Running'
    }
}
