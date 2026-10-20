import Combine
import Foundation
import DraftlyCore

@MainActor enum AutomationActionExecution {
    struct Output {
        let report: ActionExecutionReport
        let noteID: UUID?
        let message: String
    }

    static func run(_ action: DraftAction, noteID: UUID, library: LibraryStore,
                    models: [WindowModel], host: any ActionHost) async throws -> Output {
        try Task.checkCancellation()
        let models = models.filter { $0.library === library }
        for model in models {
            guard model.flush() else { throw DraftlyError.message("Pending edits could not be saved. The action was not started.") }
        }
        guard let note = library.notes.first(where: { $0.id == noteID }) else { throw DraftlyError.message("The draft was not found.") }
        let editor = EditorSession(); editor.load(note)
        let runner = ActionRunner(library: library, editor: editor, host: host)
        var subscriptions: [AnyCancellable] = []
        var previous = Dictionary(uniqueKeysWithValues: library.notes.map { ($0.id, $0.content) })
        subscriptions.append(library.$notes.dropFirst().sink { notes in
            let current = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.content) })
            defer { previous = current }
            guard runner.isRunning, !runner.isApplyingScriptCommand, let id = editor.noteID,
                  current[id] != previous[id] else { return }
            guard let content = current[id] else {
                runner.cancel(); editor.noteID = nil; editor.content = ""; return
            }
            guard content != editor.content else { return }
            runner.cancel()
            editor.content = content
        })
        for model in models {
            subscriptions.append(model.$hasUnsavedChanges.dropFirst().sink { dirty in
                guard dirty, runner.isRunning, !model.runner.isApplyingScriptCommand,
                      model.editor.noteID == editor.noteID else { return }
                runner.cancel()
                editor.content = model.editor.content
            })
        }
        defer { subscriptions.forEach { $0.cancel() } }
        let report = await runner.runAsync(action)
        _ = host
        return Output(report: report, noteID: editor.noteID, message: runner.message ?? "")
    }
}
