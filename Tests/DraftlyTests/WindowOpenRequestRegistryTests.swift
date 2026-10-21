import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Correlated window open requests") @MainActor
struct WindowOpenRequestRegistryTests {
    @Test func inlineCompletionReturnsTheActualResultAndCleansUpOnce() async throws {
        let registry = WindowOpenRequestRegistry()
        for expected in [true, false] {
            var ended: [UUID] = []
            var id: UUID?
            let result = try await registry.request(start: { requestID in
                id = requestID
                #expect(registry.contains(requestID))
                #expect(registry.complete(requestID, expected))
                #expect(!registry.complete(requestID, !expected))
            }, onEnd: { ended.append($0) })
            #expect(result == expected)
            let completedID = try #require(id)
            #expect(ended == [completedID] && !registry.contains(completedID))
        }
        #expect(!registry.complete(UUID(), true))
    }

    @Test func simultaneousRequestsCompleteOnlyTheirOwnWaiters() async throws {
        let registry = WindowOpenRequestRegistry()
        let starts = AsyncStream.makeStream(of: UUID.self)
        defer { starts.continuation.finish(); registry.cancelAll() }
        var ended: [UUID] = []
        let first = Task { defer { starts.continuation.finish() }; return try await registry.request(start: { starts.continuation.yield($0) }, onEnd: { ended.append($0) }) }
        var events = starts.stream.makeAsyncIterator()
        let firstID = try #require(await events.next())
        let second = Task { defer { starts.continuation.finish() }; return try await registry.request(start: { starts.continuation.yield($0) }, onEnd: { ended.append($0) }) }
        let secondID = try #require(await events.next())
        #expect(firstID != secondID)
        #expect(registry.complete(secondID, false))
        #expect(try await second.value == false)
        #expect(registry.contains(firstID) && ended == [secondID])
        #expect(registry.complete(firstID, true))
        #expect(try await first.value)
        #expect(ended == [secondID, firstID])
    }

    @Test func timeoutRemovesRequestAndRejectsLateCompletion() async throws {
        let registry = WindowOpenRequestRegistry()
        var id: UUID?
        var ended: [UUID] = []
        do {
            _ = try await registry.request(timeout: 0.02, start: { id = $0 }, onEnd: { ended.append($0) })
            Issue.record("The window request did not time out.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        let expiredID = try #require(id)
        #expect(!registry.contains(expiredID) && !registry.complete(expiredID, true))
        registry.cancel(expiredID)
        #expect(ended == [expiredID])
    }

    @Test func completionAtTheDeadlineCannotBeatTheScheduledTimeout() async throws {
        var now = Date(timeIntervalSince1970: 100)
        let registry = WindowOpenRequestRegistry(now: { now })
        var ended = 0
        do {
            _ = try await registry.request(timeout: 10, start: { id in
                now = now.addingTimeInterval(10)
                #expect(!registry.contains(id))
                #expect(!registry.complete(id, true))
            }, onEnd: { _ in ended += 1 })
            Issue.record("An expired window request completed successfully.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        #expect(ended == 1)
    }

    @Test func taskCancellationReleasesTheWaiterAndRejectsLateCompletion() async throws {
        let registry = WindowOpenRequestRegistry()
        let starts = AsyncStream.makeStream(of: UUID.self)
        defer { starts.continuation.finish(); registry.cancelAll() }
        var ended: [UUID] = []
        let task = Task { defer { starts.continuation.finish() }; return try await registry.request(start: { starts.continuation.yield($0) }, onEnd: { ended.append($0) }) }
        var events = starts.stream.makeAsyncIterator()
        let id = try #require(await events.next())
        task.cancel()
        do { _ = try await task.value; Issue.record("The cancelled window request returned a result.") }
        catch { #expect(error is CancellationError) }
        #expect(!registry.contains(id) && !registry.complete(id, true))
        #expect(ended == [id])
    }

    @Test func cancellingOneRequestKeepsTheOtherRequestActive() async throws {
        let registry = WindowOpenRequestRegistry()
        let starts = AsyncStream.makeStream(of: UUID.self)
        defer { starts.continuation.finish(); registry.cancelAll() }
        let first = Task { defer { starts.continuation.finish() }; return try await registry.request(start: { starts.continuation.yield($0) }) }
        var events = starts.stream.makeAsyncIterator()
        let firstID = try #require(await events.next())
        let second = Task { defer { starts.continuation.finish() }; return try await registry.request(start: { starts.continuation.yield($0) }) }
        let secondID = try #require(await events.next())
        registry.cancel(firstID)
        do { _ = try await first.value; Issue.record("The cancelled window request returned a result.") }
        catch { #expect(error is CancellationError) }
        #expect(registry.contains(secondID))
        registry.complete(secondID, true)
        #expect(try await second.value)
    }

    @Test func invalidTimeoutDoesNotStartOrAllocateARequest() async {
        let registry = WindowOpenRequestRegistry()
        for timeout in [0, -1, .infinity, .nan] {
            do {
                _ = try await registry.request(timeout: timeout, start: { _ in Issue.record("Invalid request started.") },
                    onEnd: { _ in Issue.record("Invalid request allocated cleanup.") })
                Issue.record("The invalid window timeout was accepted.")
            } catch { #expect(error.localizedDescription == "The window open timeout must be positive and finite.") }
        }
    }

    @Test func alreadyCancelledTaskDoesNotStartOrAllocateARequest() async {
        let registry = WindowOpenRequestRegistry()
        let task = Task {
            try await registry.request(start: { _ in Issue.record("Cancelled request started.") },
                onEnd: { _ in Issue.record("Cancelled request allocated cleanup.") })
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("The cancelled request returned a result.") }
        catch { #expect(error is CancellationError) }
    }
}
