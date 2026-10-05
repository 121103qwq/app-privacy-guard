using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
class Launcher {
    [STAThread] static void Main() {
        var script=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"deployment","panel.ps1");
        if(!File.Exists(script)){MessageBox.Show("请先完整解压 ZIP，再打开部署工具。","App Privacy Guard");return;}
        var shell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","WindowsPowerShell","v1.0","powershell.exe");
        var psi=new ProcessStartInfo(shell,"-NoProfile -STA -ExecutionPolicy Bypass -File \""+script+"\"");
        psi.UseShellExecute=false;psi.CreateNoWindow=true;
        Process.Start(psi);
    }
}
