import Foundation
import CoreData
import CloudKit
import Combine

@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var notes: [Note] = []
    @Published public private(set) var revisions: [Revision] = []
    @Published public private(set) var workspaces: [Workspace] = []
    @Published public private(set) var actions: [DraftAction] = []
    @Published public private(set) var runs: [ActionRun] = []
    @Published public var error: String?
    @Published public private(set) var syncStatus: String
    public let container: NSPersistentContainer
    private var observers: [NSObjectProtocol] = []
    private var records: [String: NSManagedObject] = [:]

    public init(inMemory: Bool = false, cloudIdentifier: String? = nil, directory: URL? = nil, seed: Bool = true) throws {
        let model = Self.model()
        if let cloudIdentifier, !inMemory {
            let cloud = NSPersistentCloudKitContainer(name: "Draftly", managedObjectModel: model)
            container = cloud
            syncStatus = "Connecting to iCloud…"
            let description = NSPersistentStoreDescription(url: try Self.storeURL(directory: directory))
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudIdentifier)
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
        } else {
            container = NSPersistentContainer(name: "Draftly", managedObjectModel: model)
            syncStatus = inMemory ? "Test storage" : "Local storage · iCloud is not configured"
            let description = NSPersistentStoreDescription()
            description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            if !inMemory { description.url = try Self.storeURL(directory: directory) }
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
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                do { try self?.reload() } catch { self?.error = error.localizedDescription }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] notification in
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event
            let status: String
            if let error = event?.error { status = "iCloud: \(error.localizedDescription)" }
            else if event?.endDate != nil { status = "iCloud up to date" }
            else { status = "Syncing with iCloud…" }
            Task { @MainActor in self?.syncStatus = status }
        })
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
        notes = try decode("note", Note.self)
        revisions = try decode("revision", Revision.self).sorted { $0.date > $1.date }
        workspaces = try decode("workspace", Workspace.self).sorted { $0.name < $1.name }
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

    public func saveNote(_ note: Note, preserveRevision: Bool = true, preserveDates: Bool = false) throws {
        var note = note
        note.tags = TagRules.normalize(note.tags)
        if let previous = notes.first(where: { $0.id == note.id }), previous == note { return }
        if preserveRevision {
            let snapshot = Revision(noteID: note.id, content: note.content)
            if revisions.first(where: { $0.noteID == note.id })?.content != note.content {
                try persist(snapshot, id: snapshot.id, kind: "revision")
            }
        }
        if !preserveDates { note.modifiedAt = Date() }
        try persist(note, id: note.id, kind: "note"); try commit()
    }

    @discardableResult public func createNote(content: String = "", tags: [String] = []) throws -> Note {
        var note = Note(content: content, tags: tags); note.tags = TagRules.normalize(tags); try saveNote(note); return note
    }
    public func saveWorkspace(_ workspace: Workspace) throws { try persist(workspace, id: workspace.id, kind: "workspace"); try commit() }
    public func saveAction(_ action: DraftAction) throws { try persist(action, id: action.id, kind: "action"); try commit() }
    public func log(_ run: ActionRun) { do { try persist(run, id: run.id, kind: "run"); try commit() } catch { self.error = error.localizedDescription } }
    public func deleteAction(_ id: UUID) throws { try delete(id, kind: "action") }
    public func deleteWorkspace(_ id: UUID) throws { try delete(id, kind: "workspace") }
    public func deleteRevision(_ id: UUID) throws { try delete(id, kind: "revision") }
    public func deleteRun(_ id: UUID) throws { try delete(id, kind: "run") }
    public func saveRevision(_ revision: Revision) throws { try persist(revision, id: revision.id, kind: "revision"); try commit() }
    private func delete(_ id: UUID, kind: String) throws {
        let key = "\(kind):\(id.uuidString)"
        let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
        request.predicate = NSPredicate(format: "key == %@", key)
        for record in try container.viewContext.fetch(request) { container.viewContext.delete(record) }
        try commit()
    }
    public func backupData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Backup(notes: notes, revisions: revisions, workspaces: workspaces, actions: actions))
    }
    public func restore(_ data: Data) throws {
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        guard backup.version == 1 else { throw DraftlyError.message("This backup version is not supported.") }
        // Keep both versions when a backup contains a different note with the same ID.
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
        for workspace in backup.workspaces { try persist(workspace, id: workspace.id, kind: "workspace") }
        for action in backup.actions { try persist(action, id: action.id, kind: "action") }
        try commit()
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
