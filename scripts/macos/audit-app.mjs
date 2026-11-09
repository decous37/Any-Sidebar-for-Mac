import {readFile,readdir,stat} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
const root=resolve('build/macos/AnySidebarMac.app'),meta=JSON.parse(await readFile('apps/macos/product.json','utf8'));
const plist=await readFile(`${root}/Contents/Info.plist`,'utf8');
for(const value of [meta.bundleId,meta.version,meta.minimumSystem,meta.executable])if(!plist.includes(`<string>${value}</string>`))throw Error('应用身份或版本不符');
const expected=['web/index.html','contracts/model-capabilities.json','contracts/bridge.schema.json','contracts/desktop-reading-prompt.txt','privacy.html','LICENSE','THIRD_PARTY_NOTICES.txt','AppIcon.icns','product.json'];for(const path of expected)if(!(await stat(`${root}/Contents/Resources/${path}`)).isFile())throw Error(`缺少资源 ${path}`);
async function walk(path){for(const entry of await readdir(path,{withFileTypes:true})){const full=`${path}/${entry.name}`;if(entry.isSymbolicLink())throw Error('包内不允许链接');if(entry.isDirectory())await walk(full);else{if(/\.(sqlite3?|pdf|env|map)$|^\.env|^fixtures$|test-results/i.test(entry.name))throw Error('包中包含开发资料');if(/\.(js|html|json|txt)$/.test(entry.name)){const text=await readFile(full,'utf8');if(/sk-[a-zA-Z0-9_-]{20,}|\/Users\/decous\/|https?:\/\/(?:localhost|127\.0\.0\.1)|SYSTEM_VALIDATION|test-secret/.test(text))throw Error(`发现敏感信息或测试入口：${entry.name}`);}}}}
await walk(root);
for(const [command,args] of [['codesign',['--verify','--deep','--strict',root]],['lipo',[`${root}/Contents/MacOS/${meta.executable}`,'-verify_arch','arm64']]]){const r=spawnSync(command,args,{stdio:'inherit'});if(r.status!==0)process.exit(r.status??1);}
console.log(`Mac ${meta.version} 包审计通过（本机签名，未公证）`);
