import Combine
import Foundation

@MainActor final class ChatGPTAccountModel: ObservableObject {
    static let shared = ChatGPTAccountModel()
    @Published private(set) var accounts: [ChatGPTAccountRecord] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var isBusy = false
    @Published private(set) var isAwaitingLogin = false
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let login: ChatGPTLoginService
    private let sessions: ChatGPTSessionService
    private var loginTask: Task<Void, Never>?
    private var requestID: UUID?

    init(defaults: UserDefaults = .standard, login: ChatGPTLoginService? = nil, sessions: ChatGPTSessionService? = nil) {
        self.defaults = defaults
        let login = login ?? ChatGPTLoginService(defaults: defaults)
        self.login = login
        self.sessions = sessions ?? ChatGPTSessionService(login: login)
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
        selectedID = id
        defaults.set(id?.uuidString, forKey: "chatGPT.selectedID")
        errorMessage = nil
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
                selectedID = record.id
                defaults.set(record.id.uuidString, forKey: "chatGPT.selectedID")
                refresh()
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

    private static func message(for error: any Error) -> String {
        switch error {
        case ChatGPTAuthorizationError.denied: "ChatGPT sign-in was cancelled or access was not granted."
        case ChatGPTCallbackListener.Failure.timedOut: "ChatGPT sign-in timed out. Please try again."
        case is ChatGPTIdentityVerifier.Failure: "The ChatGPT account could not be verified. Please sign in again."
        case ChatGPTSessionLease.Failure.busy: "The ChatGPT session is in use. Please try again."
        case let failure as ChatGPTLoginService.Failure: failure.localizedDescription
        case let failure as ChatGPTSessionService.Failure: failure.localizedDescription
        case let failure as URLError: failure.localizedDescription
        default: "The ChatGPT connection could not be completed. Please try again."
        }
    }
}
