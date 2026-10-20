import Foundation
import Testing
@testable import DraftlyCore

@Suite("Workspace scripting API") @MainActor
struct WorkspaceActionAPITests {
    private func workspaceFlagFixture() throws -> (LibraryStore, ActionRunner) {
        let (library, _, _, runner) = try makeAPIContext()
        for (title, archived, flag, tags, trashed) in [
            ("Inbox plain", false, 0, ["contract", "blue"], false),
            ("Inbox flagged", false, 1, ["contract", "green"], false),
            ("Archive plain", true, 0, ["contract", "blue", "blocked"], false),
            ("Archive flagged", true, 2, ["contract", "green"], false),
            ("Trash plain", false, 0, ["contract", "blue"], true)] {
            var note = try library.createNote(content: title, tags: tags)
            note.isArchived = archived; note.flag = flag; note.trashedAt = trashed ? Date() : nil
            try library.saveNote(note)
        }
        return (library, runner)
    }

    @Test func workspaceInboxIncludesFlaggedOnlyChangesInboxResults() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(makeAPIAction(#"""
        const w=new Workspace();w.tagFilter='contract';check(w.inboxIncludesFlagged===true,'default');
        check(w.query('inbox').length===2,'included');w.inboxIncludesFlagged=false;
        check(w.query('inbox').map(d=>d.title).join(',')==='Inbox plain','excluded');
        check(w.query('archive').length===2 && w.query('all').length===4,'other folders unaffected');
        w.name='Inbox flags';w.update();check(Workspace.find(w.name).inboxIncludesFlagged===false,'persisted');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceArchiveIncludesFlaggedOnlyChangesArchiveResults() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(makeAPIAction(#"""
        const w=new Workspace();w.tagFilter='contract';check(w.archiveIncludesFlagged===true,'default');
        check(w.query('archive').length===2,'included');w.archiveIncludesFlagged=false;
        check(w.query('archive').map(d=>d.title).join(',')==='Archive plain','excluded');
        check(w.query('inbox').length===2 && w.query('all').length===4,'other folders unaffected');
        w.name='Archive flags';w.update();check(Workspace.find(w.name).archiveIncludesFlagged===false,'persisted');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceFlaggedStatusFiltersEveryFolderAndRejectsUnknownValues() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(makeAPIAction(#"""
        const w=new Workspace();w.tagFilter='contract';check(w.flaggedStatus==='any' && w.query('all').length===4,'default');
        w.flaggedStatus='flagged';check(w.query('all').length===2 && w.query('inbox')[0].title==='Inbox flagged','flagged');
        w.flaggedStatus='unflagged';check(w.query('all').length===2 && w.query('archive')[0].title==='Archive plain','unflagged');
        w.name='Flag status';w.update();check(Workspace.find(w.name).flaggedStatus==='unflagged' && Workspace.find(w.name).query('all').length===2,'persisted status');
        w.flaggedStatus='invalid';let failed=false;try{w.query('all');}catch(e){failed=true;}check(failed,'invalid status');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceTagFilterCombinesInclusionsAndExclusionsAndSurvivesStorage() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(makeAPIAction(#"""
        const w=new Workspace();check(w.tagFilter==='','default');w.tagFilter=' CONTRACT , !blocked ';
        check(w.query('all').length===3,'inclusion and exclusion');w.name='Tag filter';w.update();
        const saved=Workspace.find(w.name);check(saved.tagFilter==='contract,!blocked' && saved.query('all').length===3,'stored normalization');
        w.tagFilter='!blocked';check(!w.query('all').some(d=>d.hasTag('blocked')),'exclusion only');
        w.tagFilter='missing';check(w.query('all').length===0,'no matches');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceTagFilterRequireAllChangesANDToORWithoutWeakeningExclusions() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(makeAPIAction(#"""
        const w=new Workspace();check(w.tagFilterRequireAll===true,'default');w.tagFilter='blue, green, !blocked';
        check(w.query('all').length===0,'AND');w.tagFilterRequireAll=false;
        check(w.query('all').length===3 && !w.query('all').some(d=>d.hasTag('blocked')),'OR keeps exclusion');
        w.name='Any tags';w.update();check(Workspace.find(w.name).tagFilterRequireAll===false,'persisted');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceQueryCoversAllFoldersAndRejectsInvalidFolder() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(makeAPIAction(#"""
        const w=new Workspace();w.tagFilter='contract';
        for(const [folder,count] of [['all',4],['inbox',2],['archive',2],['flagged',2],['trash',1]])check(w.query(folder).length===count,'folder '+folder);
        check(w.query().length===4,'omitted folder uses all');const first=w.query('inbox')[0];
        check(first===Draft.find(first.uuid),'cached draft identity');
        w.setInboxSort('name',false,false);check(w.query('inbox').map(d=>d.title).join(',')==='Inbox flagged,Inbox plain','workspace sort');
        w.setInboxSort('name',true,false);check(w.query('inbox').map(d=>d.title).join(',')==='Inbox plain,Inbox flagged','descending sort');
        let failed=false;try{w.query('invalid');}catch(e){failed=true;}check(failed,'invalid folder');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceConstructorIsIndependentAndDoesNotPersist() throws {
        let (library, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const a=new Workspace(),b=new Workspace();check(a!==b && a.startDate!==b.startDate,'independent values');
        check(a.name==='' && a.queryString==='' && a.tagFilter==='' && a.tagFilterRequireAll===true,'filter defaults');
        check(a.showDate && a.showPreview && a.showTags && a.showSearchPreview && !a.showLastAction,'display defaults');
        a.name='Unsaved';check(Workspace.find('Unsaved')===undefined,'constructor does not persist');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.workspaces.isEmpty)
    }

    @Test func workspaceCreateUsesDefaultConfigurationWithoutSavingIt() throws {
        let (library, _, _, runner) = try makeAPIContext()
        runner.defaultWorkspace = { var w = Workspace(name: ""); w.query = "café"; w.tags = ["work"]; return w }
        #expect(runner.run(makeAPIAction(#"""
        const a=Workspace.create(),b=Workspace.create();check(a!==b && a.uuid!==b.uuid,'fresh identity');
        check(a.queryString==='café' && a.tagFilter==='work','default configuration');
        a.queryString='changed';check(b.queryString==='café','independent defaults');
        check(Workspace.getAll().length===0,'factory does not persist');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.workspaces.isEmpty)
    }

    @Test func workspaceFindMatchesExactNameAndReturnsTypedValues() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const w=new Workspace();w.name='Café 🐼';w.update();const found=Workspace.find('Café 🐼');
        check(found instanceof Workspace && found.startDate instanceof QueryDate,'typed result');
        check(Workspace.find('café 🐼')===undefined && Workspace.find('missing')===undefined,'exact missing names');
        found.name='Unsaved rename';check(Workspace.find('Café 🐼').name==='Café 🐼','no implicit persistence');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceGetAllReturnsIndependentStoredWorkspaces() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        check(Workspace.getAll().length===0,'empty library');
        for(const name of ['One','Two']){const w=new Workspace();w.name=name;w.update();}
        const all=Workspace.getAll();check(all.length===2 && all.every(w=>w instanceof Workspace),'stored values');
        all[0].name='Unsaved';all.pop();check(Workspace.getAll().length===2 && !Workspace.getAll().some(w=>w.name==='Unsaved'),'independent results');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceUpdateReturnsVoidAndRollsBackStorageFailure() throws {
        let (library, _, host, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction("const w=new Workspace();w.name='Before failure';check(w.update()===undefined,'void return');")))
        let original = try #require(library.workspaces.first)
        host.onPerform = { operation in if operation == "clipboard" { library.beforeBatchCommit = { throw DraftlyError.message("Workspace storage failure") } } }
        defer { library.beforeBatchCommit = nil }
        #expect(!runner.run(makeAPIAction("const w=Workspace.find('Before failure');w.name='Lost rename';app.setClipboard('Arm');w.update();app.setClipboard('Must not run');")))
        #expect(runner.message?.contains("Workspace storage failure") == true)
        #expect(host.clipboard == "Arm")
        #expect(library.workspaces == [original])
        let restored = try LibraryStore(inMemory: true, seed: false); try restored.restore(library.backupData())
        #expect(restored.workspaces == [original])
    }

    @Test func workspaceUpdateRejectsInvalidConfigurationBeforePersistence() throws {
        let (library, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const mutations=[w=>w.loadFolder='missing',w=>w.flaggedStatus='missing',w=>w.setInboxSort('missing',false,false),w=>w.startDate.field='missing',w=>w.endDate.type='missing',w=>{w.startDate.type='absolute';w.startDate.date='not a date';}];
        for(const mutate of mutations){const w=new Workspace();w.name='Invalid';mutate(w);let failed=false;try{w.update();}catch(e){failed=true;}check(failed,'invalid update rejected');check(Workspace.find('Invalid')===undefined,'no partial save');}
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.workspaces.isEmpty)
    }

    @Test func workspaceApplicationReturnsTheHostResultAndDefaultsWhenOmitted() throws {
        let (_, _, _, runner) = try makeAPIContext()
        var applied: [Workspace] = []
        runner.defaultWorkspace = { Workspace(name:"Default contract") }
        runner.applyWorkspace = { applied.append($0) }
        #expect(runner.run(makeAPIAction("check(app.applyWorkspace()===true,'default app result');let w=Workspace.create();w.name='Explicit';check(window.applyWorkspace(w)===true,'window result');")),Comment(rawValue: runner.message ?? ""))
        #expect(applied.map(\.name) == ["Default contract","Explicit"])
    }

    @Test func invalidWorkspaceValuesFailExplicitly() throws {
        let (_, _, _, runner) = try makeAPIContext()
        for script in ["w.loadFolder='missing';", "w.flaggedStatus='missing';", "w.startDate.type='missing';", "w.startDate.type='absolute';w.startDate.date=new Date('invalid');", "w.startDate.field='missing';", "w.setAllSort('missing',false,false);"] {
            #expect(!runner.run(makeAPIAction("const w=Workspace.create();"+script+"w.update();")))
        }
    }

    @Test func workspaceDefaultsAndAllFolderSortsRoundTrip() throws {
        let (library, _, _, runner) = try makeAPIContext()
        runner.defaultWorkspace = { var w=Workspace(name:"");w.listOptions=DraftListOptions();w.listOptions?.showTags=false;return w }
        #expect(runner.run(makeAPIAction(#"""
        const w=Workspace.create();check(w.showTags===false,'default display preferences');
        w.name='Every folder';w.archiveIncludesFlagged=false;w.inboxIncludesFlagged=true;w.flaggedStatus='any';
        w.showDate=false;w.showLastAction=true;w.showPreview=false;w.showSearchPreview=false;w.showTags=true;
        w.setAllSort('created',true,false);w.setArchiveSort('name',false,true);
        w.setInboxSort('modified',true,false);w.setFlaggedSort('name',false);
        w.startDate=QueryDate.create();w.startDate.type='relative';w.startDate.days=-1;
        w.endDate=new QueryDate();w.endDate.type='absolute';w.endDate.date=new Date('2100-01-01T00:00:00Z');
        w.update();const saved=Workspace.find(w.name);
        check(saved.name===w.name && saved.installURL.startsWith('draftly://workspace?'),'identity');
        check(saved.endDate.date instanceof Date && saved.startDate.days===-1,'date values');
        check(saved.archiveIncludesFlagged===false && saved.showDate===false && saved.showTags===true,'display persistence');
        for(let folder of ['all','inbox','archive','flagged','trash'])check(Array.isArray(saved.query(folder)),'folder '+folder);
        check(Workspace.getAll().some(x=>x.name===w.name),'all workspaces');
        """#)), Comment(rawValue: runner.message ?? ""))
        let restored = try LibraryStore(inMemory:true,seed:false);try restored.restore(library.backupData())
        #expect(restored.workspaces.first?.apiOptions["archiveIncludesFlagged"] as? Bool == false)
        #expect(restored.workspaces.first?.listOptions?.showDate == false)
    }

    @Test func queryUsesOmittedTagsAscendingOrderAndStableDraftIdentity() throws {
        let (library, _, _, runner) = try makeAPIContext()
        _ = try library.createNote(content: "Zulu", tags: ["keep"])
        _ = try library.createNote(content: "Alpha", tags: ["keep"])
        _ = try library.createNote(content: "Hidden", tags: ["keep", "omit"])
        #expect(runner.run(makeAPIAction(#"""
        let matches=Draft.query('', 'all', ['keep'], ['omit'], 'name');
        check(matches.map(d=>d.title).join(',')==='Alpha,Zulu','omit tags and ascending default');
        check(matches[0]===Draft.find(matches[0].uuid),'find identity');
        matches[0].addTag(' PENDING ');
        check(Draft.queryByTitle('Alpha')[0].hasTag('pending'),'query preserves unsaved properties');
        matches[0].update();
        check(matches[0].modifiedAt instanceof Date,'updated date');
        check(!Draft.query('', 'all', [], true).some(d=>d.isFlagged),'legacy boolean');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func accessedQueriesPersistWorkspaceAndOnlyEditorLoadsRecordAccess() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        let unknown = try library.createNote(content: "Unknown")
        let older = try library.createNote(content: "Older")
        let newer = try library.createNote(content: "Newer")
        try library.recordAccess(older.id, at: Date(timeIntervalSince1970: 100))
        try library.recordAccess(newer.id, at: Date(timeIntervalSince1970: 200))
        let originalModified = try #require(library.notes.first { $0.id == unknown.id }).modifiedAt
        let originalVersions = library.revisions.filter { $0.noteID == unknown.id }
        var applied: Workspace?
        runner.applyWorkspace = { applied = $0 }
        #expect(runner.run(makeAPIAction(#"""
        let w=Workspace.create();w.name='Access contract';w.setAllSort('accessed',true,false);
        w.startDate.type='absolute';w.startDate.field='accessed';w.startDate.date=new Date('1970-01-01T00:00:00Z');
        w.update();let saved=Workspace.find('Access contract');
        check(saved.startDate.field==='accessed','persisted access field');
        check(saved.query('inbox').map(d=>d.title).join(',')==='Newer,Older','known access order');
        app.applyWorkspace(saved);
        check(Draft.query('', 'all', [], [], 'accessed', false)[0].title==='Older','ascending access query');
        check(Draft.queryByTitle('Unknown').length===1,'query unknown date');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(applied?.filter(library.notes).map(\.id) == [newer.id, older.id])
        #expect(library.notes.first { $0.id == unknown.id }?.accessedAt == nil)
        #expect(runner.run(makeAPIAction("editor.load(Draft.find('\(unknown.id.uuidString)'));")), Comment(rawValue: runner.message ?? ""))
        #expect(editor.noteID == unknown.id)
        let opened = try #require(library.notes.first { $0.id == unknown.id })
        #expect(opened.accessedAt != nil)
        #expect(opened.modifiedAt == originalModified)
        #expect(library.revisions.filter { $0.noteID == unknown.id } == originalVersions)
    }

    @Test func workspaceRestoresTypedDatesAndUsesTheSameNativeFilters() throws {
        let (library, _, _, runner) = try makeAPIContext()
        _ = try library.createNote(content: "Alpha", tags: ["keep"])
        var flagged = try library.createNote(content: "Flagged", tags: ["keep"]); flagged.flag=1; try library.saveNote(flagged)
        var applied: Workspace?
        runner.applyWorkspace = { applied=$0 }
        #expect(runner.run(makeAPIAction(#"""
        let w=Workspace.create();w.name='Contract';w.tagFilter='keep';w.loadFolder='inbox';
        w.inboxIncludesFlagged=false;w.showTags=false;w.showPreview=false;w.showLastAction=true;
        w.startDate.type='absolute';w.startDate.date=new Date('2000-01-01T00:00:00Z');
        w.setInboxSort('name',false,true);w.update();
        let saved=Workspace.find('Contract');check(saved.startDate instanceof QueryDate,'typed query date');
        check(saved.startDate.date instanceof Date,'restored Date');
        check(saved.query('inbox').map(d=>d.title).join(',')==='Alpha','script query');
        app.applyWorkspace(saved);
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(applied?.filter(library.notes).map(\.title) == ["Alpha"])
        #expect(applied?.listOptions?.showTags == false)
        #expect(applied?.listOptions?.showPreview == false)
        #expect(applied?.listOptions?.showLastAction == true)
    }

    @Test func workspacePersistsFiltersDatesAndFolderSorts() throws {
        let (library, _, _, runner) = try makeAPIContext()
        _ = try library.createNote(content: "# Zulu", tags: ["project", "omit"])
        _ = try library.createNote(content: "# Alpha", tags: ["project"])
        let source = #"""
        let w = Workspace.create(); w.name = 'Projects'; w.tagFilter = 'project, !omit';
        w.tagFilterRequireAll = true; w.setAllSort('name',false,true); w.showTags = false;
        w.startDate.type = 'relative'; w.startDate.days = -1; w.update();
        let loaded = Workspace.find('Projects');
        check(loaded.showTags === false && loaded.startDate.days === -1, 'workspace persistence');
        check(loaded.query('all').length === 1 && loaded.query('all')[0].displayTitle === 'Alpha', 'workspace filters');
        check(Workspace.getAll().length === 1, 'workspace listing');
        """#
        #expect(runner.run(makeAPIAction(source)), Comment(rawValue: runner.message ?? ""))
        #expect(library.workspaces.count == 1)
    }
}
