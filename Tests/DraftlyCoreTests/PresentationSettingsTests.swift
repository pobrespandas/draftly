import Foundation
import Testing
@testable import DraftlyCore

@Suite("Organization compatibility") @MainActor
struct PresentationSettingsTests {
    @Test func legacyActionsAndBackupsDecodeWithoutNewFields() throws {
        let action = DraftAction(name: "Legacy", steps: [])
        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(DraftAction.self, from: data).options == nil)
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.restore(JSONEncoder().encode(Backup(notes: [], revisions: [], workspaces: [], actions: [action])))
        #expect(library.orderedActions(on: .list).count == 1)
    }
    @Test func optionsGroupOrderAndWorkspaceSettingsSurviveBackup() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var first = DraftAction(name: "First", steps: []); first.group = "Work"; first.presentation.showInList = false
        first.presentation.description = "Description"; first.presentation.addTags = ["finished"]; first.presentation.order = 2
        var second = DraftAction(name: "Second", steps: []); second.group = "Work"; second.presentation.order = 1
        try library.saveActions([first, second])
        var group = ActionGroupRecord(name: "Work"); group.symbol = "folder"; try library.saveActionGroup(group)
        var workspace = Workspace(name: "Review"); workspace.order = 2
        var options = DraftListOptions(); options.searchTitlesOnly = true; options.previewSearchMatches = true; workspace.listOptions = options
        try library.saveWorkspace(workspace)
        let restored = try LibraryStore(inMemory: true, seed: false); try restored.restore(library.backupData())
        #expect(restored.actionGroups == library.actionGroups)
        #expect(restored.orderedActions().map(\.name) == ["Second", "First"])
        #expect(restored.orderedActions(on: .list).map(\.name) == ["Second"])
        #expect(restored.actions.first { $0.id == first.id }?.presentation == first.presentation)
        #expect(restored.workspaces.first?.listOptions == options)
        group.name = "Renamed"; try restored.saveActionGroup(group)
        #expect(restored.actions.allSatisfy { $0.group == "Renamed" })
    }
    @Test func titleAndCaseSearchOptionsAreApplied() {
        let note = Note(content: "Title\nneedle in body")
        var workspace = Workspace(name: "Search"); workspace.query = "needle"
        #expect(workspace.filter([note]).count == 1)
        workspace.listOptions = DraftListOptions(); workspace.listOptions?.searchTitlesOnly = true
        #expect(workspace.filter([note]).isEmpty)
        workspace.query = "title"; workspace.listOptions?.caseSensitiveSearch = true
        #expect(workspace.filter([note]).isEmpty)
        workspace.query = "Title"; #expect(workspace.filter([note]).count == 1)
    }
}
