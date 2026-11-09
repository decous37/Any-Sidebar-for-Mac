import schema from '../contracts/bridge.schema.json';
export type ID=string;
export interface Fault {code:string;message:string;retryable:boolean;currentRevision?:number}
export interface SourceView {id:ID;kind:string;appBundleId?:string;appName?:string;documentTitle?:string;pageLabel?:string;capturedAt:number}
export interface ExternalQuote {id:ID;revision:number;text:string;source:SourceView}
export interface AssistantQuote {id:ID;revision:number;sourceTurnId:ID;sourceRequestId:ID;text:string;selectedAt:number}
export interface ImageView {id:ID;draftItemId?:ID;source:SourceView;width:number;height:number;byteLength:number;thumbnailURL:string;previewURL:string}
export interface Draft {taskId:ID;revision:number;promptRevision:number;prompt:string;externalQuotes:ExternalQuote[];assistantQuote?:AssistantQuote;images:ImageView[]}
export interface TaskRecord {id:ID;title:string;revision:number;activeOperationId?:ID;activeRequestId?:ID;createdAt:number;updatedAt:number}
export interface Turn {id:ID;requestId:ID;prompt:string;externalQuotes:ExternalQuote[];assistantQuote?:AssistantQuote;images:ImageView[];answer:string;reasoning:string;status:string;error?:Fault;canRegenerate:boolean}
export interface TaskView {task:TaskRecord;draft:Draft;turns:Turn[];nextCursor?:number}
export interface Shortcut {keyCode:number;modifiers:('command'|'control'|'option'|'shift')[]}
export interface Preferences {revision:number;modelId:string;thinkingEnabled:boolean;reasoningEffort:'low'|'high'|'max';theme:'system'|'light'|'dark';fontSize:12|13|14|16;quoteMode:'accumulate'|'latest';autoSelectionEnabled:boolean;captureShortcut?:Shortcut;panelShortcut?:Shortcut;disclosureVersion?:string;companionVisible:boolean}
export interface Model {modelId:string;label:string;providerId:string;inputModalities:string[];reasoningEfforts:string[]}
export interface Runtime {bootId:ID;sequence:number;activeTaskId?:ID;tasks:TaskRecord[];currentTask?:TaskView;preferences:Preferences;models:Model[]}
export interface Bootstrap {systemRevision?:number;runtime:Runtime;permissions:{accessibility:boolean;screen:boolean};credential:{state:'known';configured:boolean}|{state:'unknown';error:Fault};shortcutState:string;panelShortcutState?:string;recordingKind?:'capture'|'panel';recordingOperationId?:ID|null;recordedShortcut?:Shortcut|null;captureOperationId?:ID|null;captureError?:Fault|null;selectionStatus:string;appFault?:Fault|null}
export interface NativeEvent {type:string;bootId:ID;sequence:number}
export interface Operation {id:ID;command:string;state:'pending'|'succeeded'|'failed';resultId?:ID;error?:Fault}
export interface Envelope {ok:boolean;messageId?:ID;data?:unknown;error?:Fault}
export interface Request {version:1;viewEpoch:ID;messageId:ID;operationId:ID;command:string;args:Record<string,unknown>}
export const isID=(v:unknown):v is ID=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export const object=(v:unknown):v is Record<string,unknown>=>!!v&&typeof v==='object'&&!Array.isArray(v);
const integer=(v:unknown)=>typeof v==='number'&&Number.isSafeInteger(v)&&v>=0;
export function validRequest(value:unknown):value is Request{
 if(!object(value)||Object.keys(value).sort().join()!==['version','viewEpoch','messageId','operationId','command','args'].sort().join()||value.version!==1||!isID(value.viewEpoch)||!isID(value.messageId)||!isID(value.operationId)||typeof value.command!=='string'||!object(value.args))return false;
 const commands:Record<string,{required:Record<string,string>;optional:Record<string,string>}>=schema.commands,rule=commands[value.command];if(!rule)return false;
 const args=value.args;
 if(Object.keys(rule.required).some(k=>!(k in args)))return false;
 return Object.entries(args).every(([k,v])=>{const type=rule.required[k]??rule.optional[k];if(!type)return false;if(type==='id')return isID(v);if(type==='string')return typeof v==='string'&&new TextEncoder().encode(v).length<=2*1024*1024;if(type==='integer')return integer(v);if(type==='boolean')return typeof v==='boolean';if(type==='object')return object(v);return typeof v==='string'&&type.split('|').includes(v);});
}
function required(value:unknown,condition:boolean):asserts condition{if(!condition)throw Error('本机数据格式异常，请重新打开面板。');}
function validateImage(value:unknown){required(value,object(value));required(value,isID(value.id)&&integer(value.width)&&integer(value.height)&&integer(value.byteLength));for(const k of ['thumbnailURL','previewURL'])required(value,typeof value[k]==='string'&&new RegExp('^anysidebar://app/asset/'+value.id+'/(thumbnail|preview)$').test(String(value[k])));}
function noPrivateFields(value:unknown){if(Array.isArray(value))value.forEach(noPrivateFields);else if(object(value)){for(const [key,v] of Object.entries(value)){if(['documentIdentity','storageKey','thumbnailKey','key','apiKey','base64','sourceLeaseId'].includes(key))throw Error('本机视图包含不可显示的字段。');noPrivateFields(v);}}}
export function decodeBootstrap(value:unknown):Bootstrap{
 noPrivateFields(value);required(value,object(value)&&object(value.runtime)&&object(value.permissions)&&object(value.credential));
 const runtime=value.runtime;required(runtime,object(runtime)&&isID(runtime.bootId)&&integer(runtime.sequence)&&Array.isArray(runtime.tasks)&&object(runtime.preferences)&&Array.isArray(runtime.models));
 const p=runtime.preferences;required(p,object(p)&&integer(p.revision)&&typeof p.modelId==='string'&&typeof p.thinkingEnabled==='boolean'&&['low','high','max'].includes(String(p.reasoningEffort))&&[12,13,14,16].includes(Number(p.fontSize))&&['system','light','dark'].includes(String(p.theme))&&['accumulate','latest'].includes(String(p.quoteMode))&&typeof p.autoSelectionEnabled==='boolean');
 for(const t of runtime.tasks as unknown[]){required(t,object(t)&&isID(t.id)&&typeof t.title==='string'&&integer(t.revision));}
 if(runtime.currentTask){const t=runtime.currentTask;required(t,object(t)&&object(t.task)&&isID(t.task.id)&&object(t.draft)&&t.draft.taskId===t.task.id&&typeof t.draft.prompt==='string'&&integer(t.draft.revision)&&integer(t.draft.promptRevision)&&Array.isArray(t.draft.images)&&Array.isArray(t.draft.externalQuotes)&&Array.isArray(t.turns));(t.draft.images as unknown[]).forEach(validateImage);for(const turn of t.turns as unknown[]){required(turn,object(turn)&&isID(turn.id)&&isID(turn.requestId)&&typeof turn.answer==='string'&&typeof turn.prompt==='string'&&Array.isArray(turn.images)&&Array.isArray(turn.externalQuotes));(turn.images as unknown[]).forEach(validateImage);}}
 const credential=value.credential;required(credential,object(credential)&&(credential.state==='known'?typeof credential.configured==='boolean':credential.state==='unknown'&&object(credential.error)));
 return value as unknown as Bootstrap;
}
declare global {interface Window{webkit?:{messageHandlers:{native:{postMessage:(request:Request)=>Promise<Envelope>}}}}}
