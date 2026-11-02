import Foundation
import CoreData
import Testing
@testable import DraftlyCore

@Suite("Atomic note mutation receipts") @MainActor
struct LibraryMutationReceiptTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func identity(request: UUID = UUID(), connection: String = String(repeating: "a", count: 64),
                          hash: String = String(repeating: "b", count: 64)) -> LibraryMutationIdentity {
        .init(requestID: request, connectionHash: connection, requestHash: hash)
    }
    nonisolated private static func resources(_ notes: [Note]) -> [LibraryMutationReceipt.Resource] {
        notes.map { .init(id: $0.id, versionToken: "opaque-neutral-version") }
    }

    @Test func groupRenameRollsBackActionsAndImplicitGroupsOnFailure() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var first = DraftAction(name: "One", steps: []); first.group = "Original"
        var second = DraftAction(name: "Two", steps: []); second.group = "Other"
        try library.saveActions([first, second])
        let identifiers = library.actionGroupIdentifiers
        var renamed = library.actionGroupRecord(named: "Original"); renamed.name = "Renamed"
        let mutation = identity()
        #expect(throws: (any Error).self) {
            try library.commitActionGroup(renamed, mutation: mutation, at: now, previousName: "Original",
                validateCommit: { throw DraftlyError.message("Authority changed") }) {
                    .init(id: $0.id, versionToken: "opaque-version")
                }
        }
        #expect(Set(library.actions.map(\.id)) == Set([first.id, second.id]))
        #expect(library.actions.contains(first) && library.actions.contains(second))
        #expect(library.actionGroupIdentifiers == identifiers && library.actionGroups.isEmpty)
        #expect(try library.mutationReceipt(for: mutation, at: now) == nil)
    }

    @Test func groupReorderRollsBackAllRecordsOnFailure() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var a = ActionGroupRecord(name: "Alpha"); a.order = 0
        var b = ActionGroupRecord(name: "Beta"); b.order = 1
        try library.saveActionGroups([a, b])
        var changedA = a; changedA.order = 1
        var changedB = b; changedB.order = 0
        let mutation = identity()
        #expect(throws: (any Error).self) {
            try library.commitActionGroups([changedB, changedA], mutation: mutation, at: now,
                validateCommit: { throw DraftlyError.message("Authority changed") }) { groups in
                    groups.map { .init(id: $0.id, versionToken: "opaque-version") }
                }
        }
        #expect(library.groupNames == ["Alpha", "Beta"])
        #expect(try library.mutationReceipt(for: mutation, at: now) == nil)
    }

    @Test func groupCopyCommitsAllItemsOnceAndRollsBackOnFailure() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var original = DraftAction(name: "Original", steps: []); original.group = "Source"
        try library.saveAction(original)
        let identifiers = library.actionGroupIdentifiers
        let group = ActionGroupRecord(name: "Copy")
        var copy = original; copy.id = UUID(); copy.group = group.name; copy.shortcut = ""
        let mutation = identity()
        #expect(throws: (any Error).self) {
            try library.commitActionGroupCopy(group, actions: [copy], mutation: mutation, at: now,
                validateCommit: { throw DraftlyError.message("Authority changed") }) {
                    .init(id: $0.id, versionToken: "opaque-version")
                }
        }
        #expect(library.actions == [original] && library.actionGroupIdentifiers == identifiers)
        #expect(try library.mutationReceipt(for: mutation, at: now) == nil)
        let receipt = try library.commitActionGroupCopy(group, actions: [copy], mutation: mutation, at: now,
            validateCommit: {}) { .init(id: $0.id, versionToken: "opaque-version") }
        let retry = try library.commitActionGroupCopy(group, actions: [copy], mutation: mutation, at: now,
            validateCommit: { Issue.record("A retry must not commit again") }) {
                .init(id: $0.id, versionToken: "opaque-version")
            }
        #expect(retry == receipt && library.actions.count == 2)
        #expect(library.actions.contains(copy) && library.actionGroupIdentifiers["Source"] == identifiers["Source"])
    }

    @Test func groupAndReceiptRollBackTogetherWhenCommitValidationFails() throws {
        let library = try LibraryStore(inMemory: true, seed: false), group = ActionGroupRecord(name: "Neutral"), mutation = identity()
        #expect(throws: (any Error).self) {
            try library.commitActionGroup(group, mutation: mutation, at: now,
                validateCommit: { throw DraftlyError.message("Authority changed") }) {
                    .init(id: $0.id, versionToken: "opaque-version")
                }
        }
        #expect(library.actionGroups.isEmpty)
        #expect(try library.mutationReceipt(for: mutation, at: now) == nil)
        #expect(!library.container.viewContext.hasChanges)
        let receipt = try library.commitActionGroup(group, mutation: mutation, at: now) {
            .init(id: $0.id, versionToken: "opaque-version")
        }
        #expect(try library.mutationReceipt(for: mutation, at: now) == receipt)
        #expect(library.actionGroups == [group])
    }

    @Test func actionAndReceiptCommitTogetherAndReplayAfterReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false)
        let action = DraftAction(name: "Neutral", steps: []), mutation = identity()
        let receipt = try library.commitActions([action], mutation: mutation, at: now) { actions in
            actions.map { .init(id: $0.id, versionToken: "opaque-version") }
        }
        let reopened = try LibraryStore(directory: root, seed: false)
        #expect(reopened.actions == [action])
        let replay = try reopened.commitActions([action], mutation: mutation, at: now.addingTimeInterval(1)) { _ in
            Issue.record("Replay must not stage another action"); return []
        }
        #expect(replay == receipt && reopened.actions == [action])
        #expect(throws: LibraryMutationReceiptError.requestConflict) {
            try reopened.commitActions([DraftAction(name: "Other", steps: [])], mutation: mutation, at: now) { _ in [] }
        }
    }

    @Test func actionAndReceiptRollBackWhenFinalValidationFails() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = DraftAction(name: "Original", steps: [])
        try library.saveAction(original)
        var changed = original; changed.name = "Changed"
        let mutation = identity()
        #expect(throws: (any Error).self) {
            try library.commitActions([changed], mutation: mutation, at: now,
                validateCommit: { throw DraftlyError.message("Authority changed") }) { actions in
                    actions.map { .init(id: $0.id, versionToken: "opaque-version") }
                }
        }
        #expect(library.actions == [original])
        #expect(try library.mutationReceipt(for: mutation, at: now) == nil)
        #expect(!library.container.viewContext.hasChanges)
    }

    @Test func noteAndReceiptSurviveReopenAndAReplyLossCannotRepeatEffects() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false)
        let note = Note(content: "Neutral café 🐼", tags: ["one", "one"]), mutation = identity()
        let committed = try library.commitNotes([note], mutation: mutation, at: now) { notes in
            #expect(notes[0].tags == ["one"])
            return Self.resources(notes)
        }
        #expect(library.notes[0].tags == ["one"])
        #expect(try library.mutationReceipt(for: mutation, at: now) == committed)
        let reopened = try LibraryStore(directory: root, seed: false)
        let saved = reopened.notes, revisions = reopened.revisions
        let replay = try reopened.commitNotes([note], mutation: mutation, at: now.addingTimeInterval(1)) { _ in
            Issue.record("A committed mutation must not stage another result")
            return []
        }
        #expect(replay == committed && reopened.notes == saved && reopened.revisions == revisions)
        #expect(!reopened.container.viewContext.hasChanges)
    }

    @Test(arguments: [false, true])
    func failuresBeforeAndAfterReceiptStagingRollBackTogether(beforeReceipt: Bool) throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = try library.createNote(content: "Keep original"), revisions = library.revisions
        var changed = original; changed.content = "Do not leak failed text"
        let mutation = identity()
        if !beforeReceipt { library.beforeBatchCommit = { throw DraftlyError.message("Neutral commit failure") } }
        #expect(throws: (any Error).self) {
            try library.commitNotes([changed], mutation: mutation, at: now) { notes in
                if beforeReceipt { throw DraftlyError.message("Neutral receipt failure") }
                return Self.resources(notes)
            }
        }
        #expect(library.notes == [original] && library.revisions == revisions)
        #expect(try library.mutationReceipt(for: mutation, at: now) == nil)
        #expect(!library.container.viewContext.hasChanges)
        library.beforeBatchCommit = nil
        _ = try library.createNote(content: "Unrelated successful save")
        #expect(try library.mutationReceipt(for: mutation, at: now) == nil)
        #expect(!library.notes.contains(where: { $0.content == changed.content }))
        _ = try library.commitNotes([changed], mutation: mutation, at: now, makeResources: Self.resources)
        #expect(library.notes.contains(where: { $0.content == changed.content }))
    }

    @Test func changedRequestHashOrTargetsCannotReuseAReceiptAndConnectionsAreDistinct() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let mutation = identity(), note = Note(content: "Neutral")
        _ = try library.commitNotes([note], mutation: mutation, at: now, makeResources: Self.resources)
        let changed = identity(request: mutation.requestID, hash: String(repeating: "c", count: 64))
        #expect(throws: LibraryMutationReceiptError.requestConflict) {
            try library.commitNotes([note], mutation: changed, at: now, makeResources: Self.resources)
        }
        #expect(throws: LibraryMutationReceiptError.requestConflict) {
            try library.commitNotes([Note(content: "Other target")], mutation: mutation, at: now, makeResources: Self.resources)
        }
        let anotherConnection = identity(request: mutation.requestID, connection: String(repeating: "d", count: 64))
        #expect(try library.mutationReceipt(for: anotherConnection, at: now) == nil)
        #expect(library.notes.count == 1)
    }

    @Test func invalidMetadataOrResourceReceiptsLeaveNoPartialNotes() throws {
        let library = try LibraryStore(inMemory: true, seed: false), note = Note(content: "Neutral")
        for bad in ["", "not-a-hash", String(repeating: "A", count: 64)] {
            #expect(throws: LibraryMutationReceiptError.invalidReceipt) {
                try library.commitNotes([note], mutation: identity(hash: bad), at: now, makeResources: Self.resources)
            }
        }
        for badResources: [LibraryMutationReceipt.Resource] in [[], [.init(id: UUID(), versionToken: "v")],
            [.init(id: note.id, versionToken: "")], [.init(id: note.id, versionToken: "v"), .init(id: note.id, versionToken: "v")]] {
            let mutation = identity()
            #expect(throws: LibraryMutationReceiptError.invalidReceipt) {
                try library.commitNotes([note], mutation: mutation, at: now) { _ in badResources }
            }
            #expect(try library.mutationReceipt(for: mutation, at: now) == nil)
        }
        #expect(library.notes.isEmpty && library.revisions.isEmpty && !library.container.viewContext.hasChanges)
    }

    @Test func retainedReceiptsExpireAtThirtyDaysAndRejectClockRollback() throws {
        let library = try LibraryStore(inMemory: true, seed: false), note = Note(content: "Neutral"), mutation = identity()
        let receipt = try library.commitNotes([note], mutation: mutation, at: now, makeResources: Self.resources)
        #expect(try library.mutationReceipt(for: mutation, at: now.addingTimeInterval(30 * 86400 - 1)) == receipt)
        #expect(throws: LibraryMutationReceiptError.retryWindowExpired) {
            try library.mutationReceipt(for: mutation, at: now.addingTimeInterval(30 * 86400))
        }
        #expect(throws: LibraryMutationReceiptError.invalidReceipt) {
            try library.mutationReceipt(for: mutation, at: now.addingTimeInterval(-1))
        }
    }

    @Test func backupsContainUserDataButNoMutationReceiptsOrRequestHashes() throws {
        let library = try LibraryStore(inMemory: true, seed: false), note = Note(content: "Neutral backup"), mutation = identity()
        _ = try library.commitNotes([note], mutation: mutation, at: now, makeResources: Self.resources)
        let data = try library.backupData(), text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains(mutation.requestID.uuidString) && !text.contains(mutation.connectionHash) && !text.contains(mutation.requestHash))
        let copy = try LibraryStore(inMemory: true, seed: false)
        try copy.restore(data)
        #expect(copy.notes.map(\.id) == [note.id])
        #expect(try copy.mutationReceipt(for: mutation, at: now) == nil)
        let stored = try #require(library.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Record"))
            .first(where: { $0.value(forKey: "kind") as? String == "agentMutationReceipt" }))
        #expect(!(stored.value(forKey: "payload") as? String ?? "").contains(note.content))
    }
    @Test func pendingReceiptsAreNotVisibleAndExistingChangesAreNeverCommittedByTheGateway() throws {
        let library = try LibraryStore(inMemory: true, seed: false), note = Note(content: "Neutral"), mutation = identity()
        library.beforeBatchCommit = {
            #expect(throws: LibraryMutationReceiptError.pendingChanges) {
                try library.mutationReceipt(for: mutation, at: now)
            }
        }
        _ = try library.commitNotes([note], mutation: mutation, at: now, makeResources: Self.resources)
        library.beforeBatchCommit = nil
        let pending = NSEntityDescription.insertNewObject(forEntityName: "Record", into: library.container.viewContext)
        pending.setValue("neutral-pending", forKey: "key"); pending.setValue("neutral", forKey: "kind")
        let another = identity()
        #expect(throws: LibraryMutationReceiptError.pendingChanges) {
            try library.commitNotes([Note(content: "Do not commit unrelated work")], mutation: another, at: now, makeResources: Self.resources)
        }
        #expect(library.container.viewContext.hasChanges && pending.isInserted)
        library.container.viewContext.rollback(); try library.reload()
        #expect(try library.mutationReceipt(for: another, at: now) == nil)
    }

    @Test func malformedStoredReceiptsBlockRetriesWithoutChangingUserData() throws {
        let library = try LibraryStore(inMemory: true, seed: false), note = Note(content: "Keep neutral"), mutation = identity()
        _ = try library.commitNotes([note], mutation: mutation, at: now, makeResources: Self.resources)
        let object = try #require(library.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Record"))
            .first(where: { $0.value(forKey: "kind") as? String == "agentMutationReceipt" }))
        object.setValue("{broken", forKey: "payload")
        try library.container.viewContext.save(); try library.reload()
        let existing = library.notes, versions = library.revisions
        #expect(throws: (any Error).self) {
            try library.commitNotes([note], mutation: mutation, at: now, makeResources: Self.resources)
        }
        #expect(library.notes == existing && library.revisions == versions && !library.container.viewContext.hasChanges)
    }

    @Test func existingUnknownRecordKindsSurviveTheNewAtomicWrite() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let object = NSEntityDescription.insertNewObject(forEntityName: "Record", into: library.container.viewContext)
        object.setValue("neutral-future-record", forKey: "key"); object.setValue("future-kind", forKey: "kind")
        object.setValue("{\"unknown\":\"café 🐼\"}", forKey: "payload")
        try library.container.viewContext.save(); try library.reload()
        _ = try library.commitNotes([Note(content: "Neutral")], mutation: identity(), at: now, makeResources: Self.resources)
        #expect(!object.isDeleted && object.value(forKey: "payload") as? String == "{\"unknown\":\"café 🐼\"}")
    }

}
