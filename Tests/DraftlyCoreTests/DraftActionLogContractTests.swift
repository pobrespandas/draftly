import Foundation
import Testing
@testable import DraftlyCore

@Suite("Draft action log member contracts") @MainActor
struct DraftActionLogContractTests {
    @Test(arguments: [false, true])
    func deleteReturnsVoidAndRollsBackAStorageFailure(worker: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try LibraryStore(directory: directory, seed: false)
        let fixture = try ScriptTestFixture(content: "Deletion source", host: APIContractHost(), library: library)
        let editor = fixture.editor, host = fixture.host, runner = fixture.runner
        let noteID = try #require(editor.noteID)
        let unrelated = ActionRun(actionName: "Keep history", status: "Success", message: "Unrelated")
        library.log(unrelated)
        var entry = ActionRun(actionName: "Delete target", status: "Success", message: "Café 🐼")
        entry.noteID = noteID; library.log(entry)
        host.onPerform = { [weak host] operation in
            if operation == "clipboard" {
                if host?.clipboard == "arm" { library.beforeBatchCommit = nil }
                else { library.beforeBatchCommit = { throw DraftlyError.message("Injected log deletion failure") } }
            }
        }
        let action = makeAPIAction(#"""
        const entry=draft.actionLogs.find(v=>v.actionName==='Delete target'),id=entry.uuid;
        app.setClipboard('arm');
        let failed=false;try{entry.delete()}catch(e){failed=String(e).includes('Injected log deletion failure')}
        app.setClipboard('disarm');
        check(failed,'storage failure reaches script');
        check(draft.actionLogs.some(v=>v.uuid===id),'failed deletion retains log');
        check(entry.delete()===undefined,'delete void return');
        check(!draft.actionLogs.some(v=>v.uuid===id),'successful deletion removes only target');
        check(entry.delete()===undefined,'repeated deletion remains void');
        """#)
        let succeeded: Bool
        if worker { succeeded = await runner.runAsync(action).result.succeeded }
        else { succeeded = runner.run(action) }
        library.beforeBatchCommit = nil
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
        #expect(!library.runs.contains { $0.id == entry.id })
        #expect(library.notes.contains { $0.id == noteID })
        let reopened = try LibraryStore(directory: directory, seed: false)
        #expect(!reopened.runs.contains { $0.id == entry.id })
        #expect(reopened.runs.contains(unrelated))
        #expect(reopened.notes.contains { $0.id == noteID })
    }

    @Test func actionRelationUsesIdentityAcrossRenameAndDoesNotRetargetADeletedAction() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        let noteID = try #require(editor.noteID)
        var action = DraftAction(name: "Original action", steps: [])
        try library.saveAction(action)
        var entry = ActionRun(actionName: action.name, status: "Success", message: "Neutral")
        entry.noteID = noteID; entry.actionID = action.id; library.log(entry)
        action.name = "Renamed action"; try library.saveAction(action)
        #expect(runner.run(makeAPIAction("check(draft.actionLogs.find(v=>v.actionName==='Original action').action.name==='Renamed action','identity survives rename');")))
        try library.deleteAction(action.id)
        try library.saveAction(DraftAction(name: "Original action", steps: []))
        #expect(runner.run(makeAPIAction("check(draft.actionLogs.find(v=>v.actionName==='Original action').action===undefined,'deleted identity does not fall back to name');")))
        #expect(library.runs.contains(entry))
    }

    @Test func importedStatusSpellingUsesTheDocumentedScriptValuesWithoutRewritingRecords() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        let noteID = try #require(editor.noteID)
        let statuses = ["success", "SUCCESS", "error", "ERROR", "Cancelled", "pending", "in-progress", "completed", "failed"]
        for (index, status) in statuses.enumerated() {
            var run = ActionRun(actionName: String(index), status: status, message: "Neutral")
            run.noteID = noteID; library.log(run)
        }
        #expect(runner.run(makeAPIAction(#"""
        const expected=['completed','completed','failed','failed','cancelled','pending','in-progress','completed','failed'];
        for(const entry of draft.actionLogs) check(entry.status===expected[Number(entry.actionName)],'status '+entry.actionName);
        """#)), Comment(rawValue: runner.message ?? ""))
        for (index, status) in statuses.enumerated() {
            #expect(library.runs.contains { $0.actionName == String(index) && $0.status == status })
        }
    }

    @Test func logsAreFilteredOrderedTypedAndReadOnlyWithoutChangingStorage() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        let noteID = try #require(editor.noteID)
        let other = try library.createNote(content: "Unrelated café 🐼")
        var first = ActionRun(actionName: "Earlier", status: "Success", message: "Café 🐼\nFirst")
        first.noteID = noteID; first.date = Date(timeIntervalSince1970: 1_000.125)
        var last = ActionRun(actionName: "Later", status: "Error", message: "Second")
        last.noteID = noteID; last.date = Date(timeIntervalSince1970: 2_000.75)
        var unrelated = first; unrelated.id = UUID(); unrelated.noteID = other.id
        library.log(first); library.log(last); library.log(unrelated)
        #expect(runner.run(makeAPIAction(#"""
        const logs=draft.actionLogs;
        check(logs.length===2 && logs.every(v=>v instanceof ActionLog),'own typed history');
        check(logs.map(v=>v.actionName).join(',')==='Later,Earlier','newest first');
        check(logs.map(v=>v.executedAt.getTime()).join(',')==='2000750,1000125','date precision');
        check(logs[0].status==='failed' && logs[1].status==='completed','status mapping');
        check(logs[0].draft===draft && logs[0].action===undefined,'own draft and missing action');
        check(logs[1].log==='Café 🐼\nFirst','Unicode and newlines');
        for(const key of ['uuid','actionName','executedAt','executedDevice','executedLatitude','executedLongitude','log','status']) {
            check(Reflect.set(logs[0],key,'changed')===false,'readonly '+key);
        }
        logs.pop();check(draft.actionLogs.length===2,'returned array is independent');
        check(Reflect.set(draft,'actionLogs',[])===false,'readonly history property');
        const unsaved=Draft.create();check(unsaved.actionLogs.length===0,'unsaved draft history empty');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.runs.contains(first) && library.runs.contains(last) && library.runs.contains(unrelated))
    }
}
