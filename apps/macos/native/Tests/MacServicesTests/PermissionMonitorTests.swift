import Testing
@testable import MacServices
@Suite struct PermissionMonitorTests {
    @MainActor @Test func reflectsGrantAndRevocationWithoutConversationMutation() {
        var actual=["accessibility":false,"screen":false],notifications:[[String:Bool]]=[]
        let monitor=PermissionMonitor(read:{actual},changed:{notifications.append($0)})
        #expect(monitor.check()["screen"]==false)
        actual=["accessibility":true,"screen":true];monitor.check()
        #expect(monitor.current["accessibility"]==true);#expect(monitor.current["screen"]==true)
        actual["accessibility"]=false;monitor.check()
        #expect(monitor.current["accessibility"]==false);#expect(notifications.count==3);#expect(monitor.revision==3)
        monitor.check();#expect(notifications.count==3)
    }
}
