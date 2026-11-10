import Foundation
import AgentContracts

/// The backend owns an authenticated local session. Chat input cannot choose it.
@MainActor final class AgentChatToolSession {
    typealias Backend = @MainActor (AgentRequest) async throws -> AgentResponse
    var expiresAt: Date?
    var followsDraftSelection = false
    private let draftID: UUID?
    var resolveCurrentEditorID: (() -> UUID?)?
    var currentEditorID: UUID? { resolveCurrentEditorID?() }
    var resolveCurrentDraftID: (() -> UUID?)?
    var currentDraftID: UUID? { resolveCurrentDraftID.map { $0() } ?? draftID }
    private let backend: Backend
    private let onClose: @MainActor () -> Void
    private let onDisconnect: @MainActor () -> Void
    private let validateContext: @MainActor () throws -> Void
    var onInvalidated: (@MainActor () -> Void)?
    private var closed = false
    private var inFlight = false
    private var usedCalls = Set<String>()

    init(backend: @escaping Backend, currentDraftID: UUID? = nil, onClose: @escaping @MainActor () -> Void = {},
         onDisconnect: @escaping @MainActor () -> Void = {},
         validateContext: @escaping @MainActor () throws -> Void = {}) {
        self.draftID = currentDraftID
        self.backend = backend; self.onClose = onClose; self.onDisconnect = onDisconnect
        self.validateContext = validateContext
    }

    convenience init(service: AgentCommandService, session: AgentCommandService.Session,
                     currentDraftID: UUID? = nil,
                     onDisconnect: @escaping @MainActor () -> Void = {},
                     validateContext: @escaping @MainActor () throws -> Void = {}) {
        self.init(backend: { request in
            let libraryID = try service.authorizedLibraryID(for: session)
            guard request.libraryID == nil || request.libraryID == libraryID else { throw AgentErrorCode.permissionDenied }
            let bound = AgentRequest(requestID: request.requestID, libraryID: libraryID, operation: request.operation,
                targets: request.targets, expectedVersion: request.expectedVersion, retryKey: request.retryKey,
                parameters: request.parameters)
            return try JSONDecoder().decode(AgentResponse.self, from: await service.respondAsync(to: JSONEncoder().encode(bound), session: session))
        }, currentDraftID: currentDraftID, onClose: { service.close(session) }, onDisconnect: onDisconnect, validateContext: validateContext)
    }

    isolated deinit { invalidate() }

    func invalidate(revoke: Bool = true) {
        guard !closed else { return }
        closed = true
        onClose()
        if revoke { onDisconnect() }
        let notify = onInvalidated; onInvalidated = nil
        notify?()
    }

    func tools(validateExecution: () throws -> Void = {}) async throws -> [AgentAvailableTools.Definition] {
        try await catalog(validateExecution: validateExecution).definitions
    }

    func execute(callID: String, tool: String, argumentsJSON: String,
                 validateExecution: () throws -> Void = {}) async throws -> String {
        try check(validateExecution)
        guard !inFlight else { throw AgentErrorCode.busy }
        guard !callID.isEmpty, callID.utf8.count <= 256,
              !usedCalls.contains(callID), usedCalls.count < 256 else { throw AgentErrorCode.invalidInput }
        inFlight = true
        defer { inFlight = false }
        let current = try await catalog(validateExecution: validateExecution)
        let request = try current.request(tool: tool, argumentsJSON: argumentsJSON)
        try check(validateExecution)
        // Reserve identity before dispatch. An uncertain result cannot trigger replay.
        usedCalls.insert(callID)
        let response = try await backend(request)
        try check(validateExecution)
        guard response.requestID == request.requestID else { throw AgentErrorCode.unavailable }
        if case .error(let code) = response.outcome,
           [.permissionDenied, .cancelled].contains(code) { throw code }
        let data = try JSONEncoder().encode(response)
        guard data.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.unavailable }
        return String(decoding: data, as: UTF8.self)
    }

    private func catalog(validateExecution: () throws -> Void) async throws -> AgentAvailableTools {
        let capabilities = try await read("server.capabilities", validateExecution: validateExecution)
        let schemas = try await read("server.schemas", validateExecution: validateExecution)
        try check(validateExecution)
        return try AgentAvailableTools(capabilities: capabilities, schemas: schemas)
    }

    private func read(_ operation: String, validateExecution: () throws -> Void) async throws -> [String: AgentJSONValue] {
        try check(validateExecution)
        let request = AgentRequest(requestID: UUID(), libraryID: nil, operation: operation)
        let response = try await backend(request)
        try check(validateExecution)
        guard response.requestID == request.requestID else { throw AgentErrorCode.unavailable }
        if case .error(let error) = response.outcome { throw error }
        guard case .result(.object(let values)) = response.outcome else { throw AgentErrorCode.unavailable }
        return values
    }

    private func check(_ validateExecution: () throws -> Void) throws {
        try Task.checkCancellation()
        try validateExecution()
        guard !closed else { throw AgentErrorCode.cancelled }
        do { try validateContext() }
        catch { invalidate(); throw error }
    }
}
