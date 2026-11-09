import Foundation
public actor ReadingRuntime {
    var state: PersistedState
    let repository: any ReadingRepository
    let assets: any AttachmentStore
    let transport: any ModelTransport
    let catalog: ModelCatalog
    let builder: ContextBuilder
    public let bootId = newID()
    var sequence=0
    var routingEpoch=0
    var jobs: [ID:Task<Void,Never>] = [:]
    var cancellation: Set<ID> = []
    var streamBuffers: [ID:(answer:String,reasoning:String)] = [:]
    var latestSelections: [ID:(lease:ID,token:ID,quote:ID,sequence:Int)] = [:]
    var sourceSequences: [ID:Int] = [:]
    let changed: @Sendable (String) -> Void
    public init(repository: any ReadingRepository, assets: any AttachmentStore, transport: any ModelTransport, catalog: ModelCatalog, prompt: String, changed: @escaping @Sendable (String) -> Void = {_ in}) throws {
        self.repository=repository;self.assets=assets;self.transport=transport;self.catalog=catalog;builder=ContextBuilder(prompt:prompt);self.changed=changed
        var loaded=try repository.load()
        if (loaded.preferences.shortcutDefaultVersion ?? 0) < 2 {
            let binding=loaded.preferences.captureShortcut
            if (binding == nil && loaded.preferences.shortcutDefaultVersion == nil) || binding == ShortcutBinding(keyCode:0,modifiers:["shift"]) {
                loaded.preferences.captureShortcut=ShortcutBinding(keyCode:0,modifiers:["command","shift"])
            }
            loaded.preferences.shortcutDefaultVersion=2
        }
        if (loaded.preferences.panelShortcutDefaultVersion ?? 0) < 2 {
            let binding=loaded.preferences.panelShortcut
            if (binding == nil && loaded.preferences.panelShortcutDefaultVersion == nil) || binding == ShortcutBinding(keyCode:1,modifiers:["shift"]) {
                loaded.preferences.panelShortcut=ShortcutBinding(keyCode:1,modifiers:["command","shift"])
            }
            loaded.preferences.panelShortcutDefaultVersion=2
        }
        for (id,var g) in loaded.generations where g.active {
            g.status="interrupted";g.error=AppFault("NETWORK_ERROR","上次运行意外中断，未自动重发。",retryable:true);loaded.generations[id]=g
            if let restore=g.restoresRequestId { loaded.turns[g.turnId]?.displayedRequestId=restore }
        }
        for (id,var p) in loaded.preparations where p.state == "preparing" {p.state="interrupted";loaded.preparations[id]=p}
        for (id,var t) in loaded.tasks {t.activeOperationId=nil;t.activeRequestId=nil;loaded.tasks[id]=t}
        for (id,var op) in loaded.operations where op.state == "pending" { op.state="failed";op.error=AppFault("NETWORK_ERROR","上次操作中断，请检查后再操作。",retryable:true);loaded.operations[id]=op }
        if loaded.tasks.isEmpty {let t=ReadingTaskRecord(title:"阅读任务");loaded.tasks[t.id]=t;loaded.drafts[t.id]=ReadingDraft(taskId:t.id);loaded.activeTaskId=t.id}
        self.state=loaded
        try repository.save(loaded)
    }
    func commit(_ next: PersistedState, event: String = "task-changed") throws {
        var next=next
        var refs:Set<AssetReference>=[]
        for d in next.drafts.values {for i in d.images {refs.insert(AssetReference(ownerKind:"draft",ownerId:d.taskId,imageId:i.imageId))}}
        for p in next.preparations.values where p.state == "preparing" {for m in p.messages {for part in m.parts {if let id=part.imageId {refs.insert(AssetReference(ownerKind:"preparation",ownerId:p.id,imageId:id))}}}}
        for s in next.snapshots.values {for m in s.messages {for part in m.parts {if let id=part.imageId {refs.insert(AssetReference(ownerKind:"snapshot",ownerId:s.id,imageId:id))}}}}
        for t in next.turns.values {for i in t.submission.images {refs.insert(AssetReference(ownerKind:"turn",ownerId:t.id,imageId:i.imageId))}}
        next.references=refs
        try repository.save(next);state=next;sequence += 1;changed(event)
    }
    func requireTask(_ id: ID) throws -> ReadingTaskRecord {
        guard let task=state.tasks[id],task.deletedAt == nil else{throw AppFault("TASK_NOT_FOUND","阅读任务已不存在。")};return task
    }
    func checkRevision(_ expected: Int, _ current: Int) throws {guard expected == current else{throw AppFault("REVISION_CONFLICT","内容刚刚更新，请重试；现有资料已保留。",retryable:true,currentRevision:current)}}
    public func route() -> (ID?,Int) { (state.activeTaskId,routingEpoch) }
    public func preferences() -> PreferencesRecord {state.preferences}
    public func snapshot() -> PersistedState {state}
    public func view(taskId: ID? = nil, cursor: Int? = nil) throws -> RuntimeView {
        let id=taskId ?? state.activeTaskId
        var taskView:TaskView?
        if let id,let task=state.tasks[id],task.deletedAt == nil,let draft=state.drafts[id] {
            let all=state.turns.values.filter{$0.taskId==id}.sorted{$0.order < $1.order}
            let end=min(cursor ?? all.count,all.count),start=max(0,end-50)
            let turns=all[start..<end].compactMap{t -> TurnView? in
                guard let g=state.generations[t.displayedRequestId] else{return nil}
                return TurnView(id:t.id,requestId:g.id,prompt:t.submission.prompt,externalQuotes:t.submission.externalQuotes.map(ExternalQuoteView.init),images:t.submission.images.compactMap{state.assets[$0.imageId].map{ImageView($0)}},assistantQuote:t.submission.assistantQuote,answer:g.answer,reasoning:g.reasoning,status:g.status,error:g.error ?? state.generations.values.filter({$0.turnId==t.id && $0.restoresRequestId==g.id && !$0.active && $0.status != "complete"}).max(by:{$0.updatedAt < $1.updatedAt}).map({AppFault($0.error?.code ?? "CANCELLED","重新生成未完成，已保留原回答。"+($0.error?.message ?? ""),retryable:true)}),canRegenerate:all.last?.id==t.id && g.status=="complete" && task.activeOperationId==nil)
            }
            taskView=TaskView(task:task,draft:DraftView(draft,assets:state.assets),turns:turns,nextCursor:start>0 ? start:nil)
        }
        return RuntimeView(bootId:bootId,sequence:sequence,activeTaskId:state.activeTaskId,tasks:state.tasks.values.filter{$0.deletedAt==nil}.sorted{$0.updatedAt > $1.updatedAt},currentTask:taskView,preferences:state.preferences,models:catalog.models)
    }
    public func operation(_ id: ID) -> OperationRecord? {state.operations[id]}
    public func reserveOperation(_ id: ID, command: String, digest: String) throws -> Bool {
        if let op=state.operations[id] {guard op.command==command,op.digest==digest else{throw AppFault("INVALID_ARGUMENT","操作标识已用于其他操作。")};return false}
        var next=state;next.operations[id]=OperationRecord(id:id,command:command,digest:digest);try commit(next);return true
    }
    public func finishOperation(_ id: ID, resultId: ID? = nil, error: AppFault? = nil) throws {
        guard var op=state.operations[id] else{return};op.state=error == nil ? "succeeded":"failed";op.resultId=resultId;op.error=error;var next=state;next.operations[id]=op;try commit(next)
    }
    public func createTask(title: String) throws -> ID {
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.count<=120 else{throw AppFault("INVALID_ARGUMENT","任务名称须为 1–120 字。")}
        var next=state;let task=ReadingTaskRecord(title:title);next.tasks[task.id]=task;next.drafts[task.id]=ReadingDraft(taskId:task.id);next.activeTaskId=task.id;routingEpoch += 1;try commit(next);return task.id
    }
    public func switchTask(_ id: ID) throws { _=try requireTask(id);var next=state;next.activeTaskId=id;routingEpoch += 1;try commit(next) }
    public func renameTask(_ id: ID, title: String, expected: Int) throws {
        var task=try requireTask(id);try checkRevision(expected,task.revision)
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.count<=120 else{throw AppFault("INVALID_ARGUMENT","任务名称须为 1–120 字。")}
        task.title=title;task.revision += 1;task.updatedAt=now();var next=state;next.tasks[id]=task;try commit(next)
    }
    public func changeDraft(taskId: ID, expected: Int, change: [String:JSONValue]) throws {
        _=try requireTask(taskId);guard var draft=state.drafts[taskId] else{throw AppFault.storage};try checkRevision(expected,draft.revision)
        try DraftReducer.change(change,draft:&draft,state:state);var next=state;next.drafts[taskId]=draft;try commit(next,event:"draft-changed")
    }
    public func ingestSelection(_ event: SelectionEvent) throws -> ID? {
        _=try requireTask(event.taskId)
        guard event.sourceSequence > (sourceSequences[event.sourceLeaseId] ?? -1) else{return nil}
        sourceSequences[event.sourceLeaseId]=event.sourceSequence
        guard var draft=state.drafts[event.taskId] else{throw AppFault.storage}
        switch event.outcome {
        case .unavailable: return nil
        case .selected(let token,let source,let text):
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,text.utf8.count <= 2*1024*1024 else{return nil}
            if state.preferences.quoteMode=="accumulate", let identity=source.documentIdentity,let existing=draft.externalQuotes.first(where:{$0.source.documentIdentity==identity && $0.source.appBundleId==source.appBundleId && $0.text==text}) {return existing.id}
            let q=ExternalQuote(source:source,text:text)
            if state.preferences.quoteMode=="latest" {draft.externalQuotes=[q]} else {draft.externalQuotes.append(q)}
            latestSelections[event.taskId]=(event.sourceLeaseId,token,q.id,event.sourceSequence)
        case .cleared(let token,let expected):
            guard state.preferences.quoteMode=="latest",let latest=latestSelections[event.taskId],latest.lease==event.sourceLeaseId,latest.token==token,latest.quote==expected else{return nil}
            draft.externalQuotes.removeAll{$0.id==expected};latestSelections[event.taskId]=nil
        }
        draft.revision += 1;draft.updatedAt=now();var next=state;next.drafts[event.taskId]=draft;try commit(next,event:"draft-changed")
        return latestSelections[event.taskId]?.quote
    }
    public func attachCapture(_ asset: ImageAsset, taskId: ID) throws {
        _=try requireTask(taskId);guard var draft=state.drafts[taskId] else{throw AppFault.storage}
        guard draft.images.count<9 else{throw AppFault("IMAGE_COUNT_EXCEEDED","每次最多 9 张截图，请先发送或移除已有截图。")}
        guard asset.byteLength<=10*1024*1024 else{throw AppFault("IMAGE_TOO_LARGE","单张截图不能超过 10 MiB。")}
        var next=state;next.assets[asset.id]=asset;draft.images.append(DraftImage(imageId:asset.id));draft.revision += 1;next.drafts[taskId]=draft;try commit(next,event:"draft-changed")
    }
    public func asset(_ id: ID) -> ImageAsset? {guard state.references.contains(where:{$0.imageId==id}) else{return nil};return state.assets[id]}
    public func savePreferences(expected: Int, patch: [String:JSONValue]) throws {
        try checkRevision(expected,state.preferences.revision);var p=state.preferences
        for (key,value) in patch {
            switch key {
            case "modelId":guard let v=value.string else{throw AppFault("INVALID_ARGUMENT","模型无效。")};_=try catalog.model(v);p.modelId=v
            case "thinkingEnabled":guard let v=value.bool else{throw AppFault("INVALID_ARGUMENT","思考设置无效。")};p.thinkingEnabled=v
            case "reasoningEffort":guard let v=value.string,["low","high","max"].contains(v) else{throw AppFault("INVALID_ARGUMENT","强度无效。")};p.reasoningEffort=v
            case "theme":guard let v=value.string,["system","light","dark"].contains(v) else{throw AppFault("INVALID_ARGUMENT","主题无效。")};p.theme=v
            case "fontSize":guard let v=value.int,[12,13,14,16].contains(v) else{throw AppFault("INVALID_ARGUMENT","字号无效。")};p.fontSize=v
            case "quoteMode":guard let v=value.string,["accumulate","latest"].contains(v) else{throw AppFault("INVALID_ARGUMENT","引用模式无效。")};p.quoteMode=v
            default:throw AppFault("INVALID_ARGUMENT","偏好字段无效。")
            }
        }
        p.revision += 1;p.updatedAt=now();var next=state;next.preferences=p;try commit(next,event:"preferences-changed")
    }
    public func setShortcut(_ binding: ShortcutBinding?,kind:String="capture") throws {var next=state;if kind=="panel"{next.preferences.panelShortcut=binding}else{next.preferences.captureShortcut=binding};next.preferences.revision += 1;try commit(next,event:"preferences-changed")}
    public func acceptDisclosure() throws {var next=state;next.preferences.disclosureVersion="v1";next.preferences.revision += 1;try commit(next,event:"preferences-changed")}
    public func enableSelection(_ enabled: Bool, expected: Int) throws {
        try checkRevision(expected,state.preferences.revision)
        guard !enabled || state.preferences.disclosureVersion=="v1" else{throw AppFault("CONSENT_REQUIRED","请先确认本机采集说明。")}
        var next=state;next.preferences.autoSelectionEnabled=enabled;next.preferences.revision += 1;try commit(next,event:"preferences-changed")
    }
    public func companionVisible(_ visible: Bool) throws {var next=state;next.preferences.companionVisible=visible;try commit(next,event:"preferences-changed")}
    public func restoreSubmission(taskId: ID, requestId: ID, expected: Int) throws {
        _=try requireTask(taskId);guard let g=state.generations[requestId],g.taskId==taskId,let s=state.snapshots[g.snapshotId],var draft=state.drafts[taskId] else{throw AppFault("INVALID_ARGUMENT","原问题不可用。")}
        try checkRevision(expected,draft.revision)
        let additions=s.submission.images.filter{image in !draft.images.contains(where:{$0.imageId==image.imageId})}
        guard draft.images.count+additions.count<=9 else{throw AppFault("IMAGE_COUNT_EXCEEDED","恢复后将超过 9 张图片，未修改草稿。")}
        draft.prompt=s.submission.prompt;draft.promptRevision += 1
        for q in s.submission.externalQuotes where !draft.externalQuotes.contains(where:{$0.id==q.id}) {draft.externalQuotes.append(q)}
        for i in additions {draft.images.append(DraftImage(imageId:i.imageId))}
        draft.assistantQuote=s.submission.assistantQuote;draft.revision += 1;var next=state;next.drafts[taskId]=draft;try commit(next,event:"draft-changed")
    }
    public func deleteTask(_ id: ID, expected: Int) async throws {
        let task=try requireTask(id);try checkRevision(expected,task.revision)
        var next=state
        if let op=task.activeOperationId {cancellation.insert(op)}
        let requests=next.generations.values.filter{$0.taskId==id}.map(\.id)
        next.tasks.removeValue(forKey:id);next.drafts.removeValue(forKey:id)
        next.turns=next.turns.filter{$0.value.taskId != id};next.generations=next.generations.filter{$0.value.taskId != id};next.snapshots=next.snapshots.filter{$0.value.taskId != id};next.preparations=next.preparations.filter{$0.value.taskId != id};latestSelections[id]=nil
        if next.activeTaskId==id {next.activeTaskId=next.tasks.values.first?.id;routingEpoch += 1}
        if next.tasks.isEmpty {let t=ReadingTaskRecord(title:"阅读任务");next.tasks[t.id]=t;next.drafts[t.id]=ReadingDraft(taskId:t.id);next.activeTaskId=t.id}
        try commit(next)
        for req in requests {jobs[req]?.cancel();await transport.stop(requestId:req);jobs[req]=nil}
        try garbageCollect()
    }
    public func clearAllTasks() async throws {for t in Array(state.tasks.values){try await deleteTask(t.id,expected:t.revision)}}
    public func garbageCollect() throws {
        try commit(state) // Recompute references after interrupted preparations before deleting files.
        let keeping=Set(state.references.map(\.imageId));try assets.removeUnreferenced(keeping:keeping)
        var next=state;next.assets=next.assets.filter{keeping.contains($0.key)};try commit(next)
    }
    public func shutdown() async {
        for (id,g) in state.generations where g.active {try? await stop(.request(taskId:g.taskId,requestId:id))}
        for p in state.preparations.values where p.state=="preparing" {cancellation.insert(p.operationId)}
    }
}
