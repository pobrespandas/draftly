import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent native action host") @MainActor
struct AgentAuthorizedActionHostTests {
    private final class Host: ActionHost {
        var calls = 0
        var operations: [String] = []
        var finished = 0
        var onCall: (() -> Void)?
        func supportsAsync(_ operation: String) -> Bool { true }
        func perform(_ operation: String, values: [String: Any]) throws -> Any? {
            calls += 1; operations.append(operation); onCall?()
            if operation == "device" { return ["systemName": "macOS", "model": "Mac", "systemVersion": "test"] }
            return "done"
        }
        func performAsync(_ operation: String, payload: String) async throws -> String {
            calls += 1; operations.append(operation); onCall?()
            if operation == "device" { return "{\"value\":{\"systemName\":\"macOS\",\"model\":\"Mac\",\"systemVersion\":\"test\"}}" }
            return "done"
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

    @Test(arguments: [false, true]) func guardedHostIsUsedWithOrWithoutVisibleEditor(visible: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let model = WindowModel(library: library); model.select(note.id)
        let native = Host()
        var checks = 0
        let guarded = AgentAuthorizedActionHost(host: native) { operation, _ in
            if operation == "device" { return }
            #expect(operation == "clipboard")
            checks += 1
            throw AgentErrorCode.permissionDenied
        }
        let action = DraftAction(name: "Copy", steps: [ActionStep("clipboard", ["template": "Neutral"])])
        let output = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: visible ? [model] : [], host: model.host, hostOverride: guarded,
            resolveModel: { models, _ in models.first })
        #expect(output.report.reason == .error)
        #expect(checks == 1 && native.operations == ["device"], "\(output.message), calls: \(native.operations), checks: \(checks)")
        #expect(model.runner.host === model.host)
    }
}
