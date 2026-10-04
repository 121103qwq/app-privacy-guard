param([string]$PrivacyLauncher)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $project 'dist/desktop/callback-fixture.exe'
$runRoot=Join-Path $project ('runtime/dispatch-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $runRoot | Out-Null
$state=[guid]::NewGuid().ToString()
[IO.File]::WriteAllText((Join-Path $runRoot 'expected-state.txt'),$state,[Text.Encoding]::ASCII)
$key='HKCU:\Software\Classes\appprivacy-fixture'
if(Test-Path $key){throw 'A test protocol registration already exists; refusing to replace it'}
if(-not(Test-Path $fixture)){throw 'Build desktop fixtures first'}
try{
    New-Item "$key\shell\open\command" -Force | Out-Null
    Set-Item $key 'URL:App Privacy account-free fixture'
    New-ItemProperty $key -Name 'URL Protocol' -Value '' -Force | Out-Null
    $command='"'+$fixture+'" "%1" "'+$runRoot+'"'
    if($PrivacyLauncher){$command='"'+$PrivacyLauncher+'" '+$command}
    Set-Item "$key\shell\open\command" $command
    $launch=[Diagnostics.ProcessStartInfo]::new("appprivacy-fixture://callback?state=$state&code=mock-only")
    $launch.UseShellExecute=$true
    [Diagnostics.Process]::Start($launch) | Out-Null
    $resultPath=Join-Path $runRoot 'callback-result.json'
    $deadline=(Get-Date).AddSeconds(10)
    while(-not(Test-Path $resultPath)){
        if((Get-Date) -gt $deadline){throw 'OS dispatch was not observed'}
        Start-Sleep -Milliseconds 100
    }
    $result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $result | Add-Member NoteProperty scope 'ShellExecute OS dispatch only; browser permission-dialog completion is not verified'
    $output=Join-Path $project 'docs/evidence/desktop-os-dispatch.json'
    $json=$result | ConvertTo-Json
    [IO.File]::WriteAllText($output,$json,[Text.UTF8Encoding]::new($false))
    Write-Output $json
    if(-not $result.state_bound){throw 'Mock callback state did not match'}
}finally{if(Test-Path $key){Remove-Item -LiteralPath $key -Recurse -Force}}
