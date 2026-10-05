[CmdletBinding()]
param(
    [ValidateSet('Inspect','Install','Verify','Remove','Rollback','ProbeRollback','LaunchDesktop','LaunchCode','LaunchBoth','OpenEdgeOne','OpenEdgeTwo')][string]$Action='Inspect',
    [ValidateRange(1,65535)][int]$ProxyPort=17992,
    [string]$CodePath,[string]$MsixPath,[switch]$IncludeEdge,[string]$ReportPath,
    [string]$TransactionPath,[string]$TestFixture,[string]$TestRoot,[switch]$SimulateFailure
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$Version='0.3.0'
$PackageRoot=Split-Path $PSScriptRoot -Parent
$SourceTools=Join-Path $PackageRoot 'desktop/local'
$InstallRoot=Join-Path $env:ProgramFiles ('App Privacy Guard/'+$Version)
$StateRoot=Join-Path $env:ProgramData 'AppPrivacyGuard'
$StatePath=Join-Path $StateRoot 'state.json'
$FixtureMode=[bool]$TestFixture
if($FixtureMode){
    if(-not $TestRoot -or [IO.Path]::GetFileName($TestFixture) -notmatch '^appprivacy-deploy-fixture-[a-f0-9]+\.exe$'){throw 'Invalid synthetic fixture parameters'}
    if((Get-FileHash -LiteralPath $TestFixture).Hash -ne (Get-FileHash -LiteralPath (Join-Path $SourceTools 'environment-probe.exe')).Hash){throw 'Only the bundled synthetic probe is accepted in fixture mode'}
    $InstallRoot=Join-Path $TestRoot 'tools';$StateRoot=Join-Path $TestRoot 'state';$StatePath=Join-Path $StateRoot 'state.json'
}
$Tools=Join-Path $InstallRoot 'desktop/local'
$IfeoRoot='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
$Utf8=New-Object Text.UTF8Encoding($false)
function Save-Json($path,$value){
    $parent=Split-Path $path -Parent
    if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force | Out-Null}
    [IO.File]::WriteAllText($path,($value | ConvertTo-Json -Depth 12),$Utf8)
}
function Read-Json($path){Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json}
function Require-Admin {
    if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'This operation requires administrator PowerShell or the elevated deployment panel'}
}
function Check-USProxy($port){
    $response=Invoke-WebRequest -Uri 'https://www.cloudflare.com/cdn-cgi/trace' -Proxy ('http://127.0.0.1:'+$port) -UseBasicParsing -TimeoutSec 15
    if($response.StatusCode -ne 200 -or $response.Content -notmatch '(?m)^loc=US\r?$'){throw 'Local HTTP proxy did not return a US exit; deployment stopped'}
    return $true
}
function Verify-Payload {
    $manifest=Join-Path $PackageRoot 'FILES.sha256.json'
    if(-not (Test-Path -LiteralPath $manifest)){throw 'Deployment payload checksum manifest missing; fully extract the quick-deploy ZIP'}
    $entries=Read-Json $manifest
    $required=@('AppPrivacyGuard.exe','deployment/engine.ps1','deployment/panel.ps1','desktop/local/privacy-launch.exe','desktop/local/network-guard.exe','desktop/local/locale-shim.dll','desktop/local/environment-probe.exe')
    foreach($name in $required){if($entries.PSObject.Properties.Name -notcontains $name){throw 'Critical deployment payload not listed in checksum manifest'}}
    $base=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')+'\'
    foreach($entry in $entries.PSObject.Properties){
        $path=[IO.Path]::GetFullPath((Join-Path $PackageRoot $entry.Name))
        if(-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe checksum manifest path'}
        if(-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path).Hash -ne $entry.Value){throw 'Deployment file checksum mismatch; re-download the Release'}
    }
}
function Claude-Package {
    $packages=@(Get-AppxPackage -Name Claude)
    if($packages.Count -gt 1){throw 'More than one Claude Desktop package found'}
    if($packages.Count){return $packages[0]}
    return $null
}
function Desktop-Entry($package){
    if(-not $package){return $null}
    if($package.Publisher -notmatch 'Anthropic, PBC'){throw 'Desktop package publisher is not Anthropic'}
    [xml]$manifest=Get-Content -LiteralPath (Join-Path $package.InstallLocation 'AppxManifest.xml') -Raw
    $entries=@($manifest.Package.Applications.Application | Where-Object {$_.Executable -match '(^|[\\/])claude\.exe$'})
    if($entries.Count -ne 1){throw 'Desktop entry could not be identified uniquely'}
    return Join-Path $package.InstallLocation $entries[0].Executable
}
function Find-Code {
    if($CodePath){return [IO.Path]::GetFullPath($CodePath)}
    $paths=@()
    $root=Join-Path $env:LOCALAPPDATA 'Claude-3p/claude-code'
    if(Test-Path -LiteralPath $root){$paths+=@(Get-ChildItem -LiteralPath $root -Filter claude.exe -File -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty FullName)}
    $command=Get-Command claude.exe -ErrorAction SilentlyContinue
    if($command -and $command.Source -notmatch '\\Microsoft\\WindowsApps\\'){$paths+=@($command.Source)}
    $native=Join-Path $env:USERPROFILE '.local/bin/claude.exe'
    if(Test-Path -LiteralPath $native){$paths+=@($native)}
    if($paths.Count){return $paths[0]}
    return $null
}
function Verify-Signer($path){
    $signature=Get-AuthenticodeSignature -LiteralPath $path
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Anthropic, PBC'){throw 'Selected Claude binary/package must have a valid Anthropic signature'}
}
function Programs($package,$code){
    if($FixtureMode){return @([IO.Path]::GetFullPath($TestFixture))}
    $all=@()
    if($package){$all+=@(Get-ChildItem -LiteralPath $package.InstallLocation -File -Filter '*.exe' -Recurse | Select-Object -ExpandProperty FullName)}
    if($code){
        if([IO.Path]::GetFileName($code) -ne 'claude.exe'){throw 'Choose an independent claude.exe, not shared node.exe or a differently named version file'}
        if((Get-Item -LiteralPath $code).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Symbolic-link Code entries require selecting the real standalone claude.exe; no shared runtime is guarded'}
        Verify-Signer $code;$all+=@($code)
    }
    if($IncludeEdge){
        $edge=Join-Path ${env:ProgramFiles(x86)} 'Microsoft/Edge/Application/msedge.exe'
        if(-not (Test-Path -LiteralPath $edge)){throw 'Edge executable missing'}
        $all+=@($edge)
    }
    return @($all | Sort-Object -Unique)
}
function Guard-Status($path,$guard){
    $value=& $guard inspect $path
    if($LASTEXITCODE){throw 'WFP state could not be read'}
    $status=$value | ConvertFrom-Json
    if([bool]$status.ipv4 -ne [bool]$status.ipv6){throw 'Partial existing WFP protection was retained; repair its original installation'}
    return [bool]$status.ipv4
}
function Registry-Snapshot($name){
    $key=Join-Path $IfeoRoot $name
    $present=Test-Path -LiteralPath $key
    $value=Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    return [pscustomobject]@{Name=$name;Key=$key;Existed=$present;HadDebugger=[bool]($value -and $value.PSObject.Properties.Name -contains 'Debugger');Debugger=$value.Debugger;HadUseFilter=[bool]($value -and $value.PSObject.Properties.Name -contains 'UseFilter');UseFilter=$value.UseFilter}
}
function Copy-Tools {
    New-Item -ItemType Directory -Path $Tools -Force | Out-Null
    foreach($file in @(Get-ChildItem -LiteralPath $SourceTools -File | Where-Object {$_.Extension -in @('.exe','.dll','.ps1')})){
        $destination=Join-Path $Tools $file.Name
        if($file.FullName -ne $destination){Copy-Item -LiteralPath $file.FullName -Destination $destination -Force}
    }
    New-Item -ItemType Directory -Path (Join-Path $Tools 'edge') -Force | Out-Null
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $SourceTools 'edge') -File)){
        $destination=Join-Path $Tools ('edge/'+$file.Name)
        if($file.FullName -ne $destination){Copy-Item -LiteralPath $file.FullName -Destination $destination -Force}
    }
    $deployment=Join-Path $InstallRoot 'deployment'
    New-Item -ItemType Directory -Path $deployment -Force | Out-Null
    foreach($file in @(Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object {$_.Extension -in @('.ps1','.cmd')})){
        $destination=Join-Path $deployment $file.Name
        if($file.FullName -ne $destination){Copy-Item -LiteralPath $file.FullName -Destination $destination -Force}
    }
    foreach($name in @('AppPrivacyGuard.exe','FILES.sha256.json','LICENSE')){
        $file=Join-Path $PackageRoot $name;$destination=Join-Path $InstallRoot $name
        if($file -ne $destination){Copy-Item -LiteralPath $file -Destination $destination -Force}
    }
    foreach($directory in @('docs','licenses')){
        $destination=Join-Path $InstallRoot $directory
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot $directory) -File)){
            $target=Join-Path $destination $file.Name
            if($file.FullName -ne $target){Copy-Item -LiteralPath $file.FullName -Destination $target -Force}
        }
    }
}
function Arm-Transaction($plan){
    $id=[Guid]::NewGuid().ToString('N')
    $script:TransactionPath=Join-Path $StateRoot ('transaction-'+$id+'.json')
    $plan.TaskName='AppPrivacyGuard-Rollback-'+$id
    $plan.Cancelled=$false;$plan.RollbackCompleted=$false
    Save-Json $TransactionPath $plan
    $engine=Join-Path $InstallRoot 'deployment/engine.ps1'
    $exe=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $extra=if($FixtureMode){' -TestFixture "'+$TestFixture+'" -TestRoot "'+$TestRoot+'"'}else{''}
    $prefix='-NoProfile -ExecutionPolicy Bypass -File "'+$engine+'" -TransactionPath "'+$TransactionPath+'"'+$extra
    $principal=New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $probeAction=New-ScheduledTaskAction -Execute $exe -Argument ($prefix+' -Action ProbeRollback')
    Register-ScheduledTask -TaskName ($plan.TaskName+'-probe') -Action $probeAction -Principal $principal -Settings $settings | Out-Null
    Start-ScheduledTask -TaskName ($plan.TaskName+'-probe')
    for($i=0;$i -lt 40;$i++){if(Test-Path -LiteralPath ($TransactionPath+'.probe')){break};Start-Sleep -Milliseconds 250}
    if(-not (Test-Path -LiteralPath ($TransactionPath+'.probe'))){throw 'Independent SYSTEM rollback probe failed; network rules not changed'}
    Unregister-ScheduledTask -TaskName ($plan.TaskName+'-probe') -Confirm:$false
    $minutes=if($MsixPath){5}else{3}
    $trigger=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($minutes)
    $action=New-ScheduledTaskAction -Execute $exe -Argument ($prefix+' -Action Rollback')
    Register-ScheduledTask -TaskName $plan.TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
    return $plan
}
function Restore-Registry($entry,$expected){
    $current=Get-ItemProperty -LiteralPath $entry.Key -ErrorAction SilentlyContinue
    if($current.Debugger -and $current.Debugger -ne $expected -and $current.Debugger -ne $entry.Debugger){throw 'Startup hook changed by another owner; it was retained'}
    if($entry.HadDebugger -or $entry.HadUseFilter){New-Item -Path $entry.Key -Force | Out-Null}
    if($entry.HadDebugger){New-ItemProperty -LiteralPath $entry.Key -Name Debugger -Value $entry.Debugger -PropertyType String -Force | Out-Null}
    else{Remove-ItemProperty -LiteralPath $entry.Key -Name Debugger -ErrorAction SilentlyContinue}
    if($entry.HadUseFilter){New-ItemProperty -LiteralPath $entry.Key -Name UseFilter -Value $entry.UseFilter -PropertyType DWord -Force | Out-Null}
    else{Remove-ItemProperty -LiteralPath $entry.Key -Name UseFilter -ErrorAction SilentlyContinue}
    if(-not $entry.Existed -and (Test-Path -LiteralPath $entry.Key)){
        $key=Get-Item -LiteralPath $entry.Key
        if(-not $key.Property.Count -and -not @(Get-ChildItem -LiteralPath $entry.Key).Count){Remove-Item -LiteralPath $entry.Key}
    }
}
function Rollback-Plan($plan){
    if($plan.Cancelled){return}
    if($plan.PSObject.Properties.Name -contains 'Mode' -and $plan.Mode -eq 'Remove'){
        foreach($path in @($plan.GuardPathsBefore)){
            & (Join-Path $Tools 'network-guard.exe') install $path | Out-Null
            if($LASTEXITCODE){throw 'Previous WFP protection could not be restored'}
        }
        foreach($entry in @($plan.RegistryBefore)){Restore-Registry $entry $plan.Debugger}
        Save-Json $StatePath $plan.StateBefore
        $plan.RollbackCompleted=$true;Save-Json $TransactionPath $plan
        return
    }
    if($plan.NewPackage){
        $package=@(Get-AppxPackage -AllUsers | Where-Object PackageFullName -eq $plan.NewPackage)
        if($package.Count){
            $prefix=$package[0].InstallLocation.TrimEnd('\')+'\'
            Get-CimInstance Win32_Process | Where-Object {$_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)} | ForEach-Object {Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}
            Remove-AppxPackage -Package $plan.NewPackage -AllUsers
            if(@(Get-AppxPackage -AllUsers | Where-Object PackageFullName -eq $plan.NewPackage).Count){throw 'New package could not be removed; protection retained'}
        }
    }
    foreach($entry in @($plan.RegistryBefore)){Restore-Registry $entry $plan.Debugger}
    Get-CimInstance Win32_Process | Where-Object {$_.ExecutablePath -in @($plan.AddedGuardPaths)} | ForEach-Object {Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}
    foreach($path in @($plan.AddedGuardPaths)){
        & (Join-Path $Tools 'network-guard.exe') remove $path | Out-Null
        if($LASTEXITCODE){throw 'Owned WFP removal failed'}
    }
    if($null -ne $plan.ProxyIniBefore){[IO.File]::WriteAllText((Join-Path $Tools 'proxy.ini'),$plan.ProxyIniBefore,$Utf8)}
    if($plan.StateBefore){Save-Json $StatePath $plan.StateBefore}
    elseif(Test-Path -LiteralPath $StatePath){Save-Json $StatePath @{Active=$false;Version=$Version;RollbackCompleted=$true}}
    $plan.RollbackCompleted=$true;Save-Json $TransactionPath $plan
}
function Install-Protection {
    Require-Admin
    if(-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess){throw 'Windows x64 PowerShell is required'}
    Verify-Payload
    Check-USProxy $ProxyPort | Out-Null
    $package=if($FixtureMode){$null}else{Claude-Package}
    $code=if($FixtureMode){$TestFixture}else{Find-Code}
    if(-not $package -and -not $code -and -not $MsixPath){throw 'Install official Claude Desktop or select a standalone Claude Code executable first'}
    if($MsixPath){
        Verify-Signer $MsixPath
        if($package -or @(Get-AppxPackage -AllUsers -Name Claude).Count){throw 'Existing Desktop package preserved; install/update it separately before refreshing protection'}
    }
    $programs=@(Programs $package $code)
    if(@(Get-CimInstance Win32_Process | Where-Object {$_.ExecutablePath -in $programs}).Count){throw 'Close covered Claude/Edge processes and stop CoworkVMService before deployment; existing sessions were preserved'}
    $before=if(Test-Path -LiteralPath $StatePath){Read-Json $StatePath}else{$null}
    $names=if($FixtureMode){@([IO.Path]::GetFileName($TestFixture))}else{@('claude.exe')}
    $snapshot=@($names | ForEach-Object {Registry-Snapshot $_})
    foreach($entry in $snapshot){
        if($entry.Debugger -and (-not $before -or $entry.Debugger -ne $before.Debugger)){throw 'An existing startup hook belongs to another installation; it was preserved'}
        if($entry.UseFilter){throw 'Existing filtered startup hooks were preserved'}
    }
    if($before -and $before.Active -and $before.InstallRoot -eq $InstallRoot){
        foreach($name in @('privacy-launch.exe','locale-shim.dll','network-guard.exe','environment-probe.exe')){
            $existing=Join-Path $Tools $name
            if(-not (Test-Path -LiteralPath $existing) -or (Get-FileHash -LiteralPath $existing).Hash -ne (Get-FileHash -LiteralPath (Join-Path $SourceTools $name)).Hash){throw 'Same-version installed binaries differ; existing protection was preserved. Use a new release version instead of overwriting active tools'}
        }
    }
    Copy-Tools
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    # Local plans contain no credentials, but only administrators/SYSTEM may write them.
    & icacls.exe $StateRoot /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    if($LASTEXITCODE){throw 'State directory ACL setup failed; no networking changes made'}
    $debugger='"'+(Join-Path $Tools 'privacy-launch.exe')+'" --ifeo'
    $ini=Join-Path $Tools 'proxy.ini'
    $plan=[pscustomobject]@{TaskName='';Cancelled=$false;RollbackCompleted=$false;Debugger=$debugger;RegistryBefore=$snapshot;AddedGuardPaths=@();NewPackage=$null;StateBefore=$before;ProxyIniBefore=$(if(Test-Path -LiteralPath $ini){[IO.File]::ReadAllText($ini)}else{$null})}
    $plan=Arm-Transaction $plan
    try{
        if($MsixPath){
            Add-AppxPackage -Path $MsixPath -Stage
            $packages=@(Get-AppxPackage -AllUsers -Name Claude)
            if($packages.Count -ne 1){throw 'Staged Desktop package could not be identified'}
            $package=$packages[0];$plan.NewPackage=$package.PackageFullName;Save-Json $TransactionPath $plan
            $programs=@(Programs $package $code)
        }
        $probe=Join-Path $Tools 'environment-probe.exe'
        $programs=@(($programs+@($probe)) | Sort-Object -Unique)
        $guard=Join-Path $Tools 'network-guard.exe'
        foreach($path in $programs){
            if(-not (Guard-Status $path $guard)){$plan.AddedGuardPaths+=@($path);Save-Json $TransactionPath $plan}
            & $guard install $path | Out-Null
            if($LASTEXITCODE){throw 'WFP install failed'}
        }
        [IO.File]::WriteAllText($ini,"[Proxy]`r`nPort=$ProxyPort`r`n",(New-Object Text.UTF8Encoding($false)))
        foreach($entry in $snapshot){
            New-Item -Path $entry.Key -Force | Out-Null
            New-ItemProperty -LiteralPath $entry.Key -Name Debugger -Value $debugger -PropertyType String -Force | Out-Null
        }
        if($MsixPath){Add-AppxPackage -Register (Join-Path $package.InstallLocation 'AppxManifest.xml') -DisableDevelopmentMode;$package=Claude-Package}
        if($SimulateFailure){throw 'Synthetic post-install failure'}
        foreach($path in $programs){if(-not (Guard-Status $path $guard)){throw 'Protection verification failed'}}
        $native=& (Join-Path $Tools 'privacy-launch.exe') $probe | ConvertFrom-Json
        if($LASTEXITCODE -or $native.userLocale -ne 'en-US' -or $native.timezone -ne 'Pacific Standard Time'){throw 'Native region probe failed'}
        Check-USProxy $ProxyPort | Out-Null
        if((Read-Json $TransactionPath).RollbackCompleted){throw 'Automatic rollback fired; installation was not committed'}
        $owned=@($plan.AddedGuardPaths)
        if($before){$owned+=@($before.AddedGuardPaths)}
        $original=if($before){@($before.RegistryOriginal)}else{$snapshot}
        $state=[pscustomobject]@{Version=$Version;Active=$true;InstallRoot=$InstallRoot;Tools=$Tools;ProxyPort=$ProxyPort;Debugger=$debugger;RegistryOriginal=$original;AddedGuardPaths=@($owned | Sort-Object -Unique);Programs=$programs;DesktopEntry=$(if($package){Desktop-Entry $package}else{$null});CodeEntry=$code;IncludeEdge=[bool]$IncludeEdge;RealAccountUsed=$false;BrowserExtensionActivationVerified=$false;AllChildRegionReadsVerified=$false}
        Save-Json $StatePath $state
        if(-not $FixtureMode){Create-Shortcuts $state}
        $plan.Cancelled=$true;Save-Json $TransactionPath $plan
        Unregister-ScheduledTask -TaskName $plan.TaskName -Confirm:$false
        return @{Success=$true;Action='Install';Installed=$true;GuardedProgramCount=$programs.Count;SystemStartupHook=$true;NativeRegionUS=$true;ProxyUS=$true;RollbackProbePassed=$true;RollbackCancelled=$true;RealAccountUsed=$false;BrowserExtensionManualStepRequired=[bool]$IncludeEdge}
    }catch{
        $failure=$_.Exception.Message
        Rollback-Plan $plan
        Unregister-ScheduledTask -TaskName $plan.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        throw ('Deployment failed and rollback ran: '+$failure)
    }
}
function Create-Shortcuts($state){
    $shell=New-Object -ComObject WScript.Shell
    $desktop=[Environment]::GetFolderPath('Desktop')
    $engine=Join-Path $state.InstallRoot 'deployment/engine.ps1'
    $items=@()
    if($state.DesktopEntry){$items+=@(@{Name='Claude Desktop - Protected';Action='LaunchDesktop';Visible=$false})}
    if($state.CodeEntry){$items+=@(@{Name='Claude Code - Protected';Action='LaunchCode';Visible=$true})}
    if($state.DesktopEntry -and $state.CodeEntry){$items+=@(@{Name='Claude Desktop + Code - Protected';Action='LaunchBoth';Visible=$false})}
    if($state.IncludeEdge){$items+=@(@{Name='Claude Edge 1 - Protected';Action='OpenEdgeOne';Visible=$false},@{Name='Claude Edge 2 - Protected';Action='OpenEdgeTwo';Visible=$false})}
    foreach($item in $items){
        $path=Join-Path $desktop ($item.Name+'.lnk')
        $link=$shell.CreateShortcut($path)
        if((Test-Path -LiteralPath $path) -and $link.Arguments -notlike ('*'+$engine+'*')){throw 'An unrelated desktop shortcut was preserved'}
        $link.TargetPath=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $link.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$engine+'" -Action '+$item.Action
        $link.WorkingDirectory=[Environment]::GetFolderPath('UserProfile')
        $link.IconLocation=Join-Path $state.Tools 'privacy-launch.exe'
        $link.WindowStyle=if($item.Visible){1}else{7}
        $link.Save()
    }
}
function Installed-State {
    if(-not (Test-Path -LiteralPath $StatePath)){throw 'Protection has not been deployed on this computer'}
    $state=Read-Json $StatePath
    if(-not $state.Active){throw 'Protection was removed; deploy it again before starting'}
    return $state
}
function Remove-Protection {
    Require-Admin;$state=Installed-State
    $running=@(Get-CimInstance Win32_Process | Where-Object {$_.ExecutablePath -in @($state.Programs)})
    if($running.Count){throw 'Close covered Claude/Edge processes before removing protection; running clients will not be left unguarded'}
    $snapshot=@($state.RegistryOriginal | ForEach-Object {Registry-Snapshot $_.Name})
    $guard=Join-Path $state.Tools 'network-guard.exe'
    $guarded=@($state.AddedGuardPaths | Where-Object {Guard-Status $_ $guard})
    $before=$state | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $plan=[pscustomobject]@{Mode='Remove';TaskName='';Cancelled=$false;RollbackCompleted=$false;Debugger=$state.Debugger;RegistryBefore=$snapshot;GuardPathsBefore=$guarded;StateBefore=$before}
    $plan=Arm-Transaction $plan
    try{
        foreach($entry in @($state.RegistryOriginal)){Restore-Registry $entry $state.Debugger}
        foreach($path in @($state.AddedGuardPaths)){& $guard remove $path | Out-Null;if($LASTEXITCODE){throw 'Owned guard removal failed'}}
        if($SimulateFailure){throw 'Synthetic post-remove failure'}
        if((Read-Json $TransactionPath).RollbackCompleted){throw 'Automatic rollback fired; removal was not committed'}
        $state.Active=$false;Save-Json $StatePath $state
        $plan.Cancelled=$true;Save-Json $TransactionPath $plan
        Unregister-ScheduledTask -TaskName $plan.TaskName -Confirm:$false
        return @{Success=$true;Action='Remove';OriginalProtectionPreserved=$true;ToolsAndProfilesPreserved=$true;RollbackProbePassed=$true;RollbackCancelled=$true}
    }catch{
        $failure=$_.Exception.Message
        Rollback-Plan $plan
        Unregister-ScheduledTask -TaskName $plan.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        throw ('Removal failed and previous protection was restored: '+$failure)
    }
}
function Verify-State($state){
    foreach($path in @($state.Programs)){if(-not (Test-Path -LiteralPath $path) -or -not (Guard-Status $path (Join-Path $state.Tools 'network-guard.exe'))){throw 'A covered executable changed or its protection is missing; refresh deployment'} }
    foreach($entry in @($state.RegistryOriginal)){if((Get-ItemProperty -LiteralPath $entry.Key -ErrorAction SilentlyContinue).Debugger -ne $state.Debugger){throw 'System startup hook is missing or changed'}}
    Check-USProxy $state.ProxyPort | Out-Null
    return @{Success=$true;Action='Verify';ProxyUS=$true;SystemHook=$true;ProgramsGuarded=$true;BrowserPageEffectVerified=$false;AllChildRegionReadsVerified=$false}
}
function Launch-Selected($state,$kind){
    Verify-State $state | Out-Null
    if($kind -eq 'LaunchBoth'){
        $engine=Join-Path $state.InstallRoot 'deployment/engine.ps1'
        $exe=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        Start-Process $exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$engine+'" -Action LaunchDesktop')
        Start-Process $exe -WindowStyle Normal -ArgumentList ('-NoProfile -NoExit -ExecutionPolicy Bypass -File "'+$engine+'" -Action LaunchCode')
    }elseif($kind -in @('OpenEdgeOne','OpenEdgeTwo')){
        if(-not $state.IncludeEdge){throw 'Edge protection was not selected during deployment'}
        $profile=if($kind -eq 'OpenEdgeOne'){'one'}else{'two'}
        & (Join-Path $state.Tools 'start-edge.ps1') -Profile $profile -ProxyPort $state.ProxyPort
    }else{
        $target=if($kind -eq 'LaunchDesktop'){$state.DesktopEntry}else{$state.CodeEntry}
        if(-not $target){throw 'This client was not selected during deployment'}
        & (Join-Path $state.Tools 'privacy-launch.exe') $target
        if($LASTEXITCODE){throw 'Protected client could not be started'}
    }
    return @{Success=$true;Action=$kind;AccountAutomationPerformed=$false}
}
try{
    $result=switch($Action){
        'Inspect'{
            $package=Claude-Package;$code=Find-Code
            $proxy=$false;$errorText=$null
            try{$proxy=Check-USProxy $ProxyPort}catch{$errorText='US proxy unavailable or exit is not US'}
            @{Success=$true;Action='Inspect';Version=$Version;WindowsX64=[Environment]::Is64BitOperatingSystem;Administrator=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);DesktopInstalled=[bool]$package;CodeFound=[bool]$code;ProxyUS=$proxy;ProxyMessage=$errorText;AlreadyDeployed=(Test-Path -LiteralPath $StatePath);DefaultProxyPort=$ProxyPort;RealAccountUsed=$false}
        }
        'Install'{Install-Protection}
        'Verify'{Verify-State (Installed-State)}
        'Remove'{Remove-Protection}
        'ProbeRollback'{Require-Admin;if(-not [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem){throw 'Rollback must run as SYSTEM'};[IO.File]::WriteAllText($TransactionPath+'.probe','SYSTEM',$Utf8);@{Success=$true;Action='ProbeRollback'}}
        'Rollback'{Require-Admin;$plan=Read-Json $TransactionPath;Rollback-Plan $plan;@{Success=$true;Action='Rollback';Cancelled=$plan.Cancelled;Restored=$plan.RollbackCompleted}}
        default{Launch-Selected (Installed-State) $Action}
    }
    if($ReportPath){Save-Json $ReportPath $result}
    $result | ConvertTo-Json -Depth 8 -Compress
}catch{
    $result=@{Success=$false;Action=$Action;Error=$_.Exception.Message;RealAccountUsed=$false}
    if($ReportPath){Save-Json $ReportPath $result}
    $result | ConvertTo-Json -Compress
    exit 1
}
