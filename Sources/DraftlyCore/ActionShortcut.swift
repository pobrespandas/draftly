import Foundation

public struct ActionShortcut: Equatable, Hashable {
    private static let modifierSymbols = [("control", "⌃"), ("option", "⌥"), ("shift", "⇧"), ("command", "⌘")]
    private static var supportedModifiers: Set<String> { Set(modifierSymbols.map(\.0)) }
    public let key: String
    public let modifiers: Set<String>
    public init(key: String, modifiers: [String]?) {
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.modifiers = Set((modifiers ?? ["command", "option"]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }
    public init(_ action: DraftAction) { self.init(key: action.shortcut, modifiers: action.shortcutModifiers) }
    public var displayLabel: String? {
        guard key.count == 1, modifiers.isSubset(of: Self.supportedModifiers) else { return nil }
        return Self.modifierSymbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + key.uppercased()
    }
    public static func conflict(for action: DraftAction, in actions: [DraftAction], commands: [(String, String, [String])]? = nil) -> String? {
        let shortcut = Self(action)
        if shortcut.key.isEmpty { return nil }
        guard shortcut.key.count == 1, shortcut.modifiers.isSubset(of: supportedModifiers) else {
            return "Use one key and the supported modifier keys."
        }
        let commands = commands ?? CommandShortcuts.bindings()
        if let command = commands.first(where: { Self(key: $0.1, modifiers: $0.2) == shortcut }) {
            return "Shortcut conflicts with \(command.0)."
        }
        if let other = actions.first(where: { $0.id != action.id && !$0.shortcut.isEmpty && Self($0) == shortcut }) {
            return "Shortcut conflicts with action “\(other.name)”."
        }
        return nil
    }
}
