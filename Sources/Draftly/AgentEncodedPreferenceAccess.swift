import Foundation
import AgentContracts
import DraftlyCore

// Prepares changes to known encoded fields. The caller owns grants, CAS and commit.
@MainActor enum AgentEncodedPreferenceAccess {
    struct Change {
        let storageKey: String
        let configuration: String
        let requiresHumanApproval: Bool
    }

    static func prepare(address item: AgentJSONValue, value: AgentJSONValue?, configuration: String,
                        syntax: SyntaxDefinition? = nil, actions: [DraftAction] = []) throws -> Change {
        let registry = try AgentPreferenceCatalog.make()
        let address = try registry.address(item)
        let field = try registry.field(address.id)
        guard field.writable else { throw AgentErrorCode.invalidInput }
        if let value { try field.value.validate(value) }
        let id = address.id
        let key: String
        let updated: String
        if id.hasPrefix("markdown.multi.") || id.hasPrefix("markdown.github.") {
            let parts = id.split(separator: ".").map(String.init)
            key = parts[1] == "multi" ? MarkdownPreferences.multiKey : MarkdownPreferences.githubKey
            if let value {
                guard case .bool(let enabled) = value else { throw AgentErrorCode.invalidInput }
                updated = try SettingsOptionEditing.markdownOption(parts[2], enabled: enabled, configuration: configuration)
            } else { updated = try removing(parts[2], from: configuration) }
        } else if id.hasPrefix("syntax.") {
            guard let syntax else { throw AgentErrorCode.notFound }
            try validateSyntax(address, definition: syntax)
            let name = String(id.dropFirst("syntax.".count))
            if name == "feature" {
                guard let feature = address.feature, syntax.features.contains(where: { $0.id == feature }) else {
                    throw AgentErrorCode.notFound
                }
                key = SyntaxFeaturePreferences.key
                if let value {
                    guard case .bool(let enabled) = value else { throw AgentErrorCode.invalidInput }
                    updated = try SettingsOptionEditing.syntaxFeature(feature, syntax: syntax.name, enabled: enabled, configuration: configuration)
                } else { updated = try removing(feature, from: configuration, syntax: syntax.name) }
            } else {
                (key, updated) = try syntaxEdit(name, value: value, syntax: syntax.name, configuration: configuration)
            }
        } else if id == "commands.shortcut" {
            guard let command = address.command else { throw AgentErrorCode.invalidInput }
            key = CommandShortcuts.storageKey
            let binding: CommandBinding?
            if let value {
                binding = try JSONDecoder().decode(CommandBinding.self, from: JSONEncoder().encode(value))
                guard let binding, binding.key.isEmpty || binding.key.count == 1,
                      Set(binding.modifiers).count == binding.modifiers.count else { throw AgentErrorCode.invalidInput }
            } else { binding = nil }
            if let binding {
                updated = try SettingsOptionEditing.command(command, binding: binding, configuration: configuration)
            } else {
                updated = try removing(["key", "modifiers", "keyCode"], from: configuration, syntax: command)
            }
            // Reset can re-enable a default shortcut. Check the resulting effective binding too.
            let effective = CommandShortcuts.binding(command, configuration: updated)
            let conflict: String?
            if GlobalShortcuts.names.contains(command) {
                conflict = GlobalShortcuts.conflict(name: command, binding: effective, configuration: updated, actions: actions)
            } else {
                var action = DraftAction(name: command, steps: [])
                action.shortcut = effective.key; action.shortcutModifiers = effective.modifiers
                conflict = effective.key.isEmpty ? nil : ActionShortcut.conflict(for: action, in: actions,
                    commands: CommandShortcuts.bindings(configuration: updated).filter { $0.0 != command })
            }
            guard conflict == nil else { throw AgentErrorCode.invalidInput }
        } else { throw AgentErrorCode.unavailable }
        return Change(storageKey: key, configuration: updated,
            requiresHumanApproval: try registry.requiresHumanApproval(item))
    }

