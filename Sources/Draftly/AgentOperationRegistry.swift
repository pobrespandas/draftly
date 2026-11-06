import Foundation
import CryptoKit
import AgentContracts
import DraftlyCore

// The optional private journal preserves request identity across restarts.
@MainActor final class AgentOperationRegistry {
    // Only app-owned handlers can report failure before they submit an effect.
    struct FailureBeforeEffects: Error {
        let code: AgentErrorCode
    }

    struct Effect {
        let id: UUID
        let kind: String
        var outcome: String
        let resources: Set<AgentResourceReference>

        var wireValue: AgentJSONValue {
            .object(["kind": .string(kind), "outcome": .string(outcome),
                "resources": .array(resources.sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }
                    .map { .object(["kind": .string($0.kind.rawValue), "id": .string($0.id.uuidString)]) })])
        }
    }
    struct Snapshot {
        let id: UUID
        let state: AgentOperationState
        let updatedAt: Date
        let output: AutomationActionExecution.Output?
        let error: AgentErrorCode?
        let effects: [Effect]
        var restoredValue: AgentJSONValue? = nil
        var name = "actions.run"
        var result: AgentJSONValue? = nil
        var prompt: AgentJSONValue? = nil

        func wireValue() throws -> AgentJSONValue {
            if let restoredValue {
                try AgentExecutionSchemas.validateResult(["operation": restoredValue], for: "operations.get")
                return restoredValue
            }
            let formatter = ISO8601DateFormatter()
            func date(_ value: Date) -> AgentJSONValue { .string(formatter.string(from: value)) }
            var report: AgentJSONValue = .null
            if let output, state.isTerminal, state != .outcomeUnknown {
                let value = output.report
                report = .object([
                    "executionID": .string(value.executionID.uuidString), "actionID": .string(value.actionID.uuidString),
                    "startedAt": date(value.startedAt), "finishedAt": date(value.finishedAt),
                    "status": .string(value.result.succeeded ? "success" : value.reason == .cancelled ? "cancelled" : "failure"),
                    "reason": .string(value.reason.rawValue), "message": .string(output.message),
                    "successParameters": .object(value.result.succeeded ? value.successParameters.mapValues(AgentJSONValue.string) : [:])
                ])
            } else if name == "actions.run", state.isTerminal && state != .outcomeUnknown {
                throw AgentErrorCode.unavailable
            }
            var fields: [String: AgentJSONValue] = [
                "operationID": .string(id.uuidString), "name": .string(name),
                "state": .string(state.rawValue), "updatedAt": date(updatedAt),
                "result": state == .succeeded ? (result ?? .object([:])) : .null,
                "error": error.map { .object(["code": .string($0.rawValue), "message": .string($0.rawValue)]) } ?? .null,
                "actionReport": report, "completedEffects": .array(effects.map(\.wireValue))
            ]
            fields["prompt"] = prompt
            let value = AgentJSONValue.object(fields)
            try AgentExecutionSchemas.validateResult(["operation": value], for: "operations.get")
            return value
        }
    }
    private struct PendingPrompt {
        let id = UUID()
        let version = UUID().uuidString
        let stepID: UUID
        let title: String
        let message: String
        let buttons: [String]
        let defaultText: String?
        let isCancellable: Bool
        let continuation: CheckedContinuation<String, Error>

        var wireValue: AgentJSONValue {
            var fields: [String: AgentJSONValue] = ["stepID": .string(stepID.uuidString), "promptID": .string(id.uuidString),
                "versionToken": .string(version), "title": .string(title), "message": .string(message),
                "buttons": .array(buttons.map(AgentJSONValue.string)), "acceptsText": .bool(defaultText != nil),
                "isCancellable": .bool(isCancellable)]
            fields["defaultText"] = defaultText.map(AgentJSONValue.string)
            return .object(fields)
        }
    }

    private var pendingPrompts: [UUID: PendingPrompt] = [:]

    private struct Entry {
        let connectionID: UUID
        let grant: AgentGrant
        let targets: Set<AgentResourceReference>
        var updatedAt: Date
        var state: AgentOperationState = .queued
        var output: AutomationActionExecution.Output?
        var error: AgentErrorCode?
        var task: Task<Void, Never>?
        var cancellationRequested = false
        var deadlineExpired = false
        var deadlineTask: Task<Void, Never>?
        var effects: [Effect] = []
        var durable = false
        var name = "actions.run"
        var result: AgentJSONValue?
    }
    private var entries: [UUID: Entry] = [:]
    private struct RequestKey: Hashable { let connectionID: UUID; let requestID: UUID }
    private var requests: [RequestKey: (fingerprint: Data, operationID: UUID)] = [:]
    private let authorization: AgentOperationAuthorization
    private let now: () -> Date
    private let capacity: Int
    private let maximumWaiters: Int
    private(set) var activeWaitCount = 0
    private let journal: AgentOperationJournal?

    init(capacity: Int = 128, maximumWaiters: Int = 16, currentGrant: @escaping (UUID) throws -> AgentGrant?,
         validateHost: @escaping () throws -> Void, isLocked: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init, journal: AgentOperationJournal? = nil) {
        self.capacity = max(1, capacity)
        self.maximumWaiters = max(1, maximumWaiters)
        authorization = AgentOperationAuthorization(currentGrant: currentGrant,
            validateHost: validateHost, isLocked: isLocked, now: now)
        self.now = now
        self.journal = journal
    }

    func start(grant: AgentGrant, targets: Set<AgentResourceReference>,
               work: @escaping @MainActor () async throws -> AutomationActionExecution.Output) throws -> UUID {
        try startIdentified(grant: grant, targets: targets) { _ in try await work() }
    }

    func startRequest(_ request: AgentRequest, grant: AgentGrant,
                      work: @escaping @MainActor (UUID) async throws -> AutomationActionExecution.Output) throws -> UUID {
        guard request.operation == "actions.run" else { throw AgentErrorCode.invalidInput }
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        if case .denied(let error) = AgentPermissionPolicy.evaluate(prepared.request,
            connectionID: grant.connectionID, grant: grant, now: now()) { throw error }
        try authorization.validate(grant, targets: Set(request.targets), operationName: request.operation)
        let key = RequestKey(connectionID: grant.connectionID, requestID: request.requestID)
        let fingerprint = try requestFingerprint(prepared.value)
        if let previous = try existingRequest(prepared.request, grant: grant) { return previous }
        try makeAdmissionRoom()
        let id = UUID()
        if let reservation = try journal?.reserve(prepared.request, grant: grant, operationID: id), !reservation.isNew {
            _ = try snapshot(reservation.record.operationID, connectionID: grant.connectionID)
            requests[key] = (fingerprint, reservation.record.operationID)
            return reservation.record.operationID
        }
        _ = try startIdentified(grant: grant, targets: Set(request.targets), operationID: id,
            durable: journal != nil, work: work)
        let seconds: Int64
        if case .integer(let value) = prepared.request.parameters["timeoutSeconds"] { seconds = value }
        else { seconds = 120 }
        scheduleDeadline(id, seconds: seconds)
        requests[key] = (fingerprint, id)
        return id
    }

    // App-owned handlers must obtain effect approval before they perform work.
    // This registry preserves identity and results. It does not grant approval.
    func startValueRequest(_ request: AgentRequest, grant: AgentGrant, effectTargets: Set<AgentResourceReference> = [],
                           work: @escaping @MainActor (UUID) async throws -> [String: AgentJSONValue]) throws -> UUID {
        guard request.operation != "actions.run",
              AgentOperationJournal.supports(request.operation),
              request.libraryID == grant.libraryID else { throw AgentErrorCode.invalidInput }
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        switch AgentPermissionPolicy.evaluate(prepared.request, connectionID: grant.connectionID, grant: grant, now: now()) {
        case .denied(let error): throw error
        default: break
        }
        let targets = Set(request.targets).union(effectTargets)
        guard targets.count <= AgentRequest.maximumTargets else { throw AgentErrorCode.invalidInput }
        try authorization.validate(grant, targets: targets, operationName: request.operation)
        if let previous = try existingRequest(prepared.request, grant: grant) { return previous }
        try makeAdmissionRoom()
        let id = UUID()
        if let reservation = try journal?.reserve(prepared.request, grant: grant, operationID: id), !reservation.isNew {
            _ = try snapshot(reservation.record.operationID, connectionID: grant.connectionID)
            return reservation.record.operationID
        }
        entries[id] = Entry(connectionID: grant.connectionID, grant: grant, targets: targets,
            updatedAt: now(), durable: journal != nil, name: request.operation)
        requests[RequestKey(connectionID: grant.connectionID, requestID: request.requestID)] = (try requestFingerprint(prepared.value), id)
        launch(id) { id in
            let result = try await work(id)
            try AgentOperationSchemas.validateResult(result, for: prepared.request, preferences: AgentPreferenceCatalog.make())
            return .value(result)
        }
        scheduleDeadline(id, seconds: 120)
        return id
    }

    func existingRequest(_ request: AgentRequest, grant: AgentGrant) throws -> UUID? {
        try authorization.validate(grant, targets: Set(request.targets), operationName: request.operation)
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        let key = RequestKey(connectionID: grant.connectionID, requestID: request.requestID)
        let id: UUID
        if let previous = requests[key] {
            guard previous.fingerprint == (try requestFingerprint(prepared.value)) else { throw AgentErrorCode.versionConflict }
            id = previous.operationID
        } else if let record = try journal?.existingRequest(prepared.request, grant: grant) {
            id = record.operationID
        } else { return nil }
        _ = try snapshot(id, connectionID: grant.connectionID)
        return id
    }

    private func requestFingerprint(_ value: AgentJSONValue) throws -> Data {
        Data(SHA256.hash(data: try AgentRequestBinding.encoded(value, maximum: AgentRequest.maximumBytes * 2)))
    }

    func startIdentified(grant: AgentGrant, targets: Set<AgentResourceReference>,
                         operationID: UUID = UUID(), durable: Bool = false,
                         work: @escaping @MainActor (UUID) async throws -> AutomationActionExecution.Output) throws -> UUID {
        try authorization.validate(grant, targets: targets, operationName: "actions.run")
        let id = operationID
        guard entries[id] == nil else { throw AgentErrorCode.versionConflict }
        try makeAdmissionRoom()
        entries[id] = Entry(connectionID: grant.connectionID, grant: grant, targets: targets, updatedAt: now())
        entries[id]?.durable = durable
        launch(id) { id in .action(try await work(id)) }
        return id
    }

    // Evict only durable terminal entries. Their journal keeps retry protection.
    private func makeAdmissionRoom() throws {
        if journal != nil, entries.count >= capacity || requests.count >= capacity {
            let completed = entries.filter { $0.value.durable && $0.value.state.isTerminal }
                .sorted { $0.value.updatedAt < $1.value.updatedAt }
            for (id, _) in completed {
                guard entries.count >= capacity || requests.count >= capacity else { break }
                entries.removeValue(forKey: id)
                requests = requests.filter { $0.value.operationID != id }
            }
        }
        guard entries.count < capacity, requests.count < capacity else { throw AgentErrorCode.busy }
    }

    private enum Completion {
        case action(AutomationActionExecution.Output)
        case value([String: AgentJSONValue])
    }

    private func launch(_ id: UUID, work: @escaping @MainActor (UUID) async throws -> Completion) {
        entries[id]?.task = Task { @MainActor [weak self] in
            guard let self, let entry = self.entries[id] else { return }
            do {
                try Task.checkCancellation()
                try self.authorization.validate(entry.grant, targets: entry.targets, operationName: entry.name)
                self.entries[id]?.state = .running
                self.entries[id]?.updatedAt = self.now()
                switch try await work(id) {
                case .action(let output): self.finish(id, output: output)
                case .value(let result): self.finishValue(id, result: result)
                }
            } catch let failure as FailureBeforeEffects {
                self.finish(id, error: self.entries[id]?.effects.isEmpty == true ? failure.code : .outcomeUnknown)
            } catch is CancellationError {
                self.finishInterrupted(id, queuedError: .cancelled)
            } catch let error as AgentErrorCode {
                self.finishInterrupted(id, queuedError: error)
            } catch {
                self.finishInterrupted(id, queuedError: .storageError)
            }
        }
    }

    private func scheduleDeadline(_ id: UUID, seconds: Int64) {
        entries[id]?.deadlineTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, let entry = self.entries[id], !entry.state.isTerminal,
                  !entry.cancellationRequested else { return }
            self.entries[id]?.deadlineExpired = true
            self.entries[id]?.cancellationRequested = true
            self.entries[id]?.task?.cancel()
        }
    }

    private func finishInterrupted(_ id: UUID, queuedError: AgentErrorCode) {
        finish(id, error: entries[id]?.state == .queued ? queuedError : .outcomeUnknown)
    }

    private func finishValue(_ id: UUID, result: [String: AgentJSONValue]) {
        entries[id]?.deadlineTask?.cancel()
        entries[id]?.deadlineTask = nil
        entries[id]?.state = .succeeded
        entries[id]?.result = .object(result)
        entries[id]?.updatedAt = now()
        entries[id]?.task = nil
        persistCompletion(id)
    }

    func snapshot(_ id: UUID, connectionID: UUID) throws -> Snapshot {
        guard let entry = entries[id] else { return try recoveredSnapshot(id, connectionID: connectionID) }
        guard entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        try authorization.validate(entry.grant, targets: entry.targets, operationName: entry.name)
        return Snapshot(id: id, state: entry.state, updatedAt: entry.updatedAt, output: entry.output,
            error: entry.error, effects: entry.effects, name: entry.name, result: entry.result,
            prompt: pendingPrompts[id]?.wireValue)
    }

    // Storage proof can resolve one interrupted deletion. It cannot replay work.
    func recoverDeletion(_ request: AgentRequest, grant: AgentGrant,
                                  receipt: LibraryMutationReceipt) throws -> Snapshot {
        guard ["workspaces.delete", "drafts.purge", "actions.delete", "actionGroups.delete"].contains(request.operation), request.libraryID == grant.libraryID,
              receipt.mutation.requestID == request.requestID,
              receipt.resources.count == request.targets.count,
              Set(receipt.resources.map(\.id)) == Set(request.targets.map(\.id)),
              let id = try existingRequest(request, grant: grant) else { throw AgentErrorCode.invalidInput }
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        guard receipt.mutation.requestHash == hash(try AgentRequestBinding.encoded(prepared.value, maximum: AgentRequest.maximumBytes * 2)),
              receipt.mutation.connectionHash == hash(Data(("draftly-connection-v1:" + grant.connectionID.uuidString.lowercased()).utf8)) else {
            throw AgentErrorCode.invalidInput
        }
        let previous = try snapshot(id, connectionID: grant.connectionID)
        if previous.state == .succeeded { return previous }
        guard previous.state == .outcomeUnknown,
              previous.effects.allSatisfy({ $0.kind == request.operation && $0.resources == Set(request.targets) }) else {
            throw AgentErrorCode.versionConflict
        }
        let result: [String: AgentJSONValue] = ["deletedIDs": .array(receipt.resources.map { .string($0.id.uuidString) })]
        try AgentOperationSchemas.validateResult(result, for: request, preferences: AgentPreferenceCatalog.make())
        let effects = [Effect(id: UUID(), kind: request.operation, outcome: "completed", resources: Set(request.targets))]
        let recovered = Snapshot(id: id, state: .succeeded, updatedAt: receipt.committedAt,
            output: nil, error: nil, effects: effects, name: request.operation, result: .object(result))
        if let journal { try journal.recoverDeletion(recovered.wireValue(), request: request, grant: grant) }
        if entries[id] != nil {
            entries[id]?.state = .succeeded; entries[id]?.error = nil
            entries[id]?.result = .object(result); entries[id]?.effects = effects
            entries[id]?.updatedAt = receipt.committedAt
        }
        return recovered
    }

    func recordEffect(_ operationID: UUID, effectID: UUID, kind: String, outcome: String) throws {
        guard let entry = entries[operationID], !entry.state.isTerminal else { throw AgentErrorCode.cancelled }
        guard !kind.isEmpty, ["submitted", "completed", "failed", "unknown"].contains(outcome) else {
            throw AgentErrorCode.invalidInput
        }
        if let index = entry.effects.firstIndex(where: { $0.id == effectID }) {
            guard entry.effects[index].kind == kind, entry.effects[index].outcome == "submitted" else {
                throw AgentErrorCode.versionConflict
            }
            entries[operationID]?.effects[index].outcome = outcome
        } else {
            guard outcome == "submitted", entry.effects.count < 10_000 else { throw AgentErrorCode.busy }
            entries[operationID]?.effects.append(.init(id: effectID, kind: kind, outcome: outcome, resources: entry.targets))
        }
        entries[operationID]?.updatedAt = now()
        try persist(operationID)
    }

    func control(_ request: AgentRequest, connectionID: UUID) throws -> (snapshot: Snapshot, cancellationAccepted: Bool) {
        guard ["operations.get", "operations.cancel"].contains(request.operation),
              request.targets.count == 1, let target = request.targets.first, target.kind == .operation,
              request.parameters.isEmpty else { throw AgentErrorCode.invalidInput }
        guard let entry = entries[target.id] else {
            guard let grant = try authorization.currentGrant(for: connectionID), request.libraryID == grant.libraryID else {
                throw AgentErrorCode.permissionDenied
            }
            return (try recoveredSnapshot(target.id, connectionID: connectionID), false)
        }
        guard entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        guard request.libraryID == entry.grant.libraryID else { throw AgentErrorCode.permissionDenied }
        let accepted = request.operation == "operations.cancel" ? try cancel(target.id, connectionID: connectionID) : false
        return (try snapshot(target.id, connectionID: connectionID), accepted)
    }

    // Waiting observes work. It does not cancel or replay it.
    func wait(_ request: AgentRequest, connectionID: UUID,
              validateSession: () throws -> Void,
              uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
              sleep: () async throws -> Void = { try await Task.sleep(for: .milliseconds(100)) }) async throws
        -> (snapshot: Snapshot, waitExpired: Bool) {
        guard request.operation == "operations.wait", request.targets.count == 1,
              let target = request.targets.first, target.kind == .operation else { throw AgentErrorCode.invalidInput }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentOperationSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard case .integer(let seconds) = parameters["timeoutSeconds"] else { throw AgentErrorCode.invalidInput }
        guard activeWaitCount < maximumWaiters else { throw AgentErrorCode.busy }
        activeWaitCount += 1; defer { activeWaitCount -= 1 }
        let started = uptime()
        do {
            while true {
                try Task.checkCancellation(); try validateSession()
                guard let grant = try authorization.currentGrant(for: connectionID), request.libraryID == grant.libraryID else {
                    throw AgentErrorCode.permissionDenied
                }
                let current = try snapshot(target.id, connectionID: connectionID)
                if current.state.isTerminal || current.state == .waitingForUser {
                    try Task.checkCancellation(); try validateSession()
                    return (current, false)
                }
                let tick = uptime()
                guard started.isFinite, tick.isFinite, tick >= started else { throw AgentErrorCode.timeout }
                if tick - started >= Double(seconds) { return (current, true) }
                try await sleep()
            }
        } catch is CancellationError { throw AgentErrorCode.cancelled }
    }

    func cancel(_ id: UUID, connectionID: UUID) throws -> Bool {
        guard let entry = entries[id], entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        try authorization.validate(entry.grant, targets: entry.targets, operationName: entry.name)
        guard !entry.state.isTerminal, !entry.cancellationRequested else { return false }
        entries[id]?.cancellationRequested = true
        entries[id]?.task?.cancel()
        return true
    }

    func cancelAll() {
        for id in Array(entries.keys) where entries[id]?.state.isTerminal == false {
            entries[id]?.cancellationRequested = true
            entries[id]?.task?.cancel()
        }
    }

    func cancelConnection(_ connectionID: UUID) {
        for id in Array(entries.keys) where entries[id]?.connectionID == connectionID && entries[id]?.state.isTerminal == false {
            entries[id]?.cancellationRequested = true
            entries[id]?.task?.cancel()
        }
    }

    func waitForPrompt(_ id: UUID, stepID: UUID, payload: String) async throws -> String {
        guard payload.utf8.count <= 65_536,
              let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let title = values["title"] as? String, let message = values["message"] as? String,
              let buttons = values["buttons"] as? [[String: String]], (1...32).contains(buttons.count),
              let fields = values["fields"] as? [[String: String]], fields.count <= 1,
              let isCancellable = values["isCancellable"] as? Bool else { throw AgentErrorCode.invalidInput }
        let labels = buttons.compactMap { $0["title"] }
        guard labels.count == buttons.count else { throw AgentErrorCode.invalidInput }
        let defaultText = fields.first?["value"]
        guard fields.isEmpty || (fields.first?["key"] == "text" && defaultText != nil) else {
            throw AgentErrorCode.invalidInput
        }
        try Task.checkCancellation()
        try setWaitingForUser(id, waiting: true)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    try? setWaitingForUser(id, waiting: false)
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pendingPrompts[id] = PendingPrompt(stepID: stepID, title: title, message: message, buttons: labels,
                    defaultText: defaultText, isCancellable: isCancellable, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in
                self.pendingPrompts.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
            }
        }
    }

    func answerPrompt(_ request: AgentRequest, connectionID: UUID) throws -> Snapshot {
        guard request.retryKey == nil else { throw AgentErrorCode.invalidInput }
        guard let id = request.targets.first?.id, let entry = entries[id],
              entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        guard request.libraryID == entry.grant.libraryID else { throw AgentErrorCode.permissionDenied }
        try authorization.validate(entry.grant, targets: entry.targets, operationName: entry.name)
        guard !entry.cancellationRequested, !entry.deadlineExpired, entry.state == .waitingForUser,
              let prompt = pendingPrompts[id], request.expectedVersion == prompt.version,
              case .string(let step) = request.parameters["stepID"], UUID(uuidString: step) == prompt.stepID,
              case .string(let promptID) = request.parameters["promptID"], UUID(uuidString: promptID) == prompt.id else {
            throw AgentErrorCode.versionConflict
        }
        guard case .object(let answers) = request.parameters["answers"] else { throw AgentErrorCode.invalidInput }
        let value: AgentJSONValue
        if answers == ["cancel": .bool(true)], prompt.isCancellable {
            value = .null
        } else {
            guard Set(answers.keys).isSubset(of: ["index", "text"]),
                  let index = try? AgentTextShapes.count(answers["index"]), index < prompt.buttons.count else {
                throw AgentErrorCode.invalidInput
            }
            var fields = prompt.defaultText.map { ["text": AgentJSONValue.string($0)] } ?? [:]
            if let supplied = answers["text"] {
                guard prompt.defaultText != nil, case .string(let text) = supplied, text.utf8.count <= 65_536 else {
                    throw AgentErrorCode.invalidInput
                }
                fields["text"] = supplied
            }
            value = .object(["index": .integer(index), "fields": .object(fields)])
        }
        let response = try JSONEncoder().encode(AgentJSONValue.object(["value": value]))
        try setWaitingForUser(id, waiting: false)
        pendingPrompts.removeValue(forKey: id)
        prompt.continuation.resume(returning: String(decoding: response, as: UTF8.self))
        return try snapshot(id, connectionID: connectionID)
    }

    func setWaitingForUser(_ id: UUID, waiting: Bool) throws {
        guard let entry = entries[id] else { throw AgentErrorCode.notFound }
        try authorization.validate(entry.grant, targets: entry.targets, operationName: entry.name)
        guard !entry.cancellationRequested else { throw AgentErrorCode.cancelled }
        if waiting && entry.state == .running { entries[id]?.state = .waitingForUser }
        else if !waiting && entry.state == .waitingForUser { entries[id]?.state = .running }
        else { throw AgentErrorCode.versionConflict }
        entries[id]?.updatedAt = now()
    }

    func removeCompleted(_ id: UUID, connectionID: UUID) throws {
        guard let entry = entries[id], entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        try authorization.validate(entry.grant, targets: entry.targets, operationName: entry.name)
        guard entry.state.isTerminal else { throw AgentErrorCode.busy }
        entries.removeValue(forKey: id)
        if entry.durable { requests = requests.filter { $0.value.operationID != id } }
    }

    private func finish(_ id: UUID, output supplied: AutomationActionExecution.Output) {
        guard let entry = entries[id], !entry.state.isTerminal else { return }
        entry.deadlineTask?.cancel()
        var output = supplied
        if entry.deadlineExpired && !output.outcomeUnknown && output.report.reason == .cancelled {
            let message = "The agent operation timed out."
            output = .init(report: output.report.timedOutAfterCancellation(message: message),
                noteID: output.noteID, message: message, presentationHandled: output.presentationHandled)
        }
        let state: AgentOperationState
        let error: AgentErrorCode?
        if output.outcomeUnknown { state = .outcomeUnknown; error = .outcomeUnknown }
        else {
            switch output.report.reason {
            case .success: state = .succeeded; error = nil
            case .cancelled: state = .cancelled; error = .cancelled
            case .timeout: state = .timedOut; error = .timeout
            case .busy: state = .failed; error = .busy
            case .error: state = .failed; error = .unavailable
            }
        }
        entries[id]?.state = state; entries[id]?.error = error
        entries[id]?.updatedAt = now()
        entries[id]?.output = state == .outcomeUnknown ? nil : output
        entries[id]?.task = nil
        entries[id]?.deadlineTask = nil
        persistCompletion(id)
    }

    private func finish(_ id: UUID, error supplied: AgentErrorCode) {
        guard let entry = entries[id], !entry.state.isTerminal else { return }
        let error: AgentErrorCode = entry.deadlineExpired && entry.state == .queued && supplied == .cancelled ? .timeout : supplied
        entry.deadlineTask?.cancel()
        entries[id]?.deadlineTask = nil
        if entry.state == .queued, let action = entry.targets.first(where: { $0.kind == .action }) {
            let reason: ActionTerminationReason = error == .cancelled ? .cancelled : error == .timeout ? .timeout
                : error == .busy ? .busy : .error
            entries[id]?.output = .init(report: .notStarted(actionID: action.id, reason: reason, message: error.rawValue),
                noteID: entry.targets.first(where: { $0.kind == .draft })?.id, message: error.rawValue)
        }
        entries[id]?.state = error == .cancelled ? .cancelled : error == .timeout ? .timedOut
            : error == .outcomeUnknown ? .outcomeUnknown : .failed
        entries[id]?.error = error; entries[id]?.task = nil
        entries[id]?.updatedAt = now()
        persistCompletion(id)
    }

    private func persist(_ id: UUID) throws {
        guard let journal, let entry = entries[id], entry.durable else { return }
        let persistedResult: AgentJSONValue?
        if entry.state == .succeeded, let unavailable = AgentNativeSchemas.unavailableResult(for: entry.name) {
            persistedResult = .object(unavailable)
        } else { persistedResult = entry.result }
        let value = try Snapshot(id: id, state: entry.state, updatedAt: entry.updatedAt,
            output: entry.output, error: entry.error, effects: entry.effects, name: entry.name, result: persistedResult).wireValue()
        try journal.save(value, operationID: id, grant: entry.grant)
    }

    private func persistCompletion(_ id: UUID) {
        do { try persist(id) } catch {
            entries[id]?.state = .outcomeUnknown
            entries[id]?.output = nil
            entries[id]?.result = nil
            entries[id]?.error = .outcomeUnknown
        }
    }

    private func recoveredSnapshot(_ id: UUID, connectionID: UUID) throws -> Snapshot {
        guard let journal else { throw AgentErrorCode.notFound }
        guard let grant = try authorization.currentGrant(for: connectionID), grant.connectionID == connectionID else { throw AgentErrorCode.permissionDenied }
        guard let record = try journal.record(id, grant: grant) else { throw AgentErrorCode.notFound }
        try authorization.validate(grant, targets: [], operationName: record.operationName ?? "actions.run")
        var value: AgentJSONValue
        if let saved = record.snapshot { value = saved }
        else {
            value = try Snapshot(id: id, state: .outcomeUnknown, updatedAt: now(),
                output: nil, error: .outcomeUnknown, effects: [], name: record.operationName ?? "actions.run").wireValue()
        }
        guard case .object(var fields) = value, case .string(let rawState) = fields["state"],
              var state = AgentOperationState(rawValue: rawState) else { throw AgentErrorCode.storageError }
        if !state.isTerminal {
            state = .outcomeUnknown
            fields["state"] = .string(state.rawValue)
            fields["updatedAt"] = .string(ISO8601DateFormatter().string(from: now()))
            fields["result"] = .null; fields["actionReport"] = .null
            fields["error"] = .object(["code": .string(AgentErrorCode.outcomeUnknown.rawValue), "message": .string("Execution was interrupted.")])
            if case .array(let effects) = fields["completedEffects"] {
                fields["completedEffects"] = .array(effects.map { effect in
                    guard case .object(var entry) = effect, entry["outcome"] == .string("submitted") else { return effect }
                    entry["outcome"] = .string("unknown"); return .object(entry)
                })
            }
            value = .object(fields)
        }
        if record.snapshot != value { try journal.save(value, operationID: id, grant: grant) }
        var effects: [Effect] = []
        if case .array(let records) = fields["completedEffects"] {
            for record in records {
                guard case .object(let effect) = record, case .string(let kind) = effect["kind"],
                      case .string(let outcome) = effect["outcome"], let resources = effect["resources"] else {
                    throw AgentErrorCode.storageError
                }
                let targets = Set(try JSONDecoder().decode([AgentResourceReference].self, from: JSONEncoder().encode(resources)))
                guard targets.allSatisfy(grant.scope.permits) else { throw AgentErrorCode.permissionDenied }
                effects.append(.init(id: UUID(), kind: kind, outcome: outcome, resources: targets))
            }
        }
        var error: AgentErrorCode?
        if case .object(let failure) = fields["error"], case .string(let code) = failure["code"] { error = AgentErrorCode(rawValue: code) }
        guard case .string(let timestamp) = fields["updatedAt"], let date = ISO8601DateFormatter().date(from: timestamp) else {
            throw AgentErrorCode.storageError
        }
        var snapshot = Snapshot(id: id, state: state, updatedAt: date, output: nil, error: error, effects: effects,
            name: record.operationName ?? "actions.run", result: fields["result"] == .null ? nil : fields["result"])
        snapshot.restoredValue = value
        return snapshot
    }
}
