import Foundation
import Testing
@testable import DraftlyCore

@Suite("Version scripting API") @MainActor
struct VersionActionAPITests {
    @Test func versionContentIsAnImmutableSnapshot() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        try library.saveRevision(Revision(noteID: try #require(editor.noteID), content: "Saved 🐼\n\"café\""))
        #expect(runner.run(makeAPIAction(#"""
        const v=draft.versions.find(x=>x.content==='Saved 🐼\n"café"');check(v instanceof Version,'version type');
        check(Reflect.set(v,'content','Changed')===false,'read-only content');
        editor.setText('New editor content');draft.update();
        check(v.content==='Saved 🐼\n"café"','snapshot independent of current content');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func versionUUIDIsStableUniqueAndReadOnly() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        let id = try #require(editor.noteID)
        try library.saveRevision(Revision(noteID: id, content: "Version A"))
        try library.saveRevision(Revision(noteID: id, content: "Version B"))
        #expect(runner.run(makeAPIAction(#"""
        const a=draft.versions.find(x=>x.content==='Version A'),b=draft.versions.find(x=>x.content==='Version B');
        check(typeof a.uuid==='string' && /^[0-9a-f-]{36}$/i.test(a.uuid),'UUID format');
        check(a.uuid!==b.uuid,'unique UUID');check(Reflect.set(a,'uuid','other')===false,'read-only identity');
        check(draft.versions.find(x=>x.uuid===a.uuid).content==='Version A','stable identity');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func versionDraftUsesCurrentCachedIdentityAndMissingDraftIsUndefined() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        try library.saveRevision(Revision(noteID: try #require(editor.noteID), content: "Related version"))
        #expect(runner.run(makeAPIAction(#"""
        const v=draft.versions.find(x=>x.content==='Related version');check(v.draft===draft,'cached draft identity');
        draft.content='Pending draft edit';check(v.draft.content==='Pending draft edit','pending changes visible');
        check(Reflect.set(v,'draft',Draft.create())===false,'read-only draft relation');
        check(new Version({uuid:'orphan',draftUUID:'00000000-0000-0000-0000-000000000000',content:'Orphan',createdAt:new Date()}).draft===undefined,'missing relation');
        """#)), Comment(rawValue: runner.message ?? ""))
    }


}
