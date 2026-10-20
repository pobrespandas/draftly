import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Automation timeout boundary") @MainActor
struct AutomationTimeoutBoundaryTests {
    @Test func actualScriptTimeoutRetainsItsReasonThroughAutomationAndResultMappings() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral source")
        let model = WindowModel(library: library)
        model.select(note.id)
        model.editor.selection = NSRange(location: 0, length: note.content.utf16.count)
        model.runner.scriptTimeout = 0.02
        var action = DraftAction(name: "Neutral automation timeout", steps: [
            ActionStep("insertText", ["template": "Completed automation write"]),
            ActionStep("script", ["script": "context.addSuccessParameter('discard','value');"]),
            ActionStep("script", ["allowAsync": "true", "script": "void 0;"]),
            ActionStep("insertText", ["template": "ERROR: later step ran"])
        ])
        action.afterSuccess = "archive"
        let output = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [model], host: model.host, resolveModel: { models, _ in models.first })
        #expect(output.report.reason == .timeout && output.report == model.runner.lastReport)
        #expect(output.report.successParameters.isEmpty)
        let error = try #require(AutomationActionError.from(output.report, message: output.message))
        #expect(error.reason == .timeout && error.executionID == output.report.executionID)
        let callback = try #require(output.report.result.callbackURL(parameters: [
            "x-success": "fixture://success", "x-cancel": "fixture://cancel", "x-error": "fixture://error?keep=yes"
        ], successParameters: output.report.successParameters))
        #expect(callback.host == "error")
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.filter { $0.name == "keep" }.map(\.value) == ["yes"])
        #expect(!query.contains { $0.name == "discard" })
        #expect(library.notes.first(where: { $0.id == note.id })?.content == "Completed automation write")
        #expect(library.notes.first(where: { $0.id == note.id })?.isArchived == false)
        #expect(library.runs.count == 1)
    }
}
