import AppKit
@preconcurrency import ApplicationServices
import ReadingCore
@MainActor public enum PermissionService {
    public static func state() -> [String:Bool] { ["accessibility":AXIsProcessTrusted(),"screen":CGPreflightScreenCaptureAccess()] }
    public static func request(_ kind: String) {
        if kind=="accessibility" {_ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt":true] as CFDictionary)}
        else if kind=="screen" {_ = CGRequestScreenCaptureAccess()}
    }
}
