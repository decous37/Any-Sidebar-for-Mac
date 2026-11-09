import AppKit
import WebKit
import ReadingCore
import ReadingStorage
import MacServices
import DeepSeekTransport
@MainActor final class EventRelay {var update:((String)->Void)?}
@MainActor final class AppComposition {
    let resources:ApplicationResources
    let runtime:ReadingRuntime
    let store:FileAttachmentStore
    let vault:KeychainVault
    let selection=AccessibilitySelectionService()
    let screen=ScreenCaptureService()
    let shortcut=ShortcutService(id:1)
    let panelShortcut=ShortcutService(id:2)
    let companion=CompanionController()
    var panel:ConversationPanelController!
    var captureJob:Task<Void,Never>?
    var captureOperation:ID?
    var captureError:AppFault?
    var runtimeError:AppFault?
    var systemRevision=0
    var credentialCache:JSONValue?
    var recordingKind="capture"
    var recordingOperation:ID?
    var recordedShortcut:ShortcutBinding?
    var selectionStatus="disabled"
    var workspaceObserver:Any?
    var mouseMonitor:Any?
    var activationObserver:Any?
    var windowObserver:Any?
    lazy var permissions=PermissionMonitor{[weak self] _ in self?.notifySystem("permissions-changed");Task{await self?.refresh()}}
    let relay:EventRelay
    static func make() async throws -> AppComposition {
        guard let resourceRoot=Bundle.main.resourceURL else{throw AppFault("RESOURCE_MISSING","应用资源缺失。")}
        let resources=try ApplicationResources(root:resourceRoot)
        let dataRoot=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("com.decous.anysidebar.mac")
        let relay=EventRelay(),vault=KeychainVault(),transport=RequestCoordinator(vault:KeychainVault())
        let (store,runtime)=try await Task.detached {
            let database=try SQLiteDatabase(directory:dataRoot),store=try FileAttachmentStore(root:dataRoot)
            let runtime=try ReadingRuntime(repository:database,assets:store,transport:transport,catalog:resources.catalog,prompt:resources.prompt,changed:{type in Task{@MainActor in relay.update?(type)}})
            return (store,runtime)
        }.value
        return AppComposition(resources:resources,runtime:runtime,store:store,vault:vault,relay:relay)
    }
    init(resources:ApplicationResources,runtime:ReadingRuntime,store:FileAttachmentStore,vault:KeychainVault,relay:EventRelay){
        self.resources=resources;self.runtime=runtime;self.store=store;self.vault=vault;self.relay=relay
        panel=ConversationPanelController(resources:resources,composition:self)
        relay.update={[weak self] type in if type=="storage-failed"{self?.runtimeError=AppFault.storage};self?.panel.bridge.event(type);Task{await self?.refresh()}}
        companion.opened={[weak self] in guard let self else{return};self.panel.toggle(near:self.companion.window.frame)}
        companion.visibilityChanged={[weak self] visible in Task{guard let self else{return};do{try await self.runtime.companionVisible(visible);self.companion.show(visible)}catch{self.runtimeError=AppFault.storage}}}
        companion.captured={[weak self] in Task{await self?.captureCurrent()}}
        companion.windowCaptured={[weak self] in Task{await self?.captureCurrent(mode:"window")}}
        companion.panelVisible={[weak self] in self?.panel.panel.isVisible ?? false}
        companion.settingsOpened={[weak self] in guard let self else{return};self.panel.show(near:self.companion.window.frame);self.panel.bridge.event("open-settings")}
        companion.quit={NSApp.terminate(nil)}
        selection.receive={[weak self] event in Task{@MainActor in
            guard let self else{return}
            do{let id=try await runtime.ingestSelection(event);if case .selected(let token,_,_)=event.outcome{self.selection.acknowledge(token:token,quoteId:id)}}catch{self.selectionStatus="unsupported"}
        }}
        selection.status={[weak self] value in Task{@MainActor in self?.selectionStatus=value}}
        shortcut.triggered={[weak self] in Task{await self?.captureCurrent()}}
        panelShortcut.triggered={[weak self] in guard let self,self.captureOperation==nil else{return};self.panel.toggle(near:self.companion.window.frame)}
        let onRecorded:(ID,ShortcutBinding?)->Void = {[weak self] id,binding in
            guard let self,self.recordingOperation==id else{return}
            self.recordedShortcut=binding;self.recordingOperation=nil;self.shortcut.resume();self.panelShortcut.resume();self.notifySystem("shortcut-recording-changed")
        }
        shortcut.recorded=onRecorded;panelShortcut.recorded=onRecorded
        workspaceObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main){[weak self] notification in
            guard let app=notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else{return}
            Task{@MainActor in self?.selection.activate(app);await self?.refresh()}
        }
        activationObserver=NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.permissions.afterUserAction();await self?.refresh()}}
        windowObserver=NotificationCenter.default.addObserver(forName:NSWindow.didBecomeKeyNotification,object:panel.panel,queue:.main){[weak self] _ in Task{@MainActor in self?.permissions.afterUserAction();await self?.refresh()}}
        mouseMonitor=NSEvent.addGlobalMonitorForEvents(matching:.leftMouseUp){[weak self] _ in Task{@MainActor in self?.selection.scheduleRead()}}
        Task {let p=await runtime.preferences();shortcut.restore(p.captureShortcut);panelShortcut.restore(p.panelShortcut);companion.show(p.companionVisible);await refresh();panel.show(near:companion.window.frame);try? await runtime.garbageCollect()}
    }
    func refresh() async {
        let p=await runtime.preferences(),route=await runtime.route(),permissionState=permissions.check()
        selection.configure(enabled:p.autoSelectionEnabled && p.disclosureVersion=="v1" && permissionState["accessibility"]==true,taskId:route.0,epoch:route.1)
        if p.autoSelectionEnabled,let app=NSWorkspace.shared.frontmostApplication,app.bundleIdentifier != Bundle.main.bundleIdentifier {selection.activate(app)}
        if let view=try? await runtime.view(),let draft=view.currentTask?.draft {companion.reference(!draft.externalQuotes.isEmpty || !draft.images.isEmpty || draft.assistantQuote != nil)}
    }
    func notifySystem(_ type:String){systemRevision += 1;panel?.bridge.event(type)}
    func bootstrap() async throws -> JSONValue {
        if credentialCache == nil {
            do{credentialCache = .object(["state":.string("known"),"configured":.bool(try await vault.configured())])}
            catch{credentialCache = .object(["state":.string("unknown"),"error":try .encode(AppFault("CREDENTIAL_ACCESS_DENIED","暂时无法检查钥匙串，请检查系统授权。",retryable:true))])}
        }
        let view=try await runtime.view()
        let permissionState=permissions.check()
        // No await between ephemeral state and its revision: earlier replies cannot replace a later candidate.
        return .object(["runtime":try .encode(view),"permissions":try .encode(permissionState),"systemRevision":.number(Double(systemRevision)),"credential":credentialCache!,"shortcutState":.string(shortcut.state),"panelShortcutState":.string(panelShortcut.state),"recordingKind":.string(recordingKind),"recordingOperationId":recordingOperation.map(JSONValue.string) ?? .null,"recordedShortcut":try .encode(recordedShortcut),"captureOperationId":captureOperation.map(JSONValue.string) ?? .null,"captureError":try .encode(captureError),"selectionStatus":.string(selectionStatus),"appFault":try .encode(runtimeError)])
    }
    func captureCurrent(mode:String="region") async {
        if let operation=captureOperation {cancelCapture(operation);return}
        if let id=(await runtime.route()).0 {
            do{try await startCapture(taskId:id,mode:mode,operationId:newID())}
            catch{captureError=(error as? AppFault);notifySystem("capture-changed");panel.show(near:companion.window.frame)}
        }
    }
    func cancelCapture(_ operation:ID) {
        guard captureOperation==operation else{return}
        screen.cancel();captureJob?.cancel()
    }
    func startCapture(taskId:ID,mode:String,operationId:ID) async throws {
        guard captureOperation==nil else{throw AppFault("CAPTURE_BUSY","已有截图操作正在进行。")}
        let p=await runtime.preferences()
        guard p.disclosureVersion=="v1" else{throw AppFault("CONSENT_REQUIRED","请先在设置中确认采集说明。")}
        _=try await runtime.view(taskId:taskId)
        captureOperation=operationId;captureError=nil;notifySystem("capture-changed")
        let restorePanel=panel.panel.isVisible
        panel.hide();companion.show(false)
        captureJob=Task {
            defer{captureOperation=nil;captureJob=nil;companion.show(p.companionVisible);notifySystem("capture-changed")}
            do{
                let (png,source)=try await screen.capture(mode:mode);try Task.checkCancellation()
                let store=self.store
                let asset=try await Task.detached{try store.persist(png:png,source:source)}.value
                try Task.checkCancellation();try await runtime.attachCapture(asset,taskId:taskId)
                panel.show(near:companion.window.frame)
            }catch{
                captureError=error is CancellationError ? AppFault("CAPTURE_CANCELLED","已取消截图。") : ((error as? AppFault) ?? AppFault("CAPTURE_FAILED","截图失败，请检查屏幕访问权限后重试。",retryable:true))
                if restorePanel || captureError?.code != "CAPTURE_CANCELLED" {panel.show(near:companion.window.frame)}
            }
        }
    }
    func dispatch(_ request:BridgeRequest) async throws -> JSONValue {
        let c=request.command,a=request.args,op=request.operationId
        func str(_ key:String)->String{a[key]?.string ?? ""}
        func int(_ key:String)->Int{a[key]?.int ?? -1}
        let reads:Set<String>=["bootstrap","listTasks","getTaskView","getOperation","getCredentialStatus"]
        if c=="getOperation" {return try .encode(await runtime.operation(str("sourceOperationId")))}
        if c=="getTaskView" {return .object(["runtime":try .encode(await runtime.view(taskId:str("taskId"),cursor:a["cursor"]?.int))])}
        if c=="listTasks" {return try .encode(await runtime.view().tasks)}
        if !reads.contains(c) {
            let digest=c=="setKey" ? "sensitive":FileAttachmentStore.digest(try JSONEncoder().encode(JSONValue.object(a)))
            if try await !runtime.reserveOperation(op,command:c,digest:digest) {
                if let previous=await runtime.operation(op),previous.state=="failed",let error=previous.error {throw error}
                return try await bootstrap()
            }
        }
        do {
            var resultID:ID?
            switch c {
            case "bootstrap":break
            case "getCredentialStatus":credentialCache=nil
            case "createTask":resultID=try await runtime.createTask(title:str("title"))
            case "switchTask":try await runtime.switchTask(str("taskId"))
            case "renameTask":try await runtime.renameTask(str("taskId"),title:str("title"),expected:int("expectedRevision"))
            case "changeDraft":try await runtime.changeDraft(taskId:str("taskId"),expected:int("expectedRevision"),change:a["change"]!.object!)
            case "send":resultID=try await runtime.send(taskId:str("taskId"),expectedDraft:int("expectedDraftRevision"),expectedPreferences:int("expectedPreferencesRevision"),operationId:op)
            case "retry","regenerate":resultID=try await runtime.replay(taskId:str("taskId"),turnId:str("turnId"),requestId:str("requestId"),kind:c,expectedPreferences:int("expectedPreferencesRevision"),operationId:op)
            case "stop":
                let t=a["target"]!.object!
                if t["kind"]?.string=="request",Set(t.keys)==["kind","taskId","requestId"],let tid=t["taskId"]?.string,let rid=t["requestId"]?.string,validID(tid),validID(rid) {try await runtime.stop(.request(taskId:tid,requestId:rid))}
                else if t["kind"]?.string=="operation",Set(t.keys)==["kind","taskId","sourceOperationId"],let tid=t["taskId"]?.string,let source=t["sourceOperationId"]?.string,validID(tid),validID(source) {try await runtime.stop(.operation(taskId:tid,sourceOperationId:source))}
                else{throw AppFault("INVALID_ARGUMENT","停止目标无效。")}
            case "restoreSubmission":try await runtime.restoreSubmission(taskId:str("taskId"),requestId:str("requestId"),expected:int("expectedDraftRevision"))
            case "savePreferences":
                let patch=a["patch"]!.object!
                if let raw=patch["captureShortcut"] ?? patch["panelShortcut"] {
                    guard patch.count==1 else{throw AppFault("INVALID_ARGUMENT","请单独设置快捷键。")}
                    let binding=raw == .null ? nil:try raw.decode(ShortcutBinding.self)
                    guard int("expectedRevision") == (await runtime.preferences()).revision else{throw AppFault("REVISION_CONFLICT","设置已更新，请重试。")}
                    let kind=patch["panelShortcut"] != nil ? "panel":"capture"
                    let service=kind=="panel" ? panelShortcut:shortcut
                    try await service.replace(binding){try await self.runtime.setShortcut(binding,kind:kind)};recordedShortcut=nil;notifySystem("shortcut-recording-changed")
                }else{try await runtime.savePreferences(expected:int("expectedRevision"),patch:patch)}
            case "setKey":try await vault.replace(str("key"));credentialCache = .object(["state":.string("known"),"configured":.bool(true)]);notifySystem("credential-changed")
            case "clearKey":try await vault.clear();credentialCache = .object(["state":.string("known"),"configured":.bool(false)]);notifySystem("credential-changed")
            case "acceptDisclosure":try await runtime.acceptDisclosure()
            case "setAutoSelectionEnabled":try await runtime.enableSelection(a["enabled"]!.bool!,expected:int("expectedRevision"));await refresh()
            case "requestPermission":PermissionService.request(str("kind"));permissions.afterUserAction();await refresh()
            case "startCapture":try await startCapture(taskId:str("taskId"),mode:str("mode"),operationId:op)
            case "cancelCapture":cancelCapture(str("captureOperationId"))
            case "startShortcutRecording":
                shortcut.cancelRecording();panelShortcut.cancelRecording();shortcut.suspend();panelShortcut.suspend()
                panel.show(near:companion.window.frame);panel.panel.makeFirstResponder(panel.web)
                recordingKind=a["kind"]?.string ?? "capture";recordingOperation=op;recordedShortcut=nil
                (recordingKind=="panel" ? panelShortcut:shortcut).startRecording(id:op);notifySystem("shortcut-recording-changed")
            case "cancelShortcutRecording":if recordingOperation==str("recordingOperationId"){shortcut.cancelRecording();panelShortcut.cancelRecording();shortcut.resume();panelShortcut.resume();recordingOperation=nil;notifySystem("shortcut-recording-changed")}
            case "deleteTask":try await runtime.deleteTask(str("taskId"),expected:int("expectedRevision"))
            case "clearAllTasks":try await runtime.clearAllTasks()
            case "setCompanionVisible":let visible=a["visible"]!.bool!;try await runtime.companionVisible(visible);companion.show(visible)
            case "hidePanel":panel.hide()
            case "copyText":NSPasteboard.general.clearContents();guard NSPasteboard.general.setString(str("text"),forType:.string) else{throw AppFault("COPY_FAILED","复制失败，请重试。")}
            default:throw AppFault("INVALID_ARGUMENT","未知操作。")
            }
            if !reads.contains(c){try await runtime.finishOperation(op,resultId:resultID)}
            return try await bootstrap()
        }catch{
            let fault=(error as? AppFault) ?? AppFault("STORAGE_FAILED","操作未完成，已保存的数据会保留。",retryable:true)
            if !reads.contains(c){try? await runtime.finishOperation(op,error:fault)}
            throw fault
        }
    }
    func shutdown() async {permissions.stop();captureJob?.cancel();screen.cancel();shortcut.stop();panelShortcut.stop();selection.configure(enabled:false,taskId:nil,epoch:0);if let mouseMonitor{NSEvent.removeMonitor(mouseMonitor)};await runtime.shutdown()}
}
