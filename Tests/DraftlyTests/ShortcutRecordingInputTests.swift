import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Shortcut recording input") @MainActor
struct ShortcutRecordingInputTests {
    @Test func escapeCancelsAndBothDeleteKeysClearWithoutRecordingTheirCharacters() {
        #expect(ShortcutRecordingInput.decision(keyCode: 53, characters: "x", flags: [.command]) == .cancel)
        for keyCode: UInt16 in [51, 117] {
            #expect(ShortcutRecordingInput.decision(keyCode: keyCode, characters: "x", flags: [.option])
                    == .record(CommandBinding(key: "", modifiers: [])))
        }
    }

    @Test(arguments: [String?.none, "", "\n", "\t", "\0", "two"])
    func missingControlAndMultipleCharactersKeepRecording(characters: String?) {
        #expect(ShortcutRecordingInput.decision(keyCode: 12, characters: characters, flags: [.command]) == .ignore)
    }

    @Test func printableInputNormalizesCaseKeepsThePhysicalKeyAndOmitsUnrelatedFlags() {
        let flags: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function, .shift, .option, .control, .command]
        let decision = ShortcutRecordingInput.decision(keyCode: 12, characters: "É", flags: flags)
        #expect(decision == .record(CommandBinding(key: "é", modifiers: ["command", "control", "option", "shift"], keyCode: 12)))
        #expect(ShortcutRecordingInput.decision(keyCode: 49, characters: " ", flags: [])
                == .record(CommandBinding(key: " ", modifiers: [], keyCode: 49)))
    }

    @Test func recordedLabelsKeepTheExistingModifierOrderAndEmptyPrompt() {
        let binding = CommandBinding(key: "n", modifiers: ["shift", "command", "option", "control", "command", "future"], keyCode: 45)
        #expect(ShortcutCaptureButton.title(binding) == "⌃⌥⇧⌘N")
        #expect(ShortcutCaptureButton.title(CommandBinding(key: "", modifiers: ["command"])) == "Record Shortcut")
    }
}
