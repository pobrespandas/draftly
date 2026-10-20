import Foundation
import Darwin
import DraftlyCore

@MainActor
final class NativeProcessExecutor {
    private let process: Process
    private var continuation: CheckedContinuation<Int32, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var killTask: Task<Void, Never>?
    private var interruption: Error?
    private var finished = false
    private var parentExited = false
    private var cleanupPending = false
    private var isolatedProcessGroup: pid_t?
    private var onExit: (() -> Void)?

    init(process: Process) { self.process = process }

    static func run(_ process: Process, timeout: TimeInterval) async throws -> Int32 {
        let executor = NativeProcessExecutor(process: process)
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
        process.terminationHandler = { [self] _ in
            Task { @MainActor in self.parentExited = true; self.finish() }
        }
        try process.run()
        let pid = process.processIdentifier
        if getpgid(pid) == pid, pid != getpgrp() { isolatedProcessGroup = pid }
        else if process.isRunning {
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
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                do { try launch(timeout: timeout) }
                catch { finish(error: error) }
            }
        } onCancel: {
            Task { @MainActor [self] in interrupt(CancellationError()) }
        }
    }

    private func interrupt(_ error: Error) {
        guard !finished, interruption == nil else { return }
        interruption = error
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
