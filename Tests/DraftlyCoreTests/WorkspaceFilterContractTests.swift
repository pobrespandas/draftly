import Foundation
import Testing
@testable import DraftlyCore

@Suite("Workspace filter contracts") @MainActor
struct WorkspaceFilterContractTests {
    @Test(arguments: NoteSort.allCases.map(\.rawValue), [false, true])
    func tiedSortKeysKeepIdentityOrderAcrossReloads(sortName: String, ascending: Bool) {
        let sort = NoteSort(rawValue: sortName)!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let notes = (1...3).map { value -> Note in
            var note = Note(content: "Same title")
            note.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
            note.createdAt = date; note.modifiedAt = date; note.accessedAt = date
            return note
        }
        var workspace = Workspace(name: "Stable order")
        workspace.sort = sort; workspace.ascending = ascending
        for input in [notes, Array(notes.reversed()), [notes[1], notes[2], notes[0]]] {
            #expect(workspace.filter(input).map(\.id) == notes.map(\.id))
        }
        var flagged = notes[2]; flagged.flag = 1
        let name = sort == .title ? "name" : sort.rawValue
        workspace.scriptMetadata = ["api": "{\"_sorts\":{\"inbox\":{\"sort\":\"\(name)\",\"descending\":\(!ascending),\"flagged\":true}}}"]
        #expect(workspace.filter([notes[1], flagged, notes[0]]).map(\.id) == [flagged.id, notes[0].id, notes[1].id])
    }

    private struct Harness {
        let library: LibraryStore
        let editor: EditorSession
        let runner: ActionRunner
    }

    private func harness(notes: [Note] = [], library: LibraryStore? = nil) throws -> Harness {
        let library = try library ?? LibraryStore(inMemory: true, seed: false)
        let source: Note
        if let existing = library.notes.first(where: { $0.content == "Workspace contract source" }) {
            source = existing
        } else {
            source = try library.createNote(content: "Workspace contract source")
        }
        for note in notes { try library.saveNote(note, preserveDates: true) }
        let editor = EditorSession()
        editor.load(source)
        return Harness(library: library, editor: editor,
                       runner: ActionRunner(library: library, editor: editor))
    }

    private func run(_ script: String, in harness: Harness) {
        let action = ScriptTestAction.make(script, name: "Workspace filter contract",
            helpers: "function titles(workspace, folder) { return workspace.query(folder).map(d => d.title).join('|'); }\n")
        #expect(harness.runner.run(action), Comment(rawValue: harness.runner.message ?? ""))
    }

