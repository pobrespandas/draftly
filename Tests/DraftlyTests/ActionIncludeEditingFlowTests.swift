import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Included action target editing") @MainActor
struct ActionIncludeEditingFlowTests {
    @Test(arguments: [false, true])
    func editingTheTargetPreservesStepIdentityAndRunsTheSelectedUUID(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral source")
        let first = DraftAction(name: "Old helper", steps: [ActionStep("script", ["script": "var includeResult='Old';"])] )
        let selected = DraftAction(name: "Renamed helper", steps: [ActionStep("script", ["script": "var includeResult='Selected café 🐼';"])] )
        try library.saveAction(first); try library.saveAction(selected)
        var included = ActionStep("includeAction", ["uuid": first.id.uuidString, "name": first.name])
        included.unknownFields = ["future": .object(["keep": .bool(true)])]
        let original = DraftAction(name: "Neutral parent", steps: [included,
            ActionStep("script", ["script": "editor.setText(includeResult);draft.update();"])])
        try library.saveAction(original)
        var copy = ActionEditingCopy(action: original)
        let targetField = try #require(ActionStepInspectorFields.fields(for: copy.action.steps[0]).first { $0.key == "uuid" })
        copy.action.steps[0].values[targetField.key] = selected.id.uuidString
        #expect(library.actions.first { $0.id == original.id } == original)
        #expect(copy.action.steps[0].id == included.id)
        #expect(copy.action.steps[0].unknownFields == included.unknownFields)
        try library.saveAction(copy.action)
        let restored = try JSONDecoder().decode(DraftAction.self, from: JSONEncoder().encode(copy.action))
        #expect(restored.steps[0].id == included.id)
        #expect(restored.steps[0].values["uuid"] == selected.id.uuidString)
        #expect(restored.steps[0].values["name"] == first.name)
        let editor = EditorSession(); editor.load(note)
        let runner = ActionRunner(library: library, editor: editor)
        let report = asynchronous ? await runner.runAsync(restored) : runner.runReport(restored)
        #expect(report.reason == .success)
        #expect(editor.content == "Selected café 🐼" && library.notes.first?.content == "Selected café 🐼")
    }
}
