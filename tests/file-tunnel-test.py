from pathlib import Path
import argparse, subprocess, socket, threading, time, json, uuid, shutil
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--proxy-port',type=int,default=17992);args=p.parse_args()
ipc=root/'runtime'/('ipc-'+uuid.uuid4().hex);ipc.mkdir(parents=True)
exe=root/'dist/desktop/file-tunnel.exe';guest_exe=ipc.parent/('guest-'+uuid.uuid4().hex+'.exe');shutil.copyfile(exe,guest_exe);children=[]
def request(port):
 with socket.create_connection(('127.0.0.1',port),timeout=10) as s:
  s.settimeout(12);s.sendall(b'GET http://example.com/ HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n');data=b''
  try:
   while len(data)<65536:
    chunk=s.recv(4096)
    if not chunk:break
    data+=chunk
  except (OSError,TimeoutError):pass
  return data
try:
 children.append(subprocess.Popen([str(exe),'broker',str(ipc),str(args.proxy_port)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
 children.append(subprocess.Popen([str(guest_exe),'guest',str(ipc),'18080'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
 time.sleep(.6)
 data=request(18080);working=data.startswith(b'HTTP/1.1 200') and b'Example Domain' in data
 children[0].terminate();children[0].wait(5)
 offline=request(18080);offline_closed=not offline
 report={'scope':'Two host processes exercising file IPC; not a Windows guest or official Claude runtime test. Only explicit proxy egress was used.','file_proxy_http_pass':working,'broker_failure_closed':offline_closed,'direct_baseline_requested':False,'real_account_used':False}
 (root/'docs/evidence').mkdir(parents=True,exist_ok=True);(root/'docs/evidence/file-tunnel.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report));assert working and offline_closed
finally:
 for child in children:
  if child.poll() is None:child.terminate();child.wait(5)
