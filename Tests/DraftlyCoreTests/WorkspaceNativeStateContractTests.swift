import Foundation
import Testing
@testable import DraftlyCore

@Suite("Workspace native state bridge") @MainActor
struct WorkspaceNativeStateContractTests {
    @Test(arguments: [false, true])
    func createKeepsDefaultNativeSettingsWithANewIdentity(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        let preferences = try TestPreferences()
        defer { preferences.close() }
        var original = Workspace(name: "Default source")
        original.order = 9; original.tagged = false
        var options = DraftListOptions()
        options.previewLines = 1; options.searchTitlesOnly = true
        options.caseSensitiveSearch = true; options.highlightFlagged = true
        original.listOptions = options; original.scriptMetadata = ["future": "Café 🐼"]
        try library.saveWorkspace(original)
        preferences.defaults.set(original.id.uuidString, forKey: WorkspaceDefaults.key)
        runner.defaultWorkspace = { WorkspaceDefaults.make(in: library, defaults: preferences.defaults) }
        let action = makeAPIAction("const w=Workspace.create();w.name='Default copy';w.update();")
        let succeeded: Bool
        if worker { succeeded = await runner.runAsync(action).result.succeeded }
        else { succeeded = runner.run(action) }
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
        let copy = try #require(library.workspaces.first { $0.name == "Default copy" })
        #expect(copy.id != original.id && copy.order == nil)
        #expect(copy.tagged == original.tagged && copy.listOptions == original.listOptions)
        #expect(copy.scriptMetadata?["future"] == original.scriptMetadata?["future"])
        #expect(library.workspaces.contains(original))
    }

    @Test(arguments: [false, true])
    func malformedNativeStateCannotPartiallyReplaceASavedWorkspace(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        var original = Workspace(name: "Keep native state")
        original.order = 5; original.tagged = true
        try library.saveWorkspace(original)
        let action = makeAPIAction(#"""
        const w=Workspace.find('Keep native state');w.name='Must not save';
        for(const invalid of [17,'{invalid']){
            w._draftlyNative=invalid;let failed=false;
            try{w.update()}catch(e){failed=true}
            check(failed,'reject malformed native state');
        }
        """#)
        let succeeded: Bool
        if worker { succeeded = await runner.runAsync(action).result.succeeded }
        else { succeeded = runner.run(action) }
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
        #expect(library.workspaces == [original])
    }

    @Test(arguments: [false, true])
    func currentSnapshotAppliesScriptChangesOverTheRetainedNativeState(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        var snapshot = Workspace(name: "Current native snapshot")
        snapshot.tagged = false; snapshot.order = 4
        var options = DraftListOptions()
        options.previewLines = 3; options.searchTitlesOnly = true
        options.caseSensitiveSearch = true; options.highlightFlagged = true
        snapshot.listOptions = options
        runner.currentWorkspace = { snapshot }
        var applied: [Workspace] = []
        runner.applyWorkspace = { applied.append($0) }
        let action = makeAPIAction(#"""
        const w=app.currentWorkspace;w.name='Changed snapshot';w.queryString='Changed query';
        w.showPreview=false;w.showDate=false;w.update();app.applyWorkspace(w);
        """#)
        let succeeded: Bool
        if worker { succeeded = await runner.runAsync(action).result.succeeded }
        else { succeeded = runner.run(action) }
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
        let saved = try #require(library.workspaces.first { $0.id == snapshot.id })
        var expected = options; expected.showPreview = false; expected.showDate = false
        for value in [saved] + applied {
            #expect(value.query == "Changed query" && value.name == "Changed snapshot")
            #expect(value.listOptions == expected)
            #expect(value.order == snapshot.order && value.tagged == snapshot.tagged)
        }
        #expect(applied.count == 1)
    }

    @Test(arguments: [false, true])
    func scriptingQueryUpdateApplyAndInstallKeepNativeOptions(worker: Bool) async throws {
        let (library, _, host, runner) = try makeAPIContext()
        _ = try library.createNote(content: "Needle café 🐼", tags: ["keep"])
        _ = try library.createNote(content: "Other\nNeedle", tags: ["keep"])
        _ = try library.createNote(content: "needle lowercase", tags: ["keep"])
        _ = try library.createNote(content: "Needle untagged")
        var original = Workspace(name: "Native bridge")
        original.folder = .all; original.query = "Needle"; original.order = 7; original.tagged = true
        original.scriptMetadata = ["future": "Café 🐼", "api": "{}"]
        var options = DraftListOptions()
        options.previewLines = 3; options.searchTitlesOnly = true; options.caseSensitiveSearch = true
        options.highlightFlagged = true; options.showDate = false
        original.listOptions = options
        try library.saveWorkspace(original)
        var applied: [Workspace] = []
        runner.applyWorkspace = { applied.append($0) }
        let action = makeAPIAction(#"""
        const w=Workspace.find('Native bridge');
        check(w.query('all').map(d=>d.title).join(',')==='Needle café 🐼','native query before save');
        w.update();w.update();
        check(w.query('all').map(d=>d.title).join(',')==='Needle café 🐼','native query after save');
        check(app.applyWorkspace(w)===true,'apply result');
        app.setClipboard(w.installURL);
        """#)
        let succeeded: Bool
        if worker { succeeded = await runner.runAsync(action).result.succeeded }
        else { succeeded = runner.run(action) }
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
        let saved = try #require(library.workspaces.first { $0.id == original.id })
        let installed = try WorkspaceInstallation.decode(#require(URL(string: host.clipboard)))
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        let recovered = try #require(restored.workspaces.first { $0.id == original.id })
        for value in [saved, installed, recovered] + applied {
            #expect(value.order == original.order && value.tagged == original.tagged)
            #expect(value.listOptions == original.listOptions)
            #expect(value.scriptMetadata?["future"] == original.scriptMetadata?["future"])
            #expect(value.filter(library.notes).map(\.id) == original.filter(library.notes).map(\.id))
            #expect(value.apiOptions["_draftlyNative"] == nil)
        }
        #expect(applied.count == 1)
    }
}
