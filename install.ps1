param(
    [string]$Destination = (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'AppLimiter'),
    [string]$UserDataDir = '',
    [string]$OwnerSid = '',
    [string]$OwnerName = '',
    [string]$OwnerIdentity = '',
    [ValidateRange(0,1)][int]$DesktopShortcut = 1,
    [ValidateRange(0,1)][int]$StartWithWindows = 1
)
$ErrorActionPreference = 'Stop'
if ($OwnerIdentity) {
    $ownerParts = $OwnerIdentity.Split('|')
    if ($ownerParts.Count -ne 2) { throw 'Invalid installer owner identity.' }
    $OwnerSid = $ownerParts[0]
    $OwnerName = $ownerParts[1]
}
if (-not $OwnerSid) { $OwnerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
if (-not $OwnerName) { $OwnerName = $env:USERNAME }
if ($OwnerSid -notmatch '^S-1-[0-9]+(?:-[0-9]+)+$') { throw 'Invalid owner SID.' }
if ($OwnerName -notmatch '^[^\\/:*?"<>|\x00-\x1F]{1,128}$' -or
    $OwnerName -in @('.', '..') -or $OwnerName.EndsWith(' ') -or $OwnerName.EndsWith('.')) {
    throw 'Invalid owner account name.'
}
if (-not $UserDataDir) {
    $UserDataDir = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) (Join-Path 'AppLimiter\Users' $OwnerName)
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$configFile = Join-Path $UserDataDir 'config.json'
if (-not ('AppLimiterMachine' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AppLimiterMachine {
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool IsWow64Process2(IntPtr process, out ushort processMachine, out ushort nativeMachine);
}
'@
}
[System.UInt16]$processMachine = 0
[System.UInt16]$nativeMachine = 0
if (-not [AppLimiterMachine]::IsWow64Process2([AppLimiterMachine]::GetCurrentProcess(),
    [ref]$processMachine, [ref]$nativeMachine)) {
    throw 'Could not determine the Windows processor architecture.'
}
$windowsBuild = [Environment]::OSVersion.Version.Build
if (-not [Environment]::Is64BitOperatingSystem -or
    $windowsBuild -lt 22000 -or $nativeMachine -ne 0x8664) {
    throw 'App Limiter requires Windows 11 x64 (Intel or AMD). The bundled driver cannot run on Windows on ARM.'
}
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Destination "' + $Destination + '" -UserDataDir "' + $UserDataDir + '" -OwnerSid "' + $OwnerSid + '" -OwnerName "' + $OwnerName + '" -DesktopShortcut ' + $DesktopShortcut + ' -StartWithWindows ' + $StartWithWindows
    $child = Start-Process -FilePath 'powershell.exe' -ArgumentList $arg -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($child.ExitCode -ne 0) { throw "Elevated installer failed with exit code $($child.ExitCode)." }
    exit
}
$root = Split-Path -Parent $PSCommandPath
Start-Transcript -Path (Join-Path $root 'install.log') -Force | Out-Null
$Destination = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$programFilesRoot = [IO.Path]::GetFullPath([Environment]::GetFolderPath('ProgramFiles')).TrimEnd('\')
if (-not [string]::Equals([IO.Path]::GetDirectoryName($Destination), $programFilesRoot,
    [StringComparison]::OrdinalIgnoreCase)) {
    throw "Install App Limiter in a dedicated folder directly under $programFilesRoot so standard users cannot replace the system service."
}
$runKey = "Registry::HKEY_USERS\$OwnerSid\Software\Microsoft\Windows\CurrentVersion\Run"
if (-not (Test-Path -Path "Registry::HKEY_USERS\$OwnerSid")) {
    throw 'The installing Windows account is not signed in, so its startup setting cannot be updated.'
}
$unsafeLocations = @([IO.Path]::GetPathRoot($Destination), $env:WINDIR,
    [Environment]::GetFolderPath('ProgramFiles'),
    [Environment]::GetFolderPath('ProgramFilesX86'),
    [Environment]::GetFolderPath('CommonApplicationData'))
if ($unsafeLocations | Where-Object { $_ -and [string]::Equals($_.TrimEnd('\'), $Destination, [StringComparison]::OrdinalIgnoreCase) }) {
    throw "Choose a dedicated App Limiter folder, not $Destination."
}
$uninstallKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AppLimiter'
$previousLocation = (Get-ItemProperty -Path $uninstallKey -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
if (Test-Path -LiteralPath $Destination) {
    if ((Get-Item -LiteralPath $Destination -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Choose a folder that is not a symbolic link or junction.'
    }
    $existing = @(Get-ChildItem -LiteralPath $Destination -Force -ErrorAction Stop)
    if ($existing.Count -gt 0 -and
        (-not $previousLocation -or
         -not [string]::Equals([IO.Path]::GetFullPath($previousLocation).TrimEnd('\'), $Destination, [StringComparison]::OrdinalIgnoreCase))) {
        throw "The selected folder contains other files. Choose an empty folder or the existing App Limiter folder."
    }
}
$dist = Join-Path $root 'dist\AppLimiter'
$required = @('AppLimiter.exe', 'app_limiter_service.exe', 'AppLimiter.ico', 'WinDivert.dll', 'WinDivert64.sys', 'LICENSE')
foreach ($name in $required) {
    if (!(Test-Path -LiteralPath (Join-Path $dist $name))) { throw "Build first: missing $name" }
}
$stateDir = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'AppLimiter'
$stateFile = Join-Path $stateDir 'state.json'
New-Item -ItemType Directory -Force -Path $Destination, $stateDir | Out-Null
& icacls.exe $Destination '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not secure the installation directory.' }
foreach ($name in @('AppLimiter.exe', 'app_limiter_service.exe', 'AppLimiter.ico', 'WinDivert.dll', 'WinDivert64.sys', 'LICENSE', 'Uninstall.exe', 'uninstall.ps1', 'run_uninstall.ps1')) {
    $existingFile = Join-Path $Destination $name
    if (Test-Path -LiteralPath $existingFile) {
        & icacls.exe $existingFile '/reset' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not secure $name." }
    }
}
& icacls.exe $stateDir '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not secure backend state directory.' }
New-Item -ItemType Directory -Force -Path $UserDataDir | Out-Null
& icacls.exe $UserDataDir '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' ("*$($OwnerSid):(OI)(CI)F") | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not secure user configuration directory.' }
if (!(Test-Path -LiteralPath $configFile)) {
    $legacyConfig = if ($OwnerSid -eq $identity.User.Value) { Join-Path $env:LOCALAPPDATA 'AppLimiter\config.json' } else { '' }
    if ($legacyConfig -and (Test-Path -LiteralPath $legacyConfig)) {
        Copy-Item -LiteralPath $legacyConfig -Destination $configFile
    } else {
        $default = '{"version":1,"paused":false,"startMinimized":false,"darkTheme":true,"hotkey":"Ctrl+Alt+N","rules":[]}'
        [IO.File]::WriteAllText($configFile, $default, [Text.UTF8Encoding]::new($false))
    }
}
$panelPath = Join-Path $Destination 'AppLimiter.exe'
$panelPaths = @($panelPath)
if ($previousLocation) { $panelPaths += (Join-Path $previousLocation 'AppLimiter.exe') }
foreach ($process in @(Get-Process -Name 'AppLimiter' -ErrorAction SilentlyContinue)) {
    if ($process.Path -and ($panelPaths | Where-Object { [string]::Equals($_, $process.Path, [StringComparison]::OrdinalIgnoreCase) })) {
        $process | Stop-Process -Force
    }
}
if (Get-Service -Name 'AppLimiterService' -ErrorAction SilentlyContinue) {
    Stop-Service -Name 'AppLimiterService' -ErrorAction SilentlyContinue
    (Get-Service -Name 'AppLimiterService').WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
}
foreach ($name in $required) {
    $sourceFile = Join-Path $dist $name
    $destinationFile = Join-Path $Destination $name
    if ((Test-Path -LiteralPath $destinationFile) -and
        ((Get-FileHash -LiteralPath $sourceFile).Hash -eq (Get-FileHash -LiteralPath $destinationFile).Hash)) {
        continue
    }
    Copy-Item -LiteralPath $sourceFile -Destination $destinationFile -Force
}
$binary = '"' + (Join-Path $Destination 'app_limiter_service.exe') + '" --config "' + $configFile + '" --state "' + $stateFile + '"'
$serviceDacl = 'D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;LCSWRPWPRC;;;' + $OwnerSid + ')'
if (!(Get-Service -Name 'AppLimiterService' -ErrorAction SilentlyContinue)) {
    New-Service -Name 'AppLimiterService' -BinaryPathName $binary -DisplayName 'App Limiter Service' -StartupType Automatic | Out-Null
} else {
    & sc.exe sdset AppLimiterService $serviceDacl
    if ($LASTEXITCODE -ne 0) { throw 'Could not repair service permissions.' }
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='AppLimiterService'"
    $change = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{ PathName = $binary; StartMode = 'Automatic' }
    if ($change.ReturnValue -ne 0) { throw "Could not update service registration ($($change.ReturnValue))." }
}
& sc.exe description AppLimiterService 'Per-application traffic monitor and bandwidth limits'
& sc.exe failure AppLimiterService reset= 86400 actions= restart/1000/restart/5000/restart/5000
if ($LASTEXITCODE -ne 0) { throw 'Could not configure service recovery.' }
& sc.exe sdset AppLimiterService $serviceDacl
if ($LASTEXITCODE -ne 0) { throw 'Could not grant service control to the installing user.' }
Start-Service -Name 'AppLimiterService'
Write-Host "Service command: $((Get-CimInstance -ClassName Win32_Service -Filter "Name='AppLimiterService'").PathName)"
$shortcutPath = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'App Limiter.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $Destination 'AppLimiter.exe'
$shortcut.IconLocation = (Join-Path $Destination 'AppLimiter.ico') + ',0'
$shortcut.WorkingDirectory = $Destination
$shortcut.Save()
$desktopPath = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'App Limiter.lnk'
if ($DesktopShortcut -eq 1) {
    $desktop = $shell.CreateShortcut($desktopPath)
    $desktop.TargetPath = $panelPath
    $desktop.IconLocation = (Join-Path $Destination 'AppLimiter.ico') + ',0'
    $desktop.WorkingDirectory = $Destination
    $desktop.Save()
} elseif (Test-Path -LiteralPath $desktopPath) {
    $desktop = $shell.CreateShortcut($desktopPath)
    if ($panelPaths | Where-Object { [string]::Equals($_, $desktop.TargetPath, [StringComparison]::OrdinalIgnoreCase) }) {
        Remove-Item -LiteralPath $desktopPath -Force
    }
}
New-Item -Path $runKey -Force | Out-Null
$startupValue = (Get-ItemProperty -Path $runKey -Name AppLimiter -ErrorAction SilentlyContinue).AppLimiter
if ($StartWithWindows -eq 1) {
    Set-ItemProperty -Path $runKey -Name AppLimiter -Value ('"' + $panelPath + '" --startup')
} elseif ($startupValue -and ($panelPaths | Where-Object { [string]::Equals($startupValue, ('"' + $_ + '"'), [StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($startupValue, ('"' + $_ + '" --startup'), [StringComparison]::OrdinalIgnoreCase) })) {
    Remove-ItemProperty -Path $runKey -Name AppLimiter
}
if ($previousLocation -and -not [string]::Equals($previousLocation.TrimEnd('\'), $Destination, [StringComparison]::OrdinalIgnoreCase)) {
    foreach ($name in @('AppLimiter.exe', 'app_limiter_service.exe', 'AppLimiter.ico', 'WinDivert.dll', 'WinDivert64.sys', 'LICENSE', 'Uninstall.exe', 'uninstall.ps1', 'run_uninstall.ps1')) {
        Remove-Item -LiteralPath (Join-Path $previousLocation $name) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $previousLocation -ErrorAction SilentlyContinue
}
if (-not ('AppLimiterShellIcons' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AppLimiterShellIcons {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(uint eventId, uint flags,
        IntPtr item1, IntPtr item2);
}
'@
}
[AppLimiterShellIcons]::SHChangeNotify(0x08000000, 0,
    [IntPtr]::Zero, [IntPtr]::Zero)
Write-Host "Installed App Limiter for $OwnerName ($OwnerSid). Launch it from the Start Menu."
Stop-Transcript | Out-Null
