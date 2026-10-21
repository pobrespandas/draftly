import Foundation

public struct EditorThemeDefinition: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = "New Theme"
    public var foreground = "202020"
    public var background = "FFFFFF"
    public var heading = "007AFF"
    public var isDark = false
    public var type = "custom"
    public var unknownFields: [String: ThemeJSONValue] = [:]

    public init(id: UUID = UUID(), name: String = "New Theme", foreground: String = "202020", background: String = "FFFFFF", heading: String = "007AFF", isDark: Bool = false, type: String = "custom", unknownFields: [String: ThemeJSONValue] = [:]) {
        self.id = id; self.name = name; self.foreground = foreground; self.background = background
        self.heading = heading; self.isDark = isDark; self.type = type; self.unknownFields = unknownFields
    }

    private static let keys: Set<String> = ["id", "name", "foreground", "background", "heading", "isDark", "type"]
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
        if let value = fields["type"] {
            guard case .string(let value) = value else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "The theme type is invalid."))
            }
            type = value
        } else { type = "custom" }
        for key in Self.keys { fields.removeValue(forKey: key) }
        unknownFields = fields
    }
    public func encode(to encoder: Encoder) throws {
        var fields = unknownFields
        fields["id"] = .string(id.uuidString); fields["name"] = .string(name)
        fields["foreground"] = .string(foreground); fields["background"] = .string(background)
        fields["heading"] = .string(heading); fields["isDark"] = .bool(isDark)
        if type != "custom" { fields["type"] = .string(type) }
        else { fields.removeValue(forKey: "type") }
        try fields.encode(to: encoder)
    }
    public func validate() throws {
        guard ["custom", "file"].contains(type) else {
            throw DraftlyError.message("The theme type is invalid.")
        }
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
