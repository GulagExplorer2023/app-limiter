$ErrorActionPreference = 'Stop'
$configPath = Join-Path $env:ProgramData "AppLimiter\Users\$env:USERNAME\config.json"
$statePath = Join-Path $env:ProgramData 'AppLimiter\state.json'
$original = [IO.File]::ReadAllBytes($configPath)
$config = [Text.Encoding]::UTF8.GetString($original) | ConvertFrom-Json
if ($config.paused -or @($config.rules).Count -ne 0) {
    throw 'This test expects an unpaused installation with no saved rules.'
}
if ((Get-Date).Hour -eq 23 -and (Get-Date).Minute -eq 59) {
    throw 'Run this check before the last minute of the day.'
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ScheduleConfigPublish {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, EntryPoint="MoveFileExW", SetLastError=true)]
  public static extern bool Move(string source, string destination, uint flags);
}
'@
function Publish-Config([byte[]]$bytes) {
    $temp = "$configPath.schedule.tmp"
    [IO.File]::WriteAllBytes($temp, $bytes)
    if (-not [ScheduleConfigPublish]::Move($temp, $configPath, 9)) {
        throw "Could not publish schedule test configuration: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
}
function Wait-Status([string]$expected, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($state.status -eq $expected) { return $state }
        Start-Sleep -Milliseconds 250
    }
    throw "Service did not enter '$expected' within $seconds seconds."
}

$now = Get-Date
if ($now.Second -gt 45) {
    Start-Sleep -Seconds (62 - $now.Second)
    $now = Get-Date
}
$startMinute = $now.Hour * 60 + $now.Minute
$endMinute = $startMinute + 1
$dayBit = ([int]$now.DayOfWeek + 6) % 7
$rule = [ordered]@{
    path = 'C:\Windows\System32\curl.exe'
    downloadBps = 1048576
    uploadBps = 1048576
    enabled = $true
    scheduleEnabled = $true
    scheduleStartMin = $startMinute
    scheduleEndMin = $endMinute
    scheduleDays = (1 -shl $dayBit)
    quotaBytes = 0
    quotaPeriod = 'monthly'
    quotaSlowBps = 0
}
$config.rules = @($rule)
try {
    Publish-Config ([Text.Encoding]::UTF8.GetBytes(($config | ConvertTo-Json -Depth 10)))
    $active = Wait-Status 'Limits active' 10
    $monitoring = Wait-Status 'Monitoring (limits paused or unset)' 70
    "Schedule switched from active to monitoring at $((Get-Date).ToString('HH:mm:ss')); droppedPackets=$($monitoring.droppedPackets)"
} finally {
    Publish-Config $original
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($state.ruleCount -eq 0) { break }
        Start-Sleep -Milliseconds 250
    }
}
