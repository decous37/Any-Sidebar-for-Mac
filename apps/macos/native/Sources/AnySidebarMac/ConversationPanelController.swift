import AppKit
import WebKit
@MainActor final class ConversationPanel: NSPanel {override var canBecomeKey:Bool {true};override var canBecomeMain:Bool {false}}
@MainActor final class ConversationPanelController: NSObject, NSWindowDelegate, WKNavigationDelegate {
    let panel:ConversationPanel
    let web:WKWebView
    let bridge:WebViewBridge
    init(resources:ApplicationResources,composition:AppComposition) {
        let configuration=WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(AssetSchemeHandler(root:resources.root,runtime:composition.runtime,store:composition.store),forURLScheme:"anysidebar")
        bridge=WebViewBridge(schema:resources.schema,composition:composition)
        configuration.userContentController.addScriptMessageHandler(bridge,contentWorld:.page,name:"native")
        web=WKWebView(frame:.zero,configuration:configuration)
        panel=ConversationPanel(contentRect:NSRect(x:100,y:100,width:380,height:640),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
        super.init()
        panel.title="Any Sidebar";panel.minSize=NSSize(width:320,height:420);panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=false;panel.level = .floating;panel.collectionBehavior=[.fullScreenAuxiliary,.moveToActiveSpace];panel.delegate=self
        panel.isOpaque=false;panel.backgroundColor = .clear
        let backdrop=NSVisualEffectView(frame:panel.contentView?.bounds ?? .zero)
        backdrop.material = .popover;backdrop.blendingMode = .behindWindow;backdrop.state = .active
        web.underPageBackgroundColor = .clear;web.frame=backdrop.bounds;web.autoresizingMask=[.width,.height]
        backdrop.addSubview(web);panel.contentView=backdrop;web.navigationDelegate=self;bridge.web=web
        if !panel.setFrameUsingName("AnySidebarConversation") {panel.center()};panel.setFrameAutosaveName("AnySidebarConversation")
        web.load(URLRequest(url:URL(string:"anysidebar://app/index.html")!))
    }
    func show(near anchor:NSRect? = nil) {
        if let anchor {
            let screen=NSScreen.screens.first(where:{$0.visibleFrame.intersects(anchor)}) ?? NSScreen.main
            if let screen {panel.setFrame(DisplayPlacement.panel(size:panel.frame.size,anchor:anchor,visible:screen.visibleFrame),display:true)}
        }
        panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func toggle(near anchor:NSRect) {if panel.isVisible{hide()}else{show(near:anchor)}}
    func hide() {panel.orderOut(nil)}
    func windowShouldClose(_ sender:NSWindow) -> Bool {hide();return false}
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping @MainActor @Sendable (WKNavigationActionPolicy)->Void) {
        guard let url=action.request.url else{decisionHandler(.cancel);return}
        if url.scheme=="anysidebar",url.host=="app",action.targetFrame?.isMainFrame==true {decisionHandler(.allow)}
        else {if action.navigationType == .linkActivated,["https","http"].contains(url.scheme ?? ""){NSWorkspace.shared.open(url)};decisionHandler(.cancel)}
    }
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) {bridge.invalidate();webView.reload()}
}
