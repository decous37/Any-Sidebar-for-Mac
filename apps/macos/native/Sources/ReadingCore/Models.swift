import Foundation

public typealias ID = String
public func newID() -> ID { UUID().uuidString.lowercased() }
public func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
public func validID(_ value: String) -> Bool { UUID(uuidString: value) != nil }
public struct AppFault: Error, Codable, Sendable, Equatable, LocalizedError {
    public var code: String
    public var message: String
    public var retryable: Bool
    public var currentRevision: Int?
    public init(_ code: String, _ message: String, retryable: Bool = false, currentRevision: Int? = nil) {
        self.code = code; self.message = message; self.retryable = retryable; self.currentRevision = currentRevision
    }
    public var errorDescription: String? { message }
    public static let storage = AppFault("STORAGE_FAILED", "本机保存失败，请保留当前数据并重试。", retryable: true)
}
public struct SourceInfo: Codable, Sendable, Equatable {
    public var id = newID()
    public var kind: String
    public var appBundleId: String?
    public var appName: String?
    public var documentTitle: String?
    public var documentIdentity: String?
    public var pageLabel: String?
    public var capturedAt = now()
    public init(kind: String, appBundleId: String? = nil, appName: String? = nil, documentTitle: String? = nil, documentIdentity: String? = nil, pageLabel: String? = nil) {
        self.kind = kind; self.appBundleId = appBundleId; self.appName = appName; self.documentTitle = documentTitle; self.documentIdentity = documentIdentity; self.pageLabel = pageLabel
    }
}
public struct SourceView: Codable, Sendable, Equatable {
    public var id: ID; public var kind: String; public var appBundleId: String?; public var appName: String?
    public var documentTitle: String?; public var pageLabel: String?; public var capturedAt: Int64
    public init(_ s: SourceInfo) { id=s.id; kind=s.kind; appBundleId=s.appBundleId; appName=s.appName; documentTitle=s.documentTitle; pageLabel=s.pageLabel; capturedAt=s.capturedAt }
}
public struct ExternalQuote: Codable, Sendable, Equatable {
    public var id = newID(); public var revision = 0; public var source: SourceInfo; public var text: String; public var selectedAt = now()
    public init(source: SourceInfo, text: String) { self.source=source; self.text=text }
}
public struct AssistantQuote: Codable, Sendable, Equatable {
    public var id = newID(); public var revision = 0; public var sourceTurnId: ID; public var sourceRequestId: ID; public var text: String; public var selectedAt = now()
    public init(sourceTurnId: ID, sourceRequestId: ID, text: String) { self.sourceTurnId=sourceTurnId; self.sourceRequestId=sourceRequestId; self.text=text }
}
public struct DraftImage: Codable, Sendable, Equatable {
    public var id = newID(); public var revision = 0; public var imageId: ID; public var addedAt = now()
    public init(imageId: ID) { self.imageId=imageId }
}
public struct ReadingDraft: Codable, Sendable, Equatable {
    public var taskId: ID; public var revision = 0; public var promptRevision = 0; public var prompt = ""
    public var externalQuotes: [ExternalQuote] = []; public var images: [DraftImage] = []; public var assistantQuote: AssistantQuote?
    public var updatedAt = now()
    public init(taskId: ID) { self.taskId=taskId }
}
public struct ReadingTaskRecord: Codable, Sendable, Equatable {
    public var id = newID(); public var title: String; public var revision = 0; public var nextTurnOrder = 0
    public var activeOperationId: ID?; public var activeRequestId: ID?
    public var createdAt = now(); public var updatedAt = now(); public var deletedAt: Int64?
    public init(title: String) { self.title=title }
}
public struct ImageAsset: Codable, Sendable, Equatable {
    public var id: ID; public var revision = 0; public var source: SourceInfo; public var mediaType = "image/png"
    public var width: Int; public var height: Int; public var byteLength: Int; public var sha256: String
    public var storageKey: String; public var thumbnailKey: String?; public var state = "ready"; public var createdAt = now()
    public init(id: ID, source: SourceInfo, width: Int, height: Int, byteLength: Int, sha256: String, storageKey: String, thumbnailKey: String?) {
        self.id=id; self.source=source; self.width=width; self.height=height; self.byteLength=byteLength; self.sha256=sha256; self.storageKey=storageKey; self.thumbnailKey=thumbnailKey
    }
}
public struct AssetReference: Codable, Sendable, Equatable, Hashable {
    public var ownerKind: String; public var ownerId: ID; public var imageId: ID
    public init(ownerKind: String, ownerId: ID, imageId: ID) { self.ownerKind=ownerKind; self.ownerId=ownerId; self.imageId=imageId }
}
public struct FrozenImage: Codable, Sendable, Equatable {
    public var draftItemId: ID; public var itemRevision: Int; public var imageId: ID; public var sha256: String
    public init(draftItemId: ID, itemRevision: Int, imageId: ID, sha256: String) { self.draftItemId=draftItemId; self.itemRevision=itemRevision; self.imageId=imageId; self.sha256=sha256 }
}
public struct FrozenSubmission: Codable, Sendable, Equatable {
    public var taskId: ID; public var draftRevision: Int; public var promptRevision: Int; public var prompt: String
    public var externalQuotes: [ExternalQuote]; public var images: [FrozenImage]; public var assistantQuote: AssistantQuote?
    public init(draft: ReadingDraft, assets: [ID:ImageAsset]) throws {
        taskId=draft.taskId; draftRevision=draft.revision; promptRevision=draft.promptRevision; prompt=draft.prompt
        externalQuotes=draft.externalQuotes; assistantQuote=draft.assistantQuote
        images = try draft.images.map { item in
            guard let asset=assets[item.imageId], asset.state == "ready" else { throw AppFault("IMAGE_MISSING", "截图不可用，请移除后重新截取。") }
            return FrozenImage(draftItemId:item.id,itemRevision:item.revision,imageId:asset.id,sha256:asset.sha256)
        }
    }
}
public struct MessagePart: Codable, Sendable, Equatable {
    public var type: String; public var text: String?; public var imageId: ID?; public var sha256: String?; public var detail: String?
    public static func text(_ text: String) -> Self { Self(type:"text",text:text) }
    public static func image(_ image: FrozenImage) -> Self { Self(type:"image",imageId:image.imageId,sha256:image.sha256,detail:"original") }
}
public struct FrozenMessage: Codable, Sendable, Equatable {
    public var role: String; public var parts: [MessagePart]
    public init(role: String, parts: [MessagePart]) { self.role=role; self.parts=parts }
    public static func text(_ role: String, _ text: String) -> Self { Self(role:role,parts:[.text(text)]) }
}
public struct ResolvedOptions: Codable, Sendable, Equatable {
    public var providerId = "deepseek"; public var modelId: String; public var thinkingEnabled: Bool; public var reasoningEffort: String?; public var maxOutputTokens: Int
    public init(modelId: String, thinkingEnabled: Bool, reasoningEffort: String?, maxOutputTokens: Int) { self.modelId=modelId; self.thinkingEnabled=thinkingEnabled; self.reasoningEffort=reasoningEffort; self.maxOutputTokens=maxOutputTokens }
}
public struct BudgetReport: Codable, Sendable, Equatable {
    public var newImageCount: Int; public var requestImageParts: Int; public var encodedBodyBytes: Int
    public var textTokenUpperBound: Int; public var imageTokenUpperBound: Int; public var reservedEnvelopeTokens: Int
    public var reservedOutputTokens: Int; public var modelContextTokens: Int; public var allowed: Bool
    public var violations: [String]; public var method = "desktop-utf8-image-upper-bound-v1"
}
public struct PreparationRecord: Codable, Sendable, Equatable {
    public var id = newID(); public var operationId: ID; public var taskId: ID; public var kind: String; public var sourceRequestId: ID?
    public var submission: FrozenSubmission; public var messages: [FrozenMessage]; public var options: ResolvedOptions
    public var state = "preparing"; public var acceptedRequestId: ID?; public var error: AppFault?
    public var createdAt = now(); public var updatedAt = now()
}
public struct RequestSnapshot: Codable, Sendable, Equatable {
    public var id = newID(); public var taskId: ID; public var turnId: ID; public var submission: FrozenSubmission
    public var messages: [FrozenMessage]; public var promptVersion = "desktop-reading-v1"; public var capabilitiesVersion: String
    public var options: ResolvedOptions; public var budget: BudgetReport; public var createdAt = now()
}
public struct TurnRecord: Codable, Sendable, Equatable {
    public var id = newID(); public var taskId: ID; public var order: Int; public var submission: FrozenSubmission
    public var displayedRequestId: ID; public var completedRequestId: ID?; public var createdAt = now()
}
public struct GenerationRecord: Codable, Sendable, Equatable {
    public var id: ID; public var taskId: ID; public var turnId: ID; public var snapshotId: ID; public var kind: String; public var restoresRequestId: ID?
    public var status = "prepared"; public var answer = ""; public var reasoning = ""; public var lastDeltaSequence = 0
    public var finishReason: String?; public var error: AppFault?; public var createdAt = now(); public var updatedAt = now()
    public var active: Bool { ["prepared","connecting","streaming"].contains(status) }
}
public struct ShortcutBinding: Codable, Sendable, Equatable {
    public var keyCode: Int; public var modifiers: [String]
    public init(keyCode: Int, modifiers: [String]) { self.keyCode=keyCode; self.modifiers=modifiers }
}
public struct PreferencesRecord: Codable, Sendable, Equatable {
    public var revision = 0; public var modelId = "deepseek-flash"; public var thinkingEnabled = true; public var reasoningEffort = "high"
    public var theme = "system"; public var fontSize = 13; public var quoteMode = "latest"; public var autoSelectionEnabled = false
    public var captureShortcut: ShortcutBinding? = ShortcutBinding(keyCode:0,modifiers:["command","shift"]); public var shortcutDefaultVersion:Int? = 2; public var panelShortcut:ShortcutBinding? = ShortcutBinding(keyCode:1,modifiers:["command","shift"]); public var panelShortcutDefaultVersion:Int? = 2; public var disclosureVersion: String?; public var companionVisible = true; public var updatedAt = now()
    public init() {}
}
public struct OperationRecord: Codable, Sendable, Equatable {
    public var id: ID; public var command: String; public var digest: String; public var state: String; public var resultId: ID?; public var error: AppFault?
    public init(id: ID, command: String, digest: String, state: String = "pending", resultId: ID? = nil, error: AppFault? = nil) { self.id=id; self.command=command; self.digest=digest; self.state=state; self.resultId=resultId; self.error=error }
}
public struct NativeCredentialLease: Sendable, Equatable {
    public let id: ID; public let preparationId: ID
    public init(id: ID, preparationId: ID) { self.id=id; self.preparationId=preparationId }
}
