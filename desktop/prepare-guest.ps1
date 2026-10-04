[CmdletBinding()]
param([Parameter(Mandatory)][string]$IpcDirectory,[int]$Port=18080,[string]$MsixPath)
$ErrorActionPreference='Stop'
if(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -EQ 'Up'){throw 'Remove or disable every guest network adapter before starting. This script does not disconnect the host.'}
Set-TimeZone -Id 'Pacific Standard Time'
Set-Culture en-US
Set-WinHomeLocation -GeoId 244
Set-WinUserLanguageList en-US -Force
Set-WinUILanguageOverride en-US
if($MsixPath){
    $signature=Get-AuthenticodeSignature -LiteralPath $MsixPath
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Anthropic'){throw 'Official Anthropic package signature required'}
    Add-AppxPackage -Path $MsixPath
}
$internet='HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
Set-ItemProperty $internet ProxyEnable 1
Set-ItemProperty $internet ProxyServer "127.0.0.1:$Port"
Set-ItemProperty $internet ProxyOverride ''
& "$PSScriptRoot/file-tunnel.exe" guest $IpcDirectory $Port
