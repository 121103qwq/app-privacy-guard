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
