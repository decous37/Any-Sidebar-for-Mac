import {useEffect,useRef} from 'react';
import {Plus,Pencil,Trash2,ChevronLeft,MessageSquare} from 'lucide-react';
import TooltipButton from '../../../../src/ui/TooltipButton';
import type {TaskRecord} from '../protocol';
export default function TaskPicker({tasks,current,onClose,onSwitch,onCreate,onRename,onDelete,disabled}:{tasks:TaskRecord[];current:string;onClose:()=>void;onSwitch:(id:string)=>void;onCreate:()=>void;onRename:(task:TaskRecord)=>void;onDelete:(task:TaskRecord)=>void;disabled:boolean}){
 const dialog=useRef<HTMLDialogElement>(null);
 useEffect(()=>{const previous=document.activeElement as HTMLElement|null;dialog.current?.showModal();return()=>{dialog.current?.close();previous?.focus();};},[]);
 return <dialog ref={dialog} className="task-drawer" aria-label="会话" onCancel={e=>{e.preventDefault();onClose();}}>
  <header className="drawer-header"><button className="icon-button" aria-label="返回对话" onClick={onClose}><ChevronLeft size={20}/></button><h2>会话</h2></header>
  <button className="new-task" disabled={disabled} onClick={onCreate}><Plus size={17}/>新建会话</button>
  <nav className="task-list" aria-label="会话列表">{tasks.map(task=><div className="task-row" data-active={task.id===current} key={task.id}>
   <button className="task-open" aria-current={task.id===current?'page':undefined} disabled={disabled} onClick={()=>onSwitch(task.id)}><MessageSquare size={14}/><span>{task.title}</span></button>
   <div className="task-actions"><TooltipButton tip="重命名" aria-label={`重命名 ${task.title}`} className="icon-button small" disabled={disabled} onClick={()=>onRename(task)}><Pencil size={13}/></TooltipButton><TooltipButton tip="删除" aria-label={`删除 ${task.title}`} className="icon-button small" disabled={disabled} onClick={()=>onDelete(task)}><Trash2 size={13}/></TooltipButton></div>
  </div>)}</nav>
 </dialog>;
}
