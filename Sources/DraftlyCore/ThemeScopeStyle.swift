import Foundation

public struct ThemeScopeStyle: Equatable, Sendable {
    public var foreground: String?
    public var background: String?
    public var fontWeight: String?
    public var fontStyles: [String]?
    public var fontSize: String?

    public init(foreground: String? = nil, background: String? = nil,
                fontWeight: String? = nil, fontStyles: [String]? = nil, fontSize: String? = nil) {
        self.foreground = foreground
        self.background = background
        self.fontWeight = fontWeight
        self.fontStyles = fontStyles
        self.fontSize = fontSize
    }
}

extension EditorThemeDefinition {
    /// Resolve an exact scope name. The theme format does not define ancestor inheritance.
    public func scopeStyle(named name: String) -> ThemeScopeStyle? {
        guard let source = draftsThemeSource,
              case .object(let scopes) = source["scopes"],
              case .object(let scope) = scopes[name],
              case .object(let settings) = scope["settings"] else { return nil }
        let colors: [String: ThemeJSONValue]
        if case .object(let containers) = source["colors"],
           case .object(let editor) = containers["editor"] { colors = editor }
        else { colors = [:] }
        func string(_ key: String) -> String? {
            guard case .string(let value) = settings[key] else { return nil }
            return value
        }
        let weight = string("fontWeight")
        let size = string("fontSize")
        let weights: Set<String> = ["ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"]
        let sizes: Set<String> = ["extraSmall", "small", "normal", "large", "extraLarge"]
        var styles: [String]?
        if let value = string("fontStyle") {
            let supported: Set<String> = ["italic", "underline", "strikethrough", "monospace"]
            let tokens = value.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tokens == ["normal"] {
                styles = []
            } else {
                let valid = tokens.filter { supported.contains($0) }
                if !valid.isEmpty {
                    styles = valid.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
                }
            }
        }
        return ThemeScopeStyle(foreground: resolveThemeColor(string("foreground"), named: colors),
                               background: resolveThemeColor(string("background"), named: colors),
                               fontWeight: weight.flatMap { weights.contains($0) ? $0 : nil },
                               fontStyles: styles,
                               fontSize: size.flatMap { sizes.contains($0) ? $0 : nil })
    }

    public func interfaceColor(named name: String) -> String? {
        guard let source = draftsThemeSource,
              case .object(let colors) = source["colors"],
              case .object(let interface) = colors["interface"],
              case .string(let value) = interface[name] else { return nil }
        return resolveThemeColor(value, named: [:])
    }

    private var draftsThemeSource: [String: ThemeJSONValue]? {
        guard case .object(let source) = unknownFields["draftsSource"] else { return nil }
        return source
    }

    private func resolveThemeColor(_ value: String?, named colors: [String: ThemeJSONValue]) -> String? {
        guard var value else { return nil }
        if case .string(let color) = colors[value] { value = color }
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return digits.uppercased()
    }
}
