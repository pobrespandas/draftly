import Foundation
import DraftlyCore

enum WorkspaceOptionsEditor {
    static func set(_ value: Any, for key: String, in workspace: inout Workspace) throws {
        var options = workspace.apiOptions
        options[key] = value
        try store(options, in: &workspace)
    }

    static func setSort(_ sort: NoteSort, ascending: Bool, flaggedFirst: Bool,
                        folder: NoteFolder, in workspace: inout Workspace) throws {
        var options = workspace.apiOptions
        var sorts = options["_sorts"] as? [String: [String: Any]] ?? [:]
        var entry = sorts[folder.rawValue] ?? [:]
        entry["sort"] = sort == .title ? "name" : sort.rawValue
        entry["descending"] = !ascending
        entry["flagged"] = flaggedFirst
        sorts[folder.rawValue] = entry
        options["_sorts"] = sorts
        try store(options, in: &workspace)
    }

    static func setDate(_ value: Any, component: String, key: String,
                        in workspace: inout Workspace) throws {
        var date = workspace.apiOptions[key] as? [String: Any] ?? [:]
        date[component] = value
        try set(date, for: key, in: &workspace)
    }

    private static func store(_ options: [String: Any], in workspace: inout Workspace) throws {
        guard JSONSerialization.isValidJSONObject(options) else {
            throw DraftlyError.message("The workspace options contain an invalid value.")
        }
        let data = try JSONSerialization.data(withJSONObject: options, options: [.sortedKeys])
        var metadata = workspace.scriptMetadata ?? [:]
        metadata["api"] = String(decoding: data, as: UTF8.self)
        workspace.scriptMetadata = metadata
    }
}
