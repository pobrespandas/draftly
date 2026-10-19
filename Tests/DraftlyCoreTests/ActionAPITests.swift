import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class APIHost: ActionHost {
    var calls: [(String, [String: Any])] = []
    var clipboard = ""
    var previewSuccess = true
    var callbackStatus = "success"
    var confirmation = true
    var templateFiles: [String: String] = [:]
    var selectedIndex: Int? = 0
    var onPerform: ((String) -> Void)?
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        calls.append((operation, values))
        onPerform?(operation)
        switch operation {
        case "selectPrompt": return selectedIndex.map { ["index": $0] }
        case "confirmAction": return confirmation
        case "actionNotification": return true
        case "fileAPI":
            let path = values["path"] as? String ?? ""
            if values["operation"] as? String == "listContents" { return templateFiles.keys.filter { $0.hasPrefix(path + "/") }.sorted() }
            if let text = templateFiles[path] { return text }
            throw DraftlyError.message("Missing template")
        case "clipboard": clipboard = values["text"] as? String ?? ""; return true
        case "getClipboard": return clipboard
        case "prompt":
            var fields: [String: Any] = [:]
            for field in values["fields"] as? [[String: Any]] ?? [] { if let key = field["key"] as? String { fields[key] = field["value"] } }
            return ["index": 0, "fields": fields]
        case "htmlPreview": return ["success": previewSuccess, "values": ["answer": ["value": 42]]]
        case "callbackURL": return ["status": callbackStatus, "parameters": ["result": "Returned + café"]]
        case "requireScript": return "function loadedHelper(value) { return value.toUpperCase(); }"
        case "shortcut": return "Shortcut output"
        case "appleScript": return ["value": 42]
        case "markdown": return MarkdownRenderer.render(values["text"] as? String ?? "")
        default: throw DraftlyError.message("Unexpected test operation: \(operation)")
        }
    }
}

@Suite("Action API contracts") @MainActor
struct ActionAPITests {
    private func setup(_ content: String = "# Source\nBody") throws -> (LibraryStore, EditorSession, APIHost, ActionRunner) {
        let library = try LibraryStore(inMemory: true, seed: false), editor = EditorSession(), host = APIHost()
        editor.load(try library.createNote(content: content))
        return (library, editor, host, ActionRunner(library: library, editor: editor, host: host))
    }
    private func action(_ script: String, async: Bool = false) -> DraftAction {
        DraftAction(name: "API contract", steps: [ActionStep("script", ["script": "function check(value,label) { if (!value) throw new Error(label); }\n" + script, "allowAsync": async ? "true" : "false"])])
    }

