import AppKit
import DraftlyCore

@MainActor protocol NativeSpeechDriver: AnyObject {
    var rate: Float { get set }
    var onFinish: ((Bool) -> Void)? { get set }
    func start(_ text: String) -> Bool
    func stop()
}

@MainActor final class SystemSpeechDriver: NSObject, NativeSpeechDriver, NSSpeechSynthesizerDelegate {
    private let synthesizer: NSSpeechSynthesizer
    var onFinish: ((Bool) -> Void)?
    var rate: Float { get { synthesizer.rate } set { synthesizer.rate = newValue } }
    init(voice: String?) throws {
        guard let synthesizer = NSSpeechSynthesizer(voice: voice.map(NSSpeechSynthesizer.VoiceName.init(rawValue:))) else {
            throw DraftlyError.message("The selected voice is unavailable.")
        }
        self.synthesizer = synthesizer
        super.init()
        synthesizer.delegate = self
    }
    func start(_ text: String) -> Bool { synthesizer.startSpeaking(text) }
    func stop() { synthesizer.stopSpeaking() }
    nonisolated func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        Task { @MainActor [weak self] in self?.onFinish?(finishedSpeaking) }
    }
}

@MainActor enum NativeSpeechRequest {
    enum Notice: Equatable { case confirm(String), complete }

    static func run(_ values: [String: Any],
                    makeDriver: @MainActor (String?) throws -> any NativeSpeechDriver = { try SystemSpeechDriver(voice: $0) },
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
    private var stopped = false
    init(driver: any NativeSpeechDriver) { self.driver = driver }
    func run(_ text: String) async throws -> Bool {
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError()), stop: true); return }
                driver.onFinish = { [weak self] success in self?.finish(.success(success)) }
                if !driver.start(text) { finish(.success(false)) }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError()), stop: true) }
        }
        do { try Task.checkCancellation() }
        catch { stopPlayback(); throw error }
        return result
    }
    private func stopPlayback() {
        guard !stopped else { return }
        stopped = true
        driver.stop()
    }
    private func finish(_ result: Result<Bool, Error>, stop: Bool = false) {
        guard let continuation else { return }
        self.continuation = nil
        driver.onFinish = nil
        if stop { stopPlayback() }
        continuation.resume(with: result)
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
