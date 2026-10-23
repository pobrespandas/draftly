import Foundation
import DraftlyCore

enum SettingsOptionEditing {
    static func markdownOption(_ key: String, enabled: Bool, configuration: String) throws -> String {
        var values = try JSONDecoder().decode([String: JSONValue].self, from: Data(configuration.utf8))
        values[key] = .bool(enabled)
        return String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }
    static func syntaxFeature(_ feature: String, syntax: String, enabled: Bool, configuration: String) throws -> String {
        let failure = DraftlyError.message("The saved syntax feature options are invalid. They were kept unchanged.")
        guard let fields = try? JSONDecoder().decode([String: JSONValue].self, from: Data(configuration.utf8)) else {
            throw failure
        }
        if let stored = fields[syntax] {
            guard case .object = stored else { throw failure }
        }
        return SyntaxFeaturePreferences.setting(enabled, feature: feature, syntax: syntax, encoded: configuration)
    }

    static func command(_ name: String, binding: CommandBinding?, configuration: String) throws -> String {
        var values = try JSONDecoder().decode([String: JSONValue].self, from: Data(configuration.utf8))
        if let binding {
            var fields: [String: JSONValue] = [:]
            if case .object(let stored) = values[name] { fields = stored }
            let data = try JSONEncoder().encode(binding)
            let updated = try JSONDecoder().decode([String: JSONValue].self, from: data)
            fields.merge(updated) { _, new in new }
            if binding.keyCode == nil { fields.removeValue(forKey: "keyCode") }
            values[name] = .object(fields)
        } else {
            values.removeValue(forKey: name)
        }
        return String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }

}
