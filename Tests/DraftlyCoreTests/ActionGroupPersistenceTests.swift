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
