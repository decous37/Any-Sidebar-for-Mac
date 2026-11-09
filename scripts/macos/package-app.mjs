import {spawnSync} from 'node:child_process';
import {mkdir,readFile} from 'node:fs/promises';
const audit=spawnSync(process.execPath,['scripts/macos/audit-app.mjs'],{stdio:'inherit'});if(audit.status!==0)process.exit(audit.status??1);
const meta=JSON.parse(await readFile('apps/macos/product.json','utf8'));await mkdir('release/macos',{recursive:true});
const path=`release/macos/AnySidebarMac-${meta.version}-arm64-local.zip`,result=spawnSync('ditto',['-c','-k','--sequesterRsrc','--keepParent','build/macos/AnySidebarMac.app',path],{stdio:'inherit'});if(result.status!==0)process.exit(result.status??1);console.log(path);
