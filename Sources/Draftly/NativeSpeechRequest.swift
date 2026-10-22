import AppKit
import DraftlyCore

@MainActor protocol NativeSpeechDriver: AnyObject {
    var rate: Float { get set }
    var onFinish: ((Result<Bool, Error>) -> Void)? { get set }
    func start(_ text: String) -> Bool
    func stop() async
}

@MainActor final class SystemSpeechDriver: NativeSpeechDriver {
    private let voice: String?
    private let executable: URL?
    private let timeout: TimeInterval
    private let temporaryDirectory: URL
    private var playback: Task<Void, Never>?
    var onFinish: ((Result<Bool, Error>) -> Void)?
    var rate: Float = 180
    init(voice: String?, executable: URL? = Bundle.main.executableURL, timeout: TimeInterval = 120,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.voice = voice; self.executable = executable
        self.timeout = timeout; self.temporaryDirectory = temporaryDirectory
    }
    func start(_ text: String) -> Bool {
        guard playback == nil else { return false }
        let voice = voice, rate = rate, executable = executable, timeout = timeout, temporaryDirectory = temporaryDirectory
        playback = Task { [weak self] in
            let result: Result<Bool, Error>
            do { result = .success(try await NativeSpeechProcess.run(text: text, voice: voice, rate: rate, executable: executable, timeout: timeout, temporaryDirectory: temporaryDirectory)) }
            catch { result = .failure(error) }
            self?.onFinish?(result)
        }
        return true
    }
    func stop() async {
        playback?.cancel()
        await playback?.value
    }
}

@MainActor enum NativeSpeechRequest {
    enum Notice: Equatable { case confirm(String), complete }

    static func run(_ values: [String: Any],
                    makeDriver: @MainActor (String?) throws -> any NativeSpeechDriver = { SystemSpeechDriver(voice: $0) },
                    present: @MainActor (Notice) async throws -> Bool = { try await SpeechNoticePresenter.show($0) }) async throws -> Bool {
        try Task.checkCancellation()
        let settings = values["settings"] as? [String: Any] ?? [:]
        let text = values["text"] as? String ?? ""
        if settings["autoStart"] as? Bool == false {
            let accepted = try await present(.confirm(text))
            try Task.checkCancellation()
            guard accepted else { return false }
        }
        try Task.checkCancellation()
        let driver = try makeDriver((settings["voice"] as? [String: Any])?["id"] as? String)
        driver.rate = settings["rate"] as? String == "slow" ? 130 : settings["rate"] as? String == "fast" ? 240 : 180
        guard try await SpeechPlayback(driver: driver).run(text) else { return false }
        if settings["autoClose"] as? Bool == false {
            let accepted = try await present(.complete)
            try Task.checkCancellation()
            return accepted
        }
        return true
    }
}

@MainActor private final class SpeechPlayback {
    let driver: any NativeSpeechDriver
    var continuation: CheckedContinuation<Bool, Error>?
    private var stopTask: Task<Void, Never>?
    init(driver: any NativeSpeechDriver) { self.driver = driver }
    func run(_ text: String) async throws -> Bool {
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError()), stop: true); return }
                driver.onFinish = { [weak self] result in self?.finish(result) }
                if !driver.start(text) { finish(.success(false)) }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError()), stop: true) }
        }
        do { try Task.checkCancellation() }
        catch { await stopPlayback(); throw error }
        return result
    }
    private func stopPlayback() async {
        if stopTask == nil { stopTask = Task { await driver.stop() } }
        await stopTask?.value
    }
    private func finish(_ result: Result<Bool, Error>, stop: Bool = false) {
        guard let continuation else { return }
        self.continuation = nil
        driver.onFinish = nil
        if stop {
            Task { await stopPlayback(); continuation.resume(with: result) }
        } else { continuation.resume(with: result) }
    }
}

@MainActor private final class SpeechNoticePresenter: NSObject, NSWindowDelegate {
    let notice: NativeSpeechRequest.Notice
    var panel: NSPanel?
    var continuation: CheckedContinuation<Bool, Error>?
    init(_ notice: NativeSpeechRequest.Notice) { self.notice = notice }
    static func show(_ notice: NativeSpeechRequest.Notice) async throws -> Bool {
        try await SpeechNoticePresenter(notice).show()
    }
    private func show() async throws -> Bool {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError())); return }
                let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 210), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                self.panel = panel; panel.isReleasedWhenClosed = false; panel.delegate = self
                let heading = NSTextField(labelWithString: notice == .complete ? "Reading complete" : "Read text aloud")
                heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
                let buttons = NSStackView(); buttons.orientation = .horizontal
                let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
                stack.addArrangedSubview(heading)
                if case .confirm(let text) = notice {
                    let body = NSTextField(wrappingLabelWithString: text); body.maximumNumberOfLines = 6
                    stack.addArrangedSubview(body)
                    let cancel = NSButton(title: "Cancel", target: self, action: #selector(Self.cancel)); cancel.keyEquivalent = "\u{1b}"
                    buttons.addArrangedSubview(cancel)
                }
                let accept = NSButton(title: notice == .complete ? "OK" : "Read", target: self, action: #selector(Self.accept)); accept.keyEquivalent = "\r"
                buttons.addArrangedSubview(accept); stack.addArrangedSubview(buttons)
                guard let root = panel.contentView else { finish(.success(false)); return }
                stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
                NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24), stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)])
                panel.center(); panel.makeKeyAndOrderFront(nil)
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }
    @objc private func accept() { finish(.success(true)) }
    @objc private func cancel() { finish(.success(false)) }
    func windowWillClose(_ notification: Notification) { finish(.success(false)) }
    private func finish(_ result: Result<Bool, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        panel?.delegate = nil; panel?.close(); panel = nil
        continuation.resume(with: result)
    }
}
