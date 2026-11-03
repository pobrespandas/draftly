import AppKit
import AuthenticationServices

@MainActor final class MCPBrowserAuthorization: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Failure: Error { case unavailable, busy, timedOut }
    private let anchor: NSWindow
    private var session: ASWebAuthenticationSession?
    private var waiter: CheckedContinuation<URL, Error>?
    private var attemptID: UUID?
    private var timeout: Task<Void, Never>?

    init(anchor: NSWindow) { self.anchor = anchor }

    func authenticate(url: URL, redirectURI: URL) async throws -> URL {
        guard attemptID == nil else { throw Failure.busy }
        guard let scheme = redirectURI.scheme, !["http", "https"].contains(scheme.lowercased()) else {
            throw Failure.unavailable
        }
        let id = UUID()
        attemptID = id
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
                let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { [weak self] callback, error in
                    Task { @MainActor in
                        if let callback { self?.finish(id, result: .success(callback)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self?.finish(id, result: .failure(CancellationError()))
                        } else { self?.finish(id, result: .failure(Failure.unavailable)) }
                    }
                }
                self.session = session
                session.presentationContextProvider = self
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(300)) } catch { return }
                    self?.finish(id, result: .failure(Failure.timedOut))
                }
                if !session.start() { finish(id, result: .failure(Failure.unavailable)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }

    private func finish(_ id: UUID, result: Result<URL, Error>) {
        guard attemptID == id else { return }
        attemptID = nil
        let continuation = waiter; waiter = nil
        let oldSession = session; session = nil
        timeout?.cancel(); timeout = nil
        oldSession?.cancel()
        continuation?.resume(with: result)
    }
}
