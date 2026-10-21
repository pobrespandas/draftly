import Foundation
import DraftlyCore

enum WorkspacePresentationResolver {
    static func resolve(_ workspace: Workspace, groupNames: [String], groups: [ActionGroupRecord], themes: [EditorTheme]) throws -> Workspace {
        var workspace = workspace
        var values = workspace.apiOptions
        for key in ["loadActionListGroup", "loadActionBarGroup"] {
            guard let group = values[key] as? [String: Any] else { continue }
            values[key] = try ActionGroupReferenceResolver.resolve(group, names: groupNames, groups: groups,
                errorMessage: "The workspace action group was not found.")
        }
        for key in ["preferredDarkTheme", "preferredLightTheme"] {
            guard var theme = values[key] as? [String: Any] else { continue }
            theme = try ThemeReferenceResolver.resolve(theme, themes: themes,
                errorMessage: "The workspace theme was not found.")
            values[key] = theme
        }
        if workspace.scriptMetadata != nil { workspace.scriptMetadata?["api"] = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self) }
        return workspace
    }

}
