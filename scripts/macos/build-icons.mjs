import {chromium} from 'playwright';
import {readFile,mkdir,rm} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
const output='build/macos/AppIcon.iconset';await rm(output,{recursive:true,force:true});await mkdir(output,{recursive:true});
const svg=await readFile('apps/macos/resources/icon-source.svg','utf8'),browser=await chromium.launch({headless:true});
try{const page=await browser.newPage({deviceScaleFactor:1});for(const size of [16,32,128,256,512])for(const scale of [1,2]){const px=size*scale;await page.setViewportSize({width:px,height:px});await page.setContent('<style>html,body{margin:0;background:transparent}svg{display:block;width:100vw;height:100vh}</style>'+svg);await page.screenshot({path:`${output}/icon_${size}x${size}${scale===2?'@2x':''}.png`,omitBackground:true});}}finally{await browser.close();}
const result=spawnSync('iconutil',['-c','icns',output,'-o','build/macos/AppIcon.icns'],{stdio:'inherit'});process.exit(result.status??1);
