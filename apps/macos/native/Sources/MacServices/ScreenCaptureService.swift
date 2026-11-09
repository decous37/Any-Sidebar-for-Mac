import AppKit
@preconcurrency import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import ReadingCore
@MainActor public final class ScreenCaptureService {
    public let overlay=CaptureOverlayController()
    private var windowAlert:NSAlert?
    public func cancel(){overlay.cancel();if let windowAlert{windowAlert.window.orderOut(nil);NSApp.abortModal()}}
    public init() {}
    private func png(_ image:CGImage) throws -> Data {
        let data=NSMutableData()
        guard let dest=CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil) else{throw AppFault("CAPTURE_FAILED","无法编码截图。")}
        CGImageDestinationAddImage(dest,image,nil);guard CGImageDestinationFinalize(dest) else{throw AppFault("CAPTURE_FAILED","无法保存截图。")};return data as Data
    }
    public func capture(mode:String) async throws -> (Data,SourceInfo) {
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else{throw AppFault("SCREEN_PERMISSION_REQUIRED","请先在设置中允许屏幕访问。")}
        let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
        try Task.checkCancellation()
        let configuration=SCStreamConfiguration();configuration.showsCursor=false
        let filter:SCContentFilter
        var source=SourceInfo(kind:mode=="region" ? "screen-region":"screen-window")
        if mode=="region" {
            guard let region=await overlay.choose() else{throw AppFault("CAPTURE_CANCELLED","已取消截图。")}
            guard let display=content.displays.first(where:{$0.displayID==region.displayId}) else{throw AppFault("CAPTURE_FAILED","显示器已变化，请重新截取。")}
            let rect=region.rect
            let own=content.applications.filter{$0.bundleIdentifier==Bundle.main.bundleIdentifier}
            filter=SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
            configuration.sourceRect=CGRect(x:rect.minX,y:region.screenHeight-rect.maxY,width:rect.width,height:rect.height)
            configuration.width=Int(rect.width*region.scale);configuration.height=Int(rect.height*region.scale)
        } else {
            let choices=content.windows.filter{$0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier && $0.frame.width>80 && $0.frame.height>60 && !($0.title ?? "").isEmpty}
            guard !choices.isEmpty else{throw AppFault("CAPTURE_FAILED","没有可截取的窗口。")}
            let alert=NSAlert();windowAlert=alert;defer{windowAlert=nil};alert.messageText="选择要读取的窗口";alert.addButton(withTitle:"截取");alert.addButton(withTitle:"取消")
            let combo=NSPopUpButton(frame:NSRect(x:0,y:0,width:340,height:28));for w in choices{combo.addItem(withTitle:"\(w.owningApplication?.applicationName ?? "应用") · \(w.title ?? "窗口")")};alert.accessoryView=combo
            guard alert.runModal() == .alertFirstButtonReturn else{throw AppFault("CAPTURE_CANCELLED","已取消截图。")}
            let window=choices[combo.indexOfSelectedItem];filter=SCContentFilter(desktopIndependentWindow:window)
            let scale=NSScreen.screens.first?.backingScaleFactor ?? 2
            configuration.width=Int(window.frame.width*scale);configuration.height=Int(window.frame.height*scale)
            source.appName=window.owningApplication?.applicationName;source.appBundleId=window.owningApplication?.bundleIdentifier;source.documentTitle=window.title
        }
        let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:configuration)
        try Task.checkCancellation()
        return (try png(image),source)
    }
}
