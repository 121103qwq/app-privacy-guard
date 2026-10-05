$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'targets.ps1')
& (Join-Path $PSScriptRoot 'privacy-launch.exe') (Get-LocalDesktopEntry)
exit $LASTEXITCODE
