import Foundation
import AgentContracts

// Bind each concrete native effect to a new, single-use human review.
@MainActor enum AgentNativeEffectApproval {
    static func wait(store: AgentApprovalStore, request: AgentRequest, connectionID: UUID,
                     operation: String, values: [String: Any],
                     currentSnapshot: () throws -> [String: AgentJSONValue]) async throws {
        guard request.operation == "actions.run" else { throw AgentErrorCode.invalidInput }
        let unrestricted = ["appleScript", "shortcut", "shell"].contains(operation)
        let supported = ["share", "shareFile", "shareURL", "print", "mail", "message", "saveFile",
                         "clipboard", "getClipboard", "openURL", "appleScript", "shortcut", "shell"]
        guard supported.contains(operation) else { throw AgentErrorCode.unavailable }
        guard JSONSerialization.isValidJSONObject(values) else { throw AgentErrorCode.invalidInput }
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        guard data.count <= AgentRequest.maximumBytes,
              case .object(let parameters) = try JSONDecoder().decode(AgentJSONValue.self, from: data) else {
            throw AgentErrorCode.invalidInput
        }
        let reviewRequest = AgentRequest(requestID: UUID(), libraryID: request.libraryID, operation: request.operation,
            targets: request.targets, expectedVersion: request.expectedVersion, parameters: request.parameters)
        try await store.waitForApproval(reviewRequest, connectionID: connectionID, resolveEffects: {
            var snapshot = try currentSnapshot()
            guard snapshot["nativeOperation"] == nil, snapshot["nativeParameters"] == nil else {
                throw AgentErrorCode.invalidInput
            }
            snapshot["nativeOperation"] = .string(operation)
            snapshot["nativeParameters"] = .object(parameters)
            return AgentApprovalStore.Effects(capabilities: unrestricted ? [.nativeUse, .scriptsUnrestricted] : [.nativeUse],
                targets: Set(request.targets), requiresLibraryScope: unrestricted || operation == "saveFile",
                snapshot: snapshot)
        })
    }
}
