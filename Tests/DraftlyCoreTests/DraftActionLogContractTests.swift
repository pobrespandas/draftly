import Foundation
import Testing
@testable import DraftlyCore

@Suite("Draft action log member contracts") @MainActor
struct DraftActionLogContractTests {
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
