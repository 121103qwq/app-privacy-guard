from pathlib import Path
import argparse,subprocess,json,hashlib
p=argparse.ArgumentParser();p.add_argument('--adb',required=True);p.add_argument('--adb-port',required=True);p.add_argument('--serial',required=True);args=p.parse_args()
root=Path(__file__).resolve().parents[1]
command=[args.adb,'-P',args.adb_port,'-s',args.serial,'logcat','-d','-s','PrivacyFixture:I']
log=subprocess.check_output(command).decode('utf-8',errors='replace');objects=[]
allowed={'language','languages','timezone','locale','date_constructor_timezone','intl_constructor_timezone','january_offset','july_offset','worker_blocked','worker_constructor_blocked','shared_worker_blocked','webrtc_blocked','webrtc_constructor_blocked','location_denied','service_worker_blocked','iframe_language','iframe_timezone','java_locale_us','java_timezone_us','direct_tcp4_denied','direct_tcp6_denied','tunnel_v4_drops','tunnel_v6_drops','tunnel_udp_drops','addresses_are_documentation_ranges'}
for line in log.splitlines():
 if 'PrivacyFixture:' not in line:continue
 tail=line.split('PrivacyFixture:',1)[1].strip()
 if not tail.startswith('{'):continue
 try: obj=json.loads(tail)
 except json.JSONDecodeError:continue
 objects.append({k:v for k,v in obj.items() if k in allowed})
region=next((o for o in reversed(objects) if 'java_locale_us' in o),None)
network=next((o for o in reversed(objects) if 'direct_tcp4_denied' in o),None)
apk=root/'dist/app-privacy-browser-0.2.0.apk'
report={'scope':'Independent Android 14 emulator. Mock callback and explicit proxy only. No real account, address or direct IP baseline.','apk_sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'region':region,'network':network,'mock_callback_observed':'callback_bound=true' in log,'us_proxy_check_observed':'proxy_us_verified=true' in log,'real_account_used':False,'direct_ip_baseline_requested':False}
out=root/'docs/evidence/android-runtime.json';out.write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))
assert region and region['java_locale_us'] and region['java_timezone_us'] and network and network['direct_tcp4_denied'] and network['direct_tcp6_denied']
