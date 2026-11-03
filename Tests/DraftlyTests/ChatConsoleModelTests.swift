import Foundation
import Testing
@testable import Draftly

@Suite("Chat Console") @MainActor
struct ChatConsoleModelTests {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ChatConsoleTests-\(UUID().uuidString)")!
    }

    @Test func sendsContextAndKeepsConversationsSeparate() async throws {
        let model = ChatConsoleModel(loadModes: { ["onDevice", "unsupported"] }, respond: { prompt, mode in
            #expect(mode == "onDevice")
            return "Reply to: " + prompt
        }, defaults: isolatedDefaults())
        await model.loadModels()
        #expect(model.availableModels == ["onDevice"])
        model.prompt = "Use café as an example"
        model.send()
        for _ in 0..<100 where model.isResponding { await Task.yield() }
        let firstID = try #require(model.selectedConversationID)
        let first = try #require(model.conversations.first { $0.id == firstID })
        #expect(first.title == "Use café as an example")
        #expect(first.messages.map(\.role) == [.user, .assistant])
        #expect(first.messages[1].text.contains("User: Use café as an example"))

        model.startConversation()
        let secondID = try #require(model.selectedConversationID)
        #expect(secondID != firstID)
        #expect(model.selectedConversation?.messages.isEmpty == true)
        model.selectConversation(firstID)
        #expect(model.selectedConversation?.messages == first.messages)
    }

    @Test func stopCancelsOnlyTheActiveResponse() async throws {
        let model = ChatConsoleModel(loadModes: { ["onDevice"] }, respond: { _, _ in
            try await Task.sleep(for: .seconds(5))
            return "Should not appear"
        }, defaults: isolatedDefaults())
        await model.loadModels()
        model.prompt = "Please wait"
        model.send()
        #expect(model.isResponding)
        model.cancelResponse()
        for _ in 0..<100 where model.isResponding { await Task.yield() }
        #expect(model.selectedConversation?.messages.map(\.role) == [.user])
        #expect(!model.isResponding)
    }

    @Test func conversationsSurviveModelRecreation() async throws {
        let defaults = isolatedDefaults()
        let model = ChatConsoleModel(loadModes: { ["onDevice"] }, respond: { _, _ in "Saved reply" }, defaults: defaults)
        await model.loadModels()
        model.prompt = "Keep this conversation"
        model.send()
        for _ in 0..<100 where model.isResponding { await Task.yield() }
        let originalID = try #require(model.selectedConversationID)

        let restored = ChatConsoleModel(loadModes: { ["onDevice"] }, respond: { _, _ in "unused" }, defaults: defaults)
        #expect(restored.selectedConversationID == originalID)
        #expect(restored.selectedConversation?.messages.map(\.text) == ["Keep this conversation", "Saved reply"])
    }

    @Test func lateResponseFromClosedConversationCannotAffectTheNewChat() async throws {
        var pending: [CheckedContinuation<String, Never>] = []
        let model = ChatConsoleModel(loadModes: { ["onDevice"] }, respond: { _, _ in
            await withCheckedContinuation { pending.append($0) }
        }, defaults: isolatedDefaults())
        await model.loadModels()

        model.prompt = "Old request"
        model.send()
        for _ in 0..<100 where pending.isEmpty { await Task.yield() }
        #expect(pending.count == 1)

        model.startConversation()
        model.prompt = "New request"
        model.send()
        for _ in 0..<100 where pending.count < 2 { await Task.yield() }
        #expect(pending.count == 2)

        pending[0].resume(returning: "Stale reply")
        pending[1].resume(returning: "Current reply")
        for _ in 0..<100 where model.isResponding { await Task.yield() }
        #expect(model.selectedConversation?.messages.map(\.text) == ["New request", "Current reply"])
        #expect(!model.isResponding)
    }
}
