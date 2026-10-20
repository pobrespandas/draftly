import Foundation
import Testing
@testable import Draftly

@Suite("Calendar dialog commit boundary") @MainActor
struct NativeEventDialogTests {
    private func initial() -> EventDialogValues {
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        return EventDialogValues(title: "Neutral café 🐼", notes: "Line one\nLine two", start: start, end: start.addingTimeInterval(3600))
    }

    @Test func acceptedValuesAreValidatedAndSavedOnce() async throws {
        let source = initial()
        var edited = source
        edited.title = "Edited 🐼"; edited.notes = "New\nnotes"
        edited.start += 60; edited.end += 120
        var saves: [EventDialogValues] = []
        let result = try await EventDialogCommit.run(source, present: {
            #expect($0 == source)
            return edited
        }, save: { saves.append($0) })
        #expect(result == edited && saves == [edited])
        #expect(source.title == "Neutral café 🐼")
    }

    @Test func userCancellationDoesNotSaveOrChangeTheInput() async throws {
        let source = initial()
        var saved = false
        let result = try await EventDialogCommit.run(source, present: { _ in nil }, save: { _ in saved = true })
        #expect(result == nil && !saved)
        #expect(source.notes == "Line one\nLine two")
    }

    @Test func finalDatesAreCheckedAfterEditingBeforeSave() async throws {
        let source = initial()
        var saved = false
        do {
            _ = try await EventDialogCommit.run(source, present: { values in
                var edited = values
                edited.end = edited.start.addingTimeInterval(-1)
                return edited
            }, save: { _ in saved = true })
            Issue.record("An invalid final range must fail.")
        } catch { #expect(!saved) }
    }

    @Test func invalidInitialDatesFailBeforePresentation() async throws {
        var source = initial()
        source.start = source.end.addingTimeInterval(1)
        var presented = false
        do {
            _ = try await EventDialogCommit.run(source, present: { _ in presented = true; return nil }, save: { _ in
                Issue.record("An invalid initial range must not save.")
            })
            Issue.record("An invalid initial range must fail.")
        } catch { #expect(!presented) }
    }

    @Test func cancellationRejectsAnAcceptedLateResponseBeforeSave() async throws {
        let gate = EventPresenterGate()
        var saved = false
        let source = initial()
        let task = Task {
            try await EventDialogCommit.run(source, present: { await gate.present($0) }, save: { _ in saved = true })
        }
        var iterator = gate.started.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        gate.accept(source)
        do {
            _ = try await task.value
            Issue.record("Task cancellation must reject a late accepted edit.")
        } catch { #expect(error is CancellationError) }
        #expect(!saved)
    }

    @Test func saveErrorsPropagateWithoutRetry() async throws {
        enum SaveFailure: Error { case refused }
        var attempts = 0
        do {
            _ = try await EventDialogCommit.run(initial(), present: { $0 }, save: { _ in
                attempts += 1
                throw SaveFailure.refused
            })
            Issue.record("The save failure must propagate.")
        } catch { #expect(error is SaveFailure && attempts == 1) }
    }
}

@MainActor private final class EventPresenterGate {
    let started = AsyncStream.makeStream(of: Bool.self)
    private var continuation: CheckedContinuation<EventDialogValues?, Never>?
    func present(_ values: EventDialogValues) async -> EventDialogValues? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.continuation.yield(true)
        }
    }
    func accept(_ values: EventDialogValues) {
        continuation?.resume(returning: values)
        continuation = nil
    }
}
