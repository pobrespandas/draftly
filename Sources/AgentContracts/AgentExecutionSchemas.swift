import Foundation

package enum AgentExecutionSchemas {
    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }
    package static var operationNames: Set<String> { Set(schemas.keys) }

    package static func validateResult(_ values: [String: AgentJSONValue], for operation: String) throws {
        guard let schema = schema(for: operation) else { throw AgentErrorCode.unavailable }
        try schema.result.validate(values)
        guard case .object(let snapshot) = values["operation"],
              case .string(let rawState) = snapshot["state"], let state = AgentOperationState(rawValue: rawState),
              case .string(let name) = snapshot["name"] else { throw AgentSchemaError.invalidValue }
        if !state.isTerminal {
            guard snapshot["result"] == .null, snapshot["error"] == .null,
                  snapshot["actionReport"] == .null else { throw AgentSchemaError.invalidValue }
        } else if state == .succeeded {
            guard snapshot["error"] == .null else { throw AgentSchemaError.invalidValue }
        } else {
            guard case .object(let error) = snapshot["error"], case .string(let code) = error["code"] else {
                throw AgentSchemaError.invalidValue
            }
            let required: AgentErrorCode?
            switch state {
            case .cancelled: required = .cancelled
            case .timedOut: required = .timeout
            case .outcomeUnknown: required = .outcomeUnknown
            default: required = nil
            }
            if let required, code != required.rawValue { throw AgentSchemaError.invalidValue }
            if state == .failed, ["cancelled", "timeout", "outcome_unknown"].contains(code) {
                throw AgentSchemaError.invalidValue
            }
        }
        if operation == "operations.cancel", state.isTerminal, state != .cancelled,
           values["cancellationAccepted"] == .bool(true) { throw AgentSchemaError.invalidValue }
        if case .object(let report) = snapshot["actionReport"] {
            guard name == "actions.run", state.isTerminal, state != .outcomeUnknown,
                  case .string(let status) = report["status"], case .string(let reason) = report["reason"],
                  case .object(let success) = report["successParameters"] else { throw AgentSchemaError.invalidValue }
            let matches: Bool
            switch state {
            case .succeeded: matches = status == "success" && reason == "success"
            case .cancelled: matches = status == "cancelled" && reason == "cancelled"
            case .timedOut: matches = status == "failure" && reason == "timeout"
            case .failed: matches = status == "failure" && ["error", "busy"].contains(reason)
            default: matches = false
            }
            guard matches, state == .succeeded || success.isEmpty else { throw AgentSchemaError.invalidValue }
            if state == .failed {
                guard case .object(let error) = snapshot["error"], case .string(let code) = error["code"],
                      (reason == "busy") == (code == AgentErrorCode.busy.rawValue) else {
                    throw AgentSchemaError.invalidValue
                }
            }
        } else if name == "actions.run", state.isTerminal, state != .outcomeUnknown {
            throw AgentSchemaError.invalidValue
        }
    }

    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static func o(_ shape: AgentValueShape, default value: AgentJSONValue? = nil) -> AgentFieldShape {
        .init(shape: shape, defaultValue: value)
    }
    private static let text = AgentValueShape.string()
    private static let rawObject = AgentValueShape.object(.init(fields: [:], allowsAdditionalFields: true))

    private static let snapshot = AgentObjectShape(fields: [
        "operationID": r(.uuid), "name": r(.string(choices: AgentOperationCatalog.operations.map(\.name))),
        "state": r(.string(choices: AgentOperationState.allCases.map(\.rawValue))), "updatedAt": r(.utcDate),
        "result": r(.nullable(rawObject)),
        "error": r(.nullable(.object(.init(fields: [
            "code": r(.string(choices: AgentErrorCode.allCases.map(\.rawValue))), "message": r(text)
        ])))),
        "actionReport": r(.nullable(.object(.init(fields: [
            "executionID": r(.uuid), "actionID": r(.uuid), "startedAt": r(.utcDate), "finishedAt": r(.utcDate),
            "status": r(.string(choices: ["success", "cancelled", "failure"])),
            "reason": r(.string(choices: ["success", "cancelled", "error", "timeout", "busy"])),
            "message": r(text), "successParameters": r(.map(text))
        ])))),
        "completedEffects": r(.array(.object(.init(fields: [
            "kind": r(.string(minimum: 1)),
            "outcome": r(.string(choices: ["completed", "submitted", "failed", "unknown"])),
            "resources": r(.array(.object(.init(fields: ["id": r(.uuid),
                "kind": r(.string(choices: AgentResourceKind.allCases.map(\.rawValue)))])), maximum: 10_000))
        ])), maximum: 10_000))
    ])

    private static let schemas: [String: AgentOperationSchema] = [
        "operations.get": .init(parameters: .init(fields: [:]), result: .init(fields: ["operation": r(.object(snapshot))])),
        "operations.wait": .init(parameters: .init(fields: [
            "timeoutSeconds": o(.integer(minimum: 1, maximum: 30), default: .integer(10))
        ]), result: .init(fields: ["operation": r(.object(snapshot)), "waitExpired": r(.boolean)])),
        "operations.cancel": .init(parameters: .init(fields: [:]), result: .init(fields: [
            "operation": r(.object(snapshot)), "cancellationAccepted": r(.boolean)
        ])),
        "operations.answerPrompt": .init(parameters: .init(fields: [
            "stepID": r(.uuid), "promptID": r(.uuid), "answers": r(rawObject)
        ]), result: .init(fields: ["operation": r(.object(snapshot))]))
    ]
}
