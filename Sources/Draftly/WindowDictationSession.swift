import Foundation
import DraftlyCore

@MainActor final class WindowDictationSession {
    private(set) var isActive = false
    private var task: Task<Void, Never>?
    private var identity: UUID?

    deinit { task?.cancel() }

    func cancel() { task?.cancel() }
    func wait() async { await task?.value }

    func start(model: WindowModel, present: @escaping @MainActor () async throws -> String) {
        let id = UUID()
        let noteID = model.editor.noteID
        let content = model.editor.content
        let selection = model.editor.safeSelection
        let stored = model.library.notes.first { $0.id == noteID }?.content
        identity = id; isActive = true
        task = Task { @MainActor [weak self, weak model] in
            defer {
                if self?.identity == id {
                    self?.isActive = false
                    self?.identity = nil
                    self?.task = nil
                }
            }
            guard !Task.isCancelled else { return }
            guard model?.editor.focusForDictation?() == true else {
                model?.library.error = "The editor dictation interface is unavailable."
                return
            }
            do {
                let text = try await present()
                try Task.checkCancellation()
                guard !text.isEmpty, let model else { return }
                let currentStored = model.library.notes.first { $0.id == noteID }?.content
                guard model.editor.noteID == noteID, model.editor.content == content,
                      model.editor.safeSelection == selection, currentStored == stored else {
                    model.recoverDictation(text)
                    return
                }
                // Finish before insertion. User-edit cancellation must not cancel this result.
                if self?.identity == id { self?.isActive = false; self?.identity = nil; self?.task = nil }
                try model.editor.replace(selection, with: text)
                model.editor.synchronizeScriptEdit?()
                model.contentChanged()
                _ = model.flush()
            } catch is CancellationError {
            } catch ActionExecutionInterruption.cancelled {
            } catch {
                if !Task.isCancelled { model?.library.error = error.localizedDescription }
            }
        }
    }
}
