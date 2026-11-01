import Foundation
import Combine
import Testing
import AgentContracts
@testable import DraftlyCore
@testable import Draftly

@Suite("Agent editor mutation lifecycle") @MainActor
struct AgentEditorMutationTests {
    @MainActor private final class Fixture {
        let preferences: TestPreferences
        let library: LibraryStore
        let note: Note
        var models: [WindowModel] = []
        var undo: [ScriptUndoEditorFixture] = []
        var publications: [AnyCancellable] = []
        lazy var registry = AgentEditorRegistry(library: library, models: { [unowned self] in self.models })
        init() throws {
            preferences = try TestPreferences(prefix: "Draftly-Agent-Mutation-")
            library = try LibraryStore(inMemory: true, seed: false)
            note = try library.createNote(content: "Original café 🐼")
        }
        func close() {
            publications.removeAll(); undo.forEach { $0.close() }
            registry.invalidate(); models.removeAll(); preferences.close()
        }
        func model() -> WindowModel {
            var dependencies = WindowDependencies()
            dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
            let model = WindowModel(library: library, dependencies: dependencies)
            model.editor.load(note, focusEditor: false)
            let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
                lineSpacing: 2, markdown: false, onChange: { [weak model] in model?.contentChanged() })
            undo.append(ScriptUndoEditorFixture(native, content: note.content))
            models.append(model); registry.refreshMembership()
            publications.append(library.$notes.sink { [weak model] in model?.synchronizeStoredEditor($0) })
            return model
        }
        func save(_ note: Note) throws -> Note {
            try library.saveNote(note)
            return try #require(library.notes.first { $0.id == note.id })
        }
    }

    @Test func committedTextReachesEveryEditorWithUndoAndStableGeneration() throws {
        let f = try Fixture(); defer { f.close() }
        let first = f.model(), second = f.model()
        first.editor.selection = NSRange(location: 8, length: 4)
        second.editor.selection = NSRange(location: 2, length: 2)
        first.editor.synchronizeScriptEdit?(); second.editor.synchronizeScriptEdit?()
        let focus = first.editor.focusToken
        var changed = f.note; changed.content = "New 🐼"
        var reserved: String?
        let result = try f.registry.synchronizeMutation(changed) { value, generation in
            reserved = generation
            let saved = try f.save(value)
            #expect(first.editor.content == f.note.content && second.editor.content == f.note.content)
            return saved
        }
        #expect(first.editor.content == changed.content && second.editor.content == changed.content)
        #expect(first.editor.selection == NSRange(location: changed.content.utf16.count, length: 0))
        #expect(second.editor.selection == NSRange(location: 2, length: 2))
        #expect(first.editor.focusToken == focus)
        #expect(!first.hasUnsavedChanges && !second.hasUnsavedChanges)
        #expect(!first.editor.hasUnpersistedText && !second.editor.hasUnpersistedText)
        #expect(result.generation == reserved)
        #expect(try f.registry.snapshot(result.storedNote).generation == reserved)
        for (index, model) in f.models.enumerated() {
            #expect(f.undo[index].text.manager.canUndo)
            model.editor.performUndo?(false)
            #expect(model.editor.content == f.note.content)
            model.editor.performUndo?(true)
            #expect(model.editor.content == changed.content)
            _ = model.flush()
        }
    }

    @Test func storageFailureRetainsPendingTextSelectionAndUndo() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model()
        model.editor.content = "Pending e\u{0301} 🐼"
        model.editor.selection = NSRange(location: 3, length: 2)
        model.editor.synchronizeScriptEdit?(); model.hasUnsavedChanges = true
        let selection = model.editor.selection
        f.library.beforeBatchCommit = { throw AgentErrorCode.storageError }
        var changed = f.note; changed.content = "Agent replacement"
        #expect(throws: AgentErrorCode.storageError) {
            try f.registry.synchronizeMutation(changed) { value, _ in try f.save(value) }
        }
        #expect(model.editor.content == "Pending e\u{0301} 🐼" && model.editor.selection == selection)
        #expect(model.hasUnsavedChanges && model.editor.hasUnpersistedText)
        #expect(try #require(f.library.notes.first).content == f.note.content)
        #expect(f.undo[0].text.manager.canUndo)
        f.library.beforeBatchCommit = nil
        model.editor.performUndo?(false)
        #expect(model.editor.content == f.note.content)
        _ = model.flush()
    }

    @Test func divergentEditorsFailBeforeStorageAndReentryIsBusy() throws {
        let f = try Fixture(); defer { f.close() }
        let first = f.model(), second = f.model()
        first.editor.content = "One"; second.editor.content = "Two"
        var saves = 0
        #expect(throws: AgentErrorCode.editorConflict) {
            try f.registry.synchronizeMutation(f.note) { _, _ in saves += 1; return f.note }
        }
        #expect(saves == 0)
        first.editor.content = f.note.content; second.editor.content = f.note.content
        _ = try f.registry.synchronizeMutation(f.note) { value, _ in
            #expect(throws: AgentErrorCode.busy) {
                try f.registry.synchronizeMutation(value) { _, _ in saves += 1; return value }
            }
            saves += 1; return try f.save(value)
        }
        #expect(saves == 1)
    }

    @Test func invalidatedRegistryCannotStartAStoredMutation() throws {
        let f = try Fixture(); defer { f.close() }
        f.registry.invalidate()
        #expect(throws: AgentErrorCode.cancelled) {
            try f.registry.synchronizeMutation(f.note) { _, _ in Issue.record("Unexpected save"); return f.note }
        }
    }
    @Test func cleanStorageFailureDoesNotCreateAnEditOrUndo() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model()
        let previous = try f.registry.snapshot(f.note).generation
        f.library.beforeBatchCommit = { throw AgentErrorCode.storageError }
        var changed = f.note; changed.content = "Replacement"
        #expect(throws: AgentErrorCode.storageError) {
            try f.registry.synchronizeMutation(changed) { value, _ in try f.save(value) }
        }
        #expect(model.editor.content == f.note.content && !model.hasUnsavedChanges)
        #expect(!model.editor.hasUnpersistedText && !f.undo[0].text.manager.canUndo)
        #expect(try f.registry.snapshot(f.note).generation == previous)
        f.library.beforeBatchCommit = nil
    }

    @Test func aNewCallbackEditRemainsPendingAndInvalidatesTheReservedGeneration() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model(), synchronize = model.editor.synchronizeScriptEdit
        model.editor.synchronizeScriptEdit = {
            synchronize?()
            model.editor.content = "New neutral user edit"; model.contentChanged()
        }
        var changed = f.note; changed.content = "Committed replacement"
        var reserved: String?
        let result = try f.registry.synchronizeMutation(changed) { value, generation in
            reserved = generation; return try f.save(value)
        }
        #expect(result.storedNote.content == changed.content)
        #expect(result.note.content == "New neutral user edit")
        #expect(result.generation != reserved && model.hasUnsavedChanges)
        #expect(model.editor.hasUnpersistedText)
        model.editor.synchronizeScriptEdit = synchronize
        _ = model.flush()
    }

    @Test func callbackNavigationCannotOverwriteAnotherDraft() throws {
        let f = try Fixture(); defer { f.close() }
        let first = f.model(), second = f.model()
        let other = try f.library.createNote(content: "Other neutral draft")
        let synchronize = first.editor.synchronizeScriptEdit
        first.editor.synchronizeScriptEdit = {
            synchronize?()
            second.editor.load(other, focusEditor: false)
            second.hasUnsavedChanges = false
        }
        var changed = f.note; changed.content = "Committed replacement"
        #expect(throws: AgentErrorCode.editorConflict) {
            try f.registry.synchronizeMutation(changed) { value, _ in try f.save(value) }
        }
        #expect(second.editor.noteID == other.id && second.editor.content == other.content)
        #expect(f.library.notes.first { $0.id == f.note.id }?.content == changed.content)
        #expect(f.library.notes.first { $0.id == other.id }?.content == other.content)
        first.editor.synchronizeScriptEdit = synchronize
    }

    @Test func unconfirmedTagInputSurvivesWhileCleanTagFieldsRefresh() throws {
        let f = try Fixture(); defer { f.close() }
        let editing = f.model(), clean = f.model()
        editing.tagsText = "unfinished, Cafe\u{0301}"
        var changed = f.note; changed.content = "Committed replacement"; changed.tags = ["saved"]
        _ = try f.registry.synchronizeMutation(changed) { value, _ in try f.save(value) }
        #expect(editing.tagsText.utf8.elementsEqual("unfinished, Cafe\u{0301}".utf8))
        #expect(clean.tagsText == "saved")
        #expect(try #require(f.library.notes.first { $0.id == f.note.id }).tags == ["saved"])
    }

}
