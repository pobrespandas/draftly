import Testing
import Carbon
@testable import Draftly

@MainActor struct GlobalHotKeyMappingTests {
    @Test func staleEventsCannotUseReplacementOrResumedBindings() throws {
        var identities = GlobalHotKeyIdentity()
        let originalValue = identities.allocate()
        let original = try #require(originalValue)
        identities.register(original, name: "Quick Capture")
        #expect(identities.name(for: original) == "Quick Capture")
        identities.invalidate()
        #expect(identities.name(for: original) == nil)
        let replacementValue = identities.allocate()
        let replacement = try #require(replacementValue)
        #expect(replacement != original)
        #expect(identities.name(for: replacement) == nil)
        identities.register(replacement, name: "Main Window")
        #expect(identities.name(for: original) == nil)
        #expect(identities.name(for: replacement) == "Main Window")
        identities.invalidate()
        let resumedValue = identities.allocate()
        let resumed = try #require(resumedValue)
        identities.register(resumed, name: "Quick Capture")
        #expect(resumed != replacement && resumed != original)
        #expect(identities.name(for: original) == nil)
        #expect(identities.name(for: replacement) == nil)
    }

    @Test func identityExhaustionDoesNotWrapToAnEarlierRegistration() throws {
        var identities = GlobalHotKeyIdentity(nextID: .max)
        let lastValue = identities.allocate()
        let last = try #require(lastValue)
        #expect(last == .max)
        identities.register(last, name: "Quick Capture")
        let exhausted = identities.allocate()
        #expect(exhausted == nil)
        identities.invalidate()
        let stillExhausted = identities.allocate()
        #expect(stillExhausted == nil)
        #expect(identities.name(for: last) == nil)
        var invalid = GlobalHotKeyIdentity(nextID: 0)
        let invalidValue = invalid.allocate()
        #expect(invalidValue == nil)
    }

    @Test func legacyCaptureAndRecordedModifiersMapToCarbonWithoutRegistering() {
        #expect(GlobalHotKeys.legacyKeyCode("n") == UInt32(kVK_ANSI_N))
        #expect(GlobalHotKeys.legacyKeyCode("K") == UInt32(kVK_ANSI_K))
        #expect(GlobalHotKeys.legacyKeyCode("🐼") == nil)
        #expect(GlobalHotKeys.carbonModifiers(["command", "control", "option", "command"]) == UInt32(cmdKey | controlKey | optionKey))
        #expect(GlobalHotKeys.carbonModifiers(["shift"]) == UInt32(shiftKey))
    }
}
