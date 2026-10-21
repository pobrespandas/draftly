import Foundation
import CoreData
import CloudKit
import Combine
import CryptoKit

@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var notes: [Note] = []
    @Published public private(set) var revisions: [Revision] = []
    @Published public private(set) var workspaces: [Workspace] = []
    @Published public private(set) var actionGroups: [ActionGroupRecord] = []
    @Published public private(set) var actions: [DraftAction] = []
    @Published public private(set) var themes: [EditorThemeDefinition] = []
    @Published public private(set) var syntaxes: [SyntaxDefinition] = []
    @Published public private(set) var runs: [ActionRun] = []
    @Published public var error: String?
    @Published public private(set) var syncStatus: String
    public let container: NSPersistentContainer
    private let persistence: LibraryRecordPersistence
    private var syncCoordinator: LibrarySyncCoordinator?
    public let cloudIdentifier: String?

    enum ExecutionIdentity: Hashable {
        case persistent(URL)
        case memory(ObjectIdentifier)
    }

    var executionIdentity: ExecutionIdentity {
        if let store = container.persistentStoreCoordinator.persistentStores.first(where: { $0.type != NSInMemoryStoreType }),
           let url = store.url {
            return .persistent(url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL)
        }
        return .memory(ObjectIdentifier(self))
    }

    public init(inMemory: Bool = false, cloudIdentifier: String? = nil, directory: URL? = nil, seed: Bool = true) throws {
        self.cloudIdentifier = inMemory ? nil : cloudIdentifier
        persistence = try LibraryRecordPersistence(inMemory: inMemory, cloudIdentifier: cloudIdentifier, directory: directory)
        container = persistence.container
        syncStatus = cloudIdentifier != nil && !inMemory ? "Connecting to iCloud…" : inMemory ? "Test storage" : "Local storage · iCloud is not configured"
        try reload()
        if seed && actions.isEmpty {
            for action in Self.defaultActions { try saveAction(action) }
        }
        syncCoordinator = LibrarySyncCoordinator(container: container, cloudIdentifier: self.cloudIdentifier,
            onRemoteChange: { [weak self] in
                do { try self?.reload() } catch { self?.error = error.localizedDescription }
            }, onStatusChange: { [weak self] in self?.syncStatus = $0 })
    }

    public func refreshCloudAccount() async { await syncCoordinator?.refreshCloudAccount() }

    private struct NoteAccess: Codable {
        var id: UUID
        var date: Date
    }

    public func reload() throws {
        try persistence.reloadRecords()
        func decode<T: Decodable>(_ kind: String, _ type: T.Type) throws -> [T] {
            try persistence.decode(kind, type)
        }
        themes = try decode("theme", EditorThemeDefinition.self).sorted { $0.name < $1.name }
        syntaxes = try decode("syntax", SyntaxDefinition.self).sorted { $0.name < $1.name }
        let accessDates = Dictionary(try decode("noteAccess", NoteAccess.self).map { ($0.id, $0.date) }, uniquingKeysWith: max)
        notes = try decode("note", Note.self).map { value in
            var note = value
            if let date = accessDates[note.id], note.accessedAt.map({ $0 < date }) ?? true { note.accessedAt = date }
            return note
        }
        revisions = try decode("revision", Revision.self).sorted { $0.date > $1.date }
        workspaces = try decode("workspace", Workspace.self).sorted { ($0.order ?? 0) == ($1.order ?? 0) ? $0.name < $1.name : ($0.order ?? 0) < ($1.order ?? 0) }
        actionGroups = try decode("actionGroup", ActionGroupRecord.self).sorted { $0.order == $1.order ? $0.name < $1.name : $0.order < $1.order }
        actions = try decode("action", DraftAction.self).sorted { $0.name < $1.name }
        runs = try decode("run", ActionRun.self).sorted { $0.date > $1.date }
    }

    private func persist<T: Encodable>(_ item: T, id: UUID, kind: String) throws {
        try persistence.persist(item, id: id, kind: kind)
    }
    private func commit() throws {
        do {
            try preserveCollidingGroupIdentities()
            try persistence.commit { try reload() }
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }

    private func preserveCollidingGroupIdentities() throws {
        let pendingGroups = try persistence.decode("actionGroup", ActionGroupRecord.self)
        let pendingActions = try persistence.decode("action", DraftAction.self)
        let names = Set(pendingGroups.map(\.name) + pendingActions.map(\.group))
        let affected = ActionGroupIdentity.collisionNames(names: Array(names), records: pendingGroups)
            .union(ActionGroupIdentity.collisionNames(names: groupNames, records: actionGroups))
        guard !affected.isEmpty else { return }
        let ids = ActionGroupIdentity.identifiers(names: Array(names), records: pendingGroups,
            preferred: actionGroupIdentifiers)
        let storedNames = Set(pendingGroups.map(\.name))
        for name in names.intersection(affected).subtracting(storedNames).sorted() {
            var record = ActionGroupRecord(name: name)
            record.id = ids[name]!
            record.order = groupNames.firstIndex(of: name) ?? groupNames.count
            try persist(record, id: record.id, kind: "actionGroup")
        }
    }

    var beforeBatchCommit: (() throws -> Void)?

    public func saveNote(_ note: Note, preserveRevision: Bool = true, preserveDates: Bool = false) throws {
        try saveNotes([note], preserveRevision: preserveRevision, preserveDates: preserveDates)
    }
    public func saveNotes(_ values: [Note], preserveRevision: Bool = true, preserveDates: Bool = false) throws {
        do {
            for var note in values {
                note.tags = TagRules.normalize(note.tags)
                if let accessed = notes.first(where: { $0.id == note.id })?.accessedAt,
                   note.accessedAt.map({ $0 < accessed }) ?? true { note.accessedAt = accessed }
                if notes.first(where: { $0.id == note.id }) == note { continue }
                if preserveRevision && revisions.first(where: { $0.noteID == note.id })?.content != note.content {
                    let revision = Revision(noteID: note.id, content: note.content)
                    try persist(revision, id: revision.id, kind: "revision")
                }
                if !preserveDates { note.modifiedAt = Date() }
                try persist(note, id: note.id, kind: "note")
            }
            try beforeBatchCommit?()
            try commit()
        } catch {
            container.viewContext.rollback(); try? reload(); throw error
        }
    }
    public func recordAccess(_ id: UUID, at date: Date = Date()) throws {
        guard date.timeIntervalSince1970.isFinite else { throw DraftlyError.message("The access date is invalid.") }
        guard let note = notes.first(where: { $0.id == id }) else { throw DraftlyError.message("The draft was not found.") }
        if let current = note.accessedAt, current >= date { return }
        do {
            // Access must not replace a concurrent content payload in CloudKit.
            try persist(NoteAccess(id: id, date: date), id: id, kind: "noteAccess")
            try beforeBatchCommit?()
            try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    @discardableResult public func duplicateNotes(_ sources: [Note]) throws -> [Note] {
        let copies = sources.map { DraftOperations.duplicate($0) }
        try saveNotes(copies, preserveRevision: false, preserveDates: true)
        return copies
    }
    public func emptyTrash() throws {
        let ids = Set(notes.filter { $0.trashedAt != nil }.map(\.id))
        let keys = ids.flatMap { ["note:" + $0.uuidString, "noteAccess:" + $0.uuidString] }
            + revisions.filter { ids.contains($0.noteID) }.map { "revision:" + $0.id.uuidString }
        guard !keys.isEmpty else { return }
        do {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
            request.predicate = NSPredicate(format: "key IN %@", keys)
            for record in try container.viewContext.fetch(request) { container.viewContext.delete(record) }
            try beforeBatchCommit?()
            try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }

    @discardableResult public func createNote(content: String = "", tags: [String] = []) throws -> Note {
        var note = Note(content: content, tags: tags); note.tags = TagRules.normalize(tags); try saveNote(note); return notes.first(where: { $0.id == note.id }) ?? note
    }
    public func saveWorkspace(_ workspace: Workspace) throws { try saveWorkspaces([workspace]) }
    public func saveAction(_ action: DraftAction) throws { try persist(action, id: action.id, kind: "action"); try commit() }
    @discardableResult public func changeTag(_ oldValue: String, to newValue: String?) throws -> Int {
        let old = TagRules.normalize(oldValue)
        let replacement = newValue.map(TagRules.normalize)
        guard !old.isEmpty, replacement != "", replacement?.contains(",") != true else { throw DraftlyError.message("Enter one nonempty tag without commas.") }
        func updated(_ tags: [String]) -> [String] {
            TagRules.normalize(tags.flatMap { $0 == old ? replacement.map { [$0] } ?? [] : [$0] })
        }
        do {
            var count = 0
            for var note in notes where note.tags.contains(old) {
                note.tags = updated(note.tags); note.modifiedAt = Date()
                try persist(note, id: note.id, kind: "note"); count += 1
            }
            for var workspace in workspaces where workspace.tags.contains(old) || (workspace.excludedTags ?? []).contains(old) {
                workspace.tags = updated(workspace.tags)
                workspace.excludedTags = updated(workspace.excludedTags ?? [])
                try persist(workspace, id: workspace.id, kind: "workspace")
            }
            try beforeBatchCommit?(); try commit(); return count
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func saveActions(_ values: [DraftAction]) throws {
        do {
            for action in values { try persist(action, id: action.id, kind: "action") }
            try beforeBatchCommit?(); try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func saveWorkspaces(_ values: [Workspace]) throws {
        do {
            for workspace in values { try persist(workspace, id: workspace.id, kind: "workspace") }
            try beforeBatchCommit?(); try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public var groupNames: [String] {
        var seen = Set<String>()
        let known = actionGroups.map(\.name).filter { seen.insert($0).inserted }
        return known + Set(actions.map(\.group)).subtracting(known).sorted()
    }
    public var actionGroupIdentifiers: [String: UUID] {
        ActionGroupIdentity.identifiers(names: groupNames, records: actionGroups)
    }

    public func actionGroupRecord(named name: String) -> ActionGroupRecord {
        if let record = actionGroups.first(where: { $0.name == name }) { return record }
        var record = ActionGroupRecord(name: name)
        record.id = ActionGroupIdentity.identifiers(names: groupNames + [name], records: actionGroups,
            preferred: actionGroupIdentifiers)[name]!
        return record
    }

    public func orderedActions(on surface: ActionSurface? = nil) -> [DraftAction] {
        let names = groupNames
        let preferred = ["Copy", "Share", "Add to Reminders", "Add Calendar Event", "Save to File", "Markdown Preview"]
        return actions.filter { action in surface.map { action.appears(on: $0) } ?? true }.sorted { a, b in
            let ga = names.firstIndex(of: a.group) ?? Int.max, gb = names.firstIndex(of: b.group) ?? Int.max
            if ga != gb { return ga < gb }
            let x = a.options?.order ?? preferred.firstIndex(of: a.name) ?? 100
            let y = b.options?.order ?? preferred.firstIndex(of: b.name) ?? 100
            return x == y ? (a.name == b.name ? a.id.uuidString < b.id.uuidString : a.name.localizedStandardCompare(b.name) == .orderedAscending) : x < y
        }
    }
    public func saveActionGroup(_ group: ActionGroupRecord, replacing previousName: String? = nil) throws {
        var group = group
        let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let reserved = ActionGroupIdentity.identifiers(names: groupNames, records: actionGroups)
        if previousName == nil, group.id == ActionGroupRecord.identifier(for: name),
           !actionGroups.contains(where: { $0.name == name }) {
            group.id = ActionGroupIdentity.identifiers(names: groupNames + [name], records: actionGroups,
                preferred: reserved)[name]!
        }
        guard !name.isEmpty, !actionGroups.contains(where: { $0.id != group.id && $0.name == name }) else { throw DraftlyError.message("Use a unique group name.") }
        let oldName = actionGroups.first(where: { $0.id == group.id })?.name ?? previousName
        guard !groupNames.contains(name) || oldName == name || name == group.name && oldName == nil && !actionGroups.contains(where: { $0.name == name }) else { throw DraftlyError.message("Use a unique group name.") }
        do {
            for (order, existingName) in groupNames.enumerated() where !actionGroups.contains(where: { $0.name == existingName }) && existingName != oldName && existingName != name {
                var record = ActionGroupRecord(name: existingName)
                record.id = reserved[existingName]!
                record.order = order
                try persist(record, id: record.id, kind: "actionGroup")
            }
            if let oldName, oldName != name {
                for var action in actions where action.group == oldName { action.group = name; try persist(action, id: action.id, kind: "action") }
            }
            var group = group; group.name = name
            try persist(group, id: group.id, kind: "actionGroup"); try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func saveActionGroups(_ values: [ActionGroupRecord]) throws {
        let names = values.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !names.contains(""), Set(names).count == names.count else { throw DraftlyError.message("Use unique nonempty group names.") }
        guard Set(values.map(\.id)).count == values.count else { throw DraftlyError.message("Use unique action group identifiers.") }
        do {
            for group in values { try persist(group, id: group.id, kind: "actionGroup") }
            try beforeBatchCommit?(); try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func removeActionGroup(_ name: String, movingActionsTo destination: String) throws {
        guard name != destination, !destination.isEmpty else { throw DraftlyError.message("Choose another destination group.") }
        do {
            for var action in actions where action.group == name { action.group = destination; try persist(action, id: action.id, kind: "action") }
            if let group = actionGroups.first(where: { $0.name == name }), let record = persistence.record(for: "actionGroup:" + group.id.uuidString) { container.viewContext.delete(record) }
            try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func log(_ run: ActionRun) { do { try persist(run, id: run.id, kind: "run"); try commit() } catch { self.error = error.localizedDescription } }
    public func deleteAction(_ id: UUID) throws { try delete(id, kind: "action") }
    public func deleteWorkspace(_ id: UUID) throws { try delete(id, kind: "workspace") }
    public func deleteRevision(_ id: UUID) throws { try delete(id, kind: "revision") }
    public func deleteRun(_ id: UUID) throws { try delete(id, kind: "run") }
    public func saveRevision(_ revision: Revision) throws {
        do {
            try persist(revision, id: revision.id, kind: "revision")
            try beforeBatchCommit?()
            try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    private func delete(_ id: UUID, kind: String) throws {
        do {
            let key = "\(kind):\(id.uuidString)"
            let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
            request.predicate = NSPredicate(format: "key == %@", key)
            for record in try container.viewContext.fetch(request) { container.viewContext.delete(record) }
            try beforeBatchCommit?()
            try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func syntaxDefinition(named name: String) throws -> SyntaxDefinition {
        if let definition = syntaxes.first(where: { $0.name == name }) { return try definition.type == "file" ? SyntaxFileAccess.read(definition) : definition }
        return try ScriptSyntax.definition(name)
    }
    public func saveSyntax(_ value: SyntaxDefinition) throws {
        let value = try SyntaxDefinition(data: Data(value.source.utf8), type: value.type, id: value.id)
        guard !ScriptSyntax.names.contains(value.name), !syntaxes.contains(where: { $0.name == value.name && $0.id != value.id }) else { throw DraftlyError.message("Use a unique syntax name.") }
        do { try persist(value, id: value.id, kind: "syntax"); try beforeBatchCommit?(); try commit() }
        catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    private struct ThemeMigration: Codable { var id: UUID; var name: String }

    private func validateThemes(_ values: [EditorThemeDefinition]) throws {
        for value in values { try value.validate() }
        guard Set(values.map(\.id)).count == values.count else { throw DraftlyError.message("The themes contain duplicate identities.") }
        let replacements = Set(values.map(\.id))
        let combined = themes.filter { !replacements.contains($0.id) } + values
        guard Set(combined.map(\.name)).count == combined.count else { throw DraftlyError.message("Use unique theme names.") }
    }
    public func saveTheme(_ value: EditorThemeDefinition) throws { try saveThemes([value]) }
    public func saveThemes(_ values: [EditorThemeDefinition]) throws {
        try validateThemes(values)
        do {
            for value in values { try persist(value, id: value.id, kind: "theme") }
            try beforeBatchCommit?(); try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func deleteTheme(_ id: UUID) throws { try delete(id, kind: "theme") }
    public func hasThemeMigration(_ migrationID: String) throws -> Bool {
        try persistence.decode("themeMigration", ThemeMigration.self).contains(where: { $0.name == migrationID })
    }
    public func migrateThemes(_ values: [EditorThemeDefinition], migrationID: String) throws {
        guard !migrationID.isEmpty else { throw DraftlyError.message("The theme migration ID is empty.") }
        if try hasThemeMigration(migrationID) { return }
        let incoming = values.filter { value in !themes.contains(where: { $0.id == value.id }) }
        try validateThemes(incoming)
        do {
            for value in incoming { try persist(value, id: value.id, kind: "theme") }
            let marker = ThemeMigration(id: UUID(), name: migrationID)
            try persist(marker, id: marker.id, kind: "themeMigration")
            try beforeBatchCommit?(); try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func backupData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Backup(notes: notes, revisions: revisions, workspaces: workspaces, actions: actions, actionGroups: actionGroups, syntaxes: syntaxes, themes: themes, runs: runs))
    }
    public func restore(_ data: Data) throws {
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        guard backup.version == 1 else { throw DraftlyError.message("This backup version is not supported.") }
        try validateBackupIdentities(backup)
        let runsToRestore = backup.runs ?? []
        let themesToRestore = backup.themes ?? []
        try validateThemes(themesToRestore)
        let syntaxesToRestore = try (backup.syntaxes ?? []).map { try SyntaxDefinition(data: Data($0.source.utf8), type: $0.type, id: $0.id) }
        guard Set(syntaxesToRestore.map(\.name)).count == syntaxesToRestore.count,
              !syntaxesToRestore.contains(where: { incoming in ScriptSyntax.names.contains(incoming.name) || syntaxes.contains(where: { $0.name == incoming.name && $0.id != incoming.id }) }) else { throw DraftlyError.message("The backup contains conflicting syntax names.") }
        do {
        // Keep both versions when a backup contains a different draft with the same ID.
        var remapped: [UUID: UUID] = [:]
        for var note in backup.notes {
            if let existing = notes.first(where: { $0.id == note.id }), existing != note {
                let original = note.id
                note.id = try recoveryIdentity(note, kind: "note", existing: notes, id: { $0.id }) { candidate, source in
                    var candidate = candidate; candidate.id = source.id
                    candidate.accessedAt = source.accessedAt
                    return candidate == source
                }
                remapped[original] = note.id
                if let recovered = notes.first(where: { $0.id == note.id }) { note = recovered }
            }
            try persist(note, id: note.id, kind: "note")
        }
        for var revision in backup.revisions {
            if let newID = remapped[revision.noteID] {
                revision.noteID = newID
                revision.id = try recoveryIdentity(revision, kind: "revision", existing: revisions, id: { $0.id }) { candidate, source in
                    var candidate = candidate; candidate.id = source.id
                    return candidate == source
                }
            }
            try persist(revision, id: revision.id, kind: "revision")
        }
        for var run in runsToRestore {
            if let noteID = run.noteID, let newID = remapped[noteID] { run.noteID = newID }
            if let existing = runs.first(where: { $0.id == run.id }), existing != run {
                run.id = try recoveryIdentity(run, kind: "run", existing: runs, id: { $0.id }) { candidate, source in
                    var candidate = candidate; candidate.id = source.id
                    return candidate == source
                }
            }
            try persist(run, id: run.id, kind: "run")
        }
        for theme in themesToRestore { try persist(theme, id: theme.id, kind: "theme") }
        for syntax in syntaxesToRestore { try persist(syntax, id: syntax.id, kind: "syntax") }
        for workspace in backup.workspaces { try persist(workspace, id: workspace.id, kind: "workspace") }
        for group in backup.actionGroups ?? [] { try persist(group, id: group.id, kind: "actionGroup") }
        for action in backup.actions { try persist(action, id: action.id, kind: "action") }
        try beforeBatchCommit?(); try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }

    func applyImportedRecords(from staging: LibraryStore) throws {
        func changed<T: Identifiable & Equatable>(_ incoming: [T], existing: [T]) -> [T] where T.ID == UUID {
            let previous = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            return incoming.filter { previous[$0.id] != $0 }
        }
        do {
            for note in changed(staging.notes, existing: notes) { try persist(note, id: note.id, kind: "note") }
            for revision in changed(staging.revisions, existing: revisions) { try persist(revision, id: revision.id, kind: "revision") }
            for action in changed(staging.actions, existing: actions) { try persist(action, id: action.id, kind: "action") }
            for workspace in changed(staging.workspaces, existing: workspaces) { try persist(workspace, id: workspace.id, kind: "workspace") }
            for group in changed(staging.actionGroups, existing: actionGroups) { try persist(group, id: group.id, kind: "actionGroup") }
            for syntax in changed(staging.syntaxes, existing: syntaxes) { try persist(syntax, id: syntax.id, kind: "syntax") }
            for theme in changed(staging.themes, existing: themes) { try persist(theme, id: theme.id, kind: "theme") }
            for run in changed(staging.runs, existing: runs) { try persist(run, id: run.id, kind: "run") }
            try beforeBatchCommit?()
            try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }

    private func validateBackupIdentities(_ backup: Backup) throws {
        let collections: [(String, [UUID])] = [
            ("draft", backup.notes.map(\.id)),
            ("revision", backup.revisions.map(\.id)),
            ("workspace", backup.workspaces.map(\.id)),
            ("action", backup.actions.map(\.id)),
            ("action group", (backup.actionGroups ?? []).map(\.id)),
            ("syntax", (backup.syntaxes ?? []).map(\.id)),
            ("theme", (backup.themes ?? []).map(\.id)),
            ("execution", (backup.runs ?? []).map(\.id))
        ]
        for (kind, ids) in collections where Set(ids).count != ids.count {
            throw DraftlyError.message("The backup contains duplicate \(kind) identities.")
        }
    }

    private func recoveryIdentity<T: Encodable>(_ source: T, kind: String, existing: [T],
        id: (T) -> UUID, matches: (T, T) -> Bool) throws -> UUID {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(source)
        var attempt = 0
        while true {
            var input = Data("Draftly backup recovery v1/\(kind)/\(attempt)/".utf8)
            input.append(payload)
            var bytes = Array(SHA256.hash(data: input).prefix(16))
            bytes[6] = (bytes[6] & 0x0f) | 0x80
            bytes[8] = (bytes[8] & 0x3f) | 0x80
            let candidateID = bytes.withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress!) as UUID }
            guard let candidate = existing.first(where: { id($0) == candidateID }) else { return candidateID }
            if matches(candidate, source) { return candidateID }
            attempt += 1
        }
    }

    public static var defaultActions: [DraftAction] {
        var copy = DraftAction(name: "Copy", steps: [ActionStep("clipboard", ["template": "[[draft]]"])])
        copy.symbol = "doc.on.doc"; copy.shortcut = "1"
        var share = DraftAction(name: "Share", steps: [ActionStep("share", ["template": "[[draft]]"])])
        share.symbol = "square.and.arrow.up"
        var file = DraftAction(name: "Save to File", steps: [ActionStep("file", ["template": "[[draft]]", "name": "[[safe_title]].md"])])
        file.symbol = "folder"
        var preview = DraftAction(name: "Markdown Preview", steps: [ActionStep("htmlpreview", ["template": "[[draft]]"])])
        preview.symbol = "eye"
        var task = DraftAction(name: "Add to Reminders", steps: [ActionStep("reminder", ["template": "[[draft]]"])])
        task.symbol = "checklist"
        var event = DraftAction(name: "Add Calendar Event", steps: [ActionStep("event", ["template": "[[draft]]"])])
        event.symbol = "calendar"
        let defaults = [copy, share, file, preview, task, event]
        return defaults.enumerated().map { index, action in
            var action = action
            action.id = UUID(uuidString: String(format: "DAAF7100-0000-4000-8000-%012d", index + 1))!
            return action
        }
    }
}
