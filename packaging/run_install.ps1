param(
    [Parameter(Mandatory=$true)][string]$Destination,
    [Parameter(Mandatory=$true)][string]$OwnerIdentity,
    [ValidateRange(0,1)][int]$DesktopShortcut = 1,
    [ValidateRange(0,1)][int]$StartWithWindows = 1
)
$ErrorActionPreference = 'Stop'
try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    & (Join-Path $scriptDir 'install.ps1') -Destination $Destination -OwnerIdentity $OwnerIdentity -DesktopShortcut $DesktopShortcut -StartWithWindows $StartWithWindows | Out-Null
    [Console]::Out.Write('Installed')
} catch {
    [Console]::Out.Write($_.Exception.Message)
    exit 1
}
