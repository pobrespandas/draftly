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
        case "native.dictate": operation = "dictate"; values = parameters
        case "native.transcribe": operation = "transcribe"; values = parameters
        case "native.location": operation = "location"; values = parameters
        case "native.shell": operation = "shellScript"; values = parameters
        case "native.appleScript": operation = "appleScript"; values = parameters
        case "native.shortcut":
            operation = "shortcut"; var input = parameters; input["waitForResponse"] = .bool(true); values = input
        default: throw AgentErrorCode.unavailable
        }
        guard let descriptor = AgentOperationCatalog.operation(named: request.operation) else { throw AgentErrorCode.unavailable }
        var capabilities = descriptor.capabilities
        var libraryScope = descriptor.requiresLibraryScope
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
                    environment: Environment, operations: AgentOperationRegistry,
                    validateAuthority: () throws -> Void) async throws -> [String: AgentJSONValue] {
        var submittedEffect: UUID?
        var host: (any ActionHost)?
        defer { host?.finishAction() }
        do {
            try Task.checkCancellation(); try validateAuthority()
            let initial = try plan(request, grant: grant)
            try operations.setWaitingForUser(operationID, waiting: true)
            try await environment.approvals.waitForApproval(request, connectionID: grant.connectionID, resolveEffects: {
                try Task.checkCancellation(); try validateAuthority()
                return try plan(request, grant: grant).effects
            })
            try operations.setWaitingForUser(operationID, waiting: false)
            try Task.checkCancellation(); try validateAuthority()
            let current = try plan(request, grant: grant)
            guard current.operation == initial.operation, current.values == initial.values else { throw AgentErrorCode.versionConflict }
            let payload: String
            if request.operation == "native.appleScript" {
                guard var values = try JSONSerialization.jsonObject(with: JSONEncoder().encode(current.values)) as? [String: Any] else { throw AgentErrorCode.invalidInput }
                guard case .string(let arguments) = current.values["argumentsJSON"] else { throw AgentErrorCode.invalidInput }
                values.removeValue(forKey: "argumentsJSON")
                values["arguments"] = try AgentNativeSchemas.boundedJSON(arguments)
                payload = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
            } else { payload = String(decoding: try JSONEncoder().encode(current.values), as: UTF8.self) }
            let adapter = environment.makeHost()
            host = adapter
            try Task.checkCancellation(); try validateAuthority()
            let effect = UUID()
            try operations.recordEffect(operationID, effectID: effect, kind: request.operation, outcome: "submitted")
            submittedEffect = effect
            let raw = try await adapter.performAsync(current.operation, payload: payload)
            try Task.checkCancellation(); try validateAuthority()
            let result = try decodedResult(raw, for: request.operation)
            let outcome: String
            if case .bool(let completed) = result["completed"] { outcome = completed ? "completed" : "failed" }
            else if request.operation == "native.shell", case .object(let process) = result["process"] {
                outcome = process["status"] == .integer(0) ? "completed" : "failed"
            } else { outcome = "completed" }
            try AgentNativeSchemas.validateResult(result, for: request.operation)
            try validateAuthority(); try Task.checkCancellation()
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

    static func decodedResult(_ raw: String, for operation: String) throws -> [String: AgentJSONValue] {
        guard raw.utf8.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.outcomeUnknown }
        if operation == "native.appleScript" {
            guard let envelope = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  envelope["error"] == nil else { throw AgentErrorCode.outcomeUnknown }
            _ = try AppleScriptValueTransport.decode(envelope)
            let result: [String: AgentJSONValue] = ["valueJSON": .string(raw), "resultAvailable": .bool(true)]
            try AgentNativeSchemas.validateResult(result, for: operation)
            return result
        }
        guard let envelope = try? JSONDecoder().decode([String: AgentJSONValue].self, from: Data(raw.utf8)),
              envelope["error"] == nil, let value = envelope["value"] else { throw AgentErrorCode.outcomeUnknown }
        let result: [String: AgentJSONValue]
        if let field = AgentNativeSchemas.transientResultField(for: operation) {
            result = [field: value, "resultAvailable": .bool(true)]
        } else { result = ["completed": value] }
        try AgentNativeSchemas.validateResult(result, for: operation)
        return result
    }

}
