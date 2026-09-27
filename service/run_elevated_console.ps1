$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root 'build'
$config = Join-Path $PSScriptRoot 'test_config.json'
$state = Join-Path $PSScriptRoot 'test_state.json'
$out = Join-Path $PSScriptRoot 'test_stdout.log'
$err = Join-Path $PSScriptRoot 'test_stderr.log'
$progress = Join-Path $PSScriptRoot 'test_progress.log'
'starting' | Set-Content -LiteralPath $progress
try {
    $process = Start-Process -FilePath (Join-Path $bin 'app_limiter_service.exe') -ArgumentList @('--console', ('"' + $config + '"'), ('"' + $state + '"'), '60') -WorkingDirectory $bin -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
    "pid=$($process.Id)" | Add-Content -LiteralPath $progress
    $process.WaitForExit()
    "exit=$($process.ExitCode)" | Add-Content -LiteralPath $progress
} catch {
    "error=$_" | Add-Content -LiteralPath $progress
    throw
}
