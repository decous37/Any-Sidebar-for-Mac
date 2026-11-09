import {webcrypto} from 'node:crypto';
import {vi} from 'vitest';
Object.defineProperty(globalThis,'crypto',{value:webcrypto,configurable:true});
Object.defineProperty(globalThis,'matchMedia',{value:()=>({matches:false,addEventListener:()=>{},removeEventListener:()=>{}}),configurable:true});
Object.defineProperty(globalThis,'ResizeObserver',{value:class{observe(){}disconnect(){}},configurable:true});
HTMLDialogElement.prototype.showModal=vi.fn(function(this:HTMLDialogElement){this.setAttribute('open','');});
HTMLDialogElement.prototype.close=vi.fn(function(this:HTMLDialogElement){this.removeAttribute('open');});
Element.prototype.scrollIntoView=vi.fn();
