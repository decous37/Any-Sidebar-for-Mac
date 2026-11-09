import Foundation
import ReadingCore
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {completionHandler(nil)}
}
public struct URLSessionClient: Sendable {
    public init() {}
    public func stream(body: Data, key: String, continuation: AsyncThrowingStream<StreamDelta,Error>.Continuation) async throws {
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=120;config.timeoutIntervalForResource=1800;config.urlCache=nil;config.httpCookieStorage=nil
        let delegate=NoRedirect(),session=URLSession(configuration:config,delegate:delegate,delegateQueue:nil)
        defer{session.invalidateAndCancel()}
        var request=URLRequest(url:URL(string:"https://api.deepseek.com/chat/completions")!)
        request.httpMethod="POST";request.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("text/event-stream",forHTTPHeaderField:"Accept");request.httpBody=body
        let (bytes,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse else{throw AppFault("API_BAD_RESPONSE","服务响应无效。")}
        guard http.statusCode==200 else{throw SSEDecoder.httpFault(http.statusCode)}
        guard http.value(forHTTPHeaderField:"Content-Type")?.lowercased().contains("text/event-stream")==true else{throw AppFault("API_BAD_RESPONSE","服务未返回流式回答。")}
        var decoder=SSEDecoder()
        for try await byte in bytes {try Task.checkCancellation();for delta in try decoder.feed(byte) {continuation.yield(delta)}}
        for delta in try decoder.finish() {continuation.yield(delta)}
    }
}
