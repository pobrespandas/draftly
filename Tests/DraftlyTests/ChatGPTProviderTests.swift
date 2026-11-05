import Foundation
import Testing
@testable import Draftly

@Suite("Direct ChatGPT Responses") @MainActor
struct ChatGPTProviderTests {
    @Test func catalogUsesAccountTokenAndPreservesVisibleServerOrder() async throws {
        let data = Data(#"{"models":[{"slug":"second","display_name":"Second","visibility":"list"},{"slug":"hidden","display_name":"Hidden","visibility":"hidden"},{"slug":"first","display_name":"First","visibility":"list"},{"slug":"second","display_name":"Duplicate","visibility":"list"}]}"#.utf8)
        let provider = ChatGPTProvider(exchange: { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer neutral-token")
            return .init(status: 200, data: data)
        })
        #expect(try await provider.models(token: "neutral-token") == [.init(id: "second", name: "Second"), .init(id: "first", name: "First")])
    }

    @Test func sendsStatelessStructuredHistoryAndCommitsAuthoritativeCompletedText() async throws {
        var updates: [String] = []
        let provider = ChatGPTProvider(stream: { request, event in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer neutral-token")
            let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect(Set(body.keys) == ["model", "input", "store", "stream"])
            #expect(body["store"] as? Bool == false && body["stream"] as? Bool == true)
            let input = try #require(body["input"] as? [[String: String]])
            #expect(input.map { $0["role"]! } == ["user", "assistant", "user"])
            #expect(input.last?["content"] == "Keep café 🐼")
            #expect(try event(Data(#"{"type":"response.output_text.delta","delta":"Partial","output_index":0,"content_index":0}"#.utf8)) == false)
            #expect(try event(Self.completed("Final café 🐼")))
        })
        let result = try await provider.respond(messages: [.init(role: .user, text: "First"), .init(role: .assistant, text: "Earlier"),
            .init(role: .user, text: "Keep café 🐼")], model: "neutral-model", token: "neutral-token") { updates.append($0) }
        #expect(result == "Final café 🐼" && updates == ["Partial", "Final café 🐼"])
    }

    @Test func partialOrFailedStreamCannotBecomeSuccessfulResponse() async throws {
        let partial = Data(#"{"type":"response.output_text.delta","delta":"Unfinished","output_index":0,"content_index":0}"#.utf8)
        let provider = ChatGPTProvider(stream: { _, event in _ = try event(partial) })
        await #expect(throws: ChatGPTProvider.Failure.incomplete) {
            try await provider.respond(messages: [], model: "neutral", token: "neutral", onText: { _ in })
        }
        let failed = ChatGPTProvider(stream: { _, event in
            _ = try event(partial)
            _ = try event(Data(#"{"type":"response.failed","response":{"status":"failed","error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"#.utf8))
        })
        await #expect(throws: ChatGPTProvider.Failure.usageLimit) {
            try await failed.respond(messages: [], model: "neutral", token: "neutral", onText: { _ in })
        }
    }

    @Test func cancelledRequestRejectsLateCompletionWithoutRetry() async throws {
        let (started, entered) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        var calls = 0
        let provider = ChatGPTProvider(stream: { _, event in
            calls += 1
            entered.yield(); entered.finish()
            for await _ in released { break }
            _ = try event(Self.completed("Late reply"))
        })
        let task = Task { try await provider.respond(messages: [], model: "neutral", token: "neutral", onText: { _ in
            Issue.record("A cancelled response reached the transcript.")
        }) }
        for await _ in started { break }
        task.cancel()
        release.yield(); release.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(calls == 1)
    }

    @Test func rejectsMismatchedResponsesIncompleteStatusAndUnconnectedTools() async throws {
        let endings = [
            Data(#"{"type":"response.completed","response":{"id":"other","status":"completed","output":[]}}"#.utf8),
            Data(#"{"type":"response.completed","response":{"id":"same","status":"incomplete","output":[]}}"#.utf8),
            Data(#"{"type":"response.completed","response":{"id":"same","status":"completed","output":[{"type":"function_call"}]}}"#.utf8)
        ]
        for ending in endings {
            let provider = ChatGPTProvider(stream: { _, event in
                _ = try event(Data(#"{"type":"response.created","response":{"id":"same","status":"in_progress"}}"#.utf8))
                _ = try event(ending)
            })
            await #expect(throws: ChatGPTProvider.Failure.self) {
                try await provider.respond(messages: [], model: "neutral", token: "neutral", onText: { _ in })
            }
        }
    }

    @Test func sseHandlesUTF8CommentsMultilineDataAndAllLineEndings() throws {
        for separator in ["\n", "\r\n", "\r"] {
            let payload = ": keepalive\(separator)event: response\(separator)data: {\(separator)data: \"text\":\"café 🐼\"}\(separator)\(separator)"
            var decoder = ChatGPTSSEDecoder(), events: [Data] = []
            for byte in payload.utf8 { if let event = try decoder.append(byte) { events.append(event) } }
            #expect(events.count == 1)
            let value = try #require(try JSONSerialization.jsonObject(with: events[0]) as? [String: String])
            #expect(value["text"] == "café 🐼")
        }
        var decoder = ChatGPTSSEDecoder()
        #expect(throws: ChatGPTProvider.Failure.tooLarge) {
            for byte in Data(repeating: 65, count: 1048577) { _ = try decoder.append(byte) }
        }
    }

    private static func completed(_ text: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": "response.completed", "response": ["id": "neutral", "status": "completed",
            "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]]])
    }
}
