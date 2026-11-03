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

    @Test func codexCatalogRoutesTheChatAndLogoutDoesNotSwitchProviders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        read -r request
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r initialized
        read -r request
        printf '%s\\n' '{"id":2,"result":{"account":{"type":"chatgpt"},"requiresOpenaiAuth":true}}'
        if [ "$1" = "model" ]; then
          read -r request
          printf '%s\\n' '{"id":3,"result":{"thread":{"id":"thread-a"}}}'
          read -r request
          printf '%s\\n' '{"id":4,"result":{"turn":{"id":"turn-a"}}}' \
            '{"method":"item/agentMessage/delta","params":{"threadId":"thread-a","turnId":"turn-a","itemId":"message","delta":"Reply café"}}' \
            '{"method":"turn/completed","params":{"threadId":"thread-a","turn":{"id":"turn-a","status":"completed"}}}'
        else
          read -r request
          printf '%s\\n' '{"id":3,"result":{"data":[{"model":"model-a","displayName":"Test model","isDefault":true},{"model":"hidden","hidden":true}],"nextCursor":null}}'
          read -r request
          printf '%s\\n' '{"id":4,"result":{"account":{"type":"chatgpt"},"requiresOpenaiAuth":true}}'
          read -r request
          printf '%s\\n' '{"id":5,"result":{}}'
        fi
        while read -r request; do :; done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let modelClient = CodexAppServerClient(makeLaunchPlan: { executable, _ in
            CodexLaunchPlan(executable: executable, arguments: ["model"])
        })
        let account = CodexAccountModel(client: modelClient, authenticationClient: .protocolFixture(), home: root.appendingPathComponent("home"))
        account.executable = executable
        var appleCalls = 0
        let model = ChatConsoleModel(loadModes: { [] }, respond: { _, _ in appleCalls += 1; return "Wrong provider" },
            defaults: isolatedDefaults(), codexAccount: account)
        defer { model.close() }
        await model.loadModels()
        await account.refresh()
        #expect(account.errorMessage == nil)
        #expect(model.availableModels == ["codex:model-a"])
        #expect(model.modelName(model.selectedModel) == "ChatGPT · Test model")
        model.prompt = "Neutral café"
        model.send()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while model.isResponding, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isResponding)
        #expect(model.errorMessage == nil)
        #expect(model.selectedConversation?.messages.map(\.text) == ["Neutral café", "Reply café"])
        await account.signOut()
        model.prompt = "Keep this prompt"
        model.send()
        #expect(!model.canSend)
        #expect(model.prompt == "Keep this prompt")
        #expect(model.selectedModel == "codex:model-a")
        #expect(appleCalls == 0)
    }
}
