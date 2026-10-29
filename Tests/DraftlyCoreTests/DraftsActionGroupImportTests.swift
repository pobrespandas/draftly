import Foundation
import Testing
@testable import DraftlyCore

@Suite("Drafts action group file import") @MainActor
struct DraftsActionGroupImportTests {
    private func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "drafts-54-empty-action-group", withExtension: "draftsActionGroup", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func realEmptyExportPreservesIdentityMetadataAndBackup() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let data = try fixture()
        try LibraryFileImport.apply(data, fileExtension: "draftsActionGroup", to: library)
        let group = try #require(library.actionGroups.first)
        #expect(group.name == "QA Included Configuration 20261022")
        #expect(group.id.uuidString == "0D1CD9D7-CA91-40E0-8600-0B79D6E642F4")
        #expect(group.importedMetadata["icon"] == .string("action_circle2"))
        #expect(group.importedMetadata["visibility"] == .number(2016))
        #expect(library.actions.isEmpty)
        try LibraryFileImport.apply(data, fileExtension: "draftsActionGroup", to: library)
        #expect(library.actionGroups == [group])
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.actionGroups == [group])
    }

    @Test func invalidAndCorruptExportsNeverMutateLibrary() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = try fixture()
        var badChecksum = original; badChecksum[badChecksum.count - 1] ^= 1
        var badHeader = original; badHeader[0] = 0
        for data in [Data(), badChecksum, badHeader, original.dropLast() as Data] {
            #expect(throws: (any Error).self) { try LibraryFileImport.apply(data, fileExtension: "draftsActionGroup", to: library) }
        }
        #expect(library.actionGroups.isEmpty && library.actions.isEmpty && library.notes.isEmpty)
    }

    @Test func writeFailureRollsBackAndRetrySucceeds() throws {
        enum Failure: Error { case commit }
        let library = try LibraryStore(inMemory: true, seed: false)
        let data = try fixture()
        library.beforeBatchCommit = { throw Failure.commit }
        #expect(throws: Failure.commit) { try LibraryFileImport.apply(data, fileExtension: "draftsActionGroup", to: library) }
        library.beforeBatchCommit = nil
        try library.reload(); #expect(library.actionGroups.isEmpty)
        try LibraryFileImport.apply(data, fileExtension: "draftsActionGroup", to: library)
        #expect(library.actionGroups.count == 1)
    }

    @Test func compressedOutputLimitRejectsOversizedData() throws {
        let input = Data(repeating: 65, count: 16 * 1024 * 1024 + 1)
        let raw = try (input as NSData).compressed(using: .zlib) as Data
        let wrapped = Data([0x78, 0x9c]) + raw + Data(repeating: 0, count: 4)
        do {
            _ = try DraftsActionGroupImport.decode(wrapped)
            Issue.record("Oversized output was accepted")
        } catch {
            #expect(error.localizedDescription.contains("size limit"))
        }
    }

    @Test func existingGroupConflictDoesNotOverwriteItsData() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var existing = ActionGroupRecord(name: "QA Included Configuration 20261022")
        existing.id = UUID(); existing.symbol = "star.fill"
        try library.saveActionGroup(existing)
        #expect(throws: (any Error).self) { try LibraryFileImport.apply(fixture(), fileExtension: "draftsActionGroup", to: library) }
        try library.reload()
        #expect(library.actionGroups == [existing] && library.actions.isEmpty)
    }
}
