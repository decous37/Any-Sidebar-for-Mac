import {NativeBridge} from './bridge';
import {decodeBootstrap,type Bootstrap,type Draft,type NativeEvent,type Preferences} from './protocol';
type Buffer={text:string;saved:string;promptRevision:number;dirty:boolean};
export class MacStore {
 data:Bootstrap|undefined;error='';busy=false;private listeners=new Set<()=>void>();private buffers=new Map<string,Buffer>();private tail:Promise<unknown>=Promise.resolve();private refreshTimer:ReturnType<typeof setTimeout>|undefined;private version=0;private saveTimers=new Map<string,ReturnType<typeof setTimeout>>();
 constructor(readonly bridge=new NativeBridge()){}
 subscribe=(listener:()=>void)=>{this.listeners.add(listener);return()=>{this.listeners.delete(listener);};};
 getSnapshot=()=>this.version;
 private notify(){this.version++;for(const listener of this.listeners)listener();}
 accept(data:unknown){const next=decodeBootstrap(data);const prev=this.data;if(prev?.runtime.bootId===next.runtime.bootId&&(next.runtime.sequence<prev.runtime.sequence||(next.systemRevision??0)<(prev.systemRevision??0)))return;this.data=next;const d=next.runtime.currentTask?.draft;if(d){const b=this.buffers.get(d.taskId);if(!b||!b.dirty)this.buffers.set(d.taskId,{text:d.prompt,saved:d.prompt,promptRevision:d.promptRevision,dirty:false});}this.notify();}
 async refresh(){this.accept(await this.bridge.call('bootstrap'));}
 event(event:NativeEvent){if(!this.data||event.bootId!==this.data.runtime.bootId||event.sequence>this.data.runtime.sequence||event.type==='shortcut-recording-changed'||event.type==='capture-changed'||event.type==='permissions-changed'||event.type==='credential-changed'){clearTimeout(this.refreshTimer);this.refreshTimer=setTimeout(()=>{void this.refresh().catch(e=>this.fail(e));},40);}}
 input(taskId:string){return this.buffers.get(taskId)?.text??this.data?.runtime.currentTask?.draft.prompt??'';}
 edit(taskId:string,text:string){const d=this.data?.runtime.currentTask?.draft;if(!d||d.taskId!==taskId)return;const b=this.buffers.get(taskId)??{text:d.prompt,saved:d.prompt,promptRevision:d.promptRevision,dirty:false};this.buffers.set(taskId,{...b,text,dirty:text!==b.saved});clearTimeout(this.saveTimers.get(taskId));this.saveTimers.set(taskId,setTimeout(()=>{void this.flush(taskId).catch(e=>this.fail(e));},300));this.notify();}
 private enqueue<T>(action:()=>Promise<T>):Promise<T>{const next=this.tail.then(action);this.tail=next.catch(()=>{});return next;}
 async command(command:string,args:Record<string,unknown>={}){return this.enqueue(async()=>{const result=await this.bridge.call(command,args);if(result&&typeof result==='object'&&'runtime' in result)this.accept(result);return result;});}
 private async saveBuffer(taskId:string){
  const b=this.buffers.get(taskId);if(!b?.dirty)return;
  await this.refresh();const current=this.data?.runtime.currentTask;if(current?.task.id!==taskId)throw Error('任务已切换，输入暂存于原任务。');
  if(current.draft.promptRevision!==b.promptRevision&&current.draft.prompt!==b.saved)throw Error('另一处修改了问题，当前输入仍已保留。请复制输入后重新打开任务。');
  const frozen=b.text;this.accept(await this.bridge.call('changeDraft',{taskId,expectedRevision:current.draft.revision,change:{kind:'prompt',text:frozen}}));
  const latest=this.buffers.get(taskId);const draft=this.data!.runtime.currentTask!.draft;
  if(latest)this.buffers.set(taskId,{text:latest.text,saved:frozen,promptRevision:draft.promptRevision,dirty:latest.text!==frozen});this.notify();
 }
 flush(taskId:string){return this.enqueue(()=>this.saveBuffer(taskId));}
 savePreferences(patch:Partial<Preferences>){return this.enqueue(async()=>{await this.refresh();this.accept(await this.bridge.call('savePreferences',{expectedRevision:this.data!.runtime.preferences.revision,patch}));});}
 changeDraft(change:Record<string,unknown>){return this.enqueue(async()=>{await this.refresh();const draft=this.data!.runtime.currentTask!.draft;this.accept(await this.bridge.call('changeDraft',{taskId:draft.taskId,expectedRevision:draft.revision,change}));});}
 async switchTask(id:string){const current=this.data?.runtime.currentTask?.task.id;if(current)await this.flush(current);await this.command('switchTask',{taskId:id});}
 async send(){if(this.busy)return;this.busy=true;this.notify();try{const id=this.data!.runtime.currentTask!.task.id;await this.flush(id);await this.enqueue(async()=>{await this.saveBuffer(id);const d=this.data!.runtime.currentTask!.draft,p=this.data!.runtime.preferences;this.accept(await this.bridge.call('send',{taskId:id,expectedDraftRevision:d.revision,expectedPreferencesRevision:p.revision}));const b=this.buffers.get(id),after=this.data!.runtime.currentTask!.draft;if(b){this.buffers.set(id,{text:b.dirty?b.text:after.prompt,saved:after.prompt,promptRevision:after.promptRevision,dirty:b.dirty&&b.text!==after.prompt});}});}finally{this.busy=false;this.notify();}}
 fail(error:unknown){this.error=error instanceof Error?error.message:String(error);this.notify();}
 clearError(){this.error='';this.notify();}
 draft():Draft|undefined{return this.data?.runtime.currentTask?.draft;}
}
