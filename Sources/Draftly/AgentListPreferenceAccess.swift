import Foundation
import AgentContracts
import DraftlyCore

// List defaults are device state, independent from an applied Workspace.
@MainActor enum AgentListPreferenceAccess {
    static let supportedIDs: Set<String> = ["list.showPreview", "list.previewLines", "list.showTags", "list.showDate",
        "list.searchTitlesOnly", "list.caseSensitiveSearch", "list.previewSearchMatches", "list.showLastAction", "list.highlightFlagged"]
    private static let legacyIDs: Set<String> = ["list.showPreview", "list.previewLines", "list.showTags", "list.showDate"]

    struct Change {
        let data: Data
        let legacyKey: String?
        let legacyValue: AgentJSONValue?
    }

    static func prepare(address item: AgentJSONValue, value: AgentJSONValue?, configuration: Data?) throws -> Change {
        let field = try supportedField(item)
        if let value { try field.value.validate(value) }
        let original = configuration ?? Data("{}".utf8)
        // Keep malformed stores unchanged instead of replacing other fields with defaults.
        _ = try JSONDecoder().decode(DraftListOptions.self, from: original)
        var values = try JSONDecoder().decode([String: AgentJSONValue].self, from: original)
        let name = String(field.id.dropFirst("list.".count))
        if let value { values[name] = value } else { values.removeValue(forKey: name) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Change(data: try encoder.encode(values), legacyKey: legacyIDs.contains(field.id) ? field.id : nil,
            legacyValue: value)
    }

    static func read(address item: AgentJSONValue, defaults: UserDefaults) throws -> AgentPreferenceReading {
        let field = try supportedField(item)
        let name = String(field.id.dropFirst("list.".count))
        let effective = try JSONDecoder().decode([String: AgentJSONValue].self,
            from: JSONEncoder().encode(DraftListDefaults.load(defaults: defaults)))
        guard let value = effective[name] else { throw AgentErrorCode.unavailable }
        if legacyIDs.contains(field.id), let raw = defaults.object(forKey: field.id) {
            let typed = try? JSONDecoder().decode(AgentJSONValue.self,
                from: JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]))
            let valid = typed.map { (try? field.value.validate($0)) != nil } ?? false
            return .init(effectiveValue: value, origin: valid ? "stored" : "invalid", hasOverride: true)
        }
        guard let raw = defaults.object(forKey: "list.options") else {
            return .init(effectiveValue: value, origin: "default", hasOverride: false)
        }
        guard let data = raw as? Data,
              let object = try? JSONDecoder().decode([String: AgentJSONValue].self, from: data),
              (try? JSONDecoder().decode(DraftListOptions.self, from: data)) != nil else {
            return .init(effectiveValue: value, origin: "invalid", hasOverride: true)
        }
        let overridden = object[name] != nil
        return .init(effectiveValue: value, origin: overridden ? "stored" : "default", hasOverride: overridden)
    }

    private static func supportedField(_ item: AgentJSONValue) throws -> AgentPreferenceField {
        let registry = try AgentPreferenceCatalog.make()
        let address = try registry.address(item)
        guard supportedIDs.contains(address.id) else { throw AgentErrorCode.unavailable }
        return try registry.field(address.id)
    }
}
