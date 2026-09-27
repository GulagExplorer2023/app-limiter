param(
    [Parameter(Mandatory=$true)][string]$Destination
)
$ErrorActionPreference = 'Stop'
try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    & (Join-Path $scriptDir 'uninstall.ps1') -Destination $Destination -KeepFiles | Out-Null
    [Console]::Out.Write('Removed')
} catch {
    [Console]::Out.Write($_.Exception.Message)
    exit 1
}
