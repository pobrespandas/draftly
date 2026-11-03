import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Chat Console") @MainActor
struct ChatConsoleModelTests {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ChatConsoleTests-\(UUID().uuidString)")!
    }

    @Test func restoresSelectedModelWithoutGrantingAccess() async {
        let defaults = isolatedDefaults()
        let first = ChatConsoleModel(loadModes: { ["onDevice", "pcc"] }, respond: { _, _ in "unused" }, defaults: defaults)
        await first.loadModels()
        first.selectedModel = "chatgpt:previous-model"
        first.close()
        let restored = ChatConsoleModel(loadModes: { ["onDevice", "pcc"] }, respond: { _, _ in "unused" }, defaults: defaults)
        await restored.loadModels()
        restored.prompt = "Wait for the selected provider"
        #expect(restored.selectedModel == "chatgpt:previous-model")
        #expect(!restored.canSend && !restored.hasTools)
        restored.selectedModel = "pcc"
        let cloud = ChatConsoleModel(loadModes: { ["onDevice", "pcc"] }, respond: { _, _ in "unused" }, defaults: defaults)
        await cloud.loadModels()
        #expect(cloud.selectedModel == "pcc")
        restored.close(); cloud.close()
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

    @Test func twoWindowsKeepBothHistoriesAndMergeSharedMessages() async throws {
        let defaults = isolatedDefaults()
        func makeWindow() -> ChatConsoleModel {
            ChatConsoleModel(loadModes: { ["onDevice"] }, respond: { _, _ in "Reply" }, defaults: defaults)
        }
        let first = makeWindow(), second = makeWindow()
        await first.loadModels(); await second.loadModels()
        let sharedID = try #require(first.selectedConversationID)
        first.prompt = "First window"; first.send()
        for _ in 0..<100 where first.isResponding { await Task.yield() }
        second.prompt = "Second window"; second.send()
        for _ in 0..<100 where second.isResponding { await Task.yield() }
        #expect(second.selectedConversation?.messages.map(\.text) == ["First window", "Reply", "Second window", "Reply"])
        second.startConversation()
        let separateID = try #require(second.selectedConversationID)
        second.prompt = "Separate conversation"; second.send()
        for _ in 0..<100 where second.isResponding { await Task.yield() }
        first.prompt = "Still here"; first.send()
        for _ in 0..<100 where first.isResponding { await Task.yield() }
        let restored = makeWindow()
        #expect(restored.conversations.contains { $0.id == separateID && $0.messages.count == 2 })
        let shared = try #require(restored.conversations.first { $0.id == sharedID })
        #expect(shared.messages.count == 6)
        #expect(Set(shared.messages.map(\.id)).count == 6)
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

    @Test func rejectedToolAttachmentClosesTheIncomingSession() throws {
        let model = ChatConsoleModel(loadModes: { [] }, respond: { _, _ in "unused" }, defaults: isolatedDefaults())
        var closes = 0
        let tools = AgentChatToolSession(backend: { _ in
            Issue.record("An unsigned-in console invoked local tools")
            throw CancellationError()
        }, onDisconnect: { closes += 1 })
        #expect(throws: AgentErrorCode.permissionDenied) { try model.connectTools(tools) }
        #expect(!model.hasTools && closes == 1)
        model.close(); tools.invalidate()
        #expect(closes == 1)
    }

    @Test func directCatalogRoutesTheChatAndLogoutDoesNotSwitchProviders() async throws {
        let defaults = isolatedDefaults(), vault = ChatGPTLoginServiceTests.Vault()
        let login = ChatGPTLoginService(defaults: defaults, store: vault.store, lease: { _ in NSObject() })
        let record = ChatGPTAccountRecord(id: UUID(), identity: ChatGPTIdentity(issuer: "https://auth.openai.com", clientID: "oaiapp_neutral",
            subject: "neutral", email: nil, name: nil), hostID: login.hostID,
            tokens: ChatGPTTokens(accessToken: "neutral-token", refreshToken: "neutral-refresh", idToken: "neutral-id",
                scopes: ["resource.invoke", "chatgpt.tokens.use.direct"], expiresAt: .distantFuture))
        try login.save(record)
        defaults.set([record.id.uuidString], forKey: "chatGPT.registrationIDs")
        defaults.set(record.id.uuidString, forKey: "chatGPT.selectedID")
        let provider = ChatGPTProvider(exchange: { _ in
            .init(status: 200, data: Data(#"{"models":[{"slug":"model-a","display_name":"Test model","visibility":"list"}]}"#.utf8))
        }, stream: { _, event in
            _ = try event(Data(#"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Reply café"}]}]}}"#.utf8))
        })
        let sessions = ChatGPTSessionService(login: login, exchange: { _ in .init(status: 503, data: Data()) }, lease: { _ in NSObject() })
        let account = ChatGPTAccountModel(defaults: defaults, login: login, sessions: sessions, provider: provider)
        var appleCalls = 0
        let model = ChatConsoleModel(loadModes: { [] }, respond: { _, _ in appleCalls += 1; return "Wrong provider" },
                                     defaults: defaults, chatGPTAccount: account)
        defer { model.close() }
        await model.loadModels()
        #expect(model.availableModels == ["chatgpt:model-a"])
        #expect(model.modelName(model.selectedModel) == "ChatGPT · Test model")
        let runtime = try AgentChatToolSessionTests.Runtime()
        var toolDisconnects = 0
        let tools = AgentChatToolSession(service: runtime.service, session: runtime.session,
            onDisconnect: { toolDisconnects += 1 })
        try model.connectTools(tools)
        #expect(model.hasTools)
        model.prompt = "Neutral café"; model.send()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while model.isResponding, ContinuousClock.now < deadline { await Task.yield() }
        #expect(model.errorMessage == nil)
        #expect(model.selectedConversation?.messages.map(\.text) == ["Neutral café", "Reply café"])
        await account.signOut()
        #expect(!model.hasTools && toolDisconnects == 1)
        model.prompt = "Keep this prompt"; model.send()
        #expect(!model.canSend && model.prompt == "Keep this prompt")
        #expect(model.selectedModel == "chatgpt:model-a" && appleCalls == 0)
    }
}
