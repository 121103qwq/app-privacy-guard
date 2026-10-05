param([ValidateSet('one','two')][string]$Profile='one',[string]$Url='about:blank',[ValidateRange(1,65535)][int]$ProxyPort=17992)
$ErrorActionPreference='Stop'
if($Url -ne 'about:blank' -and $Url -notmatch '^https://'){throw 'Use an HTTPS URL or about:blank'}
$edge=Join-Path ${env:ProgramFiles(x86)} 'Microsoft/Edge/Application/msedge.exe'
& (Join-Path $PSScriptRoot 'network-guard.exe') check $edge | Out-Null
if($LASTEXITCODE){throw 'Edge is not guarded; run setup.ps1 -IncludeEdge first'}
$profileRoot=Join-Path $env:LOCALAPPDATA ('AppPrivacyGuard/edge-'+$Profile)
$preferences=Join-Path $profileRoot 'Default/Preferences'
if(-not (Test-Path -LiteralPath $preferences)){
    New-Item -ItemType Directory -Force (Split-Path $preferences -Parent) | Out-Null
    @{intl=@{accept_languages='en-US,en';app_locale='en-US'};omnibox=@{prevent_url_elisions=$true}} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $preferences -Encoding UTF8
}
$extension=Join-Path $PSScriptRoot 'edge'
$arguments=@(("--user-data-dir=$profileRoot"),'--no-first-run','--no-default-browser-check','--lang=en-US',
    ("--proxy-server=http://127.0.0.1:$ProxyPort"),'--proxy-bypass-list=localhost;127.0.0.1;[::1]',
    '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1, EXCLUDE ::1',
    '--disable-background-networking','--disable-quic','--disable-sync','--force-renderer-accessibility',
    ("--load-extension=$extension"),$Url)
& $edge @arguments
