import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class DraftVersionHost: ActionHost {
    var onClipboard: ((String) throws -> Void)?
    var clipboard = ""
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        switch operation {
        case "clipboard":
            let text = values["text"] as? String ?? ""
            try onClipboard?(text)
            clipboard = text
            return true
        case "actionNotification": return true
        default: throw DraftlyError.message("Unexpected version test operation: " + operation)
        }
    }
}

@MainActor private struct DraftVersionFixture {
    let library: LibraryStore
    let editor: EditorSession
    let host: DraftVersionHost
    let runner: ActionRunner
    let note: Note

    init(directory: URL? = nil) throws {
        library = try LibraryStore(inMemory: directory == nil, directory: directory, seed: false)
        editor = EditorSession()
        host = DraftVersionHost()
        var source = Note(content: "Version source", createdAt: Date(timeIntervalSince1970: 1_000),
                          modifiedAt: Date(timeIntervalSince1970: 2_000), accessedAt: Date(timeIntervalSince1970: 3_000))
        source.scriptMetadata = ["selectionStart": "2", "selectionLength": "3"]
        note = source
        try library.saveNote(source, preserveRevision: false, preserveDates: true)
        editor.load(source)
        runner = ActionRunner(library: library, editor: editor, host: host)
    }

    func action(_ script: String) -> DraftAction {
        ScriptTestAction.make(script, name: "Draft version contract")
    }

    func run(_ script: String) -> Bool { runner.run(action(script)) }

    func restoredLibrary() throws -> LibraryStore {
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        return restored
    }
}

