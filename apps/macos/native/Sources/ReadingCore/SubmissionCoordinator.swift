import Foundation
extension ReadingRuntime {
    public func send(taskId: ID, expectedDraft: Int, expectedPreferences: Int, operationId: ID) async throws -> ID {
        let task=try requireTask(taskId)
        if let old=state.preparations.values.first(where:{$0.operationId==operationId}),let id=old.acceptedRequestId {return id}
        guard task.activeOperationId==nil else{throw AppFault("REQUEST_BUSY","此任务已有回答正在生成。")}
        guard let draft=state.drafts[taskId] else{throw AppFault.storage}
        try checkRevision(expectedDraft,draft.revision);try checkRevision(expectedPreferences,state.preferences.revision)
        guard !draft.prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !draft.images.isEmpty else{throw AppFault("INVALID_ARGUMENT","请输入问题或添加截图。") }
        let sub=try FrozenSubmission(draft:draft,assets:state.assets),options=try catalog.resolve(state.preferences)
        let preparation=PreparationRecord(operationId:operationId,taskId:taskId,kind:"send",submission:sub,messages:builder.build(sub,state:state),options:options)
        var next=state;next.preparations[preparation.id]=preparation;next.tasks[taskId]?.activeOperationId=operationId;try commit(next)
        return try await prepareAndAccept(preparation)
    }
    public func replay(taskId: ID, turnId: ID, requestId: ID, kind: String, expectedPreferences: Int, operationId: ID) async throws -> ID {
        let task=try requireTask(taskId)
        guard task.activeOperationId==nil else{throw AppFault("REQUEST_BUSY","此任务已有回答正在生成。")}
        try checkRevision(expectedPreferences,state.preferences.revision)
        guard let turn=state.turns[turnId],turn.taskId==taskId,turn.displayedRequestId==requestId,let generation=state.generations[requestId],let old=state.snapshots[generation.snapshotId] else{throw AppFault("INVALID_ARGUMENT","原请求不可用。")}
        if kind=="regenerate" {
            guard generation.status=="complete",state.turns.values.filter({$0.taskId==taskId}).max(by:{$0.order<$1.order})?.id==turnId else{throw AppFault("INVALID_ARGUMENT","只能重新生成最后一条完整回答。")}
        } else { guard ["failed","stopped","interrupted","truncated"].contains(generation.status) else{throw AppFault("INVALID_ARGUMENT","该请求无需重试。")} }
        let preparation=PreparationRecord(operationId:operationId,taskId:taskId,kind:kind,sourceRequestId:requestId,submission:old.submission,messages:old.messages,options:try catalog.resolve(state.preferences))
        var next=state;next.preparations[preparation.id]=preparation;next.tasks[taskId]?.activeOperationId=operationId;try commit(next)
        return try await prepareAndAccept(preparation)
    }
    func prepareAndAccept(_ preparation: PreparationRecord) async throws -> ID {
        var lease:NativeCredentialLease?
        do {
            // Native actor, not MainActor. Actual image bytes are validated before credentials or draft clearing.
            let encoded=try BudgetValidator.encode(messages:preparation.messages,submission:preparation.submission,options:preparation.options,model:catalog.model(preparation.options.modelId),assets:state.assets,store:assets)
            lease=try await transport.acquire(preparationId:preparation.id)
            guard !cancellation.contains(preparation.operationId),state.tasks[preparation.taskId]?.activeOperationId==preparation.operationId else{throw AppFault("CANCELLED","已取消发送。")}
            let requestID=newID()
            var next=state
            let turnID:ID
            if let original=preparation.sourceRequestId,let old=state.generations[original] {turnID=old.turnId}
            else {
                turnID=newID()
                var turn=TurnRecord(taskId:preparation.taskId,order:next.tasks[preparation.taskId]!.nextTurnOrder,submission:preparation.submission,displayedRequestId:requestID)
                turn.id=turnID;next.turns[turnID]=turn;next.tasks[preparation.taskId]?.nextTurnOrder += 1
            }
            let snapshot=RequestSnapshot(taskId:preparation.taskId,turnId:turnID,submission:preparation.submission,messages:preparation.messages,capabilitiesVersion:catalog.version,options:preparation.options,budget:encoded.budget)
            let generation=GenerationRecord(id:requestID,taskId:preparation.taskId,turnId:turnID,snapshotId:snapshot.id,kind:preparation.kind,restoresRequestId:preparation.kind=="regenerate" ? preparation.sourceRequestId:nil)
            next.snapshots[snapshot.id]=snapshot;next.generations[requestID]=generation;next.turns[turnID]?.displayedRequestId=requestID
            next.tasks[preparation.taskId]?.activeRequestId=requestID;next.tasks[preparation.taskId]?.updatedAt=now()
            next.preparations[preparation.id]?.state="accepted";next.preparations[preparation.id]?.acceptedRequestId=requestID
            if preparation.kind=="send",var draft=next.drafts[preparation.taskId] {DraftReducer.clearAccepted(preparation.submission,draft:&draft);next.drafts[preparation.taskId]=draft}
            try commit(next,event:"generation-changed")
            let acceptedLease=lease!
            jobs[requestID]=Task { await self.run(requestID,body:encoded.body,lease:acceptedLease) }
            return requestID
        } catch {
            if let lease {await transport.release(lease)}
            let fault=(error as? AppFault) ?? AppFault("NETWORK_ERROR","请求准备失败，输入与资料已保留。",retryable:true)
            if state.tasks[preparation.taskId]?.activeOperationId==preparation.operationId {
                var next=state;next.tasks[preparation.taskId]?.activeOperationId=nil;next.tasks[preparation.taskId]?.activeRequestId=nil
                next.preparations[preparation.id]?.state=fault.code=="CANCELLED" ? "cancelled":"rejected";next.preparations[preparation.id]?.error=fault
                try commit(next)
            }
            throw fault
        }
    }
    func run(_ id: ID, body: Data, lease: NativeCredentialLease) async {
        let flusher=Task {
            while !Task.isCancelled {
                do {try await Task.sleep(for:.milliseconds(200));try self.flush(id)}
                catch {if !Task.isCancelled{await self.transport.stop(requestId:id);self.jobs[id]?.cancel();self.changed("storage-failed")};return}
            }
        }
        defer { flusher.cancel();jobs[id]=nil;streamBuffers[id]=nil }
        do {
            guard state.generations[id]?.active==true else{await transport.release(lease);return}
            var next=state;next.generations[id]?.status="connecting";try commit(next,event:"generation-changed")
            let stream=try await transport.stream(requestId:id,body:body,lease:lease)
            var finish:String?
            for try await delta in stream {
                try Task.checkCancellation()
                guard state.generations[id]?.active==true else{break}
                var buffer=streamBuffers[id] ?? ("","")
                buffer.answer += delta.answer;buffer.reasoning += delta.reasoning;streamBuffers[id]=buffer
                if let reason=delta.finishReason {finish=reason}
                if buffer.answer.utf8.count+buffer.reasoning.utf8.count>=8192 || finish != nil {try flush(id)}
            }
            try flush(id)
            guard let finish else{throw AppFault("NETWORK_ERROR","连接提前结束，已保存收到的内容。",retryable:true)}
            try complete(id,status:finish=="stop" ? "complete":"truncated",finish:finish,error:finish=="stop" ? nil:AppFault("API_BAD_RESPONSE","回答未完整结束，可以手动重试。",retryable:true))
        } catch {
            let cancelled=Task.isCancelled || error is CancellationError
            do {
                try flush(id)
                let fault=cancelled ? AppFault("CANCELLED","已停止，已接收内容保留。") : ((error as? AppFault) ?? AppFault("NETWORK_ERROR","连接失败或超时，已保存收到的内容。",retryable:true))
                try complete(id,status:cancelled ? "stopped":"failed",error:fault)
            } catch { await transport.stop(requestId:id);changed("storage-failed") }
        }
        await transport.release(lease)
    }
    func flush(_ id:ID) throws {
        guard let buffer=streamBuffers[id] else{return}
        try append(id,answer:buffer.answer,reasoning:buffer.reasoning);streamBuffers[id]=nil
    }
    func append(_ id: ID, answer: String, reasoning: String) throws {
        guard var g=state.generations[id],g.active else{return}
        guard !answer.isEmpty || !reasoning.isEmpty else{return}
        g.answer += answer;g.reasoning += reasoning;g.lastDeltaSequence += 1;g.status="streaming";g.updatedAt=now();var next=state;next.generations[id]=g
        try commit(next,event:"generation-changed")
    }
    func complete(_ id: ID, status: String, finish: String? = nil, error: AppFault? = nil) throws {
        guard var g=state.generations[id],g.active else{return}
        g.status=status;g.finishReason=finish;g.error=error;g.updatedAt=now();var next=state;next.generations[id]=g
        if status=="complete" {next.turns[g.turnId]?.completedRequestId=id}
        else if let restore=g.restoresRequestId {next.turns[g.turnId]?.displayedRequestId=restore}
        if next.tasks[g.taskId]?.activeRequestId==id {next.tasks[g.taskId]?.activeRequestId=nil;next.tasks[g.taskId]?.activeOperationId=nil}
        try commit(next,event:"generation-changed")
    }
    public func stop(_ target: StopTarget) async throws {
        let taskID:ID,requestID:ID?
        switch target {
        case .request(let tid,let rid): taskID=tid;requestID=rid
        case .operation(let tid,let op):
            taskID=tid;cancellation.insert(op)
            guard let prep=state.preparations.values.first(where:{$0.operationId==op && $0.taskId==tid}) else{return}
            requestID=prep.acceptedRequestId
            if requestID==nil,prep.state=="preparing" {
                var next=state;next.preparations[prep.id]?.state="cancelled"
                if next.tasks[tid]?.activeOperationId==op {next.tasks[tid]?.activeOperationId=nil};try commit(next)
            }
        }
        if let id=requestID,let g=state.generations[id],g.taskId==taskID,g.active {
            try flush(id);jobs[id]?.cancel();await transport.stop(requestId:id);try complete(id,status:"stopped",error:AppFault("CANCELLED","已停止，已接收内容保留。"))
        }
    }
}
