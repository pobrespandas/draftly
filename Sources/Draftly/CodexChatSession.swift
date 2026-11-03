import Foundation

@MainActor final class CodexChatSession {
    var onText: ((String) -> Void)?
    private let client: CodexAppServerClient
    private var requestID: UUID?
    private var threadID: String?
    private var turnID: String?
    private var earlyEvents: [(String, Data)] = []
    private var messages: [(id: String, text: String)] = []
    private var continuation: CheckedContinuation<String, Error>?
    private var terminal: Result<String, Error>?
    private var deadline: Task<Void, Never>?

    init(client: CodexAppServerClient) { self.client = client }

    func respond(prompt: String, model: String, workingDirectory: URL) async throws -> String {
        guard requestID == nil else { throw CodexConnectionError.remote("A Codex response is already running.") }
        try Task.checkCancellation()
        let id = UUID(); requestID = id
        defer {
            deadline?.cancel(); deadline = nil
            requestID = nil; threadID = nil; turnID = nil
            earlyEvents.removeAll(); messages.removeAll(); terminal = nil
        }
        let thread = try await request("thread/start", ["model": model, "cwd": workingDirectory.path,
            "ephemeral": true, "sandbox": "read-only", "approvalPolicy": "untrusted",
            "baseInstructions": "Help the user write and develop ideas. Use only the text and authorized tools supplied by Draftly.",
            "config": ["features.shell_tool": false, "agents.enabled": false, "web_search": "disabled"]])
        guard let value = thread["thread"] as? [String: Any], let thread = value["id"] as? String else {
            throw CodexConnectionError.invalidMessage
        }
        threadID = thread
        let started = try await request("turn/start", ["threadId": thread,
            "input": [["type": "text", "text": prompt, "text_elements": []]]])
        guard let turn = started["turn"] as? [String: Any], let turn = turn["id"] as? String else {
            throw CodexConnectionError.invalidMessage
        }
        turnID = turn
        let events = earlyEvents; earlyEvents.removeAll()
        for (method, data) in events { receive(method, data: data) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiting in
                if Task.isCancelled {
                    continuation = waiting
                    Task { await self.interrupt(id: id, error: CancellationError()) }
                } else if let terminal { waiting.resume(with: terminal) }
                else {
                    continuation = waiting
                    deadline = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(180)) } catch { return }
                        await self?.interrupt(id: id, error: CodexConnectionError.timeout)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in await self?.interrupt(id: id, error: CancellationError()) }
        }
    }

    func receive(_ method: String, data: Data) {
        guard requestID != nil, let threadID,
              let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              params["threadId"] as? String == threadID else { return }
        guard let turnID else {
            if earlyEvents.count < 2048 { earlyEvents.append((method, data)) }
            else { finish(.failure(CodexConnectionError.invalidMessage)) }
            return
        }
        if method == "turn/completed" {
            guard let turn = params["turn"] as? [String: Any], turn["id"] as? String == turnID else { return }
            switch turn["status"] as? String {
            case "completed": finish(.success(messages.map(\.text).joined(separator: "\n\n")))
            case "interrupted": finish(.failure(CancellationError()))
            default:
                let error = turn["error"] as? [String: Any]
                finish(.failure(CodexConnectionError.remote(error?["message"] as? String ?? "Codex could not complete the response.")))
            }
        } else if params["turnId"] as? String == turnID {
            if method == "item/agentMessage/delta", let item = params["itemId"] as? String,
               let delta = params["delta"] as? String {
                updateMessage(item, text: delta, append: true)
            } else if method == "item/completed", let item = params["item"] as? [String: Any],
                      item["type"] as? String == "agentMessage", let id = item["id"] as? String,
                      let text = item["text"] as? String {
                updateMessage(id, text: text, append: false)
            }
        }
    }

    func disconnected() { finish(.failure(CodexConnectionError.disconnected)) }

    private func updateMessage(_ id: String, text: String, append: Bool) {
        guard terminal == nil else { return }
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text = append ? messages[index].text + text : text
        } else { messages.append((id, text)) }
        onText?(messages.map(\.text).joined(separator: "\n\n"))
    }

    private func interrupt(id: UUID, error: Error) async {
        guard requestID == id, terminal == nil else { return }
        // Set the terminal result before awaiting the interrupt acknowledgement.
        terminal = .failure(error)
        if let threadID, let turnID {
            do { _ = try await request("turn/interrupt", ["threadId": threadID, "turnId": turnID]) }
            catch { client.close() }
        }
        guard requestID == id else { return }
        finish(.failure(error))
    }

    private func finish(_ result: Result<String, Error>) {
        guard requestID != nil else { return }
        let result = terminal ?? result
        terminal = result
        if let waiting = continuation { continuation = nil; waiting.resume(with: result) }
    }

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let data = try await client.request(method, params: JSONSerialization.data(withJSONObject: params))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CodexConnectionError.invalidMessage }
        return object
    }
}
