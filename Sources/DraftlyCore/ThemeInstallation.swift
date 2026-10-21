import Foundation

public enum ThemeInstallation: Sendable, Equatable {
    case builtIn(String)
    case custom(EditorThemeDefinition)

    public var url: URL {
        get throws {
            var components = URLComponents()
            components.scheme = "draftly"
            components.host = "theme"
            switch self {
            case .builtIn(let name):
                try Self.validateBuiltIn(name)
                components.queryItems = [URLQueryItem(name: "type", value: "builtIn"), URLQueryItem(name: "name", value: name)]
            case .custom(let theme):
                try theme.validate()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(theme)
                components.queryItems = [URLQueryItem(name: "type", value: "custom"),
                                         URLQueryItem(name: "data", value: String(decoding: data, as: UTF8.self))]
            }
            guard let url = components.url else { throw Self.invalidLink }
            return url
        }
    }

    public init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "draftly", components.host == "theme",
              components.path.isEmpty, components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let items = components.queryItems, !items.isEmpty,
              Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ ["type", "name", "data"].contains($0.name) && $0.value != nil }) else {
            throw Self.invalidLink
        }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        switch values["type"] {
        case "builtIn", nil:
            guard values["data"] == nil, let name = values["name"] else { throw Self.invalidLink }
            try Self.validateBuiltIn(name)
            self = .builtIn(name)
        case "custom":
            guard values["name"] == nil, let text = values["data"] else { throw Self.invalidLink }
            let theme: EditorThemeDefinition
            do { theme = try JSONDecoder().decode(EditorThemeDefinition.self, from: Data(text.utf8)) }
            catch { throw DraftlyError.message("The theme link contains invalid theme data.") }
            try theme.validate()
            self = .custom(theme)
        case "file":
            throw DraftlyError.message("File theme installation is not implemented.")
        default: throw Self.invalidLink
        }
    }

    private static var invalidLink: DraftlyError { .message("The theme link is invalid.") }

    private static func validateBuiltIn(_ name: String) throws {
        guard ThemeCatalog.builtInNames.contains(name) else {
            throw DraftlyError.message("The built-in theme was not found.")
        }
    }
}
