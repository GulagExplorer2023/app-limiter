param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$OwnerIdentity,
    [ValidateRange(0,1)][int]$DesktopShortcut = 1,
    [ValidateRange(0,1)][int]$StartWithWindows = 1
)
$ErrorActionPreference = 'Stop'
try {
    & (Join-Path $PSScriptRoot 'install.ps1') -Destination $Destination -OwnerIdentity $OwnerIdentity -DesktopShortcut $DesktopShortcut -StartWithWindows $StartWithWindows *> $null
    [Console]::Out.Write('Installed')
} catch {
    [Console]::Out.Write($_.Exception.Message)
    exit 1
}
