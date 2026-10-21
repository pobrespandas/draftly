import Foundation
import DraftlyCore

@MainActor
final class WindowOpenRequestRegistry {
    private final class Pending {
        let continuation: CheckedContinuation<Bool, Error>
        let deadline: Date
        let onEnd: (UUID) -> Void
        var timeoutTask: Task<Void, Never>?

        init(continuation: CheckedContinuation<Bool, Error>, deadline: Date, onEnd: @escaping (UUID) -> Void) {
            self.continuation = continuation
            self.deadline = deadline
            self.onEnd = onEnd
        }
    }

    private var pending: [UUID: Pending] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    func contains(_ id: UUID) -> Bool {
        guard let request = pending[id] else { return false }
        return now() < request.deadline
    }

    func request(timeout: TimeInterval = 120, start: (UUID) -> Void,
                 onEnd: @escaping (UUID) -> Void = { _ in }) async throws -> Bool {
        guard timeout.isFinite, timeout > 0 else {
            throw DraftlyError.message("The window open timeout must be positive and finite.")
        }
        try Task.checkCancellation()
        let id = UUID()
        let result: Bool = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let entry = Pending(continuation: continuation, deadline: now().addingTimeInterval(timeout), onEnd: onEnd)
                pending[id] = entry
                guard !Task.isCancelled else { finish(id, with: .failure(CancellationError())); return }
                entry.timeoutTask = Task { @MainActor [self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    finish(id, with: .failure(ActionExecutionInterruption.timeout))
                }
                start(id)
            }
        } onCancel: {
            Task { @MainActor [self] in finish(id, with: .failure(CancellationError())) }
        }
        try Task.checkCancellation()
        return result
    }

    @discardableResult
    func complete(_ id: UUID, _ result: Bool) -> Bool {
        guard let request = pending[id] else { return false }
        guard now() < request.deadline else {
            finish(id, with: .failure(ActionExecutionInterruption.timeout))
            return false
        }
        finish(id, with: .success(result))
        return true
    }

    func cancel(_ id: UUID) { finish(id, with: .failure(CancellationError())) }

    func cancelAll() {
        for id in Array(pending.keys) { cancel(id) }
    }

    private func finish(_ id: UUID, with result: Result<Bool, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask?.cancel()
        request.timeoutTask = nil
        request.onEnd(id)
        request.continuation.resume(with: result)
    }
}
