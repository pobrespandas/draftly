import Foundation

public struct CommandBinding: Codable, Equatable {
    public var key: String
    public var modifiers: [String]
    public var keyCode: UInt32?
    public init(key: String, modifiers: [String], keyCode: UInt32? = nil) { self.key = key; self.modifiers = modifiers; self.keyCode = keyCode }
}

public enum CommandShortcuts {
    public static let storageKey = "commands.bindings"
    public static let editable = ["New Draft", "New Window", "Import", "Filters", "Draft List", "Actions", "Command Palette", "Quick Search", "Markdown Preview", "Main Window", "Quick Capture", "Capture Clipboard"]
    public static let defaults: [(String, String, [String])] = [
        ("Main Window", "", []), ("Capture Clipboard", "", []),
        ("New Draft", "n", ["command"]), ("New Window", "n", ["command", "shift"]),
        ("Quick Capture", "n", ["command", "control", "option"]), ("Import", "o", ["command"]),
        ("New with Clipboard", "n", ["option", "command"]),
        ("New with Dictation", "n", ["option", "shift", "command"]),
        ("Move to Inbox", "i", ["shift", "command"]), ("Move to Archive", "a", ["shift", "command"]),
        ("Move to Trash", "\u{8}", ["option", "shift", "command"]),
        ("Save Version", "s", ["command"]), ("Get Info", "i", ["option", "command"]),
        ("Previous Draft", "\u{F700}", ["control", "shift"]), ("Next Draft", "\u{F701}", ["control", "shift"]),
        ("Print", "p", ["command"]), ("Editor Settings", ",", ["option", "command"]),
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
        let saved = storedBindings(text)
        return defaults.map { name, key, modifiers in
            guard editable.contains(name), let value = saved[name], (value.key.count == 1 || value.key.isEmpty),
                  Set(value.modifiers).isSubset(of: ["command", "option", "control", "shift"]) else { return (name, key, modifiers) }
            return (name, value.key.lowercased(), value.modifiers)
        }
    }
    public static func binding(_ name: String, configuration: String) -> CommandBinding {
        let value = bindings(configuration: configuration).first { $0.0 == name }!
        let saved = storedBindings(configuration)
        let stored = saved[name]
        let matches = stored?.key.lowercased() == value.1 && Set(stored?.modifiers ?? []) == Set(value.2)
        return CommandBinding(key: value.1, modifiers: value.2, keyCode: matches ? stored?.keyCode : nil)
    }
    private static func storedBindings(_ configuration: String) -> [String: CommandBinding] {
        let values = (try? JSONDecoder().decode([String: JSONValue].self,
            from: Data(configuration.utf8))) ?? [:]
        return values.compactMapValues { value in
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return try? JSONDecoder().decode(CommandBinding.self, from: data)
        }
    }

}
