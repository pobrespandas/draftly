import Foundation
import CryptoKit
import Testing
@_spi(DraftlyInternal) @testable import DraftlyCore

@Suite("Drafts action group file import") @MainActor
struct DraftsActionGroupImportTests {
    @Test func officialGroupPayloadInInstallationLinkKeepsGroupAndOrder() throws {
        let fixture = try #require(Bundle.module.url(forResource: "drafts-directory-basic-2026-10-29.synthetic", withExtension: "draftsActionGroup", subdirectory: "Fixtures"))
        let json = try DraftsActionGroupImport.decompress(Data(contentsOf: fixture))
        var link = URLComponents(); link.scheme = "draftly"; link.host = "actionGroup"
        link.queryItems = [URLQueryItem(name: "data", value: String(decoding: json, as: UTF8.self))]
        let result = try ActionImporter.installationData(#require(link.url))
        let backup = try JSONDecoder().decode(Backup.self, from: result)
        let group = try #require(backup.actionGroups?.first)
        let actions = try #require(backup.actions)
        #expect(group.id.uuidString == "078CF5D6-AD76-419C-AF19-A7EC3236F21B")
        #expect(group.symbol == "arrow.up.forward.app")
        #expect(actions.count == 31 && actions.first?.name == "Copy")
        #expect(actions.filter(\.isSeparator).map(\.name) == ["Services", "Apps"])
        #expect(actions.enumerated().allSatisfy { $0.element.options?.order == $0.offset })
    }
    @Test func legacyStepMetadataFormattingDoesNotCauseConflict() throws {
        let url = try #require(Bundle.module.url(forResource: "drafts-directory-basic-2026-10-29.synthetic", withExtension: "draftsActionGroup", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let library = try LibraryStore(inMemory: true, seed: false)
        try LibraryFileImport.apply(data, fileExtension: "draftsActionGroup", to: library)
        var action = try #require(library.actions.first { $0.name == "Message" })
        let original = try #require(action.steps[0].values["data"])
        let object = try JSONSerialization.jsonObject(with: Data(original.utf8))
        let legacy = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]), as: UTF8.self)
        action.steps[0].values["data"] = legacy
        try library.saveAction(action)
        try LibraryFileImport.apply(data, fileExtension: "draftsActionGroup", to: library)
        #expect(library.actions.first { $0.id == action.id } == action)
        action.steps[0].values["subjectTemplate"] = "Local edit"
        try library.saveAction(action)
        #expect(throws: (any Error).self) { try LibraryFileImport.apply(data, fileExtension: "draftsActionGroup", to: library) }
        #expect(library.actions.first { $0.id == action.id } == action)
    }
    @Test func officialPopulatedPayloadKeepsOrderSeparatorsAndGroupSymbol() throws {
        let url = try #require(Bundle.module.url(forResource: "drafts-directory-basic-2026-10-29.synthetic", withExtension: "draftsActionGroup", subdirectory: "Fixtures"))
        let library = try LibraryStore(inMemory: true, seed: false)
        let data = try Data(contentsOf: url)
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == "141e7b7c29e0b56e3543f3c5d916b7dbdf1a74230a2e8cd9d4d3e7f3d97e519e")
        try LibraryFileImport.apply(data, fileExtension: "draftsActionGroup", to: library)
        let group = try #require(library.actionGroups.first)
        #expect(group.id.uuidString == "078CF5D6-AD76-419C-AF19-A7EC3236F21B")
        #expect(group.symbol == "arrow.up.forward.app")
        let expected = ["Copy", "Share", "Mail", "Message", "Post to Mastodon", "Google Search", "Event", "Send to Reminders", "List in Reminders", "Print - Plain Text", "Services", "Save to Files", "Save to Files as...", "Save to iCloud Drive", "Append to iCloud Journal", "Save to Dropbox", "Append to Dropbox Journal", "Save to Google Drive", "Save as Google Doc", "Append to Google Drive Journal", "Save to OneDrive", "Append to OneDrive Journal", "Save to OneNote", "Append to OneNote Journal", "Post to WordPress", "Post to Ghost", "Save to Box", "Append to Box Journal", "AI", "Using ChatGPT & AI", "Apps"]
        #expect(library.orderedActions().map(\.name) == expected)
        #expect(library.orderedActions().filter(\.isSeparator).map(\.name) == ["Services", "Apps"])
        #expect(library.groupNames(on: .list).contains(group.name))
        #expect(!library.groupNames(on: .bar).contains(group.name))
        let (_, decoded) = try DraftsActionGroupImport.decode(data)
        for action in decoded {
            let stored = try #require(library.actions.first { $0.id == action.id })
            #expect(stored == action, Comment(rawValue: "Mismatch: \(action.name)"))
        }
        try LibraryFileImport.apply(data, fileExtension: "draftsActionGroup", to: library)
        #expect(library.orderedActions().map(\.name) == expected)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.orderedActions().map(\.name) == expected)
        #expect(restored.actionGroups == [group])
        #expect(restored.orderedActions().allSatisfy { $0.rawPayload != nil })
    }
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
        #expect(group.symbol == "circle.circle")
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

    @Test func observedMacVisibilityFlagsFilterSurfacesButKeepCatalogAndIdentity() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let (original, _) = try DraftsActionGroupImport.decode(fixture())
        var action = DraftAction(name: "Neutral action", steps: []); action.group = original.name
        try library.saveAction(action)
        for (surface, bit) in [(ActionSurface.list, 128), (.bar, 256), (.search, 1024)] {
            var group = original
            group.importedMetadata["visibility"] = .number(Decimal(2016 - bit))
            try library.saveActionGroup(group)
            #expect(!library.groupNames(on: surface).contains(group.name))
            #expect(library.orderedActions(on: surface).isEmpty)
            #expect(library.groupNames.contains(group.name))
            #expect(library.orderedActions() == [action])
            #expect(library.actionGroupIdentifiers[group.name] == group.id)
            for other in [ActionSurface.list, .bar, .search] where other != surface {
                #expect(library.groupNames(on: other).contains(group.name))
                #expect(library.orderedActions(on: other) == [action])
            }
        }
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(!restored.groupNames(on: .search).contains(original.name))
        #expect(restored.orderedActions() == [action])
    }

    @Test func absentAndInvalidVisibilityRetainExistingDefaults() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var group = ActionGroupRecord(name: "Neutral")
        var action = DraftAction(name: "Visible", steps: []); action.group = group.name
        try library.saveAction(action)
        for value: JSONValue? in [nil, .string("unknown"), .number(-1), .number(1.5)] {
            group.importedMetadata["visibility"] = value
            try library.saveActionGroup(group)
            for surface in [ActionSurface.list, .bar, .search] {
                #expect(library.groupNames(on: surface).contains(group.name))
                #expect(library.orderedActions(on: surface) == [action])
            }
        }
    }

    @Test(arguments: [128, 256, 1024])
    func visibilitySurvivesLibraryReopenAndBackup(bit: Int) throws {
        let surface: ActionSurface = bit == 128 ? .list : bit == 256 ? .bar : .search
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try LibraryStore(directory: directory, seed: false)
        try LibraryFileImport.apply(fixture(), fileExtension: "draftsActionGroup", to: library)
        var group = try #require(library.actionGroups.first)
        group.importedMetadata["visibility"] = .number(Decimal(2016 - bit))
        try library.saveActionGroup(group)
        var action = DraftAction(name: "Neutral action", steps: [])
        action.group = group.name
        try library.saveAction(action)

        let reopened = try LibraryStore(directory: directory, seed: false)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        for store in [reopened, restored] {
            #expect(store.actionGroups == [group])
            #expect(store.actionGroupIdentifiers[group.name] == group.id)
            #expect(store.orderedActions() == [action])
            #expect(!store.groupNames(on: surface).contains(group.name))
            #expect(store.orderedActions(on: surface).isEmpty)
            for other in [ActionSurface.list, .bar, .search] where other != surface {
                #expect(store.groupNames(on: other).contains(group.name))
                #expect(store.orderedActions(on: other) == [action])
            }
        }
    }
}
