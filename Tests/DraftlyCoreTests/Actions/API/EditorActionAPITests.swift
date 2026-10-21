import Foundation
import Testing
@testable import DraftlyCore

@Suite("Editor scripting API") @MainActor
struct EditorActionAPITests {
    @Test func editorSetSelectedRangeReturnsVoidAndRejectsInvalidUTF16Ranges() throws {
        let (_, editor, _, runner) = try makeAPIContext("🐼 café")
        #expect(runner.run(makeAPIAction(#"""
        check(editor.setSelectedRange(0,2)===undefined,'void');check(editor.getSelectedText()==='🐼','UTF16');
        for(const r of [[-1,0],[0,-1],[8,0],[0,8],[0.5,1],[NaN,0]]){let failed=false;try{editor.setSelectedRange(...r);}catch(e){failed=e instanceof RangeError;}check(failed,'invalid range');check(editor.getSelectedRange().join(',')==='0,2','preserved range');}
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.selection == NSRange(location: 0, length: 2))
    }

    @Test func editorSetSelectedTextReturnsVoidAndUpdatesCachedDraftAndStorage() throws {
        let (library, editor, _, runner) = try makeAPIContext("🐼 café")
        #expect(runner.run(makeAPIAction(#"""
        const cached=editor.draft;editor.setSelectedRange(0,2);check(editor.setSelectedText('🌿')===undefined,'void');
        check(editor.getText()==='🌿 café' && cached.content===editor.getText(),'cached content');
        check(editor.getSelectedRange().join(',')==='2,0','cursor after replacement');
        editor.setSelectedText('');check(editor.getText()==='🌿 café','empty insertion');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.id == editor.noteID }?.content == "🌿 café")
    }

    @Test func editorSetTextInRangeReturnsVoidAndRejectsInvalidRanges() throws {
        let (_, _, _, runner) = try makeAPIContext("🐼 café")
        #expect(runner.run(makeAPIAction(#"""
        const cached=editor.draft;check(editor.setTextInRange(3,4,'té')===undefined,'void');
        check(editor.getText()==='🐼 té' && cached.content==='🐼 té','replacement');
        check(editor.getSelectedRange().join(',')==='5,0','replacement cursor');
        for(const r of [[-1,0],[0,99],[0.5,1]]){let failed=false;try{editor.setTextInRange(...r,'bad');}catch(e){failed=e instanceof RangeError;}check(failed,'invalid');check(editor.getText()==='🐼 té','unchanged after error');}
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorGetTextInRangeReturnsExactUTF16SubstringsWithoutChangingSelection() throws {
        let (_, _, _, runner) = try makeAPIContext("🐼 café")
        #expect(runner.run(makeAPIAction(#"""
        editor.setSelectedRange(3,4);check(editor.getTextInRange(0,2)==='🐼','emoji');check(editor.getTextInRange(7,0)==='','empty end');
        check(editor.getSelectedRange().join(',')==='3,4','selection preserved');
        let failed=false;try{editor.getTextInRange(6,2);}catch(e){failed=e instanceof RangeError;}check(failed,'invalid range');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorSetTextReturnsVoidAndUpdatesAllCurrentReferences() throws {
        let (library, editor, _, runner) = try makeAPIContext("Original")
        #expect(runner.run(makeAPIAction(#"""
        const cached=editor.draft;editor.setSelectedRange(8,0);check(editor.setText('🐼')===undefined,'void');
        check(editor.getText()==='🐼' && cached.content==='🐼' && draft.content==='🐼','all current references');
        check(editor.getSelectedRange().join(',')==='2,0','clamped selection');editor.setText('');check(editor.getText()==='' && cached.content==='','empty replacement');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.id == editor.noteID }?.content == "")
    }

    @Test func editorGetTextReturnsCurrentUnicodeContentIncludingEmptyText() throws {
        let (_, _, _, runner) = try makeAPIContext("🐼 café\r\n日本語")
        #expect(runner.run(makeAPIAction(#"""
        check(editor.getText()==='🐼 café\r\n日本語','exact current text');editor.setText('');check(editor.getText()==='','empty text');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorNewReturnsVoidAndPreservesThePreviousDraft() throws {
        let (library, editor, _, runner) = try makeAPIContext("Previous 🐼")
        let original = try #require(editor.noteID)
        #expect(runner.run(makeAPIAction(#"""
        const previous=editor.draft;editor.setSelectedRange(0,8);check(editor.new()===undefined,'void');
        check(editor.getText()==='' && editor.getSelectedRange().join(',')==='0,0','new empty editor');
        check(editor.draft.uuid!==previous.uuid && editor.draft.folder==='inbox','new identity and folder');
        check(previous.selectionStart===0 && previous.selectionLength===8,'previous selection');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.noteID != original)
        #expect(library.notes.first { $0.id == original }?.content == "Previous 🐼")
    }

    @Test func editorNewSaveFailureKeepsTheCurrentDraftAndPendingText() throws {
        let (library, editor, host, runner) = try makeAPIContext("Stored")
        let originalID = editor.noteID
        host.onPerform = { op in if op == "clipboard" { editor.content = "Pending 🐼"; library.beforeBatchCommit = { throw DraftlyError.message("New editor save failure") } } }
        defer { library.beforeBatchCommit = nil }
        #expect(!runner.run(makeAPIAction("app.setClipboard('Arm');editor.new();")))
        #expect(runner.message?.contains("New editor save failure") == true)
        #expect(editor.noteID == originalID && editor.content == "Pending 🐼")
        #expect(library.notes.count == 1)
    }

    @Test func editorTextMutationsKeepPendingTextAndReportStorageFailure() throws {
        for mutation in ["editor.setText('Pending 🐼')", "editor.setSelectedText('Pending 🐼')", "editor.setTextInRange(0,8,'Pending 🐼')"] {
            let (library, editor, host, runner) = try makeAPIContext("Original")
            host.onPerform = { op in if op == "clipboard" { library.beforeBatchCommit = { throw DraftlyError.message("Mutation storage failure") } } }
            #expect(!runner.run(makeAPIAction("editor.setSelectedRange(0,8);app.setClipboard('Arm');\(mutation);app.setClipboard('Must not run');")))
            #expect(runner.message?.contains("Mutation storage failure") == true)
            #expect(editor.content == "Pending 🐼" && host.clipboard == "Arm")
            library.beforeBatchCommit = nil
        }
    }

    @Test func editorSaveReturnsVoidAndPreservesPendingTextOnFailure() throws {
        let (library, editor, host, runner) = try makeAPIContext("Stored")
        #expect(runner.run(makeAPIAction("check(editor.save()===undefined,'void');")))
        host.onPerform = { op in if op == "clipboard" { editor.content = "Pending 🐼"; library.beforeBatchCommit = { throw DraftlyError.message("Editor save failure") } } }
        defer { library.beforeBatchCommit = nil }
        #expect(!runner.run(makeAPIAction("app.setClipboard('Arm');editor.save();app.setClipboard('Must not run');")))
        #expect(runner.message?.contains("Editor save failure") == true)
        #expect(editor.content == "Pending 🐼" && host.clipboard == "Arm")
    }

    @Test func editorLoadRejectsUnsavedDraftWithoutChangingTheCurrentDraft() throws {
        let (_, editor, _, runner) = try makeAPIContext("Current 🐼")
        let originalID = editor.noteID
        #expect(!runner.run(makeAPIAction("const unsaved=Draft.create();unsaved.content='Not stored';editor.load(unsaved);")))
        #expect(runner.message?.contains("Save the draft before loading") == true)
        #expect(editor.noteID == originalID && editor.content == "Current 🐼")
    }

    @Test func editorLoadSaveFailureKeepsPendingTextAndDoesNotOpenTheTarget() throws {
        let (library, editor, host, runner) = try makeAPIContext("Stored source")
        let originalID = editor.noteID
        let target = try library.createNote(content: "Target remains intact")
        host.onPerform = { operation in
            if operation == "clipboard" {
                editor.content = "Pending source 🐼"
                library.beforeBatchCommit = { throw DraftlyError.message("Pending editor save failure") }
            }
        }
        defer { library.beforeBatchCommit = nil }
        #expect(!runner.run(makeAPIAction("const target=Draft.find('\(target.id.uuidString)');app.setClipboard('Arm');editor.load(target);")))
        #expect(runner.message?.contains("Pending editor save failure") == true)
        #expect(editor.noteID == originalID && editor.content == "Pending source 🐼")
        #expect(library.notes.first { $0.id == target.id }?.content == target.content)
    }

    @Test func editorGetLineRangeMatchesNativeUTF16Boundaries() throws {
        let (_, _, _, runner) = try makeAPIContext()
        let fixtures: [(String, [[Int]])] = [
            ("", [[0,0,0,0]]),
            ("🐼 café\nNext\n", [[0,0,0,8],[2,0,0,8],[7,0,0,8],[8,0,8,5],[0,8,0,8],[7,1,0,8],[7,2,0,13],[8,4,8,5],[13,0,13,0]]),
            ("A\rB", [[0,0,0,2],[1,0,0,2],[2,0,2,1],[3,0,2,1]]),
            ("A\r\nB", [[0,0,0,3],[1,0,0,3],[2,0,0,3],[3,0,3,1],[4,0,3,1],[0,3,0,3],[2,2,0,4]]),
            ("A\u{2028}B\u{2029}C", [[0,0,0,2],[2,0,2,2],[4,0,4,1],[5,0,4,1],[1,2,0,4]])]
        for (text, cases) in fixtures {
            let input = String(decoding: try JSONSerialization.data(withJSONObject: [text]), as: UTF8.self)
            let expected = String(decoding: try JSONSerialization.data(withJSONObject: cases), as: UTF8.self)
            #expect(runner.run(makeAPIAction("editor.setText(\(input)[0]);check(editor.getLineRange(0).join(',')===editor.getLineRange(0,0).join(','),'omitted length');for(const [p,n,start,size] of \(expected)){const r=editor.getLineRange(p,n);check(r[0]===start && r[1]===size,'native line '+p+','+n);}")), Comment(rawValue: runner.message ?? ""))
        }
    }

    @Test func editorGetSelectedLineRangeUsesCurrentSelectionAndPreservesIt() throws {
        let (_, editor, _, runner) = try makeAPIContext("A\r\n🐼 café\r\nEnd")
        #expect(runner.run(makeAPIAction(#"""
        editor.setSelectedRange(3,2);const r=editor.getSelectedLineRange();
        check(r[0]===3 && r[1]===9,'selected CRLF line');
        check(editor.getSelectedRange().join(',')==='3,2','selection unchanged');
        editor.setSelectedRange(editor.getText().length,0);check(editor.getSelectedLineRange().join(',')==='12,3','last line');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "A\r\n🐼 café\r\nEnd")
    }

    @Test func editorGetSelectedRangeReturnsACopyInUTF16Units() throws {
        let (_, _, _, runner) = try makeAPIContext("🐼 café")
        #expect(runner.run(makeAPIAction(#"""
        editor.setSelectedRange(0,2);const r=editor.getSelectedRange();check(r.join(',')==='0,2','UTF16 range');
        r[0]=99;check(editor.getSelectedRange().join(',')==='0,2','independent range');
        editor.setSelectedRange(7,0);check(editor.getSelectedRange().join(',')==='7,0','empty end range');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorGetSelectedTextReturnsUnicodeAndEmptySelection() throws {
        let (_, _, _, runner) = try makeAPIContext("🐼 café")
        #expect(runner.run(makeAPIAction(#"""
        editor.setSelectedRange(0,2);check(editor.getSelectedText()==='🐼','emoji selection');
        editor.setSelectedRange(3,4);check(editor.getSelectedText()==='café','accent selection');
        editor.setSelectedRange(7,0);check(editor.getSelectedText()==='','empty selection');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func invalidRangesAndQueriesFailWithoutChangingTheEditor() throws {
        let (_, editor, _, runner) = try makeAPIContext("🐼 café\nLine")
        let original = editor.content
        #expect(runner.run(makeAPIAction(#"""
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

    @Test(arguments: [false, true])
    func editorInterfaceMembersDelegateWithoutLosingArguments(worker: Bool) async throws {
        let (_, _, _, runner) = try makeAPIContext()
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
        let action = makeAPIAction(#"""
        check(editor.isActive && editor.preferredTabString==='\t','read-only UI properties');
        for(let key of ['linkModeEnabled','pinningEnabled','focusModeEnabled','typewriterScrollingEnabled']){
            editor[key]=true;check(editor[key]===true,key);
        }
        check(editor.activate()===undefined && editor.deactivate()===undefined,'activation returns void');
        check(editor.showFind(true,'café')===undefined,'showFind returns void');
        for(const name of ['showArrange','showDictate','nextDraft','previousDraft','undo','redo']) {
            check(editor[name]()===undefined,name+' returns void');
        }
        check(editor.arrange('Text')==='Returned','arrange return');
        check(editor.dictate('es-AR')==='Returned','dictation return');
        check(editor.scanDocument()==='Returned' && editor.transcribe()==='Returned','input returns');
        """#)
        let succeeded: Bool
        if worker { succeeded = await runner.runAsync(action).result.succeeded }
        else { succeeded = runner.run(action) }
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
        #expect(calls.contains { $0["operation"] as? String == "showFind" && ($0["args"] as? [Any])?.last as? String == "café" })
        #expect(calls.contains { $0["operation"] as? String == "dictate" && ($0["args"] as? [String]) == ["es-AR"] })
    }

    @Test func editorMutationsKeepCachedDraftAndUnicodeRangesCoherent() throws {
        let (_, editor, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
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
}
