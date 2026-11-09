import {createContext,useContext,type ReactNode} from 'react';
const ClipboardContext=createContext<(text:string)=>Promise<void>>(text=>navigator.clipboard.writeText(text));
export function ClipboardProvider({write,children}:{write:(text:string)=>Promise<void>;children:ReactNode}){return <ClipboardContext.Provider value={write}>{children}</ClipboardContext.Provider>;}
export const useClipboard=()=>useContext(ClipboardContext);
