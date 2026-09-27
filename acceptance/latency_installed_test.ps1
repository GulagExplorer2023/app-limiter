param(
    [string]$ConfigPath = (Join-Path $env:ProgramData "AppLimiter\Users\$env:USERNAME\config.json")
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$installedService = 'C:\Program Files\AppLimiter\app_limiter_service.exe'
$builtService = Join-Path $root 'dist\AppLimiter\app_limiter_service.exe'
$statePath = Join-Path $env:ProgramData 'AppLimiter\state.json'
$curl = (Get-Command curl.exe -ErrorAction Stop).Source
$resultPath = Join-Path $root 'acceptance\latency_installed_result.json'

if ((Get-FileHash -LiteralPath $installedService -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $builtService -Algorithm SHA256).Hash) {
    throw 'Install the current App Limiter build before measuring latency.'
}
if ((Get-Service AppLimiterService).Status -ne 'Running') {
    throw 'AppLimiterService is not running.'
}

$native = @'
using System;
using System.Runtime.InteropServices;
public static class AtomicConfigPublish {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, EntryPoint="MoveFileExW", SetLastError=true)]
  public static extern bool Move(string source, string destination, uint flags);
}
'@
Add-Type -TypeDefinition $native

function Publish-Config([byte[]]$bytes) {
    $temp = "$ConfigPath.latency.tmp"
    [IO.File]::WriteAllBytes($temp, $bytes)
    if (-not [AtomicConfigPublish]::Move($temp, $ConfigPath, 9)) {
        throw "Could not publish temporary test rule: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
}

function Wait-RuleCount([int]$count) {
    for ($i=0; $i -lt 50; $i++) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($state.ruleCount -eq $count) { return $state }
        Start-Sleep -Milliseconds 100
    }
    throw "Service did not load $count rules"
}

function Measure-Requests([int]$count) {
    $times = @()
    for ($i=0; $i -lt $count; $i++) {
        $measurement = & $curl -sS -o NUL --max-time 10 -w '%{time_total}' -I 'https://example.com'
        if ($LASTEXITCODE -ne 0) { throw "curl latency probe failed: $measurement" }
        $times += [double]::Parse($measurement, [Globalization.CultureInfo]::InvariantCulture) * 1000
    }
    return $times
}

function Measure-KeepAlive([int]$count) {
    $arguments = @('-sS', '--max-time', '10', '-w', "total=%{time_total} connects=%{num_connects}`n")
    for ($i=0; $i -le $count; $i++) {
        $arguments += @('-o', 'NUL', 'https://example.com/')
    }
    $measurements = & $curl @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Persistent curl probe failed' }
    $rows = @($measurements | Where-Object { $_ -match '^total=([0-9.]+) connects=([0-9]+)$' })
    if ($rows.Count -ne $count + 1) { throw "Expected $($count + 1) persistent request timings, got $($rows.Count)" }
    $times = @()
    foreach ($row in $rows | Select-Object -Skip 1) {
        $match = [regex]::Match($row, '^total=([0-9.]+) connects=0$')
        if (!$match.Success) {
            throw "Connection was not reused: $row"
        }
        $times += [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) * 1000
    }
    return $times
}

function Median([double[]]$numbers) {
    $sorted = @($numbers | Sort-Object)
    return $sorted[[int][Math]::Floor($sorted.Count / 2)]
}

$original = [IO.File]::ReadAllBytes($ConfigPath)
$config = [Text.Encoding]::UTF8.GetString($original) | ConvertFrom-Json
if ($config.paused) { throw 'Unpause limits before testing.' }
$otherRules = @($config.rules | Where-Object { $_.path -ine $curl })
$baselineConfig = $config | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$baselineConfig.rules = @($otherRules)
$wasChanged = $false
try {
    Publish-Config ([Text.Encoding]::UTF8.GetBytes(($baselineConfig | ConvertTo-Json -Depth 10)))
    $wasChanged = $true
    $baselineState = Wait-RuleCount $otherRules.Count
    Start-Sleep -Milliseconds 500
    $baseline = @(Measure-Requests 12)
    $baselineKeepAlive = @(Measure-KeepAlive 30)

    $limitedConfig = $baselineConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $limitedConfig.rules = @($otherRules) + @(@{
        path = $curl
        downloadBps = 3 * 1024 * 1024
        uploadBps = 3 * 1024 * 1024
        enabled = $true
    })
    Publish-Config ([Text.Encoding]::UTF8.GetBytes(($limitedConfig | ConvertTo-Json -Depth 10)))
    $limitedState = Wait-RuleCount ($otherRules.Count + 1)
    Start-Sleep -Milliseconds 500
    $limited = @(Measure-Requests 12)
    $beforeKeepAlive = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $limitedKeepAlive = @(Measure-KeepAlive 30)
    Start-Sleep -Milliseconds 500
    $afterKeepAlive = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $transfer = & $curl -sS -o NUL --max-time 20 -w 'bytes=%{size_download} seconds=%{time_total} code=%{http_code}' 'https://speed.cloudflare.com/__down?bytes=4194304'
    if ($LASTEXITCODE -ne 0) { throw "curl transfer failed: $transfer" }
    Start-Sleep -Milliseconds 500
    $afterState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $direct = $afterState.immediatePackets - $limitedState.immediatePackets
    if ($direct -lt 1) { throw 'No limited packets used the immediate send path.' }
    $result = [ordered]@{
        baselineMs = $baseline
        limitedMs = $limited
        baselineMedianMs = (Median $baseline)
        limitedMedianMs = (Median $limited)
        medianAddedMs = ((Median $limited) - (Median $baseline))
        baselineKeepAliveMs = $baselineKeepAlive
        limitedKeepAliveMs = $limitedKeepAlive
        keepAliveMedianAddedMs = ((Median $limitedKeepAlive) - (Median $baselineKeepAlive))
        keepAliveQueuedPackets = ($afterKeepAlive.queuedPackets - $beforeKeepAlive.queuedPackets)
        keepAliveImmediatePackets = ($afterKeepAlive.immediatePackets - $beforeKeepAlive.immediatePackets)
        transfer = $transfer
        immediatePackets = $direct
        queuedPackets = ($afterState.queuedPackets - $limitedState.queuedPackets)
        droppedPackets = ($afterState.droppedPackets - $limitedState.droppedPackets)
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath
    $result | ConvertTo-Json -Depth 5
} finally {
    if ($wasChanged) {
        Publish-Config $original
        Wait-RuleCount @($config.rules).Count | Out-Null
    }
}
