import Foundation
import DraftlyCore

enum EditorSyntaxLayoutPreferences {
    static let key = "editor.layoutBySyntax"

    enum Field: String, CaseIterable {
        case lineHeightMultiple, paragraphSpacing, horizontalMargin, verticalMargin, maximumWidth
    }

    struct Layout: Equatable {
        var lineHeightMultiple: Double
        var paragraphSpacing: Double
        var horizontalMargin: Double
        var verticalMargin: Double
        var maximumWidth: Double

        subscript(field: Field) -> Double {
            get {
                switch field {
                case .lineHeightMultiple: lineHeightMultiple
                case .paragraphSpacing: paragraphSpacing
                case .horizontalMargin: horizontalMargin
                case .verticalMargin: verticalMargin
                case .maximumWidth: maximumWidth
                }
            }
            set {
                switch field {
                case .lineHeightMultiple: lineHeightMultiple = newValue
                case .paragraphSpacing: paragraphSpacing = newValue
                case .horizontalMargin: horizontalMargin = newValue
                case .verticalMargin: verticalMargin = newValue
                case .maximumWidth: maximumWidth = newValue
                }
            }
        }
    }

    static func layout(for syntax: String, encoded: String, defaults: Layout) -> Layout {
        var result = defaults
        guard let fields = try? fields(for: syntax, in: object(encoded)) else { return result }
        for field in Field.allCases {
            if case .number(let stored) = fields[field.rawValue] {
                let value = NSDecimalNumber(decimal: stored).doubleValue
                if value.isFinite && value >= 0 { result[field] = value }
            }
        }
        return result
    }

    static func hasOverrides(for syntax: String, encoded: String) -> Bool {
        guard let fields = try? fields(for: syntax, in: object(encoded)) else { return false }
        return Field.allCases.contains { fields[$0.rawValue] != nil }
    }

    static func setting(_ field: Field, value: Double, for syntax: String, encoded: String) throws -> String {
        guard value.isFinite, value >= 0, !Decimal(value).isNaN else {
            throw DraftlyError.message("Use a finite value of zero or more.")
        }
        return try edit(syntax, encoded: encoded) { $0[field.rawValue] = .number(Decimal(value)) }
    }

    static func reset(for syntax: String, encoded: String) throws -> String {
        try edit(syntax, encoded: encoded) { fields in
            for field in Field.allCases { fields.removeValue(forKey: field.rawValue) }
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
        .message("The saved syntax layout options are invalid. They were kept unchanged.")
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
