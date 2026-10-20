import Testing
import Carbon
@testable import Draftly

@MainActor struct GlobalHotKeyMappingTests {
    @Test func legacyCaptureAndRecordedModifiersMapToCarbonWithoutRegistering() {
        #expect(GlobalHotKeys.legacyKeyCode("n") == UInt32(kVK_ANSI_N))
        #expect(GlobalHotKeys.legacyKeyCode("K") == UInt32(kVK_ANSI_K))
        #expect(GlobalHotKeys.legacyKeyCode("🐼") == nil)
        #expect(GlobalHotKeys.carbonModifiers(["command", "control", "option", "command"]) == UInt32(cmdKey | controlKey | optionKey))
        #expect(GlobalHotKeys.carbonModifiers(["shift"]) == UInt32(shiftKey))
    }
}
