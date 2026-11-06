import Foundation
import AgentContracts
import DraftlyCore

// A caller must authorize each concrete native invocation. This wrapper does
// not authorize scripts, library access, templates, or action execution itself.
@MainActor final class AgentAuthorizedActionHost: ActionHost {
    typealias Authorize = (String, [String: Any]) throws -> Void
    typealias Approve = (String, [String: Any]) async throws -> Void
    typealias RecordEffect = (UUID, String, String) throws -> Void
    typealias AnswerablePrompt = (UUID, String) async throws -> String
    private let answerablePrompt: AnswerablePrompt?
    private let host: any ActionHost
    private let authorize: Authorize
    private let approve: Approve?
    private let requiresApproval: (String) -> Bool
    private let recordEffect: RecordEffect?
    private(set) var hasUncertainOutcome = false

    init(host: any ActionHost, approve: Approve? = nil,
         requiresApproval: @escaping (String) -> Bool = { _ in true }, recordEffect: RecordEffect? = nil,
         answerablePrompt: AnswerablePrompt? = nil, authorize: @escaping Authorize) {
        self.host = host
        self.answerablePrompt = answerablePrompt
        self.approve = approve
        self.requiresApproval = requiresApproval
        self.recordEffect = recordEffect
        self.authorize = authorize
    }

    func supportsAsync(_ operation: String) -> Bool { host.supportsAsync(operation) }

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        try Task.checkCancellation()
        // A synchronous call cannot wait for a human decision.
        guard approve == nil || !requiresApproval(operation) else { throw AgentErrorCode.interactionRequired }
        try authorize(operation, values)
        let effect = try beginEffect(operation)
        let result: Any?
        do { result = try host.perform(operation, values: values) }
        catch { recordUnknown(effect, operation); throw error }
        do {
            try authorize(operation, values); try Task.checkCancellation()
            try record(effect, operation, effectOutcome(operation, value: result))
        } catch { recordUnknown(effect, operation); throw AgentErrorCode.outcomeUnknown }
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
        let effect = try beginEffect(operation)
        let result: String
        do { result = try await host.performAsync(operation, payload: payload) }
        catch { recordUnknown(effect, operation); throw error }
        do {
            try authorize(operation, values); try Task.checkCancellation()
            let envelope = result.data(using: .utf8).flatMap {
                try? JSONDecoder().decode([String: AgentJSONValue].self, from: $0)
            }
            let completed: Bool?
            if case .bool(let value) = envelope?["value"] { completed = value } else { completed = nil }
            try record(effect, operation, effectOutcome(operation, value: completed))
        } catch { recordUnknown(effect, operation); throw AgentErrorCode.outcomeUnknown }
        return result
    }

    private func beginEffect(_ operation: String) throws -> UUID? {
        guard operation != "device", let recordEffect else { return nil }
        let id = UUID()
        try recordEffect(id, operation, "submitted")
        return id
    }

    private func record(_ id: UUID?, _ operation: String, _ outcome: String) throws {
        if let id { try recordEffect?(id, operation, outcome) }
    }

    private func recordUnknown(_ id: UUID?, _ operation: String) {
        hasUncertainOutcome = true
        try? record(id, operation, "unknown")
    }

    private func effectOutcome(_ operation: String, value: Any?) -> String {
        guard ["share", "shareFile", "print", "clipboard", "htmlToClipboard", "openURL"].contains(operation) else { return "completed" }
        guard let completed = value as? Bool else {
            hasUncertainOutcome = true
            return "unknown"
        }
        return completed ? "completed" : "failed"
    }

    func performPrompt(stepID: UUID, payload: String) async throws -> String {
        guard let answerablePrompt else { return try await performAsync("prompt", payload: payload) }
        try Task.checkCancellation()
        try authorize("device", [:])
        let result = try await answerablePrompt(stepID, payload)
        try Task.checkCancellation()
        try authorize("device", [:])
        return result
    }

    func finishAction() { host.finishAction() }
}
