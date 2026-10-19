import Foundation

public extension Workspace {
    var apiOptions: [String: Any] {
        guard let text = scriptMetadata?["api"], let data = text.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func scriptSort(for folder: NoteFolder) -> (NoteSort, Bool, Bool)? {
        let sorts = apiOptions["_sorts"] as? [String: [String: Any]] ?? [:]
        guard let value = sorts[folder.rawValue] else { return nil }
        let name = value["sort"] as? String ?? "modified"
        return (name == "name" ? .title : NoteSort(rawValue: name) ?? .modified,
                !(value["descending"] as? Bool ?? false), value["flagged"] as? Bool ?? false)
    }

    func matchesScriptFilters(_ note: Note, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let details = apiOptions
        let status = details["flaggedStatus"] as? String ?? "any"
        if status == "flagged" && note.flag == 0 || status == "unflagged" && note.flag > 0 { return false }
        if folder == .inbox && details["inboxIncludesFlagged"] as? Bool == false && note.flag > 0 { return false }
        if folder == .archive && details["archiveIncludesFlagged"] as? Bool == false && note.flag > 0 { return false }
        for key in ["startDate", "endDate"] {
            guard let query = details[key] as? [String: Any], let type = query["type"] as? String, type != "none" else { continue }
            let date = type == "relative" ? calendar.date(byAdding: .day, value: query["days"] as? Int ?? 0, to: now) : APIValues.parseDate(query["date"])
            guard let date else { continue }
            let start = calendar.startOfDay(for: date)
            let value: Date
            switch query["field"] as? String {
            case "created": value = note.createdAt
            case "accessed":
                guard let accessed = note.accessedAt else { return false }
                value = accessed
            default: value = note.modifiedAt
            }
            if key == "startDate" && value < start { return false }
            if key == "endDate", let end = calendar.date(byAdding: .day, value: 1, to: start), value >= end { return false }
        }
        return true
    }
}

@MainActor public enum WorkspaceDefaults {
    public static let key = "workspace.defaultID"
    public static func make(in library: LibraryStore, defaults: UserDefaults = .standard) -> Workspace {
        var value = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)).flatMap { id in
            library.workspaces.first { $0.id == id }
        } ?? Workspace(name: "")
        value.id = UUID()
        value.name = ""
        value.order = nil
        return value
    }
}
