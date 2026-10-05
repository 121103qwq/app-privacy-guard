param([switch]$SelfTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form=New-Object Windows.Forms.Form
$form.Text='Claude 保护部署工具 0.3.0'
$form.Size=New-Object Drawing.Size(740,690)
$form.MinimumSize=$form.Size
$form.StartPosition='CenterScreen'
$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10)
$form.BackColor=[Drawing.Color]::FromArgb(246,248,252)
$title=New-Object Windows.Forms.Label
$title.Text='在这台电脑部署 Claude 保护'
$title.Font=New-Object Drawing.Font('Microsoft YaHei UI',17,[Drawing.FontStyle]::Bold)
$title.Location=New-Object Drawing.Point(24,20);$title.Size=New-Object Drawing.Size(680,38)
$form.Controls.Add($title)
$subtitle=New-Object Windows.Forms.Label
$subtitle.Text='适用于 Windows 10/11 x64。保留 Windows 的语言和时区，不自动登录账号。'
$subtitle.Location=New-Object Drawing.Point(25,65);$subtitle.Size=New-Object Drawing.Size(675,30)
$form.Controls.Add($subtitle)
function Label($text,$y){$label=New-Object Windows.Forms.Label;$label.Text=$text;$label.Location=New-Object Drawing.Point(25,$y);$label.Size=New-Object Drawing.Size(190,27);$form.Controls.Add($label)}
Label '美国 HTTP 代理端口' 112
$port=New-Object Windows.Forms.NumericUpDown;$port.Minimum=1;$port.Maximum=65535;$port.Value=17992;$port.Location=New-Object Drawing.Point(215,109);$port.Size=New-Object Drawing.Size(125,28);$form.Controls.Add($port)
$hint=New-Object Windows.Forms.Label;$hint.Text='127.0.0.1：此端口须固定走美国节点，无直连回退。';$hint.Location=New-Object Drawing.Point(25,144);$hint.Size=New-Object Drawing.Size(675,26);$form.Controls.Add($hint)
Label 'Claude Code（可选）' 185
$code=New-Object Windows.Forms.TextBox;$code.Location=New-Object Drawing.Point(215,182);$code.Size=New-Object Drawing.Size(385,28);$form.Controls.Add($code)
Label '官方 MSIX（可选）' 225
$msix=New-Object Windows.Forms.TextBox;$msix.Location=New-Object Drawing.Point(215,222);$msix.Size=New-Object Drawing.Size(385,28);$form.Controls.Add($msix)
function Browse-Button($box,$y,$filter){
    $button=New-Object Windows.Forms.Button;$button.Text='选择';$button.Location=New-Object Drawing.Point(613,$y);$button.Size=New-Object Drawing.Size(80,29)
    $button.Tag=@{Box=$box;Filter=$filter}
    $button.Add_Click({$dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter=$this.Tag.Filter;if($dialog.ShowDialog() -eq 'OK'){$this.Tag.Box.Text=$dialog.FileName};$dialog.Dispose()})
    $form.Controls.Add($button)
}
Browse-Button $code 180 '独立 Claude Code|claude.exe'
Browse-Button $msix 220 '官方 MSIX|*.msix'
$edge=New-Object Windows.Forms.CheckBox;$edge.Text='同时保护 Edge（规则会影响这个 Edge 的所有资料）';$edge.Checked=$true;$edge.Location=New-Object Drawing.Point(25,268);$edge.Size=New-Object Drawing.Size(680,28);$form.Controls.Add($edge)
$boundary=New-Object Windows.Forms.Label
$boundary.Text='这是非严格方案。浏览器扩展需手动启用，子进程及全部地区读取没有零泄漏保证。'
$boundary.Location=New-Object Drawing.Point(25,304);$boundary.Size=New-Object Drawing.Size(680,44);$boundary.ForeColor=[Drawing.Color]::FromArgb(83,94,114);$form.Controls.Add($boundary)
$log=New-Object Windows.Forms.TextBox;$log.Multiline=$true;$log.ReadOnly=$true;$log.ScrollBars='Vertical';$log.Location=New-Object Drawing.Point(25,443);$log.Size=New-Object Drawing.Size(670,171);$log.BackColor=[Drawing.Color]::White;$form.Controls.Add($log)
$status=New-Object Windows.Forms.Label;$status.Text='先启动固定美国代理，再点“检查环境”。';$status.Location=New-Object Drawing.Point(25,622);$status.Size=New-Object Drawing.Size(670,28);$form.Controls.Add($status)
$buttons=New-Object Collections.Generic.List[Windows.Forms.Button]
function Quote-Argument([string]$value){
    if($value.Contains('"') -or $value.Contains("`n") -or $value.Contains("`r")){throw '路径包含无效字符'}
    return '"'+$value.TrimEnd('\')+'"'
}
function Run-Action($action){
    foreach($button in $buttons){$button.Enabled=$false}
    $form.UseWaitCursor=$true;$status.Text='正在执行，请稍候……'
    try{
        $engine=Join-Path $PSScriptRoot 'engine.ps1'
        $exe=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $report=Join-Path ([IO.Path]::GetTempPath()) ('appprivacy-panel-'+[Guid]::NewGuid().ToString('N')+'.json')
        $arguments='-NoProfile -ExecutionPolicy Bypass -File '+(Quote-Argument $engine)+' -Action '+$action+' -ProxyPort '+$port.Value+' -ReportPath '+(Quote-Argument $report)
        if($code.Text.Trim()){$arguments+=' -CodePath '+(Quote-Argument $code.Text.Trim())}
        if($msix.Text.Trim() -and $action -eq 'Install'){$arguments+=' -MsixPath '+(Quote-Argument $msix.Text.Trim())}
        if($edge.Checked){$arguments+=' -IncludeEdge'}
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=$exe;$psi.Arguments=$arguments;$psi.UseShellExecute=$true;$psi.WindowStyle='Hidden'
        if($action -in @('Install','Remove')){$psi.Verb='runas'}
        if($action -eq 'LaunchCode'){$psi.WindowStyle='Normal'}
        $process=[Diagnostics.Process]::Start($psi)
        if($action -in @('LaunchDesktop','LaunchCode','LaunchBoth','OpenEdgeOne','OpenEdgeTwo')){
            $status.Text='已发起启动检查。规则或美国代理检查失败时，客户端不会打开。'
            $log.AppendText('启动检查已发起：'+$action+"`r`n")
            return
        }
        while(-not $process.HasExited){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 120}
        if(-not (Test-Path -LiteralPath $report)){throw '操作未完成，或系统管理员确认被取消。没有收到成功结果。'}
        $result=Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
        $log.AppendText((Get-Date -Format 'HH:mm:ss')+' '+$action+"`r`n"+($result | ConvertTo-Json -Depth 8)+"`r`n`r`n")
        if(-not $result.Success){throw $result.Error}
        if($action -eq 'Inspect'){$status.Text=if($result.ProxyUS){'美国代理通过。确认客户端后可部署。'}else{'美国代理未通过，请先调整固定代理端口。'}}
        elseif($action -eq 'Install'){$status.Text='保护已部署。Edge 扩展仍需手动启用并核对。'}
        elseif($action -eq 'Remove'){$status.Text='本工具新增的保护已撤销。文件、资料及原有保护保留。'}
        else{$status.Text='操作完成；结果见日志。'}
    }catch{$status.Text='操作未完成：'+$_.Exception.Message;$log.AppendText('未完成：'+$_.Exception.Message+"`r`n")}
    finally{$form.UseWaitCursor=$false;foreach($button in $buttons){$button.Enabled=$true}}
}
$specs=@(
    @{Text='检查环境';Action='Inspect';X=25;Y=357},@{Text='部署 / 更新保护';Action='Install';X=192;Y=357},@{Text='检查保护';Action='Verify';X=359;Y=357},@{Text='撤销本工具保护';Action='Remove';X=526;Y=357},
    @{Text='打开 Desktop';Action='LaunchDesktop';X=25;Y=400},@{Text='打开 Code';Action='LaunchCode';X=192;Y=400},@{Text='同时打开两个';Action='LaunchBoth';X=359;Y=400},@{Text='打开专用 Edge';Action='OpenEdgeOne';X=526;Y=400}
)
foreach($spec in $specs){
    $button=New-Object Windows.Forms.Button;$button.Text=$spec.Text;$button.Tag=$spec.Action;$button.Location=New-Object Drawing.Point($spec.X,$spec.Y);$button.Size=New-Object Drawing.Size(157,35)
    $button.Add_Click({Run-Action $this.Tag});$form.Controls.Add($button);$buttons.Add($button)
}
if($SelfTest){
    @{FormCreated=$true;ActionButtons=$buttons.Count;ProxyPortEditable=$true;CodeFilePicker=$true;MsixFilePicker=$true;ShowsBoundary=$boundary.Text.Length -gt 0;FormDisplayed=$false;NetworkOrAccountUsed=$false} | ConvertTo-Json -Compress
    $form.Dispose();exit 0
}
[void]$form.ShowDialog()
