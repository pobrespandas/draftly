import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action group query contracts") @MainActor
struct ActionGroupQueryContractTests {
    @Test(arguments: [false, true])
    func findUsesExactDisplayNameAndReturnsUndefinedWhenAbsent(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        try library.saveActionGroup(ActionGroupRecord(name: "Café 🐼"))
        let source = makeAPIAction(#"""
        const group=ActionGroup.find('Café 🐼');
        check(group instanceof ActionGroup && group.name==='Café 🐼','exact Unicode lookup');
        for(const name of ['café 🐼','Café','Café 🐼 ','','Missing'])
            check(ActionGroup.find(name)===undefined,'absent exact name '+name);
        check(ActionGroup.find('Café 🐼').uuid===group.uuid,'stable repeat lookup');
        """#)
        #expect(await execute(source, runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
    }

    @Test(arguments: [false, true])
    func getAllIncludesEmptyAndImplicitGroupsWithoutExposingMutableStorage(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        #expect(await execute(makeAPIAction("check(Array.isArray(ActionGroup.getAll()) && ActionGroup.getAll().length===0,'empty catalog');"), runner: runner, worker: worker))
        try library.saveActionGroup(ActionGroupRecord(name: "Empty"))
        var member = DraftAction(name: "Member", steps: []); member.group = "Implicit"
        try library.saveActions([member])
        let source = makeAPIAction(#"""
        const groups=ActionGroup.getAll();
        check(groups.length===2 && groups.every(x=>x instanceof ActionGroup),'all available groups');
        check(groups.some(x=>x.name==='Empty') && groups.some(x=>x.name==='Implicit'),'empty and implicit');
        check(new Set(groups.map(x=>x.uuid)).size===2,'unique identities');
        groups.pop();groups.push(new ActionGroup({name:'Local'}));
        check(ActionGroup.getAll().length===2 && !ActionGroup.find('Local'),'array edits are local');
        """#)
        #expect(await execute(source, runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
    }

    @Test(arguments: [false, true])
    func actionsIncludesHiddenDisabledAndSeparatorEntriesInStoredOrder(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        try library.saveActionGroup(ActionGroupRecord(name: "Empty"))
        var hidden = DraftAction(name: "Hidden", steps: []); hidden.group = "Members"
        hidden.presentation.order = 2; hidden.presentation.showInList = false
        hidden.presentation.showInBar = false; hidden.presentation.showInSearch = false
        var separator = DraftAction(name: "Section", steps: []); separator.group = "Members"
        separator.presentation.order = 1; separator.scriptMetadata = ["isSeparator": "true"]
        var disabled = DraftAction(name: "Disabled step", steps: []); disabled.group = "Members"
        disabled.presentation.order = 3
        var step = ActionStep("unknown", [:]); step.isEnabled = false; disabled.steps = [step]
        var other = DraftAction(name: "Other", steps: []); other.group = "Elsewhere"
        try library.saveActions([hidden, separator, disabled, other])
        let source = makeAPIAction(#"""
        check(ActionGroup.find('Empty').actions.length===0,'empty group members');
        const group=ActionGroup.find('Members'), values=group.actions;
        check(values.length===3 && values.every(x=>x instanceof Action),'typed members');
        check(values.map(x=>x.name).join('|')==='Section|Hidden|Disabled step','stored order includes hidden and disabled');
        check(values[0].isSeparator===true,'separator retained');
        check(Reflect.set(group,'actions',[])===false,'readonly collection property');
        values.length=0;
        check(group.actions.length===3,'returned array does not mutate storage');
        check(!group.actions.some(x=>x.name==='Other'),'other group excluded');
        """#)
        #expect(await execute(source, runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
    }

    private func execute(_ action: DraftAction, runner: ActionRunner, worker: Bool) async -> Bool {
        if worker { return await runner.runAsync(action).result.succeeded }
        return runner.run(action)
    }
}