    static func read(address item: AgentJSONValue, configuration: String,
                     syntax: SyntaxDefinition? = nil, inherited: AgentJSONValue? = nil) throws -> AgentPreferenceReading {
        let registry = try AgentPreferenceCatalog.make()
        let address = try registry.address(item), field = try registry.field(address.id)
        let path: [String]
        let fallback: AgentJSONValue
        let origin: String
        if address.id.hasPrefix("markdown.multi.") || address.id.hasPrefix("markdown.github.") {
            path = [String(address.id.split(separator: ".")[2])]
            guard let value = field.defaultValue else { throw AgentErrorCode.unavailable }
            fallback = value; origin = "default"
        } else if address.id.hasPrefix("syntax.") {
            guard let syntax else { throw AgentErrorCode.notFound }
            try validateSyntax(address, definition: syntax)
            let name = String(address.id.dropFirst("syntax.".count))
            if name == "feature" {
                guard let feature = address.feature,
                      let declared = syntax.features.first(where: { $0.id == feature }) else { throw AgentErrorCode.notFound }
                path = [syntax.name, feature]; fallback = .bool(declared.defaultValue); origin = "default"
            } else {
                path = name == "indentation" ? [syntax.name] : [syntax.name, name]
                switch field.defaultSource {
                case .literal:
                    guard let value = field.defaultValue else { throw AgentErrorCode.unavailable }
                    fallback = value; origin = "default"
                case .inherited:
                    guard let inherited else { throw AgentErrorCode.unavailable }
                    try field.value.validate(inherited)
                    fallback = inherited; origin = "inherited"
                case .system: fallback = .null; origin = "system"
                case .contextual: throw AgentErrorCode.unavailable
                }
            }
        } else if address.id == "commands.shortcut" {
            guard let command = address.command else { throw AgentErrorCode.invalidInput }
            path = [command]
            fallback = try bindingValue(CommandShortcuts.binding(command, configuration: "{}"))
            origin = "default"
        } else { throw AgentErrorCode.unavailable }
        guard let root = try? JSONDecoder().decode([String: AgentJSONValue].self, from: Data(configuration.utf8)) else {
            return AgentPreferenceReading(effectiveValue: fallback, origin: "invalid", hasOverride: true)
        }
        var object = root
        for component in path.dropLast() {
            guard let stored = object[component] else { return AgentPreferenceReading(effectiveValue: fallback, origin: origin, hasOverride: false) }
            guard case .object(let fields) = stored else { return AgentPreferenceReading(effectiveValue: fallback, origin: "invalid", hasOverride: true) }
            object = fields
        }
        guard let stored = object[path.last!] else { return AgentPreferenceReading(effectiveValue: fallback, origin: origin, hasOverride: false) }
        do {
            let value: AgentJSONValue
            if address.id == "commands.shortcut" {
                if case .object(let fields) = stored,
                   ["key", "modifiers", "keyCode"].allSatisfy({ fields[$0] == nil }) {
                    return AgentPreferenceReading(effectiveValue: fallback, origin: origin, hasOverride: false)
                }
                let binding = try JSONDecoder().decode(CommandBinding.self, from: JSONEncoder().encode(stored))
                guard binding.key.isEmpty || binding.key.count == 1 else { throw AgentErrorCode.invalidInput }
                // Ignore imported additional fields, as the existing consumer does.
                try field.value.validate(try bindingValue(binding))
                guard let command = address.command else { throw AgentErrorCode.invalidInput }
                value = try bindingValue(CommandShortcuts.binding(command, configuration: configuration))
            } else { value = stored }
            try field.value.validate(value)
            return AgentPreferenceReading(effectiveValue: value, origin: "stored", hasOverride: true)
        } catch { return AgentPreferenceReading(effectiveValue: fallback, origin: "invalid", hasOverride: true) }
    }

