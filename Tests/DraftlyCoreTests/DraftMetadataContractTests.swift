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
        DraftAction(name: "Draft metadata contract", steps: [ActionStep("script", ["script": "function check(value,label){if(!value)throw new Error(label);}\n" + script])])
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
        #expect(f.run(#"""
        check(draft.flagType===0,'default type');
        for(let value=0;value<=6;value++){
          draft.flagType=value;check(draft.isFlagged===(value>0),'derived flag status');
          draft.update();check(draft.flagType===value,'stored type');
        }
        """#), Comment(rawValue: f.runner.message ?? ""))
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

    @Test func draftFindReturnsMissingValuesAndReusesSavedIdentity() throws {
        let f = try DraftMetadataFixture()
        #expect(f.run(#"""
        check(Draft.find('00000000-0000-0000-0000-000000000000')===undefined,'missing identity');
        const d=Draft.create();d.content='Find identity';d.update();
        check(Draft.find(d.uuid)===d && Draft.find(d.uuid)===Draft.find(d.uuid),'cached saved identity');
        d.content='Pending local edit';check(Draft.find(d.uuid).content==='Pending local edit','pending values survive lookup');
        """#), Comment(rawValue: f.runner.message ?? ""))
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

    @Test func draftQueryByTitleMatchesOnlyTheFirstLineAndKeepsIdentity() throws {
        let f = try DraftMetadataFixture()
        let title = try f.library.createNote(content: "Project Café\nBody")
        _ = try f.library.createNote(content: "Unrelated title\nProject Café in body")
        #expect(f.run("const matches=Draft.queryByTitle('cAFé');check(matches.length===1 && matches[0].uuid==='\(title.id.uuidString)','title-only case-insensitive match');check(matches[0]===Draft.find(matches[0].uuid),'shared identity');check(Draft.queryByTitle('absent title').length===0,'no matches');"), Comment(rawValue: f.runner.message ?? ""))
    }

    @Test func draftFlaggedOmitsUnflaggedAndTrashedDraftsAndFiltersNamedColors() throws {
        let f = try DraftMetadataFixture()
        let red = Note(content: "Flag red", flag: 1), blue = Note(content: "Flag blue", flag: 5)
        let trashed = Note(content: "Trashed red", flag: 1, trashedAt: Date())
        try f.library.saveNotes([red, blue, trashed])
        #expect(f.run("const all=Draft.flagged();check(all.length===2 && all.every(d=>d.isFlagged && !d.isTrashed),'default all flags');const red=Draft.flagged('red');check(red.length===1 && red[0].uuid==='\(red.id.uuidString)','named type');check(red[0]===Draft.find(red[0].uuid),'shared identity');check(Draft.flagged('green').length===0,'no matching color');"), Comment(rawValue: f.runner.message ?? ""))
    }
}
