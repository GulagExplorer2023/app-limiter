$ErrorActionPreference = 'Stop'
$config = 'C:\ProgramData\AppLimiter\Users\Brendon\config.json'
$state = 'C:\ProgramData\AppLimiter\state.json'
$original = [IO.File]::ReadAllText($config)
function Publish-Config([string]$content) {
    $temp = $config + '.acceptance.tmp'
    [IO.File]::WriteAllText($temp, $content, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $config -Force
}
try {
    $test = $original | ConvertFrom-Json
    $test.rules = @($test.rules) + [pscustomobject]@{
        path = 'C:\Windows\System32\curl.exe'
        downloadBps = 0
        uploadBps = 0
        enabled = $true
        scheduleEnabled = $false
        scheduleStartMin = 0
        scheduleEndMin = 0
        scheduleDays = 127
        quotaBytes = 1
        quotaPeriod = 'monthly'
        quotaSlowBps = 4096
    }
    Publish-Config ($test | ConvertTo-Json -Depth 10)
    Start-Sleep -Seconds 2
    $current = Get-Content -Raw -LiteralPath $state | ConvertFrom-Json
    if ($current.ruleCount -lt 2) { throw 'Service did not load the temporary rule.' }
    & 'C:\Windows\System32\curl.exe' -L -sS -o NUL -w 'http=%{http_code} bytes=%{size_download} time=%{time_total}\n' --max-time 25 https://example.com
    if ($LASTEXITCODE -ne 0) { throw "curl failed with exit code $LASTEXITCODE" }
    Start-Sleep -Seconds 1
    $current = Get-Content -Raw -LiteralPath $state | ConvertFrom-Json
    $entry = $current.apps | Where-Object path -eq 'C:\Windows\System32\curl.exe' | Select-Object -First 1
    if (-not $entry -or $entry.quotaUsedBytes -lt 1) { throw 'Quota usage was not reported.' }
    "quotaUsedBytes=$($entry.quotaUsedBytes) droppedPackets=$($current.droppedPackets)"
} finally {
    Publish-Config $original
    Start-Sleep -Seconds 2
}
