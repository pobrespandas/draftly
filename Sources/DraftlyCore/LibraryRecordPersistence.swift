import Foundation
import CoreData
import CloudKit

@MainActor
final class LibraryRecordPersistence {
    let container: NSPersistentContainer
    let isNewStore: Bool
    private var records: [String: NSManagedObject] = [:]

    init(inMemory: Bool, cloudIdentifier: String?, directory: URL?) throws {
        let model = Self.model()
        let persistentURL = inMemory ? nil : Self.storeURL(directory: directory)
        isNewStore = inMemory || persistentURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true
        if !inMemory { try Self.createStoreDirectory(directory: directory) }
        if let cloudIdentifier, !inMemory {
            let cloud = NSPersistentCloudKitContainer(name: "Draftly", managedObjectModel: model)
            container = cloud
            let description = NSPersistentStoreDescription(url: persistentURL!)
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudIdentifier)
            options.databaseScope = .private
            description.cloudKitContainerOptions = options
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
        } else {
            container = NSPersistentContainer(name: "Draftly", managedObjectModel: model)
            let description = NSPersistentStoreDescription()
            description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            if !inMemory {
                description.url = persistentURL
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
    }

    private static func createStoreDirectory(directory: URL?) throws {
        let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draftly", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private static func storeURL(directory: URL?) -> URL {
        let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draftly", isDirectory: true)
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

    @discardableResult
    func reloadRecords() throws -> [String: NSManagedObject] {
        let objects = try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Record"))
        var unique: [String: NSManagedObject] = [:]
        for object in objects {
            guard let key = object.value(forKey: "key") as? String else { continue }
            let previous = unique[key]?.value(forKey: "modified") as? Date ?? .distantPast
            let date = object.value(forKey: "modified") as? Date ?? .distantPast
            if unique[key] == nil || date > previous { unique[key] = object }
        }
        records = unique
        return unique
    }

    func decode<T: Decodable>(_ kind: String, _ type: T.Type) throws -> [T] {
        try records.values.filter { !$0.isDeleted && $0.value(forKey: "kind") as? String == kind }.map { object in
            guard let string = object.value(forKey: "payload") as? String, let data = string.data(using: .utf8) else {
                throw DraftlyError.message("Cannot read a stored \(kind) record. Restore a backup before changing the library.")
            }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }
    func persist<T: Encodable>(_ item: T, id: UUID, kind: String) throws {
        let key = "\(kind):\(id.uuidString)"
        let payload = String(data: try JSONEncoder().encode(item), encoding: .utf8)!
        let record = records[key] ?? NSEntityDescription.insertNewObject(forEntityName: "Record", into: container.viewContext)
        record.setValue(key, forKey: "key"); record.setValue(kind, forKey: "kind")
        record.setValue(payload, forKey: "payload"); record.setValue(Date(), forKey: "modified")
        records[key] = record
    }

    func commit(reload: () throws -> Void) throws {
        do { try container.viewContext.save(); try reload() }
        catch { container.viewContext.rollback(); try? reload(); throw error }
    }
    func record(for key: String) -> NSManagedObject? { records[key] }
}
