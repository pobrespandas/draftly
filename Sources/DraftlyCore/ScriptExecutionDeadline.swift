import Foundation

// JavaScriptCore can signal its deadline from outside the worker queue.
final class ScriptExecutionDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var reached = false

    var timedOut: Bool {
        lock.lock(); defer { lock.unlock() }
        return reached
    }

    func recordTimeout() {
        lock.lock(); defer { lock.unlock() }
        reached = true
    }
}
