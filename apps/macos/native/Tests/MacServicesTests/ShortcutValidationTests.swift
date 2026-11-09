import Testing
import ReadingCore
@testable import MacServices
@Suite struct ShortcutValidationTests {
    @MainActor @Test func shiftOnlyBindingIsValid() throws {
        try ShortcutService.validate(ShortcutBinding(keyCode:0,modifiers:["shift"]))
        #expect(throws:AppFault.self){try ShortcutService.validate(ShortcutBinding(keyCode:0,modifiers:[]))}
        #expect(throws:AppFault.self){try ShortcutService.validate(ShortcutBinding(keyCode:200,modifiers:["shift"]))}
    }
}
