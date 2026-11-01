import Foundation
import Testing
import DraftlyCore
@testable import AgentContracts

@Suite("Agent operation lifecycle schemas")
struct AgentExecutionSchemaTests {
    private func snapshot(state: AgentOperationState, report: AgentJSONValue = .null,
                          error: AgentErrorCode? = nil) -> [String: AgentJSONValue] {
        ["operationID": .string(UUID().uuidString), "name": .string("actions.run"),
         "state": .string(state.rawValue), "updatedAt": .string("2026-10-31T22:00:00Z"),
         "result": .null, "error": error.map { .object(["code": .string($0.rawValue), "message": .string("Neutral")]) } ?? .null,
         "actionReport": report, "completedEffects": .array([])]
    }

    private func report(status: String, reason: String, success: [String: AgentJSONValue] = [:]) -> AgentJSONValue {
        .object(["executionID": .string(UUID().uuidString), "actionID": .string(UUID().uuidString),
            "startedAt": .string("2026-10-31T22:00:00Z"), "finishedAt": .string("2026-10-31T22:00:01Z"),
            "status": .string(status), "reason": .string(reason), "message": .string("Neutral"),
            "successParameters": .object(success)])
    }

    @Test func waitExpiryDoesNotBecomeAnExecutionTimeout() throws {
        let schema = try #require(AgentExecutionSchemas.schema(for: "operations.wait"))
        #expect(try schema.validatedParameters([:])["timeoutSeconds"] == .integer(10))
        let value = snapshot(state: .running)
        try AgentOperationSchemas.validateResult(["operation": .object(value), "waitExpired": .bool(true)], for: "operations.wait")
        #expect(throws: AgentSchemaError.self) { try schema.validatedParameters(["timeoutSeconds": .integer(31)]) }
    }

    @Test func pendingAndAmbiguousStatesCannotReportSuccess() {
        let success = report(status: "success", reason: "success")
        for state in [AgentOperationState.running, .waitingForUser, .outcomeUnknown] {
            let value = snapshot(state: state, report: success, error: state == .outcomeUnknown ? .outcomeUnknown : nil)
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validateResult(["operation": .object(value)], for: "operations.get")
            }
        }
    }

    @Test func failuresCannotCarrySuccessParametersAndCancelCannotHideACommittedResult() throws {
        let failed = snapshot(state: .failed, report: report(status: "failure", reason: "error", success: ["output": .string("Wrong")]), error: .storageError)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["operation": .object(failed)], for: "operations.get")
        }
        let completed = snapshot(state: .succeeded, report: report(status: "success", reason: "success"))
        try AgentOperationSchemas.validateResult(["operation": .object(completed), "cancellationAccepted": .bool(false)], for: "operations.cancel")
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["operation": .object(completed), "cancellationAccepted": .bool(true)], for: "operations.cancel")
        }
    }

    @Test func terminalErrorKindsStayDistinct() throws {
        let timedOut = snapshot(state: .timedOut, report: report(status: "failure", reason: "timeout"), error: .timeout)
        try AgentOperationSchemas.validateResult(["operation": .object(timedOut)], for: "operations.get")
        let ambiguous = snapshot(state: .outcomeUnknown, error: .outcomeUnknown)
        try AgentOperationSchemas.validateResult(["operation": .object(ambiguous)], for: "operations.get")
        let incorrect = snapshot(state: .cancelled, report: report(status: "cancelled", reason: "cancelled"), error: .timeout)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["operation": .object(incorrect)], for: "operations.get")
        }
    }

    @Test func repliesBindToTheRequestedOperationIdentity() throws {
        let id = UUID()
        let request = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "operations.get",
            targets: [.init(kind: .operation, id: id)])
        var value = snapshot(state: .running)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["operation": .object(value)], for: request)
        }
        value["operationID"] = .string(id.uuidString)
        try AgentOperationSchemas.validateResult(["operation": .object(value)], for: request)
    }

    @Test func promptRepliesRequireStepAndPromptIdentitiesAndCannotApprovePermissions() throws {
        let schema = try #require(AgentExecutionSchemas.schema(for: "operations.answerPrompt"))
        var answer: [String: AgentJSONValue] = ["stepID": .string(UUID().uuidString),
            "promptID": .string(UUID().uuidString), "answers": .object(["choice": .string("Neutral")])]
        #expect(try schema.validatedParameters(answer) == answer)
        answer["approveGrant"] = .bool(true)
        #expect(throws: AgentSchemaError.self) { try schema.validatedParameters(answer) }
        #expect(throws: AgentSchemaError.self) { try schema.validatedParameters(["answers": .object([:])]) }
    }

    @Test func canonicalNotStartedReportsHaveCompatibleReasons() throws {
        for reason in [ActionTerminationReason.cancelled, .timeout, .busy, .error] {
            let value = ActionExecutionReport.notStarted(actionID: UUID(), reason: reason, message: "Neutral")
            let state: AgentOperationState = reason == .cancelled ? .cancelled : reason == .timeout ? .timedOut : .failed
            let error: AgentErrorCode = reason == .cancelled ? .cancelled : reason == .timeout ? .timeout : reason == .busy ? .busy : .executionError
            let status: String
            switch value.result { case .success: status = "success"; case .cancelled: status = "cancelled"; case .failure: status = "failure" }
            let result = snapshot(state: state, report: report(status: status, reason: value.reason.rawValue), error: error)
            try AgentOperationSchemas.validateResult(["operation": .object(result)], for: "operations.get")
        }
    }

    @Test func aBusyReportCannotBeRelabelledAsAStorageFailure() {
        let value = snapshot(state: .failed, report: report(status: "failure", reason: "busy"), error: .storageError)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["operation": .object(value)], for: "operations.get")
        }
    }
}
