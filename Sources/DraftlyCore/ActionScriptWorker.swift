import Foundation
import JavaScriptCore

struct ActionBridgeRequest: Sendable {
    let executionID: UUID
    let stepID: UUID
    let token = UUID()
    let deadline: Date
    let operation: String
    let payload: String
}

private final class BridgeReply: @unchecked Sendable {
    private let condition = NSCondition()
    private var result: String?

    func finish(_ result: String) {
        condition.lock()
        defer { condition.unlock() }
        guard self.result == nil else { return }
        self.result = result
        condition.broadcast()
    }

    func wait(until deadline: Date) -> String {
        condition.lock()
        defer { condition.unlock() }
        while result == nil {
            if !condition.wait(until: deadline), result == nil {
                result = "{\"error\":\"The host operation timed out.\",\"termination\":\"timeout\"}"
            }
        }
        return result!
    }
}

// Only cancellation and pending replies cross queues. JavaScript stays on queue.
private final class WorkerCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var replies: [UUID: BridgeReply] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func register(_ reply: BridgeReply, token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        replies[token] = reply
        return true
    }

    func attach(_ task: Task<Void, Never>, token: UUID) {
        lock.lock()
        let active = !cancelled && replies[token] != nil
        if active { tasks[token] = task }
        lock.unlock()
        if !active { task.cancel() }
    }

    func remove(_ token: UUID) {
        lock.lock()
        replies.removeValue(forKey: token)
        let task = tasks.removeValue(forKey: token)
        lock.unlock()
        task?.cancel()
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let pending = Array(replies.values)
        replies.removeAll()
        let running = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()
        for task in running { task.cancel() }
        for reply in pending { reply.finish("{\"error\":\"The action was cancelled.\"}") }
    }
}

struct ScriptWorkerFailure: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

