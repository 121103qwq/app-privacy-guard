$ErrorActionPreference='Stop'
$project=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$output=Join-Path $project 'dist/desktop/local'
New-Item -ItemType Directory -Force $output | Out-Null
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(-not $installation){throw 'Visual Studio x64 C++ build tools are required'}
$vcvars=Join-Path $installation 'VC/Auxiliary/Build/vcvars64.bat'
$batch=Join-Path $output 'compile-local.cmd'
@"
@echo off
call "$vcvars" >nul
cd /d "$PSScriptRoot"
cl /nologo /O2 /MT /DNDEBUG /c /Ivendor\minhook\include vendor\minhook\src\buffer.c vendor\minhook\src\hook.c vendor\minhook\src\trampoline.c vendor\minhook\src\hde\hde64.c /Fo"$output\\"
if errorlevel 1 exit /b 1
cl /nologo /O2 /MT /EHsc /std:c++17 /LD /Ivendor\minhook\include locale-shim.cpp "$output\buffer.obj" "$output\hook.obj" "$output\trampoline.obj" "$output\hde64.obj" /Fo"$output\locale-shim.obj" /Fe"$output\locale-shim.dll" /link advapi32.lib
if errorlevel 1 exit /b 1
cl /nologo /O2 /MT /EHsc /std:c++17 privacy-launch.cpp /Fo"$output\privacy-launch.obj" /Fe"$output\privacy-launch.exe"
if errorlevel 1 exit /b 1
cl /nologo /O2 /MT /EHsc /std:c++17 network-guard.cpp /Fo"$output\network-guard.obj" /Fe"$output\network-guard.exe" /link fwpuclnt.lib rpcrt4.lib
if errorlevel 1 exit /b 1
cl /nologo /O2 /MT /EHsc /std:c++17 environment-probe.cpp /Fo"$output\environment-probe.obj" /Fe"$output\environment-probe.exe" /link advapi32.lib
exit /b %errorlevel%
"@ | Set-Content -LiteralPath $batch -Encoding ascii
& cmd /c $batch
if($LASTEXITCODE){throw 'Local tools build failed'}
