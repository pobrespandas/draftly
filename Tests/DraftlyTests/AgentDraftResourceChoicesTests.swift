import Foundation
import Testing
import DraftlyCore
import AgentContracts
@testable import Draftly

@Suite("Agent draft resource choices") @MainActor
struct AgentDraftResourceChoicesTests {
    @Test func choicesAndResolutionFollowLiveLibrary() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "First 🐼")
        let second = try library.createNote(content: "Second")
        let choices = AgentDraftResourceChoices(library: library)
        let target = AgentResourceReference(kind: .draft, id: first.id)
        let missing = AgentResourceReference(kind: .draft, id: UUID())
        let wrongKind = AgentResourceReference(kind: .workspace, id: second.id)
        #expect(Set(choices.choices().map(\.reference)) == [target, .init(kind: .draft, id: second.id)])
        #expect(choices.resolve([target, missing, wrongKind]) == [target])
        var trashed = first
        trashed.trashedAt = Date()
        try library.saveNote(trashed)
        try library.emptyTrash()
        #expect(choices.resolve([target]).isEmpty)
    }

    @Test func actionChoicesAndResolutionFollowLiveLibrary() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Draft")
        let action = DraftAction(name: "Allowed action", steps: [])
        try library.saveAction(action)
        let choices = AgentLibraryResourceChoices(library: library)
        let draft = AgentResourceReference(kind: .draft, id: note.id)
        let target = AgentResourceReference(kind: .action, id: action.id)
        let group = AgentResourceReference(kind: .actionGroup, id: try #require(library.actionGroupIdentifiers[action.group]))
        let wrongKind = AgentResourceReference(kind: .draft, id: action.id)
        #expect(Set(choices.choices().map(\.reference).filter { $0.kind != .revision }) == [draft, target, group])
        #expect(choices.resolve([draft, target, wrongKind]) == [draft, target])
        try library.deleteAction(action.id)
        #expect(choices.resolve([draft, target]) == [draft])
    }

    @Test func revisionChoicesFollowTheExistingDraftAndRevision() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Draft with version")
        let revision = Revision(noteID: note.id, content: "Older text")
        try library.saveRevision(revision)
        let choices = AgentLibraryResourceChoices(library: library)
        let target = AgentResourceReference(kind: .revision, id: revision.id)
        #expect(choices.choices().contains { $0.reference == target && $0.title.contains(note.title) })
        #expect(choices.resolve([target]) == [target])
        try library.deleteRevision(revision.id)
        #expect(choices.resolve([target]).isEmpty)
    }
}
