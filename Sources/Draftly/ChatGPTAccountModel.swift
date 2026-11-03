import Combine
import Foundation

@MainActor final class ChatGPTAccountModel: ObservableObject {
    static let shared = ChatGPTAccountModel(provider: ChatGPTProvider())
    @Published private(set) var accounts: [ChatGPTAccountRecord] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var isBusy = false
    @Published private(set) var isAwaitingLogin = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var models: [ChatGPTModel] = []
    @Published private(set) var sessionEpoch = UUID()
    @Published private(set) var isLoadingModels = false
    private let defaults: UserDefaults
    private let login: ChatGPTLoginService
    private let sessions: ChatGPTSessionService
    private let provider: ChatGPTProvider?
    private var catalogTask: Task<Void, Never>?
    private var catalogID: UUID?
    private var loginTask: Task<Void, Never>?
    private var requestID: UUID?

    init(defaults: UserDefaults = .standard, login: ChatGPTLoginService? = nil, sessions: ChatGPTSessionService? = nil,
         provider: ChatGPTProvider? = nil) {
        self.defaults = defaults
        let login = login ?? ChatGPTLoginService(defaults: defaults)
        self.login = login
        self.sessions = sessions ?? ChatGPTSessionService(login: login)
        self.provider = provider
        selectedID = defaults.string(forKey: "chatGPT.selectedID").flatMap(UUID.init(uuidString:))
    }

    var selectedAccount: ChatGPTAccountRecord? { accounts.first { $0.id == selectedID } }
    var isSignedIn: Bool {
        guard let account = selectedAccount, let tokens = account.tokens, account.refreshUncertain != true else { return false }
        return tokens.expiresAt > Date() || tokens.refreshToken != nil
    }

    func refresh() {
        do {
            let ids = (defaults.stringArray(forKey: "chatGPT.registrationIDs") ?? []).compactMap(UUID.init(uuidString:))
            var seen = Set<UUID>()
            accounts = try ids.filter { seen.insert($0).inserted }.compactMap { try login.read($0) }
        } catch { errorMessage = "The saved ChatGPT accounts could not be read from Keychain." }
    }

    func select(_ id: UUID?) {
        guard !isBusy, id == nil || accounts.contains(where: { $0.id == id }) else { return }
        guard selectedID != id else { return }
        changeSession()
        selectedID = id
        defaults.set(id?.uuidString, forKey: "chatGPT.selectedID")
        errorMessage = nil
        scheduleModels()
    }

    func signIn() {
        beginSignIn(registration: selectedID)
    }

    private func beginSignIn(registration: UUID?) {
        guard !isBusy else { return }
        let id = UUID()
        requestID = id
        isBusy = true; isAwaitingLogin = true; errorMessage = nil
        loginTask = Task { [self] in
            defer {
                if requestID == id { isBusy = false; isAwaitingLogin = false; loginTask = nil; requestID = nil }
            }
            do {
                let record = try await login.signIn(registrationID: registration)
                guard requestID == id else { return }
                var ids = defaults.stringArray(forKey: "chatGPT.registrationIDs") ?? []
                if !ids.contains(record.id.uuidString) { ids.append(record.id.uuidString) }
                defaults.set(ids, forKey: "chatGPT.registrationIDs")
                changeSession()
                selectedID = record.id
                defaults.set(record.id.uuidString, forKey: "chatGPT.selectedID")
                refresh()
                scheduleModels()
            } catch is CancellationError {
                // Cancellation does not change the previously selected registration.
            } catch {
                if requestID == id { errorMessage = Self.message(for: error) }
            }
        }
    }

    func addAccount() {
        guard !isBusy else { return }
        login.startDifferentRegistration()
        beginSignIn(registration: nil)
    }

    func cancelSignIn() {
        guard isAwaitingLogin else { return }
        requestID = nil
        login.cancel(); loginTask?.cancel(); loginTask = nil
        isBusy = false; isAwaitingLogin = false
    }

    func signOut() async {
        guard !isBusy, let selectedID else { return }
        isBusy = true; errorMessage = nil
        changeSession()
        defer { isBusy = false }
        do {
            let confirmed = try await sessions.signOut(selectedID)
            refresh()
            if !confirmed {
                errorMessage = "Signed out on this Mac. Remote sign-out could not be confirmed. You can disconnect Draftly in ChatGPT Settings."
            }
        } catch { errorMessage = Self.message(for: error) }
    }

    func accessToken() async throws -> String {
        guard let selectedID, !isAwaitingLogin else { throw ChatGPTSessionService.Failure.signedOut }
        return try await sessions.accessToken(for: selectedID)
    }

    func loadModels() async {
        guard !isLoadingModels else { return }
        guard let provider, let selectedID, isSignedIn, selectedAccount?.tokens?.allowsInference == true else { models = []; return }
        let epoch = sessionEpoch, id = UUID()
        catalogID = id; isLoadingModels = true
        defer { if catalogID == id { isLoadingModels = false; catalogID = nil } }
        do {
            let token = try await sessions.accessToken(for: selectedID)
            try Task.checkCancellation()
            guard epoch == sessionEpoch else { return }
            let result = try await provider.models(token: token)
            try Task.checkCancellation()
            if epoch == sessionEpoch, catalogID == id { models = result }
        } catch is CancellationError {} catch {
            if epoch == sessionEpoch, catalogID == id { models = []; errorMessage = Self.message(for: error) }
        }
    }

    func respond(messages: [ChatConsoleMessage], model: String, tools: AgentChatToolSession? = nil, onText: @escaping @MainActor (String) -> Void) async throws -> String {
        guard let provider, models.contains(where: { $0.id == model }) else { throw ChatGPTProvider.Failure.unavailable }
        let epoch = sessionEpoch
        let token = try await accessToken()
        try Task.checkCancellation()
        guard epoch == sessionEpoch else { throw CancellationError() }
        let response = try await provider.respond(messages: messages, model: model, token: token, tools: tools, validate: { [weak self] in
            guard self?.sessionEpoch == epoch else { throw CancellationError() }
        }) { [weak self] text in
            guard self?.sessionEpoch == epoch else { throw CancellationError() }
            onText(text)
        }
        guard epoch == sessionEpoch else { throw CancellationError() }
        return response
    }

    private func changeSession() {
        sessionEpoch = UUID()
        catalogTask?.cancel(); catalogTask = nil; catalogID = nil
        isLoadingModels = false; models = []
    }

    private func scheduleModels() {
        guard provider != nil else { return }
        catalogTask?.cancel()
        catalogTask = Task { [weak self] in await self?.loadModels() }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case ChatGPTAuthorizationError.denied: "ChatGPT sign-in was cancelled or access was not granted."
        case ChatGPTCallbackListener.Failure.timedOut: "ChatGPT sign-in timed out. Please try again."
        case is ChatGPTIdentityVerifier.Failure: "The ChatGPT account could not be verified. Please sign in again."
        case ChatGPTSessionLease.Failure.busy: "The ChatGPT session is in use. Please try again."
        case let failure as ChatGPTLoginService.Failure: failure.localizedDescription
        case let failure as ChatGPTSessionService.Failure: failure.localizedDescription
        case let failure as ChatGPTProvider.Failure: failure.localizedDescription
        case let failure as URLError: failure.localizedDescription
        default: "The ChatGPT connection could not be completed. Please try again."
        }
    }
}
