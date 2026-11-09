import {forwardRef,useCallback,useEffect,useId,useLayoutEffect,useRef,useState,type ButtonHTMLAttributes} from 'react';
import {createPortal} from 'react-dom';
interface Props extends ButtonHTMLAttributes<HTMLButtonElement>{tip:string}
/** Short, non-interactive tooltips. Accessible button names remain independent. */
const TooltipButton=forwardRef<HTMLButtonElement,Props>(function TooltipButton({tip,children,onPointerEnter,onPointerLeave,onFocus,onBlur,onClick,onKeyDown,...props},ref){
 const anchor=useRef<HTMLButtonElement|null>(null),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined);
 const [open,setOpen]=useState(false),[position,setPosition]=useState({left:0,top:0});const bubble=useRef<HTMLDivElement>(null),id=useId();
 const hide=useCallback(()=>{clearTimeout(timer.current);setOpen(false);},[]);
 useEffect(()=>()=>clearTimeout(timer.current),[]);
 useEffect(()=>{if(!open)return;const escape=(e:KeyboardEvent)=>{if(e.key==='Escape')hide();};document.addEventListener('keydown',escape);return()=>{document.removeEventListener('keydown',escape);};},[open,hide]);
 useLayoutEffect(()=>{if(!open)return;const place=()=>{if(!anchor.current||!bubble.current)return;const a=anchor.current.getBoundingClientRect(),b=bubble.current.getBoundingClientRect();if(a.bottom<0||a.top>innerHeight){hide();return;}setPosition({left:Math.max(6,Math.min(innerWidth-b.width-6,a.left+(a.width-b.width)/2)),top:a.top-b.height-7>=6?a.top-b.height-7:Math.min(innerHeight-b.height-6,a.bottom+7)});};place();window.addEventListener('resize',place);document.addEventListener('scroll',place,true);return()=>{window.removeEventListener('resize',place);document.removeEventListener('scroll',place,true);};},[open,tip,hide]);
 return <><button {...props} ref={node=>{anchor.current=node;if(typeof ref==='function')ref(node);else if(ref)ref.current=node;}} aria-describedby={open?id:undefined} onPointerEnter={e=>{onPointerEnter?.(e);clearTimeout(timer.current);timer.current=setTimeout(()=>setOpen(true),350);}} onPointerLeave={e=>{hide();onPointerLeave?.(e);}} onFocus={e=>{setOpen(true);onFocus?.(e);}} onBlur={e=>{hide();onBlur?.(e);}} onClick={e=>{hide();onClick?.(e);}} onKeyDown={e=>{if(e.key==='Escape')hide();onKeyDown?.(e);}}>{children}</button>{open&&createPortal(<div ref={bubble} id={id} role="tooltip" className="action-tooltip" style={position}>{tip}</div>,anchor.current?.closest('dialog')??document.body)}</>;
});
export default TooltipButton;
