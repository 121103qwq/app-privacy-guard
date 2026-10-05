import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const region=fs.readFileSync(path.join(root,'shared/region.js'),'utf8').replace('export function','function');
const deny=fs.readFileSync(path.join(root,'shared/deny-capabilities.js'),'utf8');
const script=`(()=>{${region}\ninstallRegion(globalThis);\n${deny}\n})();\n`;
for(const dir of ['android/app/src/main/assets','edge']){
 fs.mkdirSync(path.join(root,dir),{recursive:true});fs.writeFileSync(path.join(root,dir,'region-start.js'),script);
}
fs.mkdirSync(path.join(root,'via'),{recursive:true});
fs.writeFileSync(path.join(root,'via/via-us-privacy.user.js'),`// ==UserScript==\n// @name App Privacy region helper\n// @version 0.2.0\n// @match https://*/*\n// @run-at document-start\n// @grant none\n// ==/UserScript==\n// Region helper only. This userscript does not enforce network routing.\n${script}`);
fs.copyFileSync(path.join(root,'tests/flow.html'),path.join(root,'android/app/src/main/assets/flow.html'));
const localEdge=path.join(root,'desktop/local/edge');fs.mkdirSync(localEdge,{recursive:true});
const sites=['https://claude.ai/*','https://*.claude.ai/*','https://claude.com/*','https://*.claude.com/*','https://anthropic.com/*','https://*.anthropic.com/*','https://accounts.google.com/*'];
const challengeSites=['https://www.google.com/recaptcha/*','https://www.recaptcha.net/recaptcha/*','https://www.gstatic.com/recaptcha/*'];
const localManifest=JSON.parse(fs.readFileSync(path.join(root,'edge/manifest.json'),'utf8'));
localManifest.name='App Privacy local Claude and Google region';localManifest.version='0.2.2';
localManifest.description='Region patch for Claude, Google sign-in and related challenge frames. Network routing requires the local guard.';
localManifest.host_permissions=[...sites,'https://www.google.com/*','https://www.recaptcha.net/*','https://www.gstatic.com/*'];
localManifest.content_scripts[0].matches=sites;
// Origin fallback requires a wildcard path. Keep path-scoped challenge frames separate.
localManifest.content_scripts.push({...localManifest.content_scripts[0],matches:challengeSites,match_origin_as_fallback:false});
fs.writeFileSync(path.join(localEdge,'manifest.json'),JSON.stringify(localManifest));
fs.writeFileSync(path.join(localEdge,'region-start.js'),script);
const language=JSON.parse(fs.readFileSync(path.join(root,'edge/language.json'),'utf8'));
for(const rule of language)rule.condition.requestDomains=['claude.ai','claude.com','anthropic.com','accounts.google.com'];
const challengeLanguage=JSON.parse(JSON.stringify(language[0]));
challengeLanguage.id=Math.max(...language.map(rule=>rule.id))+1;
delete challengeLanguage.condition.requestDomains;
delete challengeLanguage.condition.urlFilter;
challengeLanguage.condition.regexFilter='^https://(www[.]google[.]com|www[.]recaptcha[.]net|www[.]gstatic[.]com)/recaptcha/';
language.push(challengeLanguage);
fs.writeFileSync(path.join(localEdge,'language.json'),JSON.stringify(language));
