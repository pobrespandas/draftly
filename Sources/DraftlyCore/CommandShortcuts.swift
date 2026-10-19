import Foundation

public struct CommandBinding: Codable, Equatable {
    public var key: String
    public var modifiers: [String]
    public init(key: String, modifiers: [String]) { self.key = key; self.modifiers = modifiers }
}

public enum CommandShortcuts {
    public static let storageKey = "commands.bindings"
    public static let editable = ["New Draft", "New Window", "Import", "Filters", "Draft List", "Actions", "Command Palette", "Quick Search", "Markdown Preview"]
    public static let defaults: [(String, String, [String])] = [
        ("New Draft", "n", ["command"]), ("New Window", "n", ["command", "shift"]),
        ("Quick Capture", "n", ["command", "control", "option"]), ("Import", "i", ["command", "shift"]),
        ("Filters", "1", ["command", "option"]), ("Draft List", "2", ["command", "option"]),
        ("Actions", "a", ["command", "option"]), ("Command Palette", "p", ["command", "shift"]),
        ("Quick Search", "f", ["command", "shift"]), ("Markdown Preview", "p", ["command", "option"]),
        ("Quit", "q", ["command"]), ("Close Window", "w", ["command"]), ("Settings", ",", ["command"]),
        ("Copy", "c", ["command"]), ("Cut", "x", ["command"]), ("Paste", "v", ["command"]),
        ("Select All", "a", ["command"]), ("Undo", "z", ["command"]), ("Redo", "z", ["command", "shift"]),
        ("Find", "f", ["command"]), ("Hide", "h", ["command"]), ("Minimize", "m", ["command"])
    ]
    public static func bindings(configuration: String? = nil) -> [(String, String, [String])] {
        let text = configuration ?? UserDefaults.standard.string(forKey: storageKey) ?? "{}"
        let saved = (try? JSONDecoder().decode([String: CommandBinding].self, from: Data(text.utf8))) ?? [:]
        return defaults.map { name, key, modifiers in
            guard editable.contains(name), let value = saved[name], value.key.count == 1,
                  Set(value.modifiers).isSubset(of: ["command", "option", "control", "shift"]) else { return (name, key, modifiers) }
            return (name, value.key.lowercased(), value.modifiers)
        }
    }
    public static func binding(_ name: String, configuration: String) -> CommandBinding {
        let value = bindings(configuration: configuration).first { $0.0 == name }!
        return CommandBinding(key: value.1, modifiers: value.2)
    }
}
