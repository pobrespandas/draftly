import Foundation
import CryptoKit
import DraftlyCore
import AgentContracts

// Workspace snapshots and durable mutations share one version key.
@MainActor final class AgentWorkspaceAccess {
    static let operationNames: Set<String> = ["workspaces.create", "workspaces.update", "workspaces.duplicate"]
    private let library: LibraryStore
    private let libraryID: UUID
    private let versionKey: SymmetricKey
    private let retryKeys: AgentRetryKeys
    private let defaults: UserDefaults
    private let validateAdmission: () throws -> Void
    private let now: () -> Date

    init(library: LibraryStore, libraryID: UUID, versionKey: SymmetricKey,
         retryKeys: AgentRetryKeys, defaults: UserDefaults,
         validateAdmission: @escaping () throws -> Void, now: @escaping () -> Date) {
        self.library = library; self.libraryID = libraryID; self.versionKey = versionKey
        self.retryKeys = retryKeys; self.defaults = defaults
        self.validateAdmission = validateAdmission; self.now = now
    }

    func version(_ workspace: Workspace) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return Data(HMAC<SHA256>.authenticationCode(for: try encoder.encode(workspace), using: versionKey)).base64EncodedString()
    }

    private func checkedWorkspaceUpdate(_ request: AgentRequest) throws -> Workspace {
        guard let target = request.targets.first?.id, let expected = request.expectedVersion,
              let original = library.workspaces.first(where: { $0.id == target }) else { throw AgentErrorCode.notFound }
        guard try version(original) == expected else { throw AgentErrorCode.versionConflict }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentWorkspaceSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard let value = parameters["workspace"] else { throw AgentErrorCode.invalidInput }
        let updated: Workspace
        do { updated = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(value)) }
        catch { throw AgentErrorCode.invalidInput }
        guard updated.id == target, updated.order == original.order,
              !updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentErrorCode.invalidInput
        }
        return updated
    }

    private func checkedMutation(_ request: AgentRequest, generatedID: UUID? = nil) throws -> Workspace {
        if request.operation == "workspaces.update" { return try checkedWorkspaceUpdate(request) }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentWorkspaceSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        var value: Workspace
        if request.operation == "workspaces.create" {
            guard case .object(let input) = parameters["workspace"] else { throw AgentErrorCode.invalidInput }
            let base = WorkspaceDefaults.make(in: library, defaults: defaults)
            guard case .object(var definition) = try JSONDecoder().decode(AgentJSONValue.self,
                from: JSONEncoder().encode(base)) else { throw AgentErrorCode.storageError }
            definition.merge(input) { _, new in new }
            if input["id"] == nil, let generatedID { definition["id"] = .string(generatedID.uuidString) }
            do { value = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(AgentJSONValue.object(definition))) }
            catch { throw AgentErrorCode.invalidInput }
        } else if request.operation == "workspaces.duplicate" {
            guard let target = request.targets.first?.id,
                  let original = library.workspaces.first(where: { $0.id == target }) else { throw AgentErrorCode.notFound }
            guard let expected = request.expectedVersion, try version(original) == expected else {
                throw AgentErrorCode.versionConflict
            }
            value = original
            value.id = generatedID ?? UUID()
            if case .string(let name) = parameters["name"] { value.name = name }
            else { value.name += " Copy" }
        } else { throw AgentErrorCode.unavailable }
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentErrorCode.invalidInput }
        guard !library.workspaces.contains(where: { $0.id == value.id }) else { throw AgentErrorCode.versionConflict }
        return value
    }

    private func workspaceReceipt(_ request: AgentRequest, ticket: AgentRetryKeys.Ticket) throws -> LibraryMutationReceipt? {
        let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        do {
            let receipt = try library.mutationReceipt(for: identity, at: now())
            guard let receipt else { return nil }
            guard receipt.resources.count == 1, let resource = receipt.resources.first else { throw AgentErrorCode.storageError }
            switch request.operation {
            case "workspaces.update":
                guard resource.id == request.targets.first?.id else { throw AgentErrorCode.storageError }
            case "workspaces.duplicate":
                guard resource.id != request.targets.first?.id else { throw AgentErrorCode.storageError }
            case "workspaces.create":
                if case .object(let input) = request.parameters["workspace"], case .string(let rawID) = input["id"] {
                    guard UUID(uuidString: rawID) == resource.id else { throw AgentErrorCode.storageError }
                }
            default: throw AgentErrorCode.unavailable
            }
            return receipt
        } catch let error as LibraryMutationReceiptError {
            switch error {
            case .requestConflict: throw AgentErrorCode.invalidInput
            case .retryWindowExpired: throw AgentErrorCode.retryWindowExpired
            case .pendingChanges: throw AgentErrorCode.busy
            case .invalidReceipt: throw AgentErrorCode.storageError
            }
        }
    }

    func prepare(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
        guard Self.operationNames.contains(request.operation), request.retryKey == nil, request.libraryID == libraryID else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try retryKeys.issue(request, connectionID: connectionID)
        if try workspaceReceipt(request, ticket: ticket) == nil { _ = try checkedMutation(request) }
        try validateAdmission(); _ = try retryKeys.verify(ticket.value, request: request, connectionID: connectionID)
        return ticket
    }

    func update(_ request: AgentRequest, connectionID: UUID) throws -> LibraryMutationReceipt {
        guard Self.operationNames.contains(request.operation), request.libraryID == libraryID, let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try retryKeys.verify(key, request: request, connectionID: connectionID)
        if let previous = try workspaceReceipt(request, ticket: ticket) {
            try validateAdmission(); _ = try retryKeys.verify(key, request: request, connectionID: connectionID)
            return previous
        }
        let updated = try checkedMutation(request)
        let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        do {
            return try library.commitWorkspaces([updated], mutation: identity, at: now(), validateCommit: {
                try self.validateAdmission(); _ = try self.retryKeys.verify(key, request: request, connectionID: connectionID)
                guard try self.checkedMutation(request, generatedID: updated.id) == updated else { throw AgentErrorCode.versionConflict }
            }, makeResources: { values in
                try values.map { .init(id: $0.id, versionToken: try self.version($0)) }
            })
        } catch let error as AgentErrorCode { throw error }
        catch { throw AgentErrorCode.storageError }
    }

}
