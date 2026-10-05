$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$output=Join-Path $root 'runtime'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$vswhere=Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(-not $installation){throw 'Visual Studio x64 C++ build tools are required for developer tests'}
$vcvars=Join-Path $installation 'VC/Auxiliary/Build/vcvars64.bat'
$batch=Join-Path $output 'build-fixtures.cmd'
@"
@echo off
call "$vcvars" >nul
cl /nologo /O2 /MT /EHsc /std:c++17 "$PSScriptRoot\limited-launch.cpp" /Fo"$output\limited-launch.obj" /Fe"$output\limited-launch.exe" /link advapi32.lib user32.lib
exit /b %errorlevel%
"@ | Set-Content -LiteralPath $batch -Encoding ascii
& cmd /c $batch
if($LASTEXITCODE){throw 'Restricted-token fixture build failed'}
