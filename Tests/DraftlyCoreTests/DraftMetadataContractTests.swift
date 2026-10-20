import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class DraftMetadataHost: ActionHost {
    var onClipboard: ((String) throws -> Void)?
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        switch operation {
        case "clipboard": try onClipboard?(values["text"] as? String ?? ""); return true
        case "actionNotification": return true
        default: throw DraftlyError.message("Unexpected metadata test operation: " + operation)
        }
    }
}

@MainActor private struct DraftMetadataFixture {
    let library: LibraryStore
    let editor: EditorSession
    let host: DraftMetadataHost
    let runner: ActionRunner
    init() throws {
        library = try LibraryStore(inMemory: true, seed: false)
        editor = EditorSession()
        host = DraftMetadataHost()
        let source = Note(content: "Metadata source", createdAt: Date(timeIntervalSince1970: 1_000), modifiedAt: Date(timeIntervalSince1970: 2_000))
        try library.saveNote(source, preserveRevision: false, preserveDates: true)
        editor.load(source)
        runner = ActionRunner(library: library, editor: editor, host: host)
    }
    func action(_ script: String) -> DraftAction {
        ScriptTestAction.make(script, name: "Draft metadata contract")
    }
    func run(_ script: String) -> Bool { runner.run(action(script)) }
}

