import Foundation
import CoreData
import CryptoKit
import Darwin
import DraftlyCore
import AgentContracts
import AgentLocalSecurity

// Identifies the loaded local store without changing its Core Data metadata.
@MainActor final class AgentLibraryLocation {
    let url: URL
    let storeID: UUID
    let volumeID: UUID
    let fileID: String
    let locationKey: String
    let physicalKey: String
    private let descriptor: Int32
    private let library: LibraryStore
    private let store: NSPersistentStore

    init(library: LibraryStore) throws {
        let coordinator = library.container.persistentStoreCoordinator
        guard coordinator.persistentStores.count == 1, let store = coordinator.persistentStores.first,
              store.type == NSSQLiteStoreType, let source = store.url, source.isFileURL else { throw AgentErrorCode.unavailable }
        guard let rawID = coordinator.metadata(for: store)[NSStoreUUIDKey] as? String,
              let storeID = UUID(uuidString: rawID) else { throw AgentErrorCode.storageError }
        guard let physical = realpath(source.path, nil) else { throw AgentErrorCode.storageError }
        defer { free(physical) }
        let file = Darwin.open(physical, O_RDONLY | O_NONBLOCK | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard file >= 0 else { throw AgentErrorCode.permissionDenied }
        do {
            let info = try Self.checkedInfo(file)
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(file, F_GETPATH, &buffer) == 0, let end = buffer.firstIndex(of: 0),
                  let canonical = String(validating: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self),
                  !canonical.isEmpty else { throw AgentErrorCode.storageError }
            let url = URL(fileURLWithPath: canonical)
            let volume = try url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
            guard let volume, let volumeID = UUID(uuidString: volume) else { throw AgentErrorCode.unavailable }
            let parent = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
            guard parent >= 0 else { throw AgentErrorCode.permissionDenied }
            defer { Darwin.close(parent) }
            try AgentPrivateFilePolicy.validateTrustedParent(parent)
            self.url = url; self.storeID = storeID; self.volumeID = volumeID; fileID = String(info.st_ino)
            locationKey = Self.key("location", canonical)
            physicalKey = Self.key("physical", volumeID.uuidString + ":" + String(info.st_ino))
            descriptor = file; self.library = library; self.store = store
        } catch { Darwin.close(file); throw error }
    }

    deinit { Darwin.close(descriptor) }

    func validate() throws {
        let held = try Self.checkedInfo(descriptor)
        var current = stat()
        guard lstat(url.path, &current) == 0, current.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              held.st_dev == current.st_dev, held.st_ino == current.st_ino else { throw AgentErrorCode.versionConflict }
        let coordinator = library.container.persistentStoreCoordinator
        guard coordinator.persistentStores.count == 1, coordinator.persistentStores.first === store,
              let currentID = coordinator.metadata(for: store)[NSStoreUUIDKey] as? String,
              UUID(uuidString: currentID) == storeID, let loadedURL = store.url else { throw AgentErrorCode.versionConflict }
        guard let loadedPath = realpath(loadedURL.path, nil) else { throw AgentErrorCode.versionConflict }
        defer { free(loadedPath) }
        var loaded = stat()
        guard lstat(loadedPath, &loaded) == 0, loaded.st_dev == held.st_dev, loaded.st_ino == held.st_ino else {
            throw AgentErrorCode.versionConflict
        }
    }

    private static func checkedInfo(_ descriptor: Int32) throws -> stat {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(), info.st_nlink == 1,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_mode & mode_t(0o022) == 0 else {
            throw AgentErrorCode.permissionDenied
        }
        return info
    }

    private static func key(_ domain: String, _ value: String) -> String {
        SHA256.hash(data: Data(("Draftly agent " + domain + " v1\0" + value).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
