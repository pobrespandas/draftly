import Foundation
import AgentContracts
import DraftlyCore

// The optional private journal preserves request identity across restarts.
@MainActor final class AgentOperationRegistry {
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
            let value: AgentJSONValue = .object([
                "operationID": .string(id.uuidString), "name": .string(name),
                "state": .string(state.rawValue), "updatedAt": date(updatedAt),
                "result": state == .succeeded ? (result ?? .object([:])) : .null,
                "error": error.map { .object(["code": .string($0.rawValue), "message": .string($0.rawValue)]) } ?? .null,
                "actionReport": report, "completedEffects": .array(effects.map(\.wireValue))
            ])
            try AgentExecutionSchemas.validateResult(["operation": value], for: "operations.get")
            return value
        }
    }
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
    private var requests: [RequestKey: (value: AgentJSONValue, operationID: UUID)] = [:]
    private let currentGrant: (UUID) throws -> AgentGrant?
    private let validateHost: () throws -> Void
    private let isLocked: () -> Bool
    private let now: () -> Date
    private let capacity: Int
    private let journal: AgentOperationJournal?

    init(capacity: Int = 128, currentGrant: @escaping (UUID) throws -> AgentGrant?,
         validateHost: @escaping () throws -> Void, isLocked: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init, journal: AgentOperationJournal? = nil) {
        self.capacity = max(1, capacity); self.currentGrant = currentGrant
        self.validateHost = validateHost; self.isLocked = isLocked; self.now = now
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
        try validate(grant, targets: Set(request.targets))
        let key = RequestKey(connectionID: grant.connectionID, requestID: request.requestID)
        if let previous = requests[key] {
            guard previous.value == prepared.value else { throw AgentErrorCode.versionConflict }
            _ = try snapshot(previous.operationID, connectionID: grant.connectionID)
            return previous.operationID
        }
        guard requests.count < capacity else { throw AgentErrorCode.busy }
        guard entries.count < capacity else { throw AgentErrorCode.busy }
        let id = UUID()
        if let reservation = try journal?.reserve(prepared.request, grant: grant, operationID: id), !reservation.isNew {
            _ = try snapshot(reservation.record.operationID, connectionID: grant.connectionID)
            requests[key] = (prepared.value, reservation.record.operationID)
            return reservation.record.operationID
        }
        _ = try startIdentified(grant: grant, targets: Set(request.targets), operationID: id,
            durable: journal != nil, work: work)
        let seconds: Int64
        if case .integer(let value) = prepared.request.parameters["timeoutSeconds"] { seconds = value }
        else { seconds = 120 }
        entries[id]?.deadlineTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, let entry = self.entries[id], !entry.state.isTerminal,
                  !entry.cancellationRequested else { return }
            self.entries[id]?.deadlineExpired = true
            self.entries[id]?.cancellationRequested = true
            self.entries[id]?.task?.cancel()
        }
        requests[key] = (prepared.value, id)
        return id
    }

    // App-owned handlers must obtain effect approval before they perform work.
    // This registry preserves identity and results. It does not grant approval.
    func startValueRequest(_ request: AgentRequest, grant: AgentGrant,
                           work: @escaping @MainActor (UUID) async throws -> [String: AgentJSONValue]) throws -> UUID {
        guard request.operation != "actions.run",
              AgentOperationJournal.supports(request.operation),
              request.libraryID == grant.libraryID else { throw AgentErrorCode.invalidInput }
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        switch AgentPermissionPolicy.evaluate(prepared.request, connectionID: grant.connectionID, grant: grant, now: now()) {
        case .denied(let error): throw error
        default: break
        }
        try validate(grant, targets: Set(request.targets), operationName: request.operation)
        if let previous = try existingRequest(prepared.request, grant: grant) { return previous }
        guard entries.count < capacity, requests.count < capacity else { throw AgentErrorCode.busy }
        let id = UUID()
        if let reservation = try journal?.reserve(prepared.request, grant: grant, operationID: id), !reservation.isNew {
            _ = try snapshot(reservation.record.operationID, connectionID: grant.connectionID)
            return reservation.record.operationID
        }
        entries[id] = Entry(connectionID: grant.connectionID, grant: grant, targets: Set(request.targets),
            updatedAt: now(), durable: journal != nil, name: request.operation)
        requests[RequestKey(connectionID: grant.connectionID, requestID: request.requestID)] = (prepared.value, id)
        entries[id]?.task = Task { @MainActor [weak self] in
            guard let self, self.entries[id] != nil else { return }
            do {
                try Task.checkCancellation()
                try self.validate(grant, targets: Set(request.targets), operationName: request.operation)
                self.entries[id]?.state = .running
                self.entries[id]?.updatedAt = self.now()
                let result = try await work(id)
                try AgentOperationSchemas.validateResult(result, for: prepared.request, preferences: AgentPreferenceCatalog.make())
                self.entries[id]?.deadlineTask?.cancel()
                self.entries[id]?.deadlineTask = nil
                self.entries[id]?.state = .succeeded
                self.entries[id]?.result = .object(result)
                self.entries[id]?.updatedAt = self.now()
                self.entries[id]?.task = nil
                self.persistCompletion(id)
            } catch is CancellationError {
                self.finish(id, error: self.entries[id]?.state == .queued ? .cancelled : .outcomeUnknown)
            } catch let error as AgentErrorCode {
                self.finish(id, error: self.entries[id]?.state == .queued ? error : .outcomeUnknown)
            } catch {
                self.finish(id, error: self.entries[id]?.state == .queued ? .storageError : .outcomeUnknown)
            }
        }
        entries[id]?.deadlineTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            guard let self, let entry = self.entries[id], !entry.state.isTerminal, !entry.cancellationRequested else { return }
            self.entries[id]?.deadlineExpired = true
            self.entries[id]?.cancellationRequested = true
            self.entries[id]?.task?.cancel()
        }
        return id
    }

    func existingRequest(_ request: AgentRequest, grant: AgentGrant) throws -> UUID? {
        try validate(grant, targets: Set(request.targets), operationName: request.operation)
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        let key = RequestKey(connectionID: grant.connectionID, requestID: request.requestID)
        let id: UUID
        if let previous = requests[key] {
            guard previous.value == prepared.value else { throw AgentErrorCode.versionConflict }
            id = previous.operationID
        } else if let record = try journal?.existingRequest(prepared.request, grant: grant) {
            id = record.operationID
        } else { return nil }
        _ = try snapshot(id, connectionID: grant.connectionID)
        return id
    }

    func startIdentified(grant: AgentGrant, targets: Set<AgentResourceReference>,
                         operationID: UUID = UUID(), durable: Bool = false,
                         work: @escaping @MainActor (UUID) async throws -> AutomationActionExecution.Output) throws -> UUID {
        try validate(grant, targets: targets)
        guard entries.count < capacity else { throw AgentErrorCode.busy }
        let id = operationID
        guard entries[id] == nil else { throw AgentErrorCode.versionConflict }
        entries[id] = Entry(connectionID: grant.connectionID, grant: grant, targets: targets, updatedAt: now())
        entries[id]?.durable = durable
        entries[id]?.task = Task { @MainActor [weak self] in
            guard let self, self.entries[id] != nil else { return }
            do {
                try Task.checkCancellation()
                try self.validate(grant, targets: targets)
                self.entries[id]?.state = .running
                self.entries[id]?.updatedAt = self.now()
                let output = try await work(id)
                self.finish(id, output: output)
            } catch is CancellationError {
                self.finish(id, error: self.entries[id]?.state == .queued ? .cancelled : .outcomeUnknown)
            } catch let error as AgentErrorCode {
                self.finish(id, error: self.entries[id]?.state == .queued ? error : .outcomeUnknown)
            } catch {
                self.finish(id, error: self.entries[id]?.state == .queued ? .storageError : .outcomeUnknown)
            }
        }
        return id
    }

    func snapshot(_ id: UUID, connectionID: UUID) throws -> Snapshot {
        guard let entry = entries[id] else { return try recoveredSnapshot(id, connectionID: connectionID) }
        guard entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        try validate(entry.grant, targets: entry.targets, operationName: entry.name)
        return Snapshot(id: id, state: entry.state, updatedAt: entry.updatedAt, output: entry.output,
            error: entry.error, effects: entry.effects, name: entry.name, result: entry.result)
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
            guard let grant = try currentGrant(connectionID), request.libraryID == grant.libraryID else {
                throw AgentErrorCode.permissionDenied
            }
            return (try recoveredSnapshot(target.id, connectionID: connectionID), false)
        }
        guard entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        guard request.libraryID == entry.grant.libraryID else { throw AgentErrorCode.permissionDenied }
        let accepted = request.operation == "operations.cancel" ? try cancel(target.id, connectionID: connectionID) : false
        return (try snapshot(target.id, connectionID: connectionID), accepted)
    }

    func cancel(_ id: UUID, connectionID: UUID) throws -> Bool {
        guard let entry = entries[id], entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        try validate(entry.grant, targets: entry.targets, operationName: entry.name)
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

    func setWaitingForUser(_ id: UUID, waiting: Bool) throws {
        guard let entry = entries[id] else { throw AgentErrorCode.notFound }
        try validate(entry.grant, targets: entry.targets, operationName: entry.name)
        guard !entry.cancellationRequested else { throw AgentErrorCode.cancelled }
        if waiting && entry.state == .running { entries[id]?.state = .waitingForUser }
        else if !waiting && entry.state == .waitingForUser { entries[id]?.state = .running }
        else { throw AgentErrorCode.versionConflict }
        entries[id]?.updatedAt = now()
    }

    func removeCompleted(_ id: UUID, connectionID: UUID) throws {
        guard let entry = entries[id], entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        try validate(entry.grant, targets: entry.targets, operationName: entry.name)
        guard entry.state.isTerminal else { throw AgentErrorCode.busy }
        entries.removeValue(forKey: id)
    }

    private func validate(_ original: AgentGrant, targets: Set<AgentResourceReference>, operationName: String = "actions.run") throws {
        guard let descriptor = AgentOperationCatalog.operation(named: operationName) else { throw AgentErrorCode.invalidInput }
        guard !isLocked() else { throw AgentErrorCode.permissionDenied }
        try validateHost()
        guard let current = try currentGrant(original.connectionID), !current.revoked,
              current.expiresAt.timeIntervalSince1970.isFinite, current.expiresAt > now(),
              current.capabilities.isSuperset(of: descriptor.capabilities),
              AgentRequestBinding.grantValue(current) == AgentRequestBinding.grantValue(original),
              targets.allSatisfy(current.scope.permits), !isLocked() else { throw AgentErrorCode.permissionDenied }
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
        let value = try Snapshot(id: id, state: entry.state, updatedAt: entry.updatedAt,
            output: entry.output, error: entry.error, effects: entry.effects, name: entry.name, result: entry.result).wireValue()
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
        guard let grant = try currentGrant(connectionID), grant.connectionID == connectionID else { throw AgentErrorCode.permissionDenied }
        guard let record = try journal.record(id, grant: grant) else { throw AgentErrorCode.notFound }
        try validate(grant, targets: [], operationName: record.operationName ?? "actions.run")
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
