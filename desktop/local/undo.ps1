param([string]$StatePath=(Join-Path $PSScriptRoot 'state/local-state.json'))
$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath $StatePath)){throw 'This setup ownership record is missing; no rules were removed'}
$state=Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
foreach($entry in @($state.StartupKeys)){
    if(Test-Path -LiteralPath $entry.Key){
        $current=Get-ItemProperty -LiteralPath $entry.Key
        if($current.Debugger -ne $entry.Debugger){throw 'Startup filter changed after setup; it was preserved'}
        Remove-Item -LiteralPath $entry.Key -Recurse -Force
    }
}
foreach($root in @($state.Roots)){
    $other=@(Get-ChildItem -LiteralPath $root.Key -ErrorAction SilentlyContinue | Where-Object {(Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).FilterFullPath})
    if(-not $other.Count){
        if($root.HadUseFilter){New-ItemProperty -LiteralPath $root.Key -Name UseFilter -Value $root.UseFilter -PropertyType DWord -Force | Out-Null}
        else{Remove-ItemProperty -LiteralPath $root.Key -Name UseFilter -ErrorAction SilentlyContinue}
        if(-not $root.ExistedBefore -and (Test-Path -LiteralPath $root.Key)){
            $item=Get-Item -LiteralPath $root.Key
            $children=@(Get-ChildItem -LiteralPath $root.Key)
            if(-not $item.Property.Count -and -not $children.Count){Remove-Item -LiteralPath $root.Key -Force}
        }
    }
}
foreach($path in @($state.AddedGuardPaths)){
    & (Join-Path $PSScriptRoot 'network-guard.exe') remove $path | Out-Null
    if($LASTEXITCODE){throw 'Owned WFP removal failed'}
}
$state.StartupKeys=@();$state.Roots=@();$state.AddedGuardPaths=@()
$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding UTF8
Write-Output 'Only this setup-owned filters were removed; profiles and other protection were preserved.'
