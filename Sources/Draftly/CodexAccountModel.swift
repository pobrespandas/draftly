import AppKit
import Combine

struct CodexChatModel: Equatable, Identifiable {
    let id: String
    let name: String
    let isDefault: Bool
}

@MainActor final class CodexAccountModel: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var isBusy = false
    @Published private(set) var isAwaitingLogin = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var models: [CodexChatModel] = []
    private let client: CodexAppServerClient
    private let chatSession: CodexChatSession
    private let home: URL
    private var initialized = false
    private var loginID: String?
    private var startingLogin = false
    private var earlyLoginCompletion: Data?
    var executable: URL?

    init(client: CodexAppServerClient = CodexAppServerClient(), home: URL? = nil) {
        self.client = client
        self.chatSession = CodexChatSession(client: client)
        let identifier = Bundle.main.bundleIdentifier ?? "com.pobrespandas.draftly"
        let folder = identifier == "com.pobrespandas.draftly" ? "Draftly" : identifier.replacingOccurrences(of: "/", with: "_")
        self.home = home ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folder, isDirectory: true).appendingPathComponent("Codex", isDirectory: true)
        let candidates = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
                          "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
        client.onNotification = { [weak self] method, data in
            guard let self else { return }
            self.chatSession.receive(method, data: data)
            guard method == "account/login/completed" else { return }
            if self.startingLogin, self.loginID == nil { self.earlyLoginCompletion = data }
            else { self.completeLogin(data) }
        }
        client.onDisconnect = { [weak self] in
            self?.chatSession.disconnected()
            self?.initialized = false; self?.isSignedIn = false
            self?.models = []
            self?.loginID = nil; self?.isAwaitingLogin = false
        }
    }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            try await initialize()
            let account = try await request("account/read", ["refreshToken": false])
            isSignedIn = (account["account"] as? [String: Any])?["type"] as? String == "chatgpt"
            models = isSignedIn ? try await loadModels() : []
        } catch { models = []; errorMessage = error.localizedDescription }
    }

    func signIn(openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }) async {
        guard !isBusy, !isAwaitingLogin else { return }
        isBusy = true; errorMessage = nil
        startingLogin = true; earlyLoginCompletion = nil
        defer { isBusy = false; startingLogin = false }
        do {
            try await initialize()
            let result = try await request("account/login/start", ["type": "chatgpt"])
            guard let id = result["loginId"] as? String,
                  let rawURL = result["authUrl"] as? String, let url = URL(string: rawURL),
                  url.scheme == "https", url.host != nil else { throw CodexConnectionError.invalidMessage }
            loginID = id; isAwaitingLogin = true
            guard openURL(url) else {
                await cancelSignIn()
                throw CodexConnectionError.remote("The sign-in page could not be opened.")
            }
            if let completion = earlyLoginCompletion {
                earlyLoginCompletion = nil; completeLogin(completion)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func completeLogin(_ data: Data) {
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              loginID != nil, result["loginId"] as? String == loginID else { return }
        loginID = nil; isAwaitingLogin = false
        if result["success"] as? Bool == true { Task { await self.refresh() } }
        else { errorMessage = result["error"] as? String ?? "ChatGPT sign-in did not complete." }
    }

    func cancelSignIn() async {
        guard let id = loginID else { return }
        loginID = nil; isAwaitingLogin = false
        do { _ = try await request("account/login/cancel", ["loginId": id]) }
        catch { client.close(); errorMessage = error.localizedDescription }
    }

    func signOut() async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            try await initialize()
            _ = try await request("account/logout", [:])
            isSignedIn = false; loginID = nil; isAwaitingLogin = false
            models = []
        } catch { errorMessage = error.localizedDescription }
    }

    func disconnect() { client.close() }

    private func loadModels() async throws -> [CodexChatModel] {
        var cursor: String?, visited = Set<String>(), result: [String: CodexChatModel] = [:]
        for _ in 0..<32 {
            var params: [String: Any] = ["includeHidden": false, "limit": 50]
            if let cursor { params["cursor"] = cursor }
            let page = try await request("model/list", params)
            guard let entries = page["data"] as? [[String: Any]] else { throw CodexConnectionError.invalidMessage }
            for entry in entries where entry["hidden"] as? Bool != true {
                guard let id = entry["model"] as? String, !id.isEmpty else { continue }
                result[id] = CodexChatModel(id: id, name: entry["displayName"] as? String ?? id,
                    isDefault: entry["isDefault"] as? Bool ?? false)
            }
            guard let next = page["nextCursor"] as? String else {
                return result.values.sorted {
                    if $0.isDefault != $1.isDefault { return $0.isDefault }
                    return $0.id < $1.id
                }
            }
            guard visited.insert(next).inserted else { throw CodexConnectionError.invalidMessage }
            cursor = next
        }
        throw CodexConnectionError.invalidMessage
    }

    func respond(prompt: String, model: String, onText: @escaping (String) -> Void) async throws -> String {
        guard !isBusy, !isAwaitingLogin else { throw CodexConnectionError.remote("The ChatGPT connection is busy.") }
        isBusy = true
        defer { isBusy = false; chatSession.onText = nil }
        try await initialize()
        let account = try await request("account/read", ["refreshToken": false])
        isSignedIn = (account["account"] as? [String: Any])?["type"] as? String == "chatgpt"
        guard isSignedIn else { throw CodexConnectionError.remote("Sign in with ChatGPT before sending a message.") }
        let workspace = home.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        chatSession.onText = onText
        return try await chatSession.respond(prompt: prompt, model: model, workingDirectory: workspace)
    }

    private func initialize() async throws {
        guard !initialized else { return }
        guard let executable else { throw CodexConnectionError.remote("Choose the Codex executable to connect your ChatGPT account.") }
        try client.start(executable: executable, home: home)
        do {
            _ = try await request("initialize", ["clientInfo": ["name": "draftly", "title": "Draftly", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"], "capabilities": [:]])
            try client.notify("initialized")
            initialized = true
        } catch { client.close(); throw error }
    }

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: params)
        let result = try await client.request(method, params: data)
        guard let object = try JSONSerialization.jsonObject(with: result) as? [String: Any] else {
            throw CodexConnectionError.invalidMessage
        }
        return object
    }
}
