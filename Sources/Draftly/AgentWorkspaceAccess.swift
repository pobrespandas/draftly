import Foundation
import CryptoKit
import DraftlyCore
import AgentContracts

// Workspace snapshots and durable mutations share one version key.
@MainActor final class AgentWorkspaceAccess {
    static let operationNames: Set<String> = ["workspaces.create", "workspaces.update", "workspaces.duplicate", "workspaces.reorder"]
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

    func orderVersion() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let records = library.workspaces.sorted { $0.id.uuidString < $1.id.uuidString }
        let data = Data("workspace-order\n".utf8) + (try encoder.encode(records))
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: versionKey)).base64EncodedString()
    }

    private func checkedOrder(_ request: AgentRequest) throws -> [Workspace] {
        guard let expected = request.expectedVersion, try orderVersion() == expected else { throw AgentErrorCode.versionConflict }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentWorkspaceSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard case .array(let order) = parameters["order"] else { throw AgentErrorCode.invalidInput }
        let byID = Dictionary(uniqueKeysWithValues: library.workspaces.map { ($0.id, $0) })
        let ids = order.compactMap { item -> UUID? in
            guard case .string(let raw) = item else { return nil }; return UUID(uuidString: raw)
        }
        guard ids.count == byID.count, Set(ids) == Set(byID.keys) else { throw AgentErrorCode.versionConflict }
        return try ids.enumerated().map { index, id in
            guard var value = byID[id] else { throw AgentErrorCode.versionConflict }
            value.order = index
            return value
        }
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

    private func checkedDeletion(_ request: AgentRequest) throws -> Workspace {
        guard request.operation == "workspaces.delete", request.libraryID == libraryID,
              request.targets.count == 1, let target = request.targets.first, target.kind == .workspace,
              let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
        do { _ = try AgentWorkspaceSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard let workspace = library.workspaces.first(where: { $0.id == target.id }) else { throw AgentErrorCode.notFound }
        guard try version(workspace) == expected else { throw AgentErrorCode.versionConflict }
        return workspace
    }

    func prepareDeletion(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
        guard request.operation == "workspaces.delete", request.retryKey == nil,
              request.libraryID == libraryID else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try retryKeys.issue(request, connectionID: connectionID)
        if try workspaceReceipt(request, ticket: ticket) == nil { _ = try checkedDeletion(request) }
        try validateAdmission()
        _ = try retryKeys.verify(ticket.value, request: request, connectionID: connectionID)
        return ticket
    }

    func deletionReceipt(_ request: AgentRequest, connectionID: UUID) throws -> LibraryMutationReceipt? {
        guard request.operation == "workspaces.delete", request.libraryID == libraryID,
              let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try retryKeys.verify(key, request: request, connectionID: connectionID)
        return try workspaceReceipt(request, ticket: ticket)
    }

    func deletionEffects(_ request: AgentRequest, connectionID: UUID) throws -> AgentApprovalStore.Effects {
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        _ = try retryKeys.verify(key, request: request, connectionID: connectionID)
        let workspace = try checkedDeletion(request)
        return .init(capabilities: [.workspacesManage, .destructiveRequest], targets: Set(request.targets),
            requiresLibraryScope: false, snapshot: ["workspaceName": .string(workspace.name),
                "workspaceVersion": .string(try version(workspace)), "deletesDrafts": .bool(false)])
    }

    // The caller must consume the exact app-owned review before this commit.
    func delete(_ request: AgentRequest, connectionID: UUID,
                validateCommit: () throws -> Void) throws -> LibraryMutationReceipt {
        if let previous = try deletionReceipt(request, connectionID: connectionID) { return previous }
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        let ticket = try retryKeys.verify(key, request: request, connectionID: connectionID)
        let workspace = try checkedDeletion(request)
        let identity = LibraryMutationIdentity(requestID: request.requestID,
            connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        do {
            return try library.commitWorkspaceDeletion(workspace.id, mutation: identity, at: now(),
                resource: .init(id: workspace.id, versionToken: try version(workspace)), validateCommit: {
                    try self.validateAdmission()
                    _ = try self.retryKeys.verify(key, request: request, connectionID: connectionID)
                    guard try self.checkedDeletion(request) == workspace else { throw AgentErrorCode.versionConflict }
                    try validateCommit()
                })
        } catch let error as AgentErrorCode { throw error }
        catch { throw AgentErrorCode.storageError }
    }

    func reviewAndDelete(_ request: AgentRequest, connectionID: UUID,
                         operationID: UUID, approvals: AgentApprovalStore,
                         operations: AgentOperationRegistry,
                         validateSession: () throws -> Void) async throws -> [String: AgentJSONValue] {
        var submitted = false
        do {
            try Task.checkCancellation()
            try validateSession()
            if let receipt = try deletionReceipt(request, connectionID: connectionID) {
                return ["deletedIDs": .array(receipt.resources.map { .string($0.id.uuidString) })]
            }
            try operations.setWaitingForUser(operationID, waiting: true)
            try await approvals.waitForApproval(request, connectionID: connectionID, resolveEffects: {
                try validateSession()
                return try self.deletionEffects(request, connectionID: connectionID)
            })
            try operations.setWaitingForUser(operationID, waiting: false)
            try Task.checkCancellation()
            try validateSession()
            let effectID = UUID()
            let receipt = try delete(request, connectionID: connectionID, validateCommit: {
                try Task.checkCancellation()
                try validateSession()
                try operations.recordEffect(operationID, effectID: effectID,
                    kind: "workspaces.delete", outcome: "submitted")
                submitted = true
            })
            try operations.recordEffect(operationID, effectID: effectID,
                kind: "workspaces.delete", outcome: "completed")
            return ["deletedIDs": .array(receipt.resources.map { .string($0.id.uuidString) })]
        } catch {
            if submitted { throw AgentErrorCode.outcomeUnknown }
            let code = error is CancellationError ? AgentErrorCode.cancelled : (error as? AgentErrorCode ?? .storageError)
            throw AgentOperationRegistry.FailureBeforeEffects(code: code)
        }
    }

    private func workspaceReceipt(_ request: AgentRequest, ticket: AgentRetryKeys.Ticket) throws -> LibraryMutationReceipt? {
        let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        do {
            let receipt = try library.mutationReceipt(for: identity, at: now())
            guard let receipt else { return nil }
            if request.operation == "workspaces.reorder" {
                guard receipt.resources.count == request.targets.count,
                      Set(receipt.resources.map(\.id)) == Set(request.targets.map(\.id)) else { throw AgentErrorCode.storageError }
                return receipt
            }
            guard receipt.resources.count == 1, let resource = receipt.resources.first else { throw AgentErrorCode.storageError }
            switch request.operation {
            case "workspaces.update", "workspaces.delete":
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
        if try workspaceReceipt(request, ticket: ticket) == nil {
            if request.operation == "workspaces.reorder" { _ = try checkedOrder(request) }
            else { _ = try checkedMutation(request) }
        }
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
        let updated: [Workspace]
        if request.operation == "workspaces.reorder" { updated = try checkedOrder(request) }
        else { updated = [try checkedMutation(request)] }
        let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        do {
            return try library.commitWorkspaces(updated, mutation: identity, at: now(), validateCommit: {
                try self.validateAdmission(); _ = try self.retryKeys.verify(key, request: request, connectionID: connectionID)
                let current: [Workspace]
                if request.operation == "workspaces.reorder" { current = try self.checkedOrder(request) }
                else { current = [try self.checkedMutation(request, generatedID: updated.first?.id)] }
                guard current == updated else { throw AgentErrorCode.versionConflict }
            }, makeResources: { values in
                try values.map { .init(id: $0.id, versionToken: try self.version($0)) }
            })
        } catch let error as AgentErrorCode { throw error }
        catch { throw AgentErrorCode.storageError }
    }

}
