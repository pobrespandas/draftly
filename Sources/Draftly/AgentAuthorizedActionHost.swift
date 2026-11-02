import Foundation
import AgentContracts
import DraftlyCore

// A caller must authorize each concrete native invocation. This wrapper does
// not authorize scripts, library access, templates, or action execution itself.
@MainActor final class AgentAuthorizedActionHost: ActionHost {
    typealias Authorize = (String, [String: Any]) throws -> Void
    typealias Approve = (String, [String: Any]) async throws -> Void
    private let host: any ActionHost
    private let authorize: Authorize
    private let approve: Approve?
    private let requiresApproval: (String) -> Bool
    private(set) var hasUncertainOutcome = false

    init(host: any ActionHost, approve: Approve? = nil,
         requiresApproval: @escaping (String) -> Bool = { _ in true }, authorize: @escaping Authorize) {
        self.host = host
        self.approve = approve
        self.requiresApproval = requiresApproval
        self.authorize = authorize
    }

    func supportsAsync(_ operation: String) -> Bool { host.supportsAsync(operation) }

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        try Task.checkCancellation()
        // A synchronous call cannot wait for a human decision.
        guard approve == nil || !requiresApproval(operation) else { throw AgentErrorCode.interactionRequired }
        try authorize(operation, values)
        let result: Any?
        do { result = try host.perform(operation, values: values) }
        catch { hasUncertainOutcome = true; throw error }
        do { try authorize(operation, values); try Task.checkCancellation() }
        catch { hasUncertainOutcome = true; throw AgentErrorCode.outcomeUnknown }
        return result
    }

    func performAsync(_ operation: String, payload: String) async throws -> String {
        guard let data = payload.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentErrorCode.invalidInput
        }
        try Task.checkCancellation()
        try authorize(operation, values)
        if let approve, requiresApproval(operation) {
            try await approve(operation, values)
            try Task.checkCancellation()
            try authorize(operation, values)
        }
        let result: String
        do { result = try await host.performAsync(operation, payload: payload) }
        catch { hasUncertainOutcome = true; throw error }
        do { try authorize(operation, values); try Task.checkCancellation() }
        catch { hasUncertainOutcome = true; throw AgentErrorCode.outcomeUnknown }
        return result
    }

    func finishAction() { host.finishAction() }
}