@Suite("Draft metadata member contracts") @MainActor
struct DraftMetadataContractTests {
    @Test func draftConstructorCreatesIndependentUnsavedValues() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const a=new Draft(),b=new Draft();
        check(a instanceof Draft && b instanceof Draft && a!==b,'independent objects');
        check(a.uuid!==b.uuid && a.content==='' && b.content==='','new identities and empty text');
        check(Array.isArray(a.tags) && a.tags.length===0,'empty tags');
        a.content='Unsaved constructor 🐼';a.addTag('local');
        check(b.content==='' && b.tags.length===0,'independent values');
        check(Draft.queryByTitle('Unsaved constructor 🐼').length===0,'no implicit storage');
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.notes.count == 1)
    }

    @Test func draftCreateReturnsIndependentUnsavedDrafts() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const a=Draft.create(),b=Draft.create();
        check(a instanceof Draft && b instanceof Draft && a!==b && a.uuid!==b.uuid,'fresh factory values');
        check(a.content==='' && a.folder==='inbox' && !a.isFlagged,'factory defaults');
        a.content='Unsaved factory café';check(Draft.queryByTitle(a.title).length===0,'not saved');
        a.update();check(Draft.find(a.uuid)===a,'saved identity');
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.notes.count == 2)
    }

    @Test func draftContentPreservesExactUnicodeWithoutImplicitSaving() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const stored=draft.content,text='🐼 cafe\u0301\r\n日本語\n';
        draft.content=text;check(draft.content===text,'exact string');
        check(editor.getText()===stored,'pending draft content is local');
        draft.content='';check(draft.content==='','empty content');
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.notes.first?.content == "Metadata source")
        #expect(f.editor.content == "Metadata source")
    }

    @Test func draftTitleReturnsTheReadOnlyFirstLineAcrossLineEndings() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const d=Draft.create();check(d.title==='','empty title');
        for(const separator of ['\n','\r\n','\r','\u2028','\u2029']){
          d.content='🐼 Title'+separator+'Body';check(d.title==='🐼 Title','first logical line');
        }
        d.content='\nBody';check(d.title==='','initial empty line');
        d.content='# Heading\nBody';check(d.title==='# Heading','raw heading');
        const value=d.title;try{d.title='Replacement';}catch(e){}
        check(d.title===value && d.content==='# Heading\nBody','read-only title');
        """#), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftDisplayTitleRemovesMarkdownHeadersAndIsReadOnly() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const d=Draft.create();check(d.displayTitle==='Untitled','empty display title');
        for(const pair of [['# Heading\nBody','Heading'],['### 🐼 café\nBody','🐼 café'],['Plain title\nBody','Plain title']]){
          d.content=pair[0];check(d.displayTitle===pair[1],'display title');
          const original=d.content;try{d.displayTitle='Replacement';}catch(e){}
          check(d.displayTitle===pair[1] && d.content===original,'read-only display title');
        }
        """#), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftUUIDIsUniqueStableAndReadOnly() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const d=Draft.create(),other=Draft.create(),id=d.uuid;
        check(typeof id==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id),'UUID string');
        check(id!==other.uuid,'unique identity');d.content='Stable identity';d.update();
        check(d.uuid===id && Draft.find(id)===d,'stable after update');
        try{d.uuid=other.uuid;}catch(e){}
        check(d.uuid===id,'read-only identity');
        """#), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftPermalinkUsesStableDraftlyIdentityAndIsReadOnly() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const d=Draft.create(),link='draftly://open?uuid='+d.uuid;
        check(d.permalink===link,'identity link');d.content='Link';d.update();
        check(d.permalink===link,'stable after save');try{d.permalink='other://open';}catch(e){}
        check(d.permalink===link,'read-only link');
        """#), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftToJSONReturnsAStandardSerializableObject() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const d=Draft.create();d.content='🐼 "quoted", café\r\nBody';d.addTag('unicode');
        d.flagType=4;d.folder='archive';d.createdLatitude=-12.5;d.createdLongitude=45.25;
        const value=d.toJSON(),roundTrip=JSON.parse(JSON.stringify(d));
        check(value && typeof value==='object' && !(value instanceof Draft),'plain object');
        check(value.uuid===d.uuid && value.content===d.content && value.tags[0]==='unicode','identity and content');
        check(value.isArchived===true && value.isTrashed===false && value.isFlagged===true && value.flagType===4,'state');
        check(value.createdAt instanceof Date && value.modifiedAt instanceof Date,'typed dates in object');
        check(roundTrip.content===d.content && roundTrip.createdAt===d.createdAt.toISOString(),'JSON serialization');
        check(roundTrip.syntax.name==='Markdown' && roundTrip.createdLatitude===-12.5 && roundTrip.createdLongitude===45.25,'syntax and coordinates');
        check(!Object.keys(value).some(key=>key.startsWith('_')),'no internal cache fields');
        """#), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftCreatedAtIsATypedWritableDatePreservedByStorage() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const d=Draft.create();check(d.createdAt instanceof Date && Math.abs(Date.now()-d.createdAt.getTime())<10000,'new creation timestamp');
        draft.createdAt=new Date('2001-02-03T04:05:06.125Z');check(draft.createdAt instanceof Date,'typed assignment');
        check(draft.update()===undefined,'save date');
        """#), Comment(rawValue: f.runner.message ?? ""))
        let saved = try #require(f.library.notes.first { $0.id == f.editor.noteID })
        #expect(APIValues.date(saved.createdAt) == "2001-02-03T04:05:06.125Z")
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(f.library.backupData())
        #expect(restored.notes.first { $0.id == saved.id }?.createdAt == saved.createdAt)
        #expect(f.run("check(draft.createdAt instanceof Date && draft.createdAt.toISOString()==='2001-02-03T04:05:06.125Z','restored script date');"), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftModifiedAtPreservesExplicitDatesAndUpdatesOnNormalSave() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const d=Draft.create();check(d.modifiedAt instanceof Date && Math.abs(Date.now()-d.modifiedAt.getTime())<10000,'new modified timestamp');
        draft.modifiedAt=new Date('2002-03-04T05:06:07.250Z');draft.content='Imported date';draft.update();
        check(draft.modifiedAt.toISOString()==='2002-03-04T05:06:07.250Z','explicit imported date');
        """#), Comment(rawValue: f.runner.message ?? ""))
        let saved = try #require(f.library.notes.first { $0.id == f.editor.noteID })
        #expect(APIValues.date(saved.modifiedAt) == "2002-03-04T05:06:07.250Z")
        #expect(f.run("const previous=draft.modifiedAt.getTime();draft.content='Normal edit';draft.update();check(draft.modifiedAt instanceof Date && draft.modifiedAt.getTime()>previous,'automatic modified date');"), Comment(rawValue: f.runner.message ?? ""))
        #expect(try #require(f.library.notes.first { $0.id == saved.id }).modifiedAt > saved.modifiedAt)
    }

    private func checkCoordinate(_ key: String, value: Double) throws {
        let f = try DraftMetadataFixture()
        #expect(f.run("const d=Draft.create();check(d.\(key)===0,'unavailable location');draft.\(key)=\(value);check(draft.\(key)===\(value),'numeric value');draft.update();"), Comment(rawValue: f.runner.message ?? ""))
        let saved = try #require(f.library.notes.first { $0.id == f.editor.noteID })
        #expect(Double(saved.scriptMetadata?[key] ?? "") == value)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(f.library.backupData())
        #expect(restored.notes.first { $0.id == saved.id }?.scriptMetadata?[key] == saved.scriptMetadata?[key])
        #expect(f.run("check(draft.\(key)===\(value),'reopened coordinate');"), Comment(rawValue: f.runner.message ?? ""))
    }
    @Test func draftCreatedLatitudeDefaultsToZeroAndPersistsSignedFractions() throws { try checkCoordinate("createdLatitude", value: -34.60375) }
    @Test func draftCreatedLongitudeDefaultsToZeroAndPersistsSignedFractions() throws { try checkCoordinate("createdLongitude", value: -58.38160) }
    @Test func draftModifiedLatitudeDefaultsToZeroAndPersistsSignedFractions() throws { try checkCoordinate("modifiedLatitude", value: 48.85825) }
    @Test func draftModifiedLongitudeDefaultsToZeroAndPersistsSignedFractions() throws { try checkCoordinate("modifiedLongitude", value: 2.29450) }

    @Test func draftFolderMovesBetweenSupportedLocationsAndRejectsUnknownValues() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const d=Draft.create();d.content='Folder contract';check(d.folder==='inbox','default folder');
        for(const folder of ['archive','trash','inbox']){
          d.folder=folder;d.update();check(d.folder===folder,'selected folder');
          check(Draft.query('Folder contract',folder,[],[],'name').some(value=>value===d),'stored folder');
        }
        let failed=false;try{d.folder='all';}catch(e){failed=e instanceof RangeError;}
        check(failed && d.folder==='inbox','invalid folder preserves state');
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.notes.first { $0.content == "Folder contract" }?.isArchived == false)
        #expect(f.library.notes.first { $0.content == "Folder contract" }?.trashedAt == nil)
    }

    @Test func draftIsArchivedPersistsAndKeepsItsStateWhileTrashed() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        check(draft.isArchived===false,'inbox default');draft.isArchived=true;draft.update();
        check(draft.folder==='archive','archive flag');draft.isTrashed=true;draft.update();
        check(draft.isArchived===true && draft.folder==='trash','archive state retained');
        draft.isTrashed=false;draft.update();check(draft.folder==='archive','restore archive');
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.notes.first?.isArchived == true)
        #expect(f.library.notes.first?.trashedAt == nil)
    }

    @Test func draftIsTrashedPersistsAndRestoresWithoutLosingContentOrFlag() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        check(draft.isTrashed===false,'not trashed');const text=draft.content;draft.flagType=3;
        draft.isTrashed=true;draft.update();check(draft.folder==='trash' && draft.isFlagged,'trashed flag');
        check(Draft.query('', 'inbox',[],[],'name').every(d=>d.uuid!==draft.uuid),'hidden from inbox');
        draft.isTrashed=false;draft.update();check(draft.folder==='inbox' && draft.content===text && draft.flagType===3,'restore keeps values');
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.notes.first?.trashedAt == nil)
        #expect(f.library.notes.first?.content == "Metadata source")
        #expect(f.library.notes.first?.flag == 3)
    }

    @Test func draftIsFlaggedAssignsPreservesAndClearsFlagType() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const d=Draft.create();check(d.isFlagged===false && d.flagType===0,'unflagged default');
        d.isFlagged=true;check(d.isFlagged===true && d.flagType===1,'default flag type');
        d.flagType=5;d.isFlagged=true;check(d.flagType===5,'existing flag color');
        d.isFlagged=false;check(d.flagType===0 && !d.isFlagged,'cleared flag');
        draft.isFlagged=true;draft.update();
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.notes.first?.flag == 1)
    }

    @Test func draftFlagTypeSupportsEveryDocumentedIndexAndSetsFlaggedStatus() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run("check(draft.flagType===0,'default type');"), Comment(rawValue: f.runner.message ?? ""))
        for value in 0...6 {
            #expect(f.run("draft.flagType=\(value);check(draft.isFlagged===(\(value)>0),'derived flag status');draft.update();check(draft.flagType===\(value),'current type');"), Comment(rawValue: f.runner.message ?? ""))
            let saved = try #require(f.library.notes.first { $0.id == f.editor.noteID })
            #expect(saved.flag == value)
            let restored = try LibraryStore(inMemory: true, seed: false)
            try restored.restore(f.library.backupData())
            let reopened = try #require(restored.notes.first { $0.id == saved.id })
            #expect(reopened.flag == value)
            let editor = EditorSession(), host = DraftMetadataHost()
            editor.load(reopened)
            let runner = ActionRunner(library: restored, editor: editor, host: host)
            #expect(runner.run(f.action("check(draft.flagType===\(value) && draft.isFlagged===(\(value)>0),'reopened flag state');")), Comment(rawValue: runner.message ?? ""))
        }
        #expect(f.library.notes.first?.flag == 6)
    }

    @Test func draftGrayFlagExtensionRemainsCompatibleWithExistingLibraries() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run("draft.flagType=7;draft.update();check(draft.isFlagged && draft.flagType===7,'Draftly gray extension');"), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.notes.first?.flag == 7)
    }

    @Test func draftUpdateReturnsVoidAndSynchronizesStoredEditorAndCachedValues() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const cached=Draft.find(draft.uuid),id=draft.uuid;
        check(cached===draft && editor.draft===draft,'initial shared identity');
        draft.content='Updated 🐼\nBody';draft.addTag('persisted');draft.flagType=2;
        check(draft.update()===undefined,'void result');
        check(editor.getText()===draft.content && cached.content===draft.content,'immediate editor content');
        check(Draft.find(id)===cached && Draft.queryByTitle('Updated 🐼')[0]===cached,'identity after update');
        check(draft.modifiedAt instanceof Date && draft.hasTag('persisted'),'updated metadata');
        """#), Comment(rawValue: f.runner.message ?? ""))
        let saved = try #require(f.library.notes.first { $0.id == f.editor.noteID })
        #expect(saved.content == "Updated 🐼\nBody" && saved.tags == ["persisted"] && saved.flag == 2)
    }

    @Test func draftUpdateStorageFailureThrowsAndPreservesStoredEditorAndVersions() throws {
        let f = try DraftMetadataFixture()
        let library = f.library
        var armedSnapshot: [Note] = [], armedVersions: [Revision] = []
        f.host.onClipboard = { _ in
            armedSnapshot = library.notes; armedVersions = library.revisions
            library.beforeBatchCommit = { throw DraftlyError.message("Metadata storage failure") }
        }
        defer { library.beforeBatchCommit = nil }
        let original = f.editor.content
        let action = f.action("app.setClipboard('arm');draft.content='Must not persist';draft.addTag('unsaved');draft.update();throw new Error('later statement ran');")
        #expect(f.runner.runResult(action) == .failure("Error: Metadata storage failure"))
        #expect(library.notes == armedSnapshot)
        #expect(library.revisions == armedVersions)
        #expect(f.editor.content == original)
    }

    @Test(arguments: [false, true])
    func draftFindReturnsMissingValuesAndReusesSavedIdentity(worker: Bool) async throws {
        let f = try DraftMetadataFixture()
        let action = f.action(#"""
        check(Draft.find('00000000-0000-0000-0000-000000000000')===undefined,'missing identity');
        for(const name of ['__proto__','constructor','toString','hasOwnProperty','prototype','']) {
            check(Draft.find(name)===undefined,'invalid identity '+name);
        }
        check(Draft.find(draft.uuid)===draft,'valid identity remains cached');
        const d=Draft.create();d.content='Find identity';d.update();
        check(Draft.find(d.uuid)===d && Draft.find(d.uuid)===Draft.find(d.uuid),'cached saved identity');
        d.content='Pending local edit';check(Draft.find(d.uuid).content==='Pending local edit','pending values survive lookup');
        """#)
        let succeeded: Bool
        if worker { succeeded = await f.runner.runAsync(action).result.succeeded }
        else { succeeded = f.runner.run(action) }
        #expect(succeeded, Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftFindAcceptsBothCasesOfAValidStoredUUID() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const id=draft.uuid;
        check(Draft.find(id.toLowerCase())===draft && Draft.find(id.toUpperCase())===draft,'canonical UUID identity');
        """#), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftQueriesKeepPendingCachedValuesThroughUpdateAndEditorLoad() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        const d=Draft.create();d.content='Cache contract';d.addTag('cache');d.update();
        const id=d.uuid;d.content='Pending cached 🐼';
        const result=Draft.query('Cache contract','inbox',['cache'],[],'name');
        check(result.length===1 && result[0]===d && result[0].content==='Pending cached 🐼','query preserves pending cache');
        d.update();editor.load(d);check(editor.draft===d && Draft.find(id)===d,'load keeps identity');
        editor.setText('Immediate editor change');
        check(d.content==='Immediate editor change' && Draft.queryByTitle('Immediate editor change')[0]===d,'editor refreshes cache');
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.notes.first { $0.id == f.editor.noteID }?.content == "Immediate editor change")
    }

    @Test func draftQueryDefaultsOrderingFiltersAndErrorsHaveSpecificCoverage() throws {
        let f = try DraftMetadataFixture()
        _ = try f.library.createNote(content: "Zulu", tags: ["include"])
        var alpha = try f.library.createNote(content: "Alpha", tags: ["include"])
        alpha.flag = 2; try f.library.saveNote(alpha)
        _ = try f.library.createNote(content: "Excluded", tags: ["include", "omit"])
        #expect(f.run(#"""
        let values=Draft.query('','inbox',['include'],['omit'],'name');
        check(values.map(d=>d.title).join(',')==='Alpha,Zulu','ascending default and omitted tag');
        check(Draft.query('','inbox',['include'],['omit'],'name',true).map(d=>d.title).join(',')==='Zulu,Alpha','descending');
        check(Draft.query('','inbox',['include'],['omit'],'name',true,true).map(d=>d.title).join(',')==='Alpha,Zulu','flagged first');
        for(const args of [['','missing',[],[],'name'],['','all',[],[],'missing'],['/[/','all',[],[],'name']]){
          let failed=false;try{Draft.query(...args);}catch(e){failed=true;}check(failed,'invalid query rejected');
        }
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.editor.content == "Metadata source")
    }

    @Test func draftQuerySelectsEveryDocumentedFolderAndExcludesTrashFromAll() throws {
        let f = try DraftMetadataFixture()
        let inbox = Note(content: "Folder matrix Inbox", tags: ["folder-matrix"])
        let flaggedInbox = Note(content: "Folder matrix Flagged Inbox", tags: ["folder-matrix"], flag: 2)
        let archive = Note(content: "Folder matrix Archive", tags: ["folder-matrix"], isArchived: true)
        let flaggedArchive = Note(content: "Folder matrix Flagged Archive", tags: ["folder-matrix"], flag: 4, isArchived: true)
        let trash = Note(content: "Folder matrix Trash", tags: ["folder-matrix"], trashedAt: Date())
        let archivedTrash = Note(content: "Folder matrix Archived Trash", tags: ["folder-matrix"], flag: 5, isArchived: true, trashedAt: Date())
        try f.library.saveNotes([inbox, flaggedInbox, archive, flaggedArchive, trash, archivedTrash])
        let cases: [(String, [Note])] = [
            ("inbox", [inbox, flaggedInbox]), ("archive", [archive, flaggedArchive]),
            ("trash", [trash, archivedTrash]), ("flagged", [flaggedInbox, flaggedArchive]),
            ("all", [inbox, flaggedInbox, archive, flaggedArchive])
        ]
        for (folder, notes) in cases {
            let ids = notes.map { $0.id.uuidString }.sorted().joined(separator: ",")
            #expect(f.run("const result=Draft.query('','\(folder)',['folder-matrix'],[],'name');check(result.every(d=>d instanceof Draft),'Draft array');check(result.map(d=>d.uuid).sort().join(',')==='\(ids)','folder \(folder)');check(Draft.query('No folder matrix match','\(folder)',['folder-matrix'],[],'name').length===0,'empty folder query result');"), Comment(rawValue: f.runner.message ?? ""))
        }
    }

    @Test func draftQueryRequiresEveryIncludedTagAndOmitsAnyExcludedTag() throws {
        let f = try DraftMetadataFixture()
        let both = Note(content: "Tag matrix Both", tags: ["red", "blue"])
        let redOnly = Note(content: "Tag matrix Red only", tags: ["red"])
        let blueOnly = Note(content: "Tag matrix Blue only", tags: ["blue"])
        let blocked = Note(content: "Tag matrix Blocked", tags: ["red", "blue", "blocked"])
        let skipped = Note(content: "Tag matrix Skipped", tags: ["red", "blue", "skip"])
        let other = Note(content: "Tag matrix Other", tags: ["redfish", "bluebird"])
        try f.library.saveNotes([both, redOnly, blueOnly, blocked, skipped, other])
        let allIncluded = [both, blocked, skipped].map { $0.id.uuidString }.sorted().joined(separator: ",")
        let afterExclusions = [both, redOnly, blueOnly, other].map { $0.id.uuidString }.sorted().joined(separator: ",")
        #expect(f.run("function ids(tags,omit){return Draft.query('Tag matrix','all',tags,omit,'name').map(d=>d.uuid).sort().join(',');}check(ids(['red','blue'],[])==='\(allIncluded)','AND includes');check(ids(['red','blue'],['blocked','skip'])==='\(both.id.uuidString)','OR excludes');check(ids([],['blocked','skip'])==='\(afterExclusions)','exclude without include');check(ids(['red','red','blue'],[])==='\(allIncluded)','repeated included tag');check(ids(['red'],['red'])==='','excluded tag takes precedence');check(Draft.query('Tag matrix','all',[],[],'name').length===6,'empty tag lists do not filter');"), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftQueryTagNamesNormalizeUnicodeAndKeepExactNameBoundaries() throws {
        let f = try DraftMetadataFixture()
        let exact = Note(content: "Tag boundary Exact", tags: ["café", "work/project"])
        let longer = Note(content: "Tag boundary Longer", tags: ["caféteria", "work/projectile"])
        let plain = Note(content: "Tag boundary Plain", tags: ["cafe", "workshop/project"])
        try f.library.saveNotes([exact, longer, plain])
        #expect(f.run("const result=Draft.query('Tag boundary','all',[' CAFE\\u0301 ','WORK/PROJECT'],[],'name');check(result.length===1 && result[0].uuid==='\(exact.id.uuidString)','Unicode normalized exact tags');check(Draft.query('Tag boundary','all',[],[' CAFÉ '],'name').map(d=>d.uuid).sort().join(',')==='\([longer, plain].map { $0.id.uuidString }.sorted().joined(separator: ","))','normalized excluded tag');check(Draft.query('Tag boundary','all',['work/project'],[],'name').length===1,'similar tag prefix does not match');"), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftQuerySortsCreatedAndModifiedDatesInBothDirections() throws {
        let f = try DraftMetadataFixture()
        let alpha = Note(content: "Date order Alpha", tags: ["date-order"], createdAt: Date(timeIntervalSince1970: 100), modifiedAt: Date(timeIntervalSince1970: 400))
        let beta = Note(content: "Date order Beta", tags: ["date-order"], createdAt: Date(timeIntervalSince1970: 300), modifiedAt: Date(timeIntervalSince1970: 200))
        let gamma = Note(content: "Date order Gamma", tags: ["date-order"], createdAt: Date(timeIntervalSince1970: 200), modifiedAt: Date(timeIntervalSince1970: 300))
        try f.library.saveNotes([alpha, beta, gamma], preserveRevision: false, preserveDates: true)
        for (sort, ascending) in [("created", [alpha, gamma, beta]), ("modified", [beta, gamma, alpha])] {
            let ids = ascending.map { $0.id.uuidString }.joined(separator: ",")
            let reversed = ascending.reversed().map { $0.id.uuidString }.joined(separator: ",")
            #expect(f.run("function ids(descending){return Draft.query('','all',['date-order'],[],'\(sort)',descending).map(d=>d.uuid).join(',');}check(Draft.query('','all',['date-order'],[],'\(sort)').map(d=>d.uuid).join(',')==='\(ids)','\(sort) ascending default');check(ids(false)==='\(ids)' && ids(true)==='\(reversed)','\(sort) direction');"), Comment(rawValue: f.runner.message ?? ""))
        }
        for note in [alpha, beta, gamma] {
            let saved = try #require(f.library.notes.first { $0.id == note.id })
            #expect(saved.createdAt == note.createdAt && saved.modifiedAt == note.modifiedAt)
        }
    }

    @Test func draftQuerySortsUnknownAccessDatesLastAndUsesStableUUIDTies() throws {
        let f = try DraftMetadataFixture()
        let older = Note(content: "Access query Older", tags: ["access-query"], accessedAt: Date(timeIntervalSince1970: 100))
        let newer = Note(content: "Access query Newer", tags: ["access-query"], accessedAt: Date(timeIntervalSince1970: 200))
        let unknownA = Note(id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")), content: "Access query Unknown A", tags: ["access-query"])
        let unknownB = Note(id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")), content: "Access query Unknown B", tags: ["access-query"])
        try f.library.saveNotes([unknownB, newer, unknownA, older], preserveDates: true)
        let ascending = [older, newer, unknownA, unknownB].map { $0.id.uuidString }.joined(separator: ",")
        let descending = [newer, older, unknownA, unknownB].map { $0.id.uuidString }.joined(separator: ",")
        #expect(f.run("function ids(descending){return Draft.query('','all',['access-query'],[],'accessed',descending).map(d=>d.uuid).join(',');}check(ids(false)==='\(ascending)','known first ascending and unknown UUID tie');check(ids(true)==='\(descending)','known first descending and unknown UUID tie');check(Draft.query('','all',['access-query'],[],'accessed').map(d=>d.uuid).join(',')==='\(ascending)','access ascending default');"), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.notes.first { $0.id == older.id }?.accessedAt == older.accessedAt)
        #expect(f.library.notes.first { $0.id == newer.id }?.accessedAt == newer.accessedAt)
        #expect(f.library.notes.first { $0.id == unknownA.id }?.accessedAt == nil)
        #expect(f.library.notes.first { $0.id == unknownB.id }?.accessedAt == nil)
    }

    @Test func draftQueryFlaggedFirstKeepsTheSelectedDateAndNameOrder() throws {
        let f = try DraftMetadataFixture()
        let alpha = Note(content: "Flag order Alpha", tags: ["flag-order"], createdAt: Date(timeIntervalSince1970: 100), modifiedAt: Date(timeIntervalSince1970: 400), accessedAt: Date(timeIntervalSince1970: 300))
        let beta = Note(content: "Flag order Beta", tags: ["flag-order"], flag: 2, createdAt: Date(timeIntervalSince1970: 300), modifiedAt: Date(timeIntervalSince1970: 200), accessedAt: Date(timeIntervalSince1970: 100))
        let gamma = Note(content: "Flag order Gamma", tags: ["flag-order"], flag: 5, createdAt: Date(timeIntervalSince1970: 200), modifiedAt: Date(timeIntervalSince1970: 300), accessedAt: Date(timeIntervalSince1970: 200))
        let unknown = Note(content: "Flag order Unknown", tags: ["flag-order"], createdAt: Date(timeIntervalSince1970: 400), modifiedAt: Date(timeIntervalSince1970: 100))
        try f.library.saveNotes([alpha, beta, gamma, unknown], preserveDates: true)
        let cases: [(String, Bool, [Note])] = [
            ("name", false, [beta, gamma, alpha, unknown]), ("name", true, [gamma, beta, unknown, alpha]),
            ("created", false, [gamma, beta, alpha, unknown]), ("created", true, [beta, gamma, unknown, alpha]),
            ("modified", false, [beta, gamma, unknown, alpha]), ("modified", true, [gamma, beta, alpha, unknown]),
            ("accessed", false, [beta, gamma, alpha, unknown]), ("accessed", true, [gamma, beta, alpha, unknown])
        ]
        for (sort, descending, expected) in cases {
            let ids = expected.map { $0.id.uuidString }.joined(separator: ",")
            #expect(f.run("check(Draft.query('','all',['flag-order'],[],'\(sort)',\(descending),true).map(d=>d.uuid).join(',')==='\(ids)','flagged first \(sort) \(descending)');"), Comment(rawValue: f.runner.message ?? ""))
        }
    }

    @Test func draftQueryStructuredSearchUsesTheSameDocumentedInputArguments() throws {
        let f = try DraftMetadataFixture()
        let first = Note(content: "Search red title\nA blue parachute and café", tags: ["search-query", "topic"], flag: 1)
        let second = Note(content: "Search green title\nRed kite", tags: ["search-query"])
        let third = Note(content: "Other title\nblue red", tags: ["search-query"], flag: 5)
        try f.library.saveNotes([first, second, third])
        let cases: [(String, [Note])] = [
            ("cafe", [first]), ("\"blue parachute\"", [first]), ("red AND blue", [first, third]),
            ("red -blue", [second]), ("missing OR café", [first]),
            ("title:green", [second]), ("tag:topic", [first]), ("flag:red", [first]),
            ("/Search red title/", [first]), ("No matching search content", [])
        ]
        for (query, expected) in cases {
            let encodedQuery = String(decoding: try JSONEncoder().encode(query), as: UTF8.self)
            let ids = expected.map { $0.id.uuidString }.sorted().joined(separator: ",")
            #expect(f.run("check(Draft.query(\(encodedQuery),'all',['search-query'],[],'name').map(d=>d.uuid).sort().join(',')==='\(ids)','structured search');"), Comment(rawValue: f.runner.message ?? ""))
        }
    }

    @Test func draftQueryDoesNotChangeStoredTextDatesAccessOrVersions() throws {
        let f = try DraftMetadataFixture()
        let known = Note(content: "Read query Known 🐼", tags: ["read-query"], createdAt: Date(timeIntervalSince1970: 100), modifiedAt: Date(timeIntervalSince1970: 200), accessedAt: Date(timeIntervalSince1970: 300))
        let unknown = Note(content: "Read query Unknown", tags: ["read-query"], createdAt: Date(timeIntervalSince1970: 400), modifiedAt: Date(timeIntervalSince1970: 500))
        try f.library.saveNotes([known, unknown], preserveDates: true)
        let before = f.library.notes.filter { $0.id == known.id || $0.id == unknown.id }
        let revisions = f.library.revisions.filter { $0.noteID == known.id || $0.noteID == unknown.id }
        #expect(f.run("for(const sort of ['name','created','modified','accessed'])for(const descending of [false,true]){const result=Draft.query('Read query','all',['read-query'],[],sort,descending);check(result.length===2,'read query results');}"), Comment(rawValue: f.runner.message ?? ""))
        let after = f.library.notes.filter { $0.id == known.id || $0.id == unknown.id }
        #expect(Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) }) == Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) }))
        #expect(f.library.revisions.filter { $0.noteID == known.id || $0.noteID == unknown.id } == revisions)
        #expect(f.editor.content == "Metadata source")
    }

    @Test func draftQueryByTitleMatchesOnlyTheFirstLineAndKeepsIdentity() throws {
        let f = try DraftMetadataFixture()
        let title = try f.library.createNote(content: "Project Café\nBody")
        _ = try f.library.createNote(content: "Unrelated title\nProject Café in body")
        let expectedIDs = f.library.notes.map { $0.id.uuidString }.sorted().joined(separator: ",")
        #expect(f.run("const matches=Draft.queryByTitle('cAFé');check(matches.length===1 && matches[0].uuid==='\(title.id.uuidString)','title-only case-insensitive match');check(matches[0]===Draft.find(matches[0].uuid),'shared identity');check(Draft.queryByTitle('absent title').length===0,'no matches');check(Draft.queryByTitle('').map(d=>d.uuid).sort().join(',')==='\(expectedIDs)','empty title matches each available first line');"), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftFlaggedOmitsUnflaggedAndTrashedDraftsAndFiltersNamedColors() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run("check(Draft.flagged().length===0 && Draft.flagged('red').length===0,'no eligible flags');"), Comment(rawValue: f.runner.message ?? ""))
        let red = Note(content: "Flag red", flag: 1), blue = Note(content: "Flag blue", flag: 5)
        let archived = Note(content: "Archived green", flag: 4, isArchived: true)
        let trashed = Note(content: "Trashed red", flag: 1, trashedAt: Date())
        try f.library.saveNotes([red, blue, archived, trashed])
        #expect(f.run("const all=Draft.flagged();check(all.length===3 && all.every(d=>d.isFlagged && !d.isTrashed),'default all flags');check(all.some(d=>d.uuid==='\(archived.id.uuidString)' && d.isArchived),'archived flagged draft included');const red=Draft.flagged('red');check(red.length===1 && red[0].uuid==='\(red.id.uuidString)','named type');check(red[0]===Draft.find(red[0].uuid),'shared identity');const green=Draft.flagged('green');check(green.length===1 && green[0].uuid==='\(archived.id.uuidString)','archived named color');check(Draft.flagged('purple').length===0,'no matching color');"), Comment(rawValue: f.runner.message ?? ""))
    }
}
