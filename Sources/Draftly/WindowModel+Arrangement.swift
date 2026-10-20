import Foundation
import DraftlyCore

@MainActor final class WindowArrangementSession {
    private(set) var token: UUID?
    var task: Task<Void, Never>?
    var isActive: Bool { token != nil }
    deinit { task?.cancel() }

    func begin() -> UUID {
        let token = UUID()
        self.token = token
        return token
    }
    func matches(_ token: UUID) -> Bool { self.token == token }
    func finish(_ token: UUID) {
        guard matches(token) else { return }
        self.token = nil
        task = nil
    }
    func cancel() {
        token = nil
        task?.cancel()
        task = nil
    }
}

@MainActor extension WindowModel {
    func showArrangement(present: @escaping NativeArrangementRequest.Presenter = NativeArrangementRequest.present) throws {
        guard !arrangementSession.isActive else { throw DraftlyError.message("Arrange is already open in this window.") }
        guard let id = editor.noteID, currentNote?.id == id else {
            throw DraftlyError.message("Select a draft before arranging its lines.")
        }
        guard flush() else { throw DraftlyError.message("Pending edits could not be saved. Arrange was not opened.") }
        let original = editor.content
        let stored = library.notes.first { $0.id == id }?.content
        let token = arrangementSession.begin()
        arrangementSession.task = Task { [weak self] in
            do {
                let arranged = try await NativeArrangementRequest.arrange(original, present: present)
                try Task.checkCancellation()
                guard let self, self.arrangementSession.matches(token) else { return }
                self.arrangementSession.finish(token)
                guard arranged != original else { return }
                guard self.editor.noteID == id, self.editor.content == original,
                      self.library.notes.first(where: { $0.id == id })?.content == stored else {
                    self.library.error = "The draft changed while Arrange was open. No arrangement was applied."
                    return
                }
                let selection = self.editor.safeSelection
                self.editor.content = arranged
                self.editor.selection = selection
                self.editor.selection = self.editor.safeSelection
                self.editor.synchronizeScriptEdit?()
                self.contentChanged()
                _ = self.flush()
            } catch is CancellationError {
                self?.arrangementSession.finish(token)
            } catch {
                guard let self, self.arrangementSession.matches(token) else { return }
                self.arrangementSession.finish(token)
                self.library.error = error.localizedDescription
            }
        }
    }
}
