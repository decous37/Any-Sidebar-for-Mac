import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import rehypeSanitize from 'rehype-sanitize';
import {Copy,Check,ChevronDown} from 'lucide-react';
import {useState} from 'react';
import TooltipButton from './TooltipButton';
import {useClipboard} from './ClipboardProvider';
export function CopyButton({text,label='复制回答'}:{text:string;label?:string}){const [copied,setCopied]=useState(false),[error,setError]=useState(false);const write=useClipboard();return <> <TooltipButton className="icon-button small" tip="复制" aria-label={label} onClick={()=>{void write(text).then(()=>{setCopied(true);setError(false);setTimeout(()=>setCopied(false),1600);}).catch(()=>setError(true));}}>{copied?<Check size={15}/>:<Copy size={15}/>}</TooltipButton>{error&&<span role="status" className="copy-error">复制失败</span>}</>;}
export default function MarkdownMessage({answer,reasoning}:{answer:string;reasoning?:string}){return <>{reasoning&&<details className="thinking"><summary><ChevronDown size={14}/>思考过程</summary><div className="reasoning">{reasoning}</div></details>}<div className="markdown"><ReactMarkdown remarkPlugins={[remarkGfm]} rehypePlugins={[rehypeSanitize]} skipHtml components={{img:()=>null,a:({href,children})=>/^https?:\/\//i.test(href??'')?<a href={href} target="_blank" rel="noopener noreferrer">{children}</a>:<span>{children}</span>,pre:({children})=><div className="code-wrap"><pre>{children}</pre></div>,code:({children,className})=>{const text=String(children);return <><code className={className}>{children}</code>{text.includes('\n')&&<CopyButton text={text.replace(/\n$/,'')} label="复制代码"/>}</>},table:({children})=><div className="table-wrap"><table>{children}</table></div>}}>{answer}</ReactMarkdown></div></>;}
