import AVFoundation
import Foundation
@preconcurrency import Speech
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous live dictation")
@MainActor
struct NativeDictationRequestTests {
    @Test func doneReturnsPartialUnicodeTextAndCleansCapture() async throws {
        let driver = DictationDriverFixture()
        driver.whenShown = {
            driver.onUpdate?(.init(text: "café 🐼\nsecond line", isFinal: false))
            driver.onDecision?(true)
        }
        let result = try await NativeDictationRequest.run(["locale": "es-AR"], driver: driver)
        #expect(result == "café 🐼\nsecond line")
        #expect(driver.locale == "es-AR")
        #expect(driver.speechRequests == 0 && driver.microphoneRequests == 0)
        #expect(driver.stops == 1 && driver.cleanups == 1)
        #expect(!driver.resourcesActive && !driver.windowOpen)
        #expect(driver.onUpdate == nil && driver.onDecision == nil)
        #expect(driver.displayAfterCleanup == 0)
    }

    @Test func userCancelReturnsEmptyTextAndDiscardsPartialRecognition() async throws {
        let driver = DictationDriverFixture()
        driver.whenShown = {
            driver.onUpdate?(.init(text: "Discard this partial", isFinal: false))
            driver.onDecision?(false)
        }
        #expect(try await NativeDictationRequest.run([:], driver: driver) == "")
        #expect(driver.stops == 1 && driver.cleanups == 1)
    }

    @Test func speechAndMicrophoneAuthorizationCompleteBeforeCaptureStarts() async throws {
        let driver = DictationDriverFixture()
        driver.speechAuthorization = .notDetermined
        driver.microphoneAuthorization = .notDetermined
        driver.whenSpeechRequested = { completion in
            #expect(driver.starts == 0 && driver.microphoneRequests == 0)
            completion(.authorized)
        }
        driver.whenMicrophoneRequested = { completion in
            #expect(driver.starts == 0 && driver.locale == "")
            completion(true)
        }
        driver.whenShown = { driver.onDecision?(true) }
        _ = try await NativeDictationRequest.run([:], driver: driver)
        #expect(driver.speechRequests == 1 && driver.microphoneRequests == 1)
        #expect(driver.starts == 1 && driver.cleanups == 1)
    }

