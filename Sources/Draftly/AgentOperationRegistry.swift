import Foundation
import AgentContracts

// In-memory operation ownership. It does not provide restart recovery.
@MainActor final class AgentOperationRegistry {
    struct Snapshot {
        let id: UUID
        let state: AgentOperationState
        let updatedAt: Date
        let output: AutomationActionExecution.Output?
        let error: AgentErrorCode?
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
    }
    private var entries: [UUID: Entry] = [:]
    private let currentGrant: (UUID) throws -> AgentGrant?
    private let validateHost: () throws -> Void
    private let isLocked: () -> Bool
    private let now: () -> Date
    private let capacity: Int

    init(capacity: Int = 128, currentGrant: @escaping (UUID) throws -> AgentGrant?,
         validateHost: @escaping () throws -> Void, isLocked: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init) {
        self.capacity = max(1, capacity); self.currentGrant = currentGrant
        self.validateHost = validateHost; self.isLocked = isLocked; self.now = now
    }

    func start(grant: AgentGrant, targets: Set<AgentResourceReference>,
               work: @escaping @MainActor () async throws -> AutomationActionExecution.Output) throws -> UUID {
        try startIdentified(grant: grant, targets: targets) { _ in try await work() }
    }

    func startIdentified(grant: AgentGrant, targets: Set<AgentResourceReference>,
                         work: @escaping @MainActor (UUID) async throws -> AutomationActionExecution.Output) throws -> UUID {
        try validate(grant, targets: targets)
        guard entries.count < capacity else { throw AgentErrorCode.busy }
        let id = UUID()
        entries[id] = Entry(connectionID: grant.connectionID, grant: grant, targets: targets, updatedAt: now())
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
        guard let entry = entries[id], entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        try validate(entry.grant, targets: entry.targets)
        return Snapshot(id: id, state: entry.state, updatedAt: entry.updatedAt, output: entry.output, error: entry.error)
    }

    func control(_ request: AgentRequest, connectionID: UUID) throws -> (snapshot: Snapshot, cancellationAccepted: Bool) {
        guard ["operations.get", "operations.cancel"].contains(request.operation),
              request.targets.count == 1, let target = request.targets.first, target.kind == .operation,
              request.parameters.isEmpty else { throw AgentErrorCode.invalidInput }
        guard let entry = entries[target.id], entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        guard request.libraryID == entry.grant.libraryID else { throw AgentErrorCode.permissionDenied }
        let accepted = request.operation == "operations.cancel" ? try cancel(target.id, connectionID: connectionID) : false
        return (try snapshot(target.id, connectionID: connectionID), accepted)
    }

    func cancel(_ id: UUID, connectionID: UUID) throws -> Bool {
        guard let entry = entries[id], entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        try validate(entry.grant, targets: entry.targets)
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
        try validate(entry.grant, targets: entry.targets)
        guard !entry.cancellationRequested else { throw AgentErrorCode.cancelled }
        if waiting && entry.state == .running { entries[id]?.state = .waitingForUser }
        else if !waiting && entry.state == .waitingForUser { entries[id]?.state = .running }
        else { throw AgentErrorCode.versionConflict }
        entries[id]?.updatedAt = now()
    }

    func removeCompleted(_ id: UUID, connectionID: UUID) throws {
        guard let entry = entries[id], entry.connectionID == connectionID else { throw AgentErrorCode.notFound }
        try validate(entry.grant, targets: entry.targets)
        guard entry.state.isTerminal else { throw AgentErrorCode.busy }
        entries.removeValue(forKey: id)
    }

    private func validate(_ original: AgentGrant, targets: Set<AgentResourceReference>) throws {
        guard !isLocked() else { throw AgentErrorCode.permissionDenied }
        try validateHost()
        guard let current = try currentGrant(original.connectionID), !current.revoked,
              current.expiresAt.timeIntervalSince1970.isFinite, current.expiresAt > now(),
              current.capabilities.isSuperset(of: [.actionsRun, .draftsRead]),
              AgentRequestBinding.grantValue(current) == AgentRequestBinding.grantValue(original),
              targets.allSatisfy(current.scope.permits), !isLocked() else { throw AgentErrorCode.permissionDenied }
    }

    private func finish(_ id: UUID, output: AutomationActionExecution.Output) {
        guard let entry = entries[id], !entry.state.isTerminal else { return }
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
    }

    private func finish(_ id: UUID, error: AgentErrorCode) {
        guard let entry = entries[id], !entry.state.isTerminal else { return }
        entries[id]?.state = error == .cancelled ? .cancelled : error == .timeout ? .timedOut
            : error == .outcomeUnknown ? .outcomeUnknown : .failed
        entries[id]?.error = error; entries[id]?.task = nil
        entries[id]?.updatedAt = now()
    }
}
