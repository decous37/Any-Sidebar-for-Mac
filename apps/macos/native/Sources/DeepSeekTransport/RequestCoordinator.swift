import Foundation
import ReadingCore
public actor RequestCoordinator: ModelTransport {
    private let vault: any CredentialReader
    private var leases: [ID:(preparationId:ID,key:String)] = [:]
    private var jobs: [ID:Task<Void,Never>] = [:]
    private var started:Set<ID>=[]
    private var stopped:Set<ID>=[]
    public init(vault: any CredentialReader) {self.vault=vault}
    public func acquire(preparationId: ID) async throws -> NativeCredentialLease {
        let key=try await vault.readForRequest()
        guard !key.isEmpty else{throw AppFault("CREDENTIAL_REQUIRED","请先填写 API Key。")}
        let lease=NativeCredentialLease(id:newID(),preparationId:preparationId);leases[lease.id]=(preparationId,key);return lease
    }
    public func release(_ lease: NativeCredentialLease) {leases.removeValue(forKey:lease.id)}
    public func stream(requestId: ID, body: Data, lease: NativeCredentialLease) throws -> AsyncThrowingStream<StreamDelta,Error> {
        guard !started.contains(requestId),!stopped.contains(requestId),let entry=leases.removeValue(forKey:lease.id),entry.preparationId==lease.preparationId else{throw AppFault("REQUEST_BUSY","请求已处理或已停止。")}
        started.insert(requestId)
        return AsyncThrowingStream{continuation in
            let job=Task {
                do {try await URLSessionClient().stream(body:body,key:entry.key,continuation:continuation);continuation.finish()}
                catch {continuation.finish(throwing:error)}
                self.finished(requestId)
            }
            jobs[requestId]=job
            continuation.onTermination={_ in job.cancel()}
        }
    }
    private func finished(_ id:ID) {jobs[id]=nil}
    public func stop(requestId: ID) {stopped.insert(requestId);jobs[requestId]?.cancel();jobs[requestId]=nil}
}
