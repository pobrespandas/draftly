import Foundation
import CoreData
import CloudKit
import Combine

@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var notes: [Note] = []
    @Published public private(set) var revisions: [Revision] = []
    @Published public private(set) var workspaces: [Workspace] = []
    @Published public private(set) var actionGroups: [ActionGroupRecord] = []
    @Published public private(set) var actions: [DraftAction] = []
    @Published public private(set) var syntaxes: [SyntaxDefinition] = []
    @Published public private(set) var runs: [ActionRun] = []
    @Published public var error: String?
    @Published public private(set) var syncStatus: String
    public let container: NSPersistentContainer
    private var observers: [NSObjectProtocol] = []
    private var cloudState = CloudSyncState()
    private var accountCheck = 0
    public let cloudIdentifier: String?
    private var records: [String: NSManagedObject] = [:]

    public init(inMemory: Bool = false, cloudIdentifier: String? = nil, directory: URL? = nil, seed: Bool = true) throws {
        self.cloudIdentifier = inMemory ? nil : cloudIdentifier
        let model = Self.model()
        if let cloudIdentifier, !inMemory {
            let cloud = NSPersistentCloudKitContainer(name: "Draftly", managedObjectModel: model)
            container = cloud
            syncStatus = "Connecting to iCloud…"
            let description = NSPersistentStoreDescription(url: try Self.storeURL(directory: directory))
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudIdentifier)
            options.databaseScope = .private
            description.cloudKitContainerOptions = options
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
        } else {
            container = NSPersistentContainer(name: "Draftly", managedObjectModel: model)
            syncStatus = inMemory ? "Test storage" : "Local storage · iCloud is not configured"
            let description = NSPersistentStoreDescription()
            description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            if !inMemory {
                description.url = try Self.storeURL(directory: directory)
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            }
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
        }
        var loadError: Error?
        container.loadPersistentStores { _, e in loadError = e }
        if let loadError { throw loadError }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        try reload()
        if seed && actions.isEmpty {
            for action in Self.defaultActions { try saveAction(action) }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator, queue: .main) { [weak self] _ in
            Task { @MainActor in
                do { try self?.reload() } catch { self?.error = error.localizedDescription }
            }
        })
        if let cloud = container as? NSPersistentCloudKitContainer {
            observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: cloud, queue: .main) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
                let phase: CloudSyncState.Phase
                switch event.type {
                case .setup: phase = .setup
                case .import: phase = .download
                case .export: phase = .upload
                @unknown default: return
                }
                let id = event.identifier, storeID = event.storeIdentifier
                let ended = event.endDate != nil, succeeded = event.succeeded
                let message = event.error.map(CloudSyncError.message)
                Task { @MainActor in
                    guard let self, self.container.persistentStoreCoordinator.persistentStores.contains(where: { $0.identifier == storeID }) else { return }
                    self.cloudState.receive(id: id, phase: phase, ended: ended, succeeded: succeeded, error: message)
                    self.syncStatus = self.cloudState.message
                }
            })
            observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refreshCloudAccount() }
            })
            Task { @MainActor [weak self] in await self?.refreshCloudAccount() }
        }
    }

    public func refreshCloudAccount() async {
        guard let cloudIdentifier else { return }
        accountCheck += 1
        let check = accountCheck
        let account: CloudSyncState.Account
        do {
            switch try await CKContainer(identifier: cloudIdentifier).accountStatus() {
            case .available: account = .available
            case .noAccount: account = .signedOut
            case .restricted: account = .restricted
            case .temporarilyUnavailable: account = .temporarilyUnavailable
            case .couldNotDetermine: account = .failed("The account status could not be determined.")
            @unknown default: account = .failed("The account status is not supported.")
            }
        } catch { account = .failed(CloudSyncError.message(error)) }
        guard accountCheck == check else { return }
        cloudState.account = account
        syncStatus = cloudState.message
    }

    private static func storeURL(directory: URL?) throws -> URL {
        let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draftly", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Library.sqlite")
    }

    private static func model() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "Record"
        entity.managedObjectClassName = "NSManagedObject"
        func attribute(_ name: String, _ type: NSAttributeType, _ value: Any) -> NSAttributeDescription {
            let a = NSAttributeDescription(); a.name = name; a.attributeType = type
            a.isOptional = true; a.defaultValue = value; return a
        }
        entity.properties = [attribute("key", .stringAttributeType, ""), attribute("kind", .stringAttributeType, ""),
                             attribute("payload", .stringAttributeType, "{}"), attribute("modified", .dateAttributeType, Date(timeIntervalSince1970: 0))]
        model.entities = [entity]
        return model
    }

    private struct NoteAccess: Codable {
        var id: UUID
        var date: Date
    }

    public func reload() throws {
        let objects = try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Record"))
        var unique: [String: NSManagedObject] = [:]
        for object in objects {
            guard let key = object.value(forKey: "key") as? String else { continue }
            let previous = unique[key]?.value(forKey: "modified") as? Date ?? .distantPast
            let date = object.value(forKey: "modified") as? Date ?? .distantPast
            if unique[key] == nil || date > previous { unique[key] = object }
        }
        records = unique
        func decode<T: Decodable>(_ kind: String, _ type: T.Type) throws -> [T] {
            try unique.values.filter { $0.value(forKey: "kind") as? String == kind }.map { object in
                guard let string = object.value(forKey: "payload") as? String, let data = string.data(using: .utf8) else {
                    throw DraftlyError.message("Cannot read a stored \(kind) record. Restore a backup before changing the library.")
                }
                return try JSONDecoder().decode(T.self, from: data)
            }
        }
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
        let key = "\(kind):\(id.uuidString)"
        let payload = String(data: try JSONEncoder().encode(item), encoding: .utf8)!
        let record = records[key] ?? NSEntityDescription.insertNewObject(forEntityName: "Record", into: container.viewContext)
        record.setValue(key, forKey: "key"); record.setValue(kind, forKey: "kind")
        record.setValue(payload, forKey: "payload"); record.setValue(Date(), forKey: "modified")
        records[key] = record
    }

    private func commit() throws {
        do { try container.viewContext.save(); try reload() }
        catch { container.viewContext.rollback(); try? reload(); throw error }
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
        let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !actionGroups.contains(where: { $0.id != group.id && $0.name == name }) else { throw DraftlyError.message("Use a unique group name.") }
        let oldName = actionGroups.first(where: { $0.id == group.id })?.name ?? previousName
        guard !groupNames.contains(name) || oldName == name || name == group.name && oldName == nil && !actionGroups.contains(where: { $0.name == name }) else { throw DraftlyError.message("Use a unique group name.") }
        do {
            for (order, existingName) in groupNames.enumerated() where !actionGroups.contains(where: { $0.name == existingName }) && existingName != oldName && existingName != name {
                var record = ActionGroupRecord(name: existingName); record.order = order
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
        do {
            for group in values { try persist(group, id: group.id, kind: "actionGroup") }
            try beforeBatchCommit?(); try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func removeActionGroup(_ name: String, movingActionsTo destination: String) throws {
        guard name != destination, !destination.isEmpty else { throw DraftlyError.message("Choose another destination group.") }
        do {
            for var action in actions where action.group == name { action.group = destination; try persist(action, id: action.id, kind: "action") }
            if let group = actionGroups.first(where: { $0.name == name }), let record = records["actionGroup:" + group.id.uuidString] { container.viewContext.delete(record) }
            try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func log(_ run: ActionRun) { do { try persist(run, id: run.id, kind: "run"); try commit() } catch { self.error = error.localizedDescription } }
    public func deleteAction(_ id: UUID) throws { try delete(id, kind: "action") }
    public func deleteWorkspace(_ id: UUID) throws { try delete(id, kind: "workspace") }
    public func deleteRevision(_ id: UUID) throws {
        do { try delete(id, kind: "revision", beforeCommit: beforeBatchCommit) }
        catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    public func deleteRun(_ id: UUID) throws { try delete(id, kind: "run") }
    public func saveRevision(_ revision: Revision) throws {
        do {
            try persist(revision, id: revision.id, kind: "revision")
            try beforeBatchCommit?()
            try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    private func delete(_ id: UUID, kind: String, beforeCommit: (() throws -> Void)? = nil) throws {
        let key = "\(kind):\(id.uuidString)"
        let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
        request.predicate = NSPredicate(format: "key == %@", key)
        for record in try container.viewContext.fetch(request) { container.viewContext.delete(record) }
        try beforeCommit?()
        try commit()
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
    public func backupData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Backup(notes: notes, revisions: revisions, workspaces: workspaces, actions: actions, actionGroups: actionGroups, syntaxes: syntaxes))
    }
    public func restore(_ data: Data) throws {
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        guard backup.version == 1 else { throw DraftlyError.message("This backup version is not supported.") }
        let syntaxesToRestore = try (backup.syntaxes ?? []).map { try SyntaxDefinition(data: Data($0.source.utf8), type: $0.type, id: $0.id) }
        guard Set(syntaxesToRestore.map(\.name)).count == syntaxesToRestore.count,
              !syntaxesToRestore.contains(where: { incoming in ScriptSyntax.names.contains(incoming.name) || syntaxes.contains(where: { $0.name == incoming.name && $0.id != incoming.id }) }) else { throw DraftlyError.message("The backup contains conflicting syntax names.") }
        do {
        // Keep both versions when a backup contains a different draft with the same ID.
        var remapped: [UUID: UUID] = [:]
        for var note in backup.notes {
            if let existing = notes.first(where: { $0.id == note.id }), existing != note {
                let original = note.id; note.id = UUID(); remapped[original] = note.id
            }
            try persist(note, id: note.id, kind: "note")
        }
        for var revision in backup.revisions {
            if let newID = remapped[revision.noteID] { revision.noteID = newID; revision.id = UUID() }
            try persist(revision, id: revision.id, kind: "revision")
        }
        for syntax in syntaxesToRestore { try persist(syntax, id: syntax.id, kind: "syntax") }
        for workspace in backup.workspaces { try persist(workspace, id: workspace.id, kind: "workspace") }
        for group in backup.actionGroups ?? [] { try persist(group, id: group.id, kind: "actionGroup") }
        for action in backup.actions { try persist(action, id: action.id, kind: "action") }
        try beforeBatchCommit?(); try commit()
        } catch { container.viewContext.rollback(); try? reload(); throw error }
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
