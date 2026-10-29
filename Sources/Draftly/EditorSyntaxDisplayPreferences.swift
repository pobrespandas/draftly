import Foundation
import DraftlyCore

enum EditorSyntaxDisplayPreferences {
    static let key = "editor.displayBySyntax"
    enum Option: String, CaseIterable, Identifiable {
        case paragraphNumbers, highlightInsertionPoint
        var id: String { rawValue }
        var title: String {
            switch self {
            case .paragraphNumbers: "Paragraph Numbers"
            case .highlightInsertionPoint: "Highlight Insertion Point"
            }
        }
    }

    static func value(_ option: Option, for syntax: String, encoded: String, legacyHighlight: Bool = false) -> Bool {
        guard let object = try? decode(encoded), case .object(let fields) = object[syntax],
              case .bool(let value) = fields[option.rawValue] else {
            return option == .highlightInsertionPoint && legacyHighlight
        }
        return value
    }

    static func setting(_ option: Option, enabled: Bool, for syntax: String, encoded: String) throws -> String {
        var object = try decode(encoded)
        var fields: [String: JSONValue]
        if let value = object[syntax] {
            guard case .object(let existing) = value else { throw invalidOptions() }
            fields = existing
        } else { fields = [:] }
        fields[option.rawValue] = .bool(enabled)
        object[syntax] = .object(fields)
        return String(decoding: try JSONEncoder().encode(object), as: UTF8.self)
    }

    private static func decode(_ encoded: String) throws -> [String: JSONValue] {
        do { return try JSONDecoder().decode([String: JSONValue].self, from: Data(encoded.utf8)) }
        catch { throw invalidOptions() }
    }
    private static func invalidOptions() -> DraftlyError {
        .message("The saved display options are invalid. They were kept unchanged.")
    }
}
