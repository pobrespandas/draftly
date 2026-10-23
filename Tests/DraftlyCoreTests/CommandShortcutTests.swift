import Foundation
import Testing
@testable import DraftlyCore

@Suite("Command shortcut configuration")
struct CommandShortcutTests {
    @Test func fileMenuCommandsReserveTheObservedBindingsWithoutChangingImportedActions() {
        let expected: [(String, String, [String])] = [
            ("Import", "o", ["command"]), ("New with Clipboard", "n", ["command", "option"]),
            ("New with Dictation", "n", ["command", "shift", "option"]),
            ("Move to Inbox", "i", ["command", "shift"]), ("Move to Archive", "a", ["command", "shift"]),
            ("Move to Trash", "\u{8}", ["command", "shift", "option"]),
            ("Save Version", "s", ["command"]), ("Get Info", "i", ["command", "option"]),
            ("Previous Draft", "\u{F700}", ["shift", "control"]), ("Next Draft", "\u{F701}", ["shift", "control"]),
            ("Print", "p", ["command"]), ("Editor Settings", ",", ["command", "option"])
        ]
        let commands = CommandShortcuts.bindings(configuration: "{}")
        #expect(Set(commands.map(\.0)).count == commands.count)
        for (name, key, modifiers) in expected {
            let binding = CommandShortcuts.binding(name, configuration: "{}")
            #expect(binding.key == key && Set(binding.modifiers) == Set(modifiers))
            var imported = DraftAction(name: "Imported neutral", steps: [])
            imported.shortcut = key; imported.shortcutModifiers = modifiers.reversed()
            let original = imported
            #expect(ActionShortcut.conflict(for: imported, in: [], commands: commands) == "Shortcut conflicts with \(name).")
            #expect(imported == original)
        }
        let configured = CommandShortcuts.binding("Import", configuration: #"{"Import":{"key":"x","modifiers":["command","control"]}}"#)
        #expect(configured.key == "x" && Set(configured.modifiers) == ["command", "control"])
    }
    @Test func actionLabelsUseNormalizedModifiersInMacOrder() {
        #expect(ActionShortcut(key: " K ", modifiers: nil).displayLabel == "⌥⌘K")
        #expect(ActionShortcut(key: "é", modifiers: [" SHIFT ", "command", "OPTION", "control", "shift"]).displayLabel == "⌃⌥⇧⌘É")
        #expect(ActionShortcut(key: "7", modifiers: []).displayLabel == "7")
    }

    @Test func invalidImportedShortcutsAreNotDisplayedAsWorkingBindings() {
        for shortcut in [ActionShortcut(key: " ", modifiers: nil),
                         ActionShortcut(key: "many", modifiers: ["command"]),
                         ActionShortcut(key: "k", modifiers: ["unsupported"])] {
            #expect(shortcut.displayLabel == nil)
        }
        var action = DraftAction(name: "Imported conflict", steps: [])
        action.shortcut = "K"; action.shortcutModifiers = ["command"]
        #expect(ActionShortcut(action).displayLabel == "⌘K")
        #expect(action.shortcut == "K" && action.shortcutModifiers == ["command"])
    }

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
    @Test func clearingAnEditableCommandDisablesOnlyThatCommand() {
        let configuration = #"{"Quick Search":{"key":"","modifiers":[]}}"#
        #expect(CommandShortcuts.binding("Quick Search", configuration: configuration).key.isEmpty)
        #expect(CommandShortcuts.binding("New Draft", configuration: configuration).key == "n")
        #expect(CommandShortcuts.binding("Quit", configuration: #"{"Quit":{"key":"","modifiers":[]}}"#).key == "q")
    }

    @Test func anUnknownMalformedEntryDoesNotDiscardValidShortcutSiblings() {
        let configuration = #"{"future":{"name":"café 🐼"},"Quick Search":{"key":"k","modifiers":["command","shift"],"keyCode":40,"future":true}}"#
        #expect(CommandShortcuts.binding("Quick Search", configuration: configuration)
            == CommandBinding(key: "k", modifiers: ["command", "shift"], keyCode: 40))
    }

}
