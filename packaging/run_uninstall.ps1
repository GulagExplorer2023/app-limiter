param(
    [Parameter(Mandatory)][string]$Destination
)
$ErrorActionPreference = 'Stop'
try {
    & (Join-Path $PSScriptRoot 'uninstall.ps1') -Destination $Destination -KeepFiles *> $null
    [Console]::Out.Write('Removed')
} catch {
    [Console]::Out.Write($_.Exception.Message)
    exit 1
}
