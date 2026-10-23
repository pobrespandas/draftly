import Foundation
import DraftlyCore

enum SettingsOptionEditing {
    static func markdownOption(_ key: String, enabled: Bool, configuration: String) throws -> String {
        var values = try JSONDecoder().decode([String: JSONValue].self, from: Data(configuration.utf8))
        values[key] = .bool(enabled)
        return String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
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
