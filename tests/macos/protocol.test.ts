import {describe,it,expect} from 'vitest';
import cases from '../../apps/macos/contracts/fixtures/bridge-cases.json';
import {validRequest,decodeBootstrap} from '../../apps/macos/web/protocol';
import {bootstrap} from './fixtures';
describe('native boundary',()=>{
 for(const c of cases)it(c.id,()=>expect(validRequest(c.input)).toBe(c.allowed));
 it('rejects private file fields',()=>{const view=bootstrap();Object.assign(view.runtime.currentTask!.draft,{storageKey:'/private/a'});expect(()=>decodeBootstrap(view)).toThrow();});
 it('rejects external image URLs',()=>{const view=bootstrap();view.runtime.currentTask!.draft.images.push({id:'x',source:{id:'x',kind:'screen-region',capturedAt:0},width:2,height:2,byteLength:4,thumbnailURL:'https://example.com/private.png',previewURL:'file:///private/x'});expect(()=>decodeBootstrap(view)).toThrow();});
 it('keeps credential unknown distinct',()=>{const view=bootstrap();view.credential={state:'unknown',error:{code:'CREDENTIAL_ACCESS_DENIED',message:'系统拒绝检查',retryable:true}};expect(decodeBootstrap(view).credential.state).toBe('unknown');});
});
