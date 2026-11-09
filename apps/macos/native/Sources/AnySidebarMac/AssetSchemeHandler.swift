import Foundation
import WebKit
import ReadingCore
import ReadingStorage
@MainActor final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    let root:URL
    let runtime:ReadingRuntime
    let store:FileAttachmentStore
    var pending:[ObjectIdentifier:Task<Void,Never>] = [:]
    init(root:URL,runtime:ReadingRuntime,store:FileAttachmentStore) {self.root=root;self.runtime=runtime;self.store=store}
    func webView(_ webView:WKWebView,start urlSchemeTask:any WKURLSchemeTask) {
        let key=ObjectIdentifier(urlSchemeTask)
        pending[key]=Task{[weak self] in
            guard let self,let url=urlSchemeTask.request.url,url.scheme=="anysidebar",url.host=="app",url.query==nil else{return}
            do {
                let components=url.path.split(separator:"/").map(String.init)
                guard !components.contains(".."),!url.absoluteString.lowercased().contains("%2e"),!url.absoluteString.lowercased().contains("%2f") else{throw AppFault("INVALID_ARGUMENT","资源路径无效。")}
                let data:Data,mime:String
                if components.first=="asset" {
                    guard components.count==3,validID(components[1]),["thumbnail","preview"].contains(components[2]),let asset=await runtime.asset(components[1]) else{throw AppFault("IMAGE_MISSING","截图不存在。")}
                    let thumbnail=components[2]=="thumbnail",store=self.store
                    data=try await Task.detached{try store.preview(asset,thumbnail:thumbnail)}.value;mime="image/png"
                } else {
                    let path=components.isEmpty ? "index.html":components.joined(separator:"/")
                    let base=root.appendingPathComponent("web").standardizedFileURL
                    let resource=base.appendingPathComponent(path).standardizedFileURL
                    guard resource.resolvingSymlinksInPath().path.hasPrefix(base.path+"/"),["html","js","css","svg","woff2"].contains(resource.pathExtension) else{throw AppFault("INVALID_ARGUMENT","资源不允许访问。")}
                    data=try await Task.detached{try Data(contentsOf:resource)}.value
                    mime=["html":"text/html","js":"text/javascript","css":"text/css","svg":"image/svg+xml","woff2":"font/woff2"][resource.pathExtension]!
                }
                guard !Task.isCancelled else{return}
                urlSchemeTask.didReceive(URLResponse(url:url,mimeType:mime,expectedContentLength:data.count,textEncodingName:mime.hasPrefix("text/") ? "utf-8":nil));urlSchemeTask.didReceive(data);urlSchemeTask.didFinish()
            } catch {if !Task.isCancelled{urlSchemeTask.didFailWithError(AppFault("RESOURCE_MISSING","资源无法读取。"))}}
            pending[key]=nil
        }
    }
    func webView(_ webView:WKWebView,stop urlSchemeTask:any WKURLSchemeTask) {let key=ObjectIdentifier(urlSchemeTask);pending.removeValue(forKey:key)?.cancel()}
}
