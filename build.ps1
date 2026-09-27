param(
    [string]$LazarusRoot = 'C:\lazarus'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$fpc = Join-Path $LazarusRoot 'fpc\3.2.2\bin\x86_64-win64\fpc.exe'
$lazbuild = Join-Path $LazarusRoot 'lazbuild.exe'
$fpcres = Join-Path $LazarusRoot 'fpc\3.2.2\bin\x86_64-win64\fpcres.exe'
$archive = Join-Path $root 'third_party\WinDivert-2.2.2-A.zip'
$vendor = Join-Path $root 'third_party\WinDivert-2.2.2-A'
$build = Join-Path $root 'build'
$dist = Join-Path $root 'dist\AppLimiter'
if (!(Test-Path -LiteralPath $fpc) -or !(Test-Path -LiteralPath $lazbuild) -or !(Test-Path -LiteralPath $fpcres)) {
    throw 'Lazarus 4.8 / FPC 3.2.2 x64 was not found. Pass -LazarusRoot.'
}
if (!(Test-Path -LiteralPath $archive)) { throw 'Pinned WinDivert archive is missing.' }
$expected = '63CB41763BB4B20F600B6DE04E991A9C2BE73279E317D4D82F237B150C5F3F15'
$actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
if ($actual -ne $expected) { throw 'WinDivert archive checksum mismatch.' }
if (!(Test-Path -LiteralPath (Join-Path $vendor 'x64\WinDivert.dll'))) {
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $root 'third_party')
}
New-Item -ItemType Directory -Force -Path $build, $dist | Out-Null
& (Join-Path $root 'assets\create_icon.ps1')
Push-Location -LiteralPath (Join-Path $root 'assets')
try {
    & $fpcres 'AppLimiter.rc' -of res -o '..\panel\AppLimiterIcon.res'
    if ($LASTEXITCODE -ne 0) { throw 'Icon resource build failed.' }
} finally {
    Pop-Location
}
Push-Location -LiteralPath (Join-Path $root 'service')
try {
    & $fpcres 'AppLimiterVersion.rc' -of res -o 'AppLimiterVersion.res'
    if ($LASTEXITCODE -ne 0) { throw 'Service version resource build failed.' }
} finally {
    Pop-Location
}
Push-Location -LiteralPath $root
try {
    & $fpc -Mobjfpc -O2 -Xs '-Fusrc' '-FUbuild' '-FEbuild' 'service\app_limiter_service.pas'
    if ($LASTEXITCODE -ne 0) { throw 'Service build failed.' }
    & $lazbuild '--bm=Release' '-B' 'panel\app_limiter.lpi'
    if ($LASTEXITCODE -ne 0) { throw 'Panel build failed.' }
} finally {
    Pop-Location
}
Copy-Item -LiteralPath (Join-Path $build 'AppLimiter.exe'), (Join-Path $build 'app_limiter_service.exe'), (Join-Path $root 'assets\AppLimiter.ico'), (Join-Path $vendor 'x64\WinDivert.dll'), (Join-Path $vendor 'x64\WinDivert64.sys'), (Join-Path $vendor 'LICENSE') -Destination $dist -Force
Write-Host "Build ready: $dist"
