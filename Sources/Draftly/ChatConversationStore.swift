import Foundation

// MainActor keeps each merge and write serial across app windows.
@MainActor struct ChatConversationStore {
    struct Snapshot: Codable {
        var conversations: [ChatConsoleConversation]
        var selectedConversationID: UUID?
    }

    static let storageKey = "chatConsole.state"
    static let maximumCount = 50
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func restore() -> Snapshot? {
        guard var saved = read() else { return nil }
        saved.conversations = newest(saved.conversations)
        if let id = saved.selectedConversationID,
           !saved.conversations.contains(where: { $0.id == id }) {
            saved.selectedConversationID = nil
        }
        return saved
    }

    func merging(_ conversations: [ChatConsoleConversation]) -> [ChatConsoleConversation] {
        guard let saved = read() else { return conversations }
        var merged = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        for stored in saved.conversations {
            guard var local = merged[stored.id] else {
                merged[stored.id] = stored
                continue
            }
            let localIDs = Set(local.messages.map(\.id))
            local.messages += stored.messages.filter { !localIDs.contains($0.id) }
            local.messages.sort { $0.date < $1.date }
            local.updatedAt = max(local.updatedAt, stored.updatedAt)
            if let first = local.messages.first(where: { $0.role == .user }) {
                local.title = String(first.text.prefix(48))
            }
            merged[stored.id] = local
        }
        return newest(Array(merged.values))
    }

    func save(_ conversations: [ChatConsoleConversation], selectedConversationID: UUID?) -> [ChatConsoleConversation] {
        let merged = merging(conversations)
        let state = Snapshot(conversations: merged, selectedConversationID: selectedConversationID)
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storageKey)
        }
        return merged
    }

    private func newest(_ conversations: [ChatConsoleConversation]) -> [ChatConsoleConversation] {
        Array(conversations.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.maximumCount))
    }

    private func read() -> Snapshot? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
