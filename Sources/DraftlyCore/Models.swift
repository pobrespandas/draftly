import Foundation

public enum NoteFolder: String, Codable, CaseIterable, Identifiable {
    case inbox, archive, trash, all, flagged
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .inbox: "tray"
        case .archive: "archivebox"
        case .trash: "trash"
        case .all: "square.stack"
        case .flagged: "flag"
        }
    }
}

public struct Note: Identifiable, Codable, Equatable {
    public var id: UUID
    public var content: String
    public var tags: [String]
    public var flag: Int
    public var isArchived: Bool
    public var trashedAt: Date?
    public var createdAt: Date
    public var modifiedAt: Date
    public var accessedAt: Date?
    public var syntax: String
    public var scriptMetadata: [String: String]?
    public init(id: UUID = UUID(), content: String = "", tags: [String] = [], flag: Int = 0,
                isArchived: Bool = false, trashedAt: Date? = nil, createdAt: Date = Date(),
                modifiedAt: Date = Date(), syntax: String = "Markdown", accessedAt: Date? = nil) {
        self.id = id; self.content = content; self.tags = tags; self.flag = flag
        self.isArchived = isArchived; self.trashedAt = trashedAt
        self.createdAt = createdAt; self.modifiedAt = modifiedAt; self.syntax = syntax
        self.accessedAt = accessedAt
    }
    public var title: String {
        let line = content.components(separatedBy: .newlines).first ?? ""
        let clean = line.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        return clean.isEmpty ? "Untitled" : clean
    }
    public var preview: String { content.components(separatedBy: .newlines).dropFirst().joined(separator: " ") }
}

public struct Revision: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var noteID: UUID
    public var date: Date = Date()
    public var content: String
    public init(noteID: UUID, content: String) { self.noteID = noteID; self.content = content }
}

public enum NoteSort: String, Codable, CaseIterable {
    case modified, created, title, accessed
}

public enum TagRules {
    public static func normalize(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping.lowercased()
    }

    public static func normalize(_ tags: [String]) -> [String] {
        Array(Set(tags.map(normalize).filter { !$0.isEmpty })).sorted()
    }

    public static func matches(_ filter: String, in tags: [String]) -> Bool {
        let key = normalize(filter)
        return tags.map(normalize).contains { value in
            value == key || value.hasPrefix(key + "/") || (key.hasSuffix("::") && value.hasPrefix(key))
        }
    }
}

public struct Workspace: Identifiable, Codable, Equatable {
    public var order: Int?
    public var listOptions: DraftListOptions?
    public var id: UUID = UUID()
    public var name: String
    public var query: String = ""
    public var tags: [String] = []
    public var excludedTags: [String]?
    public var matchAnyTag: Bool?
    public var tagged: Bool?
    public var scriptMetadata: [String: String]?
    public var folder: NoteFolder = .inbox
    public var sort: NoteSort = .modified
    public var ascending: Bool = false
    public init(name: String) { self.name = name }
    public func filter(_ notes: [Note]) -> [Note] {
        let options = listOptions ?? DraftListOptions()
        let search = DraftQuery(query, caseSensitive: options.caseSensitiveSearch)
        return notes.filter { n in
            let folderMatch: Bool
            switch folder {
            case .trash: folderMatch = n.trashedAt != nil
            case .archive: folderMatch = n.trashedAt == nil && n.isArchived
            case .inbox: folderMatch = n.trashedAt == nil && !n.isArchived
            case .flagged: folderMatch = n.trashedAt == nil && n.flag > 0
            case .all: folderMatch = n.trashedAt == nil
            }
            let tagPresenceMatch = tagged.map { $0 ? !n.tags.isEmpty : n.tags.isEmpty } ?? true
            let includes = tags.map { TagRules.matches($0, in: n.tags) }
            let excludes = (excludedTags ?? []).contains { TagRules.matches($0, in: n.tags) }
            let tagMatch = tags.isEmpty || ((matchAnyTag ?? false) ? includes.contains(true) : includes.allSatisfy { $0 })
            return matchesScriptFilters(n) && folderMatch && tagPresenceMatch && tagMatch && !excludes
                && search.matches(n, titlesOnly: options.searchTitlesOnly)
        }.sorted { a, b in
            if a.id == b.id { return false }
            let effective = scriptSort(for: folder)
            if effective?.2 == true && (a.flag > 0) != (b.flag > 0) { return a.flag > 0 }
            let ascending = effective?.1 ?? ascending
            switch effective?.0 ?? sort {
            case .modified: return ascending ? a.modifiedAt < b.modifiedAt : a.modifiedAt > b.modifiedAt
            case .created: return ascending ? a.createdAt < b.createdAt : a.createdAt > b.createdAt
            case .accessed:
                guard let left = a.accessedAt else {
                    return b.accessedAt == nil && a.id.uuidString < b.id.uuidString
                }
                guard let right = b.accessedAt else { return true }
                if left == right { return a.id.uuidString < b.id.uuidString }
                return ascending ? left < right : left > right
            case .title: return ascending ? a.title.localizedStandardCompare(b.title) == .orderedAscending : a.title.localizedStandardCompare(b.title) == .orderedDescending
            }
        }
    }
}

public struct ActionStep: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var type: String
    public var values: [String: String]
    public var isEnabled: Bool?
    public init(_ type: String, _ values: [String: String] = [:]) { self.type = type; self.values = values }
}

public struct DraftAction: Identifiable, Codable, Equatable {
    public var options: ActionPresentation?
    public var id: UUID = UUID()
    public var name: String
    public var symbol: String = "bolt"
    public var group: String = "General"
    public var shortcut: String = ""
    public var shortcutModifiers: [String]?
    public var afterSuccess: String = "none"
    public var configuredValues: [String: String] = [:]
    public var steps: [ActionStep]
    public var sourceURL: String?
    public var rawPayload: String?
    public var scriptMetadata: [String: String]?
    public init(name: String, steps: [ActionStep]) { self.name = name; self.steps = steps }
    public static let supportedSteps: Set<String> = ["script", "clipboard", "url", "insertText", "createDraft", "file", "share", "runShortcut", "runAppleScript", "htmlpreview", "configurationKey", "includeAction", "reminder", "event", "callbackUrl", "prompt", "defineTemplateTag", "configureWindow", "mail", "message", "listInReminders", "export", "openIn", "print", "speak"]
    public var unsupportedSteps: [String] { steps.filter { $0.isEnabled != false }.map(\.type).filter { !Self.supportedSteps.contains($0) } }
}

public struct ActionRun: Identifiable, Codable {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var actionName: String
    public var status: String
    public var message: String
    public var noteID: UUID?
    public var actionID: UUID?
    public init(actionName: String, status: String, message: String) {
        self.actionName = actionName; self.status = status; self.message = message
    }
}

public struct Backup: Codable {
    public var syntaxes: [SyntaxDefinition]?
    public var actionGroups: [ActionGroupRecord]?
    public var version: Int = 1
    public var notes: [Note]
    public var revisions: [Revision]
    public var workspaces: [Workspace]
    public var actions: [DraftAction]
    public init(notes: [Note], revisions: [Revision], workspaces: [Workspace], actions: [DraftAction], actionGroups: [ActionGroupRecord]? = nil, syntaxes: [SyntaxDefinition]? = nil) {
        self.syntaxes = syntaxes
        self.actionGroups = actionGroups
        self.notes = notes; self.revisions = revisions; self.workspaces = workspaces; self.actions = actions
    }
}

public enum DraftlyError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
