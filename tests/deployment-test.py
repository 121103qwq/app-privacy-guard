"""Bounded Windows deployment tests using synthetic executables only."""
from pathlib import Path
import json, os, select, shutil, socket, socketserver, subprocess, threading, uuid, winreg

root=Path(__file__).resolve().parents[1]
stage=root/'dist/quick-deploy'
runtime=root/'runtime'/('deployment-'+uuid.uuid4().hex)
runtime.mkdir(parents=True)
engine=stage/'deployment/engine.ps1'
probe=stage/'desktop/local/environment-probe.exe'
name='appprivacy-deploy-fixture-'+uuid.uuid4().hex+'.exe'
fixture=runtime/name
shutil.copy2(probe,fixture)
testroot=runtime/'primary'
pwsh=str(Path(os.environ['SYSTEMROOT'])/'System32/WindowsPowerShell/v1.0/powershell.exe')
CREATE=subprocess.CREATE_NO_WINDOW
report={}

def run(args,timeout=60):
    return subprocess.run(args,capture_output=True,timeout=timeout,creationflags=CREATE)

def ps(code,timeout=60):
    r=run([pwsh,'-NoProfile','-Command',code],timeout)
    (runtime/'last-ps.log').write_bytes(r.stdout+r.stderr)
    assert r.returncode==0,'PowerShell fixture operation failed; private runtime log retained'
    return r.stdout.decode('utf-8',errors='replace').strip()

def action(which,folder=testroot,path=fixture,port=17992,extra=()):
    output=runtime/('result-'+uuid.uuid4().hex+'.json')
    args=[pwsh,'-NoProfile','-ExecutionPolicy','Bypass','-File',str(engine),'-Action',which,'-TestFixture',str(path),'-TestRoot',str(folder),'-ProxyPort',str(port),'-ReportPath',str(output),*extra]
    r=run(args,90)
    (runtime/'last-action.log').write_bytes(r.stdout+r.stderr)
    assert output.exists(),'No deployment result; private runtime log retained'
    return r,json.loads(output.read_text(encoding='utf-8-sig'))

def q(path):return "'"+str(path).replace("'","''")+"'"

def inspect_guard(path,folder=testroot):
    binary=folder/'tools/desktop/local/network-guard.exe'
    if not binary.exists():binary=stage/'desktop/local/network-guard.exe'
    r=run([str(binary),'inspect',str(path)])
    assert r.returncode==0
    return json.loads(r.stdout)

