import Foundation
import Testing
@testable import DraftlyCore

@Suite("Recent action contracts") @MainActor
struct ActionRecentContractTests {
    @Test(arguments: [false, true])
    func savedHistoryReturnsUniqueCurrentActionsInReverseDateOrderWithoutMutation(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        var emptyProbe = makeAPIAction("check(Array.isArray(Action.recent()) && Action.recent().length===0,'empty recent actions');")
        emptyProbe.presentation.logLevel = 0
        #expect(await ActionTestExecution.succeeds(emptyProbe, runner: runner, worker: worker),
                Comment(rawValue: runner.message ?? ""))
        #expect(library.runs.isEmpty)

        var renamed = DraftAction(name: "Original name", steps: [])
        let older = DraftAction(name: "Older café 🐼", steps: [])
        let legacy = DraftAction(name: "Legacy name", steps: [])
        let deleted = DraftAction(name: "Deleted", steps: [])
        let unused = DraftAction(name: "Unused name match", steps: [])
        try library.saveActions([renamed, older, legacy, deleted, unused])

        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        func record(_ action: DraftAction, at seconds: TimeInterval, identity: UUID?, name: String? = nil) {
            var run = ActionRun(actionName: name ?? action.name, status: "Success", message: "Neutral history")
            run.date = origin.addingTimeInterval(seconds)
            run.actionID = identity
            library.log(run)
        }
        // Insert records out of date order. The second use must not repeat an action.
        record(older, at: 20, identity: older.id)
        record(renamed, at: 10, identity: renamed.id)
        record(legacy, at: 30, identity: nil)
        record(renamed, at: 40, identity: renamed.id)
        record(deleted, at: 50, identity: deleted.id)
        record(unused, at: 60, identity: UUID())
        renamed.name = "Renamed café 🐼"
        try library.saveAction(renamed)
        try library.deleteAction(deleted.id)
        let before = try library.backupData()

        var probe = makeAPIAction("""
        const first=Action.recent(), second=Action.recent();
        check(Array.isArray(first) && first.every(value=>value instanceof Action),'Action array');
        check(first.map(value=>value.uuid).join(',')==='\(renamed.id),\(legacy.id),\(older.id)','reverse date order and unique identities');
        check(first.map(value=>value.name).join('|')==='Renamed café 🐼|Legacy name|Older café 🐼','current names and legacy lookup');
        check(!first.some(value=>value.uuid==='\(deleted.id)' || value.uuid==='\(unused.id)'),'deleted and unknown identities excluded');
        check(second.map(value=>value.uuid).join(',')===first.map(value=>value.uuid).join(','),'repeat read');
        """)
        probe.presentation.logLevel = 0
        #expect(await ActionTestExecution.succeeds(probe, runner: runner, worker: worker),
                Comment(rawValue: runner.message ?? ""))
        #expect(try library.backupData() == before)
    }
}
