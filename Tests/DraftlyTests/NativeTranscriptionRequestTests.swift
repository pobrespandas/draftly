import Foundation
@preconcurrency import Speech
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous file transcription")
@MainActor
struct NativeTranscriptionRequestTests {
    @Test func finalResultUsesTheLatestPartialTextAndPreservesLocaleAndFile() async throws {
        let driver = TranscriptionDriverFixture()
        driver.onRecognize = { update in
            update(.init(text: "café 🐼\n", isFinal: false))
            update(.init(text: nil, isFinal: true))
        }
        let result = try await NativeTranscriptionRequest.run(["locale": "es-AR"], driver: driver)
        #expect(result == "café 🐼\n")
        #expect(driver.locale == "es-AR")
        #expect(driver.recognizedFile == driver.file)
        #expect(driver.recognitionCleanups == 1)
        #expect(driver.invalidated)
    }

    @Test func deniedAndRestrictedPermissionDoNotOpenAPicker() async {
        for status in [SFSpeechRecognizerAuthorizationStatus.denied, .restricted] {
            let driver = TranscriptionDriverFixture()
            driver.authorizationStatus = status
            do { _ = try await NativeTranscriptionRequest.run([:], driver: driver); Issue.record("Denied speech access succeeded.") }
            catch { #expect(error.localizedDescription == "Speech recognition access is denied.") }
            #expect(driver.permissionRequests == 0)
            #expect(driver.pickerRequests == 0)
            #expect(driver.invalidated)
        }
    }

    @Test func authorizationGrantAllowsFileSelectionAndPickerCancelReturnsEmptyText() async throws {
        let driver = TranscriptionDriverFixture()
        driver.authorizationStatus = .notDetermined
        driver.onPermission = { completion in completion(.authorized) }
        driver.onPick = { completion in completion(nil) }
        let result = try await NativeTranscriptionRequest.run([:], driver: driver)
        #expect(result.isEmpty)
        #expect(driver.permissionRequests == 1)
        #expect(driver.pickerRequests == 1)
        #expect(driver.recognizedFile == nil)
        #expect(driver.invalidated)
    }

    @Test func authorizationTimeoutIgnoresALateGrantWithoutOpeningAPicker() async throws {
        let driver = TranscriptionDriverFixture()
        driver.authorizationStatus = .notDetermined
        var latePermission: (@Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void)?
        driver.onPermission = { latePermission = $0 }
        do { _ = try await NativeTranscriptionRequest.run([:], driver: driver, authorizationTimeout: 0.02); Issue.record("Authorization did not time out.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        latePermission?(.authorized)
        #expect(driver.pickerRequests == 0)
        #expect(driver.invalidated)
    }

    @Test func cancellationDuringAuthorizationReturnsWithoutWaitingForPermission() async throws {
        let driver = TranscriptionDriverFixture()
        driver.authorizationStatus = .notDetermined
        let task = Task { try await NativeTranscriptionRequest.run([:], driver: driver) }
        try await driver.waitFor(.authorization)
        #expect(driver.permissionRequests == 1)
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled authorization succeeded.") }
        catch { #expect(error is CancellationError) }
        #expect(driver.pickerRequests == 0)
        #expect(driver.invalidated)
    }

    @Test func pickerCancellationClosesThePickerAndIgnoresALateSelection() async throws {
        let driver = TranscriptionDriverFixture()
        var latePick: (@MainActor @Sendable (URL?) -> Void)?
        driver.onPick = { latePick = $0 }
        let task = Task { try await NativeTranscriptionRequest.run([:], driver: driver) }
        try await driver.waitFor(.picker)
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled file selection succeeded.") }
        catch { #expect(error is CancellationError) }
        latePick?(driver.file)
        #expect(driver.pickerCleanups == 1)
        #expect(driver.recognizedFile == nil)
    }

    @Test func pickerTimeoutClosesThePicker() async {
        let driver = TranscriptionDriverFixture()
        driver.onPick = { _ in }
        do { _ = try await NativeTranscriptionRequest.run([:], driver: driver, timeout: 0.02); Issue.record("File selection did not time out.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(driver.pickerCleanups == 1)
        #expect(driver.recognizedFile == nil)
    }

    @Test func recognitionCancellationStopsTheTaskAndIgnoresALateFinalResult() async throws {
        let driver = TranscriptionDriverFixture()
        var lateUpdate: (@MainActor @Sendable (NativeTranscriptionUpdate) -> Void)?
        driver.onRecognize = { lateUpdate = $0 }
        let task = Task { try await NativeTranscriptionRequest.run([:], driver: driver) }
        try await driver.waitFor(.recognition)
        #expect(driver.recognizedFile != nil)
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled recognition succeeded.") }
        catch { #expect(error is CancellationError) }
        lateUpdate?(.init(text: "Late text", isFinal: true))
        #expect(driver.recognitionCleanups == 1)
        #expect(driver.invalidated)
    }

    @Test func recognitionTimeoutCancelsTheRecognitionTask() async {
        let driver = TranscriptionDriverFixture()
        driver.onRecognize = { _ in }
        do { _ = try await NativeTranscriptionRequest.run([:], driver: driver, timeout: 0.02); Issue.record("Recognition did not time out.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(driver.recognitionCleanups == 1)
    }

    @Test(arguments: ["authorization", "picker", "recognition"], [false, true])
    func expiredPhaseCannotAdvanceBeforeQueuedTimeout(phase: String, exactDeadline: Bool) async {
        let driver = TranscriptionDriverFixture()
        var now = Date(timeIntervalSinceReferenceDate: 100)
        func expire() { now = now.addingTimeInterval(exactDeadline ? 10 : 11) }
        if phase == "authorization" {
            driver.authorizationStatus = .notDetermined
            driver.onPermission = { reply in expire(); reply(.authorized) }
        } else if phase == "picker" {
            driver.onPick = { reply in expire(); reply(driver.file) }
        } else {
            driver.onRecognize = { reply in expire(); reply(.init(text: "Expired café 🐼", isFinal: true)) }
        }
        do {
            _ = try await NativeTranscriptionRequest.run([:], driver: driver,
                authorizationTimeout: 10, timeout: 10, now: { now })
            Issue.record("Expired transcription returned success.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        if phase == "authorization" { #expect(driver.locale == nil && driver.pickerRequests == 0) }
        if phase != "recognition" { #expect(driver.recognizedFile == nil) }
        if phase != "authorization" { #expect(driver.pickerCleanups == 1) }
        #expect(driver.recognitionCleanups == (phase == "recognition" ? 1 : 0))
        #expect(driver.invalidated)
    }

    @Test func timelyAuthorizationPickerAndRecognitionKeepSeparateBudgets() async throws {
        let driver = TranscriptionDriverFixture()
        var now = Date(timeIntervalSinceReferenceDate: 100)
        driver.authorizationStatus = .notDetermined
        driver.onPermission = { reply in now = now.addingTimeInterval(9); reply(.authorized) }
        driver.onPick = { reply in now = now.addingTimeInterval(9); reply(driver.file) }
        driver.onRecognize = { reply in
            now = now.addingTimeInterval(9)
            reply(.init(text: "Timely café 🐼", isFinal: true))
        }
        let text = try await NativeTranscriptionRequest.run([:], driver: driver,
            authorizationTimeout: 10, timeout: 10, now: { now })
        #expect(text == "Timely café 🐼")
        #expect(driver.pickerCleanups == 1 && driver.recognitionCleanups == 1 && driver.invalidated)
    }

    @Test func cancellationAtDeadlineKeepsItsReasonAndClosesThePicker() async throws {
        let driver = TranscriptionDriverFixture()
        var now = Date(timeIntervalSinceReferenceDate: 100)
        driver.onPick = { _ in }
        let task = Task { try await NativeTranscriptionRequest.run([:], driver: driver, timeout: 10, now: { now }) }
        try await driver.waitFor(.picker)
        now = now.addingTimeInterval(10)
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled transcription returned text.") }
        catch { #expect(error is CancellationError) }
        #expect(driver.pickerCleanups == 1 && driver.recognizedFile == nil && driver.invalidated)
    }

    @Test func recognitionErrorTakesPriorityOverAFinalText() async {
        let driver = TranscriptionDriverFixture()
        driver.onRecognize = { update in update(.init(text: "Partial", isFinal: true, error: NSError(domain: "Draftly.SpeechFixture", code: 42, userInfo: [NSLocalizedDescriptionKey: "Neutral recognition failure"]))) }
        do { _ = try await NativeTranscriptionRequest.run([:], driver: driver); Issue.record("The recognition failure succeeded.") }
        catch { #expect(error.localizedDescription == "Neutral recognition failure") }
        #expect(driver.recognitionCleanups == 1)
    }

    @Test func unavailableRecognizerDoesNotOpenAPicker() async {
        let driver = TranscriptionDriverFixture()
        driver.configurationError = DraftlyError.message("Speech recognition is unavailable for this language.")
        do { _ = try await NativeTranscriptionRequest.run([:], driver: driver); Issue.record("The unavailable recognizer succeeded.") }
        catch { #expect(error.localizedDescription == "Speech recognition is unavailable for this language.") }
        #expect(driver.pickerRequests == 0)
    }

    @Test func invalidTimeoutDoesNotRequestPermissionOrOpenAPicker() async {
        let driver = TranscriptionDriverFixture()
        do { _ = try await NativeTranscriptionRequest.run([:], driver: driver, timeout: .nan); Issue.record("The invalid timeout succeeded.") }
        catch { #expect(error.localizedDescription == "The transcription timeouts must be positive and finite.") }
        #expect(driver.permissionRequests == 0)
        #expect(driver.pickerRequests == 0)
    }
}

@MainActor
private final class TranscriptionDriverFixture: NativeTranscriptionDriving {
    enum Stage { case authorization, picker, recognition }
    private let started = AsyncStream.makeStream(of: Stage.self)

    func waitFor(_ stage: Stage) async throws {
        for await observed in started.stream {
            if observed == stage { return }
        }
        try #require(false, "The transcription fixture did not reach the requested stage.")
    }

    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized
    var onPermission: ((@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void)?
    var onPick: ((@escaping @MainActor @Sendable (URL?) -> Void) -> Void)?
    var onRecognize: ((@escaping @MainActor @Sendable (NativeTranscriptionUpdate) -> Void) -> Void)?
    var configurationError: Error?
    let file = URL(fileURLWithPath: "/neutral-audio-fixture.m4a")
    var permissionRequests = 0
    var pickerRequests = 0
    var pickerCleanups = 0
    var recognitionCleanups = 0
    var recognizedFile: URL?
    var locale: String?
    var invalidated = false

    func requestAuthorization(_ completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) { permissionRequests += 1; started.continuation.yield(.authorization); onPermission?(completion) }
    func configure(locale: String) throws { self.locale = locale; if let configurationError { throw configurationError } }
    func selectFile(_ completion: @escaping @MainActor @Sendable (URL?) -> Void) -> (() -> Void) {
        pickerRequests += 1
        started.continuation.yield(.picker)
        if let onPick { onPick(completion) } else { completion(file) }
        return { self.pickerCleanups += 1 }
    }
    func recognize(file: URL, update: @escaping @MainActor @Sendable (NativeTranscriptionUpdate) -> Void) throws -> (() -> Void) {
        recognizedFile = file
        started.continuation.yield(.recognition)
        if let onRecognize { onRecognize(update) } else { update(.init(text: "Neutral text", isFinal: true)) }
        return { self.recognitionCleanups += 1 }
    }
    func invalidate() { started.continuation.finish(); invalidated = true; onPermission = nil; onPick = nil; onRecognize = nil }
}
