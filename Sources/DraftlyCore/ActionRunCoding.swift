import Foundation

extension ActionRun {
    private enum KnownKey: String, CodingKey, CaseIterable {
        case id, date, actionName, status, message, noteID, actionID
    }
    private struct FieldKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let known = try decoder.container(keyedBy: KnownKey.self)
        id = try known.decode(UUID.self, forKey: .id)
        date = try known.decode(Date.self, forKey: .date)
        actionName = try known.decode(String.self, forKey: .actionName)
        status = try known.decode(String.self, forKey: .status)
        message = try known.decode(String.self, forKey: .message)
        noteID = try known.decodeIfPresent(UUID.self, forKey: .noteID)
        actionID = try known.decodeIfPresent(UUID.self, forKey: .actionID)
        let fields = try decoder.container(keyedBy: FieldKey.self)
        for key in fields.allKeys where KnownKey(rawValue: key.stringValue) == nil {
            unknownFields[key.stringValue] = try fields.decode(JSONValue.self, forKey: key)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var known = encoder.container(keyedBy: KnownKey.self)
        try known.encode(id, forKey: .id)
        try known.encode(date, forKey: .date)
        try known.encode(actionName, forKey: .actionName)
        try known.encode(status, forKey: .status)
        try known.encode(message, forKey: .message)
        try known.encodeIfPresent(noteID, forKey: .noteID)
        try known.encodeIfPresent(actionID, forKey: .actionID)
        var fields = encoder.container(keyedBy: FieldKey.self)
        for (name, value) in unknownFields where KnownKey(rawValue: name) == nil {
            if let key = FieldKey(stringValue: name) { try fields.encode(value, forKey: key) }
        }
    }
}
