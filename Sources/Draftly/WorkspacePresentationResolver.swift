import Foundation
import DraftlyCore

enum WorkspacePresentationResolver {
    static func resolve(_ workspace: Workspace, groupNames: [String], groups: [ActionGroupRecord], themes: [EditorTheme]) throws -> Workspace {
        var workspace = workspace
        var values = workspace.apiOptions
        let groupIDs = ActionGroupIdentity.identifiers(names: groupNames, records: groups)
        for key in ["loadActionListGroup", "loadActionBarGroup"] {
            guard var group = values[key] as? [String: Any] else { continue }
            let name: String?
            if let id = (group["uuid"] as? String).flatMap(UUID.init(uuidString:)) {
                name = groupNames.first { candidate in groupIDs[candidate] == id }
            } else { name = (group["name"] as? String).flatMap { groupNames.contains($0) ? $0 : nil } }
            guard let name else { throw DraftlyError.message("The workspace action group was not found.") }
            group["name"] = name; values[key] = group
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
