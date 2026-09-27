param(
    [ValidateRange(1, 10080)][int]$DurationMinutes = 120,
    [ValidateRange(1, 60)][int]$SampleSeconds = 5,
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
$statePath = Join-Path $env:ProgramData 'AppLimiter\state.json'
if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot ('backend-soak-' + $started.ToString('yyyyMMdd-HHmmss') + '.csv')
}
$installation = (Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AppLimiter' -ErrorAction SilentlyContinue).InstallLocation
if (-not $installation) { $installation = Join-Path $env:ProgramFiles 'AppLimiter' }
$serviceBinary = Join-Path $installation 'app_limiter_service.exe'
if (-not (Test-Path -LiteralPath $serviceBinary)) { throw 'Installed service binary not found.' }
$version = (Get-Item -LiteralPath $serviceBinary).VersionInfo.FileVersion
$end = $started.AddMinutes($DurationMinutes)
$previousTotals = @{}
$rows = [System.Collections.Generic.List[object]]::new()
$staleSamples = 0
$counterResets = 0

do {
    $timestamp = Get-Date
    $ageSeconds = [double]::PositiveInfinity
    $status = 'State unavailable'
    $appCount = 0
    $sessionCount = 0
    $sampleResets = 0
    try {
        $file = Get-Item -LiteralPath $statePath -ErrorAction Stop
        $ageSeconds = ($timestamp.ToUniversalTime() - $file.LastWriteTimeUtc).TotalSeconds
        $state = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json
        $status = [string]$state.status
        $appCount = @($state.apps).Count
        foreach ($session in @($state.sessions)) {
            if ($null -eq $session -or $null -eq $session.processes) { continue }
            $sessionCount++
            $total = [long]$session.downloadBytes + [long]$session.uploadBytes
            foreach ($process in @($session.processes)) {
                $key = [string]$session.path + '|' + [string]$process.pid + '|' + [string]$process.startTime
                if ($previousTotals.ContainsKey($key) -and $total -lt $previousTotals[$key]) {
                    $sampleResets++
                }
                $previousTotals[$key] = $total
            }
        }
    } catch {
        $status = 'State read error: ' + $_.Exception.Message
    }
    if ($ageSeconds -gt 10 -or $ageSeconds -lt -10) { $staleSamples++ }
    $counterResets += $sampleResets
    $rows.Add([pscustomobject]@{
        Time = $timestamp.ToString('o')
        InstalledVersion = $version
        StateAgeSeconds = [math]::Round($ageSeconds, 2)
        Status = $status
        VisibleApps = $appCount
        LiveSessions = $sessionCount
        CounterResets = $sampleResets
    })
    if ($timestamp -ge $end) { break }
    Start-Sleep -Seconds $SampleSeconds
} while ($true)

$rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
$serviceCrashes = @(Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Service Control Manager'
    Id = 7031
    StartTime = $started
} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'App Limiter Service' }).Count
$result = [pscustomobject]@{
    InstalledVersion = $version
    Samples = $rows.Count
    StaleSamples = $staleSamples
    CounterResets = $counterResets
    ServiceCrashes = $serviceCrashes
    Results = $OutputPath
}
$result | Format-List
if ($staleSamples -gt 0 -or $counterResets -gt 0 -or $serviceCrashes -gt 0) { exit 1 }
