function Get-LocalClaudeTargets {
    $targets=@()
    $packages=@(Get-AppxPackage | Where-Object {$_.Name -match '^Claude$|^Claude_'})
    foreach($package in $packages){
        $targets+=@(Get-ChildItem -LiteralPath $package.InstallLocation -Filter '*.exe' -File -Recurse | Select-Object -ExpandProperty FullName)
    }
    $codeRoot=Join-Path $env:LOCALAPPDATA 'Claude-3p/claude-code'
    if(Test-Path -LiteralPath $codeRoot){
        $targets+=@(Get-ChildItem -LiteralPath $codeRoot -Filter '*.exe' -File -Recurse | Select-Object -ExpandProperty FullName)
    }
    $code=Get-Command claude.exe -ErrorAction SilentlyContinue
    if($code -and $code.Source -notmatch '\\Microsoft\\WindowsApps\\'){$targets+=@($code.Source)}
    return @($targets | Sort-Object -Unique)
}

function Get-LocalDesktopEntry {
    $entries=@()
    $packages=@(Get-AppxPackage | Where-Object {$_.Name -match '^Claude$|^Claude_'})
    foreach($package in $packages){
        [xml]$manifest=Get-Content -LiteralPath (Join-Path $package.InstallLocation 'AppxManifest.xml') -Raw
        foreach($app in @($manifest.Package.Applications.Application)){
            if($app.Executable -match '(^|[\\/])claude\.exe$'){
                $entries+=@(Join-Path $package.InstallLocation $app.Executable)
            }
        }
    }
    if($entries.Count -ne 1){throw 'Exactly one installed official Claude Desktop entry is required'}
    return $entries[0]
}

function Get-LocalCodeEntry {
    $root=Join-Path $env:LOCALAPPDATA 'Claude-3p/claude-code'
    $entries=if(Test-Path -LiteralPath $root){@(Get-ChildItem -LiteralPath $root -Filter 'claude.exe' -File -Recurse | Sort-Object LastWriteTime -Descending)}else{@()}
    if($entries.Count){return $entries[0].FullName}
    $code=Get-Command claude.exe -ErrorAction SilentlyContinue
    if($code -and $code.Source -notmatch '\\Microsoft\\WindowsApps\\'){return $code.Source}
    throw 'A standalone Claude Code executable is required; shared node.exe is not automatically guarded'
}