    private static func bindingValue(_ binding: CommandBinding) throws -> AgentJSONValue {
        try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(binding))
    }

    private static func validateSyntax(_ address: AgentPreferenceAddress, definition: SyntaxDefinition) throws {
        switch address.syntax {
        case .builtIn(let name):
            guard definition.type == "builtIn", definition.name == name else { throw AgentErrorCode.notFound }
        case .installed(let uuid):
            guard definition.type != "builtIn", definition.id == uuid else { throw AgentErrorCode.notFound }
        case nil: throw AgentErrorCode.invalidInput
        }
        if address.id == "syntax.feature" {
            guard let feature = address.feature, definition.features.contains(where: { $0.id == feature }) else {
                throw AgentErrorCode.notFound
            }
        }
    }

    private static func syntaxEdit(_ name: String, value: AgentJSONValue?, syntax: String,
                                   configuration: String) throws -> (String, String) {
        if name == "indentation" {
            guard EditorIndentationPreferences.isValid(configuration) else { throw AgentErrorCode.invalidInput }
            if let value {
                guard case .string(let name) = value, let style = EditorIndentationStyle(rawValue: name) else {
                    throw AgentErrorCode.invalidInput
                }
                return (EditorIndentationPreferences.key, EditorIndentationPreferences.setting(style, for: syntax, encoded: configuration))
            }
            return (EditorIndentationPreferences.key, try removing(syntax, from: configuration))
        }
        let key: String
        if ["fontName", "fontSize", "monospaceFontName"].contains(name) {
            key = EditorSyntaxFontPreferences.key
        } else if EditorSyntaxLayoutPreferences.Field(rawValue: name) != nil {
            key = EditorSyntaxLayoutPreferences.key
        } else if EditorTextInputPreferences.Option(rawValue: name) != nil
                    || EditorTextInputPreferences.SystemOption(rawValue: name) != nil {
            key = EditorTextInputPreferences.key
        } else if EditorSyntaxDisplayPreferences.Option(rawValue: name) != nil {
            key = EditorSyntaxDisplayPreferences.key
        } else { throw AgentErrorCode.unavailable }
        guard let value else { return (key, try removing(name, from: configuration, syntax: syntax)) }
        let updated: String
        switch name {
        case "fontName", "monospaceFontName":
            guard case .string(let text) = value else { throw AgentErrorCode.invalidInput }
            updated = try name == "fontName"
                ? EditorSyntaxFontPreferences.settingName(text, for: syntax, encoded: configuration)
                : EditorSyntaxFontPreferences.settingMonospace(text, for: syntax, encoded: configuration)
        case "fontSize":
            updated = try EditorSyntaxFontPreferences.settingSize(number(value), for: syntax, encoded: configuration)
        default:
            if let field = EditorSyntaxLayoutPreferences.Field(rawValue: name) {
                updated = try EditorSyntaxLayoutPreferences.setting(field, value: number(value), for: syntax, encoded: configuration)
            } else if let option = EditorTextInputPreferences.Option(rawValue: name), case .bool(let enabled) = value {
                updated = try EditorTextInputPreferences.setting(option, enabled: enabled, for: syntax, encoded: configuration)
            } else if let option = EditorTextInputPreferences.SystemOption(rawValue: name) {
                let enabled: Bool?
                switch value { case .null: enabled = nil; case .bool(let flag): enabled = flag
                default: throw AgentErrorCode.invalidInput }
                updated = try EditorTextInputPreferences.setting(option, enabled: enabled, for: syntax, encoded: configuration)
            } else if let option = EditorSyntaxDisplayPreferences.Option(rawValue: name), case .bool(let enabled) = value {
                updated = try EditorSyntaxDisplayPreferences.setting(option, enabled: enabled, for: syntax, encoded: configuration)
            } else { throw AgentErrorCode.invalidInput }
        }
        return (key, updated)
    }

    private static func number(_ value: AgentJSONValue) throws -> Double {
        switch value {
        case .integer(let value): Double(value)
        case .number(let value): NSDecimalNumber(decimal: value).doubleValue
        default: throw AgentErrorCode.invalidInput
        }
    }

    // Reset removes one reviewed override and retains all other saved fields.
    private static func removing(_ field: String, from configuration: String, syntax: String? = nil) throws -> String {
        try removing([field], from: configuration, syntax: syntax)
    }

    private static func removing(_ fieldsToRemove: [String], from configuration: String, syntax: String?) throws -> String {
        var object = try JSONDecoder().decode([String: JSONValue].self, from: Data(configuration.utf8))
        if let syntax {
            if let stored = object[syntax] {
                guard case .object(var fields) = stored else { throw AgentErrorCode.invalidInput }
                for field in fieldsToRemove { fields.removeValue(forKey: field) }
                if fields.isEmpty { object.removeValue(forKey: syntax) }
                else { object[syntax] = .object(fields) }
            }
        } else { for field in fieldsToRemove { object.removeValue(forKey: field) } }
        return String(decoding: try JSONEncoder().encode(object), as: UTF8.self)
    }
}
