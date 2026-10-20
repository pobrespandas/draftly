import Foundation

public indirect enum ThemeJSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Decimal), string(String), array([ThemeJSONValue]), object([String: ThemeJSONValue])

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let result = try? value.decode(Bool.self) { self = .bool(result) }
        else if let result = try? value.decode(Decimal.self) { self = .number(result) }
        else if let result = try? value.decode(String.self) { self = .string(result) }
        else if let result = try? value.decode([ThemeJSONValue].self) { self = .array(result) }
        else { self = .object(try value.decode([String: ThemeJSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let result): try value.encode(result)
        case .number(let result): try value.encode(result)
        case .string(let result): try value.encode(result)
        case .array(let result): try value.encode(result)
        case .object(let result): try value.encode(result)
        }
    }
}

public struct EditorThemeDefinition: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = "New Theme"
    public var foreground = "202020"
    public var background = "FFFFFF"
    public var heading = "007AFF"
    public var isDark = false
    public var unknownFields: [String: ThemeJSONValue] = [:]

    public init(id: UUID = UUID(), name: String = "New Theme", foreground: String = "202020", background: String = "FFFFFF", heading: String = "007AFF", isDark: Bool = false, unknownFields: [String: ThemeJSONValue] = [:]) {
        self.id = id; self.name = name; self.foreground = foreground; self.background = background
        self.heading = heading; self.isDark = isDark; self.unknownFields = unknownFields
    }

    private static let keys: Set<String> = ["id", "name", "foreground", "background", "heading", "isDark"]
    public init(from decoder: Decoder) throws {
        var fields = try [String: ThemeJSONValue](from: decoder)
        func required(_ key: String) throws -> String {
            guard case .string(let value) = fields[key] else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "The theme requires \(key)."))
            }
            return value
        }
        guard let identity = UUID(uuidString: try required("id")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "The theme ID is invalid."))
        }
        id = identity; name = try required("name")
        foreground = try required("foreground"); background = try required("background"); heading = try required("heading")
        guard case .bool(let dark) = fields["isDark"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "The theme requires isDark."))
        }
        isDark = dark
        for key in Self.keys { fields.removeValue(forKey: key) }
        unknownFields = fields
    }
    public func encode(to encoder: Encoder) throws {
        var fields = unknownFields
        fields["id"] = .string(id.uuidString); fields["name"] = .string(name)
        fields["foreground"] = .string(foreground); fields["background"] = .string(background)
        fields["heading"] = .string(heading); fields["isDark"] = .bool(isDark)
        try fields.encode(to: encoder)
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name != "System" else {
            throw DraftlyError.message("Use a nonempty theme name other than System.")
        }
        for color in [foreground, background, heading] {
            let value = color.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            guard value.count == 6, value.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
                throw DraftlyError.message("Use six hexadecimal digits for each theme color.")
            }
        }
    }
}
