import {readFile} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
export const signingLabel='Any Sidebar Local Development';
export const signingDirectory=join(homedir(),'Library','Application Support','com.decous.anysidebar.mac-build');
export const signingMetadata=join(signingDirectory,'signing.json');
export async function signingIdentity(){
 try{const value=JSON.parse(await readFile(signingMetadata,'utf8'));if(value.label!==signingLabel||!/^\b[0-9A-F]{40}\b$/.test(value.identity))throw Error('本机签名配置无效');return value.identity;}
 catch(error){if(error.code==='ENOENT')return null;throw error;}
}
