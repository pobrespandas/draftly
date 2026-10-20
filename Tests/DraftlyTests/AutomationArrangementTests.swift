import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Automation arrangement") @MainActor
struct AutomationArrangementTests {
    @Test(arguments: ["none", "target", "other", "both"])
    func textArrangementDoesNotBorrowOrMutateAnExistingEditor(modelScope: String) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Target draft")
        let other = try library.createNote(content: "Other draft")
        var models: [WindowModel] = []
        for note in [target, other] where modelScope == "both" || (modelScope == "target" && note.id == target.id) || (modelScope == "other" && note.id == other.id) {
            let model = WindowModel(library: library)
            model.select(note.id)
            model.editor.selection = NSRange(location: 1, length: 2)
            models.append(model)
        }
        let before = models.map { EditorState(model: $0) }
        let host = AutomationArrangementHost(immediate: "Second 🐼\nFirst")
        let action = DraftAction(name: "Arrange automation text", steps: [ActionStep("script", ["script": "let arranged=editor.arrange('First\\nSecond 🐼');context.addSuccessParameter('arranged',arranged);"])])
        let output = try await AutomationActionExecution.run(action, noteID: target.id, library: library, models: models, host: host)
        #expect(output.report.reason == .success)
        #expect(output.report.successParameters == ["arranged": "Second 🐼\nFirst"])
        #expect(output.noteID == target.id)
        #expect(host.texts == ["First\nSecond 🐼"] && host.synchronousCalls == 0)
        #expect(models.map { EditorState(model: $0) } == before)
        #expect(library.notes.first { $0.id == target.id }?.content == target.content)
        #expect(library.notes.first { $0.id == other.id }?.content == other.content)
    }

    @Test(arguments: [false, true])
    func cancellationOrNativeTimeoutCannotApplyALateArrangement(timeout: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Keep source")
        let model = WindowModel(library: library); model.select(target.id)
        model.editor.selection = NSRange(location: 1, length: 2)
        let before = EditorState(model: model)
        let host = AutomationArrangementHost()
        var action = DraftAction(name: "Interrupted automation arrangement", steps: [ActionStep("script", ["script": "let result=editor.arrange('First\\nSecond');editor.setText(result);context.addSuccessParameter('late','must not escape');"]), ActionStep("insertText", ["template": "Must not run"])])
        action.afterSuccess = "archive"
        let task = Task { try await AutomationActionExecution.run(action, noteID: target.id, library: library, models: [model], host: host) }
        await host.waitForStart()
        if timeout {
            // The injected host reports native timeout. This does not test the 120-second production deadline.
            #expect(host.complete(.failure(ActionExecutionInterruption.timeout)))
        } else { task.cancel() }
        let output = try await task.value
        #expect(output.report.reason == (timeout ? .timeout : .cancelled))
        #expect(output.report.successParameters.isEmpty)
        #expect(!host.complete(.success("Late arranged text")))
        #expect(EditorState(model: model) == before)
        #expect(library.notes.first?.content == target.content && library.notes.first?.isArchived == false)
        #expect(host.synchronousCalls == 0)
        if !timeout { #expect(host.cancellationReceived) }
    }
}

private struct EditorState: Equatable {
    let noteID: UUID?
    let content: String
    let selection: NSRange
    let dirty: Bool
    @MainActor init(model: WindowModel) {
        noteID = model.editor.noteID; content = model.editor.content
        selection = model.editor.selection; dirty = model.hasUnsavedChanges
    }
}

@MainActor private final class AutomationArrangementHost: ActionHost {
    let immediate: String?
    private let started = AsyncStream.makeStream(of: Bool.self)
    private var continuation: CheckedContinuation<String, Error>?
    private(set) var texts: [String] = []
    private(set) var synchronousCalls = 0
    private(set) var cancellationReceived = false
    init(immediate: String? = nil) { self.immediate = immediate }
    func supportsAsync(_ operation: String) -> Bool { operation == "arrangeText" }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        synchronousCalls += 1
        throw DraftlyError.message("Unexpected synchronous operation: \(operation)")
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        guard operation == "arrangeText",
              let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let text = values["text"] as? String else { throw DraftlyError.message("Invalid arrangement request.") }
        texts.append(text)
        if let immediate { return try envelope(immediate) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled { _ = complete(.failure(CancellationError())); return }
                started.continuation.yield(true)
            }
        } onCancel: {
            Task { @MainActor in
                self.cancellationReceived = true
                _ = self.complete(.failure(CancellationError()))
            }
        }
    }
    func waitForStart() async {
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
    @discardableResult func complete(_ result: Result<String, Error>) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        do { continuation.resume(returning: try envelope(result.get())) }
        catch { continuation.resume(throwing: error) }
        return true
    }
    private func envelope(_ text: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["value": text]), as: UTF8.self)
    }
}
