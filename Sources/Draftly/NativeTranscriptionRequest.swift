import AppKit
@preconcurrency import Speech
import DraftlyCore

struct NativeTranscriptionUpdate: Sendable {
    var text: String?
    var isFinal: Bool
    var error: Error? = nil
}

@MainActor
protocol NativeTranscriptionDriving: AnyObject {
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus { get }
    func requestAuthorization(_ completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void)
    func configure(locale: String) throws
    func selectFile(_ completion: @escaping @MainActor @Sendable (URL?) -> Void) -> (() -> Void)
    func recognize(file: URL, update: @escaping @MainActor @Sendable (NativeTranscriptionUpdate) -> Void) throws -> (() -> Void)
    func invalidate()
}

@MainActor
enum NativeTranscriptionRequest {
    static func run(_ values: [String: Any],
                    driver: (any NativeTranscriptionDriving)? = nil,
                    authorizationTimeout: TimeInterval = 60,
                    timeout: TimeInterval = 120,
                    now: @escaping @MainActor () -> Date = Date.init) async throws -> String {
        guard authorizationTimeout.isFinite, authorizationTimeout > 0, timeout.isFinite, timeout > 0 else {
            throw DraftlyError.message("The transcription timeouts must be positive and finite.")
        }
        try Task.checkCancellation()
        let driver = driver ?? SystemTranscriptionDriver()
        defer { driver.invalidate() }
        var authorization = driver.authorizationStatus
        if authorization == .notDetermined {
            authorization = try await TranscriptionPhase.wait(timeout: authorizationTimeout, now: now) { completion in
                driver.requestAuthorization { completion(.success($0)) }
                return nil
            }
        }
        try Task.checkCancellation()
        guard authorization == .authorized else { throw DraftlyError.message("Speech recognition access is denied.") }
        try driver.configure(locale: values["locale"] as? String ?? "")
        let file: URL? = try await TranscriptionPhase.wait(timeout: timeout, now: now) { completion in
            driver.selectFile { completion(.success($0)) }
        }
        try Task.checkCancellation()
        guard let file else { return "" }
        let accumulator = TranscriptionAccumulator()
        let result: String = try await TranscriptionPhase.wait(timeout: timeout, now: now) { completion in
            try driver.recognize(file: file) { update in
                if let text = update.text { accumulator.text = text }
                if let error = update.error { completion(.failure(error)) }
                else if update.isFinal { completion(.success(accumulator.text)) }
            }
        }
        try Task.checkCancellation()
        return result
    }
}

@MainActor
private final class TranscriptionAccumulator { var text = "" }

@MainActor
private final class TranscriptionPhase<Value: Sendable> {
    private final class CancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }
    private let cancellation = CancellationState()
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var cleanup: (() -> Void)?
    private let now: @MainActor () -> Date
    private let deadline: Date

    private init(timeout: TimeInterval, now: @escaping @MainActor () -> Date) {
        self.now = now; self.deadline = now().addingTimeInterval(timeout)
    }

    static func wait(timeout: TimeInterval, now: @escaping @MainActor () -> Date,
                     start: (@escaping @Sendable (Result<Value, Error>) -> Void) throws -> (() -> Void)?) async throws -> Value {
        let pending = TranscriptionPhase(timeout: timeout, now: now)
        let cancellation = pending.cancellation
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.continuation = continuation
                guard !Task.isCancelled else { pending.finish(.failure(CancellationError())); return }
                do {
                    pending.cleanup = try start { result in
                        Task { @MainActor in pending.finish(result) }
                    }
                    pending.timeoutTask = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(max(0, pending.deadline.timeIntervalSince(pending.now())))) } catch { return }
                        pending.finish(.failure(ActionExecutionInterruption.timeout))
                    }
                } catch { pending.finish(.failure(error)) }
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor in pending.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<Value, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        let cleanup = cleanup
        self.cleanup = nil
        cleanup?()
        if cancellation.isCancelled { continuation.resume(throwing: CancellationError()) }
        else if case .failure(let error) = result, error is CancellationError { continuation.resume(throwing: error) }
        else if now() >= deadline { continuation.resume(throwing: ActionExecutionInterruption.timeout) }
        else { continuation.resume(with: result) }
    }
}

@MainActor
private final class SystemTranscriptionDriver: NativeTranscriptionDriving {
    private var recognizer: SFSpeechRecognizer?
    private var panel: NSOpenPanel?
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus { SFSpeechRecognizer.authorizationStatus() }

    func requestAuthorization(_ completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }
    func configure(locale: String) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale.isEmpty ? .current : Locale(identifier: locale)),
              recognizer.isAvailable else {
            throw DraftlyError.message("Speech recognition is unavailable for this language.")
        }
        self.recognizer = recognizer
    }
    func selectFile(_ completion: @escaping @MainActor @Sendable (URL?) -> Void) -> (() -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        self.panel = panel
        panel.begin { response in
            Task { @MainActor [weak self] in
                let file = response == .OK ? panel.url : nil
                self?.panel = nil
                completion(file)
            }
        }
        return { panel.cancel(nil) }
    }
    func recognize(file: URL, update: @escaping @MainActor @Sendable (NativeTranscriptionUpdate) -> Void) throws -> (() -> Void) {
        guard let recognizer else { throw DraftlyError.message("Speech recognition is unavailable for this language.") }
        let task = recognizer.recognitionTask(with: SFSpeechURLRecognitionRequest(url: file)) { response, error in
            let value = NativeTranscriptionUpdate(text: response?.bestTranscription.formattedString,
                                                  isFinal: response?.isFinal == true, error: error)
            Task { @MainActor in update(value) }
        }
        return { task.cancel() }
    }
    func invalidate() {
        panel?.cancel(nil); panel = nil
        recognizer = nil
    }
}
