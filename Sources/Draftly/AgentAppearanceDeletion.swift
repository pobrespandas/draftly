import Foundation
import DraftlyCore
import AgentContracts

// The destructive review binds the stored definition. Source files are not read.
@MainActor final class AgentAppearanceDeletion {
    let library: LibraryStore
    let libraryID: UUID
    let reader: AgentThemeReading
    let syntaxVersion: (SyntaxDefinition) throws -> String
    let retryKeys: AgentRetryKeys
    let defaults: UserDefaults
    let now: () -> Date
    let validateAdmission: () throws -> Void
    init(library: LibraryStore, libraryID: UUID, reader: AgentThemeReading, keys: AgentRetryKeys,
         defaults: UserDefaults, syntaxVersion: @escaping (SyntaxDefinition) throws -> String, now: @escaping () -> Date, validateAdmission: @escaping () throws -> Void) {
        self.library = library; self.libraryID = libraryID; self.reader = reader; self.retryKeys = keys
        self.defaults = defaults; self.syntaxVersion = syntaxVersion; self.now = now; self.validateAdmission = validateAdmission
    }
    static let operationNames: Set<String> = ["themes.delete", "syntaxes.delete"]

    private struct Definition: Equatable {
        let id: UUID
        let name: String
        let version: String
    }
    private func storedReceipt(_ request: AgentRequest, ticket: AgentRetryKeys.Ticket) throws -> LibraryMutationReceipt? {
        do {
            let receipt = try library.mutationReceipt(for: .init(requestID: request.requestID,
                connectionHash: ticket.connectionHash, requestHash: ticket.requestHash), at: now())
            if let receipt {
                guard receipt.resources.count == 1, receipt.resources.first?.id == request.targets.first?.id else {
                    throw AgentErrorCode.storageError
                }
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
    func cleanupBookmark(_ request: AgentRequest, validate: () throws -> Void) throws {
        try validate()
        guard let id = request.targets.first?.id else { throw AgentErrorCode.invalidInput }
        // A recovered receipt must not change a replacement with the same ID.
        let key: String
        if request.operation == "syntaxes.delete" {
            guard !library.syntaxes.contains(where: { $0.id == id }) else { return }
            key = SyntaxFileAccess.bookmarkKey(for: id)
        } else {
            guard !library.themes.contains(where: { $0.id == id }) else { return }
            key = ThemeFileAccess.bookmarkKey(for: id)
        }
        defaults.removeObject(forKey: key)
        guard defaults.object(forKey: key) == nil else { throw AgentErrorCode.storageError }
        try validate()
    }
    private func checkedDeletion(_ request: AgentRequest) throws -> Definition {
        guard Self.operationNames.contains(request.operation), request.libraryID == libraryID,
              request.targets.count == 1, let target = request.targets.first,
              let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
        do { _ = try AgentAppearanceSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        let definition: Definition
        if request.operation == "syntaxes.delete", target.kind == .syntax {
            guard let syntax = library.syntaxes.first(where: { $0.id == target.id && $0.type != "builtIn" }) else {
                throw AgentErrorCode.notFound
            }
            definition = try Definition(id: syntax.id, name: syntax.name, version: syntaxVersion(syntax))
            guard definition.version == expected else { throw AgentErrorCode.versionConflict }
            // Drafts store the syntax name. Leave the definition installed while it is in use.
            guard !library.notes.contains(where: { $0.syntax == syntax.name }) else { throw AgentErrorCode.invalidInput }
        } else if request.operation == "themes.delete", target.kind == .theme {
            guard let theme = library.themes.first(where: { $0.id == target.id }) else { throw AgentErrorCode.notFound }
            definition = try Definition(id: theme.id, name: theme.name, version: reader.version(theme))
            guard definition.version == expected else { throw AgentErrorCode.versionConflict }
        } else { throw AgentErrorCode.invalidInput }
        return definition
    }

    func prepareDeletion(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
        guard Self.operationNames.contains(request.operation), request.retryKey == nil,
              request.libraryID == libraryID else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try retryKeys.issue(request, connectionID: connectionID)
        if try storedReceipt(request, ticket: ticket) == nil { _ = try checkedDeletion(request) }
        try validateAdmission()
        _ = try retryKeys.verify(ticket.value, request: request, connectionID: connectionID)
        return ticket
    }

    func deletionReceipt(_ request: AgentRequest, connectionID: UUID) throws -> LibraryMutationReceipt? {
        guard Self.operationNames.contains(request.operation), request.libraryID == libraryID,
              let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try retryKeys.verify(key, request: request, connectionID: connectionID)
        return try storedReceipt(request, ticket: ticket)
    }

    func deletionEffects(_ request: AgentRequest, connectionID: UUID) throws -> AgentApprovalStore.Effects {
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        _ = try retryKeys.verify(key, request: request, connectionID: connectionID)
        let definition = try checkedDeletion(request)
        let prefix = request.operation == "syntaxes.delete" ? "syntax" : "theme"
        return .init(capabilities: [.appearanceManage, .destructiveRequest], targets: Set(request.targets),
            requiresLibraryScope: false, snapshot: [prefix + "Name": .string(definition.name),
                prefix + "Version": .string(definition.version), "deletesDrafts": .bool(false), "deletesSourceFile": .bool(false)])
    }

    // The caller must consume the exact app-owned review before this commit.
    func delete(_ request: AgentRequest, connectionID: UUID,
                validateCommit: @escaping () throws -> Void) throws -> LibraryMutationReceipt {
        if let previous = try deletionReceipt(request, connectionID: connectionID) { return previous }
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        let ticket = try retryKeys.verify(key, request: request, connectionID: connectionID)
        let definition = try checkedDeletion(request)
        let identity = LibraryMutationIdentity(requestID: request.requestID,
            connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        do {
            let resource = LibraryMutationReceipt.Resource(id: definition.id, versionToken: definition.version)
            let validate = {
                try self.validateAdmission()
                _ = try self.retryKeys.verify(key, request: request, connectionID: connectionID)
                guard try self.checkedDeletion(request) == definition else { throw AgentErrorCode.versionConflict }
                try validateCommit()
            }
            if request.operation == "syntaxes.delete" {
                return try library.commitSyntaxDeletion(definition.id, mutation: identity, at: now(),
                    resource: resource, validateCommit: validate)
            }
            return try library.commitThemeDeletion(definition.id, mutation: identity, at: now(),
                resource: resource, validateCommit: validate)
        } catch let error as AgentErrorCode { throw error }
        catch { throw AgentErrorCode.storageError }
    }

    func reviewAndDelete(_ request: AgentRequest, connectionID: UUID,
                         operationID: UUID, approvals: AgentApprovalStore,
                         operations: AgentOperationRegistry,
                         validateSession: @escaping () throws -> Void) async throws -> [String: AgentJSONValue] {
        var submitted = false
        do {
            try Task.checkCancellation()
            try validateSession()
            if let receipt = try deletionReceipt(request, connectionID: connectionID) {
                try cleanupBookmark(request, validate: validateSession)
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
                    kind: request.operation, outcome: "submitted")
                submitted = true
            })
            try cleanupBookmark(request, validate: validateSession)
            try operations.recordEffect(operationID, effectID: effectID,
                kind: request.operation, outcome: "completed")
            return ["deletedIDs": .array(receipt.resources.map { .string($0.id.uuidString) })]
        } catch {
            if submitted { throw AgentErrorCode.outcomeUnknown }
            let code = error is CancellationError ? AgentErrorCode.cancelled : (error as? AgentErrorCode ?? .storageError)
            throw AgentOperationRegistry.FailureBeforeEffects(code: code)
        }
    }

}
