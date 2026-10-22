import AppKit
import AVFoundation
@preconcurrency import Speech
import DraftlyCore

enum DictationCallback {
    static func onMainActor<Value: Sendable>(
        _ completion: @escaping @MainActor @Sendable (Value) -> Void
    ) -> @Sendable (Value) -> Void {
        { value in Task { @MainActor in completion(value) } }
    }
}

@MainActor
protocol NativeDictationDriving: AnyObject {
    var speechAuthorization: SFSpeechRecognizerAuthorizationStatus { get }
    var microphoneAuthorization: AVAuthorizationStatus { get }
    var onUpdate: (@MainActor @Sendable (NativeTranscriptionUpdate) -> Void)? { get set }
    var onDecision: ((Bool) -> Void)? { get set }
    func requestSpeechAuthorization(_ completion: @escaping @MainActor @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void)
    func requestMicrophoneAuthorization(_ completion: @escaping @MainActor @Sendable (Bool) -> Void)
    func configure(locale: String) throws
    func startRecording() throws
    func showRecorder() throws
    func displayTranscript(_ text: String)
    func stopRecording()
    func cleanup()
}

@MainActor
enum NativeDictationRequest {
    static func run(_ values: [String: Any], driver: (any NativeDictationDriving)? = nil,
                    authorizationTimeout: TimeInterval = 60,
                    timeout: TimeInterval = 120,
                    now: @escaping @MainActor () -> Date = Date.init) async throws -> String {
        guard authorizationTimeout.isFinite, authorizationTimeout > 0, timeout.isFinite, timeout > 0 else {
            throw DraftlyError.message("The dictation timeouts must be positive and finite.")
        }
        try Task.checkCancellation()
        let request = DictationSession(driver: driver ?? SystemDictationDriver(), locale: values["locale"] as? String ?? "",
                                       authorizationTimeout: authorizationTimeout, recordingTimeout: timeout, now: now)
        let text = try await request.run()
        try Task.checkCancellation()
        return text
    }
}

@MainActor
private final class DictationSession {
    private enum Phase { case speech, microphone, recording }
    private final class CancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }
    private let cancellation = CancellationState()
    private let driver: any NativeDictationDriving
    private let locale: String
    private let authorizationTimeout: TimeInterval
    private let recordingTimeout: TimeInterval
    private let now: @MainActor () -> Date
    private var deadline = Date.distantFuture
    private var phase = Phase.speech
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var speechRequested = false
    private var microphoneRequested = false
    private var recognitionFinished = false
    private var text = ""

    init(driver: any NativeDictationDriving, locale: String, authorizationTimeout: TimeInterval, recordingTimeout: TimeInterval,
         now: @escaping @MainActor () -> Date) {
        self.driver = driver; self.locale = locale
        self.authorizationTimeout = authorizationTimeout; self.recordingTimeout = recordingTimeout
        self.now = now
    }

    func run() async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError())); return }
                driver.onUpdate = { [weak self] update in self?.received(update) }
                driver.onDecision = { [weak self] accepted in
                    guard let self, self.phase == .recording else { return }
                    self.finish(.success(accepted ? self.text : ""))
                }
                armTimeout(authorizationTimeout)
                speechChanged(driver.speechAuthorization)
            }
        } onCancel: { [cancellation] in
            cancellation.cancel()
            Task { @MainActor [self] in finish(.failure(CancellationError())) }
        }
    }

    private func speechChanged(_ status: SFSpeechRecognizerAuthorizationStatus) {
        guard continuation != nil, phase == .speech, canContinue() else { return }
        switch status {
        case .notDetermined:
            guard !speechRequested else { return }
            speechRequested = true
            driver.requestSpeechAuthorization { [weak self] status in self?.speechChanged(status) }
        case .authorized:
            do { try driver.configure(locale: locale) }
            catch { finish(.failure(error)); return }
            phase = .microphone
            armTimeout(authorizationTimeout)
            microphoneChanged(driver.microphoneAuthorization)
        case .denied, .restricted:
            finish(.failure(DraftlyError.message("Speech recognition access is denied.")))
        @unknown default:
            finish(.failure(DraftlyError.message("Speech recognition authorization is unavailable.")))
        }
    }

    private func microphoneChanged(_ status: AVAuthorizationStatus) {
        guard continuation != nil, phase == .microphone, canContinue() else { return }
        switch status {
        case .notDetermined:
            guard !microphoneRequested else { return }
            microphoneRequested = true
            driver.requestMicrophoneAuthorization { [weak self] allowed in
                guard let self, self.continuation != nil, self.phase == .microphone else { return }
                if allowed { self.beginRecording() }
                else { self.finish(.failure(DraftlyError.message("Microphone access is denied."))) }
            }
        case .authorized: beginRecording()
        case .denied, .restricted:
            finish(.failure(DraftlyError.message("Microphone access is denied.")))
        @unknown default:
            finish(.failure(DraftlyError.message("Microphone authorization is unavailable.")))
        }
    }

    private func beginRecording() {
        guard continuation != nil, phase == .microphone, canContinue() else { return }
        phase = .recording
        armTimeout(recordingTimeout)
        do {
            try driver.startRecording()
            guard continuation != nil, canContinue() else { return }
            try driver.showRecorder()
            guard continuation != nil, canContinue() else { return }
            driver.displayTranscript(text)
        } catch { finish(.failure(error)) }
    }

    private func received(_ update: NativeTranscriptionUpdate) {
        guard continuation != nil, phase == .recording, !recognitionFinished, canContinue() else { return }
        if let value = update.text { text = value; driver.displayTranscript(value) }
        if let error = update.error { finish(.failure(error)); return }
        if update.isFinal {
            recognitionFinished = true
            driver.stopRecording()
        }
    }

    private func canContinue() -> Bool {
        guard !cancellation.isCancelled else {
            finish(.failure(CancellationError()))
            return false
        }
        guard now() < deadline else {
            finish(.failure(ActionExecutionInterruption.timeout))
            return false
        }
        return true
    }

    private func armTimeout(_ seconds: TimeInterval) {
        deadline = now().addingTimeInterval(seconds)
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            finish(.failure(ActionExecutionInterruption.timeout))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        driver.onUpdate = nil; driver.onDecision = nil
        driver.cleanup()
        if cancellation.isCancelled { continuation.resume(throwing: CancellationError()) }
        else if now() >= deadline { continuation.resume(throwing: ActionExecutionInterruption.timeout) }
        else { continuation.resume(with: result) }
    }
}