    @Test func deniedAndRestrictedSpeechDoNotRequestMicrophoneOrStartCapture() async {
        for status in [SFSpeechRecognizerAuthorizationStatus.denied, .restricted] {
            let driver = DictationDriverFixture()
            driver.speechAuthorization = status
            do { _ = try await NativeDictationRequest.run([:], driver: driver); Issue.record("Denied speech access succeeded.") }
            catch { #expect(error.localizedDescription == "Speech recognition access is denied.") }
            #expect(driver.microphoneRequests == 0 && driver.starts == 0)
            #expect(driver.cleanups == 1)
        }
    }

    @Test func deniedAndRestrictedMicrophoneDoNotStartCapture() async {
        for status in [AVAuthorizationStatus.denied, .restricted] {
            let driver = DictationDriverFixture()
            driver.microphoneAuthorization = status
            do { _ = try await NativeDictationRequest.run([:], driver: driver); Issue.record("Denied microphone access succeeded.") }
            catch { #expect(error.localizedDescription == "Microphone access is denied.") }
            #expect(driver.microphoneRequests == 0 && driver.starts == 0)
            #expect(driver.cleanups == 1)
        }
    }

    @Test func unavailableRecognizerDoesNotRequestMicrophoneAccess() async {
        let driver = DictationDriverFixture()
        driver.microphoneAuthorization = .notDetermined
        driver.configurationError = DraftlyError.message("Speech recognition is unavailable for this language.")
        do { _ = try await NativeDictationRequest.run([:], driver: driver); Issue.record("The unavailable recognizer succeeded.") }
        catch { #expect(error.localizedDescription == "Speech recognition is unavailable for this language.") }
        #expect(driver.microphoneRequests == 0 && driver.starts == 0)
    }

    @Test func captureStartupFailureReleasesResourcesWithoutShowingAWindow() async {
        let driver = DictationDriverFixture()
        driver.startError = DraftlyError.message("No microphone is available.")
        do { _ = try await NativeDictationRequest.run([:], driver: driver); Issue.record("Capture startup unexpectedly succeeded.") }
        catch { #expect(error.localizedDescription == "No microphone is available.") }
        #expect(driver.starts == 1 && driver.shows == 0)
        #expect(driver.stops == 1 && driver.cleanups == 1)
        #expect(!driver.resourcesActive)
    }

    @Test func windowPresentationFailureStopsCaptureAndClosesTheWindow() async {
        let driver = DictationDriverFixture()
        driver.presentationError = DraftlyError.message("Neutral presentation failure")
        do { _ = try await NativeDictationRequest.run([:], driver: driver); Issue.record("Presentation unexpectedly succeeded.") }
        catch { #expect(error.localizedDescription == "Neutral presentation failure") }
        #expect(driver.stops == 1 && driver.cleanups == 1)
        #expect(!driver.resourcesActive && !driver.windowOpen)
    }

    @Test func finalRecognitionStopsAudioAndWaitsForDone() async throws {
        let driver = DictationDriverFixture()
        driver.whenShown = {
            driver.onUpdate?(.init(text: "Final text", isFinal: true))
            #expect(driver.stops == 1 && driver.windowOpen)
            driver.onUpdate?(.init(text: "Late replacement", isFinal: true))
            driver.onDecision?(true)
        }
        let result = try await NativeDictationRequest.run([:], driver: driver)
        #expect(result == "Final text")
        #expect(driver.stops == 1 && driver.cleanups == 1)
    }

    @Test func taskCancellationStopsCaptureAndIgnoresLateCallbacks() async throws {
        let driver = DictationDriverFixture()
        let task = Task { try await NativeDictationRequest.run([:], driver: driver) }
        try await driver.waitFor(.shown)
        let lateUpdate = driver.onUpdate, lateDecision = driver.onDecision
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled capture succeeded.") }
        catch { #expect(error is CancellationError) }
        lateUpdate?(.init(text: "Late text", isFinal: true))
        lateDecision?(true)
        #expect(driver.stops == 1 && driver.cleanups == 1)
        #expect(driver.displayAfterCleanup == 0)
        #expect(!driver.resourcesActive && !driver.windowOpen)
    }

    @Test func cancellationDuringMicrophoneAuthorizationRejectsALateGrant() async throws {
        let driver = DictationDriverFixture()
        driver.microphoneAuthorization = .notDetermined
        var latePermission: (@MainActor @Sendable (Bool) -> Void)?
        driver.whenMicrophoneRequested = { latePermission = $0 }
        let task = Task { try await NativeDictationRequest.run([:], driver: driver) }
        try await driver.waitFor(.microphone)
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled microphone authorization succeeded.") }
        catch { #expect(error is CancellationError) }
        latePermission?(true)
        #expect(driver.starts == 0 && driver.cleanups == 1)
    }

    @Test(arguments: [false, true])
    func cancelledAuthorizationCannotAdvanceBeforeQueuedCleanup(microphone: Bool) async throws {
        let driver = DictationDriverFixture()
        driver.speechAuthorization = microphone ? .authorized : .notDetermined
        driver.microphoneAuthorization = .notDetermined
        var speechReply: (@MainActor @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void)?
        var microphoneReply: (@MainActor @Sendable (Bool) -> Void)?
        driver.whenSpeechRequested = { speechReply = $0 }
        driver.whenMicrophoneRequested = { microphoneReply = $0 }
        let task = Task { try await NativeDictationRequest.run([:], driver: driver) }
        try await driver.waitFor(microphone ? .microphone : .speech)
        task.cancel()
        if microphone { microphoneReply?(true) }
        else { speechReply?(.authorized) }
        do { _ = try await task.value; Issue.record("Cancelled authorization succeeded.") }
        catch { #expect(error is CancellationError) }
        #expect(driver.starts == 0 && driver.shows == 0)
        #expect(driver.microphoneRequests == (microphone ? 1 : 0))
        if !microphone { #expect(driver.locale == nil) }
        #expect(driver.cleanups == 1 && !driver.resourcesActive && !driver.windowOpen)
    }

    @Test(arguments: [false, true])
    func authorizationTimeoutDoesNotStartCapture(microphone: Bool) async {
        let driver = DictationDriverFixture()
        driver.speechAuthorization = microphone ? .authorized : .notDetermined
        driver.microphoneAuthorization = .notDetermined
        do { _ = try await NativeDictationRequest.run([:], driver: driver, authorizationTimeout: 0.02); Issue.record("Authorization did not time out.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(driver.starts == 0 && driver.cleanups == 1)
    }

    @Test func recordingTimeoutReleasesAudioAndClosesTheWindow() async {
        let driver = DictationDriverFixture()
        do { _ = try await NativeDictationRequest.run([:], driver: driver, timeout: 0.02); Issue.record("Recording did not time out.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(driver.stops == 1 && driver.cleanups == 1)
        #expect(!driver.resourcesActive && !driver.windowOpen)
    }

    @Test func recognitionErrorPreservesItsReasonAndCleansCapture() async {
        let driver = DictationDriverFixture()
        driver.whenShown = { driver.onUpdate?(.init(text: "Partial", isFinal: true,
            error: NSError(domain: "Draftly.DictationFixture", code: 42, userInfo: [NSLocalizedDescriptionKey: "Neutral recognition failure"]))) }
        do { _ = try await NativeDictationRequest.run([:], driver: driver); Issue.record("Recognition failure succeeded.") }
        catch { #expect(error.localizedDescription == "Neutral recognition failure") }
        #expect(driver.stops == 1 && driver.cleanups == 1)
        #expect(!driver.resourcesActive && !driver.windowOpen)
    }

    @Test func invalidTimeoutDoesNotRequestPermissionOrStartCapture() async {
        let driver = DictationDriverFixture()
        do { _ = try await NativeDictationRequest.run([:], driver: driver, timeout: 0); Issue.record("The invalid timeout succeeded.") }
        catch { #expect(error.localizedDescription == "The dictation timeouts must be positive and finite.") }
        #expect(driver.speechRequests == 0 && driver.microphoneRequests == 0 && driver.starts == 0)
    }
}

@MainActor
private final class DictationDriverFixture: NativeDictationDriving {
    enum Stage { case speech, microphone, shown }
    private let started = AsyncStream.makeStream(of: Stage.self)
    var speechAuthorization: SFSpeechRecognizerAuthorizationStatus = .authorized
    var microphoneAuthorization: AVAuthorizationStatus = .authorized
    var onUpdate: (@MainActor @Sendable (NativeTranscriptionUpdate) -> Void)?
    var onDecision: ((Bool) -> Void)?
    var whenSpeechRequested: ((@escaping @MainActor @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void)?
    var whenMicrophoneRequested: ((@escaping @MainActor @Sendable (Bool) -> Void) -> Void)?
    var whenShown: (() -> Void)?
    var configurationError: Error?
    var startError: Error?
    var presentationError: Error?
    var locale: String?
    var speechRequests = 0, microphoneRequests = 0, starts = 0, shows = 0, stops = 0, cleanups = 0
    var resourcesActive = false, windowOpen = false
    var displayAfterCleanup = 0

    func waitFor(_ stage: Stage) async throws {
        for await current in started.stream { if current == stage { return } }
        try #require(false, "The dictation fixture did not reach the requested stage.")
    }
    func requestSpeechAuthorization(_ completion: @escaping @MainActor @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        speechRequests += 1; started.continuation.yield(.speech); whenSpeechRequested?(completion)
    }
    func requestMicrophoneAuthorization(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        microphoneRequests += 1; started.continuation.yield(.microphone); whenMicrophoneRequested?(completion)
    }
    func configure(locale: String) throws { self.locale = locale; if let configurationError { throw configurationError } }
    func startRecording() throws { starts += 1; resourcesActive = true; if let startError { throw startError } }
    func showRecorder() throws {
        shows += 1; windowOpen = true
        if let presentationError { throw presentationError }
        started.continuation.yield(.shown)
        whenShown?()
    }
    func displayTranscript(_ text: String) { if cleanups > 0 { displayAfterCleanup += 1 } }
    func stopRecording() { if resourcesActive { resourcesActive = false; stops += 1 } }
    func cleanup() {
        cleanups += 1; stopRecording(); windowOpen = false
        onUpdate = nil; onDecision = nil
        whenSpeechRequested = nil; whenMicrophoneRequested = nil; whenShown = nil
        started.continuation.finish()
    }
}

@Suite("Async dictation host injection") @MainActor
struct NativeDictationHostTests {
    @Test func injectedHandlerPreservesLocaleAndAvoidsSystemCapture() async throws {
        let host = NativeActionHost()
        var locale: String?
        host.dictationHandler = { values in locale = values["locale"] as? String; return "café 🐼" }
        let response = try await host.performAsync("dictate", payload: #"{"locale":"es-AR"}"#)
        let envelope = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any]
        #expect(envelope?["value"] as? String == "café 🐼" && locale == "es-AR")
    }
}

@Suite("Dictation callback isolation") @MainActor
struct DictationCallbackTests {
    @Test func backgroundPermissionRepliesReachMainActor() async {
        for allowed in [true, false] {
            let received = await withCheckedContinuation { continuation in
                let reply = DictationCallback.onMainActor { (value: Bool) in
                    MainActor.assertIsolated()
                    continuation.resume(returning: value)
                }
                Task.detached { reply(allowed) }
            }
            #expect(received == allowed)
        }
    }
}
