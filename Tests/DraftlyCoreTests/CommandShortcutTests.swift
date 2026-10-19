import Foundation
import Testing
@testable import DraftlyCore

@Suite("Command shortcut configuration")
struct CommandShortcutTests {
    @Test func configuredCommandsAndActionsUseTheSameConflictRules() throws {
        let data = try JSONEncoder().encode(["Quick Search": CommandBinding(key: "k", modifiers: ["shift", "command"])])
        let configuration = String(decoding: data, as: UTF8.self)
        let commands = CommandShortcuts.bindings(configuration: configuration)
        var action = DraftAction(name: "Collision", steps: []); action.shortcut = "K"; action.shortcutModifiers = ["command", "shift"]
        #expect(ActionShortcut.conflict(for: action, in: [], commands: commands) == "Shortcut conflicts with Quick Search.")
        let binding = CommandShortcuts.binding("Quick Search", configuration: configuration)
        #expect(binding.key == "k")
        #expect(Set(binding.modifiers) == ["command", "shift"])
        action.shortcut = "f"
        #expect(ActionShortcut.conflict(for: action, in: [], commands: commands) == nil)
    }
    @Test func malformedOrUnknownOverridesDoNotReplaceSystemCommands() {
        let config = "{\"Quit\":{\"key\":\"x\",\"modifiers\":[\"command\"]},\"Quick Search\":{\"key\":\"many\",\"modifiers\":[\"command\"]}}"
        #expect(CommandShortcuts.binding("Quit", configuration: config).key == "q")
        #expect(CommandShortcuts.binding("Quick Search", configuration: config).key == "f")
        #expect(CommandShortcuts.binding("New Draft", configuration: "invalid").key == "n")
    }
}
