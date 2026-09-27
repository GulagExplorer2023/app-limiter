$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$name = [Environment]::UserName
if (-not $identity.User -or -not $name) { throw 'Cannot identify the installing user.' }
[Console]::Out.Write($identity.User.Value + '|' + $name)
