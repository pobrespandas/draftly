import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("ChatGPT uses Draftly local tools") @MainActor
struct ChatGPTLocalToolTests {
    func completed(_ output: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": "response.completed", "response": [
            "id": "neutral-response", "status": "completed", "output": output
        ]])
    }
    func call(_ arguments: String, id: String = "neutral-call") -> [String: Any] {
        ["type": "function_call", "call_id": id, "name": "draftly_drafts_get", "namespace": "draftly",
         "arguments": arguments, "status": "completed"]
    }
    var final: [String: Any] {
        ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "Done"]]]
    }

    @Test func completedCallUsesRealPermissionServiceAndReturnsResultsWithReasoning() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        let tools = AgentChatToolSession(service: runtime.service, session: runtime.session)
        let arguments = try runtime.arguments(runtime.allowed.id)
        var requests = 0
        let provider = ChatGPTProvider(stream: { request, event in
            requests += 1
            let bodyData = try #require(request.httpBody)
            let decoded = try JSONSerialization.jsonObject(with: bodyData)
            let body = try #require(decoded as? [String: Any])
            #expect(body["store"] as? Bool == false && body["stream"] as? Bool == true)
            let definitions = try #require(body["tools"] as? [[String: Any]])
            #expect(definitions.first?["type"] as? String == "namespace")
            #expect(definitions.first?["name"] as? String == "draftly")
            if requests == 1 {
                _ = try event(completed([["type": "reasoning", "id": "reasoning-id", "summary": [], "encrypted_content": "neutral-encrypted"], call(arguments)]))
            } else {
                let input = try #require(body["input"] as? [[String: Any]])
                #expect(input.contains { $0["encrypted_content"] as? String == "neutral-encrypted" })
                let result = try #require(input.first { $0["type"] as? String == "function_call_output" })
                #expect(result["call_id"] as? String == "neutral-call")
                #expect((result["output"] as? String)?.contains(runtime.allowed.content) == true)
                #expect((result["output"] as? String)?.contains(runtime.hidden.content) == false)
                _ = try event(completed([final]))
            }
        })
        let answer = try await provider.respond(messages: [.init(role: .user, text: "Read the approved draft")],
            model: "neutral-model", token: "neutral-token", tools: tools, onText: { _ in })
        #expect(answer == "Done" && requests == 2)
    }

    @Test func duplicateBatchIsRejectedBeforeAnyToolExecutes() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        var executions = 0
        let tools = AgentChatToolSession(backend: { request in
            if request.operation == "drafts.get" { executions += 1 }
            return try runtime.backend(request)
        })
        let arguments = try runtime.arguments(runtime.allowed.id)
        let provider = ChatGPTProvider(stream: { _, event in _ = try event(completed([call(arguments), call(arguments)])) })
        await #expect(throws: ChatGPTProvider.Failure.invalidStream) {
            try await provider.respond(messages: [], model: "neutral", token: "neutral", tools: tools, onText: { _ in })
        }
        #expect(executions == 0)
    }

    @Test func revokedGrantAndChangedAccountStopBeforeLocalExecution() async throws {
        for changeAccount in [false, true] {
            let runtime = try AgentChatToolSessionTests.Runtime()
            var executions = 0, validAccount = true
            let tools = AgentChatToolSession(backend: { request in
                if request.operation == "drafts.get" { executions += 1 }
                return try runtime.backend(request)
            })
            let arguments = try runtime.arguments(runtime.allowed.id)
            let provider = ChatGPTProvider(stream: { _, event in
                _ = try event(completed([call(arguments)]))
                if changeAccount { validAccount = false }
                else { _ = try runtime.registry.revokeFromUserInterface(runtime.record.id) }
            })
            do {
                _ = try await provider.respond(messages: [], model: "neutral", token: "neutral", tools: tools,
                    validate: { if !validAccount { throw CancellationError() } }, onText: { _ in })
                Issue.record("Inactive authority executed a tool")
            } catch {
                if changeAccount { #expect(error is CancellationError) }
                else { #expect(error as? AgentErrorCode == .permissionDenied) }
            }
            #expect(executions == 0)
        }
    }
}
