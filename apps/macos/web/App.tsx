import {useEffect,useRef,useState,useSyncExternalStore} from 'react';
import {Menu,Settings,Scan,ArrowUpRight,X,PanelLeftClose} from 'lucide-react';
import {ClipboardProvider} from '../../../src/ui/ClipboardProvider';
import ConversationView from '../../../src/ui/ConversationView';
import TooltipButton from '../../../src/ui/TooltipButton';
import Dialog from '../../../src/ui/Dialog';
import type {ConversationTurn} from '../../../src/ui/view-models';
import {MacStore} from './store';
import {turnView} from './adapters';
import type {Preferences,TaskRecord} from './protocol';
import TaskPicker from './components/TaskPicker';
import PermissionNotice from './components/PermissionNotice';
import MacSettings from './components/MacSettings';
import MacComposer from './components/MacComposer';
import ImagePreview from './components/ImagePreview';
type Modal={kind:'key'|'create'|'rename'|'delete'|'clear'|'restore';turn?:ConversationTurn;task?:TaskRecord};
export default function App({store:injected}:{store?:MacStore}){
 const [store]=useState(()=>injected??new MacStore());useSyncExternalStore(store.subscribe,store.getSnapshot);
 const [drawer,setDrawer]=useState(false);
 const [settings,setSettings]=useState(false),[focusKey,setFocusKey]=useState(false),[modal,setModal]=useState<Modal|null>(null),[title,setTitle]=useState(''),[preview,setPreview]=useState<string|null>(null),[followup,setFollowup]=useState(false);
 const input=useRef<HTMLTextAreaElement>(null);
 const data=store.data,p=data?.runtime.preferences,current=data?.runtime.currentTask;
 useEffect(()=>{void store.refresh().catch(e=>store.fail(e));const event=(e:Event)=>{const detail=(e as CustomEvent).detail;store.event(detail);if(detail.type==='open-settings'){setFocusKey(false);setSettings(true);}};const focus=()=>{void store.refresh().catch(e=>store.fail(e));};window.addEventListener('native-event',event);window.addEventListener('focus',focus);return()=>{window.removeEventListener('native-event',event);window.removeEventListener('focus',focus);};},[store]);
 useEffect(()=>{if(!p)return;const media=matchMedia('(prefers-color-scheme: dark)');const apply=()=>{document.documentElement.dataset.theme=p.theme==='system'?(media.matches?'dark':'light'):p.theme;document.documentElement.style.setProperty('--conversation-font-size',p.fontSize+'px');};apply();media.addEventListener('change',apply);return()=>media.removeEventListener('change',apply);},[p?.theme,p?.fontSize]);
 async function perform(action:()=>Promise<unknown>){try{store.clearError();await action();}catch(error){store.fail(error);if((error as {code?:string}).code==='CREDENTIAL_REQUIRED')setModal({kind:'key'});}}
 async function command(c:string,args:Record<string,unknown>={}){if(c==='confirmClearAll'){setModal({kind:'clear'});return;}if(c==='startShortcutRecording')input.current?.blur();try{store.clearError();await store.command(c,args);}catch(error){store.fail(error);throw error;}}
 async function preferences(patch:Partial<Preferences>){await perform(()=>store.savePreferences(patch));}
 async function send(suggestion?:string){if(!current)return;if(suggestion)store.edit(current.task.id,suggestion);if(data?.credential.state==='known'&&!data.credential.configured){setModal({kind:'key'});return;}await perform(()=>store.send());setFollowup(false);}
 async function quote(t:ConversationTurn,text:string,next=false){await perform(()=>store.changeDraft({kind:'assistantQuote',turnId:t.id,requestId:t.requestId,text}));if(next){setFollowup(true);input.current?.focus();}}
 async function replay(t:ConversationTurn,kind:string){if(!current||!p)return;await perform(async()=>{await store.flush(current.task.id);await store.command(kind,{taskId:current.task.id,turnId:t.id,requestId:t.requestId,expectedPreferencesRevision:store.data!.runtime.preferences.revision});});}
 async function confirm(){
  if(!modal||!current)return;const m=modal;setModal(null);
  const target=m.task??current.task;
  if(m.kind==='key'){setFocusKey(true);setSettings(true);return;}
  await perform(async()=>{
   await store.flush(current.task.id);
   if(m.kind==='create')await store.command('createTask',{title:title.trim()||'阅读任务'});
   if(m.kind==='rename')await store.command('renameTask',{taskId:target.id,title:title.trim(),expectedRevision:target.revision});
   if(m.kind==='delete')await store.command('deleteTask',{taskId:target.id,expectedRevision:target.revision});
   if(m.kind==='clear')await store.command('clearAllTasks');
   if(m.kind==='restore'&&m.turn)await store.command('restoreSubmission',{taskId:current.task.id,requestId:m.turn.requestId,expectedDraftRevision:store.data!.runtime.currentTask!.draft.revision});
  });
 }
 if(!data||!current)return <div className="app-shell"><header className="topbar"><div className="brand">Any Sidebar</div></header><div className="welcome"><p>{store.error||'正在连接本机服务…'}</p>{store.error&&<button className="solid-button" onClick={()=>void perform(()=>store.refresh())}>重新连接</button>}</div></div>;
 const turns=current.turns.map((t,i)=>turnView(t,i,current.turns.length)),active=store.busy||!!current.task.activeOperationId;
 const openSettings=()=>{setFocusKey(false);setSettings(true);};
 return <ClipboardProvider write={async text=>{await store.bridge.call('copyText',{text});}}><div className="app-shell"><header className="topbar"><div className="topbar-leading"><TooltipButton tip="收起" aria-label="收起浮窗" className="icon-button" onClick={()=>void perform(()=>store.command('hidePanel'))}><PanelLeftClose size={18}/></TooltipButton><TooltipButton tip="会话" aria-label="打开会话抽屉" className="icon-button" onClick={()=>setDrawer(true)}><Menu size={19}/></TooltipButton><div className="brand">Any Sidebar</div></div><TooltipButton tip="设置" aria-label="设置" className="icon-button" onClick={openSettings}><Settings size={18}/></TooltipButton></header><PermissionNotice data={data} onSettings={openSettings}/>{store.error&&<div className="notice" role="alert"><span>{store.error}</span><TooltipButton tip="关闭" aria-label="关闭提示" className="icon-button small" onClick={()=>store.clearError()}><X size={14}/></TooltipButton></div>}{data.appFault&&<div className="notice" role="alert">{data.appFault.message}</div>}{data.captureError&&data.captureError.code!=='CAPTURE_CANCELLED'&&<div className="notice" role="status">{data.captureError.message}</div>}
 {turns.length?<ConversationView taskId={current.task.id} turns={turns} active={active} quote={current.draft.assistantQuote} onQuote={(t,text,next)=>void quote(t,text,next)} onClearQuote={id=>void perform(()=>store.changeDraft({kind:'clearAssistantQuote',id}))} onRetry={t=>void replay(t,'retry')} onRegenerate={t=>void replay(t,'regenerate')} onRestore={turn=>setModal({kind:'restore',turn})} onOlder={()=>void perform(async()=>{const old=await store.bridge.call('getTaskView',{taskId:current.task.id,cursor:current.nextCursor}) as {runtime:typeof data.runtime};const previous=old.runtime.currentTask;if(previous){previous.turns=[...previous.turns,...current.turns];store.accept({...data,runtime:old.runtime});}})} hasOlder={current.nextCursor!=null} onImage={setPreview}/>:<div className="welcome"><Scan size={30} className="welcome-icon"/><h1>读懂眼前的资料</h1><p>划选文字或截取图片，直接提问。</p><div className="suggestions">{(current.draft.images.length?['解释这张截图中的主要内容','帮我读懂这张图表或公式']:current.draft.externalQuotes.length?['解释这段内容，补充必要的背景','用一个例子说明这段话']:[]).map(text=><button key={text} disabled={active} onClick={()=>void send(text)}>{text}<ArrowUpRight size={14}/></button>)}</div>{data.credential.state==='known'&&!data.credential.configured&&<button className="setup-link" onClick={()=>{setFocusKey(true);setSettings(true);}}>填写 API Key</button>}</div>}
 <MacComposer data={data} input={store.input(current.task.id)} inputRef={input} active={active} followup={followup} onEdit={text=>store.edit(current.task.id,text)} onSend={()=>void send()} onStop={()=>void perform(()=>store.command('stop',{target:current.task.activeRequestId?{kind:'request',taskId:current.task.id,requestId:current.task.activeRequestId}:{kind:'operation',taskId:current.task.id,sourceOperationId:current.task.activeOperationId}}))} onPreferences={patch=>void preferences(patch)} onDraft={change=>void perform(()=>store.changeDraft(change))} onCapture={mode=>void perform(()=>store.command('startCapture',{taskId:current.task.id,mode}))} onPreview={image=>setPreview(image.previewURL)}/>
 {drawer&&<TaskPicker tasks={data.runtime.tasks} current={current.task.id} disabled={store.busy} onClose={()=>setDrawer(false)} onSwitch={id=>{setDrawer(false);void perform(()=>store.switchTask(id));setFollowup(false);}} onCreate={()=>{setDrawer(false);setTitle('');setModal({kind:'create'});}} onRename={task=>{setDrawer(false);setTitle(task.title);setModal({kind:'rename',task});}} onDelete={task=>{setDrawer(false);setModal({kind:'delete',task});}}/>}
 {settings&&<MacSettings data={data} focusKey={focusKey} onClose={()=>{setSettings(false);if(data.recordingOperationId)void perform(()=>store.command('cancelShortcutRecording',{recordingOperationId:data.recordingOperationId}));}} error={store.error} onCommand={command} onPreferences={preferences}/>}
 {preview&&<ImagePreview url={preview} onClose={()=>setPreview(null)}/>}
 {modal&&<Dialog title={{key:'请先填写 API Key',create:'新建会话',rename:'重命名会话',delete:'删除此会话？',clear:'删除全部会话？',restore:'恢复原问题？'}[modal.kind]} onClose={()=>setModal(null)} initialFocus={['create','rename'].includes(modal.kind)?'input':undefined}>{['create','rename'].includes(modal.kind)?<input className="task-name-input" aria-label="会话名称" value={title} maxLength={120} onChange={e=>setTitle(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'&&!e.nativeEvent.isComposing)void confirm();}}/>:<p>{modal.kind==='key'?'问题和引用会保留。点击确定后前往设置，保存 Key 后再发送。':modal.kind==='restore'?'替换输入文字，保留当前已有的引用和截图。':'相关对话和独占截图将从本机删除，此操作无法撤销。'}</p>}<div className="dialog-actions"><button className="text-button" onClick={()=>setModal(null)}>取消</button><button className="solid-button" onClick={()=>void confirm()}>确定</button></div></Dialog>}
 </div></ClipboardProvider>;
}
