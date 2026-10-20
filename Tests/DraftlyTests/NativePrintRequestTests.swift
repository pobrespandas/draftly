import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous printing requests") @MainActor
struct NativePrintRequestTests {
    @MainActor private final class Driver: NativePrintDriver {
        var onFinish: ((Result<Bool, Error>) -> Void)?
        var late: ((Result<Bool, Error>) -> Void)?
        var result: Result<Bool, Error>? = .success(true)
        var started = false
        var detached = 0
        var cancelled = 0
        var beforeFinish: (() -> Void)?
        func start() { started = true; late = onFinish; beforeFinish?(); if let result { onFinish?(result) } }
        func cancelOwnedPresentation() { cancelled += 1 }
        func detach() { detached += 1; onFinish = nil }
    }
    @Test func defaultFormatAndMarginsAreExplicit() throws {
        let configuration = try NativePrintConfiguration(["text": "Neutral café 🐼"])
        #expect(configuration.text == "Neutral café 🐼" && configuration.format == .text)
        #expect(configuration.topMargin == 72 && configuration.bottomMargin == 72 && configuration.leftMargin == 72 && configuration.rightMargin == 72)
    }
    @Test func firstPartyStringsAndNumericMarginsKeepTheirValues() async throws {
        let driver = Driver()
        let result = try await NativePrintRequest.run(["printFormat": "HTML", "text": "<p>Neutral</p>", "topMargin": "12.5", "bottomMargin": 20, "leftMargin": "0", "rightMargin": 35.25], makeDriver: { configuration in
            #expect(configuration.format == .html && configuration.text == "<p>Neutral</p>")
            #expect(configuration.topMargin == 12.5 && configuration.bottomMargin == 20 && configuration.leftMargin == 0 && configuration.rightMargin == 35.25)
            return driver
        })
        #expect(result && driver.started && driver.detached == 1 && driver.cancelled == 0)
    }
    @Test func invalidOptionsFailBeforeCreatingAnyNativePrintOperation() async {
        let invalid: [[String: Any]] = [["printFormat": "PDF"], ["topMargin": "bad"], ["topMargin": -1], ["rightMargin": Double.infinity], ["leftMargin": true]]
        for values in invalid {
            do {
                _ = try await NativePrintRequest.run(values, makeDriver: { _ in Issue.record("Invalid options created a print operation."); return Driver() })
                Issue.record("Invalid print options succeeded.")
            } catch { }
        }
    }
    @Test func nativeFalseRemainsUnsuccessfulWithoutClaimingAReasonAppKitDoesNotProvide() async throws {
        let driver = Driver(); driver.result = .success(false)
        let result = try await NativePrintRequest.run([:], makeDriver: { _ in driver })
        #expect(!result && driver.detached == 1 && driver.cancelled == 0)
    }
    @Test func driverErrorsAndUnavailableWindowsRemainErrors() async {
        enum Failure: Error { case unavailable }
        do { _ = try await NativePrintRequest.run([:], makeDriver: { _ in throw Failure.unavailable }); Issue.record("Unavailable printing succeeded.") }
        catch { #expect(error is Failure) }
        let driver = Driver(); driver.result = .failure(NSError(domain: "NeutralPrintFailure", code: 7))
        do { _ = try await NativePrintRequest.run([:], makeDriver: { _ in driver }); Issue.record("Failed printing succeeded.") }
        catch { #expect((error as NSError).domain == "NeutralPrintFailure") }
        #expect(driver.detached == 1)
    }
    @Test func aLateCallbackCannotBeatTheDeadlineWhenTheTimerHasNotRun() async {
        let driver = Driver()
        var clock = Date(timeIntervalSince1970: 10)
        driver.beforeFinish = { clock = clock.addingTimeInterval(61) }
        do {
            _ = try await NativePrintRequest.run([:], timeout: 60, now: { clock }, makeDriver: { _ in driver })
            Issue.record("A late print callback succeeded.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        #expect(driver.detached == 1 && driver.cancelled == 1)
    }

    @Test func timeoutCancelsOnlyOwnedPresentationAndRejectsLateCallbacks() async {
        let driver = Driver(); driver.result = nil
        do { _ = try await NativePrintRequest.run([:], timeout: 0.02, makeDriver: { _ in driver }); Issue.record("Timed out printing succeeded.") }
        catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        driver.late?(.success(true))
        #expect(driver.detached == 1 && driver.cancelled == 1)
    }
    @Test func taskCancellationCancelsOnlyOwnedPresentationAndCompletesOnce() async {
        let driver = Driver(); driver.result = nil
        let task = Task { @MainActor in
            do { _ = try await NativePrintRequest.run([:], makeDriver: { _ in driver }); return false }
            catch { return error is CancellationError }
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while !driver.started, ContinuousClock.now < deadline { await Task.yield() }
        task.cancel()
        #expect(await task.value)
        driver.late?(.success(false))
        #expect(driver.detached == 1 && driver.cancelled == 1)
    }
}
