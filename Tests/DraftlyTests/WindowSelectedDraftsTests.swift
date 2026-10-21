import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Window selected drafts contract") @MainActor
struct WindowSelectedDraftsTests {
    private func makeAction(_ source: String) -> DraftAction {
        DraftAction(name: "Selection contract", steps: [ActionStep("script", ["script":
            "function check(value,message){if(!value)throw Error(message);}" + source])])
    }

    @Test func editorIdentityChangesUpdateSelectionImmediatelyButSameDraftLoadsDoNotCollapseIt() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let alpha = try library.createNote(content: "Alpha")
        let beta = try library.createNote(content: "Beta")
        let model = WindowModel(library: library)
        model.select(alpha.id)
        #expect(model.selectedDraftIDs == [alpha.id])
        model.selectedDraftIDs = [alpha.id, beta.id]
        model.editor.load(alpha)
        #expect(model.selectedDraftIDs == [alpha.id, beta.id])
        model.editor.load(beta)
        #expect(model.selectedDraftIDs == [beta.id])
    }

    @Test(arguments: [false, true])
    func selectionUsesVisibleOrderWithoutReplacingTheOpenDraft(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let beta = try library.createNote(content: "Beta — open editor")
        let gamma = try library.createNote(content: "Gamma 🐼")
        let alpha = try library.createNote(content: "Alpha café")
        let model = WindowModel(library: library)
        model.select(beta.id)
        model.folder = .all; model.sort = .title; model.ascending = true
        model.selectedDraftIDs = [gamma.id, alpha.id, UUID()]
        let action = makeAction("""
        const selected=app.currentWindow.selectedDrafts;
        check(selected.length===2,'two selected rows');
        check(selected.every(d=>d instanceof Draft),'typed drafts');
        check(selected[0].uuid==='\(alpha.id.uuidString)'&&selected[1].uuid==='\(gamma.id.uuidString)','visible order');
        check(selected[0]===Draft.find(selected[0].uuid),'shared draft identity');
        selected.pop();
        check(app.currentWindow.selectedDrafts.length===2,'independent selection array');
        check(draft.uuid==='\(beta.id.uuidString)'&&editor.getText()==='Beta — open editor','open editor preserved');
        """)
        let succeeded = worker ? await model.runner.runAsync(action).result.succeeded : model.runner.run(action)
        #expect(succeeded, Comment(rawValue: model.runner.message ?? ""))
        #expect(model.editor.noteID == beta.id && model.editor.content == beta.content)
        #expect(model.selectedDraftIDs.contains(alpha.id) && model.selectedDraftIDs.contains(gamma.id))
    }

    @Test(arguments: [false, true])
    func emptySelectionDoesNotFallBackToTheCurrentDraft(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Open but not selected")
        let model = WindowModel(library: library)
        model.select(note.id)
        model.selectedDraftIDs = []
        let action = makeAction("check(app.currentWindow.selectedDrafts.length===0,'empty list selection');")
        let succeeded = worker ? await model.runner.runAsync(action).result.succeeded : model.runner.run(action)
        #expect(succeeded, Comment(rawValue: model.runner.message ?? ""))
        #expect(model.editor.noteID == note.id)
    }

    @Test(arguments: [false, true])
    func filteredOutRowsAreNotReportedAsSelected(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let alpha = try library.createNote(content: "Alpha")
        let beta = try library.createNote(content: "Beta")
        let model = WindowModel(library: library)
        model.select(beta.id)
        model.selectedDraftIDs = [alpha.id, beta.id]
        model.query = "Alpha"
        let action = makeAction("""
        const selected=app.currentWindow.selectedDrafts;
        check(selected.length===1&&selected[0].uuid==='\(alpha.id.uuidString)','only visible selection');
        """)
        let succeeded = worker ? await model.runner.runAsync(action).result.succeeded : model.runner.run(action)
        #expect(succeeded, Comment(rawValue: model.runner.message ?? ""))
        #expect(model.query == "Alpha" && model.editor.noteID == beta.id)
    }
}
