import AppKit
@MainActor private final class CompanionView:NSView {
    var opened:(() -> Void)?;var contextMenu:(() -> NSMenu)?;var hasReference=false {didSet{needsDisplay=true}}
    override init(frame:NSRect){super.init(frame:frame);setAccessibilityElement(true);setAccessibilityRole(.button);setAccessibilityLabel("Any Sidebar 小助手");setAccessibilityHelp("点击展开或收起对话；拖动改变位置；右键打开菜单。")}
    required init?(coder:NSCoder){fatalError("init(coder:) is not supported")}
    override func accessibilityPerformPress()->Bool{opened?();return true}
    private var origin:NSPoint?,windowOrigin:NSPoint?
    override func draw(_ dirtyRect:NSRect) {
        let rect=bounds.insetBy(dx:3,dy:3)
        NSColor(calibratedRed:0.94,green:0.97,blue:1,alpha:1).setFill();NSBezierPath(roundedRect:rect,xRadius:18,yRadius:18).fill()
        NSColor(calibratedRed:0.15,green:0.44,blue:0.77,alpha:1).setStroke()
        let path=NSBezierPath(roundedRect:NSRect(x:15,y:16,width:28,height:25),xRadius:6,yRadius:6);path.lineWidth=2;path.stroke()
        let line=NSBezierPath();line.move(to:NSPoint(x:32,y:17));line.line(to:NSPoint(x:32,y:40));line.move(to:NSPoint(x:21,y:33));line.line(to:NSPoint(x:27,y:33));line.move(to:NSPoint(x:21,y:26));line.line(to:NSPoint(x:26,y:26));line.lineWidth=2;line.stroke()
        if hasReference {NSColor.systemBlue.setFill();NSBezierPath(ovalIn:NSRect(x:42,y:42,width:8,height:8)).fill()}
    }
    override func mouseDown(with event:NSEvent){origin=NSEvent.mouseLocation;windowOrigin=window?.frame.origin}
    override func mouseDragged(with event:NSEvent){guard let origin,let windowOrigin else{return};let p=NSEvent.mouseLocation;window?.setFrameOrigin(NSPoint(x:windowOrigin.x+p.x-origin.x,y:windowOrigin.y+p.y-origin.y))}
    override func mouseUp(with event:NSEvent){guard let origin else{return};let p=NSEvent.mouseLocation;if hypot(p.x-origin.x,p.y-origin.y)<4{opened?()};if let window{UserDefaults.standard.set(NSStringFromPoint(window.frame.origin),forKey:"companionPosition")}}
    override func rightMouseDown(with event:NSEvent){guard let menu=contextMenu?() else{return};NSMenu.popUpContextMenu(menu,with:event,for:self)}
}
@MainActor final class CompanionController:NSObject,NSMenuDelegate {
    let window:NSPanel;let status:NSStatusItem;private let view=CompanionView(frame:NSRect(x:0,y:0,width:56,height:56))
    var opened:(() -> Void)?;var captured:(() -> Void)?;var windowCaptured:(() -> Void)?;var settingsOpened:(() -> Void)?;var panelVisible:(() -> Bool)?;var quit:(() -> Void)?;var visibilityChanged:((Bool)->Void)?
    override init(){
        window=NSPanel(contentRect:NSRect(x:100,y:100,width:56,height:56),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        super.init()
        window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=true;window.level = .floating;window.hidesOnDeactivate=false;window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];window.contentView=view
        view.opened={[weak self] in self?.opened?()};view.contextMenu={[weak self] in self?.makeMenu() ?? NSMenu()}
        status.button?.image=NSImage(systemSymbolName:"sidebar.right",accessibilityDescription:"Any Sidebar")
        status.menu=makeMenu()
        place();NotificationCenter.default.addObserver(self,selector:#selector(place),name:NSApplication.didChangeScreenParametersNotification,object:nil)
    }
    private func makeMenu()->NSMenu {
        let menu=NSMenu();menu.delegate=self
        for (title,action,tag) in [("展开对话",#selector(openPanel),1),("框选读屏",#selector(capture),0),("窗口读屏",#selector(captureWindow),0),("设置…",#selector(openSettings),0),("隐藏小助手",#selector(toggle),2)] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;item.tag=tag;menu.addItem(item)
        }
        menu.addItem(.separator())
        let quitItem=NSMenuItem(title:"退出 Any Sidebar",action:#selector(exitApp),keyEquivalent:"");quitItem.target=self;menu.addItem(quitItem)
        return menu
    }
    func menuWillOpen(_ menu:NSMenu) {
        menu.item(withTag:1)?.title=panelVisible?()==true ? "收起对话":"展开对话"
        menu.item(withTag:2)?.title=window.isVisible ? "隐藏小助手":"显示小助手"
    }
    @objc func place(){
        let stored=UserDefaults.standard.string(forKey:"companionPosition").map(NSPointFromString) ?? NSPoint(x:(NSScreen.main?.visibleFrame.maxX ?? 1100)-90,y:180)
        let frames=NSScreen.screens.map(\.visibleFrame),frame=frames.first(where:{$0.intersects(CGRect(origin:stored,size:window.frame.size))}) ?? frames.first ?? CGRect(x:0,y:0,width:1200,height:800)
        window.setFrameOrigin(NSPoint(x:max(frame.minX,min(stored.x,frame.maxX-56)),y:max(frame.minY,min(stored.y,frame.maxY-56))))
    }
    func show(_ visible:Bool){if visible{window.orderFrontRegardless()}else{window.orderOut(nil)}}
    func reference(_ has:Bool){view.hasReference=has}
    @objc private func openPanel(){opened?()}
    @objc private func capture(){captured?()}
    @objc private func captureWindow(){windowCaptured?()}
    @objc private func openSettings(){settingsOpened?()}
    @objc private func toggle(){let visible = !window.isVisible;if let visibilityChanged{visibilityChanged(visible)}else{show(visible)}}
    @objc private func exitApp(){quit?()}
}
