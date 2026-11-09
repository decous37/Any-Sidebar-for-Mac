import {validRequest,type Request,type Envelope,type Operation} from './protocol';
const delay=(ms:number)=>new Promise<void>(resolve=>setTimeout(resolve,ms));
export class NativeBridge {
 readonly epoch=crypto.randomUUID();
 constructor(private readonly post:(request:Request)=>Promise<Envelope> = request=>{const native=window.webkit?.messageHandlers.native;if(!native)return Promise.reject(Error('请从 Mac 应用打开对话面板。'));return native.postMessage(request);}){}
 private async raw(command:string,args:Record<string,unknown>,operationId:string):Promise<unknown>{const request:Request={version:1,viewEpoch:this.epoch,messageId:crypto.randomUUID(),operationId,command,args};if(!validRequest(request))throw Error('操作参数无效。');const response=await this.post(request);if(!response.ok)throw Object.assign(Error(response.error?.message??'本机操作失败。'),response.error);return response.data;}
 async call(command:string,args:Record<string,unknown>={},operationId=crypto.randomUUID()):Promise<unknown>{
  let timer:ReturnType<typeof setTimeout>|undefined;
  try{return await Promise.race([this.raw(command,args,operationId),new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(Object.assign(Error('正在核对操作结果…'),{code:'BRIDGE_TIMEOUT'})),15000);})]);}
  catch(error){
   if((error as {code?:string}).code!=='BRIDGE_TIMEOUT'||['bootstrap','getTaskView','listTasks','getCredentialStatus','getOperation'].includes(command))throw error;
   for(let i=0;i<30;i++){const op=await this.raw('getOperation',{sourceOperationId:operationId},crypto.randomUUID()) as Operation|null;if(op?.state==='succeeded')return this.raw('bootstrap',{},crypto.randomUUID());if(op?.state==='failed')throw Object.assign(Error(op.error?.message??'操作失败。'),op.error);await delay(1000);}
   throw Object.assign(Error('操作仍在处理中，请刷新查看结果；不要重复发送。'),{code:'OPERATION_PENDING',operationId});
  }finally{clearTimeout(timer);}
 }
}
