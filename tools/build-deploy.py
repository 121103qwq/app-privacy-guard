from pathlib import Path
import json, hashlib, shutil, subprocess

root=Path(__file__).resolve().parents[1]
stage=root/'dist/quick-deploy'
stage.mkdir(exist_ok=True)
local=stage/'desktop/local'
local.mkdir(parents=True,exist_ok=True)
for name in ['privacy-launch.exe','locale-shim.dll','network-guard.exe','environment-probe.exe']:
    shutil.copy2(root/'dist/desktop/local'/name,local/name)
for file in (root/'desktop/local').glob('*.ps1'):
    if file.name!='build.ps1':(local/file.name).write_text(file.read_text(encoding='utf-8-sig'),encoding='utf-8-sig',newline='\r\n')
(local/'edge').mkdir(exist_ok=True)
for file in (root/'desktop/local/edge').iterdir():
    if file.is_file():shutil.copy2(file,local/'edge'/file.name)
(stage/'deployment').mkdir(exist_ok=True)
for name in ['engine.ps1','panel.ps1','Start.cmd']:
    file=root/'deployment'/name
    (stage/'deployment'/name).write_text(file.read_text(encoding='utf-8-sig'),encoding='utf-8-sig' if name.endswith('.ps1') else 'ascii',newline='\r\n')
(stage/'docs').mkdir(exist_ok=True)
for name in ['quick-deploy.md','desktop-local-guide.md','test-report.md','package-audit.md','browser-url-diagnostics.md']:
    shutil.copy2(root/'docs'/name,stage/'docs'/name)
shutil.copy2(root/'LICENSE',stage/'LICENSE')
(stage/'licenses').mkdir(exist_ok=True)
shutil.copy2(root/'licenses/minhook-bsd.txt',stage/'licenses/minhook-bsd.txt')
csc=Path('C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe')
result=subprocess.run([str(csc),'/nologo','/target:winexe','/platform:x64','/reference:System.Windows.Forms.dll','/out:'+str(stage/'AppPrivacyGuard.exe'),str(root/'deployment/launcher.cs')],capture_output=True)
assert result.returncode==0, result.stdout.decode(errors='replace')
checks={str(p.relative_to(stage)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in stage.rglob('*') if p.is_file() and p.name!='FILES.sha256.json'}
(stage/'FILES.sha256.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
print(json.dumps({'prepared':True,'files':len(checks),'launcher_built':True,'scripts_include_utf8_bom':True}))
