import {ChevronDown} from 'lucide-react';
import type {ModelGroup} from './view-models';
/** No assumptions about provider count or the number of models per provider. */
export default function ModelPicker({providers,value,onChange,disabled=false}:{providers:readonly ModelGroup[];value:string;onChange:(model:string)=>void;disabled?:boolean}) {
 const selected=providers.flatMap(p=>p.models).find(m=>m.id===value);
 return <label className="model-picker picker-control" data-disabled={disabled}>
  <span className="visually-hidden">选择模型</span><span className="picker-value" aria-hidden="true">{selected?.label??value}</span>
  <select aria-label="选择模型" value={value} disabled={disabled} onChange={e=>onChange(e.target.value)}>
   {providers.map(provider=><optgroup key={provider.id} label={provider.label}>
    {provider.models.map(model=><option key={model.id} value={model.id}>{model.label}</option>)}
   </optgroup>)}
  </select><ChevronDown size={12}/>
 </label>;
}