keybase=r'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
keyname=keybase+'\\'+name
active=False
try:
    payload=stage/'desktop/local/locale-shim.dll'
    original=payload.read_bytes()
    try:
        payload.write_bytes(original+b'synthetic-checksum-corruption')
        r,value=action('Install')
        report['corrupt_payload_refused_before_changes']=r.returncode!=0 and 'checksum' in value.get('Error','') and not testroot.exists()
    finally:payload.write_bytes(original)
    r,value=action('Install',port=1)
    report['unavailable_proxy_refused_before_changes']=r.returncode!=0 and not value['Success'] and not testroot.exists()
    with winreg.CreateKey(winreg.HKEY_LOCAL_MACHINE,keyname) as key:
        winreg.SetValueEx(key,'Debugger',0,winreg.REG_SZ,'synthetic-foreign-owner')
    r,value=action('Install')
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,keyname) as key: foreign=winreg.QueryValueEx(key,'Debugger')[0]
    report['foreign_hook_preserved']=r.returncode!=0 and foreign=='synthetic-foreign-owner' and not inspect_guard(fixture)['ipv4']
    winreg.DeleteKey(winreg.HKEY_LOCAL_MACHINE,keyname)
    r,value=action('Install')
    assert r.returncode==0 and value['Success'],'Fixture installation failed'
    active=True
    report['install_with_independent_rollback_passed']=value['RollbackProbePassed'] and value['RollbackCancelled']
    fields=json.loads(run([str(fixture)]).stdout)
    report['direct_launch_native_region_us']=fields['userLocale']=='en-US' and fields['geo']=='US' and fields['timezone']=='Pacific Standard Time'
    limited_script=runtime/'limited-probe.ps1'
    limited_result=runtime/'limited-result.json'
    limited_script.write_text("$ErrorActionPreference='Stop'; $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); $fields=& "+q(fixture)+" | ConvertFrom-Json; @{Administrator=$admin;Fields=$fields;ExitCode=$LASTEXITCODE} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "+q(limited_result)+" -Encoding UTF8",encoding='utf-8-sig')
    limited_launcher=root/'runtime/limited-launch.exe'
    assert limited_launcher.exists(),'Build tests/limited-launch.cpp into runtime/limited-launch.exe before running'
    restricted=run([str(limited_launcher),pwsh,'-NoProfile','-ExecutionPolicy','Bypass','-File',str(limited_script)])
    (runtime/'limited-launch.log').write_bytes(restricted.stdout+restricted.stderr)
    if restricted.returncode & 0xFFFFFFFF == 0xC0000142 and not limited_result.exists():
        report['ordinary_user_guarded_launch_passed']=False
        report['ordinary_user_probe_initialization_unavailable']=True
    else:
        assert restricted.returncode==0 and limited_result.exists(),'Restricted-token probe did not return a result'
        limited=json.loads(limited_result.read_text(encoding='utf-8-sig'))
        report['ordinary_user_guarded_launch_passed']=not limited['Administrator'] and limited['ExitCode']==0 and limited['Fields']['userLocale']=='en-US'
        report['ordinary_user_probe_initialization_unavailable']=False
        assert report['ordinary_user_guarded_launch_passed'],'Ordinary-user protected launch failed'
    state=json.loads((testroot/'state/state.json').read_text())
    owned_before=state['AddedGuardPaths']
    r,value=action('Install')
    after=json.loads((testroot/'state/state.json').read_text())
    report['repeat_install_preserves_ownership']=r.returncode==0 and after['AddedGuardPaths']==owned_before
    installed_probe=testroot/'tools/desktop/local/environment-probe.exe'
    existing_bytes=installed_probe.read_bytes()
    try:
        installed_probe.write_bytes(existing_bytes+b'synthetic-installed-change')
        r,value=action('Install')
        report['same_version_changed_tools_preserved']=r.returncode!=0 and 'Same-version' in value.get('Error','') and installed_probe.read_bytes()==existing_bytes+b'synthetic-installed-change' and inspect_guard(fixture)['ipv4']
    finally:installed_probe.write_bytes(existing_bytes)
    source_engine=engine
    try:
        engine=testroot/'tools/deployment/engine.ps1'
        r,value=action('Install')
        report['refresh_from_installed_tools_passed']=r.returncode==0 and value['Success']
    finally:engine=source_engine

    class Relay(socketserver.BaseRequestHandler):
        def handle(self):
            try:
                with socket.create_connection(('127.0.0.1',17992),timeout=5) as upstream:
                    self.request.settimeout(8);upstream.settimeout(8)
                    while True:
                        ready,_,_=select.select([self.request,upstream],[],[],20)
                        if not ready:return
                        for source in ready:
                            data=source.recv(65536)
                            if not data:return
                            (upstream if source is self.request else self.request).sendall(data)
            except OSError:pass
    class RelayServer(socketserver.ThreadingTCPServer):daemon_threads=True
    with RelayServer(('127.0.0.1',0),Relay) as relay:
        threading.Thread(target=relay.serve_forever,daemon=True).start()
        alternate=relay.server_address[1]
        try:
            r,value=action('Install',port=alternate)
            assert r.returncode==0,'Alternate proxy-port install failed'
            fields=json.loads(run([str(fixture)]).stdout)
            r,value=action('Verify',port=alternate)
            report['alternate_proxy_port_native_and_network_passed']=r.returncode==0 and value['ProxyUS'] and fields['proxy']=='http://127.0.0.1:'+str(alternate)
        finally:relay.shutdown()
    r,value=action('Install')
    assert r.returncode==0,'Default proxy restore failed'
    r,value=action('Install',extra=['-SimulateFailure'])
    report['failed_refresh_restores_existing_guard']=r.returncode!=0 and inspect_guard(fixture)['ipv4'] and json.loads(run([str(fixture)]).stdout)['userLocale']=='en-US'
    r,value=action('Verify')
    report['verify_guard_and_us_proxy_passed']=r.returncode==0 and value['SystemHook'] and value['ProgramsGuarded']

    # Re-arm a completed synthetic transaction with a near deadline, then let SYSTEM run it.
    plans=sorted((testroot/'state').glob('transaction-*.json'),key=lambda p:p.stat().st_mtime)
    initial=next(p for p in plans if json.loads(p.read_text())['StateBefore'] is None)
    plan=json.loads(initial.read_text());plan['Cancelled']=False;plan['RollbackCompleted']=False
    initial.write_text(json.dumps(plan),encoding='utf-8')
    task='AppPrivacyGuard-ExpiryTest-'+uuid.uuid4().hex
    copied_engine=testroot/'tools/deployment/engine.ps1'
    command='-NoProfile -ExecutionPolicy Bypass -File "'+str(copied_engine)+'" -Action Rollback -TransactionPath "'+str(initial)+'" -TestFixture "'+str(fixture)+'" -TestRoot "'+str(testroot)+'"'
    code="$a=New-ScheduledTaskAction -Execute "+q(pwsh)+" -Argument "+q(command)+"; $p=New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest; Register-ScheduledTask -TaskName "+q(task)+" -Action $a -Principal $p -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(12)) | Out-Null"
    ps(code)
    import time
    deadline=time.monotonic()+85
    while time.monotonic()<deadline:
        if json.loads(initial.read_text()).get('RollbackCompleted'):break
        time.sleep(1)
    expired=json.loads(initial.read_text()).get('RollbackCompleted',False)
    ps('Unregister-ScheduledTask -TaskName '+q(task)+' -Confirm:$false')
    report['actual_deadline_SYSTEM_rollback_passed']=expired and not inspect_guard(fixture)['ipv4']
    assert expired,'Independent deadline rollback did not complete'
    active=False

    # A fresh failed deployment must not leave new rules or registry hooks.
    failed_name='appprivacy-deploy-fixture-'+uuid.uuid4().hex+'.exe'
    failed=runtime/failed_name;shutil.copy2(probe,failed)
    failroot=runtime/'failed'
    r,value=action('Install',folder=failroot,path=failed,extra=['-SimulateFailure'])
    report['fresh_failure_removes_only_new_guard']=r.returncode!=0 and not inspect_guard(failed,failroot)['ipv4']
    try:winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,keybase+'\\'+failed_name);missing=False
    except FileNotFoundError:missing=True
    report['fresh_failure_restores_missing_hook']=missing

    # Explicit remove is separately exercised after a successful clean install.
    cleanroot=runtime/'remove'
    r,value=action('Install',folder=cleanroot,path=failed)
    assert r.returncode==0
    r,value=action('Remove',folder=cleanroot,path=failed,extra=['-SimulateFailure'])
    report['failed_remove_restores_guard_and_hook']=r.returncode!=0 and inspect_guard(failed,cleanroot)['ipv4'] and json.loads(run([str(failed)]).stdout)['userLocale']=='en-US' and json.loads((cleanroot/'state/state.json').read_text())['Active']
    r,value=action('Remove',folder=cleanroot,path=failed)
    report['explicit_remove_preserves_tools']=r.returncode==0 and value['OriginalProtectionPreserved'] and value['RollbackProbePassed'] and value['RollbackCancelled'] and (cleanroot/'tools/desktop/local/privacy-launch.exe').exists() and not inspect_guard(failed,cleanroot)['ipv4']
    report['real_account_used']=False
    report['new_physical_computer_tested']=False
    report['actual_gui_clicked']=False
    report['official_msix_install_branch_runtime_tested']=False
    report['all_child_region_reads_verified']=False
    assert all(v for k,v in report.items() if k not in ['real_account_used','new_physical_computer_tested','actual_gui_clicked','official_msix_install_branch_runtime_tested','all_child_region_reads_verified','ordinary_user_guarded_launch_passed','ordinary_user_probe_initialization_unavailable'])
    (root/'docs/evidence/deployment-native.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report),flush=True)
finally:
    if active:
        try:action('Remove')
        except Exception:pass
    # Remove only a still-present synthetic foreign marker, never a deployed hook.
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,keyname) as key:value=winreg.QueryValueEx(key,'Debugger')[0]
        if value=='synthetic-foreign-owner':winreg.DeleteKey(winreg.HKEY_LOCAL_MACHINE,keyname)
    except FileNotFoundError:pass
