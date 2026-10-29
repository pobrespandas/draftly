import AppKit
import Combine
import Foundation
import DraftlyCore

@MainActor enum AutomationActionExecution {
    struct Output {
        let report: ActionExecutionReport
        let noteID: UUID?
        let message: String
        var presentationHandled = false
    }

    typealias ModelResolver = @MainActor ([WindowModel], UUID) -> WindowModel?
    typealias CloseRegistration = @MainActor (WindowModel, @escaping @MainActor () -> Void) -> (@MainActor () -> Void)

    private final class OwnerLifetime {
        var closed = false
        var task: Task<WindowModel.ActionOutcome?, Never>?
        func close() { closed = true; task?.cancel() }
        func attach(_ task: Task<WindowModel.ActionOutcome?, Never>) {
            self.task = task
            if closed { task.cancel() }
        }
    }

    @MainActor private final class PendingEditorConflict {
        private final class WeakModel {
            weak var value: WindowModel?
            init(_ value: WindowModel) { self.value = value }
        }
        private let noteID: UUID
        private let models: [WeakModel]

        init(noteID: UUID, models: [WindowModel]) {
            self.noteID = noteID
            self.models = models.map(WeakModel.init)
        }

        var exists: Bool {
            let contents = models.compactMap(\.value).filter {
                $0.hasUnsavedChanges && $0.editor.noteID == noteID
            }.map { $0.editor.content }
            return Set(contents).count > 1
        }
    }

    static func registerOwnerClose(_ model: WindowModel, close: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) {
        guard let window = model.window else { return {} }
        let subscription = NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window).sink { _ in
            MainActor.assumeIsolated { close() }
        }
        return { subscription.cancel() }
    }

    struct WindowState {
        var isVisible: Bool
        var isKey: Bool
        var isMain: Bool
        var order: Int
    }

    static func visibleModel(_ models: [WindowModel], noteID: UUID,
                             describe: @MainActor (WindowModel) -> WindowState? = { model in
                                 guard let window = model.window else { return nil }
                                 return WindowState(isVisible: window.isVisible, isKey: window.isKeyWindow,
                                                    isMain: window.isMainWindow, order: window.windowNumber)
                             }) -> WindowModel? {
        let candidates = models.enumerated().compactMap { index, model -> (WindowModel, Int, Int, Int)? in
            guard model.editor.noteID == noteID, let window = describe(model), window.isVisible else { return nil }
            return (model, window.isKey ? 0 : window.isMain ? 1 : 2, window.order, index)
        }
        return candidates.sorted { left, right in
            if left.1 != right.1 { return left.1 < right.1 }
            if left.2 != right.2 { return left.2 < right.2 }
            return left.3 < right.3
        }.first?.0
    }

    static func run(_ action: DraftAction, noteID: UUID, library: LibraryStore,
                    models: [WindowModel], host: any ActionHost,
                    resolveModel: ModelResolver = { AutomationActionExecution.visibleModel($0, noteID: $1) },
                    registerClose: CloseRegistration = { AutomationActionExecution.registerOwnerClose($0, close: $1) }) async throws -> Output {
        guard !Task.isCancelled else {
            return notStarted(action, noteID: noteID, reason: .cancelled, message: "The action was cancelled before it started.")
        }
        let models = models.filter { $0.library === library }
        if ActionRunner.isExecuting(in: library) || models.contains(where: { $0.actionPending || $0.runner.isRunning }) {
            return notStarted(action, noteID: noteID, reason: .busy, message: "An action is already running in this library.")
        }
        let candidate = resolveModel(models, noteID)
        let model = candidate.flatMap { $0.library === library && $0.editor.noteID == noteID ? $0 : nil }
        let ownerWindow = model?.window
        let lifetime = OwnerLifetime()
        let removeCloseObserver = model.map { registerClose($0) { lifetime.close() } }
        defer { removeCloseObserver?(); lifetime.task = nil }
        guard !lifetime.closed else {
            return notStarted(action, noteID: noteID, reason: .cancelled, message: "The target window closed before the action started.")
        }
        var pending: [UUID: Set<String>] = [:]
        for model in models where model.hasUnsavedChanges {
            if let id = model.editor.noteID { pending[id, default: []].insert(model.editor.content) }
        }
        let conflicts = Set(pending.filter { $0.value.count > 1 }.map(\.key))
        if !conflicts.isEmpty {
            for id in conflicts {
                let affected = models.filter { $0.editor.noteID == id }
                let conflict = PendingEditorConflict(noteID: id, models: affected)
                for model in affected {
                    model.pausePendingAutosave { conflict.exists }
                }
            }
            throw DraftlyError.message("Multiple windows have conflicting unsaved edits. Resolve them before running the action.")
        }
        for model in models {
            model.synchronizeStoredEditor(library.notes)
            guard model.flush() else { throw DraftlyError.message("Pending edits could not be saved. The action was not started.") }
        }
        for model in models { model.synchronizeStoredEditor(library.notes) }
        guard let note = library.notes.first(where: { $0.id == noteID }) else { throw DraftlyError.message("The draft was not found.") }
        if let model, model.editor.noteID != noteID {
            return notStarted(action, noteID: noteID, reason: .cancelled, message: "The target editor changed before the action started.")
        }
        if let ownerWindow, model?.window !== ownerWindow || !ownerWindow.isVisible {
            return notStarted(action, noteID: noteID, reason: .cancelled, message: "The target window closed before the action started.")
        }
        let editor: EditorSession
        let runner: ActionRunner
        if let model {
            editor = model.editor
            runner = model.runner
        } else {
            editor = EditorSession(); editor.load(note)
            runner = ActionRunner(library: library, editor: editor, host: host)
        }
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
        let report: ActionExecutionReport
        var resultDraftID: UUID?
        if let model {
            let operation = Task { @MainActor in
                guard !lifetime.closed, !Task.isCancelled else { return Optional<WindowModel.ActionOutcome>.none }
                return await model.runActionOutcome(action)
            }
            lifetime.attach(operation)
            let completed = await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
            if let completed { report = completed.report; resultDraftID = completed.draftID }
            else if lifetime.closed || Task.isCancelled || operation.isCancelled {
                return notStarted(action, noteID: editor.noteID, reason: .cancelled, message: "The action was cancelled before it started.")
            } else if model.actionPending || runner.isRunning {
                return notStarted(action, noteID: editor.noteID, reason: .busy, message: "An action is already running in the target window.")
            } else {
                return notStarted(action, noteID: editor.noteID, reason: .error,
                                  message: library.error ?? "Pending edits could not be saved. The action was not started.")
            }
        } else { report = await runner.runAsync(action); resultDraftID = editor.noteID }
        _ = host
        return Output(report: report, noteID: resultDraftID, message: runner.message ?? "",
                      presentationHandled: model?.window?.isVisible == true)
    }

    private static func notStarted(_ action: DraftAction, noteID: UUID?, reason: ActionTerminationReason,
                                   message: String) -> Output {
        Output(report: .notStarted(actionID: action.id, reason: reason, message: message), noteID: noteID, message: message)
    }
}
