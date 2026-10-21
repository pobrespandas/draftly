import DraftlyCore

enum WorkspaceThemeValues {
    static func preference(_ metadata: [String: String]?, key: String) -> String? {
        var workspace = Workspace(name: "")
        workspace.scriptMetadata = metadata
        return (workspace.apiOptions[key] as? [String: Any])?["name"] as? String
    }
}
