import Foundation
import CoreData
import Testing
import AgentContracts
import AgentLocalSecurity
@testable import DraftlyCore
@testable import Draftly

@Suite("Stable local agent library ownership") @MainActor
struct AgentHostLeaseTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Host-Lease-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
    private func close(_ library: LibraryStore) throws {
        library.container.viewContext.reset()
        for store in library.container.persistentStoreCoordinator.persistentStores {
            try library.container.persistentStoreCoordinator.remove(store)
        }
    }
    private func identityFile(_ location: AgentLibraryLocation) -> URL {
        location.url.deletingLastPathComponent().appendingPathComponent("Agents").appendingPathComponent(location.locationKey + ".identity.json")
    }
    private func replaceIdentity(_ fields: [String: AgentJSONValue], at url: URL) throws {
        try JSONEncoder().encode(AgentJSONValue.object(fields)).write(to: url)
    }

    @Test func identitySurvivesARealStoreReopenWithoutChangingMetadataOrDrafts() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false)
        let note = try library.createNote(content: "Neutral stable 🐼")
        let before = try library.backupData(), location = try AgentLibraryLocation(library: library)
        let lease = try AgentHostLease(location: location), id = lease.libraryID
        let file = identityFile(location), bytes = try Data(contentsOf: file)
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        try lease.validate(); lease.close(); try close(library)
        let reopened = try LibraryStore(directory: root, seed: false), nextLocation = try AgentLibraryLocation(library: reopened)
        let next = try AgentHostLease(location: nextLocation); defer { next.close() }
        #expect(next.libraryID == id && nextLocation.storeID == location.storeID)
        #expect(nextLocation.fileID == location.fileID && nextLocation.volumeID == location.volumeID)
        #expect(reopened.notes.first?.id == note.id && reopened.notes.first?.content == note.content)
        #expect(try reopened.backupData() == before)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == modified)
        let store = try #require(reopened.container.persistentStoreCoordinator.persistentStores.first)
        let storedID = reopened.container.persistentStoreCoordinator.metadata(for: store)[NSStoreUUIDKey] as? String
        #expect(storedID.flatMap { UUID(uuidString: $0) } == nextLocation.storeID)
    }

    @Test func sameLibraryCannotHaveTwoOwnersAndDeinitReleasesOwnership() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false), location = try AgentLibraryLocation(library: library)
        var lease: AgentHostLease? = try AgentHostLease(location: location)
        let id = try #require(lease).libraryID
        #expect(throws: AgentErrorCode.busy) { try AgentHostLease(location: AgentLibraryLocation(library: library)) }
        weak var previous = lease
        lease = nil
        #expect(previous == nil)
        let next = try AgentHostLease(location: AgentLibraryLocation(library: library)); defer { next.close() }
        #expect(next.libraryID == id)
        next.close(); next.close()
        #expect(throws: AgentErrorCode.cancelled) { try next.validate() }
    }

    @Test func aClosedDatabaseCopyKeepsItsStoreUUIDButGetsAnotherAgentIdentity() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source"), copy = root.appendingPathComponent("Copy")
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let library = try LibraryStore(directory: source, seed: false)
        let note = try library.createNote(content: "Neutral copied draft")
        let location = try AgentLibraryLocation(library: library), original = try AgentHostLease(location: location)
        let id = original.libraryID; original.close(); try close(library)
        // The coordinator is closed before copying SQLite; no live WAL is omitted.
        try FileManager.default.copyItem(at: source.appendingPathComponent("Library.sqlite"), to: copy.appendingPathComponent("Library.sqlite"))
        let copied = try LibraryStore(directory: copy, seed: false), copiedLocation = try AgentLibraryLocation(library: copied)
        let next = try AgentHostLease(location: copiedLocation); defer { next.close() }
        #expect(copiedLocation.storeID == location.storeID && copiedLocation.locationKey != location.locationKey)
        #expect(next.libraryID != id && copied.notes.first?.id == note.id && copied.notes.first?.content == note.content)
    }

    @Test func symbolicDirectoryAliasesResolveToOneOwnerAndIdentity() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Library"), alias = root.appendingPathComponent("Alias")
        let library = try LibraryStore(directory: directory, seed: false)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        let alternate = try LibraryStore(directory: alias, seed: false)
        let location = try AgentLibraryLocation(library: library), other = try AgentLibraryLocation(library: alternate)
        #expect(other.locationKey == location.locationKey && other.physicalKey == location.physicalKey)
        let owner = try AgentHostLease(location: location), id = owner.libraryID
        #expect(throws: AgentErrorCode.busy) { try AgentHostLease(location: other) }
        owner.close()
        let next = try AgentHostLease(location: other); defer { next.close() }
        #expect(next.libraryID == id)
    }

    @Test func deletingAnIdentityCannotStartASecondHostOrResurrectTheOldGrantBinding() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false), location = try AgentLibraryLocation(library: library)
        let lease = try AgentHostLease(location: location), id = lease.libraryID
        try FileManager.default.removeItem(at: identityFile(location))
        #expect(throws: AgentErrorCode.versionConflict) { try lease.validate() }
        #expect(throws: AgentErrorCode.busy) { try AgentHostLease(location: location) }
        lease.close()
        let next = try AgentHostLease(location: location); defer { next.close() }
        #expect(next.libraryID != id)
    }

    @Test func inMemoryLibrariesDoNotCreatePersistentAgentState() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        #expect(throws: AgentErrorCode.unavailable) { try AgentLibraryLocation(library: library) }
    }

    @Test func replacingAFileAtTheSamePathDoesNotReuseACopiedStoreBinding() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false), note = try library.createNote(content: "Neutral replacement")
        let location = try AgentLibraryLocation(library: library), owner = try AgentHostLease(location: location), id = owner.libraryID
        try close(library)
        let replacement = root.appendingPathComponent("replacement.sqlite")
        try FileManager.default.copyItem(at: location.url, to: replacement)
        try FileManager.default.moveItem(at: location.url, to: root.appendingPathComponent("old.sqlite"))
        try FileManager.default.moveItem(at: replacement, to: location.url)
        let reopened = try LibraryStore(directory: root, seed: false), nextLocation = try AgentLibraryLocation(library: reopened)
        #expect(nextLocation.storeID == location.storeID && nextLocation.fileID != location.fileID)
        #expect(throws: AgentErrorCode.versionConflict) { try owner.validate() }
        #expect(throws: AgentErrorCode.busy) { try AgentHostLease(location: nextLocation) }
        owner.close()
        let next = try AgentHostLease(location: nextLocation); defer { next.close() }
        #expect(next.libraryID != id && reopened.notes.first?.id == note.id && reopened.notes.first?.content == note.content)
    }

    @Test func changedLoadedStoreMetadataInvalidatesTheOwnerWithoutChangingDraftIDs() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false), note = try library.createNote(content: "Neutral metadata")
        let location = try AgentLibraryLocation(library: library), owner = try AgentHostLease(location: location)
        defer { owner.close() }
        let coordinator = library.container.persistentStoreCoordinator, store = try #require(coordinator.persistentStores.first)
        let previous = coordinator.metadata(for: store)
        defer { coordinator.setMetadata(previous, for: store) }
        var changed = previous; changed[NSStoreUUIDKey] = UUID().uuidString
        coordinator.setMetadata(changed, for: store)
        #expect(throws: AgentErrorCode.versionConflict) { try owner.validate() }
        #expect(library.notes.first?.id == note.id)
    }

    @Test func malformedOrForeignIdentityRecordsAreNotRepairedAndReleaseTheirLocks() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false), location = try AgentLibraryLocation(library: library)
        let owner = try AgentHostLease(location: location), id = owner.libraryID, file = identityFile(location)
        owner.close()
        let valid = try Data(contentsOf: file)
        guard case .object(let base) = try JSONDecoder().decode(AgentJSONValue.self, from: valid) else { Issue.record("Invalid fixture"); return }
        var unknown = base; unknown["approved"] = .bool(true)
        var foreign = base; foreign["locationKey"] = .string(String(repeating: "0", count: 64))
        var version = base; version["version"] = .integer(2)
        var invalidFileID = base; invalidFileID["fileID"] = .string("001")
        let invalid = try [unknown, foreign, version, invalidFileID].map { try JSONEncoder().encode(AgentJSONValue.object($0)) }
            + [Data("broken".utf8), Data(repeating: 32, count: 4097)]
        for bytes in invalid {
            try bytes.write(to: file)
            #expect(throws: AgentErrorCode.storageError) { try AgentHostLease(location: location) }
            #expect(try Data(contentsOf: file) == bytes)
            try valid.write(to: file)
            let recovered = try AgentHostLease(location: location)
            #expect(recovered.libraryID == id)
            recovered.close()
        }
    }

    @Test func manifestChangesDuringOwnershipInvalidateTheLeaseUntilRestart() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false), location = try AgentLibraryLocation(library: library)
        let owner = try AgentHostLease(location: location); defer { owner.close() }
        let file = identityFile(location), before = try Data(contentsOf: file)
        guard case .object(var fields) = try JSONDecoder().decode(AgentJSONValue.self, from: before) else { return }
        fields["libraryID"] = .string(UUID().uuidString)
        try replaceIdentity(fields, at: file)
        #expect(throws: AgentErrorCode.versionConflict) { try owner.validate() }
        try before.write(to: file)
        #expect(throws: AgentErrorCode.versionConflict) { try owner.validate() }
        owner.close()
        let restarted = try AgentHostLease(location: location); defer { restarted.close() }
        try restarted.validate()
    }

    @Test func manifestSymlinksCannotRedirectIdentityWrites() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false), location = try AgentLibraryLocation(library: library)
        let owner = try AgentHostLease(location: location), id = owner.libraryID, file = identityFile(location)
        owner.close()
        let original = try Data(contentsOf: file), target = root.appendingPathComponent("untouched")
        let neutral = Data("neutral".utf8); try neutral.write(to: target)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        #expect(throws: AgentErrorCode.permissionDenied) { try AgentHostLease(location: location) }
        #expect(try Data(contentsOf: target) == neutral)
        try FileManager.default.removeItem(at: file)
        try original.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let recovered = try AgentHostLease(location: location); defer { recovered.close() }
        #expect(recovered.libraryID == id)
    }

    @Test func linkedAndWorldWritableLibraryFilesAreNotAdoptedOrRepaired() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false), path = root.appendingPathComponent("Library.sqlite")
        let link = root.appendingPathComponent("linked.sqlite")
        try FileManager.default.linkItem(at: path, to: link)
        #expect(throws: AgentErrorCode.permissionDenied) { try AgentLibraryLocation(library: library) }
        try FileManager.default.removeItem(at: link)
        let previous = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions]
        defer { if let previous { try? FileManager.default.setAttributes([.posixPermissions: previous], ofItemAtPath: path.path) } }
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: path.path)
        #expect(throws: AgentErrorCode.permissionDenied) { try AgentLibraryLocation(library: library) }
        #expect(try (FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber)?.intValue == 0o666)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Agents").path))
    }

    @Test func differentRealLibrariesCanHoldIndependentOwnershipWithoutChangingTheirData() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try LibraryStore(directory: root.appendingPathComponent("A"), seed: false)
        let b = try LibraryStore(directory: root.appendingPathComponent("B"), seed: false)
        let noteA = try a.createNote(content: "Neutral A"), noteB = try b.createNote(content: "Neutral B")
        let first = try AgentHostLease(location: AgentLibraryLocation(library: a))
        let second = try AgentHostLease(location: AgentLibraryLocation(library: b))
        defer { first.close(); second.close() }
        #expect(first.libraryID != second.libraryID)
        try first.validate(); try second.validate()
        #expect(a.notes.first?.id == noteA.id && b.notes.first?.id == noteB.id)
    }


    @Test func temporaryIdentityLockContentionDoesNotDestroyOwnership() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false), location = try AgentLibraryLocation(library: library)
        let owner = try AgentHostLease(location: location); defer { owner.close() }
        let directory = try AgentStateDirectory(parentDirectory: root)
        let reader = try directory.acquireLock(location.locationKey + ".identity.lock")
        #expect(throws: AgentErrorCode.busy) { try owner.validate() }
        reader.release()
        try owner.validate()
    }

    @Test func unicodeStoragePathsRetainTheCorrectStoreAndBinding() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let name = "Biblioteca 🐼 é", directory = root.appendingPathComponent(name)
        let library = try LibraryStore(directory: directory, seed: false)
        let note = try library.createNote(content: "Neutral Unicode 🐼")
        let location = try AgentLibraryLocation(library: library), first = try AgentHostLease(location: location), id = first.libraryID
        #expect(location.url.deletingLastPathComponent().lastPathComponent == name)
        first.close()
        let reopened = try AgentHostLease(location: AgentLibraryLocation(library: library)); defer { reopened.close() }
        #expect(reopened.libraryID == id && library.notes.first?.id == note.id && library.notes.first?.content == note.content)
        try reopened.validate()
    }


    @Test func movingTheLibraryCannotBypassItsStillHeldPhysicalOwner() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source"), moved = root.appendingPathComponent("Moved")
        let library = try LibraryStore(directory: source, seed: false), note = try library.createNote(content: "Neutral moved draft")
        let location = try AgentLibraryLocation(library: library), owner = try AgentHostLease(location: location), id = owner.libraryID
        try close(library)
        try FileManager.default.moveItem(at: source, to: moved)
        let reopened = try LibraryStore(directory: moved, seed: false), other = try AgentLibraryLocation(library: reopened)
        #expect(other.locationKey != location.locationKey && other.physicalKey == location.physicalKey)
        #expect(throws: AgentErrorCode.busy) { try AgentHostLease(location: other) }
        #expect(throws: AgentErrorCode.permissionDenied) { try owner.validate() }
        owner.close()
        let next = try AgentHostLease(location: other); defer { next.close() }
        #expect(next.libraryID != id && reopened.notes.first?.id == note.id && reopened.notes.first?.content == note.content)
    }

}
