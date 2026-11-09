import Foundation
public struct ExternalQuoteView: Codable, Sendable { public var id: ID; public var revision: Int; public var source: SourceView; public var text: String; public init(_ q: ExternalQuote) { id=q.id;revision=q.revision;source=SourceView(q.source);text=q.text } }
public struct ImageView: Codable, Sendable {
    public var id: ID; public var draftItemId: ID?; public var source: SourceView; public var width: Int; public var height: Int; public var byteLength: Int; public var thumbnailURL: String; public var previewURL: String
    public init(_ asset: ImageAsset, draftItemId: ID? = nil) { id=asset.id;self.draftItemId=draftItemId;source=SourceView(asset.source);width=asset.width;height=asset.height;byteLength=asset.byteLength;thumbnailURL="anysidebar://app/asset/\(asset.id)/thumbnail";previewURL="anysidebar://app/asset/\(asset.id)/preview" }
}
public struct DraftView: Codable, Sendable {
    public var taskId: ID;public var revision: Int;public var promptRevision: Int;public var prompt: String
    public var externalQuotes: [ExternalQuoteView];public var images: [ImageView];public var assistantQuote: AssistantQuote?
    public init(_ draft: ReadingDraft, assets: [ID:ImageAsset]) { taskId=draft.taskId;revision=draft.revision;promptRevision=draft.promptRevision;prompt=draft.prompt;externalQuotes=draft.externalQuotes.map(ExternalQuoteView.init);images=draft.images.compactMap{item in assets[item.imageId].map{ImageView($0,draftItemId:item.id)}};assistantQuote=draft.assistantQuote }
}
public struct TurnView: Codable, Sendable {
    public var id: ID; public var requestId: ID; public var prompt: String; public var externalQuotes: [ExternalQuoteView];public var images: [ImageView];public var assistantQuote: AssistantQuote?
    public var answer: String;public var reasoning: String;public var status: String;public var error: AppFault?;public var canRegenerate: Bool
}
public struct TaskView: Codable, Sendable {
    public var task: ReadingTaskRecord;public var draft: DraftView;public var turns: [TurnView];public var nextCursor: Int?
}
public struct RuntimeView: Codable, Sendable {
    public var bootId: ID; public var sequence: Int; public var activeTaskId: ID?; public var tasks: [ReadingTaskRecord];public var currentTask: TaskView?;public var preferences: PreferencesRecord;public var models: [ModelCapabilities]
}