@MainActor
private final class SystemDictationDriver: NSObject, NativeDictationDriving, NSWindowDelegate {
    var onUpdate: (@MainActor @Sendable (NativeTranscriptionUpdate) -> Void)?
    var onDecision: ((Bool) -> Void)?
    private var recognizer: SFSpeechRecognizer?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var panel: NSPanel?
    private var transcript: NSTextField?
    var speechAuthorization: SFSpeechRecognizerAuthorizationStatus { SFSpeechRecognizer.authorizationStatus() }
    var microphoneAuthorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    func requestSpeechAuthorization(_ completion: @escaping @MainActor @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization(DictationCallback.onMainActor(completion))
    }
    func requestMicrophoneAuthorization(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: DictationCallback.onMainActor(completion))
    }
    func configure(locale: String) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale.isEmpty ? .current : Locale(identifier: locale)), recognizer.isAvailable else {
            throw DraftlyError.message("Speech recognition is unavailable for this language.")
        }
        self.recognizer = recognizer
    }
    func startRecording() throws {
        guard let recognizer else { throw DraftlyError.message("Speech recognition is unavailable for this language.") }
        let engine = AVAudioEngine()
        self.engine = engine
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        let input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw DraftlyError.message("No microphone is available.") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true
        recognitionTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let update = NativeTranscriptionUpdate(text: result?.bestTranscription.formattedString,
                                                   isFinal: result?.isFinal == true, error: error)
            Task { @MainActor in self?.onUpdate?(update) }
        }
        engine.prepare()
        try engine.start()
    }
    func showRecorder() throws {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "Dictation"; panel.delegate = self
        self.panel = panel
        guard let root = panel.contentView else { throw DraftlyError.message("The dictation window is unavailable.") }
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        let label = NSTextField(wrappingLabelWithString: "Speak, then choose Done.")
        let transcript = NSTextField(wrappingLabelWithString: "Listening…")
        transcript.maximumNumberOfLines = 6
        self.transcript = transcript
        let buttons = NSStackView()
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelRecording))
        cancel.keyEquivalent = "\u{1b}"
        let done = NSButton(title: "Done", target: self, action: #selector(acceptRecording))
        done.keyEquivalent = "\r"
        buttons.addArrangedSubview(cancel); buttons.addArrangedSubview(done)
        stack.addArrangedSubview(label); stack.addArrangedSubview(transcript); stack.addArrangedSubview(buttons)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20)
        ])
        panel.center(); panel.makeKeyAndOrderFront(nil)
    }
    func displayTranscript(_ text: String) { transcript?.stringValue = text.isEmpty ? "Listening…" : text }
    func stopRecording() {
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio()
        recognitionTask?.cancel(); recognitionTask = nil
        request = nil; engine = nil
    }
    func cleanup() {
        onUpdate = nil; onDecision = nil
        stopRecording()
        panel?.delegate = nil; panel?.close(); panel = nil; transcript = nil; recognizer = nil
    }
    @objc private func acceptRecording() { onDecision?(true) }
    @objc private func cancelRecording() { onDecision?(false) }
    func windowWillClose(_ notification: Notification) { onDecision?(false) }
}
