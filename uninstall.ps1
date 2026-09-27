param(
    [string]$Destination = '',
    [switch]$KeepFiles
)
$ErrorActionPreference = 'Stop'
$uninstallKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AppLimiter'
$registeredLocation = (Get-ItemProperty -Path $uninstallKey -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
if (-not $registeredLocation) { throw 'App Limiter installation location is not registered.' }
if (-not $Destination) { $Destination = $registeredLocation }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Destination "' + $Destination + '"'
    if ($KeepFiles) { $arg += ' -KeepFiles' }
    $child = Start-Process -FilePath 'powershell.exe' -ArgumentList $arg -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($child.ExitCode -ne 0) { throw "Elevated uninstaller failed with exit code $($child.ExitCode)." }
    exit
}
$expected = [IO.Path]::GetFullPath($registeredLocation).TrimEnd('\')
$root = Split-Path -Parent $PSCommandPath
$resolved = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
if (-not [string]::Equals($expected, $resolved, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove an unexpected directory: $resolved"
}
Start-Transcript -Path (Join-Path $root 'uninstall.log') -Force | Out-Null
$panelPath = Join-Path $resolved 'AppLimiter.exe'
Get-Process -Name 'AppLimiter' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and [string]::Equals($_.Path, $panelPath, [StringComparison]::OrdinalIgnoreCase) } |
    Stop-Process -Force
$ownerIdentity = (Get-ItemProperty -Path $uninstallKey -Name OwnerIdentity -ErrorAction SilentlyContinue).OwnerIdentity
$ownerSid = if ($ownerIdentity -match '^(S-1-[0-9]+(?:-[0-9]+)+)\|') { $Matches[1] } else { '' }
$expectedStartup = '"' + $panelPath + '" --startup'
$legacyStartup = '"' + $panelPath + '"'
$startupSids = @($ownerSid, $identity.User.Value) | Where-Object { $_ } | Select-Object -Unique
foreach ($sid in $startupSids) {
    $runKey = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Run"
    $entry = (Get-ItemProperty -Path $runKey -Name AppLimiter -ErrorAction SilentlyContinue).AppLimiter
    if ([string]::Equals($entry, $expectedStartup, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($entry, $legacyStartup, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-ItemProperty -Path $runKey -Name AppLimiter -ErrorAction Stop
    }
}
if (Get-Service -Name 'AppLimiterService' -ErrorAction SilentlyContinue) {
    Stop-Service -Name 'AppLimiterService' -ErrorAction SilentlyContinue
    (Get-Service -Name 'AppLimiterService').WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
    & sc.exe delete AppLimiterService
    if ($LASTEXITCODE -ne 0) { throw 'Could not delete AppLimiterService.' }
}
$shortcutPath = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'App Limiter.lnk'
$desktopPath = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'App Limiter.lnk'
$shell = New-Object -ComObject WScript.Shell
foreach ($linkPath in @($shortcutPath, $desktopPath)) {
    if (Test-Path -LiteralPath $linkPath) {
        $link = $shell.CreateShortcut($linkPath)
        if ([string]::Equals($link.TargetPath, $panelPath, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $linkPath -Force
        }
    }
}
if (-not $KeepFiles -and (Test-Path -LiteralPath $resolved)) {
    foreach ($name in @('AppLimiter.exe', 'app_limiter_service.exe', 'AppLimiter.ico', 'WinDivert.dll', 'WinDivert64.sys', 'LICENSE', 'Uninstall.exe', 'uninstall.ps1', 'run_uninstall.ps1', 'install.log')) {
        Remove-Item -LiteralPath (Join-Path $resolved $name) -Force -ErrorAction SilentlyContinue
    }
}
$stateDir = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'AppLimiter'))
foreach ($name in @('state.json', 'state.json.tmp')) {
    $stateFile = Join-Path $stateDir $name
    Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
}
$usersDir = Join-Path $stateDir 'Users'
if (Test-Path -LiteralPath $usersDir) {
    Get-ChildItem -LiteralPath $usersDir -Directory | ForEach-Object {
        foreach ($name in @('destinations.json', 'destinations.json.tmp', 'usage_history.json', 'usage_history.json.tmp')) {
            Remove-Item -LiteralPath (Join-Path $_.FullName $name) -Force -ErrorAction SilentlyContinue
        }
    }
}
Write-Host "App Limiter removed. Personal rules remain in $stateDir\Users."
Stop-Transcript | Out-Null
if (-not $KeepFiles -and (Test-Path -LiteralPath $resolved)) {
    Remove-Item -LiteralPath (Join-Path $resolved 'uninstall.log') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $resolved -ErrorAction SilentlyContinue
}
