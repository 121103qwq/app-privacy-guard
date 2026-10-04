$ErrorActionPreference='Stop'
$sourceRoot=$PSScriptRoot
$project=Split-Path $sourceRoot -Parent
$output=Join-Path $project 'dist/desktop'
New-Item -ItemType Directory -Force $output | Out-Null
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$csSource=Join-Path $sourceRoot 'file-tunnel.cs'
$csOutput=Join-Path $output 'file-tunnel.exe'
& $compiler /nologo /optimize+ /target:exe "/out:$csOutput" $csSource
if($LASTEXITCODE){throw 'C# build failed'}
$canarySource=Join-Path $project 'tests/network-canary.cs'
$canaryOutput=Join-Path $output 'network-canary.exe'
& $compiler /nologo /optimize+ /target:exe "/out:$canaryOutput" $canarySource
if($LASTEXITCODE){throw 'Canary build failed'}
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$buildTools=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(-not $buildTools){throw 'Install Visual Studio C++ build tools to build loopback-guard'}
$vcvars=Join-Path $buildTools 'VC/Auxiliary/Build/vcvars64.bat'
$batch=Join-Path $output 'compile.cmd'
@"
@echo off
call "$vcvars" >nul
cl /nologo /O2 /MT /EHsc /std:c++17 "$sourceRoot\loopback-guard.cpp" /Fo"$output\loopback-guard.obj" /Fe"$output\loopback-guard.exe" /link fwpuclnt.lib rpcrt4.lib
if errorlevel 1 exit /b 1
cl /nologo /O2 /MT /EHsc /std:c++17 "$project\tests\callback-fixture.cpp" /Fo"$output\callback-fixture.obj" /Fe"$output\callback-fixture.exe"
exit /b %errorlevel%
"@ | Set-Content -LiteralPath $batch -Encoding ascii
& cmd /c $batch
if($LASTEXITCODE){throw 'WFP build failed'}
