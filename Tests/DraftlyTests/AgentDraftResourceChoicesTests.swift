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

    @Test func workspaceChoicesAndResolutionFollowTheLiveLibrary() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let workspace = Workspace(name: "Neutral workspace")
        try library.saveWorkspace(workspace)
        let choices = AgentLibraryResourceChoices(library: library)
        let target = AgentResourceReference(kind: .workspace, id: workspace.id)
        #expect(choices.choices().contains { $0.reference == target && $0.title == workspace.name })
        #expect(choices.resolve([target]) == [target])
        try library.deleteWorkspace(workspace.id)
        #expect(choices.resolve([target]).isEmpty)
    }

    @Test func themeChoicesFollowLiveIdentityAndNeverResolveOtherKinds() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var theme = EditorThemeDefinition(name: "Selected café 🐼")
        try library.saveTheme(theme)
        let choices = AgentLibraryResourceChoices(library: library)
        let target = AgentResourceReference(kind: .theme, id: theme.id)
        #expect(choices.choices().contains { $0.reference == target && $0.title == theme.name })
        #expect(choices.resolve([target, .init(kind: .draft, id: theme.id)]) == [target])
        theme.name = "Renamed theme"; try library.saveTheme(theme)
        #expect(choices.choices().contains { $0.reference == target && $0.title == theme.name })
        try library.deleteTheme(theme.id)
        #expect(choices.resolve([target]).isEmpty)
    }

    @Test func bookmarkChoicesUseOnlyTheSuppliedPreferenceDomainAndLivePermission() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let prefs = try TestPreferences(prefix: "Draftly-Bookmark-Choices-"); defer { prefs.close() }
        BookmarkPreferences.store(Data([1]), named: "Selected folder", defaults: prefs.defaults)
        let first = try #require(BookmarkPreferences.agentRecords(defaults: prefs.defaults).first)
        let choices = AgentLibraryResourceChoices(library: library, bookmarkDefaults: prefs.defaults)
        let target = AgentResourceReference(kind: .bookmark, id: first.id)
        #expect(choices.choices().contains { $0.reference == target && $0.title == first.name })
        #expect(choices.resolve([target]) == [target])
        #expect(AgentLibraryResourceChoices(library: library).choices().isEmpty)
        BookmarkPreferences.store(Data([2]), named: first.name, defaults: prefs.defaults)
        #expect(choices.resolve([target]).isEmpty)
        let next = try #require(choices.choices().first?.reference)
        #expect(next != target && next.kind == .bookmark)
        BookmarkPreferences.forget(first.name, defaults: prefs.defaults)
        #expect(choices.resolve([next]).isEmpty)
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
