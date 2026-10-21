import Foundation
import DraftlyCore

enum ThemeReferenceResolver {
    static func resolve(_ reference: [String: Any], themes: [EditorTheme],
                        errorMessage: String = "The theme was not found.") throws -> [String: Any] {
        var reference = reference
        switch reference["type"] as? String ?? "builtIn" {
        case "custom":
            let theme: EditorTheme?
            if let rawID = reference["uuid"] {
                guard let text = rawID as? String, let id = UUID(uuidString: text) else {
                    throw DraftlyError.message(errorMessage)
                }
                theme = themes.first { $0.id == id }
            } else { theme = themes.first { $0.name == reference["name"] as? String } }
            guard let theme else { throw DraftlyError.message(errorMessage) }
            reference["name"] = theme.name; reference["uuid"] = theme.id.uuidString
            reference["type"] = "custom"
        case "builtIn":
            guard ThemeCatalog.builtInNames.contains(reference["name"] as? String ?? "") else {
                throw DraftlyError.message(errorMessage)
            }
            reference["type"] = "builtIn"
        case "file": throw DraftlyError.message("File themes are unavailable on macOS.")
        default: throw DraftlyError.message(errorMessage)
        }
        return reference
    }
}
