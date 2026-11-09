import AppKit
import ReadingCore
@MainActor private final class RegionWindow:NSWindow {override var canBecomeKey:Bool{true};override var canBecomeMain:Bool{false}}
@MainActor final class RegionView: NSView {
    var start:NSPoint?,end:NSPoint?
    var selected: ((CGRect?) -> Void)?
    override var acceptsFirstResponder:Bool {true}
    override func draw(_ dirtyRect:NSRect) {
        NSColor.black.withAlphaComponent(0.24).setFill();bounds.fill()
        if let start,let end {let r=CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(start.x-end.x),height:abs(start.y-end.y));NSColor.white.withAlphaComponent(0.2).setFill();r.fill();NSColor.systemBlue.setStroke();let path=NSBezierPath(rect:r);path.lineWidth=2;path.stroke()}
        let caption="拖动框选要阅读的区域 · Esc 取消"
        caption.draw(at:NSPoint(x:28,y:bounds.height-50),withAttributes:[.font:NSFont.systemFont(ofSize:14,weight:.medium),.foregroundColor:NSColor.white])
    }
    override func mouseDown(with event:NSEvent) {start=convert(event.locationInWindow,from:nil);end=start;needsDisplay=true}
    override func mouseDragged(with event:NSEvent) {end=convert(event.locationInWindow,from:nil);needsDisplay=true}
    override func mouseUp(with event:NSEvent) {
        end=convert(event.locationInWindow,from:nil)
        guard let start,let end else{return}
        let rect=CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(start.x-end.x),height:abs(start.y-end.y))
        guard rect.width>=4,rect.height>=4 else{selected?(nil);return};selected?(rect)
    }
    override func keyDown(with event:NSEvent) {if event.keyCode==53{selected?(nil)}}
}
public struct CaptureRegion: Sendable { public var displayId: CGDirectDisplayID; public var rect: CGRect; public var screenHeight: CGFloat; public var scale: CGFloat }
@MainActor public final class CaptureOverlayController {
    private var windows:[NSWindow]=[]
    private var continuation:CheckedContinuation<CaptureRegion?,Never>?
    public init() {}
    public func choose() async -> CaptureRegion? {
        await withCheckedContinuation { continuation in
            self.continuation=continuation
            for screen in NSScreen.screens {
                let window=RegionWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
                window.level = .screenSaver;window.backgroundColor = .clear;window.isOpaque=false;window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
                let view=RegionView(frame:CGRect(origin:.zero,size:screen.frame.size))
                view.selected={[weak self] rect in self?.finish(rect.flatMap{r in (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map{CaptureRegion(displayId:$0,rect:r,screenHeight:screen.frame.height,scale:screen.backingScaleFactor)}})}
                window.contentView=view;windows.append(window);window.makeKeyAndOrderFront(nil);window.makeFirstResponder(view)
            }
            NSApp.activate(ignoringOtherApps:true)
        }
    }
    public func cancel() {finish(nil)}
    private func finish(_ result:CaptureRegion?) {for w in windows{w.orderOut(nil)};windows=[];let c=continuation;continuation=nil;c?.resume(returning:result)}
}
