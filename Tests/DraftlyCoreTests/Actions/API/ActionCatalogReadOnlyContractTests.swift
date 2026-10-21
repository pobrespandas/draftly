import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action catalog read-only contracts") @MainActor
struct ActionCatalogReadOnlyContractTests {
    @Test(arguments: [false, true])
    func collidingImplicitGroupsExposeTheirStoredIdentities(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        let first = "B" + String(repeating: "A", count: 16)
        let second = "?" + String(repeating: "A", count: 15)
        var a = DraftAction(name: "Collision A", steps: []); a.group = first
        var b = DraftAction(name: "Collision B", steps: []); b.group = second
        try library.saveActions([a, b])
        let firstID = library.actionGroupRecord(named: first).id.uuidString
        let secondID = library.actionGroupRecord(named: second).id.uuidString
        let source = makeAPIAction("""
        const a=ActionGroup.find('\(first)'), b=ActionGroup.find('\(second)');
        check(a.uuid==='\(firstID)' && b.uuid==='\(secondID)' && a.uuid!==b.uuid,'distinct persisted identities');
        check(a.actions.some(x=>x.name==='Collision A') && !a.actions.some(x=>x.name==='Collision B'),'first membership');
        check(b.actions.some(x=>x.name==='Collision B') && !b.actions.some(x=>x.name==='Collision A'),'second membership');
        """)
        let succeeded = await ActionTestExecution.succeeds(source, runner: runner, worker: worker)
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
    }

    @Test(arguments: [false, true])
    func actionIdentificationAndConfigurationCannotBeReassigned(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        var source = makeAPIAction(#"""
        check(action.configuredValues===context.configuredValues,'shared execution configuration');
        check(action.configuredValues.label==='Configured café 🐼','configured value remains available');
        action.configuredValues.local='Temporary';
        check(context.configuredValues.local==='Temporary','configuration contents remain mutable');
        delete action.configuredValues.local;
        check(action.name==='Readonly action' && typeof action.uuid==='string' && action.isSeparator===false,'normal action fields');
        check(Action.find('Readonly separator').isSeparator===true,'separator field');
        for(const candidate of [action,Action.find(action.name),Action.find('Readonly separator')]) {
            const original={name:candidate.name,uuid:candidate.uuid,isSeparator:candidate.isSeparator,configuredValues:candidate.configuredValues};
            for(const [key,value] of Object.entries({name:'Replaced',uuid:'wrong',isSeparator:true,configuredValues:{label:'Wrong'}})) {
                check(Reflect.set(candidate,key,value)===false,'readonly '+key);
                check(candidate[key]===original[key],'unchanged '+key);
            }
            check(candidate.installURL.startsWith('draftly://action?'),'installation keeps source identity');
        }
        """#)
        source.name = "Readonly action"
        source.configuredValues = ["label": "Configured café 🐼"]
        try library.saveAction(source)
        var separator = DraftAction(name: "Readonly separator", steps: [])
        separator.scriptMetadata = ["isSeparator": "true"]
        try library.saveAction(separator)
        let succeeded = await ActionTestExecution.succeeds(source, runner: runner, worker: worker)
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
        #expect(library.actions.first { $0.id == source.id } == source)
    }

    @Test(arguments: [false, true])
    func groupIdentificationCannotBeReassignedOrRetargetItsActions(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        var member = makeAPIAction("")
        member.name = "Group member"
        member.group = "Readonly group"
        try library.saveAction(member)
        let source = makeAPIAction(#"""
        const group=ActionGroup.find('Readonly group');
        check(group instanceof ActionGroup,'group found');
        const id=group.uuid;
        check(Reflect.set(group,'name','Missing group')===false,'readonly group name');
        check(Reflect.set(group,'uuid','wrong')===false,'readonly group UUID');
        check(group.name==='Readonly group' && group.uuid===id,'unchanged group identity');
        check(group.actions.length===1 && group.actions[0].name==='Group member','actions keep their owner');
        check(group.installURL.startsWith('draftly://action?'),'group installation remains available');
        """#)
        let succeeded = await ActionTestExecution.succeeds(source, runner: runner, worker: worker)
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
        #expect(library.actions.first { $0.id == member.id } == member)
        var group = ActionGroupRecord(name: "Readonly group")
        let originalID = group.id
        group.name = "Renamed group"
        try library.saveActionGroup(group, replacing: "Readonly group")
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        let editor = EditorSession()
        editor.load(try #require(restored.notes.first))
        let restoredRunner = ActionRunner(library: restored, editor: editor)
        let query = makeAPIAction("""
        check(ActionGroup.find('Readonly group')===undefined,'old name removed');
        const group=ActionGroup.find('Renamed group');
        check(group.name==='Renamed group' && group.uuid==='\(originalID.uuidString)','identity survives rename and backup');
        check(group.actions[0].uuid==='\(member.id.uuidString)','member identity survives rename');
        """)
        let restoredSuccess = await ActionTestExecution.succeeds(query, runner: restoredRunner, worker: worker)
        #expect(restoredSuccess, Comment(rawValue: restoredRunner.message ?? ""))
    }
}
