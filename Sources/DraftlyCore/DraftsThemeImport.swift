import Foundation

public enum DraftsThemeImport {
    public static let limitations = "Draftly applies supported editor scopes, colors, selection, and caret. Other interface colors and unsupported styling are preserved but are not applied."

    public static func applyingEditorChanges(_ value: EditorThemeDefinition) throws -> EditorThemeDefinition {
        guard case .object(var source) = value.unknownFields["draftsSource"] else { return value }
        try value.validate()
        let original = try decode(data: JSONEncoder().encode(ThemeJSONValue.object(source)))
        func hex(_ value: String) -> String { "#" + value.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
        func object(_ value: ThemeJSONValue?) -> [String: ThemeJSONValue] {
            if case .object(let result) = value { return result }; return [:]
        }
        var colors = object(source["colors"]), scopes = object(source["scopes"])
        var interface = object(colors["interface"])
        func setForeground(_ name: String, _ color: String) {
            var scope = object(scopes[name]), settings = object(scope["settings"])
            settings["foreground"] = .string(hex(color))
            scope["settings"] = .object(settings); scopes[name] = .object(scope)
        }
        if original.foreground != value.foreground {
            interface["textForeground"] = .string(hex(value.foreground))
            setForeground("text.normal", value.foreground)
        }
        if original.background != value.background { interface["textBackground"] = .string(hex(value.background)) }
        if original.heading != value.heading { setForeground(scopes["text.heading"] != nil ? "text.heading" : "text.header", value.heading) }
        if original.name != value.name { source["name"] = .string(value.name) }
        if original.isDark != value.isDark { source["isDark"] = .bool(value.isDark) }
        colors["interface"] = .object(interface); source["colors"] = .object(colors); source["scopes"] = .object(scopes)
        var result = value; result.unknownFields["draftsSource"] = .object(source)
        try result.validate()
        return result
    }

    public static func decode(data: Data, id: UUID = UUID()) throws -> EditorThemeDefinition {
        guard String(data: data, encoding: .utf8) != nil else {
            throw DraftlyError.message("The Drafts theme must contain UTF-8 JSON.")
        }
        let source: ThemeJSONValue
        do { source = try JSONDecoder().decode(ThemeJSONValue.self, from: data) }
        catch { throw DraftlyError.message("The Drafts theme contains invalid JSON.") }
        guard case .object(let root) = source else {
            throw DraftlyError.message("The Drafts theme must contain a JSON object.")
        }
        func object(_ value: ThemeJSONValue?, _ path: String) throws -> [String: ThemeJSONValue] {
            guard case .object(let result) = value else {
                throw DraftlyError.message("The Drafts theme requires an object at \(path).")
            }
            return result
        }
        func string(_ value: ThemeJSONValue?, _ path: String) throws -> String {
            guard case .string(let result) = value else {
                throw DraftlyError.message("The Drafts theme requires a string at \(path).")
            }
            return result
        }
        func hex(_ value: String, _ path: String) throws -> String {
            let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
            guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
                throw DraftlyError.message("Unsupported color format at \(path). Use six hexadecimal digits, with an optional # prefix.")
            }
            return digits.uppercased()
        }
        let name = try string(root["name"], "name")
        if let author = root["author"] { _ = try string(author, "author") }
        _ = try string(root["description"], "description")
        let isDark: Bool
        if let supplied = root["isDark"] {
            guard case .bool(let value) = supplied else {
                throw DraftlyError.message("The Drafts theme requires a Boolean at isDark.")
            }
            isDark = value
        } else { isDark = false }
        let colors = try object(root["colors"], "colors")
        let editor = try object(colors["editor"], "colors.editor")
        let interface = try object(colors["interface"], "colors.interface")
        var editorColors: [String: String] = [:]
        var interfaceColors: [String: String] = [:]
        for (key, value) in editor {
            let path = "colors.editor.\(key)"
            editorColors[key] = try hex(string(value, path), path)
        }
        for (key, value) in interface {
            let path = "colors.interface.\(key)"
            interfaceColors[key] = try hex(string(value, path), path)
        }
        guard let fallbackForeground = interfaceColors["textForeground"],
              let background = interfaceColors["textBackground"] else {
            throw DraftlyError.message("The Drafts theme requires colors.interface.textForeground and colors.interface.textBackground.")
        }
        let scopes = try object(root["scopes"], "scopes")
        var foregrounds: [String: String] = [:]
        for (key, value) in scopes {
            let scope = try object(value, "scopes.\(key)")
            let settings = try object(scope["settings"], "scopes.\(key).settings")
            for property in ["foreground", "background"] {
                guard let value = settings[property] else { continue }
                let path = "scopes.\(key).settings.\(property)"
                let reference = try string(value, path)
                let resolved: String
                if let named = editorColors[reference] { resolved = named }
                else if reference.hasPrefix("#") || (reference.count == 6 && reference.allSatisfy({ $0.isASCII && $0.isHexDigit })) {
                    resolved = try hex(reference, path)
                } else {
                    throw DraftlyError.message("Unknown editor color or unsupported color format at \(path): \(reference).")
                }
                if property == "foreground" { foregrounds[key] = resolved }
            }
        }
        let foreground = foregrounds["text.normal"] ?? fallbackForeground
        let result = EditorThemeDefinition(id: id, name: name, foreground: foreground,
            background: background, heading: foregrounds["text.heading"] ?? foregrounds["text.header"] ?? foreground,
            isDark: isDark, unknownFields: ["draftsSource": source])
        try result.validate()
        return result
    }
}
