import Foundation
import EventKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous EventKit requests")
@MainActor
struct NativeEventKitWaitTests {
    @Test func fullAccessDoesNotRequestAuthorizationAgain() async throws {
        var requests = 0
        let request = EventKitAuthorizationRequest(status: { _ in .fullAccess }, request: { _, _ in requests += 1 })
        try await request.requireFullAccess(reminders: true)
        #expect(requests == 0)
    }

    @Test func deniedAndRestrictedAccessFailWithoutAPrompt() async {
        for status in [EKAuthorizationStatus.denied, .restricted] {
            var requested = false
            let request = EventKitAuthorizationRequest(status: { _ in status }, request: { _, _ in requested = true })
            do { try await request.requireFullAccess(reminders: false); Issue.record("Denied access succeeded.") }
            catch { #expect(error.localizedDescription == "Access was denied. Enable access in System Settings.") }
            #expect(!requested)
        }
    }

    @Test func writeOnlyAccessRequestsFullAccessForTheCorrectEntity() async throws {
        var status: EKAuthorizationStatus = .writeOnly
        var requestedReminders: Bool?
        let request = EventKitAuthorizationRequest(status: { entity in
            #expect(entity == .event)
            return status
        }, request: { reminders, completion in
            requestedReminders = reminders
            status = .fullAccess
            completion(true, nil)
        })
        try await request.requireFullAccess(reminders: false)
        #expect(requestedReminders == false)
    }

    @Test func completionCannotClaimFullAccessWithoutFullAuthorization() async {
        let request = EventKitAuthorizationRequest(status: { _ in .writeOnly }, request: { _, completion in completion(true, nil) })
        do { try await request.requireFullAccess(reminders: false); Issue.record("Write-only access was accepted as full access.") }
        catch { #expect(error.localizedDescription == "Access was denied. Enable access in System Settings.") }
    }

    @Test func authorizationFailurePreservesTheSystemError() async {
        let failure = NSError(domain: "Draftly.EventKitFixture", code: 42, userInfo: [NSLocalizedDescriptionKey: "Neutral authorization failure"])
        let request = EventKitAuthorizationRequest(status: { _ in .notDetermined }, request: { reminders, completion in
            #expect(reminders)
            completion(false, failure)
        })
        do { try await request.requireFullAccess(reminders: true); Issue.record("The authorization failure succeeded.") }
        catch { #expect(error.localizedDescription == "Neutral authorization failure") }
    }

    @Test func authorizationTimeoutIgnoresALateGrant() async throws {
        var callback: (@Sendable (Bool, Error?) -> Void)?
        let request = EventKitAuthorizationRequest(status: { _ in .notDetermined }, request: { _, completion in callback = completion })
        do { try await request.requireFullAccess(reminders: true, timeout: 0.02); Issue.record("Authorization did not time out.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        callback?(true, nil)
    }

    @Test func authorizationCancellationDoesNotWaitForTheSystemDialog() async throws {
        let started = AsyncStream.makeStream(of: Bool.self)
        var callback: (@Sendable (Bool, Error?) -> Void)?
        let request = EventKitAuthorizationRequest(status: { _ in .notDetermined }, request: { _, completion in callback = completion; started.continuation.yield(true); started.continuation.finish() })
        let task = Task { try await request.requireFullAccess(reminders: true) }
        var events = started.stream.makeAsyncIterator()
        try #require(await events.next() == true)
        #expect(callback != nil)
        task.cancel()
        do { try await task.value; Issue.record("The cancelled authorization succeeded.") }
        catch { #expect(error is CancellationError) }
        callback?(true, nil)
    }

    @Test func reminderFetchSuccessReleasesItsCancellationToken() async throws {
        var cancelled = false
        let fetch = EventKitReminderFetchRequest { completion in
            completion(EventKitReminderResult(reminders: []))
            return { cancelled = true }
        }
        let result = try await fetch.fetch()
        #expect(result.reminders.isEmpty)
        #expect(!cancelled)
    }

    @Test func reminderFetchCancellationCancelsTheUnderlyingRequestAndIgnoresLateResults() async throws {
        let started = AsyncStream.makeStream(of: Bool.self)
        var callback: (@Sendable (EventKitReminderResult) -> Void)?
        var cancelled = false
        let fetch = EventKitReminderFetchRequest { completion in
            callback = completion
            started.continuation.yield(true); started.continuation.finish()
            return { cancelled = true }
        }
        let task = Task { try await fetch.fetch() }
        var events = started.stream.makeAsyncIterator()
        try #require(await events.next() == true)
        #expect(callback != nil)
        task.cancel()
        do { _ = try await task.value; Issue.record("The cancelled fetch succeeded.") }
        catch { #expect(error is CancellationError) }
        #expect(cancelled)
        callback?(EventKitReminderResult(reminders: []))
    }

    @Test func reminderFetchTimeoutCancelsTheUnderlyingRequest() async {
        var cancelled = false
        let fetch = EventKitReminderFetchRequest { _ in { cancelled = true } }
        do { _ = try await fetch.fetch(timeout: 0.02); Issue.record("The reminder fetch did not time out.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(cancelled)
    }

    @Test func repeatedCallbacksCannotFinishTheSameWaitTwice() async throws {
        let value: String = try await EventKitCallbackWait.wait(timeout: 1) { completion in
            completion(.success("first"))
            completion(.success("first"))
            return nil
        }
        #expect(value == "first")
    }

    @Test(arguments: [9.0, 10.0, 11.0])
    func callbackDeadlineIsCheckedBeforeQueuedTimer(elapsed: Double) async {
        var now = Date(timeIntervalSinceReferenceDate: 100)
        var cancellations = 0
        do {
            let value: String = try await EventKitCallbackWait.wait(timeout: 10, now: { now }) { reply in
                now = now.addingTimeInterval(elapsed)
                reply(.success("Neutral"))
                return { cancellations += 1 }
            }
            #expect(elapsed < 10 && value == "Neutral")
        } catch {
            #expect(elapsed >= 10 && error as? ActionExecutionInterruption == .timeout)
        }
        #expect(cancellations == (elapsed >= 10 ? 1 : 0))
    }

    @Test func queuedCompletionCannotSkipCleanupAfterCancellation() async throws {
        var cancellations = 0
        var task: Task<String, Error>?
        task = Task {
            try await EventKitCallbackWait.wait(timeout: 10) { reply in
                reply(.success("Late value"))
                task?.cancel()
                return { cancellations += 1 }
            }
        }
        let pending = try #require(task)
        do { _ = try await pending.value; Issue.record("Cancelled EventKit request returned success.") }
        catch { #expect(error is CancellationError) }
        #expect(cancellations == 1)
    }

    @Test func invalidTimeoutDoesNotStartTheNativeRequest() async {
        var started = false
        do {
            let _: String = try await EventKitCallbackWait.wait(timeout: .infinity) { _ in started = true; return nil }
            Issue.record("The invalid timeout succeeded.")
        } catch { #expect(error.localizedDescription == "The EventKit timeout must be positive and finite.") }
        #expect(!started)
    }
}
