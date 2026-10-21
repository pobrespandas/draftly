import Foundation
import Testing
@testable import DraftlyCore

@Suite("Window workspace access contracts") @MainActor
struct WindowWorkspaceAccessTests {
    @Test(arguments: [false, true])
    func currentWorkspaceReturnsDetachedTypedSnapshotsWithoutSavingOrApplying(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: APIContractHost())
        var snapshot = Workspace(name: "Current window snapshot")
        snapshot.folder = .archive
        snapshot.query = "café 🐼"
        snapshot.tags = ["keep"]
        snapshot.excludedTags = ["omit"]
        snapshot.matchAnyTag = true
        snapshot.sort = .title
        snapshot.ascending = true
        var options = DraftListOptions()
        options.showPreview = false
        options.showTags = false
        snapshot.listOptions = options
        var alpha = Note(content: "Alpha café 🐼", tags: ["keep"], isArchived: true)
        var zulu = Note(content: "Zulu café 🐼", tags: ["keep"], isArchived: true)
        alpha.modifiedAt = Date(timeIntervalSince1970: 100)
        zulu.modifiedAt = Date(timeIntervalSince1970: 200)
        try f.library.saveNotes([alpha, zulu], preserveDates: true)
        var reads = 0, applies = 0
        f.runner.currentWorkspace = { reads += 1; return snapshot }
        f.runner.applyWorkspace = { _ in applies += 1 }
        defer { f.runner.currentWorkspace = nil; f.runner.applyWorkspace = nil }

        let action = makeAPIAction("""
        const first=app.currentWindow.currentWorkspace;
        check(first instanceof Workspace,'typed window workspace');
        check(first.uuid==='\(snapshot.id.uuidString)','snapshot identity');
        check(first.name==='Current window snapshot'&&first.loadFolder==='archive','name and current folder');
        check(first.queryString==='café 🐼'&&first.tagFilter==='keep,!omit','current query and tags');
        check(first.tagFilterRequireAll===false,'tag matching mode');
        check(first.showPreview===false&&first.showTags===false,'current presentation');
        first.name='Detached mutation';first.queryString='Not applied';
        first.setArchiveSort('modified',true,false);
        const second=app.currentWindow.currentWorkspace;
        check(second instanceof Workspace&&second!==first,'independent typed reads');
        check(second.name==='Current window snapshot'&&second.queryString==='café 🐼','no implicit apply');
        const ordered=second.query('archive');
        check(ordered.length===2&&ordered[0].uuid==='\(alpha.id.uuidString)'&&ordered[1].uuid==='\(zulu.id.uuidString)','independent snapshot sort');
        check(editor.getText()==='Keep café 🐼','editor preserved');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(reads == 2 && applies == 0)
        #expect(f.library.workspaces.isEmpty && f.host.calls.isEmpty)
        #expect(f.editor.content == "Keep café 🐼")
    }

    @Test(arguments: [false, true])
    func applyWorkspaceForwardsDefaultAndExplicitValuesWithBooleanResults(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        var defaults = Workspace(name: "Configured default")
        defaults.folder = .flagged
        defaults.query = "Default query"
        defaults.tags = ["default-tag"]
        var applied: [Workspace] = []
        f.runner.defaultWorkspace = { defaults }
        f.runner.applyWorkspace = { applied.append($0) }
        defer { f.runner.defaultWorkspace = nil; f.runner.applyWorkspace = nil }

        let action = makeAPIAction("""
        check(app.currentWindow.applyWorkspace()===true,'default Boolean result');
        const explicit=new Workspace();
        explicit.name='Explicit window workspace';explicit.loadFolder='archive';
        explicit.queryString='café 🐼';explicit.tagFilter='one,!two';
        explicit.showPreview=false;
        check(app.currentWindow.applyWorkspace(explicit)===true,'explicit Boolean result');
        check(editor.getText()==='Keep','application does not edit source');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        try #require(applied.count == 2)
        #expect(applied[0].name == defaults.name && applied[0].folder == .flagged)
        #expect(applied[0].query == defaults.query && applied[0].tags == defaults.tags)
        #expect(applied[1].name == "Explicit window workspace" && applied[1].folder == .archive)
        #expect(applied[1].query == "café 🐼" && applied[1].tags == ["one"])
        #expect(applied[1].excludedTags == ["two"] && applied[1].listOptions?.showPreview == false)
        #expect(f.library.workspaces.isEmpty && f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func applyWorkspaceHostFailureStopsFollowingScriptWithoutSavingOrEditing(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: APIContractHost())
        var attempts = 0
        f.runner.applyWorkspace = { workspace in
            attempts += 1
            #expect(workspace.name == "Rejected window workspace")
            throw DraftlyError.message("Neutral workspace application failure")
        }
        defer { f.runner.applyWorkspace = nil }
        let action = makeAPIAction("""
        const value=new Workspace();value.name='Rejected window workspace';
        app.currentWindow.applyWorkspace(value);
        editor.setText('Unexpected later edit');
        """)
        #expect(!(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker)))
        #expect(f.runner.message?.contains("Neutral workspace application failure") == true)
        #expect(attempts == 1 && f.editor.content == "Keep café 🐼")
        #expect(f.library.workspaces.isEmpty && f.host.calls.isEmpty)
    }
}
