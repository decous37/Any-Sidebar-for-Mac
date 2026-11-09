import {test,expect} from '@playwright/test';
import {bootstrap} from './fixtures';
import type {Request} from '../../apps/macos/web/protocol';
for(const width of [320,480,600])for(const theme of ['light','dark'] as const)test(`${theme} ${width}px full chat`,async({page})=>{
 const state=bootstrap();state.credential={state:'known',configured:true};state.runtime.preferences.disclosureVersion='v1';state.runtime.preferences.theme=theme;state.permissions={accessibility:true,screen:true};
 state.runtime.currentTask!.draft.prompt='解释缓存的作用';state.runtime.currentTask!.draft.externalQuotes=[{id:crypto.randomUUID(),revision:0,text:'这是一条用于检查省略号的较长引用。'.repeat(12),source:{id:crypto.randomUUID(),kind:'external-selection',documentTitle:'自编阅读样例',capturedAt:0}}];
 await page.setViewportSize({width,height:760});
 await page.addInitScript(data=>{window.webkit={messageHandlers:{native:{postMessage:async(request:Request)=>{const r=data.runtime,t=r.currentTask!;if(request.command==='changeDraft'){const change=request.args.change as {kind:string;text?:string};if(change.kind==='prompt'){t.draft.prompt=change.text!;t.draft.promptRevision++;t.draft.revision++;}}if(request.command==='send'){t.turns.push({id:crypto.randomUUID(),requestId:crypto.randomUUID(),prompt:t.draft.prompt,answer:'缓存保存已完成的计算结果，避免重复计算。\n\n这里先验证输入，再缓存结果。\n\n```js\ncache[key] = result;\n```',reasoning:'',status:'complete',externalQuotes:t.draft.externalQuotes,images:[],canRegenerate:true});t.draft.prompt='';t.draft.revision++;t.draft.promptRevision++;t.draft.externalQuotes=[];}r.sequence++;return{ok:true,data:structuredClone(data)};}}}};},state);
 await page.goto('http://127.0.0.1:4178');
 await expect(page.getByLabel('发送问题')).toBeVisible();
 await page.getByLabel('发送问题').click();
 await expect(page.locator('.answer-body')).toContainText('避免重复计算');
 await expect(page.getByLabel('思考强度')).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 const send=await page.getByLabel('发送问题').boundingBox();expect(send!.x+send!.width).toBeLessThanOrEqual(width);
 await page.screenshot({path:`artifacts/macos/chat-${theme}-${width}.png`});
 await page.getByLabel('设置',{exact:true}).click();await expect(page.getByRole('dialog',{name:'设置'})).toBeVisible();await page.screenshot({path:`artifacts/macos/settings-${theme}-${width}.png`});
});
