import Foundation
import Testing
@testable import Draftly

@Suite("Chat conversation storage compatibility") @MainActor
struct ChatConversationStoreTests {
    @Test func readsExistingJSONAndWritesTheSameFields() throws {
        let preferences = try TestPreferences(prefix: "ChatStore-Compatibility-")
        defer { preferences.close() }
        let defaults = preferences.defaults
        let conversationID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let messageID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
        let data = Data("""
            {"conversations":[{"id":"\(conversationID)","title":"café 🐼\\nSegunda línea", "messages":[
            {"id":"\(messageID)","role":"user","text":"café 🐼\\nSegunda línea","date":100}],"updatedAt":101}],
            "selectedConversationID":"\(conversationID)"}
            """.utf8)
        defaults.set(data, forKey: "chatConsole.state")
        let store = ChatConversationStore(defaults: defaults)
        let restored = try #require(store.restore())
        #expect(restored.selectedConversationID == conversationID)
        let message = try #require(restored.conversations.first?.messages.first)
        #expect(message.id == messageID && message.text == "café 🐼\nSegunda línea")
        #expect(message.date == Date(timeIntervalSinceReferenceDate: 100))
        _ = store.save(restored.conversations, selectedConversationID: restored.selectedConversationID)
        let written = try #require(defaults.data(forKey: "chatConsole.state"))
        let before = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        let after = try JSONSerialization.jsonObject(with: written) as? NSDictionary
        #expect(before == after)
    }

    @Test func restoreKeepsNewestFiftyAndClearsSelectionOutsideThem() throws {
        let preferences = try TestPreferences(prefix: "ChatStore-Retention-")
        defer { preferences.close() }
        let conversations = (0..<51).map {
            ChatConsoleConversation(title: "Chat \($0)", updatedAt: Date(timeIntervalSinceReferenceDate: Double($0)))
        }
        let oldID = try #require(conversations.first?.id)
        let payload = ChatConversationStore.Snapshot(conversations: conversations, selectedConversationID: oldID)
        preferences.defaults.set(try JSONEncoder().encode(payload), forKey: ChatConversationStore.storageKey)
        let restored = try #require(ChatConversationStore(defaults: preferences.defaults).restore())
        #expect(restored.conversations.map(\.id) == Array(conversations.reversed().prefix(50)).map(\.id))
        #expect(restored.selectedConversationID == nil)
    }

    @Test func invalidStorageDoesNotEraseLocalHistoryDuringMerge() throws {
        let preferences = try TestPreferences(prefix: "ChatStore-Invalid-")
        defer { preferences.close() }
        let store = ChatConversationStore(defaults: preferences.defaults)
        #expect(store.restore() == nil)
        let invalid = Data("not JSON".utf8)
        preferences.defaults.set(invalid, forKey: ChatConversationStore.storageKey)
        let local = [ChatConsoleConversation(messages: [.init(role: .user, text: "Local café 🐼")])]
        #expect(store.restore() == nil)
        #expect(store.merging(local) == local)
        #expect(preferences.defaults.data(forKey: ChatConversationStore.storageKey) == invalid)
    }
}
