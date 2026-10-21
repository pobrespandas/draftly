import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action configured value contracts") @MainActor
struct ActionConfiguredValuesContractTests {
    @Test(arguments: [false, true])
    func otherActionSnapshotsUseTypedStoredConfigurationWithoutChangingExecutionContext(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        var source = DraftAction(name: "Typed café 🐼", steps: [
            ActionStep("configurationKey", ["key": "enabled", "dataType": "boolean", "defaultBoolValue": "true"]),
            ActionStep("configurationKey", ["key": "count", "dataType": "number", "defaultNumberValue": "9"]),
            ActionStep("configurationKey", ["key": "label", "dataType": "text", "defaultTextValue": "Default"])
        ])
        source.group = "Typed values QA"
        source.configuredValues = ["enabled": "false", "count": "3.5", "label": "café 🐼\nText", "future": "Keep"]
        var disabled = ActionStep("configurationKey", ["key": "count", "dataType": "string"])
        disabled.isEnabled = false
        source.steps.append(disabled)
        let empty = DraftAction(name: "No configuration", steps: [])
        try library.saveActions([source, empty])
        var run = ActionRun(actionName: source.name, status: "Success", message: "Neutral history")
        run.actionID = source.id
        library.log(run)
        let before = try JSONDecoder().decode(Backup.self, from: library.backupData())
        var probe = makeAPIAction(#"""
        const own=action.configuredValues;
        check(own===context.configuredValues && own.local===true,'own shared typed context');
        const found=Action.find('Typed café 🐼');
        const snapshots=[found,ActionGroup.find('Typed values QA').actions[0],Action.recent()[0]];
        for(const item of snapshots){
            const values=item.configuredValues;
            check(values.enabled===false,'stored boolean');
            check(values.count===3.5,'stored number and disabled field exclusion');
            check(values.label==='café 🐼\nText' && values.future==='Keep','text and unknown key');
            check(Reflect.set(item,'configuredValues',{})===false,'readonly object replacement');
        }
        check(Object.keys(Action.find('No configuration').configuredValues).length===0,'empty configuration');
        check(action.configuredValues===own && own.local===true && own.count===undefined,'other action lookup preserves current context');
        """#)
        probe.steps.insert(ActionStep("configurationKey", ["key": "local", "dataType": "boolean", "defaultBoolValue": "true"]), at: 0)
        probe.presentation.logLevel = 0
        #expect(await ActionTestExecution.succeeds(probe, runner: runner, worker: worker),
                Comment(rawValue: runner.message ?? ""))
        #expect(library.actions == before.actions)
        #expect(library.actionGroups == before.actionGroups)
        #expect(library.runs == before.runs)
    }
}
