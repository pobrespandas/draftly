import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Draft context commands") @MainActor
struct DraftCommandTests {
    @Test func mergeWaitsForConfirmationAndUsesCapturedTargets() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let a = try store.createNote(content: "A"), b = try store.createNote(content: "B")
        let model = WindowModel(library: store)
        let original = store.notes
        model.mergeDrafts([b.id, a.id])
        let request = try #require(model.mergeRequest)
        #expect(store.notes == original)
        model.mergeRequest = nil
        #expect(store.notes == original)
        model.mergeDrafts([b.id, a.id])
        model.confirmMerge(request, separator: "", includeBlankLine: false, destination: .archive)
        #expect(model.mergeRequest == nil)
        #expect(model.currentNote?.content == "B\nA")
        #expect(store.notes.filter { $0.id == a.id || $0.id == b.id }.allSatisfy { $0.isArchived })
    }

    @Test func targetsCaptureVisibleOrderAndRightClickScope() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let a = try store.createNote(content: "A"), b = try store.createNote(content: "B"), c = try store.createNote(content: "C")
        let model = WindowModel(library: store); model.sort = .title; model.ascending = true
        #expect(model.contextTargets(rowID: b.id, selection: [c.id, b.id]) == [b.id, c.id])
        #expect(model.contextTargets(rowID: a.id, selection: [c.id, b.id]) == [a.id])
        let ids = model.contextTargets(rowID: b.id, selection: [b.id, c.id]); model.ascending = false
        model.moveDrafts(ids, to: .archive)
        #expect(store.notes.filter(\.isArchived).map(\.id).sorted { $0.uuidString < $1.uuidString } == ids.sorted { $0.uuidString < $1.uuidString })
    }
    @Test func mixedSelectionsReceiveOneDestinationAndFlag() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let a = Note(content: "A", flag: 0), b = Note(content: "B", flag: 3, isArchived: true)
        try store.saveNotes([a, b]); let model = WindowModel(library: store); let ids = [a.id, b.id]
        model.moveDrafts(ids, to: .archive); #expect(store.notes.allSatisfy { $0.isArchived })
        model.flagDrafts(ids, value: 7); #expect(store.notes.allSatisfy { $0.flag == 7 })
        model.moveDrafts(ids, to: .trash); #expect(store.notes.allSatisfy { $0.trashedAt != nil })
        model.moveDrafts(ids, to: .restore); #expect(store.notes.allSatisfy { $0.trashedAt == nil && $0.isArchived })
        model.moveDrafts(ids, to: .inbox); #expect(store.notes.allSatisfy { !$0.isArchived && $0.trashedAt == nil })
        model.flagDrafts(ids, value: 0); #expect(store.notes.allSatisfy { $0.flag == 0 })
    }
    @Test func failedFlushPreventsEveryContextChange() throws {
        enum Failure: Error { case save }
        let store = try LibraryStore(inMemory: true, seed: false)
        let a = try store.createNote(content: "A"), b = try store.createNote(content: "B")
        let model = WindowModel(library: store, saveDraft: { _ in throw Failure.save })
        model.select(a.id); model.editor.content = "Unsaved"; model.contentChanged()
        model.moveDrafts([a.id, b.id], to: .trash)
        #expect(store.notes.allSatisfy { $0.trashedAt == nil })
        #expect(model.editor.content == "Unsaved" && model.hasUnsavedChanges)
        model.duplicateDrafts([b.id]); #expect(store.notes.count == 2)
    }
    @Test func tagsAndInspectionDoNotSwitchTheCurrentDraft() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let a = try store.createNote(content: "A"), b = try store.createNote(content: "B", tags: ["work"])
        let model = WindowModel(library: store); model.select(a.id)
        model.editDraftTags([a.id, b.id], tags: [" Work ", "other"], remove: false)
        #expect(store.notes.allSatisfy { $0.tags == ["other", "work"] })
        model.editDraftTags([a.id, b.id], tags: ["WORK"], remove: true)
        #expect(store.notes.allSatisfy { $0.tags == ["other"] })
        model.inspectDraft(b.id, versions: false); #expect(model.infoDraft?.id == b.id && model.editor.noteID == a.id)
        model.inspectDraft(b.id, versions: true); #expect(model.historyDraftID == b.id && model.editor.noteID == a.id)
        model.restoreRevision(Revision(noteID: b.id, content: "Restored"))
        #expect(model.editor.noteID == a.id && model.editor.content == "A")
        #expect(store.notes.first { $0.id == b.id }?.content == "Restored")
    }
    @Test func actionBatchStopsOnCancellationAndFailure() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let a = try store.createNote(content: "A"), b = try store.createNote(content: "B")
        let model = WindowModel(library: store)
        let cancel = DraftAction(name: "Cancel", steps: [ActionStep("script", ["script": "draft.content = 'Changed'; draft.update(); context.cancel();"])])
        await model.runActionAsync(cancel, on: [a.id, b.id])
        #expect(store.notes.first { $0.id == a.id }?.content == "Changed")
        #expect(store.notes.first { $0.id == b.id }?.content == "B")
        #expect(model.editor.noteID == a.id && store.runs.count == 1)
        let failure = DraftAction(name: "Fail", steps: [ActionStep("script", ["script": "throw new Error('stop');"])])
        await model.runActionAsync(failure, on: [b.id, a.id]); #expect(model.editor.noteID == b.id && store.runs.count == 2)
    }
    @Test func successfulBatchProcessesEveryDraftAndLeavesTheLastOpen() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let a = try store.createNote(content: "A"), b = try store.createNote(content: "B")
        let model = WindowModel(library: store)
        let action = DraftAction(name: "Append", steps: [ActionStep("script", ["script": "draft.content += ' done'; draft.update();"])])
        await model.runActionAsync(action, on: [a.id, b.id])
        #expect(store.notes.first { $0.id == a.id }?.content == "A done")
        #expect(store.notes.first { $0.id == b.id }?.content == "B done")
        #expect(model.editor.noteID == b.id && store.runs.count == 2)
    }

    @Test func queuedWindowActionRejectsDuplicateRequests() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let note = try store.createNote(content: "Source")
        let model = WindowModel(library: store); model.select(note.id)
        let action = DraftAction(name: "Append once", steps: [ActionStep("script", ["script": "draft.content += ' done'; draft.update();"])])
        model.run(action)
        model.run(action)
        #expect(model.actionPending)
        let deadline = ContinuousClock.now + .seconds(5)
        while model.actionPending && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.actionPending)
        #expect(store.notes.first { $0.id == note.id }?.content == "Source done")
        #expect(store.runs.count == 1)
    }

    @Test func cancellingQueuedWindowActionDoesNotStartIt() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let note = try store.createNote(content: "Source")
        let model = WindowModel(library: store); model.select(note.id)
        let action = DraftAction(name: "Do not start", steps: [ActionStep("script", ["script": "draft.content = 'Unexpected'; draft.update();"])])
        model.run(action)
        model.cancelActions()
        let deadline = ContinuousClock.now + .seconds(5)
        while model.actionPending && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.actionPending)
        #expect(store.notes.first { $0.id == note.id }?.content == "Source")
        #expect(store.runs.isEmpty)
    }

    @Test func fullMenuHasGatedSingleDraftCommandsAndCopyUsesCapturedOrder() throws {
        _ = NSApplication.shared
        let store = try LibraryStore(inMemory: true, seed: false)
        let a = try store.createNote(content: "A"), b = try store.createNote(content: "B")
        let model = WindowModel(library: store)
        let menu = model.draftContextMenu(ids: [b.id, a.id])
        #expect(menu.item(withTitle: "Open in New Window")?.isEnabled == false)
        #expect(menu.item(withTitle: "Get Info…")?.isEnabled == false)
        #expect(menu.item(withTitle: "Merge…")?.isEnabled == true)
        #expect(menu.item(withTitle: "Export")?.submenu?.items.count == 3)
        #expect(menu.item(withTitle: "Empty Trash…")?.isEnabled == false)
        #expect(try model.copyText([b.id, a.id], field: .contents) == "B\n\nA")
        #expect(try model.copyText([a.id], field: .link) == "draftly://open?uuid=" + a.id.uuidString)
        #expect(menu.item(withTitle: "Flag")?.submenu?.item(withTitle: "Gray") != nil)
        #expect(model.draftContextMenu(ids: [a.id]).item(withTitle: "Merge…")?.isEnabled == false)
    }
}
