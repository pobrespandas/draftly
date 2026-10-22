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

    @Test(arguments: [false, true])
    func cancellationAfterFinalRecognitionDiscardsTextAndCannotAffectNextSession(taskCancellation: Bool) async throws {
        let driver = DictationDriverFixture()
        let task = Task { try await NativeDictationRequest.run([:], driver: driver) }
        defer { task.cancel() }
        try await driver.waitFor(.shown)
        let update = try #require(driver.onUpdate)
        let decide = try #require(driver.onDecision)
        update(.init(text: "Final café 🐼", isFinal: true))
        #expect(driver.stops == 1 && !driver.resourcesActive && driver.windowOpen)
        if taskCancellation { task.cancel() } else { decide(false) }
        do {
            let text = try await task.value
            #expect(!taskCancellation && text.isEmpty)
        } catch {
            #expect(taskCancellation && error is CancellationError)
        }
        #expect(driver.cleanups == 1 && driver.stops == 1 && !driver.windowOpen)
        let displayed = driver.displayed
        let next = DictationDriverFixture()
        next.whenShown = {
            update(.init(text: "Stale final result", isFinal: true))
            decide(true)
            next.onUpdate?(.init(text: "Fresh café 🐼", isFinal: false))
            next.onDecision?(true)
        }
        #expect(try await NativeDictationRequest.run([:], driver: next) == "Fresh café 🐼")
        #expect(driver.displayed == displayed && driver.displayAfterCleanup == 0)
        #expect(next.stops == 1 && next.cleanups == 1 && !next.windowOpen && !next.resourcesActive)
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

    @Test(arguments: ["speech", "microphone", "recording"], [false, true])
    func expiredPhaseCannotAdvanceBeforeQueuedTimeout(phase: String, exactDeadline: Bool) async {
        let driver = DictationDriverFixture()
        var now = Date(timeIntervalSinceReferenceDate: 100)
        func expire() { now = now.addingTimeInterval(exactDeadline ? 10 : 11) }
        if phase == "speech" {
            driver.speechAuthorization = .notDetermined
            driver.whenSpeechRequested = { reply in expire(); reply(.authorized) }
        } else if phase == "microphone" {
            driver.microphoneAuthorization = .notDetermined
            driver.whenMicrophoneRequested = { reply in expire(); reply(true) }
        }
        driver.whenShown = {
            if phase == "recording" { expire() }
            driver.onUpdate?(.init(text: "Expired text", isFinal: true))
            driver.onDecision?(true)
        }
        do {
            _ = try await NativeDictationRequest.run([:], driver: driver,
                authorizationTimeout: 10, timeout: 10, now: { now })
            Issue.record("Expired dictation phase returned success.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        if phase != "recording" { #expect(driver.starts == 0 && driver.shows == 0) }
        if phase == "speech" { #expect(driver.locale == nil && driver.microphoneRequests == 0) }
        #expect(driver.cleanups == 1 && !driver.resourcesActive && !driver.windowOpen)
    }

    @Test func eachTimelyPhaseReceivesItsOwnDeadline() async throws {
        let driver = DictationDriverFixture()
        var now = Date(timeIntervalSinceReferenceDate: 100)
        driver.speechAuthorization = .notDetermined
        driver.microphoneAuthorization = .notDetermined
        driver.whenSpeechRequested = { reply in now = now.addingTimeInterval(9); reply(.authorized) }
        driver.whenMicrophoneRequested = { reply in now = now.addingTimeInterval(9); reply(true) }
        driver.whenShown = {
            now = now.addingTimeInterval(9)
            driver.onUpdate?(.init(text: "Timely café 🐼", isFinal: false))
            driver.onDecision?(true)
        }
        let text = try await NativeDictationRequest.run([:], driver: driver,
            authorizationTimeout: 10, timeout: 10, now: { now })
        #expect(text == "Timely café 🐼")
        #expect(driver.starts == 1 && driver.cleanups == 1)
    }

    @Test func doneAtDeadlineCannotReturnEarlierPartialText() async {
        let driver = DictationDriverFixture()
        var now = Date(timeIntervalSinceReferenceDate: 100)
        driver.whenShown = {
            driver.onUpdate?(.init(text: "Earlier partial text", isFinal: false))
            now = now.addingTimeInterval(10)
            driver.onDecision?(true)
        }
        do {
            _ = try await NativeDictationRequest.run([:], driver: driver, timeout: 10, now: { now })
            Issue.record("Expired Done returned partial text.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        #expect(driver.cleanups == 1 && !driver.resourcesActive && !driver.windowOpen)
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

    @Test(arguments: ["speech denied", "speech restricted", "microphone denied"])
    func requestedPermissionRefusalCleansWithoutCaptureAndAllowsRecovery(refusal: String) async throws {
        let driver = DictationDriverFixture()
        if refusal == "microphone denied" {
            driver.microphoneAuthorization = .notDetermined
            driver.whenMicrophoneRequested = { $0(false) }
        } else {
            driver.speechAuthorization = .notDetermined
            driver.whenSpeechRequested = { $0(refusal == "speech denied" ? .denied : .restricted) }
        }
        do { _ = try await NativeDictationRequest.run([:], driver: driver); Issue.record("Refused permission started capture.") }
        catch {
            #expect(error.localizedDescription == (refusal == "microphone denied"
                ? "Microphone access is denied." : "Speech recognition access is denied."))
        }
        #expect(driver.starts == 0 && driver.shows == 0 && driver.cleanups == 1)
        #expect(driver.speechRequests == (refusal == "microphone denied" ? 0 : 1))
        #expect(driver.microphoneRequests == (refusal == "microphone denied" ? 1 : 0))
        #expect(!driver.resourcesActive && !driver.windowOpen && driver.onUpdate == nil && driver.onDecision == nil)
        let next = DictationDriverFixture()
        next.whenShown = { next.onUpdate?(.init(text: "Recovery café 🐼", isFinal: false)); next.onDecision?(true) }
        #expect(try await NativeDictationRequest.run([:], driver: next) == "Recovery café 🐼")
        #expect(next.stops == 1 && next.cleanups == 1 && !next.resourcesActive && !next.windowOpen)
    }

    @Test(arguments: [false, true])
    func staleAuthorizationCannotAdvanceOrFinishTheNextSession(microphone: Bool) async throws {
        let driver = DictationDriverFixture()
        driver.speechAuthorization = microphone ? .authorized : .notDetermined
        driver.microphoneAuthorization = .notDetermined
        var grant: (() -> Void)?, deny: (() -> Void)?
        driver.whenSpeechRequested = { reply in grant = { reply(.authorized) }; deny = { reply(.denied) } }
        driver.whenMicrophoneRequested = { reply in grant = { reply(true) }; deny = { reply(false) } }
        let task = Task { try await NativeDictationRequest.run([:], driver: driver) }
        defer { task.cancel() }
        try await driver.waitFor(microphone ? .microphone : .speech)
        let lateGrant = try #require(grant), lateDenial = try #require(deny)
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled authorization returned text.") }
        catch { #expect(error is CancellationError) }

        let next = DictationDriverFixture()
        next.speechAuthorization = .notDetermined
        var currentGrant: (@MainActor @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void)?
        next.whenSpeechRequested = { currentGrant = $0 }
        next.whenShown = { next.onUpdate?(.init(text: "Fresh café 🐼", isFinal: true)); next.onDecision?(true) }
        let fresh = Task { try await NativeDictationRequest.run([:], driver: next) }
        defer { fresh.cancel() }
        try await next.waitFor(.speech)
        lateGrant(); lateDenial(); lateGrant()
        #expect(driver.starts == 0 && driver.cleanups == 1)
        #expect(next.speechRequests == 1 && next.starts == 0 && next.cleanups == 0)
        let acceptCurrent = try #require(currentGrant)
        acceptCurrent(.authorized)
        #expect(try await fresh.value == "Fresh café 🐼")
        #expect(next.cleanups == 1 && next.stops == 1 && !next.resourcesActive && !next.windowOpen)
    }

    @Test func sameTurnRecordingCancellationRejectsTranscriptAndDoneBeforeCleanup() async throws {
        let driver = DictationDriverFixture()
        let task = Task { try await NativeDictationRequest.run([:], driver: driver) }
        defer { task.cancel() }
        try await driver.waitFor(.shown)
        let update = try #require(driver.onUpdate), done = try #require(driver.onDecision)
        let displayed = driver.displayed
        task.cancel()
        update(.init(text: "Must not display or insert", isFinal: true))
        done(true)
        do { _ = try await task.value; Issue.record("Cancelled capture returned a result.") }
        catch { #expect(error is CancellationError) }
        #expect(driver.displayed == displayed && driver.displayAfterCleanup == 0)
        #expect(driver.stops == 1 && driver.cleanups == 1 && !driver.resourcesActive && !driver.windowOpen)
        #expect(driver.onUpdate == nil && driver.onDecision == nil)
    }

    @Test(arguments: ["speech cancelled", "microphone cancelled", "recording cancelled", "speech denied", "microphone denied"])
    func interruptedActionRetainsWritesSkipsSuccessAndRecovers(scenario: String) async throws {
        let library = try LibraryStore(inMemory: true, seed: false), editor = EditorSession()
        let note = try library.createNote(content: "Original café 🐼")
        editor.load(note, focusEditor: false)
        let driver = DictationDriverFixture()
        driver.speechAuthorization = scenario.hasPrefix("speech") ? .notDetermined : .authorized
        driver.microphoneAuthorization = scenario.hasPrefix("microphone") ? .notDetermined : .authorized
        var grant: (() -> Void)?, deny: (() -> Void)?
        driver.whenSpeechRequested = { reply in grant = { reply(.authorized) }; deny = { reply(.denied) } }
        driver.whenMicrophoneRequested = { reply in grant = { reply(true) }; deny = { reply(false) } }
        let host = DictationActionFixtureHost(driver: driver)
        let runner = ActionRunner(library: library, editor: editor, host: host)
        runner.uiOperation = { _ in Issue.record("Unexpected synchronous editor operation."); return nil }
        var action = DraftAction(name: "Interrupted neutral dictation", steps: [
            ActionStep("script", ["script": "editor.setText('Retained café 🐼');draft.update();context.addSuccessParameter('mustDrop','yes');var text=editor.dictate();editor.setText('Must not insert '+text);draft.update();"]),
            ActionStep("script", ["script": "editor.setText('Must not run');draft.update();"])
        ])
        action.afterSuccess = "archive"
        let execution = Task { await runner.runAsync(action) }
        defer { execution.cancel() }
        try await driver.waitFor(scenario.hasPrefix("speech") ? .speech : scenario.hasPrefix("microphone") ? .microphone : .shown)
        let lateUpdate = driver.onUpdate, lateDecision = driver.onDecision
        if scenario.hasSuffix("denied") {
            let refuse = try #require(deny)
            refuse()
        } else { execution.cancel() }
        let report = await execution.value
        #expect(report.reason == (scenario.hasSuffix("denied") ? .error : .cancelled))
        #expect(report.successParameters.isEmpty && host.finishes == 1)
        #expect(driver.cleanups == 1 && driver.stops == (scenario.hasPrefix("recording") ? 1 : 0))
        #expect(!driver.resourcesActive && !driver.windowOpen)
        #expect(editor.content == "Retained café 🐼")
        #expect(library.notes.first?.content == editor.content && library.notes.first?.isArchived == false)
        #expect(library.runs.count == 1 && library.runs.first?.status == (scenario.hasSuffix("denied") ? "Error" : "Cancelled"))
        grant?(); deny?()
        lateUpdate?(.init(text: "Late transcript", isFinal: true)); lateDecision?(true)
        let recovery = DraftAction(name: "Dictation recovery", steps: [ActionStep("script", ["script": "editor.setText('Recovery café 🐼');draft.update();"])])
        #expect(await runner.runAsync(recovery).reason == .success)
        await TestMainQueue.drain()
        #expect(editor.content == "Recovery café 🐼" && library.notes.first?.content == editor.content)
        #expect(library.runs.count == 2 && host.finishes == 2 && driver.cleanups == 1)
        #expect(driver.displayAfterCleanup == 0)
    }

    @Test func alreadyCancelledTaskDoesNotTouchPermissionOrCaptureDriver() async {
        let driver = DictationDriverFixture()
        driver.speechAuthorization = .notDetermined
        let task = Task { try await NativeDictationRequest.run([:], driver: driver) }
        task.cancel()
        do { _ = try await task.value; Issue.record("A pre-cancelled request succeeded.") }
        catch { #expect(error is CancellationError) }
        #expect(driver.speechRequests == 0 && driver.microphoneRequests == 0)
        #expect(driver.starts == 0 && driver.shows == 0 && driver.cleanups == 0)
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
    var displayed: [String] = []

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
    func displayTranscript(_ text: String) { displayed.append(text); if cleanups > 0 { displayAfterCleanup += 1 } }
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
    @Test func audioTapCreatedOnMainActorAcceptsSyntheticAudioOffActor() async throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        let tap = DictationCallback.audioTap(for: request)
        let frames = try await Task.detached {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32))
            buffer.frameLength = 32
            buffer.floatChannelData?[0].initialize(repeating: 0, count: 32)
            tap(buffer, AVAudioTime(sampleTime: 0, atRate: format.sampleRate))
            return buffer.frameLength
        }.value
        request.endAudio()
        #expect(frames == 32)
    }

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

@MainActor
private final class DictationActionFixtureHost: ActionHost {
    let driver: DictationDriverFixture
    var finishes = 0
    init(driver: DictationDriverFixture) { self.driver = driver }
    func supportsAsync(_ operation: String) -> Bool { operation == "dictate" }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        throw DraftlyError.message("Unexpected synchronous operation: " + operation)
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        guard operation == "dictate" else { throw DraftlyError.message("Unexpected native operation: " + operation) }
        let text = try await NativeDictationRequest.run([:], driver: driver)
        return String(decoding: try JSONSerialization.data(withJSONObject: ["value": text]), as: UTF8.self)
    }
    func finishAction() { finishes += 1 }
}
