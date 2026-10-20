import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Nonblocking window arrangement") @MainActor
struct WindowArrangementTests {
    @Test func showReturnsBeforePresentationAndCommitsWithNativeUndoAndSelection() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "🐼 café\nTail")
        let model = WindowModel(library: library); model.select(note.id)
        let selection = NSRange(location: 3, length: 4)
        model.editor.selection = selection
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, onChange: { [weak model] in
            model?.contentChanged(); _ = model?.flush()
        })
        let coordinator = NativeEditor.Coordinator(native)
        let text = TestUndoTextView(frame: .zero)
        text.string = note.content; text.setSelectedRange(selection)
        coordinator.textView = text; text.manager.groupsByEvent = false
        model.editor.synchronizeScriptEdit = {
            text.manager.beginUndoGrouping()
            coordinator.synchronizeScriptEdit()
            text.manager.endUndoGrouping()
        }
        defer {
            model.editor.synchronizeScriptEdit = nil
            coordinator.textView = nil
            text.manager.removeAllActions()
        }
        let gate = ArrangementTestGate()
        try model.showArrangement { await gate.present($0) }
        let task = try #require(model.arrangementSession.task)
        #expect(model.arrangementSession.isActive && gate.text == nil)
        #expect(model.editor.content == note.content)
        await gate.waitForStart()
        gate.finish("Tail\n🐼 café")
        await task.value
        #expect(!model.arrangementSession.isActive)
        #expect(model.editor.content == "Tail\n🐼 café" && text.string == model.editor.content)
        #expect(model.editor.selection == selection)
        #expect(library.notes.first?.content == model.editor.content)
        #expect(!model.hasUnsavedChanges)
        text.manager.undo()
        #expect(model.editor.content == note.content && model.editor.selection == selection)
        #expect(library.notes.first?.content == note.content)
        text.manager.redo()
        #expect(model.editor.content == "Tail\n🐼 café")
    }

    @Test func userNavigationCancelsAndRejectsALateResultForThePreviousDraft() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "First\nSecond")
        let next = try library.createNote(content: "Next draft")
        let model = WindowModel(library: library); model.select(first.id)
        let gate = ArrangementTestGate()
        try model.showArrangement { await gate.present($0) }
        let task = try #require(model.arrangementSession.task)
        await gate.waitForStart()
        model.select(next.id)
        #expect(task.isCancelled)
        gate.finish("Second\nFirst")
        await task.value
        #expect(model.editor.noteID == next.id && model.editor.content == next.content)
        #expect(library.notes.first { $0.id == first.id }?.content == first.content)
    }

    @Test(arguments: [false, true])
    func storedChangesRejectAcceptedResultsButDoNotTurnUserCancellationIntoAnError(accept: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var note = try library.createNote(content: "First\nSecond")
        let model = WindowModel(library: library); model.select(note.id)
        let gate = ArrangementTestGate()
        try model.showArrangement { await gate.present($0) }
        let task = try #require(model.arrangementSession.task)
        await gate.waitForStart()
        note.content = "External change"; try library.saveNote(note)
        gate.finish(accept ? "Second\nFirst" : nil)
        await task.value
        #expect(library.notes.first?.content == "External change")
        #expect(model.editor.content == "First\nSecond")
        if accept { #expect(library.error?.contains("No arrangement was applied") == true) }
        else { #expect(library.error == nil) }
    }

    @Test func windowCancellationStopsOnlyItsOwnedSession() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "First\nSecond")
        let second = try library.createNote(content: "Other\nWindow")
        let model = WindowModel(library: library), other = WindowModel(library: library)
        model.select(first.id); other.select(second.id)
        let gate = ArrangementTestGate(), otherGate = ArrangementTestGate()
        try model.showArrangement { await gate.present($0) }
        try other.showArrangement { await otherGate.present($0) }
        let task = try #require(model.arrangementSession.task), otherTask = try #require(other.arrangementSession.task)
        await gate.waitForStart(); await otherGate.waitForStart()
        model.cancelActions()
        #expect(task.isCancelled && !otherTask.isCancelled)
        gate.finish("Second\nFirst"); otherGate.finish("Window\nOther")
        await task.value; await otherTask.value
        #expect(model.editor.content == first.content)
        #expect(other.editor.content == "Window\nOther")
    }

    @Test func failedSaveRetainsTheArrangedTextAsPendingEdits() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "First\nSecond")
        let model = WindowModel(library: library, saveDraft: { _ in throw DraftlyError.message("Refused arrangement save") })
        model.select(note.id)
        try model.showArrangement { _ in "Second\nFirst" }
        let task = try #require(model.arrangementSession.task)
        await task.value
        #expect(model.editor.content == "Second\nFirst" && model.hasUnsavedChanges)
        #expect(library.notes.first?.content == note.content)
        #expect(library.error == "Refused arrangement save")
    }

    @Test func aSecondRequestCannotReplaceTheActiveSession() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "First\nSecond")
        let model = WindowModel(library: library); model.select(note.id)
        let gate = ArrangementTestGate()
        try model.showArrangement { await gate.present($0) }
        let task = try #require(model.arrangementSession.task)
        await gate.waitForStart()
        #expect(throws: DraftlyError.self) {
            try model.showArrangement { _ in Issue.record("A second presenter must not open."); return nil }
        }
        gate.finish(nil)
        await task.value
        #expect(model.editor.content == note.content && !model.hasUnsavedChanges)
    }

    @Test func releasingTheWindowModelCancelsItsPresentationTask() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "First\nSecond")
        var model: WindowModel? = WindowModel(library: library)
        model?.select(note.id)
        weak var released = model
        let gate = ArrangementTestGate()
        try model?.showArrangement { await gate.present($0) }
        let task = try #require(model?.arrangementSession.task)
        await gate.waitForStart()
        model = nil
        #expect(released == nil && task.isCancelled)
        gate.finish("Second\nFirst")
        await task.value
        #expect(library.notes.first?.content == note.content)
    }
}
