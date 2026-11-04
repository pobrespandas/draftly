import Foundation
import DraftlyCore
import AgentContracts

// Window effects use host-lifetime receipts. They do not write Workspace records.
@MainActor final class AgentWorkspaceApplication {
    static let operationNames: Set<String> = ["workspaces.apply"]
    private struct Receipt {
        let requestHash: String
        let authority: AgentJSONValue
        var result: [String: AgentJSONValue]?
    }
    private let library: LibraryStore
    private let editors: AgentEditorRegistry
    private let keys: AgentRetryKeys
    private let currentGrant: (UUID) throws -> AgentGrant?
    private let version: (Workspace) throws -> String
    private var receipts: [String: Receipt] = [:]
    private var applying = false

    init(library: LibraryStore, editors: AgentEditorRegistry, keys: AgentRetryKeys,
         currentGrant: @escaping (UUID) throws -> AgentGrant?,
         version: @escaping (Workspace) throws -> String) {
        self.library = library; self.editors = editors; self.keys = keys
        self.currentGrant = currentGrant; self.version = version
    }

    private func checked(_ request: AgentRequest) throws -> (Workspace, UUID) {
        guard Self.operationNames.contains(request.operation), request.targets.count == 2,
              let workspaceID = request.targets.first(where: { $0.kind == .workspace })?.id,
              let windowID = request.targets.first(where: { $0.kind == .window })?.id,
              let workspace = library.workspaces.first(where: { $0.id == workspaceID }) else { throw AgentErrorCode.notFound }
        guard let expected = request.expectedVersion, try version(workspace) == expected else { throw AgentErrorCode.versionConflict }
        try editors.validateWorkspaceApplication(windowID: windowID)
        return (workspace, windowID)
    }

    private func previous(_ ticket: AgentRetryKeys.Ticket, request: AgentRequest, connectionID: UUID) throws -> [String: AgentJSONValue]? {
        guard let receipt = receipts[ticket.connectionHash + "/" + request.requestID.uuidString] else { return nil }
        guard let grant = try currentGrant(connectionID), AgentRequestBinding.grantValue(grant) == receipt.authority else {
            throw AgentErrorCode.permissionDenied
        }
        guard receipt.requestHash == ticket.requestHash else { throw AgentErrorCode.invalidInput }
        guard let result = receipt.result else { throw AgentErrorCode.outcomeUnknown }
        return result
    }

    func prepare(_ request: AgentRequest, connectionID: UUID, authorize: () throws -> Void) throws -> AgentRetryKeys.Ticket {
        guard !applying else { throw AgentErrorCode.busy }
        applying = true; defer { applying = false }
        guard Self.operationNames.contains(request.operation), request.retryKey == nil else { throw AgentErrorCode.invalidInput }
        try authorize()
        let ticket = try keys.issue(request, connectionID: connectionID)
        if try previous(ticket, request: request, connectionID: connectionID) == nil { _ = try checked(request) }
        try authorize(); _ = try keys.verify(ticket.value, request: request, connectionID: connectionID)
        return ticket
    }

    func apply(_ request: AgentRequest, connectionID: UUID, authorize: () throws -> Void) throws -> [String: AgentJSONValue] {
        guard !applying else { throw AgentErrorCode.busy }
        applying = true; defer { applying = false }
        guard Self.operationNames.contains(request.operation), let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try authorize()
        let ticket = try keys.verify(key, request: request, connectionID: connectionID)
        if let result = try previous(ticket, request: request, connectionID: connectionID) { return result }
        guard receipts.count < 128 else { throw AgentErrorCode.busy }
        guard let grant = try currentGrant(connectionID) else { throw AgentErrorCode.permissionDenied }
        let (workspace, windowID) = try checked(request)
        let identity = ticket.connectionHash + "/" + request.requestID.uuidString
        var submitted = false
        do {
            try editors.applyWorkspace(workspace, windowID: windowID, authorize: {
                try authorize(); _ = try self.keys.verify(key, request: request, connectionID: connectionID)
                let (current, currentWindow) = try self.checked(request)
                guard current == workspace, currentWindow == windowID else { throw AgentErrorCode.versionConflict }
                self.receipts[identity] = Receipt(requestHash: ticket.requestHash, authority: AgentRequestBinding.grantValue(grant))
                submitted = true
            })
            try authorize(); _ = try keys.verify(key, request: request, connectionID: connectionID)
            let result: [String: AgentJSONValue] = ["workspaceID": .string(workspace.id.uuidString), "windowID": .string(windowID.uuidString)]
            receipts[identity]?.result = result
            return result
        } catch {
            if submitted { throw AgentErrorCode.outcomeUnknown }
            if let code = error as? AgentErrorCode { throw code }
            if error is DraftlyError { throw AgentErrorCode.invalidInput }
            throw AgentErrorCode.storageError
        }
    }
}
