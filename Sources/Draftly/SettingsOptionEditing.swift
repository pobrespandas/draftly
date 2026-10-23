import Foundation
import DraftlyCore

enum SettingsOptionEditing {
    static func markdownOption(_ key: String, enabled: Bool, configuration: String) throws -> String {
        var values = try JSONDecoder().decode([String: JSONValue].self, from: Data(configuration.utf8))
        values[key] = .bool(enabled)
        return String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }
}