    @Test func draftAddTagNormalizesUnicodeAndAvoidsDuplicates() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const d=Draft.create();check(d.addTag(' CAFE\u0301 ')===undefined,'void');d.addTag('café');d.addTag('');d.addTag('  ');
        check(d.tags.join(',')==='café','normalized unique nonempty tags');
        d.addTag('work/project');check(d.tags.includes('work/project'),'hierarchical tag preserved');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftHasTagUsesNormalizedExactNames() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const d=Draft.create();check(d.hasTag('missing')===false,'empty tags');d.tags=['café','work/project'];
        check(d.hasTag(' CAFE\u0301 ')===true,'normalized match');check(d.hasTag('work')===false,'exact name');
        check(d.hasTag('work/project')===true && d.hasTag('')===false,'present and absent');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftRemoveTagRemovesOnlyNormalizedMatchesAndReturnsVoid() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const d=Draft.create();d.tags=['café','CAFE\u0301','other'];check(d.removeTag(' CAFÉ ')===undefined,'void');
        check(d.tags.join(',')==='other','remove all matching variants');d.removeTag('missing');check(d.tags.join(',')==='other','missing is no-op');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftTagsPersistNormalizedValuesWithoutImplicitSaving() throws {
        let (library, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const d=Draft.create();d.content='Tag contract';d.tags=[' Zebra ','CAFÉ','cafe\u0301',''];
        check(Draft.queryByTitle('Tag contract').length===0,'not saved implicitly');d.update();
        check(Draft.find(d.uuid).tags.join(',')==='café,zebra','normalized persisted values');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.content == "Tag contract" }?.tags == ["café", "zebra"])
    }

    @Test func editorSetSelectedRangeReturnsVoidAndRejectsInvalidUTF16Ranges() throws {
        let (_, editor, _, runner) = try setup("🐼 café")
        #expect(runner.run(action(#"""
        check(editor.setSelectedRange(0,2)===undefined,'void');check(editor.getSelectedText()==='🐼','UTF16');
        for(const r of [[-1,0],[0,-1],[8,0],[0,8],[0.5,1],[NaN,0]]){let failed=false;try{editor.setSelectedRange(...r);}catch(e){failed=e instanceof RangeError;}check(failed,'invalid range');check(editor.getSelectedRange().join(',')==='0,2','preserved range');}
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.selection == NSRange(location: 0, length: 2))
    }

    @Test func editorSetSelectedTextReturnsVoidAndUpdatesCachedDraftAndStorage() throws {
        let (library, editor, _, runner) = try setup("🐼 café")
        #expect(runner.run(action(#"""
        const cached=editor.draft;editor.setSelectedRange(0,2);check(editor.setSelectedText('🌿')===undefined,'void');
        check(editor.getText()==='🌿 café' && cached.content===editor.getText(),'cached content');
        check(editor.getSelectedRange().join(',')==='2,0','cursor after replacement');
        editor.setSelectedText('');check(editor.getText()==='🌿 café','empty insertion');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.id == editor.noteID }?.content == "🌿 café")
    }

    @Test func editorSetTextInRangeReturnsVoidAndRejectsInvalidRanges() throws {
        let (_, _, _, runner) = try setup("🐼 café")
        #expect(runner.run(action(#"""
        const cached=editor.draft;check(editor.setTextInRange(3,4,'té')===undefined,'void');
        check(editor.getText()==='🐼 té' && cached.content==='🐼 té','replacement');
        check(editor.getSelectedRange().join(',')==='5,0','replacement cursor');
        for(const r of [[-1,0],[0,99],[0.5,1]]){let failed=false;try{editor.setTextInRange(...r,'bad');}catch(e){failed=e instanceof RangeError;}check(failed,'invalid');check(editor.getText()==='🐼 té','unchanged after error');}
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorGetTextInRangeReturnsExactUTF16SubstringsWithoutChangingSelection() throws {
        let (_, _, _, runner) = try setup("🐼 café")
        #expect(runner.run(action(#"""
        editor.setSelectedRange(3,4);check(editor.getTextInRange(0,2)==='🐼','emoji');check(editor.getTextInRange(7,0)==='','empty end');
        check(editor.getSelectedRange().join(',')==='3,4','selection preserved');
        let failed=false;try{editor.getTextInRange(6,2);}catch(e){failed=e instanceof RangeError;}check(failed,'invalid range');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorSetTextReturnsVoidAndUpdatesAllCurrentReferences() throws {
        let (library, editor, _, runner) = try setup("Original")
        #expect(runner.run(action(#"""
        const cached=editor.draft;editor.setSelectedRange(8,0);check(editor.setText('🐼')===undefined,'void');
        check(editor.getText()==='🐼' && cached.content==='🐼' && draft.content==='🐼','all current references');
        check(editor.getSelectedRange().join(',')==='2,0','clamped selection');editor.setText('');check(editor.getText()==='' && cached.content==='','empty replacement');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.id == editor.noteID }?.content == "")
    }

    @Test func editorGetTextReturnsCurrentUnicodeContentIncludingEmptyText() throws {
        let (_, _, _, runner) = try setup("🐼 café\r\n日本語")
        #expect(runner.run(action(#"""
        check(editor.getText()==='🐼 café\r\n日本語','exact current text');editor.setText('');check(editor.getText()==='','empty text');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorNewReturnsVoidAndPreservesThePreviousDraft() throws {
        let (library, editor, _, runner) = try setup("Previous 🐼")
        let original = try #require(editor.noteID)
        #expect(runner.run(action(#"""
        const previous=editor.draft;editor.setSelectedRange(0,8);check(editor.new()===undefined,'void');
        check(editor.getText()==='' && editor.getSelectedRange().join(',')==='0,0','new empty editor');
        check(editor.draft.uuid!==previous.uuid && editor.draft.folder==='inbox','new identity and folder');
        check(previous.selectionStart===0 && previous.selectionLength===8,'previous selection');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.noteID != original)
        #expect(library.notes.first { $0.id == original }?.content == "Previous 🐼")
    }

    @Test func editorNewSaveFailureKeepsTheCurrentDraftAndPendingText() throws {
        let (library, editor, host, runner) = try setup("Stored")
        let originalID = editor.noteID
        host.onPerform = { op in if op == "clipboard" { editor.content = "Pending 🐼"; library.beforeBatchCommit = { throw DraftlyError.message("New editor save failure") } } }
        defer { library.beforeBatchCommit = nil }
        #expect(!runner.run(action("app.setClipboard('Arm');editor.new();")))
        #expect(runner.message?.contains("New editor save failure") == true)
        #expect(editor.noteID == originalID && editor.content == "Pending 🐼")
        #expect(library.notes.count == 1)
    }

    @Test func editorTextMutationsKeepPendingTextAndReportStorageFailure() throws {
        for mutation in ["editor.setText('Pending 🐼')", "editor.setSelectedText('Pending 🐼')", "editor.setTextInRange(0,8,'Pending 🐼')"] {
            let (library, editor, host, runner) = try setup("Original")
            host.onPerform = { op in if op == "clipboard" { library.beforeBatchCommit = { throw DraftlyError.message("Mutation storage failure") } } }
            #expect(!runner.run(action("editor.setSelectedRange(0,8);app.setClipboard('Arm');\(mutation);app.setClipboard('Must not run');")))
            #expect(runner.message?.contains("Mutation storage failure") == true)
            #expect(editor.content == "Pending 🐼" && host.clipboard == "Arm")
            library.beforeBatchCommit = nil
        }
    }

    @Test func editorSaveReturnsVoidAndPreservesPendingTextOnFailure() throws {
        let (library, editor, host, runner) = try setup("Stored")
        #expect(runner.run(action("check(editor.save()===undefined,'void');")))
        host.onPerform = { op in if op == "clipboard" { editor.content = "Pending 🐼"; library.beforeBatchCommit = { throw DraftlyError.message("Editor save failure") } } }
        defer { library.beforeBatchCommit = nil }
        #expect(!runner.run(action("app.setClipboard('Arm');editor.save();app.setClipboard('Must not run');")))
        #expect(runner.message?.contains("Editor save failure") == true)
        #expect(editor.content == "Pending 🐼" && host.clipboard == "Arm")
    }

    @Test func draftAppendUsesLineFeedOrExplicitSeparatorAndReturnsVoid() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const d=Draft.create();d.content='First';check(d.append('Café 🐼')===undefined,'void');
        check(d.content==='First\nCafé 🐼','default LF');d.append('tail','|');check(d.content.endsWith('🐼|tail'),'custom separator');
        d.content='';d.append('empty','');check(d.content==='empty','empty separator');
        d.content='';d.append('text');check(d.content==='\ntext','empty content keeps separator');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftPrependUsesLineFeedOrExplicitSeparatorAndReturnsVoid() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const d=Draft.create();d.content='Last';check(d.prepend('Café 🐼')===undefined,'void');
        check(d.content==='Café 🐼\nLast','default LF');d.prepend('head','|');check(d.content==='head|Café 🐼\nLast','custom separator');
        d.content='';d.prepend('empty','');check(d.content==='empty','empty separator');
        d.content='';d.prepend('text');check(d.content==='text\n','empty content keeps separator');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftInsertUsesZeroBasedLinesAndClampsOutsideIndices() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const d=Draft.create();d.content='A\nB';check(d.insert('🐼',1)===undefined,'void');
        check(d.content==='A\n🐼\nB','zero-based insertion');d.insert('Start',-9);d.insert('End',999);
        check(d.content==='Start\nA\n🐼\nB\nEnd','range checking');
        d.content='';d.insert('First',0);check(d.content==='First\n','empty line retained');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftLinesUsesLiteralLineFeedIncludingEmptyLines() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const d=Draft.create();check(JSON.stringify(d.lines)==='[""]','empty content');
        d.content='A\r\n🐼\n\n';check(JSON.stringify(d.lines)===JSON.stringify(['A\r','🐼','','']),'literal LF');
        const lines=d.lines;lines[0]='Changed';check(d.content.startsWith('A\r'),'derived array');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftLinesWithPrefixUsesCaseSensitiveLiteralPrefixes() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const d=Draft.create();d.content='Tag one\ntag two\nTag 🐼\n';
        check(JSON.stringify(d.linesWithPrefix('Tag'))===JSON.stringify(['Tag one','Tag 🐼']),'literal prefix');
        check(d.linesWithPrefix('missing').length===0,'no match');check(d.linesWithPrefix('').length===4,'empty prefix');
        check(d.linesWithPrefix('🐼').length===0,'prefix not substring');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftBodyPreviewExcludesTitleTrimsAndLimitsLength() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const d=Draft.create();check(d.bodyPreview(10)==='','empty');d.content='Only title';check(d.bodyPreview(10)==='','no body');
        d.content='Title\n  Café\nSecond  ';check(d.bodyPreview(100)==='Café Second','body trimmed and flattened');
        check(d.bodyPreview(4)==='Café' && d.bodyPreview(0)==='','length limit');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorLoadRejectsUnsavedDraftWithoutChangingTheCurrentDraft() throws {
        let (_, editor, _, runner) = try setup("Current 🐼")
        let originalID = editor.noteID
        #expect(!runner.run(action("const unsaved=Draft.create();unsaved.content='Not stored';editor.load(unsaved);")))
        #expect(runner.message?.contains("Save the draft before loading") == true)
        #expect(editor.noteID == originalID && editor.content == "Current 🐼")
    }

    @Test func editorLoadSaveFailureKeepsPendingTextAndDoesNotOpenTheTarget() throws {
        let (library, editor, host, runner) = try setup("Stored source")
        let originalID = editor.noteID
        let target = try library.createNote(content: "Target remains intact")
        host.onPerform = { operation in
            if operation == "clipboard" {
                editor.content = "Pending source 🐼"
                library.beforeBatchCommit = { throw DraftlyError.message("Pending editor save failure") }
            }
        }
        defer { library.beforeBatchCommit = nil }
        #expect(!runner.run(action("const target=Draft.find('\(target.id.uuidString)');app.setClipboard('Arm');editor.load(target);")))
        #expect(runner.message?.contains("Pending editor save failure") == true)
        #expect(editor.noteID == originalID && editor.content == "Pending source 🐼")
        #expect(library.notes.first { $0.id == target.id }?.content == target.content)
    }

    @Test func editorGetLineRangeMatchesNativeUTF16Boundaries() throws {
        let (_, _, _, runner) = try setup()
        let fixtures: [(String, [[Int]])] = [
            ("", [[0,0,0,0]]),
            ("🐼 café\nNext\n", [[0,0,0,8],[2,0,0,8],[7,0,0,8],[8,0,8,5],[0,8,0,8],[7,1,0,8],[7,2,0,13],[8,4,8,5],[13,0,13,0]]),
            ("A\rB", [[0,0,0,2],[1,0,0,2],[2,0,2,1],[3,0,2,1]]),
            ("A\r\nB", [[0,0,0,3],[1,0,0,3],[2,0,0,3],[3,0,3,1],[4,0,3,1],[0,3,0,3],[2,2,0,4]]),
            ("A\u{2028}B\u{2029}C", [[0,0,0,2],[2,0,2,2],[4,0,4,1],[5,0,4,1],[1,2,0,4]])]
        for (text, cases) in fixtures {
            let input = String(decoding: try JSONSerialization.data(withJSONObject: [text]), as: UTF8.self)
            let expected = String(decoding: try JSONSerialization.data(withJSONObject: cases), as: UTF8.self)
            #expect(runner.run(action("editor.setText(\(input)[0]);check(editor.getLineRange(0).join(',')===editor.getLineRange(0,0).join(','),'omitted length');for(const [p,n,start,size] of \(expected)){const r=editor.getLineRange(p,n);check(r[0]===start && r[1]===size,'native line '+p+','+n);}")), Comment(rawValue: runner.message ?? ""))
        }
    }

    @Test func editorGetSelectedLineRangeUsesCurrentSelectionAndPreservesIt() throws {
        let (_, editor, _, runner) = try setup("A\r\n🐼 café\r\nEnd")
        #expect(runner.run(action(#"""
        editor.setSelectedRange(3,2);const r=editor.getSelectedLineRange();
        check(r[0]===3 && r[1]===9,'selected CRLF line');
        check(editor.getSelectedRange().join(',')==='3,2','selection unchanged');
        editor.setSelectedRange(editor.getText().length,0);check(editor.getSelectedLineRange().join(',')==='12,3','last line');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "A\r\n🐼 café\r\nEnd")
    }

    @Test func editorGetSelectedRangeReturnsACopyInUTF16Units() throws {
        let (_, _, _, runner) = try setup("🐼 café")
        #expect(runner.run(action(#"""
        editor.setSelectedRange(0,2);const r=editor.getSelectedRange();check(r.join(',')==='0,2','UTF16 range');
        r[0]=99;check(editor.getSelectedRange().join(',')==='0,2','independent range');
        editor.setSelectedRange(7,0);check(editor.getSelectedRange().join(',')==='7,0','empty end range');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorGetSelectedTextReturnsUnicodeAndEmptySelection() throws {
        let (_, _, _, runner) = try setup("🐼 café")
        #expect(runner.run(action(#"""
        editor.setSelectedRange(0,2);check(editor.getSelectedText()==='🐼','emoji selection');
        editor.setSelectedRange(3,4);check(editor.getSelectedText()==='café','accent selection');
        editor.setSelectedRange(7,0);check(editor.getSelectedText()==='','empty selection');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    private func workspaceFlagFixture() throws -> (LibraryStore, ActionRunner) {
        let (library, _, _, runner) = try setup()
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
        #expect(runner.run(action(#"""
        const w=new Workspace();w.tagFilter='contract';check(w.inboxIncludesFlagged===true,'default');
        check(w.query('inbox').length===2,'included');w.inboxIncludesFlagged=false;
        check(w.query('inbox').map(d=>d.title).join(',')==='Inbox plain','excluded');
        check(w.query('archive').length===2 && w.query('all').length===4,'other folders unaffected');
        w.name='Inbox flags';w.update();check(Workspace.find(w.name).inboxIncludesFlagged===false,'persisted');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceArchiveIncludesFlaggedOnlyChangesArchiveResults() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(action(#"""
        const w=new Workspace();w.tagFilter='contract';check(w.archiveIncludesFlagged===true,'default');
        check(w.query('archive').length===2,'included');w.archiveIncludesFlagged=false;
        check(w.query('archive').map(d=>d.title).join(',')==='Archive plain','excluded');
        check(w.query('inbox').length===2 && w.query('all').length===4,'other folders unaffected');
        w.name='Archive flags';w.update();check(Workspace.find(w.name).archiveIncludesFlagged===false,'persisted');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceFlaggedStatusFiltersEveryFolderAndRejectsUnknownValues() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(action(#"""
        const w=new Workspace();w.tagFilter='contract';check(w.flaggedStatus==='any' && w.query('all').length===4,'default');
        w.flaggedStatus='flagged';check(w.query('all').length===2 && w.query('inbox')[0].title==='Inbox flagged','flagged');
        w.flaggedStatus='unflagged';check(w.query('all').length===2 && w.query('archive')[0].title==='Archive plain','unflagged');
        w.name='Flag status';w.update();check(Workspace.find(w.name).flaggedStatus==='unflagged' && Workspace.find(w.name).query('all').length===2,'persisted status');
        w.flaggedStatus='invalid';let failed=false;try{w.query('all');}catch(e){failed=true;}check(failed,'invalid status');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceTagFilterCombinesInclusionsAndExclusionsAndSurvivesStorage() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(action(#"""
        const w=new Workspace();check(w.tagFilter==='','default');w.tagFilter=' CONTRACT , !blocked ';
        check(w.query('all').length===3,'inclusion and exclusion');w.name='Tag filter';w.update();
        const saved=Workspace.find(w.name);check(saved.tagFilter==='contract,!blocked' && saved.query('all').length===3,'stored normalization');
        w.tagFilter='!blocked';check(!w.query('all').some(d=>d.hasTag('blocked')),'exclusion only');
        w.tagFilter='missing';check(w.query('all').length===0,'no matches');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceTagFilterRequireAllChangesANDToORWithoutWeakeningExclusions() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(action(#"""
        const w=new Workspace();check(w.tagFilterRequireAll===true,'default');w.tagFilter='blue, green, !blocked';
        check(w.query('all').length===0,'AND');w.tagFilterRequireAll=false;
        check(w.query('all').length===3 && !w.query('all').some(d=>d.hasTag('blocked')),'OR keeps exclusion');
        w.name='Any tags';w.update();check(Workspace.find(w.name).tagFilterRequireAll===false,'persisted');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceQueryCoversAllFoldersAndRejectsInvalidFolder() throws {
        let (_, runner) = try workspaceFlagFixture()
        #expect(runner.run(action(#"""
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
        let (library, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const a=new Workspace(),b=new Workspace();check(a!==b && a.startDate!==b.startDate,'independent values');
        check(a.name==='' && a.queryString==='' && a.tagFilter==='' && a.tagFilterRequireAll===true,'filter defaults');
        check(a.showDate && a.showPreview && a.showTags && a.showSearchPreview && !a.showLastAction,'display defaults');
        a.name='Unsaved';check(Workspace.find('Unsaved')===undefined,'constructor does not persist');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.workspaces.isEmpty)
    }

    @Test func workspaceCreateUsesDefaultConfigurationWithoutSavingIt() throws {
        let (library, _, _, runner) = try setup()
        runner.defaultWorkspace = { var w = Workspace(name: ""); w.query = "café"; w.tags = ["work"]; return w }
        #expect(runner.run(action(#"""
        const a=Workspace.create(),b=Workspace.create();check(a!==b && a.uuid!==b.uuid,'fresh identity');
        check(a.queryString==='café' && a.tagFilter==='work','default configuration');
        a.queryString='changed';check(b.queryString==='café','independent defaults');
        check(Workspace.getAll().length===0,'factory does not persist');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.workspaces.isEmpty)
    }

    @Test func workspaceFindMatchesExactNameAndReturnsTypedValues() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const w=new Workspace();w.name='Café 🐼';w.update();const found=Workspace.find('Café 🐼');
        check(found instanceof Workspace && found.startDate instanceof QueryDate,'typed result');
        check(Workspace.find('café 🐼')===undefined && Workspace.find('missing')===undefined,'exact missing names');
        found.name='Unsaved rename';check(Workspace.find('Café 🐼').name==='Café 🐼','no implicit persistence');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceGetAllReturnsIndependentStoredWorkspaces() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        check(Workspace.getAll().length===0,'empty library');
        for(const name of ['One','Two']){const w=new Workspace();w.name=name;w.update();}
        const all=Workspace.getAll();check(all.length===2 && all.every(w=>w instanceof Workspace),'stored values');
        all[0].name='Unsaved';all.pop();check(Workspace.getAll().length===2 && !Workspace.getAll().some(w=>w.name==='Unsaved'),'independent results');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func workspaceUpdateReturnsVoidAndRollsBackStorageFailure() throws {
        let (library, _, host, runner) = try setup()
        #expect(runner.run(action("const w=new Workspace();w.name='Before failure';check(w.update()===undefined,'void return');")))
        let original = try #require(library.workspaces.first)
        host.onPerform = { operation in if operation == "clipboard" { library.beforeBatchCommit = { throw DraftlyError.message("Workspace storage failure") } } }
        defer { library.beforeBatchCommit = nil }
        #expect(!runner.run(action("const w=Workspace.find('Before failure');w.name='Lost rename';app.setClipboard('Arm');w.update();app.setClipboard('Must not run');")))
        #expect(runner.message?.contains("Workspace storage failure") == true)
        #expect(host.clipboard == "Arm")
        #expect(library.workspaces == [original])
        let restored = try LibraryStore(inMemory: true, seed: false); try restored.restore(library.backupData())
        #expect(restored.workspaces == [original])
    }

    @Test func workspaceUpdateRejectsInvalidConfigurationBeforePersistence() throws {
        let (library, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const mutations=[w=>w.loadFolder='missing',w=>w.flaggedStatus='missing',w=>w.setInboxSort('missing',false,false),w=>w.startDate.field='missing',w=>w.endDate.type='missing',w=>{w.startDate.type='absolute';w.startDate.date='not a date';}];
        for(const mutate of mutations){const w=new Workspace();w.name='Invalid';mutate(w);let failed=false;try{w.update();}catch(e){failed=true;}check(failed,'invalid update rejected');check(Workspace.find('Invalid')===undefined,'no partial save');}
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.workspaces.isEmpty)
    }

    @Test func queryDateConstructorCreatesIndependentValues() throws {
        let (_, _, host, runner) = try setup()
        #expect(runner.run(action(#"""
        const before=Date.now(), a=new QueryDate(), b=new QueryDate();
        check(a instanceof QueryDate && a!==b,'independent instances');
        check(a.type==='none' && a.field==='modified' && a.days===0,'initial values');
        check(a.date instanceof Date && a.date.getTime()>=before && a.date.getTime()<=Date.now(),'current date');
        check(a.date!==b.date,'independent dates');
        a.days=-3;check(b.days===0,'no shared state');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(host.calls.isEmpty)
    }

    @Test func queryDateDatePreservesAbsoluteDateThroughStorage() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const q=new QueryDate(), stamp=new Date('2026-03-08T23:45:12.345Z');
        q.type='absolute';q.date=stamp;
        check(q.date===stamp,'Date assignment');
        const w=new Workspace();w.name='Absolute date contract';w.startDate=q;w.update();
        const restored=Workspace.find(w.name).startDate;
        check(restored instanceof QueryDate && restored.date instanceof Date,'typed restoration');
        check(restored.date.getTime()===stamp.getTime(),'absolute date precision');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func queryDateDaysPreservesNegativeZeroAndPositiveIntegers() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        for(const days of [-3,0,7]) {
            const q=new QueryDate();q.type='relative';q.days=days;
            const w=new Workspace();w.name='Relative date '+days;w.startDate=q;w.update();
            const saved=Workspace.find(w.name).startDate;
            check(saved.days===days && saved.type==='relative','relative integer '+days);
        }
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func queryDateFieldPreservesEverySupportedDateField() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        for(const field of ['created','modified','accessed']) {
            const q=new QueryDate();q.field=field;
            const w=new Workspace();w.name='Date field '+field;w.startDate=q;w.update();
            check(Workspace.find(w.name).startDate.field===field,'date field '+field);
        }
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func queryDateTypePreservesEverySupportedRangeType() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        for(const type of ['none','relative','absolute']) {
            const q=new QueryDate();q.type=type;
            const w=new Workspace();w.name='Date type '+type;w.endDate=q;w.update();
            check(Workspace.find(w.name).endDate.type===type,'date type '+type);
        }
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func queryDateFactoryReturnsFreshQueryDates() throws {
        let (_, _, host, runner) = try setup()
        #expect(runner.run(action(#"""
        const a=QueryDate.create(), b=QueryDate.create();
        check(a instanceof QueryDate && !(a instanceof Workspace),'factory result');
        check(a!==b && a.date!==b.date,'fresh values');
        check(a.type==='none' && a.field==='modified' && a.days===0 && a.date instanceof Date,'factory defaults');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(host.calls.isEmpty)
    }






    @Test func selectPromptItemConstructorCreatesIndependentEmptyValues() throws {
        let (_, _, host, runner) = try setup()
        #expect(runner.run(action(#"""
        const a=new SelectPromptItem(),b=new SelectPromptItem();
        check(a instanceof SelectPromptItem && a!==b,'independent values');
        check(a.id===undefined && a.title===undefined && a.subtitle===undefined && a.symbolName===undefined,'initial fields');
        a.title='Changed';check(b.title===undefined,'no shared state');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(host.calls.isEmpty)
    }

    @Test func selectPromptItemFactoryPreservesArgumentsAndOptionalValues() throws {
        let (_, _, host, runner) = try setup()
        #expect(runner.run(action(#"""
        const a=SelectPromptItem.create('id','Café 🐼'),b=SelectPromptItem.create('other','Title','Details','doc');
        check(a instanceof SelectPromptItem && b instanceof SelectPromptItem && a!==b,'factory type');
        check(a.id==='id' && a.title==='Café 🐼','required fields');
        check(a.subtitle===undefined && a.symbolName===undefined,'optional fields omitted');
        check(b.subtitle==='Details' && b.symbolName==='doc','optional fields supplied');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(host.calls.isEmpty)
    }

    @Test func selectPromptItemIDEnforcesUniquenessWhenAdded() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const a=new SelectPromptItem();a.id='🐼';a.title='First';
        const p=new SelectPrompt();check(p.addItem(a)===true,'writable ID');
        check(p.addItem(SelectPromptItem.create('🐼','Duplicate'))===false,'duplicate ID');
        check(p.addItem(SelectPromptItem.create('different','First'))===true,'same title allowed');
        check(p.items.length===2 && p.items[0].id==='🐼','invalid item did not change list');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func selectPromptItemTitleReachesSelectionWithoutChangingUnicode() throws {
        let (_, _, host, runner) = try setup()
        #expect(runner.run(action(#"""
        const item=new SelectPromptItem();item.id='one';item.title='Café 🐼 日本語';
        const p=new SelectPrompt();check(p.addItem(item),'add');check(p.show(),'selection');
        check(p.selectedItem.title==='Café 🐼 日本語','selected title');
        """#)), Comment(rawValue: runner.message ?? ""))
        let items = try #require(host.calls.first { $0.0 == "selectPrompt" }?.1["items"] as? [[String: Any]])
        #expect(items.first?["title"] as? String == "Café 🐼 日本語")
    }

    @Test func selectPromptItemSubtitleRemainsOptionalAndSeparate() throws {
        let (_, _, host, runner) = try setup()
        #expect(runner.run(action(#"""
        const item=SelectPromptItem.create('one','Title');check(item.subtitle===undefined,'omitted subtitle');
        item.subtitle='Details 🐼\nSecond line';const p=new SelectPrompt();p.addItem(item);check(p.show(),'selection');
        check(p.selectedItem.subtitle===item.subtitle && p.selectedItem.title==='Title','separate subtitle');
        """#)), Comment(rawValue: runner.message ?? ""))
        let items = try #require(host.calls.first { $0.0 == "selectPrompt" }?.1["items"] as? [[String: Any]])
        #expect(items.first?["subtitle"] as? String == "Details 🐼\nSecond line")
    }

    @Test func selectPromptItemSymbolNameReachesTheNativeHost() throws {
        let (_, _, host, runner) = try setup()
        #expect(runner.run(action(#"""
        const item=SelectPromptItem.create('one','Title');check(item.symbolName===undefined,'omitted symbol');
        item.symbolName='doc.text';const p=new SelectPrompt();p.addItem(item);check(p.show(),'selection');
        check(p.selectedItem.symbolName==='doc.text','selected symbol');
        """#)), Comment(rawValue: runner.message ?? ""))
        let items = try #require(host.calls.first { $0.0 == "selectPrompt" }?.1["items"] as? [[String: Any]])
        #expect(items.first?["symbolName"] as? String == "doc.text")
    }

    @Test func selectPromptDefaultsFactoryAndCancelContract() throws {
        let (library, editor, host, runner) = try setup()
        host.selectedIndex = nil
        #expect(runner.run(action(#"""
        const p=SelectPrompt.create();check(p instanceof SelectPrompt,'factory');
        check(p.message==='' && p.selectedItem===undefined,'defaults');
        check(p.addItem()===false,'missing parameters');
        check(p.addItem('one','Title')===true,'optional arguments');
        check(p.items[0].subtitle===undefined && p.items[0].symbolName===undefined,'optional defaults');
        check(p.show()===false && p.selectedItem===null,'cancel result');
        const empty=new SelectPrompt();check(empty.show()===false && empty.selectedItem===null,'empty selection');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.runs.first?.message.contains("unique string ID") == true)
        let noHost = ActionRunner(library: library, editor: editor)
        #expect(!noHost.run(action("const p=SelectPrompt.create();p.addItem('one','One');p.show();")))
        #expect(noHost.message?.contains("selectPrompt") == true)
    }

    @Test func selectPromptPreservesItemFieldsAndReturnsBooleanResults() throws {
        let (_, _, host, runner) = try setup()
        #expect(runner.run(action(#"""
        let p=SelectPrompt.create();p.message='Choose';
        check(p.addItem('one','Café','Subtitle 🐼','tag')===true,'boolean success');
        check(p.addItem('one','Duplicate')===false,'duplicate');
        check(p.addItem(42,'Invalid')===false,'missing ID');
        check(p.items.length===1,'invalid items unchanged');
        check(p.show()===true,'show');
        check(p.selectedItem.id==='one' && p.selectedItem.subtitle==='Subtitle 🐼','result fields');
        check(p.selectedItem.symbolName==='tag','symbol');
        const item=SelectPromptItem.create('two','Title','Details','doc');check(item instanceof SelectPromptItem && item.id==='two' && item.title==='Title' && item.subtitle==='Details' && item.symbolName==='doc','item factory');
        check(new SelectPromptItem().id===undefined,'item defaults');
        """#)), Comment(rawValue: runner.message ?? ""))
        let fields = try #require(host.calls.first { $0.0 == "selectPrompt" }?.1["items"] as? [[String: Any]])
        #expect(fields.count == 1)
        #expect(host.calls.first { $0.0 == "selectPrompt" }?.1["message"] as? String == "Choose")
        #expect(fields[0]["subtitle"] as? String == "Subtitle 🐼")
        host.selectedIndex = nil
        #expect(runner.run(action("let p=new SelectPrompt();p.addItem('a','A');p.selectedItem={id:'old'};check(p.show()===false && p.selectedItem===null,'cancel clears old selection');")))
        host.selectedIndex = 99
        #expect(runner.run(action("let p=new SelectPrompt();p.addItem('a','A');check(p.show()===false && p.selectedItem===null,'invalid response');")))
    }

    @Test func contextStopsLaterStepsButFinishesTheCurrentScript() throws {
        for stop in ["cancel", "fail"] {
            let (_, _, host, runner) = try setup()
            var value = action("context.\(stop)('Reason');app.setClipboard('current script finished');")
            value.steps.append(ActionStep("clipboard", ["template": "must not run"]))
            let result = runner.runResult(value)
            #expect(result == (stop == "cancel" ? .cancelled : .failure("Reason")))
            #expect(host.clipboard == "current script finished")
            #expect(host.calls.filter { $0.0 == "clipboard" }.count == 1)
        }
    }

    @Test func contextSuccessParametersAreExportedOnlyForSuccessfulRuns() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action("context.addSuccessParameter('result','café + 🐼');context.addSuccessParameter('result','replaced');")))
        #expect(runner.successParameters == ["result": "replaced"])
        #expect(runner.run(action("check(Object.keys(context.successParameters).length===0,'fresh run');")))
        #expect(runner.successParameters.isEmpty)
        #expect(!runner.run(action("context.addSuccessParameter('result','secret');context.cancel();")))
        #expect(runner.successParameters.isEmpty)
        #expect(!runner.run(action("context.addSuccessParameter('result','secret');throw new Error('stop');")))
        #expect(runner.successParameters.isEmpty)
        #expect(!runner.run(action("context.addSuccessParameter('key',42);")))
        #expect(runner.message?.contains("must be strings") == true)
    }

    @Test func finalResultChoosesAndEncodesOnlyItsOwnCallback() throws {
        let targets = ["x-success": "test://success?keep=1&result=old", "x-cancel": "test://cancel", "x-error": "test://error"]
        let url = try #require(ActionExecutionResult.success.callbackURL(parameters: targets, successParameters: ["result": "café + 🐼"]))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.filter { $0.name == "result" }.map(\.value) == ["café + 🐼"])
        #expect(items.contains { $0.name == "keep" && $0.value == "1" })
        #expect(ActionExecutionResult.cancelled.callbackURL(parameters: targets, successParameters: ["result": "unused"])?.absoluteString == "test://cancel")
        let error = try #require(ActionExecutionResult.failure("Failed + café").callbackURL(parameters: targets))
        #expect(URLComponents(url: error, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Failed + café")
        #expect(ActionExecutionResult.success.callbackURL(parameters: [:]) == nil)
        #expect(ActionExecutionResult.success.callbackURL(parameters: ["x-success": "relative/path"]) == nil)
    }

    @Test func anotherWindowCannotRunActionsInTheSameLibraryDuringAHostCall() throws {
        let (library, editor, host, runner) = try setup()
        let second = ActionRunner(library: library, editor: editor)
        var nested: ActionExecutionResult?
        host.onPerform = { operation in
            if operation == "clipboard" { nested = second.runResult(action("editor.setText('overwritten');")) }
        }
        let original = editor.content
        #expect(runner.run(action("app.setClipboard('outer');")))
        #expect(nested == .failure("An action is already running in this library."))
        #expect(editor.content == original)
        host.onPerform = nil
        #expect(second.run(action("editor.setText('after release');")))
        #expect(editor.content == "after release")
    }

    @Test func deviceUsesMacValuesAndReportsUnavailableBatteryExplicitly() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action("check(device.model==='Mac' && device.systemName==='macOS','platform');check(typeof device.systemVersion==='string' && device.systemVersion.length>0,'version');try{let level=device.batteryLevel;check(level>=0 && level<=1,'level');}catch(e){check(e.message.includes('battery level is unavailable'),'explicit unavailable');}")))
        #expect(try ScriptDevice.batteryLevel(sources: [["Type": "InternalBattery", "Current Capacity": 50.0, "Max Capacity": 100.0]]) == 0.5)
        #expect(try ScriptDevice.batteryLevel(sources: [["Type": "InternalBattery", "Current Capacity": 0.0, "Max Capacity": 100.0]]) == 0)
        let invalid: [[[String: Any]]] = [[], [["Type": "UPS", "Current Capacity": 50, "Max Capacity": 100]], [["Type": "InternalBattery", "Current Capacity": 5, "Max Capacity": 0]], [["Type": "InternalBattery", "Current Capacity": -1, "Max Capacity": 100]]]
        for values in invalid {
            #expect(throws: (any Error).self) { try ScriptDevice.batteryLevel(sources: values) }
        }
    }

    @Test func actionAndGroupQueriesKeepIdentityOrderAndInstallationData() throws {
        let (library, editor, host, runner) = try setup()
        var first = action("");first.name="First";first.group="Contracts";first.configuredValues=["key":"value"];first.presentation.order=2
        var second = action("");second.name="Second";second.group="Contracts";second.presentation.order=1
        try library.saveAction(first);try library.saveAction(second)
        var log = ActionRun(actionName:"Previous name",status:"Success",message:"");log.actionID=first.id;log.noteID=editor.noteID;library.log(log)
        #expect(runner.run(action(#"""
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

    @Test func versionContentIsAnImmutableSnapshot() throws {
        let (library, editor, _, runner) = try setup()
        try library.saveRevision(Revision(noteID: try #require(editor.noteID), content: "Saved 🐼\n\"café\""))
        #expect(runner.run(action(#"""
        const v=draft.versions.find(x=>x.content==='Saved 🐼\n"café"');check(v instanceof Version,'version type');
        check(Reflect.set(v,'content','Changed')===false,'read-only content');
        editor.setText('New editor content');draft.update();
        check(v.content==='Saved 🐼\n"café"','snapshot independent of current content');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func versionCreatedAtIsATypedReadOnlyTimestamp() throws {
        let (library, editor, _, runner) = try setup()
        var revision = Revision(noteID: try #require(editor.noteID), content: "Dated version")
        revision.date = Date(timeIntervalSince1970: 1_600_000_000.125)
        try library.saveRevision(revision)
        #expect(runner.run(action(#"""
        const v=draft.versions.find(x=>x.content==='Dated version');
        check(v.createdAt instanceof Date && v.createdAt.getTime()===1600000000125,'timestamp milliseconds');
        check(Reflect.set(v,'createdAt',new Date(0))===false,'read-only timestamp');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func versionUUIDIsStableUniqueAndReadOnly() throws {
        let (library, editor, _, runner) = try setup()
        let id = try #require(editor.noteID)
        try library.saveRevision(Revision(noteID: id, content: "Version A"))
        try library.saveRevision(Revision(noteID: id, content: "Version B"))
        #expect(runner.run(action(#"""
        const a=draft.versions.find(x=>x.content==='Version A'),b=draft.versions.find(x=>x.content==='Version B');
        check(typeof a.uuid==='string' && /^[0-9a-f-]{36}$/i.test(a.uuid),'UUID format');
        check(a.uuid!==b.uuid,'unique UUID');check(Reflect.set(a,'uuid','other')===false,'read-only identity');
        check(draft.versions.find(x=>x.uuid===a.uuid).content==='Version A','stable identity');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func versionDraftUsesCurrentCachedIdentityAndMissingDraftIsUndefined() throws {
        let (library, editor, _, runner) = try setup()
        try library.saveRevision(Revision(noteID: try #require(editor.noteID), content: "Related version"))
        #expect(runner.run(action(#"""
        const v=draft.versions.find(x=>x.content==='Related version');check(v.draft===draft,'cached draft identity');
        draft.content='Pending draft edit';check(v.draft.content==='Pending draft edit','pending changes visible');
        check(Reflect.set(v,'draft',Draft.create())===false,'read-only draft relation');
        check(new Version({uuid:'orphan',draftUUID:'00000000-0000-0000-0000-000000000000',content:'Orphan',createdAt:new Date()}).draft===undefined,'missing relation');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func versionDeleteReturnsVoidAndRemovesOnlyThatRevision() throws {
        let (library, editor, _, runner) = try setup()
        let id = try #require(editor.noteID)
        try library.saveRevision(Revision(noteID: id, content: "Delete this version"))
        try library.saveRevision(Revision(noteID: id, content: "Keep this version"))
        let original = editor.content
        #expect(runner.run(action(#"""
        const v=draft.versions.find(x=>x.content==='Delete this version');
        check(v.delete()===undefined,'void return');check(!draft.versions.some(x=>x.uuid===v.uuid),'removed revision');
        check(draft.versions.some(x=>x.content==='Keep this version'),'other revision remains');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == original)
        #expect(library.revisions.contains { $0.content == "Keep this version" })
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(!restored.revisions.contains { $0.content == "Delete this version" })
    }

    @Test func versionDeleteStorageFailureThrowsAndRestoresTheRevision() throws {
        let (library, editor, host, runner) = try setup()
        let revision = Revision(noteID: try #require(editor.noteID), content: "Keep on failure 🐼")
        try library.saveRevision(revision)
        host.onPerform = { operation in
            if operation == "clipboard" { library.beforeBatchCommit = { throw DraftlyError.message("Revision storage failure") } }
        }
        defer { library.beforeBatchCommit = nil }
        #expect(!runner.run(action(#"""
        const v=draft.versions.find(x=>x.content==='Keep on failure 🐼');
        app.setClipboard('Arm neutral failure test');v.delete();
        app.setClipboard('Must not run');
        """#)))
        #expect(runner.message?.contains("Revision storage failure") == true)
        #expect(host.clipboard == "Arm neutral failure test")
        #expect(library.revisions.contains { $0.id == revision.id && $0.content == revision.content })
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.revisions.contains { $0.id == revision.id })
    }

    @Test func tagSyntaxAndVersionMembersUsePersistedValues() throws {
        let (library, editor, _, runner) = try setup()
        let id = try #require(editor.noteID)
        var note = try #require(library.notes.first);note.tags=["blue", "black"];try library.saveNote(note)
        try library.saveRevision(Revision(noteID:id,content:"Saved 🐼"))
        #expect(runner.run(action(#"""
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

    @Test func workspaceApplicationReturnsTheHostResultAndDefaultsWhenOmitted() throws {
        let (_, _, _, runner) = try setup()
        var applied: [Workspace] = []
        runner.defaultWorkspace = { Workspace(name:"Default contract") }
        runner.applyWorkspace = { applied.append($0) }
        #expect(runner.run(action("check(app.applyWorkspace()===true,'default app result');let w=Workspace.create();w.name='Explicit';check(window.applyWorkspace(w)===true,'window result');")),Comment(rawValue: runner.message ?? ""))
        #expect(applied.map(\.name) == ["Default contract","Explicit"])
    }

    @Test func invalidRangesAndQueriesFailWithoutChangingTheEditor() throws {
        let (_, editor, _, runner) = try setup("🐼 café\nLine")
        let original = editor.content
        #expect(runner.run(action(#"""
        const ranges=[[-1,0],[0,-1],[999,0],[0,999],[0.5,1],[NaN,0],[Infinity,0],['0',1],[true,1]];
        for(let range of ranges){
            for(let method of ['getTextInRange','getLineRange','setSelectedRange']){
                let failed=false;try{editor[method](...range);}catch(e){failed=e instanceof RangeError;}
                check(failed,method+' invalid '+String(range));
            }
            let failed=false;try{editor.setTextInRange(...range,'bad');}catch(e){failed=e instanceof RangeError;}
            check(failed,'invalid replacement');
        }
        check(editor.getTextInRange(0,2)==='🐼','UTF16 emoji');
        editor.setSelectedRange(editor.getText().length,0);check(editor.getSelectedText()==='','empty end range');
        for(let args of [['','missing'],['','all',[],[],'missing']]){
            let failed=false;try{Draft.query(...args);}catch(e){failed=true;}check(failed,'invalid query option');
        }
        check(app.areLiveActivitiesSupported===false,'Mac availability');
        for(let name of ['startLiveActivity','stopLiveActivity']){let failed=false;try{app[name](draft);}catch(e){failed=e.message.includes('unavailable on macOS');}check(failed,name);}
        """#)),Comment(rawValue:runner.message ?? ""))
        #expect(editor.content == original)
    }

    @Test func synchronousTimeoutStopsLaterStepsAndSuccessEffects() throws {
        let (library, editor, host, runner) = try setup()
        runner.synchronousScriptTimeout = 0.02
        var value = action("while(true) {}")
        value.afterSuccess = "archive"
        value.steps.append(ActionStep("clipboard", ["template":"must not run"]))
        #expect(!runner.run(value))
        #expect(host.clipboard.isEmpty)
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
        runner.synchronousScriptTimeout = 0
        #expect(!runner.run(action("app.setClipboard('invalid timeout');")))
        #expect(runner.message?.contains("positive and finite") == true)
        #expect(host.clipboard.isEmpty)
    }

    @Test func shortcutResponsesReachContextInExecutionOrder() throws {
        let (_, _, host, runner) = try setup()
        let value = DraftAction(name:"Shortcut context",steps:[
            ActionStep("runShortcut",["name":"Fixture","template":"Input"]),
            ActionStep("script",["script":"if(context.callbackResponses[0].result!=='Shortcut output')throw new Error('step response');let s=Shortcut.create('Fixture');if(!s.run('Other'))throw new Error('run');if(context.callbackResponses.length!==2 || context.callbackResponses[1].result!==s.result)throw new Error('script response');"])
        ])
        #expect(runner.run(value),Comment(rawValue:runner.message ?? ""))
        #expect(host.calls.filter { $0.0 == "shortcut" }.count == 2)
    }

    @Test func importedSeparatorsRetainTheirAPIIdentityAndRawPayload() throws {
        let (library, _, _, runner) = try setup()
        let json = Data(#"{"name":"Section","backingIsSeparator":true,"steps":[],"unknown":{"nested":[1,2]}}"#.utf8)
        let imported = try #require(ActionImporter.decode(json).first)
        try library.saveAction(imported)
        #expect(imported.rawPayload?.contains("unknown") == true)
        #expect(runner.run(action("check(Action.find('Section').isSeparator===true,'imported separator');")))
    }

    @Test func contextConfigurationDefaultsAndAppleScriptResponsesKeepTheirTypes() throws {
        let (_, _, host, runner) = try setup()
        let value=DraftAction(name:"Context values",steps:[
            ActionStep("configurationKey",["key":"enabled","dataType":"boolean","defaultBoolValue":"true"]),
            ActionStep("configurationKey",["key":"count","dataType":"number","defaultNumberValue":"2.5"]),
            ActionStep("configurationKey",["key":"label","dataType":"string","defaultStringValue":"café"]),
            ActionStep("runAppleScript",["script":"fixture source"]),
            ActionStep("script",["script":"if(context.configuredValues.enabled!==true || context.configuredValues.count!==2.5 || context.configuredValues.label!=='café')throw new Error('typed defaults');if(action.configuredValues!==context.configuredValues)throw new Error('shared values');if(context.appleScriptResponses[0].value!==42)throw new Error('step response');const apple=AppleScript.create('fixture');if(!apple.execute('execute') || context.appleScriptResponses.length!==2 || context.appleScriptResponses[1].value!==42)throw new Error('script response');const p=new SelectPrompt();if(p.addItem(SelectPromptItem.create('legacy','Existing overload'))!==true)throw new Error('object overload');"])
        ])
        #expect(runner.run(value),Comment(rawValue:runner.message ?? ""))
        #expect(host.calls.filter { $0.0 == "appleScript" }.count == 2)
    }

    @Test func actionLogsKeepTheirActionAfterRenameAndUseOfficialStatuses() throws {
        let (library, _, _, runner) = try setup()
        var saved = action("context.cancel('Reason');");try library.saveAction(saved)
        #expect(!runner.run(saved))
        #expect(library.runs.first?.message == "Reason")
        saved.name="Renamed";try library.saveAction(saved)
        #expect(runner.run(action(#"""
        const log=draft.actionLogs[0];
        check(log.status==='cancelled' && log.log==='Reason','cancel log');
        check(log.action.name==='Renamed' && log.draft.uuid===draft.uuid,'relations');
        check(log.executedAt instanceof Date && log.executedDevice==='Mac','log date');
        check(log.executedLatitude===0 && log.executedLongitude===0,'log location');
        """#)),Comment(rawValue:runner.message ?? ""))
    }

    @Test func invalidWorkspaceValuesFailExplicitly() throws {
        let (_, _, _, runner) = try setup()
        for script in ["w.loadFolder='missing';", "w.flaggedStatus='missing';", "w.startDate.type='missing';", "w.startDate.type='absolute';w.startDate.date=new Date('invalid');", "w.startDate.field='missing';", "w.setAllSort('missing',false,false);"] {
            #expect(!runner.run(action("const w=Workspace.create();"+script+"w.update();")))
        }
    }

    @Test func editorLinksAndMarkersExposeTheDocumentedFields() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        editor.setText('# One\n[[note]] https://example.com\n## Two');
        const link=editor.linkedItems[0];check(link.location===6 && link.length===8 && link.value==='note','link fields');
        check(editor.urls.includes('https://example.com') && draft.urls.includes('https://example.com'),'detected URLs');
        check(editor.navigationMarkerAfter(0).label==='Two','next marker');
        check(editor.navigationMarkerBefore(2).label==='One','previous marker');
        editor.setSelectedRange(6,8);check(draft.selectionStart===6 && draft.selectionLength===8,'draft selection');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorInterfaceMembersDelegateWithoutLosingArguments() throws {
        let (_, _, _, runner) = try setup()
        var state: [String: Any] = ["isActive":true,"preferredTabString":"\t"]
        var calls: [[String: Any]] = []
        runner.uiOperation = { values in
            calls.append(values)
            let key=values["key"] as? String ?? ""
            if values["operation"] as? String == "set" { state[key]=values["value"];return true }
            if values["operation"] as? String == "get" { return state[key] ?? false }
            if ["arrange","dictate","scanDocument","transcribe"].contains(values["operation"] as? String ?? "") { return "Returned" }
            return true
        }
        #expect(runner.run(action(#"""
        check(editor.isActive && editor.preferredTabString==='\t','read-only UI properties');
        for(let key of ['linkModeEnabled','pinningEnabled','focusModeEnabled','typewriterScrollingEnabled']){
            editor[key]=true;check(editor[key]===true,key);
        }
        editor.activate();editor.deactivate();editor.showFind(true,'café');editor.showArrange();editor.showDictate();
        editor.nextDraft();editor.previousDraft();editor.undo();editor.redo();
        check(editor.arrange('Text')==='Returned','arrange return');
        check(editor.dictate('es-AR')==='Returned','dictation return');
        check(editor.scanDocument()==='Returned' && editor.transcribe()==='Returned','input returns');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(calls.contains { $0["operation"] as? String == "showFind" && ($0["args"] as? [Any])?.last as? String == "café" })
        #expect(calls.contains { $0["operation"] as? String == "dictate" && ($0["args"] as? [String]) == ["es-AR"] })
    }

    @Test func workspaceDefaultsAndAllFolderSortsRoundTrip() throws {
        let (library, _, _, runner) = try setup()
        runner.defaultWorkspace = { var w=Workspace(name:"");w.listOptions=DraftListOptions();w.listOptions?.showTags=false;return w }
        #expect(runner.run(action(#"""
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

    @Test func circularIncludesFailBeforeTheFirstSideEffect() throws {
        let (library, _, host, runner) = try setup()
        let a = DraftAction(name:"Cycle A",steps:[ActionStep("clipboard",["text":"should not run"]),ActionStep("includeAction",["name":"Cycle B"])])
        let b = DraftAction(name:"Cycle B",steps:[ActionStep("includeAction",["name":"Cycle A"])])
        try library.saveAction(a);try library.saveAction(b)
        #expect(!runner.run(a));#expect(host.clipboard.isEmpty)
        #expect(runner.message?.contains("itself") == true)
    }

    @Test func failedDraftUpdateDoesNotApplySuccessDisposition() throws {
        let (library, editor, _, runner) = try setup()
        let original=editor.content
        runner.uiOperation = { _ in library.beforeBatchCommit = { throw DraftlyError.message("Storage unavailable") }; return true }
        var a=action("editor.pinningEnabled=true;draft.content='Unsaved';draft.update();")
        a.afterSuccess="archive"
        #expect(!runner.run(a))
        #expect(library.notes.first { $0.id == editor.noteID }?.content == original)
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
        #expect(editor.content == original)
    }

    @Test func draftConveniencesMetadataAndTemplateContracts() throws {
        let (library, editor, _, runner) = try setup()
        #expect(runner.run(action(#"""
        const id=draft.uuid;check(typeof id==='string' && draft.permalink==='draftly://open?uuid='+id,'identity');
        check(draft.createdAt instanceof Date && draft.modifiedAt instanceof Date,'dates');
        check(draft.createdLatitude===0 && draft.createdLongitude===0 && draft.modifiedLatitude===0 && draft.modifiedLongitude===0,'location defaults');
        const d=new Draft();d.content='Title\nBody';d.append('End');d.prepend('Start','|');d.insert('Middle',1);
        check(d.lines[0]==='Start|Title' && d.lines[1]==='Middle','content helpers');
        check(d.linesWithPrefix('Bo')[0]==='Body' && d.bodyPreview(6)==='Middle','body helpers');
        d.tags=['one'];d.addTag(' ONE ');d.addTag('two');d.removeTag('ONE');check(d.tags.join(',')==='two','tags');
        d.isFlagged=true;check(d.isFlagged && d.flagType>0,'flag boolean');d.isFlagged=false;check(d.flagType===0,'clear flag');
        d.languageGrammar='Markdown';check(d.syntax instanceof Syntax,'legacy syntax');
        d.content='# Heading\n[[url:https://example.com]]\n- [ ]task';
        const link=d.linkedItems[0];check(link.key==='url' && link.value==='https://example.com' && link.prefix==='[[' && link.suffix===']]','link shape');
        check(link.location===10 && link.length===27,'link UTF16 range');
        check(d.navigationMarkers[0].prefix==='H1' && d.navigationMarkerAfter(-1).label==='Heading','marker shape');
        check(d.navigationMarkerBefore(1).location===0,'marker before');
        check(d.tasks[0].interactive==='[ ]' && d.tasks[0].label==='task','task shape');
        d.completeTask(d.tasks[0]);check(d.completedTasks.length===1,'complete');d.resetTask(d.tasks[0]);d.advanceTask(d.tasks[0]);
        check(d.incompleteTasks.length===0,'toggle');
        d.setTemplateTag('custom','café');check(d.getTemplateTag('custom')==='café','custom tag');
        check(d.processTemplate('[[custom]]')==='café' && d.processMustacheTemplate('{{custom}}')==='café','both template engines');
        d.update();d.saveVersion();check(d.versions.length>0,'versions');
        check(Draft.find(d.uuid)===d && typeof d.toJSON().content==='string','serialization');
        check(Array.isArray(Draft.recentTags()) && Array.isArray(d.actionLogs),'related records');
        editor.setSelectedRange(2,3);editor.save();editor.new();editor.load(Draft.find(id));
        check(editor.getSelectedRange().join(',')==='2,3' && editor.recentDrafts.length>0,'saved selection');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.contains { $0.id == editor.noteID })
    }

    @Test func taskPaperTasksUseTheirOwnStateRanges() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        draft.syntax='TaskPaper';draft.content='Project:\n- First\n- Second @done';draft.update();
        check(draft.tasks.length===2 && draft.completedTasks.length===1,'TaskPaper states');
        draft.completeTask(draft.tasks[0]);check(draft.completedTasks.length===2,'complete TaskPaper');
        draft.resetTask(draft.tasks[0]);check(draft.incompleteTasks.length===1,'reset TaskPaper');
        draft.update();editor.advanceTask(editor.tasks[0]);check(editor.completedTasks.length===2,'editor TaskPaper');
        check(draft.navigationMarkers[0].label==='Project','TaskPaper project');
        draft.syntax='Plain Text';check(draft.tasks.length===0 && draft.navigationMarkers.length===0,'plain text syntax');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func queryUsesOmittedTagsAscendingOrderAndStableDraftIdentity() throws {
        let (library, _, _, runner) = try setup()
        _ = try library.createNote(content: "Zulu", tags: ["keep"])
        _ = try library.createNote(content: "Alpha", tags: ["keep"])
        _ = try library.createNote(content: "Hidden", tags: ["keep", "omit"])
        #expect(runner.run(action(#"""
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
        let (library, editor, _, runner) = try setup()
        let unknown = try library.createNote(content: "Unknown")
        let older = try library.createNote(content: "Older")
        let newer = try library.createNote(content: "Newer")
        try library.recordAccess(older.id, at: Date(timeIntervalSince1970: 100))
        try library.recordAccess(newer.id, at: Date(timeIntervalSince1970: 200))
        let originalModified = try #require(library.notes.first { $0.id == unknown.id }).modifiedAt
        let originalVersions = library.revisions.filter { $0.noteID == unknown.id }
        var applied: Workspace?
        runner.applyWorkspace = { applied = $0 }
        #expect(runner.run(action(#"""
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
        #expect(runner.run(action("editor.load(Draft.find('\(unknown.id.uuidString)'));")), Comment(rawValue: runner.message ?? ""))
        #expect(editor.noteID == unknown.id)
        let opened = try #require(library.notes.first { $0.id == unknown.id })
        #expect(opened.accessedAt != nil)
        #expect(opened.modifiedAt == originalModified)
        #expect(library.revisions.filter { $0.noteID == unknown.id } == originalVersions)
    }

    @Test func grayFlagAndTrashKeepArchiveState() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action(#"""
        draft.flagType=7;draft.folder='archive';draft.update();
        check(Draft.flagged('gray')[0]===draft,'gray identity');
        draft.folder='trash';draft.update();check(draft.isArchived,'previous archive state');
        draft.folder='archive';draft.update();check(!draft.isTrashed,'restore');
        let caught=[];try{draft.folder='missing';}catch(e){caught.push(e);}
        check(caught.length===1,'invalid folder');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorMutationsKeepCachedDraftAndUnicodeRangesCoherent() throws {
        let (_, editor, _, runner) = try setup()
        #expect(runner.run(action(#"""
        editor.setText('🐼 café\n- [ ] tarea\n# Heading');
        check(draft.content===editor.getText() && editor.draft===draft,'editor draft identity');
        editor.setSelectedRange(3,4);check(editor.getSelectedText()==='café','UTF16 selection');
        check(editor.getTextInRange(0,2)==='🐼','surrogate pair');
        let r=editor.getLineRange(3,4);check(r[0]===0 && r[1]===8,'line expansion');
        editor.setSelectedText('té');check(draft.content.startsWith('🐼 té\n'),'replace selection cache');
        editor.completeTask(editor.tasks[0]);check(editor.completedTasks.length===1,'complete task');
        editor.resetTask(editor.tasks[0]);check(editor.incompleteTasks.length===1,'reset task');
        editor.advanceTask(editor.tasks[0]);check(editor.completedTasks.length===1,'advance task');
        check(editor.navigationMarkers[0].label==='Heading','markers');
        let errors=0;for(let args of [[-1,0],[0,-1],[100,1]]){try{editor.getTextInRange(...args);}catch(e){errors++;}}
        check(errors===3,'range failures');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content.hasPrefix("🐼 té"))
    }

    @Test func workspaceRestoresTypedDatesAndUsesTheSameNativeFilters() throws {
        let (library, _, _, runner) = try setup()
        _ = try library.createNote(content: "Alpha", tags: ["keep"])
        var flagged = try library.createNote(content: "Flagged", tags: ["keep"]); flagged.flag=1; try library.saveNote(flagged)
        var applied: Workspace?
        runner.applyWorkspace = { applied=$0 }
        #expect(runner.run(action(#"""
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

    @Test func finishedStepTimersCannotMutateTheNextStep() throws {
        let (_, _, host, runner) = try setup()
        let value=DraftAction(name:"Timer isolation",steps:[
            ActionStep("script",["allowAsync":"true","script":"var stale=script;setTimeout(()=>app.setClipboard('late'),0);script.complete();"]),
            ActionStep("script",["allowAsync":"true","script":"stale.complete();setTimeout(()=>{app.setClipboard('current');script.complete();},10);"])
        ])
        #expect(runner.runResult(value) == .success)
        #expect(host.clipboard == "current")
        #expect(host.calls.filter { $0.0 == "clipboard" }.count == 1)
    }

    @Test func commonResultDistinguishesFailureCancellationAndSuccess() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.runResult(action("context.cancel();")) == .cancelled)
        #expect(runner.runResult(action("throw new Error('Expected');")) == .failure("Error: Expected"))
        #expect(runner.runResult(action("script.complete();script.complete();",async:true)) == .success)
        #expect(runner.run(action("Draft.query('', 'all', [], [], 'accessed');")))
    }

    @Test func successMetadataIsAppliedOnlyAfterSuccessfulSteps() throws {
        let (library, editor, host, runner) = try setup()
        var value = action("editor.setText('Changed');")
        value.presentation.addTags = ["done"]; value.presentation.removeTags = ["old"]
        value.presentation.flagAfterSuccess = 7; value.presentation.notifyOnSuccess = true
        #expect(runner.run(value))
        #expect(library.notes.first { $0.id == editor.noteID }?.tags == ["done"])
        #expect(library.notes.first { $0.id == editor.noteID }?.flag == 7)
        #expect(host.calls.contains { $0.0 == "actionNotification" })
        value.steps = [ActionStep("script", ["script": "throw new Error('Stop');"])]
        value.presentation.addTags = ["should-not-appear"]; value.presentation.flagAfterSuccess = 1
        #expect(!runner.run(value))
        #expect(library.notes.first { $0.id == editor.noteID }?.tags == ["done"])
        #expect(library.notes.first { $0.id == editor.noteID }?.flag == 7)
    }
    @Test func cancelledConfirmationDoesNotRunStepsAndIsLogged() throws {
        let (library, editor, host, runner) = try setup()
        var value = action("editor.setText('Do not run');")
        value.presentation.confirmBeforeRun = true; host.confirmation = false
        let before = editor.content
        #expect(!runner.run(value))
        #expect(editor.content == before)
        #expect(library.runs.first?.status == "Cancelled")
    }
    @Test func mustacheDirectoryLoadsNamedTemplateAndPartials() throws {
        let (_, _, host, runner) = try setup()
        host.templateFiles = ["/Library/Templates/Letters/main.mustache": "Hello {{name}} {{> footer}}", "/Library/Templates/Letters/footer.mustache": "{{value}}"]
        #expect(runner.run(action("let t=MustacheTemplate.createWithPath('Letters'); t.contentType='text'; check(t.renderTemplate('main',{name:'café',value:'<&'})==='Hello café <&','directory partial');")), Comment(rawValue: runner.message ?? ""))
        #expect(!host.calls.contains { $0.0 == "fileAPI" && $0.1["operation"] as? String == "readString" && $0.1["path"] as? String == "/Library/Templates/Letters" })
    }
    @Test func xmlrpcTransportFailureIsAnExplicitResponse() throws {
        let (_, _, _, runner) = try setup()
        #expect(runner.run(action("let r=XMLRPC.request('invalid','example',[1]); check(!r.success && r.statusCode===0 && r.error && r.params.length===0,'transport failure');")))
    }
    @Test func draftMetadataDatesSyntaxAndQueriesRoundTrip() throws {
        let (library, _, _, runner) = try setup()
        let source = #"""
        let d = Draft.create();
        d.content = '# Meeting\nNotes'; d.addTag(' WORK '); d.flagType = 5;
        d.createdAt = new Date('2020-01-02T03:04:05Z'); d.modifiedAt = new Date('2021-02-03T04:05:06Z');
        d.syntax = Syntax.find('builtIn','Markdown'); d.createdLatitude = 12.5; d.createdLongitude=45;d.modifiedLatitude=11;d.modifiedLongitude=22; d.folder = 'archive'; d.update();
        check(d.title === '# Meeting' && d.displayTitle === 'Meeting', 'titles');
        let found = Draft.queryByTitle('meet')[0];
        check(found.createdAt instanceof Date && found.modifiedAt.getUTCFullYear() === 2021, 'dates');
        check(found.syntax.name === 'Markdown' && found.flagType === 5 && found.folder === 'archive', 'metadata');
        check(found.hasTag('Work') && found.createdLatitude === 12.5 && found.createdLongitude===45 && found.modifiedLatitude===11 && found.modifiedLongitude===22, 'tags and location');
        check(Draft.flagged('blue').length === 1, 'flag query');
        found.folder = 'trash'; found.update();
        check(Draft.query('', 'trash').length === 1, 'trash query');
        """#
        #expect(runner.run(action(source)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.title == "Meeting" }?.trashedAt != nil)
    }
    @Test func workspacePersistsFiltersDatesAndFolderSorts() throws {
        let (library, _, _, runner) = try setup()
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
        #expect(runner.run(action(source)), Comment(rawValue: runner.message ?? ""))
        #expect(library.workspaces.count == 1)
    }
    @Test func versionsTagsAndRecentActionsAreQueryable() throws {
        let (library, editor, _, runner) = try setup()
        let first = action("draft.addTag('old'); draft.update(); draft.saveVersion();")
        try library.saveAction(first)
        #expect(runner.run(first))
        #expect(runner.run(action(#"""
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
    @Test func editorTasksAndLineRangesUseUTF16() throws {
        let (_, editor, _, runner) = try setup("# Heading\n- [ ] Café 😀\n- [x] Done\nTail")
        #expect(runner.run(action(#"""
        check(editor.tasks.length === 2 && editor.incompleteTasks.length === 1, 'task parsing');
        check(editor.navigationMarkers.length === 1 && draft.navigationMarkers[0].location === 0, 'navigation markers');
        let task = editor.incompleteTasks[0]; editor.completeTask(task);
        check(editor.completedTasks.length === 2, 'task completion');
        editor.setSelectedRange(task.labelRange[0],task.labelRange[1]);
        check(editor.getSelectedText() === 'Café 😀', 'UTF16 task range');
        check(editor.getSelectedLineRange()[0] === 10, 'line range');
        let d = Draft.create(); d.content = 'Next'; d.update(); editor.load(d);
        check(editor.recentDrafts[0].displayTitle === 'Heading', 'recent drafts');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "Next")
    }
    @Test func asyncCompletionWaitsAndSharesStateWithNextStep() throws {
        let (_, _, host, runner) = try setup()
        var run = action("let answer; setTimeout(() => { answer = 'ready'; script.complete(); }, 5);", async: true)
        run.steps.append(ActionStep("script", ["script": "app.setClipboard(answer);"]))
        #expect(runner.run(run), Comment(rawValue: runner.message ?? ""))
        #expect(host.clipboard == "ready")
    }
    @Test func asyncPromiseRejectionAndTimeoutStopDisposition() throws {
        let (library, editor, host, runner) = try setup()
        runner.scriptTimeout = 0.02
        var timedOut = action("Promise.resolve('unused');", async: true); timedOut.afterSuccess = "archive"
        timedOut.steps.append(ActionStep("clipboard", ["template": "must not run"]))
        #expect(!runner.run(timedOut))
        #expect(runner.message?.contains("timed out") == true)
        #expect(host.calls.isEmpty)
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
        #expect(!runner.run(action("Promise.reject(new Error('Async failure'));", async: true)))
        #expect(runner.message?.contains("Async failure") == true)
    }
    @Test func includedActionsShareJavaScriptAndDoNotApplyOwnDisposition() throws {
        let (library, editor, host, runner) = try setup()
        var helper = DraftAction(name: "Helper", steps: [ActionStep("script", ["script": "function helper(value) { return value + '!'; }"])]); helper.afterSuccess = "trash"
        try library.saveAction(helper)
        let run = DraftAction(name: "Parent", steps: [ActionStep("includeAction", ["name": "Helper"]), ActionStep("script", ["script": "app.setClipboard(helper('works'));"])])
        #expect(runner.run(run), Comment(rawValue: runner.message ?? ""))
        #expect(host.clipboard == "works!")
        #expect(library.notes.first { $0.id == editor.noteID }?.trashedAt == nil)
    }
    @Test func includedUnknownStepIsRejectedBeforeAnySideEffect() throws {
        let (library, _, host, runner) = try setup()
        try library.saveAction(DraftAction(name: "Unknown", steps: [ActionStep("future")]))
        let run = DraftAction(name: "Parent", steps: [ActionStep("clipboard", ["template": "must not run"]), ActionStep("includeAction", ["name": "Unknown"])])
        #expect(!runner.run(run)); #expect(host.calls.isEmpty)
    }
    @Test func disabledUnknownStepsSurviveImportAndDoNotBlockExecution() throws {
        let (_, _, host, runner) = try setup()
        let data = Data(#"{"name":"Disabled","steps":[{"type":"future","isEnabled":false,"data":{"key":"keep"}},{"type":"clipboard","data":{"template":"ready"}}]}"#.utf8)
        let run = try #require(ActionImporter.decode(data).first)
        #expect(run.steps.count == 2 && run.steps[0].isEnabled == false)
        #expect(runner.run(run)); #expect(host.clipboard == "ready")
    }
    @Test func callbackAndPreviewResponsesReachLaterSteps() throws {
        let (_, _, host, runner) = try setup()
        var run = action(#"""
        let cb = CallbackURL.create(); cb.baseURL = 'example://run'; cb.addParameter('text','a+b & café');
        check(cb.url.includes('%2B') || cb.url.includes('a+b'), 'callback query');
        check(cb.open() && cb.callbackResponse.result === 'Returned + café', 'callback response');
        let preview = HTMLPreview.create(); check(preview.show('<b>Preview</b>'), 'preview success');
        check(context.previewValues.answer.value === 42, 'preview values');
        check(context.callbackResponses[0].result === 'Returned + café', 'callback context');
        """#)
        run.steps.append(ActionStep("clipboard", ["template": "[[callback_result]]"]))
        #expect(runner.run(run), Comment(rawValue: runner.message ?? "")); #expect(host.clipboard == "Returned + café")
        host.previewSuccess = false
        #expect(runner.run(action("if (!HTMLPreview.create().show('cancel')) context.cancel();")) == false)
    }
    @Test func promptValuesRetainNativeTypesAndRequireLoadsHelpers() throws {
        let (_, _, host, runner) = try setup()
        #expect(runner.run(action(#"""
        let p = Prompt.create(); p.addDatePicker('date','Date',new Date('2020-01-02T03:04:05Z'));
        p.addNumberField('count','Count',2,true); p.addSwitch('flag','Flag',true); p.addSelect('tags','Tags',['a','b'],['a','b'],true); p.addButton('Use',42);
        check(p.show() && p.buttonPressed === 42, 'prompt button value');
        check(p.fieldValues.date instanceof Date && p.fieldValues.count === 2 && p.fieldValues.flag === true && p.fieldValues.tags.length === 2, 'prompt types');
        require('helpers'); app.setClipboard(loadedHelper('loaded'));
        """#)), Comment(rawValue: runner.message ?? "")); #expect(host.clipboard == "LOADED")
    }
    @Test func templateRangesEscapesDatesAndMarkup() {
        let note = Note(content: "# Title\nOne\nTwo\nThree")
        let value = Templates.render(#"[[title]]|[[display_title]]|[[line|2..-1]]|[[selection]]|\[[title]]|{{a+b & café}}"#, note: note)
        #expect(value == "# Title|Title|One\nTwo\nThree|# Title\nOne\nTwo\nThree|[[title]]|a%2Bb%20%26%20caf%C3%A9")
        #expect(Templates.render("[[date|+1 day|%Y-%m-%d]]", note: note, now: Date(timeIntervalSince1970: 0)).contains("1970-01-0"))
        #expect(Templates.render("[[line|..2]]", note: note) == "# Title\nOne")
    }
    @Test func mustacheUsesNestedContextsAndEscaping() throws {
        let data: [String: Any] = ["name": "<World>", "items": [["value": "one"], ["value": "two"]]]
        let rendered = try MustacheRenderer.render("{{name}}|{{{name}}}|{{#items}}{{value}}/{{name}};{{/items}}{{^missing}}empty{{/missing}}", data: data)
        #expect(rendered == "&lt;World&gt;|<World>|one/&lt;World&gt;;two/&lt;World&gt;;empty")
    }
    @Test func markdownEnginesRenderRepeatedDocuments() throws {
        for _ in 0..<20 {
            let multi = try ScriptMarkdown.render("# Heading\n\nText[^1]\n\n[^1]: Footnote", engine: "multi")
            #expect(multi.contains("<h1") && multi.contains("Footnote"))
            let github = try ScriptMarkdown.render("- [x] Done\n\n~~Removed~~", engine: "github")
            #expect(github.contains("checkbox") && github.contains("<del>Removed</del>"))
        }
    }
    @Test func cancellingAnActionStopsItsQueue() throws {
        let (library, _, host, runner) = try setup()
        let next = action("app.setClipboard('must not run');")
        try library.saveAction(next)
        #expect(!runner.run(action("app.queueAction(Action.find('API contract'), draft); context.cancel();")))
        #expect(host.clipboard.isEmpty)
    }
    @Test func cancellingAQueuedActionStopsLaterActions() throws {
        let (library, _, host, runner) = try setup()
        var cancel = action("context.cancel();"); cancel.name = "Cancel queued"
        var next = action("app.setClipboard('must not run');"); next.name = "After cancellation"
        try library.saveAction(cancel); try library.saveAction(next)
        #expect(!runner.run(action("app.queueAction(Action.find('Cancel queued'), draft); app.queueAction(Action.find('After cancellation'), draft);")))
        #expect(host.clipboard.isEmpty)
    }
}
