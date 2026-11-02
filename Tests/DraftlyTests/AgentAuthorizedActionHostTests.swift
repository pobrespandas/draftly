import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent native action host") @MainActor
struct AgentAuthorizedActionHostTests {
    private final class Host: ActionHost {
        var calls = 0
        var finished = 0
        var onCall: (() -> Void)?
        func supportsAsync(_ operation: String) -> Bool { true }
        func perform(_ operation: String, values: [String: Any]) throws -> Any? {
            calls += 1; onCall?(); return "done"
        }
        func performAsync(_ operation: String, payload: String) async throws -> String {
            calls += 1; onCall?(); return "done"
        }
        func finishAction() { finished += 1 }
    }

    @Test func deniedNativeCallDoesNotReachHostAndCleanupStillRuns() throws {
        let host = Host()
        let guarded = AgentAuthorizedActionHost(host: host) { _, _ in throw AgentErrorCode.permissionDenied }
        #expect(throws: AgentErrorCode.permissionDenied) { try guarded.perform("share", values: ["text": "neutral"]) }
        #expect(host.calls == 0)
        guarded.finishAction()
        #expect(host.finished == 1)
    }

    @Test func authorityLostAfterNativeHandoffReportsUnknownOutcome() async throws {
        let host = Host()
        var allowed = true
        host.onCall = { allowed = false }
        let guarded = AgentAuthorizedActionHost(host: host) { operation, values in
            #expect(operation == "share")
            #expect(values["text"] as? String == "neutral")
            if !allowed { throw AgentErrorCode.permissionDenied }
        }
        await #expect(throws: AgentErrorCode.outcomeUnknown) {
            try await guarded.performAsync("share", payload: "{\"text\":\"neutral\"}")
        }
        #expect(host.calls == 1)
    }

    @Test func malformedAsyncInputNeverReachesNativeHost() async throws {
        let host = Host()
        let guarded = AgentAuthorizedActionHost(host: host) { _, _ in Issue.record("Malformed input must not be authorized") }
        await #expect(throws: AgentErrorCode.invalidInput) { try await guarded.performAsync("share", payload: "[]") }
        #expect(host.calls == 0)
    }
}
