import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Automation pre-start cancellation") @MainActor
struct AutomationPrestartCancellationTests {
    @Test func cancellationReturnsAReportBeforeResolutionOrPendingSave() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored source")
        let model = WindowModel(library: library)
        model.select(note.id)
        model.editor.content = "Pending user text"
        model.hasUnsavedChanges = true
        let action = DraftAction(name: "Cancelled before automation", steps: [
            ActionStep("script", ["script": "editor.setText('ERROR: cancelled action ran');"])
        ])
        var resolutions = 0
        let task = Task { @MainActor in
            try await AutomationActionExecution.run(action, noteID: note.id, library: library,
                models: [model], host: model.host, resolveModel: { _, _ in
                    resolutions += 1
                    return model
                })
        }
        task.cancel()
        let output = try await task.value
        #expect(output.report.reason == .cancelled && output.report.result == .cancelled)
        #expect(output.report.actionID == action.id && output.noteID == note.id)
        #expect(output.report.successParameters.isEmpty && resolutions == 0)
        #expect(model.hasUnsavedChanges && model.editor.content == "Pending user text")
        #expect(library.notes.first { $0.id == note.id }?.content == "Stored source")
        #expect(library.runs.isEmpty && model.runner.lastReport == nil)
        #expect(AutomationActionError.from(output.report)?.reason == .cancelled)
    }
}
