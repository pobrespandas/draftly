import Foundation
import DraftlyCore
import AgentContracts

// The destructive review binds the stored definition. Source files are not read.
@MainActor final class AgentThemeDeletion {
    let library: LibraryStore
    let libraryID: UUID
    let reader: AgentThemeReading
    let retryKeys: AgentRetryKeys
    let defaults: UserDefaults
    let now: () -> Date
    let validateAdmission: () throws -> Void
    init(library: LibraryStore, libraryID: UUID, reader: AgentThemeReading, keys: AgentRetryKeys,
         defaults: UserDefaults, now: @escaping () -> Date, validateAdmission: @escaping () throws -> Void) {
        self.library = library; self.libraryID = libraryID; self.reader = reader; self.retryKeys = keys
        self.defaults = defaults; self.now = now; self.validateAdmission = validateAdmission
    }
    private func version(_ theme: EditorThemeDefinition) throws -> String { try reader.version(theme) }
    private func themeReceipt(_ request: AgentRequest, ticket: AgentRetryKeys.Ticket) throws -> LibraryMutationReceipt? {
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
        guard !library.themes.contains(where: { $0.id == id }) else { return }
        let key = ThemeFileAccess.bookmarkKey(for: id)
        defaults.removeObject(forKey: key)
        guard defaults.object(forKey: key) == nil else { throw AgentErrorCode.storageError }
        try validate()
    }
    private func checkedDeletion(_ request: AgentRequest) throws -> EditorThemeDefinition {
        guard request.operation == "themes.delete", request.libraryID == libraryID,
              request.targets.count == 1, let target = request.targets.first, target.kind == .theme,
              let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
        do { _ = try AgentAppearanceSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard let theme = library.themes.first(where: { $0.id == target.id }) else { throw AgentErrorCode.notFound }
        guard try version(theme) == expected else { throw AgentErrorCode.versionConflict }
        return theme
    }

    func prepareDeletion(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
        guard request.operation == "themes.delete", request.retryKey == nil,
              request.libraryID == libraryID else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try retryKeys.issue(request, connectionID: connectionID)
        if try themeReceipt(request, ticket: ticket) == nil { _ = try checkedDeletion(request) }
        try validateAdmission()
        _ = try retryKeys.verify(ticket.value, request: request, connectionID: connectionID)
        return ticket
    }

    func deletionReceipt(_ request: AgentRequest, connectionID: UUID) throws -> LibraryMutationReceipt? {
        guard request.operation == "themes.delete", request.libraryID == libraryID,
              let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try retryKeys.verify(key, request: request, connectionID: connectionID)
        return try themeReceipt(request, ticket: ticket)
    }

    func deletionEffects(_ request: AgentRequest, connectionID: UUID) throws -> AgentApprovalStore.Effects {
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        _ = try retryKeys.verify(key, request: request, connectionID: connectionID)
        let theme = try checkedDeletion(request)
        return .init(capabilities: [.appearanceManage, .destructiveRequest], targets: Set(request.targets),
            requiresLibraryScope: false, snapshot: ["themeName": .string(theme.name),
                "themeVersion": .string(try version(theme)), "deletesDrafts": .bool(false), "deletesSourceFile": .bool(false)])
    }

    // The caller must consume the exact app-owned review before this commit.
    func delete(_ request: AgentRequest, connectionID: UUID,
                validateCommit: () throws -> Void) throws -> LibraryMutationReceipt {
        if let previous = try deletionReceipt(request, connectionID: connectionID) { return previous }
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        let ticket = try retryKeys.verify(key, request: request, connectionID: connectionID)
        let theme = try checkedDeletion(request)
        let identity = LibraryMutationIdentity(requestID: request.requestID,
            connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        do {
            return try library.commitThemeDeletion(theme.id, mutation: identity, at: now(),
                resource: .init(id: theme.id, versionToken: try version(theme)), validateCommit: {
                    try self.validateAdmission()
                    _ = try self.retryKeys.verify(key, request: request, connectionID: connectionID)
                    guard try self.checkedDeletion(request) == theme else { throw AgentErrorCode.versionConflict }
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
                    kind: "themes.delete", outcome: "submitted")
                submitted = true
            })
            try cleanupBookmark(request, validate: validateSession)
            try operations.recordEffect(operationID, effectID: effectID,
                kind: "themes.delete", outcome: "completed")
            return ["deletedIDs": .array(receipt.resources.map { .string($0.id.uuidString) })]
        } catch {
            if submitted { throw AgentErrorCode.outcomeUnknown }
            let code = error is CancellationError ? AgentErrorCode.cancelled : (error as? AgentErrorCode ?? .storageError)
            throw AgentOperationRegistry.FailureBeforeEffects(code: code)
        }
    }

}
