import Combine
import Foundation

struct ChatConsoleMessage: Codable, Equatable, Identifiable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    let date: Date

    init(role: Role, text: String, date: Date = Date()) {
        id = UUID(); self.role = role; self.text = text; self.date = date
    }
}

struct ChatConsoleConversation: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var messages: [ChatConsoleMessage]
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "New Chat", messages: [ChatConsoleMessage] = [], updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.messages = messages; self.updatedAt = updatedAt
    }
}

@MainActor final class ChatConsoleModel: ObservableObject {
    let codexAccount: CodexAccountModel
    private struct SavedState: Codable {
        var conversations: [ChatConsoleConversation]
        var selectedConversationID: UUID?
    }
    static let storageKey = "chatConsole.state"
    typealias LoadModes = @MainActor () async throws -> [String]
    typealias Respond = @MainActor (_ prompt: String, _ mode: String) async throws -> String

    @Published private(set) var conversations: [ChatConsoleConversation] = []
    @Published private(set) var selectedConversationID: UUID?
    @Published private(set) var availableModels: [String] = []
    @Published var selectedModel = "onDevice"
    @Published var prompt = ""
    @Published private(set) var isResponding = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var streamingText = ""

    private let loadModes: LoadModes
    private let respond: Respond
    private let defaults: UserDefaults
    private let refreshCodexOnLoad: Bool
    private var responseTask: Task<Void, Never>?
    private var responseID: UUID?
    private var hasLoadedModels = false
    private var appleModels: [String] = []
    private var subscriptions = Set<AnyCancellable>()

    var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
            && availableModels.contains(selectedModel)
            && (!selectedModel.hasPrefix("codex:") || !codexAccount.isBusy)
    }

    var selectedConversation: ChatConsoleConversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    init(loadModes: @escaping LoadModes, respond: @escaping Respond, defaults: UserDefaults = .standard,
         codexAccount: CodexAccountModel = CodexAccountModel(), refreshCodexOnLoad: Bool = false) {
        self.loadModes = loadModes; self.respond = respond; self.defaults = defaults
        self.codexAccount = codexAccount
        self.refreshCodexOnLoad = refreshCodexOnLoad
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            conversations = Array(saved.conversations.sorted { $0.updatedAt > $1.updatedAt }.prefix(50))
            if let id = saved.selectedConversationID, conversations.contains(where: { $0.id == id }) {
                selectedConversationID = id
            }
        }
        if conversations.isEmpty { startConversation() }
        else if selectedConversationID == nil { selectedConversationID = conversations.first?.id }
        codexAccount.$models.sink { [weak self] models in self?.updateModelOptions(models) }.store(in: &subscriptions)
        codexAccount.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    convenience init(models: NativeModelAPI) {
        self.init(loadModes: {
            let raw = try await models.performAsync("modelModes", payload: "{}")
            guard let frame = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  let values = frame["value"] as? [String] else { throw ChatConsoleError.invalidModelResponse }
            return values
        }, respond: { prompt, mode in
            let id = UUID().uuidString
            defer { models.discardSession(id) }
            let data = try JSONSerialization.data(withJSONObject: ["prompt": prompt, "mode": mode, "sessionID": id])
            let raw = try await models.performAsync("modelRespond", payload: String(decoding: data, as: UTF8.self))
            guard let frame = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  let value = frame["value"] as? [String: Any],
                  let response = value["response"] as? String else { throw ChatConsoleError.invalidModelResponse }
            return response
        }, refreshCodexOnLoad: true)
    }

    func loadModels() async {
        guard !hasLoadedModels else { return }
        hasLoadedModels = true
        do {
            appleModels = try await loadModes().filter { ["onDevice", "pcc"].contains($0) }
            updateModelOptions(codexAccount.models)
        } catch {
            errorMessage = error.localizedDescription
        }
        if refreshCodexOnLoad, codexAccount.executable != nil { await codexAccount.refresh() }
    }

    private func updateModelOptions(_ models: [CodexChatModel]) {
        availableModels = appleModels + models.map { "codex:" + $0.id }
        if !availableModels.contains(selectedModel), !selectedModel.hasPrefix("codex:") {
            selectedModel = availableModels.first ?? ""
        }
    }

    func modelName(_ value: String) -> String {
        switch value {
        case "onDevice": return "On-Device"
        case "pcc": return "Cloud"
        default:
            guard value.hasPrefix("codex:") else { return "Choose Model" }
            let id = String(value.dropFirst(6))
            return "ChatGPT · " + (codexAccount.models.first { $0.id == id }?.name ?? id)
        }
    }

    func startConversation() {
        stopCurrentResponse(); errorMessage = nil
        let conversation = ChatConsoleConversation()
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        if conversations.count > 50 { conversations.removeLast(conversations.count - 50) }
        persist()
    }

    func selectConversation(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        stopCurrentResponse(); errorMessage = nil
        selectedConversationID = id
        persist()
    }

    func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend,
              let conversationID = selectedConversationID else { return }
        prompt = ""; errorMessage = nil; streamingText = ""
        append(.init(role: .user, text: text), to: conversationID)
        let context = contextForResponse(conversationID)
        let mode = selectedModel
        let id = UUID()
        responseID = id
        isResponding = true
        responseTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if responseID == id {
                    responseID = nil; isResponding = false; responseTask = nil; streamingText = ""
                }
            }
            do {
                let answer: String
                if mode.hasPrefix("codex:") {
                    answer = try await codexAccount.respond(prompt: context, model: String(mode.dropFirst(6))) { [weak self] text in
                        guard let self, self.responseID == id else { return }
                        self.streamingText = text
                    }
                } else { answer = try await respond(context, mode) }
                try Task.checkCancellation()
                guard responseID == id else { return }
                append(.init(role: .assistant, text: answer), to: conversationID)
            } catch is CancellationError {
                // Keep the user's message. The Stop button cancels only this response.
            } catch {
                if responseID == id { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelResponse() {
        responseTask?.cancel()
    }

    func close() {
        stopCurrentResponse()
        codexAccount.disconnect()
    }

    private func stopCurrentResponse() {
        responseID = nil
        streamingText = ""
        responseTask?.cancel(); responseTask = nil; isResponding = false
    }

    private func append(_ message: ChatConsoleMessage, to id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = message.date
        if conversations[index].messages.count == 1, message.role == .user {
            conversations[index].title = String(message.text.prefix(48))
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    private func persist() {
        let state = SavedState(conversations: conversations, selectedConversationID: selectedConversationID)
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func contextForResponse(_ id: UUID) -> String {
        guard let messages = conversations.first(where: { $0.id == id })?.messages else { return "" }
        // Rebuild context for each stateless model request.
        let lines = messages.suffix(80).map { message in
            "\(message.role == .user ? "User" : "Assistant"): \(message.text)"
        }
        return lines.joined(separator: "\n\n")
    }
}

enum ChatConsoleError: LocalizedError {
    case invalidModelResponse
    var errorDescription: String? { "The model returned an invalid response." }
}
