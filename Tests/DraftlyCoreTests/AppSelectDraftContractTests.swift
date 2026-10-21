import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class DraftSelectionContractHost: ActionHost {
    let fallback = APIContractHost()
    var index: Int? = 0
    private(set) var selection: [String: Any]?
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "selectPrompt" { selection = values; return index.map { ["index": $0] } }
        return try fallback.perform(operation, values: values)
    }
}

@Suite("App draft selection contracts") @MainActor
struct AppSelectDraftContractTests {
    private func assertUnchanged(_ library: LibraryStore, from before: Backup) throws {
        let after = try JSONDecoder().decode(Backup.self, from: library.backupData())
        #expect(after.notes.sorted { $0.id.uuidString < $1.id.uuidString } == before.notes.sorted { $0.id.uuidString < $1.id.uuidString })
        #expect(after.revisions == before.revisions)
        #expect(after.workspaces == before.workspaces)
        #expect(after.actions == before.actions && after.actionGroups == before.actionGroups)
        #expect(after.runs == before.runs)
        #expect(after.syntaxes == before.syntaxes && after.themes == before.themes)
    }

    @Test(arguments: [false, true])
    func workspaceFiltersDatesFolderSortAndPresentationReachTheSelector(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep source", host: DraftSelectionContractHost())
        for (title, archived, tags, year) in [
            ("Zulu", true, ["keep"], 2025), ("Alpha", true, ["keep"], 2025),
            ("Inbox", false, ["keep"], 2025), ("Old", true, ["keep"], 2019),
            ("Excluded", true, ["keep", "blocked"], 2025)] {
            var note = Note(content: title + "\nBody café 🐼", tags: tags)
            note.isArchived = archived
            note.createdAt = ISO8601DateFormatter().date(from: "\(year)-06-01T12:00:00Z")!
            try fixture.library.saveNote(note, preserveDates: true)
            if title == "Zulu" {
                var log = ActionRun(actionName: "Picker last action", status: "Success", message: "Neutral")
                log.noteID = note.id; fixture.library.log(log)
            }
        }
        fixture.host.index = 1
        fixture.editor.selection = NSRange(location: 2, length: 3)
        try fixture.runner.flushEditor()
        let before = try JSONDecoder().decode(Backup.self, from: fixture.library.backupData())
        var action = makeAPIAction("""
        const workspace=new Workspace();workspace.name='Neutral picker';workspace.loadFolder='archive';
        workspace.tagFilter='keep,!blocked';workspace.startDate.type='absolute';workspace.startDate.field='created';workspace.startDate.date=new Date('2020-01-01T00:00:00Z');
        workspace.setArchiveSort('name',false,false);workspace.showPreview=false;workspace.showTags=false;workspace.showDate=false;workspace.showLastAction=true;workspace.queryString='Zulu';
        const originalWorkspace=JSON.stringify(workspace);
        const selected=app.selectDraft(workspace);
        check(selected instanceof Draft && selected.title==='Zulu','selected typed draft');
        check(JSON.stringify(workspace)===originalWorkspace && workspace.queryString==='Zulu','source workspace remains unchanged');
        check(selected===Draft.find(selected.uuid),'selected cached identity');
        """)
        action.presentation.logLevel = 0
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker), Comment(rawValue: fixture.runner.message ?? ""))
        let payload = try #require(fixture.host.selection)
        let items = try #require(payload["items"] as? [[String: Any]])
        #expect(items.compactMap { $0["title"] as? String } == ["Alpha", "Zulu"])
        #expect(payload["draftSelectionQuery"] as? String == "Zulu")
        let options = try #require(payload["draftListOptions"] as? [String: Any])
        #expect(options["showPreview"] as? Bool == false && options["showTags"] as? Bool == false && options["showDate"] as? Bool == false)
        #expect(options["showLastAction"] as? Bool == true)
        #expect(items[1]["lastAction"] as? String == "Picker last action")
        #expect(items[0]["lastAction"] == nil)
        #expect(fixture.editor.content == "Keep source" && fixture.editor.selection == NSRange(location: 2, length: 3))
        try assertUnchanged(fixture.library, from: before)
    }

    @Test(arguments: [false, true], [false, true])
    func defaultSelectionAndCancellationKeepTheEditorUnchanged(worker: Bool, cancelled: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep source", host: DraftSelectionContractHost())
        var archived = Note(content: "Archive café 🐼"); archived.isArchived = true
        try fixture.library.saveNote(archived)
        var trashed = Note(content: "Trash"); trashed.trashedAt = Date()
        try fixture.library.saveNote(trashed)
        fixture.host.index = cancelled ? nil : 0
        try fixture.runner.flushEditor()
        let before = try JSONDecoder().decode(Backup.self, from: fixture.library.backupData())
        var action = makeAPIAction("""
        const selected=app.selectDraft();
        check(\(cancelled ? "selected===undefined" : "selected instanceof Draft"),'default selection result');
        """)
        action.presentation.logLevel = 0
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker), Comment(rawValue: fixture.runner.message ?? ""))
        let items = try #require(fixture.host.selection?["items"] as? [[String: Any]])
        #expect(Set(items.compactMap { $0["title"] as? String }) == ["Keep source", "Archive café 🐼"])
        #expect(fixture.editor.content == "Keep source")
        try assertUnchanged(fixture.library, from: before)
    }

    @Test(arguments: [false, true])
    func cancelledNoMatchQueryReturnsUndefinedWithoutLoadingADraft(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep source", host: DraftSelectionContractHost())
        try fixture.runner.flushEditor()
        let before = try JSONDecoder().decode(Backup.self, from: fixture.library.backupData())
        fixture.host.index = nil
        var action = makeAPIAction("const w=new Workspace();w.queryString='Absent content';const original=JSON.stringify(w);check(app.selectDraft(w)===undefined,'empty selection');check(JSON.stringify(w)===original,'unchanged workspace');")
        action.presentation.logLevel = 0
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker))
        #expect((fixture.host.selection?["items"] as? [[String: Any]])?.compactMap { $0["title"] as? String } == ["Keep source"])
        #expect(fixture.host.selection?["draftSelectionQuery"] as? String == "Absent content")
        #expect(fixture.editor.content == "Keep source")
        try assertUnchanged(fixture.library, from: before)
    }

    @Test(arguments: [false, true])
    func invalidWorkspaceTypesFailBeforeShowingTheSelector(worker: Bool) async throws {
        for argument in ["null", "'workspace'", "{}", "[]", "42"] {
            let fixture = try ScriptTestFixture(content: "Keep source", host: DraftSelectionContractHost())
            var action = makeAPIAction("app.selectDraft(\(argument));")
            action.presentation.logLevel = 0
            #expect(!(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker)))
            #expect(fixture.runner.message?.contains("The workspace must be a Workspace.") == true)
            #expect(fixture.host.selection == nil && fixture.editor.content == "Keep source")
        }
    }

    @Test(arguments: [false, true])
    func invalidWorkspaceDatesFailBeforePresentingOrApplyingSuccessEffects(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep source", host: DraftSelectionContractHost())
        try fixture.runner.flushEditor()
        let before = try JSONDecoder().decode(Backup.self, from: fixture.library.backupData())
        var action = makeAPIAction("const w=new Workspace();w.startDate.type='invalid';app.selectDraft(w);")
        action.presentation.logLevel = 0
        action.afterSuccess = "archive"
        #expect(!(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker)))
        #expect(fixture.runner.message == "Error: The query date type is invalid.")
        #expect(fixture.host.selection == nil && fixture.editor.content == "Keep source")
        try assertUnchanged(fixture.library, from: before)
    }
}
