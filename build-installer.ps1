param(
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$version = '1.4.0'
$zip = Join-Path $root 'tools\nsis-3.12.zip'
$compiler = Join-Path $root 'tools\nsis-3.12\makensis.exe'
$expectedNsisHash = '56581F90DB321581C5381193D796FFFCF2D24B2F8FED2160A6C6A3BAA67F2C4F'
if (!(Test-Path -LiteralPath $zip)) { throw 'Missing tools\nsis-3.12.zip. Download the official NSIS 3.12 ZIP.' }
if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $expectedNsisHash) { throw 'NSIS ZIP checksum mismatch.' }
if (!(Test-Path -LiteralPath $compiler)) {
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $root 'tools') -Force
}
if (!$SkipBuild) { & (Join-Path $root 'build.ps1') }
$dist = Join-Path $root 'dist\AppLimiter'
foreach ($name in @('AppLimiter.exe','app_limiter_service.exe','driver_compat_probe.exe','AppLimiter.ico','WinDivert.dll','WinDivert64.sys','LICENSE')) {
    if (!(Test-Path -LiteralPath (Join-Path $dist $name))) { throw "Missing payload: $name" }
}
foreach ($name in @('AppLimiter.exe', 'app_limiter_service.exe')) {
    $file = Join-Path $dist $name
    if ((Get-Item -LiteralPath $file).VersionInfo.FileVersion -ne "$version.0") {
        throw "$name does not have release file version $version.0."
    }
    $bytes = [IO.File]::ReadAllBytes($file)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    if ([BitConverter]::ToUInt16($bytes, $peOffset + 4) -ne 0x8664) {
        throw "$name is not an x64 executable."
    }
}
$installerSource = [IO.File]::ReadAllText((Join-Path $root 'packaging\AppLimiter.nsi'))
if (-not $installerSource.Contains('!define APP_VERSION "' + $version + '"')) {
    throw 'Installer version does not match the release binaries.'
}
if ((Get-AuthenticodeSignature -LiteralPath (Join-Path $dist 'WinDivert64.sys')).Status -ne 'Valid') {
    throw 'WinDivert driver signature is not valid.'
}
Push-Location -LiteralPath (Join-Path $root 'packaging')
try {
    & $compiler /V2 'AppLimiter.nsi'
    if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
} finally {
    Pop-Location
}
$setup = Join-Path $root "dist\AppLimiter-Setup-$version.exe"
$hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumPath = Join-Path $root "dist\AppLimiter-Setup-$version.sha256"
[IO.File]::WriteAllText($checksumPath, "$hash  AppLimiter-Setup-$version.exe`n", [Text.UTF8Encoding]::new($false))
$driverCheckStage = Join-Path $root 'build\driver-check'
New-Item -ItemType Directory -Force -Path $driverCheckStage | Out-Null
Copy-Item -LiteralPath (Join-Path $dist 'driver_compat_probe.exe'), (Join-Path $dist 'WinDivert.dll'), (Join-Path $dist 'WinDivert64.sys'), (Join-Path $dist 'LICENSE'), (Join-Path $root 'packaging\run_driver_check.cmd'), (Join-Path $root 'packaging\driver_check_README.txt') -Destination $driverCheckStage -Force
$driverCheckZip = Join-Path $root "dist\AppLimiter-Driver-Check-$version.zip"
Compress-Archive -Path (Join-Path $driverCheckStage '*') -DestinationPath $driverCheckZip -Force
$driverCheckHash = (Get-FileHash -LiteralPath $driverCheckZip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $root "dist\AppLimiter-Driver-Check-$version.sha256"), "$driverCheckHash  AppLimiter-Driver-Check-$version.zip`n", [Text.UTF8Encoding]::new($false))
Write-Host "Installer ready: $setup"
Write-Host "SHA-256: $hash"
Write-Host "Driver check ready: $driverCheckZip"
