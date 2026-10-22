import AppKit
import Combine
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Advanced Find replacement") @MainActor
struct AdvancedFindReplacementTests {
    private let content = "🐼 café café\nTail"

    private func model(library: LibraryStore, note: Note, defaults: UserDefaults,
                       save: ((Note) throws -> Void)? = nil) -> WindowModel {
        let model = WindowModel(library: library,
            dependencies: WindowDependencies(preferences: WindowPreferences(defaults: defaults)), saveDraft: save)
        model.select(note.id)
        return model
    }

    @Test func individualReplacementPreservesOtherMatchesAndPersistsThroughUndo() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindReplaceOne.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: content)
        let model = model(library: library, note: note, defaults: preferences.defaults)
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: { [weak model] in model?.contentChanged() })
        let fixture = ScriptUndoEditorFixture(native, content: content)
        defer { fixture.close() }
        let query = try EditorFindQuery("(?<=🐼 )(café)", regularExpression: true)
        let range = try #require(query.matches(in: content).first)
        AdvancedFindCommands(model: model).replace(query: .success(query), range: range, with: "[$1]")
        #expect(model.editor.content == "🐼 [café] café\nTail")
        #expect(model.editor.selectedText == "[café]" && fixture.text.selectedRange() == model.editor.selection)
        #expect(fixture.text.string == model.editor.content && library.notes.first?.content == model.editor.content)
        model.editor.performUndo?(false)
        #expect(model.editor.content == content && fixture.text.string == content)
        #expect(model.flush())
        #expect(library.notes.first?.content == content)
    }

    @Test func individualReplacementRejectsInvalidResultsAndKeepsTextOnSaveFailure() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindReplaceOneFailure.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: content)
        let model = model(library: library, note: note, defaults: preferences.defaults,
            save: { _ in throw DraftlyError.message("Expected individual save failure") })
        let commands = AdvancedFindCommands(model: model)
        let query = try EditorFindQuery("café")
        var syncs = 0
        model.editor.synchronizeScriptEdit = { syncs += 1 }
        defer { model.editor.synchronizeScriptEdit = nil }
        commands.replace(query: Result { try EditorFindQuery("[", regularExpression: true) }, range: NSRange(location: 3, length: 4), with: "té")
        commands.replace(query: .success(query), range: NSRange(location: 999, length: 4), with: "té")
        #expect(syncs == 0 && model.editor.content == content && !model.hasUnsavedChanges)
        commands.replace(query: .success(query), range: NSRange(location: 3, length: 4), with: "té")
        #expect(syncs == 1 && model.editor.content == "🐼 té café\nTail")
        #expect(model.editor.selectedText == "té" && model.hasUnsavedChanges)
        #expect(library.notes.first?.content == content)
        #expect(library.error?.contains("Expected individual save failure") == true)
    }

    @Test(arguments: [false, true])
    func replacementSynchronizesSafeSelectionBeforeChangeNotificationAndDurableSave(regex: Bool) throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindReplaceOrder.")
        defer { preferences.close() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly.FindReplace.\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try LibraryStore(directory: folder, seed: false)
        let note = try library.createNote(content: content, tags: ["neutral"])
        let other = try library.createNote(content: "Other draft")
        let expected = regex ? "🐼 café! café!\nTail" : "🐼 té té\nTail"
        let selection = regex ? NSRange(location: 13, length: 4) : NSRange(location: 13, length: 0)
        var events: [String] = []
        weak var observed: WindowModel?
        let model = model(library: library, note: note, defaults: preferences.defaults, save: { value in
            events.append("save")
            #expect(observed?.hasUnsavedChanges == true)
            #expect(value.id == note.id && value.content == expected && value.tags == note.tags)
            try library.saveNote(value)
        })
        observed = model
        model.editor.selection = NSRange(location: 13, length: 4)
        model.advancedFindQuery = regex ? "(café)" : "café"
        let focus = model.editor.focusToken
        let textChanges = model.editor.$content.dropFirst().sink { _ in events.append("content") }
        let selectionChanges = model.editor.$selection.dropFirst().sink { _ in events.append("selection") }
        let dirtyChanges = model.$hasUnsavedChanges.dropFirst().sink { if $0 { events.append("changed") } }
        model.editor.synchronizeScriptEdit = {
            events.append("synchronize")
            #expect(model.editor.content == expected && model.editor.selection == selection)
            #expect(!model.hasUnsavedChanges && library.notes.first { $0.id == note.id }?.content == note.content)
        }
        defer {
            model.editor.synchronizeScriptEdit = nil
            textChanges.cancel(); selectionChanges.cancel(); dirtyChanges.cancel()
        }
        let query = Result { try EditorFindQuery(model.advancedFindQuery, regularExpression: regex) }
        AdvancedFindCommands(model: model).replaceAll(query: query, with: regex ? "$1!" : "té")
        #expect(events == ["content", "selection", "synchronize", "changed", "save"])
        #expect(model.editor.content == expected && model.editor.selection == selection)
        #expect(model.editor.focusToken == focus && !model.hasUnsavedChanges)
        #expect(library.notes.first { $0.id == other.id } == other)
        let reopened = try LibraryStore(directory: folder, seed: false)
        #expect(reopened.notes.first { $0.id == note.id }?.content == expected)
        #expect(reopened.notes.first { $0.id == note.id }?.tags == ["neutral"])
        #expect(reopened.notes.first { $0.id == other.id } == other)
    }

    @Test func replacementKeepsTheNativeEditorUndoRedoAndStoredTextCoherent() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindReplaceUndo.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: content)
        let model = model(library: library, note: note, defaults: preferences.defaults)
        let selection = NSRange(location: 13, length: 4)
        model.editor.selection = selection
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: { [weak model] in model?.contentChanged() })
        let fixture = ScriptUndoEditorFixture(native, content: content)
        defer { fixture.close() }
        fixture.text.setSelectedRange(selection)
        let query = Result { try EditorFindQuery("café") }
        AdvancedFindCommands(model: model).replaceAll(query: query, with: "té")
        #expect(fixture.text.string == "🐼 té té\nTail" && model.editor.content == fixture.text.string)
        #expect(model.editor.selection == NSRange(location: 13, length: 0))
        #expect(fixture.text.selectedRange() == model.editor.selection && fixture.text.manager.canUndo)
        #expect(library.notes.first?.content == fixture.text.string)
        model.editor.performUndo?(false)
        #expect(fixture.text.string == content && model.editor.content == content)
        #expect(model.editor.selection == selection && fixture.text.selectedRange() == selection)
        #expect(model.hasUnsavedChanges)
        let undoSaved = model.flush()
        #expect(undoSaved)
        #expect(library.notes.first?.content == content)
        model.editor.performUndo?(true)
        #expect(fixture.text.string == "🐼 té té\nTail" && model.editor.content == fixture.text.string)
        #expect(model.editor.selection == NSRange(location: 13, length: 0))
        #expect(fixture.text.selectedRange() == model.editor.selection)
        let redoSaved = model.flush()
        #expect(redoSaved)
        #expect(library.notes.first?.content == "🐼 té té\nTail")
    }

    @Test func failedSaveRetainsNativeTextAndUnsavedStateForAnExplicitRetry() throws {
        enum SaveFailure: LocalizedError {
            case unavailable
            var errorDescription: String? { "Neutral find save failure" }
        }
        let preferences = try TestPreferences(prefix: "Draftly.FindReplaceFailure.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: content)
        var fails = false
        var attempts = 0
        let model = model(library: library, note: note, defaults: preferences.defaults, save: { value in
            attempts += 1
            if fails { throw SaveFailure.unavailable }
            try library.saveNote(value)
        })
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: { [weak model] in model?.contentChanged() })
        let fixture = ScriptUndoEditorFixture(native, content: content)
        defer { fixture.close() }
        model.editor.selection = NSRange(location: 13, length: 4)
        fixture.text.setSelectedRange(model.editor.selection)
        fails = true
        AdvancedFindCommands(model: model).replaceAll(query: Result { try EditorFindQuery("café") }, with: "té")
        #expect(attempts == 1 && library.error == "Neutral find save failure")
        #expect(model.hasUnsavedChanges && model.editor.content == "🐼 té té\nTail")
        #expect(fixture.text.string == model.editor.content && fixture.text.manager.canUndo)
        #expect(model.editor.selection == NSRange(location: 13, length: 0))
        #expect(fixture.text.selectedRange() == model.editor.selection)
        #expect(library.notes.first?.content == content)
        fails = false
        let retrySaved = model.flush()
        #expect(retrySaved && attempts == 2 && !model.hasUnsavedChanges)
        #expect(library.notes.first?.content == "🐼 té té\nTail")
    }

    @Test func invalidQueryDoesNotWriteSynchronizeOrClampSelection() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindReplaceInvalid.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: content)
        var saves = 0
        let model = model(library: library, note: note, defaults: preferences.defaults, save: { value in
            saves += 1; try library.saveNote(value)
        })
        model.editor.selection = NSRange(location: 999, length: 999)
        let focus = model.editor.focusToken
        model.editor.synchronizeScriptEdit = { Issue.record("An invalid query must not synchronize.") }
        defer { model.editor.synchronizeScriptEdit = nil }
        let query = Result { try EditorFindQuery("[", regularExpression: true) }
        AdvancedFindCommands(model: model).replaceAll(query: query, with: "Changed")
        #expect(saves == 0 && !model.hasUnsavedChanges && library.error == nil)
        #expect(model.editor.content == content && library.notes.first?.content == content)
        #expect(model.editor.selection == NSRange(location: 999, length: 999))
        #expect(model.editor.focusToken == focus)
    }

    @Test(arguments: ["", "missing"])
    func validQueriesWithoutMatchesStillSynchronizeAndSavePendingText(query: String) throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindReplaceNoMatches.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: content)
        var events: [String] = []
        let model = model(library: library, note: note, defaults: preferences.defaults, save: { value in
            events.append("save"); try library.saveNote(value)
        })
        let pending = content + " pending"
        model.editor.content = pending
        model.contentChanged()
        model.editor.selection = NSRange(location: 999, length: 999)
        model.editor.synchronizeScriptEdit = { events.append("synchronize") }
        defer { model.editor.synchronizeScriptEdit = nil }
        AdvancedFindCommands(model: model).replaceAll(query: Result { try EditorFindQuery(query) }, with: "Changed")
        #expect(events == ["synchronize", "save"])
        #expect(model.editor.content == pending && library.notes.first?.content == pending)
        #expect(model.editor.selection == NSRange(location: pending.utf16.count, length: 0))
        #expect(!model.hasUnsavedChanges)
    }

    @Test func replacingTheWholeTextKeepsTheExistingDraftAndAnEmptySafeSelection() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindReplaceEmpty.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: content, tags: ["keep"])
        let model = model(library: library, note: note, defaults: preferences.defaults)
        model.editor.selection = NSRange(location: 13, length: 4)
        AdvancedFindCommands(model: model).replaceAll(query: Result { try EditorFindQuery("[\\s\\S]+", regularExpression: true) }, with: "")
        #expect(model.editor.content.isEmpty && model.editor.selection == NSRange(location: 0, length: 0))
        #expect(model.editor.noteID == note.id && !model.hasUnsavedChanges)
        #expect(library.notes.count == 1 && library.notes.first?.id == note.id)
        #expect(library.notes.first?.content == "" && library.notes.first?.tags == ["keep"])
    }
    @Test func replacementsAndUndoStayWithTheirSourceEditorAcrossTwoModels() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindTwoSources.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let firstNote = try library.createNote(content: "First 🐼 café café")
        let secondNote = try library.createNote(content: "Second 🐼 café café")
        let first = model(library: library, note: firstNote, defaults: preferences.defaults)
        let second = model(library: library, note: secondNote, defaults: preferences.defaults)
        first.advancedFindQuery = "café"; second.advancedFindQuery = "Second"
        second.editor.selection = NSRange(location: 0, length: 6)
        let firstFixture = ScriptUndoEditorFixture(NativeEditor(session: first.editor, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: { [weak first] in first?.contentChanged() }), content: firstNote.content)
        let secondFixture = ScriptUndoEditorFixture(NativeEditor(session: second.editor, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: { [weak second] in second?.contentChanged() }), content: secondNote.content)
        defer { firstFixture.close(); secondFixture.close() }
        let query = try EditorFindQuery("café")
        AdvancedFindCommands(model: first).replaceAll(query: .success(query), with: "té")
        #expect(first.editor.content == "First 🐼 té té" && firstFixture.text.string == first.editor.content)
        #expect(second.editor.content == secondNote.content && secondFixture.text.string == secondNote.content)
        #expect(second.editor.selection == NSRange(location: 0, length: 6))
        #expect(secondFixture.text.undoManager?.canUndo != true && second.advancedFindQuery == "Second")
        let firstSelection = first.editor.selection
        AdvancedFindCommands(model: second).replaceAll(query: .success(query), with: "coffee")
        #expect(second.editor.content == "Second 🐼 coffee coffee")
        #expect(first.editor.content == "First 🐼 té té" && first.editor.selection == firstSelection)
        second.editor.performUndo?(false)
        #expect(second.editor.content == secondNote.content && second.flush())
        #expect(first.editor.content == "First 🐼 té té")
        first.editor.performUndo?(false)
        #expect(first.editor.content == firstNote.content && first.flush())
        #expect(library.notes.first { $0.id == firstNote.id }?.content == firstNote.content)
        #expect(library.notes.first { $0.id == secondNote.id }?.content == secondNote.content)
        #expect(first.advancedFindQuery == "café" && second.advancedFindQuery == "Second")
    }
}
