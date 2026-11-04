import Foundation
import AgentContracts
import DraftlyCore

// Native requests use the same app-owned review and effect journal as Actions.
@MainActor enum AgentNativeExecution {
    struct Environment {
        let makeHost: @MainActor () -> any ActionHost
        let approvals: AgentApprovalStore
    }

    struct Plan {
        let operation: String
        let values: [String: AgentJSONValue]
        let effects: AgentApprovalStore.Effects
    }

    static func plan(_ request: AgentRequest, grant: AgentGrant) throws -> Plan {
        guard request.libraryID == grant.libraryID else { throw AgentErrorCode.permissionDenied }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentNativeSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        let operation: String
        let values: [String: AgentJSONValue]
        switch request.operation {
        case "native.clipboardRead": operation = "getClipboard"; values = [:]
        case "native.clipboardWrite": operation = "clipboard"; values = parameters
        case "native.htmlToMarkdown": operation = "htmlToMarkdown"; values = ["text": parameters["html"]!]
        case "native.share": operation = "share"; values = parameters
        case "native.print": operation = "print"; values = parameters
        case "native.openURL": operation = "openURL"; values = parameters
        case "native.speak": operation = "speak"; values = parameters
        default: throw AgentErrorCode.unavailable
        }
        var capabilities: Set<AgentCapability> = [.nativeUse]
        var libraryScope = false
        if request.operation == "native.openURL", case .string(let raw) = parameters["url"],
           let scheme = URL(string: raw)?.scheme?.lowercased(), !["http", "https"].contains(scheme) {
            capabilities.insert(.scriptsUnrestricted); libraryScope = true
        }
        guard grant.capabilities.isSuperset(of: capabilities), !libraryScope || grant.scope == .library else {
            throw AgentErrorCode.permissionDenied
        }
        return Plan(operation: operation, values: values,
            effects: .init(capabilities: capabilities, targets: [], requiresLibraryScope: libraryScope,
                snapshot: ["nativeOperation": .string(operation), "nativeParameters": .object(values)]))
    }

    static func run(_ request: AgentRequest, grant: AgentGrant, operationID: UUID,
                    host: any ActionHost, approvals: AgentApprovalStore, operations: AgentOperationRegistry,
                    validateSession: () throws -> Void) async throws -> [String: AgentJSONValue] {
        var submittedEffect: UUID?
        defer { host.finishAction() }
        do {
            try Task.checkCancellation(); try validateSession()
            let initial = try plan(request, grant: grant)
            try operations.setWaitingForUser(operationID, waiting: true)
            try await approvals.waitForApproval(request, connectionID: grant.connectionID, resolveEffects: {
                try Task.checkCancellation(); try validateSession()
                return try plan(request, grant: grant).effects
            })
            try operations.setWaitingForUser(operationID, waiting: false)
            try Task.checkCancellation(); try validateSession()
            let current = try plan(request, grant: grant)
            guard current.operation == initial.operation, current.values == initial.values else { throw AgentErrorCode.versionConflict }
            let payload = String(decoding: try JSONEncoder().encode(current.values), as: UTF8.self)
            let effect = UUID()
            try operations.recordEffect(operationID, effectID: effect, kind: request.operation, outcome: "submitted")
            submittedEffect = effect
            let raw = try await host.performAsync(current.operation, payload: payload)
            try Task.checkCancellation(); try validateSession()
            guard raw.utf8.count <= AgentRequest.maximumBytes,
                  let envelope = try? JSONDecoder().decode([String: AgentJSONValue].self, from: Data(raw.utf8)),
                  envelope["error"] == nil, let value = envelope["value"] else { throw AgentErrorCode.outcomeUnknown }
            let result: [String: AgentJSONValue]
            let outcome: String
            if AgentNativeSchemas.transientTextOperations.contains(request.operation) {
                guard case .string = value else { throw AgentErrorCode.outcomeUnknown }
                result = ["text": value, "resultAvailable": .bool(true)]; outcome = "completed"
            } else {
                guard case .bool(let completed) = value else { throw AgentErrorCode.outcomeUnknown }
                result = ["completed": .bool(completed)]; outcome = completed ? "completed" : "failed"
            }
            try AgentNativeSchemas.validateResult(result, for: request.operation)
            try validateSession(); try Task.checkCancellation()
            try operations.recordEffect(operationID, effectID: effect, kind: request.operation, outcome: outcome)
            return result
        } catch {
            if let submittedEffect {
                try? operations.recordEffect(operationID, effectID: submittedEffect, kind: request.operation, outcome: "unknown")
                throw AgentErrorCode.outcomeUnknown
            }
            let code = error is CancellationError ? AgentErrorCode.cancelled : (error as? AgentErrorCode ?? .storageError)
            throw AgentOperationRegistry.FailureBeforeEffects(code: code)
        }
    }
}
