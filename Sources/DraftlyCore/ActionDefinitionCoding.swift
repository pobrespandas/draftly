import Foundation

private enum UnknownActionFields {
    private struct FieldKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    static func read<Key: CodingKey & CaseIterable>(from decoder: Decoder, known: Key.Type) throws -> [String: JSONValue] {
        let names = Set(Key.allCases.map(\.stringValue))
        let fields = try decoder.container(keyedBy: FieldKey.self)
        var result: [String: JSONValue] = [:]
        for key in fields.allKeys where !names.contains(key.stringValue) {
            result[key.stringValue] = try fields.decode(JSONValue.self, forKey: key)
        }
        return result
    }

    static func write<Key: CodingKey & CaseIterable>(_ values: [String: JSONValue], to encoder: Encoder, known: Key.Type) throws {
        let names = Set(Key.allCases.map(\.stringValue))
        var fields = encoder.container(keyedBy: FieldKey.self)
        for (name, value) in values where !names.contains(name) {
            try fields.encode(value, forKey: FieldKey(stringValue: name))
        }
    }
}

extension DraftAction {
    private enum KnownKey: String, CodingKey, CaseIterable {
        case options, id, name, symbol, group, shortcut, shortcutModifiers, afterSuccess
        case configuredValues, steps, sourceURL, rawPayload, scriptMetadata
    }

    public init(from decoder: Decoder) throws {
        let known = try decoder.container(keyedBy: KnownKey.self)
        options = try known.decodeIfPresent(ActionPresentation.self, forKey: .options)
        id = try known.decode(UUID.self, forKey: .id)
        name = try known.decode(String.self, forKey: .name)
        symbol = try known.decode(String.self, forKey: .symbol)
        group = try known.decode(String.self, forKey: .group)
        shortcut = try known.decode(String.self, forKey: .shortcut)
        shortcutModifiers = try known.decodeIfPresent([String].self, forKey: .shortcutModifiers)
        afterSuccess = try known.decode(String.self, forKey: .afterSuccess)
        configuredValues = try known.decode([String: String].self, forKey: .configuredValues)
        steps = try known.decode([ActionStep].self, forKey: .steps)
        sourceURL = try known.decodeIfPresent(String.self, forKey: .sourceURL)
        rawPayload = try known.decodeIfPresent(String.self, forKey: .rawPayload)
        scriptMetadata = try known.decodeIfPresent([String: String].self, forKey: .scriptMetadata)
        unknownFields = try UnknownActionFields.read(from: decoder, known: KnownKey.self)
    }

    public func encode(to encoder: Encoder) throws {
        var known = encoder.container(keyedBy: KnownKey.self)
        try known.encodeIfPresent(options, forKey: .options)
        try known.encode(id, forKey: .id)
        try known.encode(name, forKey: .name)
        try known.encode(symbol, forKey: .symbol)
        try known.encode(group, forKey: .group)
        try known.encode(shortcut, forKey: .shortcut)
        try known.encodeIfPresent(shortcutModifiers, forKey: .shortcutModifiers)
        try known.encode(afterSuccess, forKey: .afterSuccess)
        try known.encode(configuredValues, forKey: .configuredValues)
        try known.encode(steps, forKey: .steps)
        try known.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try known.encodeIfPresent(rawPayload, forKey: .rawPayload)
        try known.encodeIfPresent(scriptMetadata, forKey: .scriptMetadata)
        try UnknownActionFields.write(unknownFields, to: encoder, known: KnownKey.self)
    }
}

extension ActionStep {
    private enum KnownKey: String, CodingKey, CaseIterable { case id, type, values, isEnabled }

    public init(from decoder: Decoder) throws {
        let known = try decoder.container(keyedBy: KnownKey.self)
        id = try known.decode(UUID.self, forKey: .id)
        type = try known.decode(String.self, forKey: .type)
        values = try known.decode([String: String].self, forKey: .values)
        isEnabled = try known.decodeIfPresent(Bool.self, forKey: .isEnabled)
        unknownFields = try UnknownActionFields.read(from: decoder, known: KnownKey.self)
    }

    public func encode(to encoder: Encoder) throws {
        var known = encoder.container(keyedBy: KnownKey.self)
        try known.encode(id, forKey: .id)
        try known.encode(type, forKey: .type)
        try known.encode(values, forKey: .values)
        try known.encodeIfPresent(isEnabled, forKey: .isEnabled)
        try UnknownActionFields.write(unknownFields, to: encoder, known: KnownKey.self)
    }
}

extension ActionPresentation {
    private enum KnownKey: String, CodingKey, CaseIterable {
        case description, showInList, showInBar, showInSearch, confirmBeforeRun
        case notifyOnSuccess, notifyOnError, addTags, removeTags, flagAfterSuccess, section, order
    }

    public init(from decoder: Decoder) throws {
        let known = try decoder.container(keyedBy: KnownKey.self)
        description = try known.decode(String.self, forKey: .description)
        showInList = try known.decode(Bool.self, forKey: .showInList)
        showInBar = try known.decode(Bool.self, forKey: .showInBar)
        showInSearch = try known.decode(Bool.self, forKey: .showInSearch)
        confirmBeforeRun = try known.decode(Bool.self, forKey: .confirmBeforeRun)
        notifyOnSuccess = try known.decode(Bool.self, forKey: .notifyOnSuccess)
        notifyOnError = try known.decode(Bool.self, forKey: .notifyOnError)
        addTags = try known.decode([String].self, forKey: .addTags)
        removeTags = try known.decode([String].self, forKey: .removeTags)
        flagAfterSuccess = try known.decodeIfPresent(Int.self, forKey: .flagAfterSuccess)
        section = try known.decode(String.self, forKey: .section)
        order = try known.decode(Int.self, forKey: .order)
        unknownFields = try UnknownActionFields.read(from: decoder, known: KnownKey.self)
    }

    public func encode(to encoder: Encoder) throws {
        var known = encoder.container(keyedBy: KnownKey.self)
        try known.encode(description, forKey: .description)
        try known.encode(showInList, forKey: .showInList)
        try known.encode(showInBar, forKey: .showInBar)
        try known.encode(showInSearch, forKey: .showInSearch)
        try known.encode(confirmBeforeRun, forKey: .confirmBeforeRun)
        try known.encode(notifyOnSuccess, forKey: .notifyOnSuccess)
        try known.encode(notifyOnError, forKey: .notifyOnError)
        try known.encode(addTags, forKey: .addTags)
        try known.encode(removeTags, forKey: .removeTags)
        try known.encodeIfPresent(flagAfterSuccess, forKey: .flagAfterSuccess)
        try known.encode(section, forKey: .section)
        try known.encode(order, forKey: .order)
        try UnknownActionFields.write(unknownFields, to: encoder, known: KnownKey.self)
    }
}
