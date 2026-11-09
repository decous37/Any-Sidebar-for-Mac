import Dialog from '../../../../src/ui/Dialog';
export default function ImagePreview({url,onClose}:{url:string;onClose:()=>void}){return <Dialog title="截图预览" onClose={onClose}><img className="image-preview" src={url} alt="本机截图原图"/><div className="dialog-actions"><button className="solid-button" onClick={onClose}>关闭</button></div></Dialog>;}
