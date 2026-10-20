import Foundation
import Testing
@testable import DraftlyCore

struct GlobalShortcutTests {
    private func configuration(_ values: [String: CommandBinding]) throws -> String {
        String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }

    @Test func existingCaptureDefaultAndOldBindingsRemainCompatible() throws {
        let capture = CommandShortcuts.binding("Quick Capture", configuration: "{}")
        #expect(capture.key == "n")
        #expect(Set(capture.modifiers) == ["command", "control", "option"])
        #expect(CommandShortcuts.binding("Main Window", configuration: "{}").key.isEmpty)
        #expect(CommandShortcuts.binding("Capture Clipboard", configuration: "{}").key.isEmpty)
        let old = try JSONDecoder().decode(CommandBinding.self, from: Data(#"{"key":"n","modifiers":["command"]}"#.utf8))
        #expect(old.keyCode == nil)
        let malformed = try configuration(["Quick Capture": CommandBinding(key: "many", modifiers: ["command"], keyCode: 40)])
        let fallback = CommandShortcuts.binding("Quick Capture", configuration: malformed)
        #expect(fallback.key == "n")
        #expect(fallback.keyCode == nil)
        let value = CommandBinding(key: "k", modifiers: ["control", "option"], keyCode: 40)
        let stored = try configuration(["Main Window": value])
        #expect(CommandShortcuts.binding("Main Window", configuration: stored) == value)
        #expect(GlobalShortcuts.conflict(name: "Main Window", binding: value, configuration: stored, actions: []) == nil)
    }

    @Test func clearPersistsAndSharedValidatorSeesGlobalCollisions() throws {
        let cleared = try configuration(["Quick Capture": CommandBinding(key: "", modifiers: [])])
        #expect(CommandShortcuts.binding("Quick Capture", configuration: cleared).key.isEmpty)
        let value = CommandBinding(key: "k", modifiers: ["command", "control"], keyCode: 40)
        let saved = try configuration(["Main Window": value])
        var action = DraftAction(name: "Imported", steps: [])
        action.shortcut = " K "; action.shortcutModifiers = ["CONTROL", "command", "control"]
        #expect(ActionShortcut.conflict(for: action, in: [], commands: CommandShortcuts.bindings(configuration: saved)) == "Shortcut conflicts with Main Window.")
        #expect(GlobalShortcuts.conflict(name: "Capture Clipboard", binding: value, configuration: saved, actions: []) == "Shortcut conflicts with Main Window.")
        #expect(action.shortcut == " K ")
    }

    @Test func invalidNewAssignmentsAndActionConflictsAreRejected() {
        #expect(GlobalShortcuts.conflict(name: "Main Window", binding: CommandBinding(key: "k", modifiers: ["shift"]), configuration: "{}", actions: []) != nil)
        #expect(GlobalShortcuts.conflict(name: "Main Window", binding: CommandBinding(key: "k", modifiers: ["command"], keyCode: 128), configuration: "{}", actions: []) != nil)
        #expect(GlobalShortcuts.conflict(name: "Main Window", binding: CommandBinding(key: "many", modifiers: ["command"]), configuration: "{}", actions: []) != nil)
        #expect(GlobalShortcuts.conflict(name: "Main Window", binding: CommandBinding(key: "q", modifiers: ["command"]), configuration: "{}", actions: []) == "Shortcut conflicts with Quit.")
        var action = DraftAction(name: "Existing action", steps: [])
        action.shortcut = "k"; action.shortcutModifiers = ["control", "option"]
        #expect(GlobalShortcuts.conflict(name: "Main Window", binding: CommandBinding(key: "K", modifiers: ["option", "control"]), configuration: "{}", actions: [action]) == "Shortcut conflicts with action “Existing action”.")
    }
}
