import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous message composition") @MainActor
struct NativeMessageAsyncTests {
    @MainActor private final class Driver: NativeMessageDriver {
        var recipients: [String] = []
        var subject = ""
        var onFinish: ((Result<Void, Error>) -> Void)?
        var late: ((Result<Void, Error>) -> Void)?
        var permitted = true
        var result: Result<Void, Error>? = .success(())
        var body: String?
        var detachCount = 0
        var onStart: (() -> Void)?
        func canPerform(_ body: String) -> Bool { permitted }
        func perform(_ body: String) { self.body = body; late = onFinish; onStart?(); if let result { onFinish?(result) } }
        func detach() { detachCount += 1; onFinish = nil }
    }

    @Test(arguments: ["composeMail", "composeMessage"])
    func recipientsSubjectAndUnicodeReachTheCorrectService(_ operation: String) async throws {
        let driver = Driver(); var requested: String?
        let result = try await NativeMessageAdapter().composeAsync(operation, ["toRecipients": ["neutral@example.invalid"], "subject": "Neutral", "body": "café 🐼"], makeDriver: { name in requested = name; return driver })
        #expect(result["status"] == "sent" && requested == operation)
        #expect(driver.recipients == ["neutral@example.invalid"] && driver.subject == "Neutral" && driver.body == "café 🐼")
        #expect(driver.detachCount == 1 && driver.onFinish == nil)
        driver.late?(.failure(NSError(domain: "Late", code: 1)))
        #expect(driver.detachCount == 1)
    }

    @Test func unsupportedOptionsFailBeforeCreatingOrOpeningAComposer() async {
        let unsupported: [[String: Any]] = [["isBodyHTML": true], ["sendInBackground": true], ["replyToRecipients": ["neutral@example.invalid"]], ["ccRecipients": ["neutral@example.invalid"]], ["bccRecipients": ["neutral@example.invalid"]]]
        for values in unsupported {
            do {
                _ = try await NativeMessageAdapter().composeAsync("composeMail", values, makeDriver: { _ in Issue.record("Unsupported composition created a service."); return Driver() })
                Issue.record("Unsupported composition succeeded.")
            } catch { }
        }
    }

    @Test func unavailableAndIncapableServicesDoNotPerform() async {
        enum Failure: Error { case unavailable }
        do {
            _ = try await NativeMessageAdapter().composeAsync("composeMail", [:], makeDriver: { _ in throw Failure.unavailable })
            Issue.record("Unavailable service succeeded.")
        } catch { #expect(error is Failure) }
        let driver = Driver(); driver.permitted = false
        do { _ = try await NativeMessageAdapter().composeAsync("composeMail", [:], makeDriver: { _ in driver }); Issue.record("Incapable service succeeded.") }
        catch { #expect(driver.body == nil && driver.detachCount == 1) }
    }

    @Test func systemUserCancellationHasItsOwnStatus() async throws {
        let driver = Driver(); driver.result = .failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        let result = try await NativeMessageAdapter().composeAsync("composeMail", [:], makeDriver: { _ in driver })
        #expect(result["status"] == "userCancelled" && driver.detachCount == 1)
    }

    @Test func serviceErrorsPropagateWithoutAFalseSuccessStatus() async {
        let driver = Driver(); driver.result = .failure(NSError(domain: "NeutralServiceFailure", code: 7))
        do { _ = try await NativeMessageAdapter().composeAsync("composeMessage", [:], makeDriver: { _ in driver }); Issue.record("Failed service succeeded.") }
        catch { #expect((error as NSError).domain == "NeutralServiceFailure") }
        #expect(driver.detachCount == 1)
    }

    @Test func timeoutDetachesAndIgnoresLateCompletion() async throws {
        let driver = Driver(); driver.result = nil
        do { _ = try await NativeMessageAdapter().composeAsync("composeMail", [:], timeout: 0.02, makeDriver: { _ in driver }); Issue.record("Timed out service succeeded.") }
        catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        driver.late?(.success(()))
        #expect(driver.detachCount == 1 && driver.onFinish == nil)
    }

    @Test func taskCancellationDetachesWithoutClaimingToRecallExternalComposition() async throws {
        let driver = Driver(); driver.result = nil
        let started = AsyncStream.makeStream(of: Bool.self)
        driver.onStart = { started.continuation.yield(true) }
        let task = Task { @MainActor in
            do { _ = try await NativeMessageAdapter().composeAsync("composeMail", [:], makeDriver: { _ in driver }); return false }
            catch { return error is CancellationError }
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        #expect(await task.value)
        driver.late?(.success(()))
        #expect(driver.detachCount == 1 && driver.onFinish == nil)
    }
}
