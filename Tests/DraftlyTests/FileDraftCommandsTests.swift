import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("File draft commands") @MainActor
struct FileDraftCommandsTests {
    private func withModel(_ body: (LibraryStore, WindowModel) async throws -> Void) async throws {
        let preferences = try TestPreferences(prefix: "Draftly.FileDraftCommands.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let dependencies = WindowDependencies(preferences: WindowPreferences(defaults: preferences.defaults))
        let model = WindowModel(library: library, dependencies: dependencies)
        try await body(library, model)
    }

    @Test func visibleSelectionUsesListOrderAndEmptySelectionUsesTheOpenDraft() async throws {
        try await withModel { library, model in
            let a = try library.createNote(content: "Alpha"), b = try library.createNote(content: "Bravo"), c = try library.createNote(content: "Charlie")
            model.sort = .title; model.ascending = true; model.select(a.id)
            model.selectedDraftIDs = [c.id, b.id]
            let captured = FileDraftCommands(model: model)
            #expect(captured.targetIDs == [b.id, c.id] && captured.canUseTargets)
            #expect(captured.singleTarget == nil)
            model.selectedDraftIDs = []
            let current = FileDraftCommands(model: model)
            #expect(current.targetIDs == [a.id] && current.singleTarget == a.id)
            #expect(captured.targetIDs == [b.id, c.id])
            await captured.printDraft { values in
                #expect(values["text"] as? String == "Bravo\n\nCharlie")
                return false
            }
            model.selectedDraftIDs = [b.id, c.id]
            model.query = "Bravo"
            #expect(FileDraftCommands(model: model).targetIDs == [b.id])
            #expect(model.editor.noteID == a.id && model.editor.content == "Alpha")
        }
    }

    @Test func emptyScratchDoesNotEnablePersistentOperationsButPendingTextDoes() async throws {
        try await withModel { library, model in
            #expect(model.create())
            let commands = FileDraftCommands(model: model)
            #expect(!commands.canUseTargets && commands.singleTarget == nil)
            commands.saveVersion()
            #expect(library.notes.isEmpty && library.revisions.isEmpty)
            model.editor.content = "Pending café 🐼"; model.contentChanged()
            let pending = FileDraftCommands(model: model)
            #expect(pending.canUseTargets && pending.singleTarget == model.editor.noteID)
            pending.saveVersion()
            let note = try #require(library.notes.first)
            #expect(note.content == "Pending café 🐼")
            #expect(library.revisions.contains { $0.noteID == note.id && $0.content == note.content })
            #expect(model.editor.noteID == note.id)
        }
    }

    @Test func clipboardCreationRejectsMissingTextAndPreservesTheProvidedUnicode() async throws {
        try await withModel { library, model in
            let note = try library.createNote(content: "Previous"); model.select(note.id)
            let commands = FileDraftCommands(model: model)
            #expect(!commands.createWithClipboard(nil) && !commands.createWithClipboard(""))
            #expect(model.editor.noteID == note.id)
            #expect(commands.createWithClipboard("Café 🐼\nSecond line"))
            #expect(model.editor.noteID != note.id && model.editor.content == "Café 🐼\nSecond line")
            #expect(model.flush())
            #expect(library.notes.first { $0.id == model.editor.noteID }?.content == "Café 🐼\nSecond line")
            #expect(library.notes.first { $0.id == note.id }?.content == "Previous")
        }
    }

    @Test func syntaxCreationUsesInstalledSyntaxesAndDoesNotChangeThePreviousDraft() async throws {
        try await withModel { library, model in
            let note = try library.createNote(content: "Keep"); model.select(note.id)
            let commands = FileDraftCommands(model: model)
            #expect(commands.syntaxNames.contains("MultiMarkdown") && commands.syntaxNames.contains("TaskPaper"))
            #expect(!commands.create(syntax: "Missing syntax"))
            #expect(model.editor.noteID == note.id)
            #expect(commands.create(syntax: "TaskPaper"))
            let created = try #require(model.currentNote)
            #expect(created.id != note.id && created.syntax == "TaskPaper" && created.content.isEmpty)
            #expect(library.notes.first { $0.id == note.id }?.syntax == note.syntax)
        }
    }

    @Test func invalidWorkspaceDoesNotCreateOrSwitchAndAValidOneAppliesAfterCreation() async throws {
        try await withModel { library, model in
            let note = try library.createNote(content: "Keep"); model.select(note.id)
            let commands = FileDraftCommands(model: model)
            let before = library.notes
            var invalid = Workspace(name: "Missing group")
            try WorkspaceOptionsEditor.setReference(["name": "Missing"], key: "loadActionListGroup", in: &invalid)
            #expect(!commands.create(in: invalid))
            #expect(model.editor.noteID == note.id && library.notes == before)
            var workspace = Workspace(name: "Archive")
            workspace.folder = .archive; workspace.query = "neutral"; workspace.tags = ["qa"]
            #expect(commands.create(in: workspace))
            #expect(model.editor.noteID != note.id && model.editor.content.isEmpty)
            #expect(model.folder == .archive && model.query == "neutral" && model.selectedTags == ["qa"])
            #expect(library.notes == before)
        }
    }

    @Test func failedPendingSavePreventsCreationVersionWritesAndNativePresentations() async throws {
        let preferences = try TestPreferences(prefix: "Draftly.FileDraftCommands.Failure.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Keep")
        var opens = 0
        var dependencies = WindowDependencies(preferences: WindowPreferences(defaults: preferences.defaults))
        dependencies.openDraftWindowAsync = { _, _, _, _ in opens += 1; return true }
        let model = WindowModel(library: library, dependencies: dependencies,
            saveDraft: { _ in throw DraftlyError.message("Injected save failure") })
        model.select(note.id); model.editor.content = "Pending"; model.contentChanged()
        let before = library.notes
        let revisionsBefore = library.revisions
        let commands = FileDraftCommands(model: model)
        #expect(!commands.createWithClipboard("New") && !commands.create(syntax: "TaskPaper"))
        commands.saveVersion()
        #expect(await commands.openNewWindow() == false)
        var prints = 0
        await commands.printDraft { _ in prints += 1; return true }
        #expect(opens == 0 && prints == 0)
        #expect(model.editor.noteID == note.id && model.editor.content == "Pending" && model.hasUnsavedChanges)
        #expect(library.notes == before && library.revisions == revisionsBefore)
    }

    @Test func newWindowWaitsForTheExistingAsyncOpeningAdapterAfterSaving() async throws {
        let preferences = try TestPreferences(prefix: "Draftly.FileDraftCommands.Open.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Keep")
        var calls = 0
        var dependencies = WindowDependencies(preferences: WindowPreferences(defaults: preferences.defaults))
        dependencies.openDraftWindowAsync = { target, tab, origin, timeout in
            calls += 1
            #expect(target == nil && !tab && origin == nil && timeout == 120)
            #expect(library.notes.first { $0.id == note.id }?.content == "Pending")
            return true
        }
        dependencies.openDraftWindow = { _, _, _ in Issue.record("The legacy opening adapter ran."); return false }
        let model = WindowModel(library: library, dependencies: dependencies)
        model.select(note.id); model.editor.content = "Pending"; model.contentChanged()
        #expect(await FileDraftCommands(model: model).openNewWindow())
        #expect(calls == 1 && model.editor.noteID == note.id && !model.hasUnsavedChanges)
    }

    @Test func printUsesTheSelectedContentsInVisibleOrderAndWaitsForTheNativeResult() async throws {
        try await withModel { library, model in
            let a = try library.createNote(content: "Alpha"), b = try library.createNote(content: "Bravo"), c = try library.createNote(content: "Charlie")
            model.sort = .title; model.ascending = true; model.select(a.id)
            model.editor.content = "Pending Alpha"; model.contentChanged()
            model.selectedDraftIDs = [c.id, b.id]
            let commands = FileDraftCommands(model: model)
            var calls = 0
            await commands.printDraft { values in
                calls += 1
                #expect(values["text"] as? String == "Bravo\n\nCharlie")
                #expect(values["format"] as? String == "text")
                #expect(library.notes.first { $0.id == a.id }?.content == "Pending Alpha")
                return false
            }
            #expect(calls == 1 && model.editor.noteID == a.id)
            #expect(model.editor.content == "Pending Alpha" && model.library.error == nil)
        }
    }
}
