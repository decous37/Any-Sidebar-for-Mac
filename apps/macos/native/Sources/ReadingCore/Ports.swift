import Foundation
public protocol ReadingRepository: Sendable {
    func load() throws -> PersistedState
    func save(_ state: PersistedState) throws
}
public protocol AttachmentStore: Sendable {
    func read(_ asset: ImageAsset) throws -> Data
    func removeUnreferenced(keeping: Set<ID>) throws
}
public struct PersistedState: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var tasks: [ID:ReadingTaskRecord] = [:]; public var drafts: [ID:ReadingDraft] = [:]
    public var assets: [ID:ImageAsset] = [:]; public var references: Set<AssetReference> = []
    public var preparations: [ID:PreparationRecord] = [:]; public var snapshots: [ID:RequestSnapshot] = [:]
    public var turns: [ID:TurnRecord] = [:]; public var generations: [ID:GenerationRecord] = [:]
    public var operations: [ID:OperationRecord] = [:]; public var preferences = PreferencesRecord(); public var activeTaskId: ID?
    public init() {}
}
public protocol CredentialReader: Sendable { func readForRequest() async throws -> String }
public struct StreamDelta: Sendable, Equatable {
    public var answer: String; public var reasoning: String; public var finishReason: String?
    public init(answer: String = "", reasoning: String = "", finishReason: String? = nil) { self.answer=answer; self.reasoning=reasoning; self.finishReason=finishReason }
}
public protocol ModelTransport: Sendable {
    func acquire(preparationId: ID) async throws -> NativeCredentialLease
    func release(_ lease: NativeCredentialLease) async
    func stream(requestId: ID, body: Data, lease: NativeCredentialLease) async throws -> AsyncThrowingStream<StreamDelta, Error>
    func stop(requestId: ID) async
}
