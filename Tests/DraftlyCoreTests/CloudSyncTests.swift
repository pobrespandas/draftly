import Foundation
import CloudKit
import CoreData
import Testing
@testable import DraftlyCore

@Suite("Cloud sync status") @MainActor
struct CloudSyncTests {
    @Test func concurrentEventsDoNotReportCompletionTooEarly() {
        var state = CloudSyncState(); state.account = .available
        let upload = UUID(), download = UUID()
        state.receive(id: upload, phase: .upload, ended: false, succeeded: false, error: nil)
        state.receive(id: download, phase: .download, ended: false, succeeded: false, error: nil)
        state.receive(id: upload, phase: .upload, ended: true, succeeded: true, error: nil)
        #expect(state.message.contains("Syncing"))
        state.receive(id: download, phase: .download, ended: true, succeeded: true, error: nil)
        #expect(state.message.contains("download completed"))
        #expect(state.message.contains("may still be pending"))
    }

    @Test func failedOperationSurvivesAnUnrelatedSuccess() {
        var state = CloudSyncState(); state.account = .available
        state.receive(id: UUID(), phase: .upload, ended: true, succeeded: false, error: "Network unavailable")
        state.receive(id: UUID(), phase: .download, ended: true, succeeded: true, error: nil)
        #expect(state.message == "iCloud upload: Network unavailable")
        state.receive(id: UUID(), phase: .upload, ended: true, succeeded: true, error: nil)
        #expect(state.message.contains("Other Macs may still be syncing"))
        state.receive(id: UUID(), phase: .setup, ended: true, succeeded: false, error: nil)
        #expect(state.message.contains("did not complete"))
    }

    @Test func partialCloudErrorsExposeCauseWithoutRecordIdentifiers() {
        let cause = NSError(domain: CKErrorDomain, code: CKError.permissionFailure.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid bundle ID for container"])
        let error = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "Partial Failure",
                                       CKPartialErrorsByItemIDKey: ["private-record-id": cause]])
        let message = CloudSyncError.message(error)
        #expect(message.contains("Invalid bundle ID for container"))
        #expect(!message.contains("private-record-id"))
        let sanitized = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue)
        #expect(CloudSyncError.message(sanitized).contains("app/container configuration"))
    }

    @Test func accountFailuresDoNotClaimSyncSuccess() {
        var state = CloudSyncState()
        #expect(state.message.contains("Checking"))
        state.account = .signedOut; #expect(state.message.contains("Sign in"))
        state.account = .restricted; #expect(state.message.contains("restricted"))
        state.account = .temporarilyUnavailable; #expect(state.message.contains("temporarily unavailable"))
        state.account = .failed("Test error"); #expect(state.message == "iCloud account: Test error")
    }

    @Test func upgradingAStoreWithoutHistoryPreservesExistingRecords() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = try LibraryStore(inMemory: true, seed: false).container.managedObjectModel
        let legacy = NSPersistentContainer(name: "Draftly", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: folder.appendingPathComponent("Library.sqlite"))
        description.shouldAddStoreAsynchronously = false
        legacy.persistentStoreDescriptions = [description]
        var loadError: Error?
        legacy.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        let note = Note(content: "Legacy local note 🐼", tags: ["legacy"])
        let record = NSEntityDescription.insertNewObject(forEntityName: "Record", into: legacy.viewContext)
        record.setValue("note:" + note.id.uuidString, forKey: "key")
        record.setValue("note", forKey: "kind")
        record.setValue(String(decoding: try JSONEncoder().encode(note), as: UTF8.self), forKey: "payload")
        record.setValue(note.modifiedAt, forKey: "modified")
        try legacy.viewContext.save()
        for store in legacy.persistentStoreCoordinator.persistentStores {
            try legacy.persistentStoreCoordinator.remove(store)
        }
        let upgraded = try LibraryStore(directory: folder, seed: false)
        #expect(upgraded.notes.first?.id == note.id)
        #expect(upgraded.notes.first?.content == note.content)
        #expect(upgraded.notes.first?.tags == note.tags)
        #expect(upgraded.notes.first?.accessedAt == nil)
        #expect(upgraded.container.persistentStoreDescriptions.first?.options[NSPersistentHistoryTrackingKey] as? Bool == true)
    }

    @Test func localLibraryIgnoresCloudAccountChecksAndReopensWithoutLoss() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let id: UUID
        do {
            let library = try LibraryStore(directory: folder, seed: false)
            id = try library.createNote(content: "Upgrade test 🐼\nSecond line", tags: ["test"]).id
            await library.refreshCloudAccount()
            #expect(library.cloudIdentifier == nil)
            #expect(library.syncStatus == "Local storage · iCloud is not configured")
        }
        let reopened = try LibraryStore(directory: folder, seed: false)
        #expect(reopened.notes.first?.id == id)
        #expect(reopened.notes.first?.content == "Upgrade test 🐼\nSecond line")
        #expect(reopened.notes.first?.tags == ["test"])
        let restored = try LibraryStore(inMemory: true, cloudIdentifier: "iCloud.example.invalid", seed: false)
        #expect(restored.cloudIdentifier == nil)
        try restored.restore(reopened.backupData())
        #expect(restored.notes.first?.id == id)
    }
}
