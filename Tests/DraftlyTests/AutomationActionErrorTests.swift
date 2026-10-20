import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Automation execution errors")
struct AutomationActionErrorTests {
    private func report(_ reason: ActionTerminationReason, _ result: ActionExecutionResult) -> ActionExecutionReport {
        ActionExecutionReport(executionID: UUID(), actionID: UUID(), startedAt: .distantPast, finishedAt: Date(), result: result, reason: reason, successParameters: [:])
    }

    @Test func successDoesNotBecomeAnError() {
        #expect(AutomationActionError.from(report(.success, .success), message: "Complete") == nil)
    }

    @Test(arguments: [ActionTerminationReason.cancelled, .timeout, .busy, .error])
    func allFailuresRetainTheReasonIdentityAndOriginalResult(_ reason: ActionTerminationReason) throws {
        let original = report(reason, reason == .cancelled ? .cancelled : .failure("Native detail 🐼"))
        let error = try #require(AutomationActionError.from(original, message: "Runner detail"))
        #expect(error.executionID == original.executionID)
        #expect(error.reason == original.reason)
        #expect(error.result == original.result)
        #expect(error.localizedDescription == (reason == .cancelled ? "Runner detail" : "Native detail 🐼"))
    }

    @Test(arguments: [ActionTerminationReason.cancelled, .timeout, .busy, .error])
    func missingMessagesHaveSpecificFallbacks(_ reason: ActionTerminationReason) throws {
        let error = try #require(AutomationActionError.from(report(reason, .failure(""))))
        #expect(error.errorDescription?.isEmpty == false)
        if reason == .timeout { #expect(error.localizedDescription.contains("timed out")) }
        if reason == .busy { #expect(error.localizedDescription.contains("already running")) }
        if reason == .cancelled { #expect(error.localizedDescription.contains("cancelled")) }
    }

    @Test func malformedSuccessCannotHideAFailure() throws {
        let error = try #require(AutomationActionError.from(report(.success, .failure("Storage failed"))))
        #expect(error.reason == .error)
        #expect(error.result == .failure("Storage failed"))
    }
}
