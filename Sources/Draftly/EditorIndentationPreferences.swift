import Foundation

enum EditorIndentationStyle: String, CaseIterable {
    case tabs, twoSpaces, fourSpaces

    var text: String {
        switch self {
        case .tabs: "\t"
        case .twoSpaces: "  "
        case .fourSpaces: "    "
        }
    }

    var label: String {
        switch self {
        case .tabs: "Tab"
        case .twoSpaces: "2 Spaces"
        case .fourSpaces: "4 Spaces"
        }
    }
}

enum EditorIndentationPreferences {
    static let key = "editor.indentationBySyntax"

    static func style(for syntax: String, encoded: String) -> EditorIndentationStyle {
        let stored = values(encoded)?[syntax] as? String
        return stored.flatMap(EditorIndentationStyle.init(rawValue:)) ?? .tabs
    }

    static func isValid(_ encoded: String) -> Bool { values(encoded) != nil }

    static func text(for syntax: String, defaults: UserDefaults = .standard) -> String {
        style(for: syntax, encoded: defaults.string(forKey: key) ?? "{}").text
    }

    static func setting(_ style: EditorIndentationStyle, for syntax: String, encoded: String) -> String {
        guard var values = values(encoded) else { return encoded }
        values[syntax] = style.rawValue
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? encoded
    }

    private static func values(_ encoded: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(encoded.utf8))) as? [String: Any]
    }
}
