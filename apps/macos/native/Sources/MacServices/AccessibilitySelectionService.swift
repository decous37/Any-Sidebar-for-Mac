import AppKit
@preconcurrency import ApplicationServices
import ReadingCore

private func selectionNotification(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    guard let context else{return}
    Unmanaged<AccessibilitySelectionService>.fromOpaque(context).takeUnretainedValue().scheduleRead()
}
/// AX calls are bounded and isolated from the window thread. No key or clipboard monitoring.
public final class AccessibilitySelectionService: @unchecked Sendable {
    private let queue=DispatchQueue(label:"com.decous.anysidebar.selection",qos:.utility)
    private var observer:AXObserver?
    private var observed:AXUIElement?
    private var app:AXUIElement?
    private var source=SourceInfo(kind:"external-selection")
    private var lease=newID(),sequence=0
    private var route:(ID,Int)?
    private var sourceFocused=false
    private var enabled=false
    private var activePID:pid_t?
    private var lastDocument:String?
    private var lastWindow:AXUIElement?
    private var lastText:String?
    private var lastToken:ID?
    private var lastQuote:ID?
    private var lastRoute:(ID,Int)?
    private var scheduled=false
    private var readGeneration=0
    public var receive: @Sendable (SelectionEvent) -> Void = {_ in}
    public var status: @Sendable (String) -> Void = {_ in}
    public init() {}
    public func configure(enabled: Bool, taskId: ID?, epoch: Int) {
        queue.async {self.enabled=enabled;self.route=taskId.map{($0,epoch)};if !enabled{self.detach()}}
    }
    @MainActor public func activate(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else{queue.async{self.sourceFocused=false};return}
        let pid=app.processIdentifier,bundle=app.bundleIdentifier,name=app.localizedName
        queue.async {
            guard self.enabled else{return}
            self.sourceFocused=true
            guard self.activePID != pid else{return}
            self.detach();self.activePID=pid;self.lease=newID();self.sequence=0;self.lastText=nil;self.lastToken=nil;self.lastQuote=nil
            let element=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(element,0.2);self.app=element
            self.source=SourceInfo(kind:"external-selection",appBundleId:bundle,appName:name)
            var observer:AXObserver?
            if AXObserverCreate(pid,selectionNotification,&observer) == .success,let observer {
                self.observer=observer
                let context=Unmanaged.passUnretained(self).toOpaque()
                for name in [kAXFocusedUIElementChangedNotification,kAXFocusedWindowChangedNotification,kAXSelectedTextChangedNotification] {AXObserverAddNotification(observer,element,name as CFString,context)}
                CFRunLoopAddSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)
            }
            // Observe selection changes but don't import an unchanged selection merely on activation.
            self.observeFocused()
        }
    }
    private func detach() {
        if let observer {CFRunLoopRemoveSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)}
        observer=nil;observed=nil;app=nil;activePID=nil
    }
    private func attribute(_ e:AXUIElement,_ name:String) -> CFTypeRef? {var value:CFTypeRef?;guard AXUIElementCopyAttributeValue(e,name as CFString,&value) == .success else{return nil};return value}
    private func element(_ value:CFTypeRef?) -> AXUIElement? {guard let value,CFGetTypeID(value)==AXUIElementGetTypeID() else{return nil};return unsafeDowncast(value,to:AXUIElement.self)}
    private func observeFocused() {
        guard let app,let observer else{return}
        let focused=element(attribute(app,kAXFocusedUIElementAttribute))
        if let old=observed {AXObserverRemoveNotification(observer,old,kAXSelectedTextChangedNotification as CFString)}
        observed=focused
        if let focused {AXUIElementSetMessagingTimeout(focused,0.2);AXObserverAddNotification(observer,focused,kAXSelectedTextChangedNotification as CFString,Unmanaged.passUnretained(self).toOpaque())}
    }
    public func scheduleRead() {
        queue.async {
            guard self.enabled,let route=self.route else{return}
            self.readGeneration += 1
            let generation=self.readGeneration,lease=self.lease
            self.queue.asyncAfter(deadline:.now()+0.15) {
                guard self.readGeneration==generation,self.lease==lease,
                      !CGEventSource.buttonState(.combinedSessionState,button:.left) else{return}
                self.read(route:route)
            }
        }
    }
    public func acknowledge(token: ID, quoteId: ID?) {queue.async {if self.lastToken==token{self.lastQuote=quoteId}}}
    private func read(route: (ID,Int)) {
        guard enabled,sourceFocused,AXIsProcessTrusted(),let app else{status("permission");return}
        observeFocused()
        guard let window=element(attribute(app,kAXFocusedWindowAttribute)) else{status("unsupported");return}
        let title=attribute(window,kAXTitleAttribute) as? String
        let document=attribute(window,kAXDocumentAttribute) as? String
        var nodes:[AXUIElement]=[]
        if let focused=element(attribute(app,kAXFocusedUIElementAttribute)){nodes.append(focused)}
        nodes.append(window)
        var count=0;let deadline=Date().addingTimeInterval(0.6)
        var found:String?
        while !nodes.isEmpty,count<120,Date()<deadline {
            let node=nodes.removeFirst();count += 1;AXUIElementSetMessagingTimeout(node,0.12)
            let role=attribute(node,kAXRoleAttribute) as? String ?? ""
            if [kAXTextFieldRole,kAXComboBoxRole,"AXSearchField","AXSecureTextField"].contains(role){continue}
            var editable:DarwinBoolean=false
            if role==kAXTextAreaRole,AXUIElementIsAttributeSettable(node,kAXValueAttribute as CFString,&editable) == .success,editable.boolValue {continue}
            if let text=attribute(node,kAXSelectedTextAttribute) as? String {if !text.isEmpty{found=text;break};found=found ?? ""}
            if let children=attribute(node,kAXChildrenAttribute) as? [AXUIElement] {nodes.append(contentsOf:children.prefix(120-count))}
        }
        guard let text=found else{status("unsupported");return}
        guard text != lastText || document != lastDocument || lastWindow.map({!CFEqual($0,window)}) == true else{return}
        // A task switch alone must not import an old selection; only a new observed selection is routed.
        lastText=text;sequence += 1
        if text.isEmpty {
            if document==lastDocument,let lastWindow,CFEqual(lastWindow,window),let token=lastToken,let quote=lastQuote,let previous=lastRoute {
                receive(SelectionEvent(taskId:previous.0,routingEpoch:previous.1,sourceLeaseId:lease,sourceSequence:sequence,outcome:.cleared(token:token,expectedQuoteId:quote)))
            }
        } else {
            var source=self.source;source.documentTitle=title;source.documentIdentity=document;source.capturedAt=now()
            let token=newID();lastToken=token;lastRoute=route;lastQuote=nil;lastDocument=document;lastWindow=window
            receive(SelectionEvent(taskId:route.0,routingEpoch:route.1,sourceLeaseId:lease,sourceSequence:sequence,outcome:.selected(token:token,source:source,text:text)))
            status("selected")
        }
    }
}
