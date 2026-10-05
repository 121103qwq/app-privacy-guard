param([switch]$IncludeEdge,[switch]$RegisterStartup,[string[]]$Programs,[string[]]$StartupNames=@('claude.exe'),
      [string]$StatePath=(Join-Path $PSScriptRoot 'state/local-state.json'))
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run this setup in administrator PowerShell'}
. (Join-Path $PSScriptRoot 'targets.ps1')
$guard=Join-Path $PSScriptRoot 'network-guard.exe'
$targets=if($Programs){@($Programs | ForEach-Object {[IO.Path]::GetFullPath($_)})}else{@(Get-LocalClaudeTargets)}
if($IncludeEdge){$targets+=@(Join-Path ${env:ProgramFiles(x86)} 'Microsoft/Edge/Application/msedge.exe')}
$targets=@($targets | Sort-Object -Unique)
if(-not $targets.Count){throw 'No selected executable is installed'}
foreach($target in $targets){if(-not (Test-Path -LiteralPath $target -PathType Leaf)){throw 'A selected executable does not exist'}}
$state=if(Test-Path -LiteralPath $StatePath){Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json}else{[pscustomobject]@{AddedGuardPaths=@();StartupKeys=@();Roots=@()}}
New-Item -ItemType Directory -Force (Split-Path $StatePath -Parent) | Out-Null
function Save-LocalState {$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding UTF8}
foreach($target in $targets){
    $present=& $guard inspect $target
    if($LASTEXITCODE){throw 'Existing WFP state could not be inspected'}
    $families=$present | ConvertFrom-Json
    if([bool]$families.ipv4 -ne [bool]$families.ipv6){throw 'Existing partial WFP filters were preserved; repair their original installation first'}
    if(-not $families.ipv4 -and $target -notin @($state.AddedGuardPaths)){$state.AddedGuardPaths+=@($target);Save-LocalState}
    & $guard install $target | Out-Null
    if($LASTEXITCODE){throw 'WFP installation failed; use the saved state to undo only this setup'}
}
$automatic=0
if($RegisterStartup){
    $entries=@($targets | Where-Object {[IO.Path]::GetFileName($_) -in $StartupNames})
    $launcher='"'+(Join-Path $PSScriptRoot 'privacy-launch.exe')+'" --ifeo'
    foreach($entry in $entries){
        $root=Join-Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' ([IO.Path]::GetFileName($entry))
        $properties=Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue
        if($properties.Debugger){Write-Warning 'An existing global Claude launch hook was preserved. Use the existing protected shortcut or the manual launcher.';continue}
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$suffix=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($entry.ToLowerInvariant())))).Replace('-','').Substring(0,12)}finally{$hash.Dispose()}
        $key=Join-Path $root ('AppPrivacyLocal-'+$suffix)
        if(Test-Path -LiteralPath $key){
            $existing=Get-ItemProperty -LiteralPath $key
            if($key -notin @($state.StartupKeys | ForEach-Object {$_.Key}) -or $existing.Debugger -ne $launcher -or $existing.FilterFullPath -ne $entry){throw 'An existing startup filter was preserved'}
        }else{
            if($root -notin @($state.Roots | ForEach-Object {$_.Key})){
                $hadProperty=$properties -and $properties.PSObject.Properties.Name -contains 'UseFilter'
                $state.Roots+=@([pscustomobject]@{Key=$root;HadUseFilter=[bool]$hadProperty;UseFilter=$properties.UseFilter;ExistedBefore=(Test-Path -LiteralPath $root)});Save-LocalState
            }
            $state.StartupKeys+=@([pscustomobject]@{Key=$key;Debugger=$launcher});Save-LocalState
            New-Item -Path $key -Force | Out-Null
            New-ItemProperty -LiteralPath $key -Name FilterFullPath -Value $entry -PropertyType String -Force | Out-Null
            New-ItemProperty -LiteralPath $key -Name Debugger -Value $launcher -PropertyType String -Force | Out-Null
        }
        New-ItemProperty -LiteralPath $root -Name UseFilter -Value 1 -PropertyType DWord -Force | Out-Null
        $automatic++
    }
}
& $guard check @targets | Out-Null
if($LASTEXITCODE){throw 'WFP verification failed'}
Save-LocalState
[pscustomobject]@{GuardedExecutableCount=$targets.Count;ExactStartupFilters=$automatic;LoopbackPreserved=$true;HostLocaleChanged=$false;RealAccountTested=$false} | ConvertTo-Json -Compress
