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
}
