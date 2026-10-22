import Foundation
import Testing
@testable import Draftly

@Suite("Asynchronous speech requests") @MainActor
struct NativeSpeechRequestTests {
    @MainActor private final class Driver: NativeSpeechDriver {
        let startSignal = AsyncStream.makeStream(of: Bool.self)
        var rate: Float = 0
        var onFinish: ((Bool) -> Void)?
        var text: String?
        var started = false
        var stopped = false
        var canStart = true
        var finishImmediately: Bool? = true
        var late: ((Bool) -> Void)?
        func start(_ text: String) -> Bool {
            self.text = text; started = true; late = onFinish
            startSignal.continuation.yield(true); startSignal.continuation.finish()
            if let finishImmediately { onFinish?(finishImmediately) }
            return canStart
        }
        func stop() { stopped = true }
    }

    @Test(arguments: [("slow", Float(130)), ("fast", Float(240)), ("normal", Float(180)), ("unknown", Float(180))])
    func rateAndVoiceOptionsReachTheDriver(_ example: (String, Float)) async throws {
        let driver = Driver(); var requestedVoice: String?
        let result = try await NativeSpeechRequest.run(["text": "Neutral café 🐼", "settings": ["rate": example.0, "voice": ["id": "test-voice"]]], makeDriver: { voice in
            requestedVoice = voice; return driver
        }, present: { _ in Issue.record("Default speech unexpectedly showed a panel."); return true })
        #expect(result && requestedVoice == "test-voice")
        #expect(driver.text == "Neutral café 🐼" && driver.rate == example.1)
        #expect(driver.onFinish == nil)
    }

    @Test func defaultOptionsUseSystemVoiceNormalRateAndNoPanels() async throws {
        let driver = Driver()
        let result = try await NativeSpeechRequest.run(["text": "Neutral"], makeDriver: { voice in
            #expect(voice == nil); return driver
        }, present: { _ in Issue.record("Default speech showed a panel."); return true })
        #expect(result && driver.rate == 180)
    }

    @Test func confirmationAndCompletionOptionsUseThePresenter() async throws {
        let driver = Driver(); var notices: [NativeSpeechRequest.Notice] = []
        let result = try await NativeSpeechRequest.run(["text": "Neutral", "settings": ["autoStart": false, "autoClose": false]], makeDriver: { _ in driver }, present: { notice in
            notices.append(notice); return true
        })
        #expect(result)
        #expect(notices == [.confirm("Neutral"), .complete])
    }

    @Test func rejectedConfirmationDoesNotCreateOrStartASynthesizer() async throws {
        let result = try await NativeSpeechRequest.run(["text": "Neutral", "settings": ["autoStart": false]], makeDriver: { _ in
            Issue.record("Cancelled speech created a driver."); return Driver()
        }, present: { _ in false })
        #expect(!result)
    }

    @Test func failedStartAndUnsuccessfulCompletionReturnFalse() async throws {
        for startFailure in [true, false] {
            let driver = Driver(); driver.canStart = !startFailure; driver.finishImmediately = startFailure ? nil : false
            let result = try await NativeSpeechRequest.run(["text": "Neutral"], makeDriver: { _ in driver }, present: { _ in Issue.record("Failed speech showed completion."); return true })
            #expect(!result)
        }
    }

    @Test func cancellationStopsPlaybackAndIgnoresLateCompletion() async throws {
        let driver = Driver(); driver.finishImmediately = nil
        let task = Task { @MainActor in
            do {
                _ = try await NativeSpeechRequest.run(["text": "Neutral"], makeDriver: { _ in driver })
                return false
            } catch { return error is CancellationError }
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while !driver.started, ContinuousClock.now < deadline { await Task.yield() }
        task.cancel()
        #expect(await task.value)
        #expect(driver.stopped && driver.onFinish == nil)
        driver.late?(true)
        #expect(driver.onFinish == nil)
    }

    @Test func cancellationRejectsCompletionBeforeQueuedCleanup() async throws {
        let driver = Driver(); driver.finishImmediately = nil
        let task = Task {
            try await NativeSpeechRequest.run(
                ["text": "Neutral", "settings": ["autoClose": false]],
                makeDriver: { _ in driver },
                present: { _ in Issue.record("Cancelled playback showed completion."); return true })
        }
        var started = driver.startSignal.stream.makeAsyncIterator()
        try #require(await started.next() == true)
        task.cancel()
        driver.onFinish?(true)
        do { _ = try await task.value; Issue.record("Cancelled playback succeeded.") }
        catch { #expect(error is CancellationError) }
        #expect(driver.stopped)
        #expect(driver.onFinish == nil)
    }

    @Test func driverCreationErrorsRemainErrors() async {
        enum Failure: Error { case unavailable }
        do {
            _ = try await NativeSpeechRequest.run(["text": "Neutral"], makeDriver: { _ in throw Failure.unavailable })
            Issue.record("Unavailable speech succeeded.")
        } catch { #expect(error is Failure) }
    }

    @Test func cancellationDuringConfirmationDoesNotCreateADriver() async {
        let task = Task { @MainActor in
            do {
                _ = try await NativeSpeechRequest.run(["text": "Neutral", "settings": ["autoStart": false]], makeDriver: { _ in
                    Issue.record("Cancelled confirmation created a driver."); return Driver()
                }, present: { _ in try await Task.sleep(for: .seconds(20)); return true })
                return false
            } catch { return error is CancellationError }
        }
        task.cancel()
        #expect(await task.value)
    }
}
