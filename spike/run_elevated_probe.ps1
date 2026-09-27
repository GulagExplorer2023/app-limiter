$Duration = 90
$FlowsOnly = $false
if ($args.Count -ge 1) { $Duration = [int]$args[0] }
if ($args.Count -ge 2) { $FlowsOnly = ($args[1] -eq '--flows-only') }
$ErrorActionPreference = 'Stop'
$bin = Join-Path $PSScriptRoot 'bin'
Set-Location -LiteralPath $bin
$stateFile = Join-Path $bin 'probe.state'
$stdoutFile = Join-Path $bin 'probe.stdout.log'
$stderrFile = Join-Path $bin 'probe.stderr.log'
$exitFile = Join-Path $bin 'probe.exit'
Remove-Item -LiteralPath $exitFile -ErrorAction SilentlyContinue
'started' | Set-Content -LiteralPath $stateFile
try {
    $probeArgs = @('C:\Windows\System32\curl.exe', '128', '128', [string]$Duration)
    if ($FlowsOnly) { $probeArgs += '--flows-only' }
    $probe = Start-Process -FilePath (Join-Path $bin 'cap_probe.exe') -ArgumentList $probeArgs -WorkingDirectory $bin -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -WindowStyle Hidden -PassThru
    "pid=$($probe.Id)" | Add-Content -LiteralPath $stateFile
    $probe.WaitForExit()
    $probe.ExitCode | Set-Content -LiteralPath $exitFile
    "exited=$($probe.ExitCode)" | Add-Content -LiteralPath $stateFile
} catch {
    "error=$_" | Add-Content -LiteralPath $stateFile
    throw
}
