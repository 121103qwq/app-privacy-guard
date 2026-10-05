param([Parameter(ValueFromRemainingArguments=$true)][string[]]$ClaudeArguments)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'targets.ps1')
& (Join-Path $PSScriptRoot 'privacy-launch.exe') (Get-LocalCodeEntry) @ClaudeArguments
exit $LASTEXITCODE
