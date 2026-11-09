import {useEffect,useRef,type ReactNode} from 'react';
export default function Dialog({title,children,onClose,initialFocus}:{title:string;children:ReactNode;onClose:()=>void;initialFocus?:string}){
 const ref=useRef<HTMLDialogElement>(null);
 useEffect(()=>{const el=ref.current;const previous=document.activeElement as HTMLElement|null;el?.showModal();if(initialFocus)el?.querySelector<HTMLElement>(initialFocus)?.focus();return()=>{el?.close();previous?.focus();};},[initialFocus]);
 return <dialog ref={ref} className="compact-dialog" aria-label={title} onCancel={e=>{e.preventDefault();onClose();}}><h2>{title}</h2>{children}</dialog>;
}
