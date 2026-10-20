import Foundation

public enum GlobalShortcuts {
    public static let names = ["Main Window", "Quick Capture", "Capture Clipboard"]

    public static func conflict(name: String, binding: CommandBinding, configuration: String,
                                actions: [DraftAction]) -> String? {
        if binding.key.isEmpty { return nil }
        let normalized = ActionShortcut(key: binding.key, modifiers: binding.modifiers)
        guard !normalized.modifiers.isDisjoint(with: ["command", "control", "option"]) else {
            return "Use Command, Control, or Option for a global shortcut."
        }
        guard binding.keyCode.map({ $0 < 128 }) ?? true else { return "This key is not supported." }
        var action = DraftAction(name: name, steps: [])
        action.shortcut = binding.key
        action.shortcutModifiers = binding.modifiers
        return ActionShortcut.conflict(for: action, in: actions,
            commands: CommandShortcuts.bindings(configuration: configuration).filter { $0.0 != name })
    }
}
