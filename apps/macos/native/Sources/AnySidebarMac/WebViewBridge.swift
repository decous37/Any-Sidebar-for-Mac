import Foundation
import WebKit
import ReadingCore
import ReadingStorage
@MainActor final class WebViewBridge:NSObject,WKScriptMessageHandlerWithReply {
    let schema:CommandSchema
    unowned let composition:AppComposition
    weak var web:WKWebView?
    var epoch=newID()
    init(schema:CommandSchema,composition:AppComposition){self.schema=schema;self.composition=composition}
    func invalidate(){epoch=newID()}
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage,replyHandler:@escaping @MainActor @Sendable (Any?,String?)->Void){
        guard message.frameInfo.isMainFrame,let url=message.frameInfo.request.url,url.scheme=="anysidebar",url.host=="app" else{replyHandler(nil,"不允许的页面来源。");return}
        Task {
            do {
                let data=try JSONSerialization.data(withJSONObject:message.body)
                let request=try BridgeRequest.decode(data,schema:schema,epoch:epoch,allowBootstrap:true)
                if request.command=="bootstrap"{epoch=request.viewEpoch}
                let result=try await composition.dispatch(request)
                let payload:[String:JSONValue] = ["messageId":.string(request.messageId),"ok":.bool(true),"data":result]
                replyHandler(try JSONSerialization.jsonObject(with:JSONEncoder().encode(payload)),nil)
            } catch {
                let fault=(error as? AppFault) ?? AppFault("INVALID_ARGUMENT","操作未完成，请重试。",retryable:true)
                let payload:[String:JSONValue] = ["ok":.bool(false),"error":(try? .encode(fault)) ?? .null]
                replyHandler(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(payload)),nil)
            }
        }
    }
    func event(_ type:String){
        guard let web else{return}
        Task {
            let view=try? await composition.runtime.view()
            let event:[String:Any]=["type":type,"bootId":view?.bootId ?? "","sequence":view?.sequence ?? 0]
            _ = try? await web.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('native-event',{detail:event}));",arguments:["event":event],in:nil,contentWorld:.page)
        }
    }
}
