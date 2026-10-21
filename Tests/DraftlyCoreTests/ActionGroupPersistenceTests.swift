import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action group collision persistence") @MainActor
struct ActionGroupPersistenceTests {
    private let first = "B" + String(repeating: "A", count: 16)
    private let second = "?" + String(repeating: "A", count: 15)

    @Test func collidingNewGroupDoesNotRenameOrReplaceStoredGroup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try LibraryStore(directory: directory, seed: false)
        let original = ActionGroupRecord(name: first)
        try library.saveActionGroup(original)
        var action = DraftAction(name: "Keep membership", steps: [])
        action.group = first
        try library.saveActions([action])
        try library.saveActionGroup(ActionGroupRecord(name: second))
        #expect(Set(library.actionGroups.map(\.name)) == [first, second])
        #expect(Set(library.actionGroups.map(\.id)).count == 2)
        #expect(library.actionGroups.first { $0.name == first }?.id == original.id)
        #expect(library.actions.first?.group == first)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.actionGroups == library.actionGroups)
        #expect(restored.actions == library.actions)
        let reopened = try LibraryStore(directory: directory, seed: false)
        #expect(reopened.actionGroups == library.actionGroups)
        #expect(reopened.actions == library.actions)
    }

    @Test func newGroupPreservesCollidingImplicitMembership() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var action = DraftAction(name: "Implicit membership", steps: [])
        action.group = first
        try library.saveActions([action])
        try library.saveActionGroup(ActionGroupRecord(name: second))
        #expect(Set(library.actionGroups.map(\.name)) == [first, second])
        #expect(Set(library.actionGroups.map(\.id)).count == 2)
        #expect(library.actionGroups.first { $0.name == first }?.id == ActionGroupRecord.identifier(for: first))
        #expect(library.actions.first?.group == first)
    }

    @Test(arguments: [false, true]) func implicitGroupsKeepIDsThroughDeletionAndRestore(reverse: Bool) throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let names = reverse ? [second, first] : [first, second]
        var a = DraftAction(name: "A", steps: []); a.group = names[0]
        var b = DraftAction(name: "B", steps: []); b.group = names[1]
        try library.saveActions([a])
        let original = library.actionGroupRecord(named: a.group).id
        #expect(library.actionGroups.isEmpty)
        try library.saveActions([b])
        let ids = library.actionGroupIdentifiers
        #expect(ids[a.group] == original)
        #expect(Set(ids.values).count == 2)
        #expect(library.actionGroups.count == 2)
        try library.deleteAction(a.id)
        #expect(library.actions.map(\.id) == [b.id])
        #expect(library.actionGroupIdentifiers == ids)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.actionGroupIdentifiers == ids)
        #expect(restored.actions.map(\.id) == [b.id])
    }

    @Test func legacyImplicitCollisionBackupAndGroupRemovalKeepSurvivingIdentity() throws {
        var a = DraftAction(name: "A", steps: []); a.group = first
        var b = DraftAction(name: "B", steps: []); b.group = second
        let data = try JSONEncoder().encode(Backup(notes: [], revisions: [], workspaces: [], actions: [a, b]))
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.restore(data)
        let surviving = library.actionGroupRecord(named: second).id
        #expect(library.actionGroups.count == 2)
        try library.removeActionGroup(first, movingActionsTo: second)
        #expect(library.groupNames == [second])
        #expect(library.actionGroupRecord(named: second).id == surviving)
        #expect(library.actions.count == 2 && library.actions.allSatisfy { $0.group == second })
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.actionGroupIdentifiers == [second: surviving])
    }

    @Test func failedActionBatchDoesNotLeakGroupAllocation() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var a = DraftAction(name: "A", steps: []); a.group = first
        var b = DraftAction(name: "B", steps: []); b.group = second
        try library.saveActions([a])
        let before = try library.backupData()
        library.beforeBatchCommit = { throw DraftlyError.message("Injected write failure") }
        #expect(throws: (any Error).self) { try library.saveActions([b]) }
        library.beforeBatchCommit = nil
        #expect(try library.backupData() == before)
        try library.saveActions([b])
        #expect(Set(library.actionGroupIdentifiers.values).count == 2)
    }

    @Test func batchRejectsDuplicateIDsBeforeWritingAnyGroup() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveActionGroup(ActionGroupRecord(name: "Existing"))
        let before = try library.backupData()
        #expect(throws: (any Error).self) {
            try library.saveActionGroups([ActionGroupRecord(name: first), ActionGroupRecord(name: second)])
        }
        #expect(try library.backupData() == before)
    }
}