// The unchecked conformance covers queue-owned state, never shared JS values.
final class ActionScriptWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Draftly.ActionScriptWorker")
    private let cancellation = WorkerCancellation()
    private let executionID: UUID
    private let dispatch: @Sendable (ActionBridgeRequest) async -> String
    private let hostTimeout: TimeInterval
    private var stepID: UUID
    private var runtime: ActionScriptRuntime?
    private var pending: CheckedContinuation<Bool, Error>?
    private var generation = UUID()
    private var stepDeadline: Date?
    private var hostTimedOut = false
    private var evaluationDeadline: ScriptExecutionDeadline?

    init(executionID: UUID, stepID: UUID, hostTimeout: TimeInterval,
         dispatch: @escaping @Sendable (ActionBridgeRequest) async -> String) {
        self.executionID = executionID
        self.stepID = stepID
        self.hostTimeout = hostTimeout
        self.dispatch = dispatch
    }

    func cancel() {
        cancellation.cancel()
        queue.async { self.finish(.failure(ActionExecutionInterruption.cancelled)) }
    }

    func start(_ source: String) async throws {
        try await onQueue {
            self.runtime = try ActionScriptRuntime(dispatch: { [weak self] operation, values in
                guard let self else { throw ScriptWorkerFailure(message: "The action was closed.") }
                let payload = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
                let response = try JSONSerialization.jsonObject(with: Data(self.request(operation, payload).utf8)) as? [String: Any] ?? [:]
                if response["termination"] as? String == "timeout" { self.hostTimedOut = true; throw ActionExecutionInterruption.timeout }
                if let error = response["error"] as? String { throw ScriptWorkerFailure(message: error) }
                return response["value"] is NSNull ? nil : response["value"]
            }, requireSource: { [weak self] path in
                guard let self else { throw ScriptWorkerFailure(message: "The action was closed.") }
                let payload = String(decoding: try JSONSerialization.data(withJSONObject: ["path": path]), as: UTF8.self)
                let response = try JSONSerialization.jsonObject(with: Data(self.request("requireScript", payload).utf8)) as? [String: Any] ?? [:]
                if response["termination"] as? String == "timeout" { self.hostTimedOut = true; throw ActionExecutionInterruption.timeout }
                if let error = response["error"] as? String { throw ScriptWorkerFailure(message: error) }
                return response["value"] as? String ?? ""
            })
            try self.evaluate(source)
        }
    }

    func evaluateSource(_ source: String) async throws {
        try await onQueue { try self.evaluate(source) }
    }

    func run(source: String, stepID: UUID, asynchronous: Bool, timeout: TimeInterval, synchronousTimeout: TimeInterval) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard !self.cancellation.isCancelled else { throw ActionExecutionInterruption.cancelled }
                    guard let runtime = self.runtime else { throw ScriptWorkerFailure(message: "The action was closed.") }
                    if asynchronous, !timeout.isFinite || timeout <= 0 {
                        throw ScriptWorkerFailure(message: "The asynchronous script timeout must be positive and finite.")
                    }
                    self.hostTimedOut = false
                    self.stepDeadline = asynchronous ? Date().addingTimeInterval(timeout) : nil
                    self.stepID = stepID
                    self.generation = UUID()
                    self.pending = continuation
                    runtime.scriptError = nil
                    runtime.context.evaluateScript("__beginStep();")
                    let deadline = ScriptExecutionDeadline()
                    try ActionRunner.limitExecution(runtime.context, seconds: asynchronous ? min(timeout, synchronousTimeout) : synchronousTimeout, deadline: deadline)
                    self.evaluationDeadline = deadline
                    let evaluation = runtime.context.evaluateScript(source)
                    if asynchronous, let evaluation, evaluation.isObject, evaluation.objectForKeyedSubscript("then")?.isObject == true {
                        runtime.context.setObject(evaluation, forKeyedSubscript: "__pendingResult" as NSString)
                        runtime.context.evaluateScript("{let epoch=__stepEpoch;__pendingResult.catch(error=>{if(epoch===__stepEpoch)__failure=String(error);});}")
                    }
                    try self.checkState()
                    if !asynchronous || runtime.context.objectForKeyedSubscript("__completed")?.toBool() == true {
                        self.finish(.success(true))
                    } else {
                        let generation = self.generation
                        self.queue.asyncAfter(deadline: .now() + max(0, self.stepDeadline?.timeIntervalSinceNow ?? timeout)) { [weak self] in
                            guard let self, self.generation == generation, self.pending != nil else { return }
                            self.finish(.failure(ActionExecutionInterruption.timeout))
                        }
                        self.scheduleTimer(generation)
                    }
                } catch ActionExecutionInterruption.cancelled {
                    if self.pending == nil { continuation.resume(throwing: ActionExecutionInterruption.cancelled) }
                    else { self.finish(.failure(ActionExecutionInterruption.cancelled)) }
                } catch {
                    if self.pending == nil { continuation.resume(throwing: error) }
                    else { self.finish(.failure(error)) }
                }
            }
        }
    }

    func close() async {
        cancellation.cancel()
        await withCheckedContinuation { continuation in
            queue.async {
                self.finish(.failure(ActionExecutionInterruption.cancelled))
                self.runtime?.close()
                self.runtime = nil
                self.evaluationDeadline = nil
                continuation.resume()
            }
        }
    }

    private func onQueue(_ body: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard !self.cancellation.isCancelled else { throw ActionExecutionInterruption.cancelled }
                    try body()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func request(_ operation: String, _ payload: String) -> String {
        let request = ActionBridgeRequest(executionID: executionID, stepID: stepID, deadline: min(Date().addingTimeInterval(hostTimeout), stepDeadline ?? .distantFuture), operation: operation, payload: payload)
        let reply = BridgeReply()
        guard cancellation.register(reply, token: request.token) else { return "{\"error\":\"The action was cancelled.\"}" }
        defer { cancellation.remove(request.token) }
        let task = Task { [dispatch] in reply.finish(await dispatch(request)) }
        cancellation.attach(task, token: request.token)
        return reply.wait(until: request.deadline)
    }

    private func evaluate(_ source: String) throws {
        guard let runtime else { throw ScriptWorkerFailure(message: "The action was closed.") }
        runtime.context.evaluateScript(source)
        try checkState()
    }

    private func checkState() throws {
        guard !cancellation.isCancelled else { throw ActionExecutionInterruption.cancelled }
        guard let runtime else { throw ScriptWorkerFailure(message: "The action was closed.") }
        if hostTimedOut || evaluationDeadline?.timedOut == true { throw ActionExecutionInterruption.timeout }
        if runtime.context.objectForKeyedSubscript("__cancelled")?.toBool() == true { throw ActionExecutionInterruption.cancelled }
        if let error = runtime.scriptError { throw ScriptWorkerFailure(message: error) }
        if let failure = runtime.context.objectForKeyedSubscript("__failure"), !failure.isNull, !failure.isUndefined {
            throw ScriptWorkerFailure(message: failure.toString())
        }
    }

    private func scheduleTimer(_ generation: UUID) {
        guard pending != nil, let context = runtime?.context else { return }
        let next = context.evaluateScript("__timers.length?__timers.reduce((a,t)=>Math.min(a,t.time),Infinity):null")
        guard let next, !next.isNull, !next.isUndefined else { return }
        guard next.toDouble().isFinite else { return }
        let delay = max(0, (next.toDouble() - Date().timeIntervalSince1970 * 1000) / 1000)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == generation, self.pending != nil else { return }
            do {
                try self.evaluate("__drainTimers();")
                if self.runtime?.context.objectForKeyedSubscript("__completed")?.toBool() == true { self.finish(.success(true)) }
                else { self.scheduleTimer(generation) }
            } catch { self.finish(.failure(error)) }
        }
    }

    private func finish(_ result: Result<Bool, Error>) {
        guard let pending else { return }
        self.pending = nil
        stepDeadline = nil
        generation = UUID()
        runtime?.context.evaluateScript("__endStep();")
        pending.resume(with: result)
    }
}
