import Foundation
import DraftlyCore

enum ThemeReferenceResolver {
    static func resolve(_ reference: [String: Any], themes: [EditorTheme],
                        errorMessage: String = "The theme was not found.") throws -> [String: Any] {
        var reference = reference
        switch reference["type"] as? String ?? "builtIn" {
        case "custom", "file":
            let type = reference["type"] as? String ?? "custom"
            let theme: EditorTheme?
            if let rawID = reference["uuid"] {
                guard let text = rawID as? String, let id = UUID(uuidString: text) else {
                    throw DraftlyError.message(errorMessage)
                }
                theme = themes.first { $0.id == id && $0.type == type }
            } else { theme = themes.first { $0.name == reference["name"] as? String && $0.type == type } }
            guard let theme else { throw DraftlyError.message(errorMessage) }
            reference["name"] = theme.name; reference["uuid"] = theme.id.uuidString
            reference["type"] = theme.type
        case "builtIn":
            guard ThemeCatalog.builtInNames.contains(reference["name"] as? String ?? "") else {
                throw DraftlyError.message(errorMessage)
            }
            reference["type"] = "builtIn"
        default: throw DraftlyError.message(errorMessage)
        }
        return reference
    }
}