    private func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_577_880_000 + Double(day) * 86_400)
    }

    private func fixture(_ number: Int, _ title: String, created: Int, modified: Int,
                         accessed: Int?, flag: Int = 0, archived: Bool = false,
                         trashed: Bool = false, tags: [String] = ["order-fixture"]) -> Note {
        Note(id: UUID(uuidString: String(format: "DAAF7200-0000-4000-8000-%012d", number))!,
             content: title, tags: tags, flag: flag, isArchived: archived,
             trashedAt: trashed ? date(300) : nil,
             createdAt: date(created), modifiedAt: date(modified),
             accessedAt: accessed.map(date))
    }

    private func orderedFixtures() -> [Note] {
        [
            fixture(1, "Inbox Alpha", created: 30, modified: 10, accessed: 20),
            fixture(2, "Inbox Bravo", created: 10, modified: 30, accessed: 30, flag: 1),
            fixture(3, "Inbox Charlie", created: 20, modified: 20, accessed: 10, flag: 2),
            fixture(4, "Inbox Delta", created: 40, modified: 40, accessed: nil),
            fixture(5, "Archive Alpha", created: 130, modified: 110, accessed: 120, archived: true),
            fixture(6, "Archive Bravo", created: 110, modified: 130, accessed: 130, flag: 1, archived: true),
            fixture(7, "Archive Charlie", created: 120, modified: 120, accessed: 110, flag: 2, archived: true),
            fixture(8, "Archive Delta", created: 140, modified: 140, accessed: nil, archived: true),
            fixture(9, "Trash Alpha", created: 230, modified: 210, accessed: 220, trashed: true),
            fixture(10, "Trash Bravo", created: 210, modified: 230, accessed: 230, flag: 1, trashed: true),
            fixture(11, "Trash Charlie", created: 220, modified: 220, accessed: 210, flag: 2, trashed: true),
            fixture(12, "Trash Delta", created: 240, modified: 240, accessed: nil, trashed: true)
        ]
    }

    private var sortSetup: String {
        """
        const w=new Workspace();w.tagFilter='order-fixture';
        function configure(sort, descending, flagged) {
            w.setInboxSort(sort,descending,flagged);
            w.setArchiveSort(sort,descending,flagged);
            w.setFlaggedSort(sort,descending);
            w.setAllSort(sort,descending,flagged);
        }
        """
    }

    @Test func tagFilterNormalizesUnicodeDuplicatesAndExclusionsForANDAndOR() throws {
        let notes = [
            fixture(21, "Both", created: 1, modified: 1, accessed: nil,
                    tags: ["café", "🐼", "タグ"]),
            fixture(22, "Accent only", created: 1, modified: 1, accessed: nil, tags: ["café"]),
            fixture(23, "Emoji only", created: 1, modified: 1, accessed: nil, tags: ["🐼"]),
            fixture(24, "Blocked", created: 1, modified: 1, accessed: nil,
                    tags: ["café", "🐼", "非公開"]),
            fixture(25, "Other", created: 1, modified: 1, accessed: nil, tags: ["other"])
        ]
        let value = try harness(notes: notes)
        run(#"""
        const w=new Workspace();w.setAllSort('name',false,false);
        w.tagFilter=' CAFE\u0301, café, 🐼, 🐼, !非公開, !非公開 ';
        check(w.tagFilterRequireAll===true,'AND default');
        check(titles(w,'all')==='Both','AND uses normalized unique tags and exclusion');
        w.tagFilterRequireAll=false;
        check(titles(w,'all')==='Accent only|Both|Emoji only','OR retains exclusions');
        w.name='Unicode filters';w.update();
        const saved=Workspace.find('Unicode filters');
        check(saved.tagFilter==='café,🐼,!非公開','stored filter is normalized and unique');
        check(saved.tagFilterRequireAll===false,'stored OR');
        check(titles(saved,'all')==='Accent only|Both|Emoji only','stored OR results');
        saved.tagFilterRequireAll=true;
        check(titles(saved,'all')==='Both','stored tokens also support AND');
        saved.tagFilter='タグ,!非公開';
        check(titles(saved,'all')==='Both','non-Latin inclusion');
        """#, in: value)
    }

    @Test func queryCreatedSortUsesExactOrderInEveryConfigurableFolder() throws {
        let value = try harness(notes: orderedFixtures())
        run(sortSetup + #"""
        configure('created',false,false);
        check(titles(w,'inbox')==='Inbox Bravo|Inbox Charlie|Inbox Alpha|Inbox Delta','Inbox created ascending');
        check(titles(w,'archive')==='Archive Bravo|Archive Charlie|Archive Alpha|Archive Delta','Archive created ascending');
        check(titles(w,'flagged')==='Inbox Bravo|Inbox Charlie|Archive Bravo|Archive Charlie','Flagged created ascending');
        check(titles(w,'all')==='Inbox Bravo|Inbox Charlie|Inbox Alpha|Inbox Delta|Archive Bravo|Archive Charlie|Archive Alpha|Archive Delta','All created ascending');
        configure('created',true,false);
        check(titles(w,'inbox')==='Inbox Delta|Inbox Alpha|Inbox Charlie|Inbox Bravo','Inbox created descending');
        check(titles(w,'archive')==='Archive Delta|Archive Alpha|Archive Charlie|Archive Bravo','Archive created descending');
        check(titles(w,'flagged')==='Archive Charlie|Archive Bravo|Inbox Charlie|Inbox Bravo','Flagged created descending');
        check(titles(w,'all')==='Archive Delta|Archive Alpha|Archive Charlie|Archive Bravo|Inbox Delta|Inbox Alpha|Inbox Charlie|Inbox Bravo','All created descending');
        """#, in: value)
    }

    @Test func queryModifiedSortUsesExactOrderInEveryConfigurableFolder() throws {
        let value = try harness(notes: orderedFixtures())
        run(sortSetup + #"""
        configure('modified',false,false);
        check(titles(w,'inbox')==='Inbox Alpha|Inbox Charlie|Inbox Bravo|Inbox Delta','Inbox modified ascending');
        check(titles(w,'archive')==='Archive Alpha|Archive Charlie|Archive Bravo|Archive Delta','Archive modified ascending');
        check(titles(w,'flagged')==='Inbox Charlie|Inbox Bravo|Archive Charlie|Archive Bravo','Flagged modified ascending');
        check(titles(w,'all')==='Inbox Alpha|Inbox Charlie|Inbox Bravo|Inbox Delta|Archive Alpha|Archive Charlie|Archive Bravo|Archive Delta','All modified ascending');
        configure('modified',true,false);
        check(titles(w,'inbox')==='Inbox Delta|Inbox Bravo|Inbox Charlie|Inbox Alpha','Inbox modified descending');
        check(titles(w,'archive')==='Archive Delta|Archive Bravo|Archive Charlie|Archive Alpha','Archive modified descending');
        check(titles(w,'flagged')==='Archive Bravo|Archive Charlie|Inbox Bravo|Inbox Charlie','Flagged modified descending');
        check(titles(w,'all')==='Archive Delta|Archive Bravo|Archive Charlie|Archive Alpha|Inbox Delta|Inbox Bravo|Inbox Charlie|Inbox Alpha','All modified descending');
        """#, in: value)
    }

    @Test func queryNameSortUsesExactOrderInEveryConfigurableFolder() throws {
        let value = try harness(notes: orderedFixtures())
        run(sortSetup + #"""
        configure('name',false,false);
        check(titles(w,'inbox')==='Inbox Alpha|Inbox Bravo|Inbox Charlie|Inbox Delta','Inbox name ascending');
        check(titles(w,'archive')==='Archive Alpha|Archive Bravo|Archive Charlie|Archive Delta','Archive name ascending');
        check(titles(w,'flagged')==='Archive Bravo|Archive Charlie|Inbox Bravo|Inbox Charlie','Flagged name ascending');
        check(titles(w,'all')==='Archive Alpha|Archive Bravo|Archive Charlie|Archive Delta|Inbox Alpha|Inbox Bravo|Inbox Charlie|Inbox Delta','All name ascending');
        configure('name',true,false);
        check(titles(w,'inbox')==='Inbox Delta|Inbox Charlie|Inbox Bravo|Inbox Alpha','Inbox name descending');
        check(titles(w,'archive')==='Archive Delta|Archive Charlie|Archive Bravo|Archive Alpha','Archive name descending');
        check(titles(w,'flagged')==='Inbox Charlie|Inbox Bravo|Archive Charlie|Archive Bravo','Flagged name descending');
        check(titles(w,'all')==='Inbox Delta|Inbox Charlie|Inbox Bravo|Inbox Alpha|Archive Delta|Archive Charlie|Archive Bravo|Archive Alpha','All name descending');
        """#, in: value)
    }

    @Test func queryAccessedSortKeepsUnknownDatesLastInBothDirections() throws {
        let value = try harness(notes: orderedFixtures())
        run(sortSetup + #"""
        configure('accessed',false,false);
        check(titles(w,'inbox')==='Inbox Charlie|Inbox Alpha|Inbox Bravo|Inbox Delta','Inbox access ascending');
        check(titles(w,'archive')==='Archive Charlie|Archive Alpha|Archive Bravo|Archive Delta','Archive access ascending');
        check(titles(w,'flagged')==='Inbox Charlie|Inbox Bravo|Archive Charlie|Archive Bravo','Flagged access ascending');
        const asc=w.query('all').map(d=>d.title);
        check(asc.slice(0,6).join('|')==='Inbox Charlie|Inbox Alpha|Inbox Bravo|Archive Charlie|Archive Alpha|Archive Bravo','All known access ascending');
        check(asc.slice(6).sort().join('|')==='Archive Delta|Inbox Delta','All unknown access last');
        configure('accessed',true,false);
        check(titles(w,'inbox')==='Inbox Bravo|Inbox Alpha|Inbox Charlie|Inbox Delta','Inbox access descending');
        check(titles(w,'archive')==='Archive Bravo|Archive Alpha|Archive Charlie|Archive Delta','Archive access descending');
        check(titles(w,'flagged')==='Archive Bravo|Archive Charlie|Inbox Bravo|Inbox Charlie','Flagged access descending');
        const desc=w.query('all').map(d=>d.title);
        check(desc.slice(0,6).join('|')==='Archive Bravo|Archive Alpha|Archive Charlie|Inbox Bravo|Inbox Alpha|Inbox Charlie','All known access descending');
        check(desc.slice(6).sort().join('|')==='Archive Delta|Inbox Delta','Unknown dates stay last descending');
        """#, in: value)
    }

    @Test func queryFlaggedFirstPrecedesNameSortWithoutChangingFlaggedFolder() throws {
        let value = try harness(notes: orderedFixtures())
        run(sortSetup + #"""
        configure('name',false,true);
        check(titles(w,'inbox')==='Inbox Bravo|Inbox Charlie|Inbox Alpha|Inbox Delta','Inbox flagged first');
        check(titles(w,'archive')==='Archive Bravo|Archive Charlie|Archive Alpha|Archive Delta','Archive flagged first');
        check(titles(w,'all')==='Archive Bravo|Archive Charlie|Inbox Bravo|Inbox Charlie|Archive Alpha|Archive Delta|Inbox Alpha|Inbox Delta','All flagged first');
        check(titles(w,'flagged')==='Archive Bravo|Archive Charlie|Inbox Bravo|Inbox Charlie','Flagged folder sorts its members');
        configure('name',true,true);
        check(titles(w,'inbox')==='Inbox Charlie|Inbox Bravo|Inbox Delta|Inbox Alpha','Inbox flagged first descending');
        check(titles(w,'archive')==='Archive Charlie|Archive Bravo|Archive Delta|Archive Alpha','Archive flagged first descending');
        check(titles(w,'all')==='Inbox Charlie|Inbox Bravo|Archive Charlie|Archive Bravo|Inbox Delta|Inbox Alpha|Archive Delta|Archive Alpha','All flagged first descending');
        """#, in: value)
    }

    @Test func queryTrashUsesDefaultModifiedOrderAndStaysOutsideOtherFolders() throws {
        let value = try harness(notes: orderedFixtures())
        run(#"""
        const w=new Workspace();w.tagFilter='order-fixture';
        check(titles(w,'trash')==='Trash Delta|Trash Bravo|Trash Charlie|Trash Alpha','Trash default modified descending');
        check(w.query('all').every(d=>!d.isTrashed),'All excludes Trash');
        check(w.query('flagged').every(d=>!d.isTrashed),'Flagged excludes flagged Trash');
        """#, in: value)
    }

    @Test func queryAccessFiltersExcludeUnknownDatesWithoutRecordingAnAccess() throws {
        let fixtures = orderedFixtures()
        let value = try harness(notes: fixtures)
        run(sortSetup + #"""
        configure('accessed',false,false);
        w.startDate.type='absolute';w.startDate.field='accessed';w.startDate.date=new Date('2020-01-01T00:00:00Z');
        w.endDate.type='absolute';w.endDate.field='accessed';w.endDate.date=new Date('2030-01-01T00:00:00Z');
        check(titles(w,'inbox')==='Inbox Charlie|Inbox Alpha|Inbox Bravo','Unknown Inbox access excluded');
        check(titles(w,'archive')==='Archive Charlie|Archive Alpha|Archive Bravo','Unknown Archive access excluded');
        check(titles(w,'all')==='Inbox Charlie|Inbox Alpha|Inbox Bravo|Archive Charlie|Archive Alpha|Archive Bravo','Known access dates only');
        check(w.query('trash').map(d=>d.title).sort().join('|')==='Trash Alpha|Trash Bravo|Trash Charlie','Unknown Trash access excluded');
        w.startDate.type='none';
        check(w.query('all').length===6,'End access filter alone excludes unknown dates');
        w.endDate.type='none';
        check(w.query('all').length===8,'No access filter includes unknown dates');
        """#, in: value)
        let stored = value.library.notes.filter { $0.tags.contains("order-fixture") }
        for expected in fixtures {
            #expect(stored.first { $0.id == expected.id } == expected)
        }
    }

    @Test func queryFiltersAndFolderSortsSurviveSaveAndBackupRestoration() throws {
        let value = try harness(notes: orderedFixtures())
        let script = #"""
        const w=Workspace.find('Restored filters');
        check(w instanceof Workspace,'Typed restored Workspace');
        check(w.startDate instanceof QueryDate && w.startDate.date instanceof Date,'Typed restored query date');
        check(w.tagFilter==='order-fixture,!absent','Restored normalized tags');
        check(w.tagFilterRequireAll===false,'Restored OR');
        check(w.inboxIncludesFlagged===false && w.archiveIncludesFlagged===true,'Restored folder flag settings');
        check(w.flaggedStatus==='any','Restored global status');
        check(titles(w,'inbox')==='Inbox Alpha','Restored Inbox filters and sort');
        check(titles(w,'archive')==='Archive Bravo|Archive Charlie|Archive Alpha','Restored Archive flagged first');
        check(titles(w,'flagged')==='Archive Charlie|Archive Bravo|Inbox Charlie|Inbox Bravo','Restored Flagged created descending');
        check(titles(w,'all')==='Inbox Charlie|Inbox Alpha|Inbox Bravo|Archive Charlie|Archive Alpha|Archive Bravo','Restored All accessed ascending');
        check(w.query('trash').map(d=>d.title).sort().join('|')==='Trash Alpha|Trash Bravo|Trash Charlie','Restored Trash access filter');
        """#
        run(#"""
        const saved=new Workspace();saved.name='Restored filters';
        saved.tagFilter=' ORDER-FIXTURE,order-fixture,!absent,!absent';saved.tagFilterRequireAll=false;
        saved.inboxIncludesFlagged=false;saved.archiveIncludesFlagged=true;saved.flaggedStatus='any';
        saved.setInboxSort('modified',false,false);saved.setArchiveSort('name',false,true);
        saved.setFlaggedSort('created',true);saved.setAllSort('accessed',false,false);
        saved.startDate.type='absolute';saved.startDate.field='accessed';saved.startDate.date=new Date('2020-01-01T00:00:00Z');
        saved.update();
        """# + script, in: value)
        let backup = try value.library.backupData()
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(backup)
        let receiver = try harness(library: restored)
        run(script, in: receiver)
        #expect(restored.workspaces == value.library.workspaces)
        #expect(restored.notes.count == value.library.notes.count)
    }

    @Test func invalidQueryDatesSortsAndFoldersDoNotReplaceTheStoredWorkspace() throws {
        let value = try harness(notes: orderedFixtures())
        run(#"""
        const initial=new Workspace();initial.name='Stable filters';initial.tagFilter='order-fixture';
        initial.setInboxSort('name',false,false);initial.update();
        const baseline=titles(initial,'inbox');
        const invalid=[
            w=>w.loadFolder='missing',
            w=>w.setInboxSort('missing',false,false),
            w=>w.setArchiveSort('missing',true,true),
            w=>w.setFlaggedSort('missing',false),
            w=>w.setAllSort('missing',true,false),
            w=>{w.startDate.type='absolute';w.startDate.date=new Date('invalid');},
            w=>{w.endDate.type='absolute';w.endDate.date='not a date';},
            w=>w.startDate.field='missing',
            w=>w.endDate.type='missing'
        ];
        for(let i=0;i<invalid.length;i++){
            const w=Workspace.find('Stable filters');invalid[i](w);w.name='Invalid change';
            let queryFailed=false,saveFailed=false;
            try{w.query('inbox');}catch(error){queryFailed=error instanceof Error;}
            try{w.update();}catch(error){saveFailed=error instanceof Error;}
            check(queryFailed && saveFailed,'Invalid configuration rejected '+i);
            check(Workspace.find('Invalid change')===undefined,'No partial save '+i);
            check(titles(Workspace.find('Stable filters'),'inbox')===baseline,'Stored results unchanged '+i);
        }
        for(const folder of ['missing','Inbox','']){
            let failed=false;try{initial.query(folder);}catch(error){failed=error instanceof Error;}
            check(failed,'Invalid query folder '+folder);
        }
        check(Workspace.getAll().length===1,'No invalid Workspace persisted');
        """#, in: value)
        #expect(value.library.workspaces.map(\.name) == ["Stable filters"])
    }
}
