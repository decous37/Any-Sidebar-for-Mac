import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));
const result=spawnSync('swift',['test','--package-path',`${root}apps/macos/native`,'--disable-xctest','--enable-swift-testing','-Xswiftc','-F/Library/Developer/CommandLineTools/Library/Developer/Frameworks','-Xlinker','-rpath','-Xlinker','/Library/Developer/CommandLineTools/Library/Developer/Frameworks','-Xlinker','-rpath','-Xlinker','/Library/Developer/CommandLineTools/Library/Developer/usr/lib',...process.argv.slice(2)],{stdio:'inherit',env:{...process.env,ANY_SIDEBAR_CONTRACTS:`${root}apps/macos/contracts`}});
process.exit(result.status??1);
