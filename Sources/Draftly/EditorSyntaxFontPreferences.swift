import Foundation
import DraftlyCore

enum EditorSyntaxFontPreferences {
    static let key = "editor.fontBySyntax"

    struct Font: Equatable {
        let name: String
        let size: Double
    }

    static func font(for syntax: String, encoded: String, defaultName: String, defaultSize: Double) -> Font {
        let fields = try? fields(for: syntax, encoded: encoded)
        let name: String
        if case .string(let stored) = fields?["fontName"] { name = stored }
        else { name = defaultName }
        let size: Double
        if case .number(let stored) = fields?["fontSize"],
           NSDecimalNumber(decimal: stored).doubleValue.isFinite, stored > 0 {
            size = NSDecimalNumber(decimal: stored).doubleValue
        }
        else { size = defaultSize }
        return Font(name: name, size: size)
    }

    static func hasOverrides(for syntax: String, encoded: String) -> Bool {
        guard let fields = try? fields(for: syntax, encoded: encoded) else { return false }
        return fields["fontName"] != nil || fields["fontSize"] != nil
    }

    static func settingName(_ name: String, for syntax: String, encoded: String) throws -> String {
        try edit(syntax, encoded: encoded) { $0["fontName"] = .string(name) }
    }

    static func settingSize(_ size: Double, for syntax: String, encoded: String) throws -> String {
        guard size.isFinite, size > 0 else { throw DraftlyError.message("Use a positive finite font size.") }
        let stored = Decimal(size)
        guard !stored.isNaN else { throw DraftlyError.message("Use a positive finite font size.") }
        return try edit(syntax, encoded: encoded) { $0["fontSize"] = .number(stored) }
    }

    static func reset(for syntax: String, encoded: String) throws -> String {
        try edit(syntax, encoded: encoded) {
            $0.removeValue(forKey: "fontName")
            $0.removeValue(forKey: "fontSize")
        }
    }

    private static func object(_ encoded: String) throws -> [String: JSONValue] {
        do { return try JSONDecoder().decode([String: JSONValue].self, from: Data(encoded.utf8)) }
        catch { throw DraftlyError.message("The saved syntax font options are invalid. They were kept unchanged.") }
    }

    private static func fields(for syntax: String, in object: [String: JSONValue]) throws -> [String: JSONValue] {
        guard let value = object[syntax] else { return [:] }
        guard case .object(let fields) = value else {
            throw DraftlyError.message("The saved syntax font options are invalid. They were kept unchanged.")
        }
        return fields
    }

    private static func fields(for syntax: String, encoded: String) throws -> [String: JSONValue] {
        try fields(for: syntax, in: object(encoded))
    }

    private static func edit(_ syntax: String, encoded: String,
                             change: (inout [String: JSONValue]) -> Void) throws -> String {
        var values = try object(encoded)
        var fields = try fields(for: syntax, in: values)
        change(&fields)
        if fields.isEmpty { values.removeValue(forKey: syntax) }
        else { values[syntax] = .object(fields) }
        return String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }
}
