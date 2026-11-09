import AppKit
@preconcurrency import Carbon
import ReadingCore
private func hotkeyHandler(_ next:EventHandlerCallRef?,_ event:EventRef?,_ context:UnsafeMutableRawPointer?) -> OSStatus {
    guard let context,let event else{return OSStatus(eventNotHandledErr)}
    let service=Unmanaged<ShortcutService>.fromOpaque(context).takeUnretainedValue()
    var identity=EventHotKeyID()
    guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&identity)==noErr,
          identity.signature==0x4153424D,identity.id==service.hotkeyID else{return OSStatus(eventNotHandledErr)}
    Task{@MainActor in service.fire()};return noErr
}
@MainActor public final class ShortcutService {
    public nonisolated let hotkeyID:UInt32
    private var hotkey:EventHotKeyRef?
    private var handler:EventHandlerRef?
    private var monitor:Any?
    private var recording:ID?
    private var suspended=false
    public private(set) var binding:ShortcutBinding?
    public private(set) var state="unbound"
    public var triggered:(()->Void)?
    public var recorded:((ID,ShortcutBinding?)->Void)?
    public init(id:UInt32=1) {
        hotkeyID=id
        var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),hotkeyHandler,1,&spec,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    public func fire(){if recording==nil && !suspended{triggered?()}}
    public static func validate(_ binding:ShortcutBinding) throws {
        guard (0...127).contains(binding.keyCode),!binding.modifiers.isEmpty,Set(binding.modifiers).isSubset(of:["command","option","control","shift"]) else{throw AppFault("INVALID_ARGUMENT","请选择有效的快捷键组合。")}
    }
    private func register(_ binding:ShortcutBinding) throws -> EventHotKeyRef {
        try Self.validate(binding)
        var modifiers:UInt32=0
        for modifier in binding.modifiers {modifiers |= UInt32(modifier=="command" ? cmdKey:modifier=="option" ? optionKey:modifier=="control" ? controlKey:shiftKey)}
        var result:EventHotKeyRef?
        let status=RegisterEventHotKey(UInt32(binding.keyCode),modifiers,EventHotKeyID(signature:0x4153424D,id:hotkeyID),GetApplicationEventTarget(),0,&result)
        guard status==noErr,let result else{throw AppFault("SHORTCUT_CONFLICT","此快捷键已被占用，请选择其他组合。")};return result
    }
    public func replace(_ proposed:ShortcutBinding?,persist:() async throws->Void) async throws {
        if proposed==binding && (proposed==nil || hotkey != nil){try await persist();return}
        let candidate=try proposed.map{try register($0)}
        do{try await persist()}catch{if let candidate{UnregisterEventHotKey(candidate)};throw error}
        if let hotkey{UnregisterEventHotKey(hotkey)};hotkey=candidate;binding=proposed;state=proposed==nil ? "unbound":"active"
    }
    public func restore(_ proposed:ShortcutBinding?){binding=proposed;resume()}
    public func suspend(){suspended=true;if let hotkey{UnregisterEventHotKey(hotkey)};hotkey=nil}
    public func resume(){
        suspended=false
        guard recording==nil,hotkey==nil else{return}
        guard let binding else{state="unbound";return}
        do{hotkey=try register(binding);state="active"}catch{state="conflict"}
    }
    public func startRecording(id:ID){
        cancelRecording()
        if let hotkey{UnregisterEventHotKey(hotkey);self.hotkey=nil}
        recording=id
        monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
            guard let self,self.recording==id else{return event}
            if event.keyCode==53{self.cancelRecording();self.recorded?(id,nil);return nil}
            var modifiers:[String]=[]
            for (flag,name):(NSEvent.ModifierFlags,String) in [(.command,"command"),(.option,"option"),(.control,"control"),(.shift,"shift")]{if event.modifierFlags.contains(flag){modifiers.append(name)}}
            if modifiers.isEmpty{return nil}
            let value=ShortcutBinding(keyCode:Int(event.keyCode),modifiers:modifiers)
            self.cancelRecording();self.recorded?(id,value);return nil
        }
    }
    public func cancelRecording(){
        if let monitor{NSEvent.removeMonitor(monitor)};monitor=nil
        let wasRecording=recording != nil;recording=nil
        if wasRecording && !suspended{resume()}
    }
    public func stop(){suspend();cancelRecording();if let handler{RemoveEventHandler(handler)};handler=nil}
}