@Suite("Draft version member contracts") @MainActor
struct DraftVersionContractTests {
    @Test func draftSaveVersionReturnsVoidAndSnapshotsPendingContentWithoutUpdatingDraft() throws {
        let f = try DraftVersionFixture()
        let selection = f.editor.selection
        #expect(f.run(#"""
        const stored=editor.getText(),modified=draft.modifiedAt.getTime();
        check(draft.versions.length===0,'initial empty history');
        draft.content='Pending 🐼 cafe\u0301\r\nSecond line';
        check(draft.saveVersion()===undefined,'void return');
        const version=draft.versions[0];
        check(version instanceof Version && version.content===draft.content,'current pending content snapshot');
        check(editor.getText()===stored && draft.modifiedAt.getTime()===modified,'no implicit draft update');
        draft.content='Later local text';
        check(version.content==='Pending 🐼 cafe\u0301\r\nSecond line','snapshot does not follow local changes');
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.revisions.map(\.content) == ["Pending 🐼 cafe\u{301}\r\nSecond line"])
        #expect(f.editor.content == f.note.content)
        let stored = try #require(f.library.notes.first { $0.id == f.note.id })
        #expect(stored == f.note)
        #expect(f.editor.selection == selection)
    }

    @Test func draftSaveVersionAcceptsEmptyContentAndCreatesIndependentVersionsEveryTime() throws {
        let f = try DraftVersionFixture()
        let earliest = Date()
        #expect(f.run(#"""
        draft.content='';
        draft.saveVersion();draft.saveVersion();
        const versions=draft.versions;
        check(versions.length===2 && versions.every(v=>v.content===''),'empty snapshots are not deduplicated');
        check(versions[0].uuid!==versions[1].uuid,'new identity for each save');
        for(const v of versions){
          check(v.createdAt instanceof Date,'typed new timestamp');
          check(v.createdAt.getTime()!==draft.createdAt.getTime(),'version date is not inherited');
        }
        """#), Comment(rawValue: f.runner.message ?? ""))
        let latest = Date()
        #expect(f.library.revisions.count == 2)
        #expect(Set(f.library.revisions.map(\.id)).count == 2)
        #expect(f.library.revisions.allSatisfy { $0.date >= earliest && $0.date <= latest })
        let restored = try f.restoredLibrary()
        #expect(restored.revisions == f.library.revisions)
    }

    @Test func draftVersionsReturnsAllOwnVersionsNewestFirstAndCannotBeAssigned() throws {
        let f = try DraftVersionFixture()
        let other = try f.library.createNote(content: "Other draft")
        var first = Revision(noteID: f.note.id, content: "Oldest")
        first.date = Date(timeIntervalSince1970: 10_000.125)
        var second = Revision(noteID: f.note.id, content: "Middle")
        second.date = Date(timeIntervalSince1970: 20_000.5)
        var third = Revision(noteID: f.note.id, content: "Newest")
        third.date = Date(timeIntervalSince1970: 30_000.75)
        try f.library.saveRevision(second)
        try f.library.saveRevision(first)
        try f.library.saveRevision(third)
        try f.library.saveRevision(Revision(noteID: other.id, content: "Other history"))

        #expect(f.run(#"""
        const versions=draft.versions;
        check(Array.isArray(versions) && versions.length===3,'all own versions');
        check(versions.map(v=>v.content).join(',')==='Newest,Middle,Oldest','newest first');
        check(versions.map(v=>v.createdAt.getTime()).join(',')==='30000750,20000500,10000125','stored timestamps');
        check(versions.every(v=>v instanceof Version && v.draft===draft),'typed values and owning draft');
        check(Reflect.set(draft,'versions',[])===false,'readonly history property');
        versions.pop();check(draft.versions.length===3,'mutating a returned array does not delete history');
        """#), Comment(rawValue: f.runner.message ?? ""))
        let restored = try f.restoredLibrary()
        #expect(restored.revisions.filter { $0.noteID == f.note.id }.map(\.id) == [third.id, second.id, first.id])
    }

    @Test func versionPropertiesHaveStableReadOnlyValuesAndTheCurrentDraftRelation() throws {
        let f = try DraftVersionFixture()
        var version = Revision(noteID: f.note.id, content: "Snapshot 🐼\nQuoted \"text\"")
        version.date = Date(timeIntervalSince1970: 1_600_000_000.125)
        try f.library.saveRevision(version)

        #expect(f.run(#"""
        const v=draft.versions[0],id=v.uuid;
        check(typeof id==='string' && /^[0-9a-f-]{36}$/i.test(id),'version UUID');
        check(v.content==='Snapshot 🐼\nQuoted "text"','stored content');
        check(v.createdAt instanceof Date && v.createdAt.getTime()===1600000000125,'stored creation date');
        check(v.draft===draft && v.draft===Draft.find(draft.uuid),'shared draft identity');
        check(Reflect.set(v,'uuid','different')===false,'readonly uuid');
        check(Reflect.set(v,'content','different')===false,'readonly content');
        check(Reflect.set(v,'createdAt',new Date(0))===false,'readonly timestamp');
        check(Reflect.set(v,'draft',Draft.create())===false,'readonly relation');
        draft.content='Current local changes';
        check(v.draft.content===draft.content && v.content!=='Current local changes','current relation and fixed snapshot');
        const again=draft.versions.find(candidate=>candidate.uuid===id);
        check(again.content===v.content && again.createdAt.getTime()===v.createdAt.getTime(),'stable reread values');
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.revisions == [version])
    }

    @Test func versionDeleteReturnsVoidAndPersistsOnlyTheChosenDeletion() throws {
        let f = try DraftVersionFixture()
        let removed = Revision(noteID: f.note.id, content: "Remove snapshot")
        let kept = Revision(noteID: f.note.id, content: "Keep snapshot")
        try f.library.saveRevision(removed)
        try f.library.saveRevision(kept)

        #expect(f.run(#"""
        const selected=draft.versions.find(v=>v.content==='Remove snapshot');
        check(selected.delete()===undefined,'void delete result');
        check(draft.versions.length===1 && draft.versions[0].content==='Keep snapshot','only selected version deleted');
        check(editor.getText()==='Version source' && draft.content==='Version source','draft content is unchanged');
        """#), Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.revisions == [kept])
        let restored = try f.restoredLibrary()
        #expect(restored.revisions == [kept])
        #expect(restored.notes.first { $0.id == f.note.id }?.content == f.note.content)
    }

    @Test func draftSaveVersionFailureThrowsStopsTheScriptAndDoesNotLeakOnLaterCommit() throws {
        let f = try DraftVersionFixture()
        let original = Revision(noteID: f.note.id, content: "Existing snapshot")
        try f.library.saveRevision(original)
        let library = f.library
        f.host.onClipboard = { _ in library.beforeBatchCommit = { throw DraftlyError.message("Version storage failure") } }
        defer { library.beforeBatchCommit = nil }

        let result = f.runner.runResult(f.action(#"""
        app.setClipboard('Arm version failure');draft.content='Failed snapshot must not survive';
        draft.saveVersion();app.setClipboard('Later statement must not run');
        """#))

        #expect(result == .failure("Error: Version storage failure"))
        #expect(f.host.clipboard == "Arm version failure")
        #expect(library.revisions == [original])
        #expect(f.editor.content == f.note.content)
        library.beforeBatchCommit = nil
        try library.saveNote(Note(content: "Unrelated successful save"), preserveRevision: false)
        #expect(library.revisions == [original])
        let restored = try f.restoredLibrary()
        #expect(restored.revisions == [original])
        #expect(!restored.revisions.contains { $0.content == "Failed snapshot must not survive" })
    }

    @Test func saveRevisionFailureRollsBackAnExistingSnapshotBeforeTheNextSave() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Source")
        let original = Revision(noteID: note.id, content: "Original snapshot")
        try library.saveRevision(original)
        let before = library.revisions
        var replacement = original
        replacement.content = "Rejected replacement"
        replacement.date = Date(timeIntervalSince1970: 1)
        library.beforeBatchCommit = { throw DraftlyError.message("Revision replacement failure") }

        #expect(throws: DraftlyError.self) { try library.saveRevision(replacement) }
        #expect(library.revisions == before)
        library.beforeBatchCommit = nil
        try library.saveNote(Note(content: "Unrelated commit"), preserveRevision: false)
        #expect(library.revisions == before)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.revisions == before)
    }

    @Test func versionDeleteFailureThrowsAndPreservesHistoryAfterAnUnrelatedCommit() throws {
        let f = try DraftVersionFixture()
        let version = Revision(noteID: f.note.id, content: "Keep after failed deletion")
        try f.library.saveRevision(version)
        let library = f.library
        f.host.onClipboard = { _ in library.beforeBatchCommit = { throw DraftlyError.message("Version deletion failure") } }
        defer { library.beforeBatchCommit = nil }

        let result = f.runner.runResult(f.action(#"""
        const v=draft.versions[0];app.setClipboard('Arm deletion failure');
        v.delete();app.setClipboard('Later statement must not run');
        """#))

        #expect(result == .failure("Error: Version deletion failure"))
        #expect(f.host.clipboard == "Arm deletion failure")
        #expect(library.revisions == [version])
        library.beforeBatchCommit = nil
        try library.saveNote(Note(content: "Unrelated successful save"), preserveRevision: false)
        let restored = try f.restoredLibrary()
        #expect(restored.revisions == [version])
        #expect(restored.notes.first { $0.id == f.note.id }?.content == f.note.content)
    }

    @Test func draftSaveVersionPersistsSnapshotsAndRollsBackFailedSaveAcrossReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DraftVersionContract-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source: Note
        let savedVersions: [Revision]
        do {
            let f = try DraftVersionFixture(directory: folder)
            source = f.note
            let selection = f.editor.selection
            #expect(f.run(#"""
            draft.content='Disk snapshot 🐼\r\nPending content';draft.saveVersion();
            """#), Comment(rawValue: f.runner.message ?? ""))
            savedVersions = f.library.revisions
            #expect(savedVersions.count == 1 && savedVersions[0].content == "Disk snapshot 🐼\r\nPending content")
            #expect(f.library.notes.first { $0.id == source.id } == source)
            #expect(f.editor.content == source.content && f.editor.selection == selection)

            let library = f.library
            f.host.onClipboard = { _ in library.beforeBatchCommit = { throw DraftlyError.message("Disk revision failure") } }
            let result = f.runner.runResult(f.action(#"""
            app.setClipboard('Arm disk failure');draft.content='Must not appear after reopening';
            draft.saveVersion();app.setClipboard('Must not run');
            """#))
            #expect(result == .failure("Error: Disk revision failure"))
            #expect(f.host.clipboard == "Arm disk failure")
            #expect(library.revisions == savedVersions)
            #expect(library.notes.first { $0.id == source.id } == source)
            #expect(f.editor.content == source.content && f.editor.selection == selection)
            library.beforeBatchCommit = nil
            try library.saveNote(Note(content: "Independent disk commit"), preserveRevision: false)
        }

        let reopened = try LibraryStore(directory: folder, seed: false)
        #expect(reopened.revisions == savedVersions)
        #expect(reopened.notes.first { $0.id == source.id } == source)
        #expect(reopened.notes.contains { $0.content == "Independent disk commit" })
        #expect(!reopened.revisions.contains { $0.content == "Must not appear after reopening" })
    }
}
