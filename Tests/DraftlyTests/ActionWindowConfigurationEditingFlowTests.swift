import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Configure Window editing flow") @MainActor
struct ActionWindowConfigurationEditingFlowTests {
    private let listGroup = "Neutral action list café 🐼"
    private let barGroup = "Neutral action bar"

    private func makeModel(defaults: UserDefaults) throws -> (WindowModel, Workspace, Note) {
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveActionGroup(ActionGroupRecord(name: listGroup))
        try library.saveActionGroup(ActionGroupRecord(name: barGroup))
        var workspace = Workspace(name: "Neutral target workspace")
        workspace.folder = .archive
        workspace.query = "Target query"
        workspace.tags = ["target"]
        try library.saveWorkspace(workspace)
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        let source = try library.createNote(content: "Source café 🐼")
        model.select(source.id)
        model.editor.selection = NSRange(location: 7, length: 4)
        return (model, workspace, source)
    }

    private func setControls(_ enabled: Bool, model: WindowModel) {
        model.setDraftListVisible(enabled)
        model.setFiltersVisible(enabled)
        model.showActions = enabled
        model.showActionBar = enabled
        model.showTags = enabled
        model.isDraftPinned = enabled
        model.linksEnabled = enabled
    }

    private func options(enabled: Bool, workspace: Workspace, byIdentity: Bool) -> [String: String] {
        let value = enabled ? "true" : "false"
        return ["showDraftList": value, "showActionList": value, "showFilters": value,
                "showActionBar": value, "showTagEntry": value, "pinCurrentDraft": value,
                "linkMode": value, "loadWorkspace": byIdentity ? workspace.id.uuidString : workspace.name,
                "loadActionGroup": listGroup, "loadActionBarGroup": barGroup]
    }

    private func expectControls(_ enabled: Bool, model: WindowModel) {
        #expect(model.showDraftList == enabled)
        #expect(model.showActions == enabled)
        #expect(model.showFilters == enabled)
        #expect(model.showActionBar == enabled)
        #expect(model.showTags == enabled)
        #expect(model.isDraftPinned == enabled)
        #expect(model.linksEnabled == enabled)
    }

    @Test(arguments: [false, true], [false, true])
    func savedCopyAppliesAllControlsAndReferencesWithoutChangingTheEditor(enabled: Bool, asynchronous: Bool) async throws {
        let preferences = try TestPreferences(prefix: "Draftly.WindowConfigurationEditing.")
        defer { preferences.close() }
        let (model, workspace, source) = try makeModel(defaults: preferences.defaults)
        let library = model.library
        setControls(!enabled, model: model)
        model.query = "Before"
        let selection = model.editor.selection
        let focus = model.editor.focusToken
        let initialListGroup = model.actionGroup, initialBarGroup = model.actionBarGroup
        var imported = ActionStep("configureWindow", ["futureOption": "Keep café 🐼"])
        imported.isEnabled = false
        imported.unknownFields = ["future": .array([.bool(false), .string("Keep")])]
        var original = DraftAction(name: "Neutral configure flow", steps: [imported])
        original.rawPayload = "{\"future\":true}"
        original.unknownFields = ["futureAction": .string("Keep")]
        try library.saveAction(original)

        var copy = ActionEditingCopy(action: original)
        copy.addStep("configureWindow")
        let stepID = try #require(copy.selectedStep)
        #expect(stepID != imported.id)
        copy.action.steps[1].values.merge(options(enabled: enabled, workspace: workspace, byIdentity: asynchronous)) { _, new in new }
        copy.action.steps[1].unknownFields = ["futureStep": .object(["keep": .bool(true)])]
        #expect(library.actions == [original])
        let discarded = ActionEditingCopy(action: try #require(library.actions.first))
        #expect(discarded.action == original && discarded.action.steps.count == 1)
        #expect(discarded.action.steps[0].values["showDraftList"] == nil)
        expectControls(!enabled, model: model)
        #expect(model.selectedWorkspace == nil && model.folder == .inbox && model.query == "Before")
        #expect(model.actionGroup == initialListGroup && model.actionBarGroup == initialBarGroup)

        try library.saveAction(copy.action)
        try library.reload()
        let saved = try #require(library.actions.first)
        #expect(saved == copy.action && saved.id == original.id)
        #expect(saved.steps[0] == imported && saved.steps[1].id == stepID)
        #expect(saved.rawPayload == original.rawPayload && saved.unknownFields == original.unknownFields)
        let report: ActionExecutionReport
        if asynchronous { report = await model.runner.runAsync(saved) }
        else { report = model.runner.runReport(saved) }
        #expect(report.reason == .success)
        expectControls(enabled, model: model)
        #expect(model.selectedWorkspace == workspace.id && model.folder == .archive)
        #expect(model.query == workspace.query && model.selectedTags == Set(workspace.tags))
        #expect(model.actionGroup == listGroup && model.actionBarGroup == barGroup)
        #expect(model.editor.noteID == source.id && model.editor.content == source.content)
        #expect(model.editor.selection == selection && model.editor.focusToken == focus)
        #expect(library.notes.count == 1 && library.notes.first?.id == source.id)
        #expect(library.notes.first?.content == source.content)
        #expect(library.actions.first == saved)
        #expect(model.window == nil)
    }

    @Test(arguments: ["loadWorkspace", "loadActionGroup", "loadActionBarGroup"], [false, true])
    func missingReferencesFailBeforeAnyControlOrWorkspaceChange(referenceKey: String, asynchronous: Bool) async throws {
        let preferences = try TestPreferences(prefix: "Draftly.WindowConfigurationMissing.")
        defer { preferences.close() }
        let (model, workspace, source) = try makeModel(defaults: preferences.defaults)
        setControls(true, model: model)
        model.query = "Before"
        model.selectedTags = ["before"]
        let selection = model.editor.selection
        let focus = model.editor.focusToken
        let initialListGroup = model.actionGroup, initialBarGroup = model.actionBarGroup
        var copy = ActionEditingCopy(action: DraftAction(name: "Neutral missing reference", steps: []))
        copy.addStep("configureWindow")
        let stepID = try #require(copy.selectedStep)
        var values = options(enabled: false, workspace: workspace, byIdentity: asynchronous)
        values[referenceKey] = "Missing neutral reference"
        copy.action.steps[0].values.merge(values) { _, new in new }
        copy.action.steps[0].unknownFields = ["future": .bool(true)]
        try model.library.saveAction(copy.action)
        try model.library.reload()
        let saved = try #require(model.library.actions.first)
        let report: ActionExecutionReport
        if asynchronous { report = await model.runner.runAsync(saved) }
        else { report = model.runner.runReport(saved) }
        #expect(report.reason == .error)
        if case .failure(let message) = report.result {
            #expect(message.contains(referenceKey == "loadWorkspace" ? "workspace was not found" : "action group was not found"))
        } else { Issue.record("The missing reference did not return an error.") }
        expectControls(true, model: model)
        #expect(model.selectedWorkspace == nil && model.folder == .inbox)
        #expect(model.query == "Before" && model.selectedTags == ["before"])
        #expect(model.actionGroup == initialListGroup && model.actionBarGroup == initialBarGroup)
        #expect(model.editor.noteID == source.id && model.editor.content == source.content)
        #expect(model.editor.selection == selection && model.editor.focusToken == focus)
        #expect(model.library.notes.count == 1 && model.library.notes.first?.id == source.id)
        #expect(model.library.actions.first == saved && saved.id == copy.action.id)
        #expect(saved.steps[0].id == stepID && saved.steps[0].unknownFields == ["future": .bool(true)])
        #expect(model.window == nil)
    }
}
