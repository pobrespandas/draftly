import Foundation
import AgentContracts

// Prepared snapshots and receipts belong to one host lifetime.
@MainActor final class AgentPreferenceWriting {
    static let operationNames: Set<String> = ["preferences.update", "preferences.reset"]
    private enum State {
        case prepared(AgentPreferenceStorage.Snapshot)
        case unknown
        case completed([String: AgentJSONValue])
    }
    private struct Entry {
        let requestHash: String
        let authority: AgentJSONValue
        var state: State
    }
    private let storage: AgentPreferenceStorage
    private let keys: AgentRetryKeys
    private let preferences: AgentPreferenceRegistry
    private let currentGrant: (UUID) throws -> AgentGrant?
    private let validateAdmission: () throws -> Void
    private let plan: (AgentRequest, AgentGrant) throws -> AgentPreferenceBatch
    private let readReceipt: (AgentRequest, AgentGrant) throws -> [String: AgentJSONValue]
    private var entries: [String: Entry] = [:]
    private var updating = false

    init(storage: AgentPreferenceStorage, keys: AgentRetryKeys, preferences: AgentPreferenceRegistry,
         currentGrant: @escaping (UUID) throws -> AgentGrant?, validateAdmission: @escaping () throws -> Void,
         plan: @escaping (AgentRequest, AgentGrant) throws -> AgentPreferenceBatch,
         readReceipt: @escaping (AgentRequest, AgentGrant) throws -> [String: AgentJSONValue]) {
        self.storage = storage; self.keys = keys; self.preferences = preferences
        self.currentGrant = currentGrant; self.validateAdmission = validateAdmission
        self.plan = plan; self.readReceipt = readReceipt
    }

    func prepare(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        guard request.retryKey == nil else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try keys.issue(request, connectionID: connectionID)
        if let entry = try entry(ticket, request: request, connectionID: connectionID) {
            switch entry.state {
            case .unknown: throw AgentErrorCode.outcomeUnknown
            case .prepared(let before):
                _ = try checkedPlan(request, grant: authority(connectionID))
                guard try storage.snapshot().version == before.version else { throw AgentErrorCode.versionConflict }
            case .completed: break
            }
            try validateAdmission()
            _ = try keys.verify(ticket.value, request: request, connectionID: connectionID)
            return ticket
        }
        guard entries.count < 128 else { throw AgentErrorCode.busy }
        let before = try storage.snapshot()
        let grant = try authority(connectionID)
        _ = try checkedPlan(request, grant: grant)
        guard try storage.snapshot().version == before.version else { throw AgentErrorCode.versionConflict }
        try validateAdmission()
        _ = try keys.verify(ticket.value, request: request, connectionID: connectionID)
        entries[identity(ticket, request)] = Entry(requestHash: ticket.requestHash,
            authority: AgentRequestBinding.grantValue(grant), state: .prepared(before))
        return ticket
    }

    func update(_ request: AgentRequest, connectionID: UUID) throws -> [String: AgentJSONValue] {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try keys.verify(key, request: request, connectionID: connectionID)
        guard let entry = try entry(ticket, request: request, connectionID: connectionID) else { throw AgentErrorCode.invalidInput }
        let before: AgentPreferenceStorage.Snapshot
        switch entry.state {
        case .completed(let result): return result
        case .unknown: throw AgentErrorCode.outcomeUnknown
        case .prepared(let value): before = value
        }
        let grant = try authority(connectionID)
        let batch = try checkedPlan(request, grant: grant)
        let id = identity(ticket, request)
        let authorize = {
            try self.validateAdmission()
            _ = try self.keys.verify(key, request: request, connectionID: connectionID)
            guard try AgentRequestBinding.grantValue(self.authority(connectionID)) == entry.authority else {
                throw AgentErrorCode.permissionDenied
            }
        }
        entries[id]?.state = .unknown
        let committed: AgentPreferenceStorage.Snapshot
        do { committed = try storage.commit(batch.storage, against: before, authorize: authorize) }
        catch {
            if (error as? AgentErrorCode) != .outcomeUnknown { entries[id]?.state = .prepared(before) }
            throw error
        }
        do {
            let result = try readReceipt(request, grant)
            try AgentPreferenceSchemas.validateResult(result, for: request, registry: preferences)
            try authorize()
            guard try storage.snapshot().version == committed.version else { throw AgentErrorCode.outcomeUnknown }
            entries[id]?.state = .completed(result)
            return result
        } catch { throw AgentErrorCode.outcomeUnknown }
    }

    private func checkedPlan(_ request: AgentRequest, grant: AgentGrant) throws -> AgentPreferenceBatch {
        guard Self.operationNames.contains(request.operation), request.targets.isEmpty else { throw AgentErrorCode.invalidInput }
        _ = try AgentPreferenceSchemas.validatedParameters(for: request, registry: preferences)
        let before = try readReceipt(request, grant)
        guard before["versionToken"] == request.expectedVersion.map(AgentJSONValue.string) else { throw AgentErrorCode.versionConflict }
        let batch = try plan(request, grant)
        guard !batch.requiresHumanApproval && batch.native.isEmpty else {
            throw request.parameters["interactive"] == .bool(true) ? AgentErrorCode.unavailable : .interactionRequired
        }
        return batch
    }

    private func authority(_ connectionID: UUID) throws -> AgentGrant {
        guard let grant = try currentGrant(connectionID), grant.connectionID == connectionID else { throw AgentErrorCode.permissionDenied }
        return grant
    }

    private func identity(_ ticket: AgentRetryKeys.Ticket, _ request: AgentRequest) -> String {
        ticket.connectionHash + "/" + request.requestID.uuidString
    }

    private func entry(_ ticket: AgentRetryKeys.Ticket, request: AgentRequest, connectionID: UUID) throws -> Entry? {
        guard let entry = entries[identity(ticket, request)] else { return nil }
        guard entry.authority == (try AgentRequestBinding.grantValue(authority(connectionID))) else { throw AgentErrorCode.permissionDenied }
        guard entry.requestHash == ticket.requestHash else { throw AgentErrorCode.invalidInput }
        return entry
    }
}
