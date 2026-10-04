import fs from 'node:fs';import http from 'node:http';import path from 'node:path';import crypto from 'node:crypto';import {createRequire} from 'node:module';import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';
const require=createRequire(process.env.PLAYWRIGHT_PACKAGE||import.meta.url);const {chromium}=require('playwright');const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const runtime=path.join(root,'runtime','os-callback');fs.mkdirSync(runtime,{recursive:true});const state=crypto.randomUUID();fs.writeFileSync(path.join(runtime,'expected-state.txt'),state);
const helper=path.join(root,'dist/desktop/callback-fixture.exe');const launcher=process.env.PRIVACY_LAUNCHER;
if(!fs.existsSync(helper))throw new Error('Build the callback fixture first');
const q=x=>"'"+x.replaceAll("'","''")+"'";
const protocolCommand=(launcher?'"'+launcher+'" ':'')+'"'+helper+'" "%1" "'+runtime+'"';
const register=`$k='HKCU:\\Software\\Classes\\appprivacy-fixture';if(Test-Path $k){throw 'Test protocol key already exists'};New-Item "$k\\shell\\open\\command" -Force|Out-Null;Set-Item $k 'URL:App Privacy account-free fixture';New-ItemProperty $k -Name 'URL Protocol' -Value '' -Force|Out-Null;Set-Item "$k\\shell\\open\\command" ${q(protocolCommand)}`;
const reg=spawnSync('pwsh',['-NoProfile','-Command',register],{encoding:'utf8'});if(reg.status!==0)throw new Error('Could not register private test protocol');
let context;const html=fs.readFileSync(path.join(root,'tests/flow.html'),'utf8').replace('appprivacy://callback?','appprivacy-fixture://callback?');
const server=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html');res.end(html);});await new Promise(r=>server.listen(18890,'127.0.0.1',r));
try{
 context=await chromium.launchPersistentContext(fs.mkdtempSync(path.join(runtime,'edge-')),{channel:'msedge',headless:false,args:['--disable-extensions-except='+path.join(root,'edge'),'--load-extension='+path.join(root,'edge'),'--proxy-server=http://127.0.0.1:17992','--proxy-bypass-list=127.0.0.1','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','--disable-background-networking']});
 const page=await context.newPage();await page.goto('http://127.0.0.1:18890/?state='+state);await page.waitForFunction(()=>!!window.fixtureResult);await page.locator('#authorize').click();console.log('Private fixture browser prompt is ready. No account was loaded.');
 let done=false;for(let i=0;i<120;i++){if(fs.existsSync(path.join(runtime,'callback-result.json'))){done=true;break;}await new Promise(r=>setTimeout(r,500));}
 if(!done)throw new Error('OS callback was not observed within the test window');
 const result=JSON.parse(fs.readFileSync(path.join(runtime,'callback-result.json'),'utf8'));fs.writeFileSync(path.join(root,'docs/evidence/desktop-os-callback.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));if(!result.state_bound||!result.native_locale_us||!result.native_timezone_pacific)process.exitCode=1;
}finally{if(context)await context.close().catch(()=>{});server.close();spawnSync('pwsh',['-NoProfile','-Command',"Remove-Item -LiteralPath 'HKCU:\\Software\\Classes\\appprivacy-fixture' -Recurse -Force"],{encoding:'utf8'});}
