import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

// Offline extension configuration model and isolated JS realms; no browser or network.
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const extension=path.join(root,'desktop/local/edge');
const manifest=JSON.parse(fs.readFileSync(path.join(extension,'manifest.json'),'utf8'));
const rules=JSON.parse(fs.readFileSync(path.join(extension,'language.json'),'utf8'));
const payload=fs.readFileSync(path.join(extension,'region-start.js'),'utf8');
const previousTimezone=process.env.TZ;
process.env.TZ='Asia/Tokyo';

function matches(pattern,url){
 const parsed=new URL(url);
 const parts=pattern.match(/^https:\/\/(\*\.)?([^/]+)(\/.*)$/);
 if(!parts||parsed.protocol!=='https:')return false;
 if(parsed.hostname!==parts[2]&&!(parts[1]&&parsed.hostname.endsWith('.'+parts[2])))return false;
 const expression=parts[3].split('*').map(part=>part.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')).join('.*');
 return new RegExp('^'+expression+'$').test(parsed.pathname+parsed.search);
}

function applies(url,parentUrl){
 return manifest.content_scripts.some(entry=>{
  if(entry.matches.some(pattern=>matches(pattern,url)))return true;
  if(parentUrl&&entry.match_about_blank&&/^about:(blank|srcdoc)$/.test(url)){
   return entry.matches.some(pattern=>matches(pattern,parentUrl));
  }
  if(parentUrl&&entry.match_origin_as_fallback&&/^(data:|blob:|filesystem:)/.test(url)){
   return entry.matches.some(pattern=>matches(pattern,new URL(parentUrl).origin+'/'));
  }
  return false;
 });
}

function languageHeader(url){
 const parsed=new URL(url);
 for(const rule of rules){
  const condition=rule.condition;
  if(condition.requestDomains&&!condition.requestDomains.some(domain=>parsed.hostname===domain||parsed.hostname.endsWith('.'+domain)))continue;
  if(condition.regexFilter&&!new RegExp(condition.regexFilter).test(url))continue;
  const header=rule.action.requestHeaders.find(item=>item.header.toLowerCase()==='accept-language');
  if(header)return header.value;
 }
 return 'fr-FR,fr;q=0.9';
}

const bootstrap=`
 const nativeFormatter=Intl.DateTimeFormat;
 Intl.DateTimeFormat=new Proxy(nativeFormatter,{
  apply(target,receiver,args){return Reflect.apply(target,receiver,[args[0]??'fr-FR',{...args[1],timeZone:args[1]?.timeZone??'Asia/Tokyo'}]);},
  construct(target,args,newTarget){return Reflect.construct(target,[args[0]??'fr-FR',{...args[1],timeZone:args[1]?.timeZone??'Asia/Tokyo'}],newTarget);}
 });
 class Navigator {get language(){return 'fr-FR';}get languages(){return ['fr-FR','fr'];}}
 globalThis.navigator=new Navigator();
 globalThis.Worker=class Worker{};
 globalThis.SharedWorker=class SharedWorker{};
 globalThis.RTCPeerConnection=class RTCPeerConnection{};
 globalThis.ServiceWorkerContainer=class ServiceWorkerContainer{register(){return Promise.resolve('canary');}};
 navigator.serviceWorker=new ServiceWorkerContainer();
 globalThis.Geolocation=class Geolocation{getCurrentPosition(success){success({synthetic:true});}watchPosition(){return 1;}};
 navigator.geolocation=new Geolocation();
 globalThis.MediaDevices=class MediaDevices{getUserMedia(){return Promise.resolve('canary');}getDisplayMedia(){return Promise.resolve('canary');}};
 navigator.mediaDevices=new MediaDevices();
`;

const observation=`({
 language:navigator.language,
 timezone:Intl.DateTimeFormat().resolvedOptions().timeZone,
 january:new Date('2026-01-01T00:00:00Z').getTimezoneOffset(),
 july:new Date('2026-07-01T00:00:00Z').getTimezoneOffset(),
 workerBlocked:(()=>{try{new Worker('synthetic');return false;}catch(error){return error.name==='NotAllowedError';}})()
})`;

async function documentRealm(url,parentUrl){
 const context=vm.createContext({DOMException,queueMicrotask});
 vm.runInContext(bootstrap,context);
 const baseline=vm.runInContext(observation,context);
 assert.equal(baseline.language,'fr-FR');
 assert.equal(baseline.timezone,'Asia/Tokyo');
 assert.equal(baseline.january,-540);
 const selected=applies(url,parentUrl);
 if(selected)vm.runInContext(payload,context);
 // This observation is the first simulated page script after extension selection.
 const first=vm.runInContext(observation,context);
 if(selected){
  assert.equal(first.language,'en-US');
  assert.equal(first.timezone,'America/Los_Angeles');
  assert.equal(first.january,480);
  assert.equal(first.july,420);
  assert.equal(first.workerBlocked,true);
  const blocked=await vm.runInContext(`navigator.serviceWorker.register('/synthetic').then(()=>false,error=>error.name==='NotAllowedError')`,context);
  assert.equal(blocked,true);
 }else{
  assert.deepEqual({...first},{...baseline});
 }
 return selected;
}

try{
 for(const script of manifest.content_scripts){
  assert.equal(script.run_at,'document_start');
  assert.equal(script.world,'MAIN');
  assert.equal(script.all_frames,true);
  if(script.match_origin_as_fallback)assert(script.matches.every(pattern=>pattern.endsWith('/*')&&!pattern.includes('/recaptcha/')));
 }
 const profiles=[];
 for(let profile=0;profile<2;profile++){
  const state=crypto.randomUUID();
  const authorize='https://claude.ai/login?state='+state;
  const google='https://accounts.google.com/o/oauth2/v2/auth?state='+state;
  const consent='https://accounts.google.com/signin/oauth/consent?state='+state;
  const callback='https://claude.ai/auth/callback?state='+state+'&code=mock-only';
  const hops=[authorize,google,consent,callback];
  for(const hop of hops){
   assert.equal(await documentRealm(hop),true);
   assert.equal(languageHeader(hop),'en-US,en;q=0.9');
   assert.equal(new URL(hop).searchParams.get('state'),state);
  }
  assert.equal(await documentRealm('about:blank',google),true);
  assert.equal(await documentRealm('data:text/html,synthetic',google),true);
  const accept=url=>new URL(url).searchParams.get('state')===state&&new URL(url).searchParams.get('code')==='mock-only';
  assert.equal(accept(callback),true);
  assert.equal(accept('https://claude.ai/auth/callback?state=wrong&code=mock-only'),false);
  profiles.push({isolated_realms:true,claude_google_consent_callback:true,first_script_us:true,
                 google_child_realm_us:true,headers_us:true,mock_state_checked:true});
 }
 const challenges=['https://www.google.com/recaptcha/api2/anchor','https://www.google.com/recaptcha/enterprise/bframe',
                   'https://www.recaptcha.net/recaptcha/api2/anchor','https://www.gstatic.com/recaptcha/synthetic-frame.html'];
 for(const url of challenges){
  assert.equal(await documentRealm(url),true);
  assert.equal(await documentRealm('about:blank',url),true);
  assert.equal(languageHeader(url),'en-US,en;q=0.9');
 }
 const ordinary=['https://www.google.com/search?q=synthetic','https://www.gstatic.com/ordinary.js',
                 'https://www.recaptcha.net/ordinary','https://accounts.google.com.example.invalid/signin',
                 'https://google.com.example.invalid/recaptcha/api2/anchor','https://example.invalid/'];
 for(const url of ordinary){
  assert.equal(await documentRealm(url),false);
  assert.equal(languageHeader(url),'fr-FR,fr;q=0.9');
 }
 // Path-scoped challenge entries intentionally cannot use broad origin fallback.
 assert.equal(applies('data:text/html,synthetic',challenges[0]),false);
 const report={scope:'Offline manifest and DNR selection model plus Node VM JS realms; not Edge runtime or real Google authentication.',
               canary:{language:'fr-FR',timezone:'Asia/Tokyo'},profiles,
               challenge_paths_checked:challenges.length,ordinary_and_spoofed_urls_unchanged:ordinary.length,
               challenge_opaque_child_origin_fallback_covered:false,
               real_account_used:false,network_requests_made:false,browser_started:false,
               actual_google_login_compatibility_verified:false};
 fs.writeFileSync(path.join(root,'docs/evidence/desktop-google-scope.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report));
}finally{
 if(previousTimezone===undefined)delete process.env.TZ;else process.env.TZ=previousTimezone;
}
