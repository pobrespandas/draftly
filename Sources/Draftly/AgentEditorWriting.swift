import Foundation
import AgentContracts

// Editor receipts belong to this host lifetime. Old keys cannot select a new window.
@MainActor final class AgentEditorWriting {
    struct Context {
        let snapshot: AgentEditorRegistry.WindowSnapshot
        let version: String
    }
    private struct Receipt {
        let owner: String
        var result: [String: AgentJSONValue]?
    }
    private let registry: AgentEditorRegistry
    private let keys: AgentRetryKeys
    private let currentGrant: (UUID) throws -> AgentGrant?
    private let validateAdmission: () throws -> Void
    private let read: (UUID, AgentGrant) throws -> Context
    private var receipts: [String: Receipt] = [:]

    init(registry: AgentEditorRegistry, keys: AgentRetryKeys,
         currentGrant: @escaping (UUID) throws -> AgentGrant?, validateAdmission: @escaping () throws -> Void,
         read: @escaping (UUID, AgentGrant) throws -> Context) {
        self.registry = registry; self.keys = keys; self.currentGrant = currentGrant
        self.validateAdmission = validateAdmission; self.read = read
    }

    func prepare(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
        guard request.retryKey == nil else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try keys.issue(request, connectionID: connectionID)
        if try previous(ticket) == nil {
            guard receipts.count < 128 else { throw AgentErrorCode.busy }
            _ = try checked(request, connectionID: connectionID)
        }
        try validateAdmission()
        _ = try keys.verify(ticket.value, request: request, connectionID: connectionID)
        return ticket
    }

    func update(_ request: AgentRequest, connectionID: UUID) throws -> [String: AgentJSONValue] {
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try keys.verify(key, request: request, connectionID: connectionID)
        if let result = try previous(ticket) { return result }
        guard receipts.count < 128 else { throw AgentErrorCode.busy }
        let (context, range) = try checked(request, connectionID: connectionID)
        receipts[ticket.requestHash] = Receipt(owner: ticket.connectionHash)
        do {
            try registry.setSelection(context.snapshot, range: range, authorize: {
                try self.validateAdmission()
                _ = try self.keys.verify(key, request: request, connectionID: connectionID)
            })
            guard let grant = try currentGrant(connectionID) else { throw AgentErrorCode.permissionDenied }
            let updated = try read(context.snapshot.id, grant)
            guard updated.snapshot.draftID == context.snapshot.draftID, updated.snapshot.selection == range else {
                throw AgentErrorCode.outcomeUnknown
            }
            try validateAdmission()
            _ = try keys.verify(key, request: request, connectionID: connectionID)
            let result: [String: AgentJSONValue] = [
                "windowID": .string(updated.snapshot.id.uuidString),
                "draftID": updated.snapshot.draftID.map { .string($0.uuidString) } ?? .null,
                "versionToken": .string(updated.version),
                "selection": .object(["offset": .integer(Int64(range.location)), "length": .integer(Int64(range.length))])
            ]
            receipts[ticket.requestHash]?.result = result
            return result
        } catch { throw AgentErrorCode.outcomeUnknown }
    }

    private func previous(_ ticket: AgentRetryKeys.Ticket) throws -> [String: AgentJSONValue]? {
        guard let receipt = receipts[ticket.requestHash] else { return nil }
        guard receipt.owner == ticket.connectionHash else { throw AgentErrorCode.permissionDenied }
        guard let result = receipt.result else { throw AgentErrorCode.outcomeUnknown }
        return result
    }

    private func checked(_ request: AgentRequest, connectionID: UUID) throws -> (Context, NSRange) {
        guard request.operation == "editor.setSelection", request.targets.count == 1,
              let target = request.targets.first, target.kind == .window,
              let grant = try currentGrant(connectionID), grant.connectionID == connectionID else {
            throw AgentErrorCode.invalidInput
        }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentEditorSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        let context = try read(target.id, grant)
        guard context.snapshot.draftID != nil else { throw AgentErrorCode.notFound }
        guard context.version == request.expectedVersion else { throw AgentErrorCode.versionConflict }
        let text = context.snapshot.content as NSString
        let bounds: (offset: Int64, end: Int64)
        do { bounds = try AgentTextShapes.bounds(parameters["range"], totalLength: Int64(text.length)) }
        catch { throw AgentErrorCode.invalidInput }
        guard let start = Int(exactly: bounds.offset), let end = Int(exactly: bounds.end),
              AgentTextShapes.isScalarBoundary(start, in: text), AgentTextShapes.isScalarBoundary(end, in: text) else {
            throw AgentErrorCode.invalidInput
        }
        return (context, NSRange(location: start, length: end - start))
    }
}
