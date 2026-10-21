import Foundation
import DraftlyCore

enum WorkspaceOptionsEditor {
    static func set(_ value: Any, for key: String, in workspace: inout Workspace) throws {
        var options = workspace.apiOptions
        options[key] = value
        try store(options, in: &workspace)
    }

    static func setReference(_ reference: [String: String]?, key: String, in workspace: inout Workspace) throws {
        var options = workspace.apiOptions
        if let reference {
            var value = options[key] as? [String: Any] ?? [:]
            for field in ["uuid", "name", "type"] { value.removeValue(forKey: field) }
            for (field, entry) in reference { value[field] = entry }
            options[key] = value
        } else { options.removeValue(forKey: key) }
        try store(options, in: &workspace)
    }

    static func setSort(_ sort: NoteSort, ascending: Bool, flaggedFirst: Bool,
                        folder: NoteFolder, in workspace: inout Workspace) throws {
        var options = workspace.apiOptions
        updateSortOptions(&options, sort: sort, ascending: ascending, flaggedFirst: flaggedFirst, folder: folder)
        try store(options, in: &workspace)
    }

    static func updateSortOptions(_ options: inout [String: Any], sort: NoteSort, ascending: Bool,
                                  flaggedFirst: Bool? = nil, folder: NoteFolder) {
        var sorts = options["_sorts"] as? [String: [String: Any]] ?? [:]
        var entry = sorts[folder.rawValue] ?? [:]
        entry["sort"] = sort == .title ? "name" : sort.rawValue
        entry["descending"] = !ascending
        if let flaggedFirst { entry["flagged"] = flaggedFirst }
        sorts[folder.rawValue] = entry
        options["_sorts"] = sorts
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
