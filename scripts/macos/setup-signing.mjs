import {spawnSync} from 'node:child_process';
import {mkdtemp,readFile,writeFile,mkdir,chmod,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomBytes} from 'node:crypto';
import {signingLabel,signingDirectory,signingMetadata} from './signing.mjs';
// Invoke only with explicit authorization: creates a dedicated local signing key and code-signing trust.
process.umask(0o077);
const secret=randomBytes(32).toString('base64url');
function run(command,args,label,{env=process.env,optional=false}={}){
 const result=spawnSync(command,args,{encoding:'utf8',env});
 if(result.status!==0&&!optional)throw Error(`${label}失败：${String(result.stderr??'').replaceAll(secret,'[redacted]').slice(0,800)}`);
 return result;
}
const keychain=run('security',['default-keychain','-d','user'],'读取用户钥匙串').stdout.trim().replace(/^"|"$/g,'');
const temporary=await mkdtemp(join(tmpdir(),'anysidebar-signing-'));
try{
 let identities=run('security',['find-identity','-v','-p','codesigning'], '检查本机签名').stdout;
 let match=identities.match(new RegExp(`([0-9A-F]{40}) "${signingLabel}"`));
 if(!match){
  const certificate=join(temporary,'certificate.pem');
  const existing=run('security',['find-certificate','-c',signingLabel,'-p',keychain],'检查已有证书',{optional:true});
  if(existing.status===0&&existing.stdout.includes('BEGIN CERTIFICATE'))await writeFile(certificate,existing.stdout,{mode:0o600});
  else{
   const key=join(temporary,'private.pem'),config=join(temporary,'certificate.cnf'),identity=join(temporary,'identity.p12');
   await writeFile(config,`[req]\ndistinguished_name=subject\nx509_extensions=extensions\nprompt=no\n[subject]\nCN=${signingLabel}\nO=Any Sidebar Local Development\n[extensions]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nsubjectKeyIdentifier=hash\n`,{mode:0o600});
   run('/usr/bin/openssl',['req','-new','-x509','-newkey','rsa:3072','-nodes','-sha256','-days','3650','-config',config,'-keyout',key,'-out',certificate],'创建专用签名证书');
   run('/usr/bin/openssl',['pkcs12','-export','-inkey',key,'-in',certificate,'-out',identity,'-name',signingLabel,'-passout','env:ANY_SIDEBAR_SIGNING_PASS'],'封装本机签名',{env:{...process.env,ANY_SIDEBAR_SIGNING_PASS:secret}});
   run('security',['import',identity,'-k',keychain,'-P',secret,'-T','/usr/bin/codesign'],'将专用密钥存入钥匙串');
  }
  run('security',['add-trusted-cert','-r','trustRoot','-p','codeSign','-k',keychain,certificate],'设置信任仅用于代码签名');
  identities=run('security',['find-identity','-v','-p','codesigning'],'检查签名身份').stdout;
  match=identities.match(new RegExp(`([0-9A-F]{40}) "${signingLabel}"`));
 }
 if(!match)throw Error('尚未找到有效的专用签名身份，请检查钥匙串授权。');
 await mkdir(signingDirectory,{recursive:true,mode:0o700});await chmod(signingDirectory,0o700);
 await writeFile(signingMetadata,JSON.stringify({label:signingLabel,identity:match[1]},null,2)+'\n',{mode:0o600});
 const saved=JSON.parse(await readFile(signingMetadata,'utf8'));
 console.log(`已配置专用本机签名：${saved.label}。私钥保留在用户钥匙串，不在工程或安装包中。`);
}finally{await rm(temporary,{recursive:true,force:true});}
