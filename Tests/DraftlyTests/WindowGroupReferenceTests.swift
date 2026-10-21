import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Window action group references") @MainActor
struct WindowGroupReferenceTests {
    @Test(arguments: ["loadActionGroup", "loadActionBarGroup"])
    func retainedIdentitySurvivesRenameAndNameReuse(operation: String) throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var original = ActionGroupRecord(name: "Original café 🐼")
        try library.saveActionGroup(original)
        let reference: [String: Any] = ["uuid": original.id.uuidString, "name": original.name, "future": true]
        original.name = "Renamed café 🐼"
        try library.saveActionGroup(original, replacing: "Original café 🐼")
        try library.saveActionGroup(ActionGroupRecord(name: "Original café 🐼"))
        let model = WindowModel(library: library)
        model.showActions = false
        model.actionGroup = "Keep list"
        model.actionBarGroup = "Keep bar"

        let result = try model.actionUIOperation(["operation": operation, "value": reference])

        #expect(result as? Bool == true)
        #expect(model.actionGroup == (operation == "loadActionGroup" ? original.name : "Keep list"))
        #expect(model.actionBarGroup == (operation == "loadActionBarGroup" ? original.name : "Keep bar"))
        #expect(model.showActions == (operation == "loadActionGroup"))
        var workspace = Workspace(name: "Same reference")
        let key = operation == "loadActionGroup" ? "loadActionListGroup" : "loadActionBarGroup"
        workspace.scriptMetadata = ["api": String(decoding: try JSONSerialization.data(withJSONObject: [key: reference]), as: UTF8.self)]
        let resolved = try WorkspacePresentationResolver.resolve(workspace, groupNames: library.groupNames,
            groups: library.actionGroups, themes: [])
        let group = try #require(resolved.apiOptions[key] as? [String: Any])
        #expect(group["name"] as? String == original.name && group["future"] as? Bool == true)
    }

    @Test(arguments: ["loadActionGroup", "loadActionBarGroup"])
    func missingIdentityDoesNotFallBackToAnExistingNameOrChangePresentation(operation: String) throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveActionGroup(ActionGroupRecord(name: "Existing"))
        let model = WindowModel(library: library)
        model.showActions = false
        model.actionGroup = "Keep list"
        model.actionBarGroup = "Keep bar"
        for rawID in [UUID().uuidString, "invalid UUID"] {
            let reference = ["uuid": rawID, "name": "Existing"]
            #expect(throws: (any Error).self) {
                _ = try model.actionUIOperation(["operation": operation, "value": reference])
            }
            var workspace = Workspace(name: "Invalid reference")
            let key = operation == "loadActionGroup" ? "loadActionListGroup" : "loadActionBarGroup"
            try WorkspaceOptionsEditor.setReference(reference, key: key, in: &workspace)
            #expect(throws: (any Error).self) {
                _ = try WorkspacePresentationResolver.resolve(workspace, groupNames: library.groupNames,
                    groups: library.actionGroups, themes: [])
            }
        }
        #expect(model.actionGroup == "Keep list" && model.actionBarGroup == "Keep bar")
        #expect(!model.showActions)
    }

    @Test(arguments: ["loadActionGroup", "loadActionBarGroup"])
    func nameOnlyReferencesRemainCompatible(operation: String) throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveActionGroup(ActionGroupRecord(name: "Legacy group"))
        let model = WindowModel(library: library)
        for value: Any in ["Legacy group", ["name": "Legacy group"]] {
            #expect(try model.actionUIOperation(["operation": operation, "value": value]) as? Bool == true)
            #expect((operation == "loadActionGroup" ? model.actionGroup : model.actionBarGroup) == "Legacy group")
        }
    }
}
