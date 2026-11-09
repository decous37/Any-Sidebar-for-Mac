import {cp,mkdir,rename,rm,access} from 'node:fs/promises';
import {homedir} from 'node:os';
import {spawnSync} from 'node:child_process';
const parent=`${homedir()}/Applications`,destination=`${parent}/AnySidebarMac.app`,staging=`${parent}/.AnySidebarMac-install.app`,previous=`${parent}/.AnySidebarMac-previous.app`;
const verify=path=>{const r=spawnSync('codesign',['--verify','--deep','--strict',path],{stdio:'inherit'});if(r.status!==0)throw Error('安装包签名检查失败');};
verify('build/macos/AnySidebarMac.app');await mkdir(parent,{recursive:true});await rm(staging,{recursive:true,force:true});await cp('build/macos/AnySidebarMac.app',staging,{recursive:true});verify(staging);
let existed=false;try{await access(destination);existed=true;}catch{/* First installation. */}
if(existed){await rm(previous,{recursive:true,force:true});await rename(destination,previous);}
try{await rename(staging,destination);verify(destination);}catch(error){await rm(destination,{recursive:true,force:true});if(existed)await rename(previous,destination);throw error;}
await rm(previous,{recursive:true,force:true});console.log(`已安装 ${destination}，本机数据和钥匙串保持不变。`);
