import Foundation
/// Recheck on native activation/panel entry, not just DOM focus. Never requests permissions itself.
@MainActor public final class PermissionMonitor {
    public private(set) var revision=0
    public private(set) var current:[String:Bool] = [:]
    private let read:()->[String:Bool]
    private let changed:([String:Bool])->Void
    private var followup:Task<Void,Never>?
    public init(read:@escaping()->[String:Bool] = {PermissionService.state()},changed:@escaping([String:Bool])->Void) {self.read=read;self.changed=changed}
    @discardableResult public func check()->[String:Bool] {
        let next=read()
        if next != current {current=next;revision += 1;changed(next)}
        return next
    }
    public func afterUserAction() {
        followup?.cancel();check()
        followup=Task{[weak self] in
            for _ in 0..<10 {
                do{try await Task.sleep(for:.seconds(1))}catch{return}
                guard let self else{return};self.check()
            }
        }
    }
    public func stop(){followup?.cancel();followup=nil}
}
