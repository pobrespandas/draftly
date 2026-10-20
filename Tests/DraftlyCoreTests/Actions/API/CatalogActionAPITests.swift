import Foundation
import Testing
@testable import DraftlyCore

@Suite("Catalog scripting API") @MainActor
struct CatalogActionAPITests {
    @Test func actionAndGroupQueriesKeepIdentityOrderAndInstallationData() throws {
        let (library, editor, host, runner) = try makeAPIContext()
        var first = makeAPIAction("");first.name="First";first.group="Contracts";first.configuredValues=["key":"value"];first.presentation.order=2
        var second = makeAPIAction("");second.name="Second";second.group="Contracts";second.presentation.order=1
        try library.saveAction(first);try library.saveAction(second)
        var log = ActionRun(actionName:"Previous name",status:"Success",message:"");log.actionID=first.id;log.noteID=editor.noteID;library.log(log)
        #expect(runner.run(makeAPIAction(#"""
        const a=Action.find('First');check(a.name==='First' && typeof a.uuid==='string','action identity');
        check(a.configuredValues.key==='value' && a.isSeparator===false,'action properties');
        check(Action.find('missing')===undefined,'missing action');
        check(Action.recent()[0].uuid===a.uuid,'recent identity after rename');
        const group=ActionGroup.find('Contracts');check(group && typeof group.uuid==='string','group identity');
        check(group.actions.map(a=>a.name).join(',')==='Second,First','group order');
        check(ActionGroup.getAll().some(g=>g.uuid===group.uuid),'all groups');
        check(ActionGroup.find('missing')===undefined,'missing group');
        check(a.installURL.startsWith('draftly://action?'),'action link');
        check(group.installURL.startsWith('draftly://action?'),'group link');
        app.setClipboard(group.installURL);
        """#)), Comment(rawValue: runner.message ?? ""))
        let link = try #require(URL(string: host.clipboard))
        let restored = try ActionImporter.installationActions(link)
        #expect(restored.map(\.id) == [second.id,first.id])
        #expect(restored[1].configuredValues == ["key":"value"])
    }

    @Test func tagSyntaxAndVersionMembersUsePersistedValues() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        let id = try #require(editor.noteID)
        var note = try #require(library.notes.first);note.tags=["blue", "black"];try library.saveNote(note)
        try library.saveRevision(Revision(noteID:id,content:"Saved 🐼"))
        #expect(runner.run(makeAPIAction(#"""
        check(Tag.query('bl').join(',')==='black,blue','tag query');
        check(Tag.query('missing').length===0,'empty tag query');
        check(Tag.recentTags().length===2,'recent tags');
        check(new Tag().renameTag('blue','green')===1,'rename count');
        check(Tag.query('gr')[0]==='green','renamed tag');
        check(new Tag().renameTag('missing','new')===0,'missing tag count');
        const syntax=Syntax.find('builtIn','Markdown');check(syntax instanceof Syntax && syntax.name==='Markdown' && syntax.type==='builtIn','syntax properties');
        check(Syntax.find('builtIn','Missing')===undefined,'missing syntax');
        check(Syntax.getAll().some(s=>s.name==='TaskPaper'),'all syntax');
        check(new Syntax().name==='Markdown','syntax constructor');
        const version=draft.versions.find(v=>v.content==='Saved 🐼');
        check(version && typeof version.uuid==='string' && version.createdAt instanceof Date,'version fields');
        check(version.draft===draft,'version draft identity');
        check(version.delete()===undefined,'delete return');
        check(!draft.versions.some(v=>v.uuid===version.uuid),'deleted version');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(!library.revisions.contains { $0.content == "Saved 🐼" })
    }

    @Test func importedSeparatorsRetainTheirAPIIdentityAndRawPayload() throws {
        let (library, _, _, runner) = try makeAPIContext()
        let json = Data(#"{"name":"Section","backingIsSeparator":true,"steps":[],"unknown":{"nested":[1,2]}}"#.utf8)
        let imported = try #require(ActionImporter.decode(json).first)
        try library.saveAction(imported)
        #expect(imported.rawPayload?.contains("unknown") == true)
        #expect(runner.run(makeAPIAction("check(Action.find('Section').isSeparator===true,'imported separator');")))
    }

    @Test func actionLogsKeepTheirActionAfterRenameAndUseOfficialStatuses() throws {
        let (library, _, _, runner) = try makeAPIContext()
        var saved = makeAPIAction("context.cancel('Reason');");try library.saveAction(saved)
        #expect(!runner.run(saved))
        #expect(library.runs.first?.message == "Reason")
        saved.name="Renamed";try library.saveAction(saved)
        #expect(runner.run(makeAPIAction(#"""
        const log=draft.actionLogs[0];
        check(log.status==='cancelled' && log.log==='Reason','cancel log');
        check(log.action.name==='Renamed' && log.draft.uuid===draft.uuid,'relations');
        check(log.executedAt instanceof Date && log.executedDevice==='Mac','log date');
        check(log.executedLatitude===0 && log.executedLongitude===0,'log location');
        """#)),Comment(rawValue:runner.message ?? ""))
    }

    @Test func versionsTagsAndRecentActionsAreQueryable() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        let first = makeAPIAction("draft.addTag('old'); draft.update(); draft.saveVersion();")
        try library.saveAction(first)
        #expect(runner.run(first))
        #expect(runner.run(makeAPIAction(#"""
        check(draft.actionLogs.length === 1 && draft.actionLogs[0].status==='completed', 'draft logs');
        check(Action.recent()[0].name === 'API contract', 'recent action');
        check(new Tag().renameTag('old','new') === 1, 'rename count');
        check(Tag.query('new')[0] === 'new', 'query tags');
        let version = draft.versions[0];
        check(version.createdAt instanceof Date && version.draft.uuid === draft.uuid, 'version metadata');
        let count = draft.versions.length; version.delete(); check(draft.versions.length === count-1,'delete version');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.id == editor.noteID }?.tags == ["new"])
    }
}
