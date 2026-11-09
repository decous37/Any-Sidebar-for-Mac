import Foundation
import Testing
@testable import ReadingCore
final class MemoryRepository:ReadingRepository,@unchecked Sendable {
    let lock=NSLock();var state=PersistedState()
    func load()->PersistedState {lock.withLock{state}}
    func save(_ value:PersistedState){lock.withLock{state=value}}
}
actor FakeTransport:ModelTransport {
    var denied=false,starts=0,failNext=false,slow=false
    func deny(){denied=true}
    func fail(){failNext=true}
    func setSlow(){slow=true}
    func acquire(preparationId:ID) throws -> NativeCredentialLease {if denied{throw AppFault("CREDENTIAL_REQUIRED","请填写 Key")};return NativeCredentialLease(id:newID(),preparationId:preparationId)}
    func release(_ lease:NativeCredentialLease){}
    func stream(requestId:ID,body:Data,lease:NativeCredentialLease)->AsyncThrowingStream<StreamDelta,Error>{
        starts += 1;let fail=failNext,slow=self.slow;failNext=false
        return AsyncThrowingStream{c in
            let job=Task{
                if slow{try? await Task.sleep(for:.milliseconds(350))}
                c.yield(StreamDelta(answer:"已保存的模拟回答"))
                if fail{c.finish(throwing:AppFault("NETWORK_ERROR","模拟断流"))}
                else{c.yield(StreamDelta(finishReason:"stop"));c.finish()}
            };c.onTermination={_ in job.cancel()}
        }
    }
    func stop(requestId:ID){}
}
@Suite struct RuntimeTests {
    func make() throws -> (ReadingRuntime,FakeTransport,MemoryRepository) {
        let transport=FakeTransport(),repository=MemoryRepository()
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["ANY_SIDEBAR_CONTRACTS"]!)
        return (try ReadingRuntime(repository:repository,assets:MemoryAssets(bytes:Data()),transport:transport,catalog:ModelCatalog(data:Data(contentsOf:root.appendingPathComponent("model-capabilities.json"))),prompt:"阅读助手"),transport,repository)
    }
    func wait(_ runtime:ReadingRuntime) async throws {
        for _ in 0..<100 {if try await runtime.view().currentTask?.task.activeOperationId==nil{return};try await Task.sleep(for:.milliseconds(10))}
        Issue.record("模拟请求没有结束")
    }
    func prompt(_ runtime:ReadingRuntime,_ text:String="问题") async throws -> (ID,Int,Int){let v=try await runtime.view(),t=v.currentTask!;try await runtime.changeDraft(taskId:t.task.id,expected:t.draft.revision,change:["kind":.string("prompt"),"text":.string(text)]);return(t.task.id,t.draft.revision+1,v.preferences.revision)}
    @Test func defaultShortcutAndExplicitClearSurviveRestart() async throws {
        let(r,t,repo)=try make()
        #expect(await r.preferences().quoteMode=="latest")
        #expect(await r.preferences().captureShortcut==ShortcutBinding(keyCode:0,modifiers:["command","shift"]))
        #expect(await r.preferences().panelShortcut==ShortcutBinding(keyCode:1,modifiers:["command","shift"]))
        try await r.setShortcut(nil,kind:"panel")
        #expect(await r.preferences().captureShortcut==ShortcutBinding(keyCode:0,modifiers:["command","shift"]))
        try await r.setShortcut(nil)
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["ANY_SIDEBAR_CONTRACTS"]!)
        let reopened=try ReadingRuntime(repository:repo,assets:MemoryAssets(bytes:Data()),transport:t,catalog:ModelCatalog(data:Data(contentsOf:root.appendingPathComponent("model-capabilities.json"))),prompt:"角色")
        #expect(await reopened.preferences().captureShortcut==nil)
        #expect(await reopened.preferences().panelShortcut==nil)
    }
    @Test func previousDefaultsUpgradeButCustomAndClearedBindingsRemain() async throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["ANY_SIDEBAR_CONTRACTS"]!)
        let catalog=try ModelCatalog(data:Data(contentsOf:root.appendingPathComponent("model-capabilities.json")))
        for scenario in 0..<3 {
            let repo=MemoryRepository();var state=repo.load()
            state.preferences.shortcutDefaultVersion=1;state.preferences.panelShortcutDefaultVersion=1
            if scenario==0 {
                state.preferences.captureShortcut=ShortcutBinding(keyCode:0,modifiers:["shift"])
                state.preferences.panelShortcut=ShortcutBinding(keyCode:1,modifiers:["shift"])
            }else if scenario==1 {
                state.preferences.captureShortcut=ShortcutBinding(keyCode:40,modifiers:["control","shift"])
                state.preferences.panelShortcut=nil
            }else {
                state.preferences.captureShortcut=nil;state.preferences.panelShortcut=nil
                state.preferences.shortcutDefaultVersion=nil;state.preferences.panelShortcutDefaultVersion=nil
            }
            repo.save(state)
            let runtime=try ReadingRuntime(repository:repo,assets:MemoryAssets(bytes:Data()),transport:FakeTransport(),catalog:catalog,prompt:"角色")
            let preferences=await runtime.preferences()
            #expect(preferences.shortcutDefaultVersion==2 && preferences.panelShortcutDefaultVersion==2)
            if scenario==1 {
                #expect(preferences.captureShortcut==state.preferences.captureShortcut)
                #expect(preferences.panelShortcut==nil)
            }else {
                #expect(preferences.captureShortcut==ShortcutBinding(keyCode:0,modifiers:["command","shift"]))
                #expect(preferences.panelShortcut==ShortcutBinding(keyCode:1,modifiers:["command","shift"]))
            }
        }
    }
    @Test func imageOnlySubmissionIsAcceptedWithDefaultReadingInstruction() async throws {
        let(r,t,_)=try make();let initial=try await r.view(),id=initial.currentTask!.task.id,imageID=newID()
        let asset=ImageAsset(id:imageID,source:SourceInfo(kind:"screen-region"),width:10,height:10,byteLength:0,sha256:"test",storageKey:"images/test.png",thumbnailKey:nil)
        try await r.attachCapture(asset,taskId:id)
        let draft=try await r.view().currentTask!.draft
        let requestID=try await r.send(taskId:id,expectedDraft:draft.revision,expectedPreferences:initial.preferences.revision,operationId:newID())
        try await wait(r)
        let state=await r.snapshot(),snapshot=state.snapshots[state.generations[requestID]!.snapshotId]!
        #expect(snapshot.submission.prompt.isEmpty);#expect(snapshot.submission.images.count==1)
        #expect(snapshot.messages.last!.parts.last!.text!.contains("请解读所附图片"))
        #expect(await t.starts==1);#expect(try await r.view().currentTask!.draft.images.isEmpty)
    }
    @Test func missingCredentialsPreservesEverything() async throws {
        let (r,t,_)=try make();await t.deny();let(id,d,p)=try await prompt(r)
        await #expect(throws:AppFault.self){try await r.send(taskId:id,expectedDraft:d,expectedPreferences:p,operationId:newID())}
        let view=try await r.view();#expect(view.currentTask?.draft.prompt=="问题");#expect(view.currentTask?.turns.isEmpty==true);#expect(await t.starts==0)
    }
    @Test func sendReplayAndFailedRegenerationRestoresOriginal() async throws {
        let(r,t,_)=try make();let(id,d,p)=try await prompt(r)
        _=try await r.send(taskId:id,expectedDraft:d,expectedPreferences:p,operationId:newID());try await wait(r)
        let original=try await r.view().currentTask!.turns[0]
        #expect(original.answer=="已保存的模拟回答");#expect(try await r.view().currentTask?.draft.prompt=="")
        await t.fail()
        _=try await r.replay(taskId:id,turnId:original.id,requestId:original.requestId,kind:"regenerate",expectedPreferences:p,operationId:newID());try await wait(r)
        #expect(try await r.view().currentTask?.turns[0].requestId==original.requestId)
        #expect(await t.starts==2)
        let state=await r.snapshot();#expect(state.generations.count==2);#expect(state.generations.values.contains{$0.status=="failed" && $0.answer=="已保存的模拟回答"})
    }
    @Test func duplicateSendAndSwitchDoNotCrossTasks() async throws {
        let(r,t,_)=try make();await t.setSlow();let(id,d,p)=try await prompt(r);let op=newID()
        let req=try await r.send(taskId:id,expectedDraft:d,expectedPreferences:p,operationId:op)
        #expect(try await r.send(taskId:id,expectedDraft:d,expectedPreferences:p,operationId:op)==req)
        let other=try await r.createTask(title:"任务二")
        try await r.changeDraft(taskId:other,expected:0,change:["kind":.string("prompt"),"text":.string("新草稿")]);try await Task.sleep(for:.milliseconds(450))
        #expect(try await r.view().currentTask?.draft.prompt=="新草稿");#expect(try await r.view(taskId:id).currentTask?.turns[0].status=="complete");#expect(await t.starts==1)
    }
    @Test func staleSelectionClearCannotRemoveNewQuote() async throws {
        let(r,_,_)=try make();let v=try await r.view(),id=v.currentTask!.task.id
        try await r.savePreferences(expected:v.preferences.revision,patch:["quoteMode":.string("latest")])
        let lease=newID(),token1=newID(),token2=newID(),source=SourceInfo(kind:"external-selection",documentIdentity:"fixture")
        let old=try await r.ingestSelection(SelectionEvent(taskId:id,routingEpoch:0,sourceLeaseId:lease,sourceSequence:1,outcome:.selected(token:token1,source:source,text:"旧段落")))!
        _=try await r.ingestSelection(SelectionEvent(taskId:id,routingEpoch:0,sourceLeaseId:lease,sourceSequence:2,outcome:.selected(token:token2,source:source,text:"新段落")))
        _=try await r.ingestSelection(SelectionEvent(taskId:id,routingEpoch:0,sourceLeaseId:lease,sourceSequence:3,outcome:.cleared(token:token1,expectedQuoteId:old)))
        #expect(try await r.view().currentTask?.draft.externalQuotes.map(\.text)==["新段落"])
    }
    @Test func restartInterruptsWithoutReissuing() async throws {
        let(r,t,repo)=try make();await t.setSlow();let(id,d,p)=try await prompt(r);_=try await r.send(taskId:id,expectedDraft:d,expectedPreferences:p,operationId:newID())
        let replacement=try ReadingRuntime(repository:repo,assets:MemoryAssets(bytes:Data()),transport:t,catalog:ModelCatalog(data:Data(contentsOf:URL(fileURLWithPath:ProcessInfo.processInfo.environment["ANY_SIDEBAR_CONTRACTS"]!).appendingPathComponent("model-capabilities.json"))),prompt:"角色")
        #expect(try await replacement.view().currentTask?.turns[0].status=="interrupted")
        await r.shutdown()
    }
}
