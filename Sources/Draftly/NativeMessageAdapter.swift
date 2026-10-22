import AppKit
import DraftlyCore

@MainActor
struct NativeMessageAdapter {
    static let unconfirmedMailDelivery = "The macOS Mail sharing service cannot confirm that a message was sent. Mail.send() is unavailable through this service."

    func compose(_ operation: String, _ values: [String: Any],
                 makeService: (NSSharingService.Name) -> NSSharingService? = { NSSharingService(named: $0) }) throws -> [String: String] {
        guard values["isBodyHTML"] as? Bool != true else { throw DraftlyError.message("HTML mail composition is unavailable on macOS.") }
        guard operation != "composeMail" else { throw DraftlyError.message(Self.unconfirmedMailDelivery) }
        guard let service = makeService(operation == "composeMail" ? .composeEmail : .composeMessage) else { throw DraftlyError.message("The system composition service is unavailable.") }
        service.recipients = values["toRecipients"] as? [String] ?? []; service.subject = values["subject"] as? String ?? ""
        if !(values["ccRecipients"] as? [String] ?? []).isEmpty || !(values["bccRecipients"] as? [String] ?? []).isEmpty { throw DraftlyError.message("The macOS composition service does not accept CC or BCC recipients. Use a mailto URL.") }
        let result = ScriptSharingResult(); service.delegate = result
        service.perform(withItems: [values["body"] as? String ?? ""])
        let deadline = Date().addingTimeInterval(120)
        while result.status == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        return ["status": result.status ?? "timeout"]
    }
}

@MainActor private final class ScriptSharingResult: NSObject, NSSharingServiceDelegate {
    var status: String?
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { status = "sent" }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) { status = "error" }
}

@MainActor protocol NativeMessageDriver: AnyObject {
    var recipients: [String] { get set }
    var subject: String { get set }
    var onFinish: ((Result<Void, Error>) -> Void)? { get set }
    func canPerform(_ body: String) -> Bool
    func perform(_ body: String)
    func detach()
}

@MainActor final class SharingMessageDriver: NSObject, NativeMessageDriver, NSSharingServiceDelegate {
    private let service: NSSharingService
    var onFinish: ((Result<Void, Error>) -> Void)?
    var recipients: [String] { get { service.recipients ?? [] } set { service.recipients = newValue } }
    var subject: String { get { service.subject ?? "" } set { service.subject = newValue } }
    init(operation: String, makeService: (NSSharingService.Name) -> NSSharingService? = { NSSharingService(named: $0) }) throws {
        guard operation != "composeMail" else { throw DraftlyError.message(NativeMessageAdapter.unconfirmedMailDelivery) }
        guard let service = makeService(operation == "composeMail" ? .composeEmail : .composeMessage) else {
            throw DraftlyError.message("The system composition service is unavailable.")
        }
        self.service = service
        super.init()
        service.delegate = self
    }
    func canPerform(_ body: String) -> Bool { service.canPerform(withItems: [body]) }
    func perform(_ body: String) { service.perform(withItems: [body]) }
    func detach() { service.delegate = nil; onFinish = nil }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { onFinish?(.success(())) }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { onFinish?(.failure(error)) }
}

@MainActor extension NativeMessageAdapter {
    func composeAsync(_ operation: String, _ values: [String: Any], timeout: TimeInterval = 120,
                      makeDriver: @MainActor (String) throws -> any NativeMessageDriver = { try SharingMessageDriver(operation: $0) }) async throws -> [String: String] {
        try Task.checkCancellation()
        guard ["composeMail", "composeMessage"].contains(operation) else { throw DraftlyError.message("The composition operation is unavailable.") }
        guard values["isBodyHTML"] as? Bool != true else { throw DraftlyError.message("HTML mail composition is unavailable on macOS.") }
        guard values["sendInBackground"] as? Bool != true else { throw DraftlyError.message("Background message sending is unavailable in the macOS composition service.") }
        guard (values["replyToRecipients"] as? [String] ?? []).isEmpty else { throw DraftlyError.message("Reply-To recipients are unavailable in the macOS composition service.") }
        guard (values["ccRecipients"] as? [String] ?? []).isEmpty, (values["bccRecipients"] as? [String] ?? []).isEmpty else {
            throw DraftlyError.message("The macOS composition service does not accept CC or BCC recipients. Use a mailto URL.")
        }
        guard timeout.isFinite, timeout > 0 else { throw DraftlyError.message("The composition timeout must be positive and finite.") }
        let driver = try makeDriver(operation)
        driver.recipients = values["toRecipients"] as? [String] ?? []
        driver.subject = values["subject"] as? String ?? ""
        let body = values["body"] as? String ?? ""
        guard driver.canPerform(body) else { driver.detach(); throw DraftlyError.message("The system composition service cannot handle this message.") }
        let status = try await MessageCompositionWait(driver: driver).run(body, timeout: timeout)
        try Task.checkCancellation()
        return ["status": status]
    }
}

@MainActor private final class MessageCompositionWait {
    let driver: any NativeMessageDriver
    var continuation: CheckedContinuation<String, Error>?
    var timer: Task<Void, Never>?
    init(driver: any NativeMessageDriver) { self.driver = driver }
    func run(_ body: String, timeout: TimeInterval) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError())); return }
                driver.onFinish = { [weak self] result in
                    switch result {
                    case .success: self?.finish(.success("sent"))
                    case .failure(let error):
                        let native = error as NSError
                        if native.domain == NSCocoaErrorDomain, native.code == NSUserCancelledError { self?.finish(.success("userCancelled")) }
                        else { self?.finish(.failure(error)) }
                    }
                }
                timer = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    finish(.failure(ActionExecutionInterruption.timeout))
                }
                driver.perform(body)
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }
    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel(); timer = nil
        // NSSharingService cannot close or recall an external composition window.
        driver.detach()
        continuation.resume(with: result)
    }
}
