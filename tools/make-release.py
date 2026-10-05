from pathlib import Path
import subprocess,zipfile,hashlib,json,shutil
root=Path(__file__).resolve().parents[1];out=root/'dist';version='0.2.1';assets=[]
def package(filename,entries):
 dest=out/filename
 with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
  for source,name in entries:z.write(source,name)
 assets.append(dest)
common=[(root/'LICENSE','LICENSE'),(root/'docs/desktop-guide.md','docs/desktop-guide.md'),(root/'docs/desktop-local-guide.md','docs/desktop-local-guide.md'),(root/'docs/desktop-strict-guide.md','docs/desktop-strict-guide.md'),(root/'docs/browser-url-diagnostics.md','docs/browser-url-diagnostics.md'),(root/'docs/test-report.md','docs/test-report.md'),(root/'docs/package-audit.md','docs/package-audit.md'),(root/'config/proxy-only.example.yaml','config/proxy-only.example.yaml'),(root/'licenses/minhook-bsd.txt','licenses/minhook-bsd.txt')]
local=[(out/'desktop/local'/n,'desktop/local/'+n) for n in ['privacy-launch.exe','locale-shim.dll','network-guard.exe','environment-probe.exe']]
local += [(p,'desktop/local/'+p.name) for p in sorted((root/'desktop/local').glob('*.ps1')) if p.name!='build.ps1']
local += [(p,'desktop/local/edge/'+p.name) for p in sorted((root/'desktop/local/edge').iterdir()) if p.is_file()]
package('app-privacy-desktop-'+version+'.zip',[(out/'desktop'/n,'desktop/'+n) for n in ['file-tunnel.exe','loopback-guard.exe','network-canary.exe','callback-fixture.exe']]+[(root/'desktop/prepare-guest.ps1','desktop/prepare-guest.ps1')]+local+common)
package('app-privacy-edge-'+version+'.zip',[(p,'edge/'+p.name) for p in sorted((root/'edge').iterdir()) if p.is_file()]+[(root/'LICENSE','LICENSE')])
package('app-privacy-via-'+version+'.zip',[(root/'via/via-us-privacy.user.js','via-us-privacy.user.js'),(root/'docs/mobile-guide.md','docs/mobile-guide.md'),(root/'config/proxy-only.example.yaml','config/proxy-only.example.yaml'),(root/'LICENSE','LICENSE')])
source=out/('app-privacy-source-'+version+'.zip');subprocess.run(['git','-C',str(root),'archive','--format=zip','--output='+str(source),'HEAD'],check=True);assets.append(source)
assets.append(out/'app-privacy-browser-0.2.0.apk')
license_file=out/'androidx-apache-2.0.txt';shutil.copyfile(root/'licenses/androidx-apache-2.0.txt',license_file);assets.append(license_file)
lines=[];meta=[]
for p in sorted(assets):
 digest=hashlib.sha256(p.read_bytes()).hexdigest();lines.append(digest+'  '+p.name);meta.append({'name':p.name,'size':p.stat().st_size,'sha256':digest})
(out/'SHA256SUMS').write_text('\n'.join(lines)+'\n',encoding='ascii')
(out/'release-assets.json').write_text(json.dumps(meta,indent=2),encoding='utf-8')
print(json.dumps(meta))
