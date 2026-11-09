import Foundation
public enum DraftReducer {
    static func containsAnswer(_ answer:String,selection:String)->Bool {
        if answer.contains(selection){return true}
        func normalize(_ value:String)->String {
            var value=value.replacingOccurrences(of:"(?m)^\\s{0,3}#{1,6}\\s+",with:"",options:.regularExpression)
            value=value.replacingOccurrences(of:"\\[([^\\]]+)\\]\\([^)]*\\)",with:"$1",options:.regularExpression)
            value=value.replacingOccurrences(of:"(?:\\*\\*|__|`{1,3}|~~)",with:"",options:.regularExpression)
            return value.replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
        }
        let plain=normalize(selection);return !plain.isEmpty && normalize(answer).contains(plain)
    }
    public static func clearAccepted(_ submission: FrozenSubmission, draft: inout ReadingDraft) {
        if draft.promptRevision == submission.promptRevision && draft.prompt == submission.prompt { draft.prompt=""; draft.promptRevision += 1 }
        draft.externalQuotes.removeAll { item in submission.externalQuotes.contains(where:{$0.id == item.id && $0.revision == item.revision}) }
        draft.images.removeAll { item in submission.images.contains(where:{$0.draftItemId == item.id && $0.itemRevision == item.revision}) }
        if draft.assistantQuote?.id == submission.assistantQuote?.id && draft.assistantQuote?.revision == submission.assistantQuote?.revision { draft.assistantQuote=nil }
        draft.revision += 1; draft.updatedAt=now()
    }
    public static func change(_ raw: [String:JSONValue], draft: inout ReadingDraft, state: PersistedState) throws {
        guard let kind=raw["kind"]?.string else { throw AppFault("INVALID_ARGUMENT","草稿变更无效。") }
        let fields: Set<String>
        switch kind { case "prompt":fields=["kind","text"];case "removeQuote","removeImage":fields=["kind","id"];case "assistantQuote":fields=["kind","turnId","requestId","text"];case "clearAssistantQuote":fields=["kind","id"];default:throw AppFault("INVALID_ARGUMENT","草稿操作无效。") }
        guard Set(raw.keys) == fields else { throw AppFault("INVALID_ARGUMENT","草稿字段无效。") }
        switch kind {
        case "prompt":
            guard let text=raw["text"]?.string,text.utf8.count <= 2*1024*1024 else { throw AppFault("INVALID_ARGUMENT","输入过长。") };draft.prompt=text;draft.promptRevision += 1
        case "removeQuote": draft.externalQuotes.removeAll{$0.id == raw["id"]?.string}
        case "removeImage":draft.images.removeAll{$0.id == raw["id"]?.string}
        case "assistantQuote":
            guard let turnID=raw["turnId"]?.string,let reqID=raw["requestId"]?.string,let text=raw["text"]?.string,!text.isEmpty,let turn=state.turns[turnID],turn.taskId == draft.taskId,let generation=state.generations[reqID],generation.turnId == turnID,Self.containsAnswer(generation.answer,selection:text) else { throw AppFault("INVALID_ARGUMENT","引用来源不属于当前回答。") }
            draft.assistantQuote=AssistantQuote(sourceTurnId:turnID,sourceRequestId:reqID,text:text)
        case "clearAssistantQuote":if draft.assistantQuote?.id == raw["id"]?.string { draft.assistantQuote=nil }
        default: break
        }
        draft.revision += 1; draft.updatedAt=now()
    }
}
