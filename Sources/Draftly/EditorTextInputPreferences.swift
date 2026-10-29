import Foundation
import DraftlyCore

enum EditorTextInputPreferences {
    static let key = "editor.textInputBySyntax"

    enum Option: String, CaseIterable, Identifiable {
        case spelling, grammar, smartQuotes, smartDashes, autoMatch, autoRenumber
        var id: String { rawValue }
        var title: String {
            switch self {
            case .spelling: "Check spelling while typing"
            case .grammar: "Grammar checking"
            case .smartQuotes: "Smart quotes"
            case .smartDashes: "Smart dashes"
            case .autoMatch: "Auto-match"
            case .autoRenumber: "Auto-renumber lists"
            }
        }
        var defaultValue: Bool { self == .spelling || self == .autoRenumber }
    }

    enum SystemOption: String, CaseIterable, Identifiable {
        case autocorrection, writingTools
        var id: String { rawValue }
        var title: String {
            switch self {
            case .autocorrection: "Correct spelling automatically"
            case .writingTools: "Writing Tools"
            }
        }
    }

    struct Configuration: Equatable {
        var spelling = true
        var grammar = false
        var smartQuotes = false
        var smartDashes = false
        var autoMatch = false
        var autoRenumber = true
        var autocorrection: Bool?
        var writingTools: Bool?
    }

    static func value(_ option: Option, for syntax: String, encoded: String) -> Bool {
        guard let fields = try? fields(for: syntax, in: object(encoded)),
              case .bool(let value) = fields[option.rawValue] else { return option.defaultValue }
        return value
    }

    static func configuration(for syntax: String, encoded: String) -> Configuration {
        Configuration(spelling: value(.spelling, for: syntax, encoded: encoded),
            grammar: value(.grammar, for: syntax, encoded: encoded),
            smartQuotes: value(.smartQuotes, for: syntax, encoded: encoded),
            smartDashes: value(.smartDashes, for: syntax, encoded: encoded),
            autoMatch: value(.autoMatch, for: syntax, encoded: encoded),
            autoRenumber: value(.autoRenumber, for: syntax, encoded: encoded),
            autocorrection: override(.autocorrection, for: syntax, encoded: encoded),
            writingTools: override(.writingTools, for: syntax, encoded: encoded))
    }

    static func setting(_ option: Option, enabled: Bool, for syntax: String, encoded: String) throws -> String {
        try edit(syntax, encoded: encoded) { $0[option.rawValue] = .bool(enabled) }
    }

    static func override(_ option: SystemOption, for syntax: String, encoded: String) -> Bool? {
        guard let fields = try? fields(for: syntax, in: object(encoded)),
              case .bool(let value) = fields[option.rawValue] else { return nil }
        return value
    }

    static func setting(_ option: SystemOption, enabled: Bool?, for syntax: String, encoded: String) throws -> String {
        try edit(syntax, encoded: encoded) { fields in
            if let enabled { fields[option.rawValue] = .bool(enabled) }
            else { fields.removeValue(forKey: option.rawValue) }
        }
    }

    static func hasOverrides(for syntax: String, encoded: String) -> Bool {
        guard let fields = try? fields(for: syntax, in: object(encoded)) else { return false }
        return Option.allCases.contains { fields[$0.rawValue] != nil }
            || SystemOption.allCases.contains { fields[$0.rawValue] != nil }
    }

    static func reset(for syntax: String, encoded: String) throws -> String {
        try edit(syntax, encoded: encoded) { fields in
            for option in Option.allCases { fields.removeValue(forKey: option.rawValue) }
            for option in SystemOption.allCases { fields.removeValue(forKey: option.rawValue) }
        }
    }

    private static func object(_ encoded: String) throws -> [String: JSONValue] {
        do { return try JSONDecoder().decode([String: JSONValue].self, from: Data(encoded.utf8)) }
        catch { throw invalidOptions() }
    }

    private static func fields(for syntax: String, in object: [String: JSONValue]) throws -> [String: JSONValue] {
        guard let value = object[syntax] else { return [:] }
        guard case .object(let fields) = value else { throw invalidOptions() }
        return fields
    }

    private static func invalidOptions() -> DraftlyError {
        .message("The saved text input options are invalid. They were kept unchanged.")
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
