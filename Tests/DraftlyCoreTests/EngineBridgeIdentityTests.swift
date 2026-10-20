import Foundation
import Testing
@testable import DraftlyCore

@Suite("Engine bridge request authority")
struct EngineBridgeIdentityTests {
    private func request(token: UUID = UUID(), executionID: UUID = UUID(), stepID: UUID = UUID(),
                         deadline: Date = .distantFuture, operation: String = "clipboard", payload: String = "{\"text\":\"Neutral\"}") -> ActionBridgeRequest {
        ActionBridgeRequest(executionID: executionID, stepID: stepID, token: token, deadline: deadline, operation: operation, payload: payload)
    }

    @Test func registeredRequestCanBeConsumedOnlyOnce() {
        let authority = ActionBridgeRequestAuthority(), value = request()
        #expect(!authority.consume(value))
        #expect(authority.register(value))
        #expect(!authority.register(value))
        #expect(authority.consume(value))
        #expect(!authority.consume(value))
        #expect(!authority.register(value))
    }

    @Test(arguments: ["execution", "step", "deadline", "operation", "payload", "token"])
    func changedRequestCannotConsumeTheValidRequest(field: String) {
        let authority = ActionBridgeRequestAuthority(), value = request()
        #expect(authority.register(value))
        let changed = request(token: field == "token" ? UUID() : value.token,
            executionID: field == "execution" ? UUID() : value.executionID,
            stepID: field == "step" ? UUID() : value.stepID,
            deadline: field == "deadline" ? Date.distantPast : value.deadline,
            operation: field == "operation" ? "shell" : value.operation,
            payload: field == "payload" ? "{\"text\":\"Changed\"}" : value.payload)
        #expect(!authority.consume(changed))
        #expect(authority.consume(value))
    }

    @Test func revocationAffectsOnlyItsTokenAndInvalidationIsPermanent() {
        let authority = ActionBridgeRequestAuthority(), first = request(), second = request()
        #expect(authority.register(first) && authority.register(second))
        authority.revoke(first.token)
        #expect(!authority.register(first))
        #expect(!authority.consume(first) && authority.consume(second))
        let pending = request()
        #expect(authority.register(pending))
        authority.invalidate()
        #expect(!authority.consume(pending))
        #expect(!authority.register(request()))
    }

    @Test func expiredRequestCannotBeRegistered() {
        let authority = ActionBridgeRequestAuthority()
        let expired = request(deadline: .distantPast)
        #expect(!authority.register(expired) && !authority.consume(expired))
    }

    @Test func concurrentConsumersAuthorizeExactlyOneEffect() async {
        let authority = ActionBridgeRequestAuthority(), value = request()
        #expect(authority.register(value))
        let accepted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<32 { group.addTask { authority.consume(value) } }
            var accepted = 0
            for await result in group where result { accepted += 1 }
            return accepted
        }
        #expect(accepted == 1)
    }
}

@Suite("Engine bridge receiver identity") @MainActor
struct EngineBridgeReceiverIdentityTests {
    @Test(arguments: ["execution", "step", "unknown token", "replay"])
    func rejectedRequestCannotAffectTheActiveAction(rejection: String) async throws {
        let host = IdentityReceiverHost()
        let f = try ScriptTestFixture(content: "Source", host: host)
        let action = ScriptTestAction.make("ShellScript.create('neutral').execute();editor.setText('Legitimate completion');", name: "Owned receiver")
        let task = Task { await f.runner.runAsync(action) }
        await host.waitForStart()
        let execution = try #require(f.runner.activeSession?.id)
        let step = try #require(f.runner.bridgeStepID)
        let authority = ActionBridgeRequestAuthority()
        let request = ActionBridgeRequest(executionID: rejection == "execution" ? UUID() : execution,
            stepID: rejection == "step" ? UUID() : step, deadline: .distantFuture,
            operation: "clipboard", payload: #"{"text":"Authorized request"}"#)
        if rejection != "unknown token" { #expect(authority.register(request)) }
        if rejection == "replay" {
            let accepted = await f.runner.receive(request, authority: authority)
            #expect(!accepted.contains("error") && host.clipboardWrites == ["Authorized request"])
        }
        let rejected = await f.runner.receive(request, authority: authority)
        if rejection == "execution" || rejection == "step" { #expect(rejected.contains("The action was closed")) }
        else { #expect(rejected.contains("unknown or already consumed")) }
        #expect(host.clipboardWrites.count == (rejection == "replay" ? 1 : 0))
        #expect(f.runner.activeSession?.id == execution && f.runner.isRunning)
        #expect(f.editor.content == "Source")
        host.release()
        let report = await task.value
        #expect(report.reason == .success)
        #expect(f.editor.content == "Legitimate completion" && f.library.notes.first?.content == "Legitimate completion")
    }
}

@MainActor private final class IdentityReceiverHost: ActionHost {
    private let started = AsyncStream.makeStream(of: Bool.self)
    private var pending: CheckedContinuation<String, Never>?
    private(set) var clipboardWrites: [String] = []
    func supportsAsync(_ operation: String) -> Bool { operation == "shellScript" }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        guard operation == "clipboard" else { throw DraftlyError.message("Unexpected synchronous operation: \(operation)") }
        clipboardWrites.append(values["text"] as? String ?? "")
        return true
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        await withCheckedContinuation { continuation in
            pending = continuation
            started.continuation.yield(true)
        }
    }
    func waitForStart() async { var iterator = started.stream.makeAsyncIterator(); _ = await iterator.next() }
    func release() {
        pending?.resume(returning: #"{"value":{"status":0,"stdout":"","stderr":""}}"#)
        pending = nil
    }
}
