import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Configured value editing and execution") @MainActor
struct ActionConfigurationEditingFlowTests {
    private final class Host: ActionHost {
        var response: Any = "Accepted café 🐼"
        var accepts = true
        var prompts = 0
        var controls: [[String: Any]] = []
        func perform(_ operation: String, values: [String: Any]) throws -> Any? {
            guard operation == "prompt" else { throw DraftlyError.message("Unexpected test operation: " + operation) }
            prompts += 1
            controls = values["fields"] as? [[String: Any]] ?? []
            return ["index": accepts ? 0 : -1, "fields": ["value": response]] as [String: Any]
        }
    }

    private func editedAction(type: String) -> DraftAction {
        var copy = ActionEditingCopy(action: DraftAction(name: "Configured neutral action", steps: []))
        copy.addStep("configurationKey")
        copy.action.steps[0].values["key"] = "value"
        copy.action.steps[0].values["dataType"] = type
        copy.action.steps[0].values["futureOption"] = "Keep café 🐼"
        copy.addStep("script")
        copy.action.steps[1].values["script"] = "editor.setText(typeof context.configuredValues.value + ':' + String(context.configuredValues.value));draft.update();"
        return copy.action
    }

    @Test(arguments: ["string", "text", "boolean", "number"], [false, true])
    func savedInspectorCopyConfiguresOnceAndRunsWithTheSelectedValueType(type: String, asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Keep neutral text")
        let editor = EditorSession(); editor.load(note)
        let host = Host()
        if type == "boolean" { host.response = false }
        if type == "number" { host.response = 0 }
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = editedAction(type: type)
        try library.saveAction(action)
        let report = asynchronous ? await runner.runAsync(action) : runner.runReport(action)
        #expect(report.reason == .success)
        #expect(host.prompts == 1)
        #expect(host.controls.first?["label"] as? String == "value")
        #expect(host.controls.first?["kind"] as? String == ["string": "text", "text": "textView", "boolean": "switch", "number": "number"][type])
        let expected = type == "boolean" ? "boolean:false" : type == "number" ? "number:0" : "string:Accepted café 🐼"
        #expect(editor.content == expected && library.notes.first?.content == expected)
        let saved = try #require(library.actions.first { $0.id == action.id })
        #expect(saved.steps == action.steps)
        #expect(saved.steps[0].values["futureOption"] == "Keep café 🐼")
        let repeatReport = asynchronous ? await runner.runAsync(saved) : runner.runReport(saved)
        #expect(repeatReport.reason == .success && host.prompts == 1)
    }

    @Test(arguments: [false, true])
    func cancellingFirstConfigurationKeepsSavedDefinitionAndStopsLaterSteps(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Keep neutral text")
        let editor = EditorSession(); editor.load(note)
        let host = Host(); host.accepts = false
        let runner = ActionRunner(library: library, editor: editor, host: host)
        var action = editedAction(type: "string"); action.afterSuccess = "archive"
        try library.saveAction(action)
        let report = asynchronous ? await runner.runAsync(action) : runner.runReport(action)
        #expect(report.reason == .cancelled && report.successParameters.isEmpty)
        #expect(library.actions.first { $0.id == action.id } == action)
        #expect(editor.content == "Keep neutral text" && library.notes.first?.content == "Keep neutral text")
        #expect(library.notes.first?.isArchived == false)
        #expect(!runner.isRunning && !ActionRunner.isExecuting(in: library))
    }
}
