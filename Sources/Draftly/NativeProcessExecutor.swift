import Foundation
import Darwin
import DraftlyCore

@MainActor
final class NativeProcessExecutor {
    private final class CancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }
    private let cancellation = CancellationState()
    private let process: Process
    private let now: @MainActor () -> Date
    private let onIsolationFailure: (@MainActor (pid_t, pid_t, Int32) -> Void)?
    private var deadline = Date.distantFuture
    private var continuation: CheckedContinuation<Int32, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var killTask: Task<Void, Never>?
    private var interruption: Error?
    private var finished = false
    private var parentExited = false
    private var parentAndGroupMissing = false
    private var cleanupPending = false
    private var isolatedProcessGroup: pid_t?
    private var onExit: (() -> Void)?
    private let afterLaunch: (@MainActor (pid_t) -> Void)?

    init(process: Process, now: @escaping @MainActor () -> Date = Date.init,
         onIsolationFailure: (@MainActor (pid_t, pid_t, Int32) -> Void)? = nil,
         afterLaunch: (@MainActor (pid_t) -> Void)? = nil) {
        self.process = process; self.now = now; self.onIsolationFailure = onIsolationFailure
        self.afterLaunch = afterLaunch
    }

    static func run(_ process: Process, timeout: TimeInterval,
                    now: @escaping @MainActor () -> Date = Date.init,
                    onIsolationFailure: (@MainActor (pid_t, pid_t, Int32) -> Void)? = nil,
                    afterLaunch: (@MainActor (pid_t) -> Void)? = nil) async throws -> Int32 {
        let executor = NativeProcessExecutor(process: process, now: now, onIsolationFailure: onIsolationFailure, afterLaunch: afterLaunch)
        return try await executor.run(timeout: timeout)
    }

    static func launchDetached(_ process: Process, timeout: TimeInterval, onExit: @escaping () -> Void) throws {
        let executor = NativeProcessExecutor(process: process)
        executor.onExit = onExit
        do { try executor.launch(timeout: timeout) }
        catch { executor.finish(error: error); throw error }
    }

    private func launch(timeout: TimeInterval) throws {
        guard timeout.isFinite, timeout > 0 else {
            throw DraftlyError.message("The process timeout must be positive and finite.")
        }
        try Task.checkCancellation()
        deadline = now().addingTimeInterval(timeout)
        try Task.checkCancellation()
        process.terminationHandler = { [self] _ in
            Task { @MainActor in self.parentExited = true; self.finish() }
        }
        try process.run()
        let pid = process.processIdentifier
        afterLaunch?(pid)
        let group = getpgid(pid)
        let groupError = group == -1 ? errno : 0
        if group == pid, pid != getpgrp() { isolatedProcessGroup = pid }
        else if group == -1, groupError == ESRCH, pid > 0, pid != getpgrp() {
            // The parent may exit before Foundation delivers its termination callback.
            // Its process group can still contain descendants.
            let groupStatus = Darwin.kill(-pid, 0)
            let probeError = groupStatus == -1 ? errno : 0
            if groupStatus == 0 { isolatedProcessGroup = pid }
            else if probeError == ESRCH { parentAndGroupMissing = true }
            else {
                onIsolationFailure?(pid, group, groupError)
                let error = DraftlyError.message("The process group could not be isolated.")
                interrupt(error)
                throw error
            }
        } else if process.isRunning {
            onIsolationFailure?(pid, group, groupError)
            let error = DraftlyError.message("The process group could not be isolated.")
            interrupt(error)
            throw error
        }
        // Detached work must not inherit cancellation from the launching action.
        timeoutTask = Task.detached { [self] in
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            await interrupt(ActionExecutionInterruption.timeout)
        }
    }

    private func run(timeout: TimeInterval) async throws -> Int32 {
        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                do { try launch(timeout: timeout) }
                catch { finish(error: error) }
            }
        } onCancel: { [cancellation] in
            cancellation.cancel()
            Task { @MainActor [self] in interrupt(CancellationError()) }
        }
        try Task.checkCancellation()
        return status
    }

    private func interrupt(_ error: Error) {
        guard !finished, interruption == nil else { return }
        interruption = error
        if parentAndGroupMissing {
            if parentExited { finish() }
            return
        }
        if let group = isolatedProcessGroup {
            signalGroup(group, SIGTERM)
        } else if process.isRunning {
            process.terminate()
        } else { finish(); return }
        cleanupPending = true
        // Descendants can outlive the direct child and can ignore SIGTERM.
        killTask = Task { [self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !finished else { return }
            if let group = isolatedProcessGroup { signalGroup(group, SIGKILL) }
            else if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            cleanupPending = false
            killTask = nil
            if parentExited { finish() }
        }
    }

    private func signalGroup(_ group: pid_t, _ signal: Int32) {
        guard group > 0, group != getpgrp(), Darwin.kill(-group, 0) == 0 else { return }
        _ = Darwin.kill(-group, signal)
    }

    private func finish(error: Error? = nil) {
        guard !finished, !cleanupPending else { return }
        let expired = now() >= deadline
        if interruption == nil, cancellation.isCancelled {
            interrupt(CancellationError())
            return
        }
        if error == nil, interruption == nil, expired {
            interrupt(ActionExecutionInterruption.timeout)
            return
        }
        finished = true
        timeoutTask?.cancel(); timeoutTask = nil
        killTask?.cancel(); killTask = nil
        process.terminationHandler = nil
        let continuation = continuation
        self.continuation = nil
        let cleanup = onExit; onExit = nil
        cleanup?()
        if let error = interruption ?? error { continuation?.resume(throwing: error) }
        else { continuation?.resume(returning: process.terminationStatus) }
    }
}
