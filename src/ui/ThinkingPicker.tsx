import {Brain,ChevronDown} from 'lucide-react';
export default function ThinkingPicker({enabled,effort,efforts,disabled,onChange}:{enabled:boolean;effort:string;efforts:readonly string[];disabled?:boolean;onChange:(value:string)=>void}){
 const label=(e:string)=>({low:'低',high:'高',max:'最高'}[e]??e),unavailable=disabled||efforts.length===0;
 return <label className="thinking-picker picker-control" data-enabled={enabled} data-disabled={unavailable}><span className="visually-hidden">思考强度</span><Brain size={13}/><span className="picker-value" aria-hidden="true">{enabled?'思考·'+label(effort):'关闭思考'}</span><select aria-label="思考强度" value={enabled?effort:'off'} disabled={unavailable} onChange={e=>onChange(e.target.value)}><option value="off">关闭思考</option>{efforts.map(e=><option key={e} value={e}>思考·{label(e)}</option>)}</select><ChevronDown size={11}/></label>;
}
