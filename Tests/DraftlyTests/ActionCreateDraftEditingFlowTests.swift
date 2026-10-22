import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Create Draft editing flow") @MainActor
struct ActionCreateDraftEditingFlowTests {
    @Test(arguments: [false, true], [false, true])
    func savedCopyUsesTheChosenEditorDestinationWithoutChangingImportedSteps(opensInEditor: Bool, asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "Source café 🐼")
        let editor = EditorSession()
        editor.load(source)
        let selection = NSRange(location: 7, length: 4)
        editor.selection = selection

        var imported = ActionStep("createDraft", ["template": "Disabled imported template"])
        imported.isEnabled = false
        imported.unknownFields = ["future": .array([.bool(true), .string("Keep")])]
        var original = DraftAction(name: "Neutral create flow", steps: [imported])
        original.rawPayload = "{\"future\":true}"
        original.unknownFields = ["futureAction": .string("Keep")]
        try library.saveAction(original)

        var copy = ActionEditingCopy(action: original)
        copy.addStep("createDraft")
        let stepID = try #require(copy.selectedStep)
        #expect(stepID != imported.id)
        #expect(copy.action.steps[1].values == ["template": "[[draft]]", "openInEditor": "true"])
        copy.action.steps[1].values["template"] = "Created café 🐼"
        copy.action.steps[1].values["openInEditor"] = opensInEditor ? "true" : "false"
        #expect(library.actions == [original])
        #expect(library.notes == [source])
        let discarded = ActionEditingCopy(action: try #require(library.actions.first))
        #expect(discarded.action == original)
        #expect(discarded.action.steps[0].values["openInEditor"] == nil)
        #expect(editor.noteID == source.id && editor.content == source.content && editor.selection == selection)

        try library.saveAction(copy.action)
        try library.reload()
        let saved = try #require(library.actions.first)
        #expect(saved == copy.action)
        #expect(saved.id == original.id)
        #expect(saved.steps[0] == imported)
        #expect(saved.steps[0].values["openInEditor"] == nil)
        #expect(saved.steps[1].id == stepID)
        #expect(saved.rawPayload == original.rawPayload && saved.unknownFields == original.unknownFields)

        let runner = ActionRunner(library: library, editor: editor)
        let report: ActionExecutionReport
        if asynchronous { report = await runner.runAsync(saved) }
        else { report = runner.runReport(saved) }
        #expect(report.reason == .success)
        let created = try #require(library.notes.first { $0.id != source.id })
        #expect(library.notes.count == 2)
        #expect(created.id != source.id)
        #expect(created.content == "Created café 🐼")
        #expect(library.notes.first { $0.id == source.id }?.content == source.content)
        #expect(library.actions.first?.id == original.id)
        #expect(library.actions.first?.steps[1].id == stepID)
        if opensInEditor {
            #expect(editor.noteID == created.id && editor.content == created.content)
            #expect(created.accessedAt != nil)
        } else {
            #expect(editor.noteID == source.id && editor.content == source.content && editor.selection == selection)
            #expect(created.accessedAt == nil)
        }
        let createdID = created.id
        try library.reload()
        #expect(library.notes.first { $0.id == createdID } == created)
    }
}
