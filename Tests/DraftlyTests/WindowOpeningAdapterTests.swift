import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Window opening result adapters") @MainActor
struct WindowOpeningAdapterTests {
    @Test func absentOpeningDependencyCannotReportSuccess() throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        #expect(try model.actionUIOperation(["operation": "openInNewTab", "value": ["uuid": UUID().uuidString]]) as? Bool == false)
        #expect(try model.actionUIOperation(["operation": "openInNewTab"]) as? Bool == false)
    }

    @Test func asyncDependencyReceivesTheExactTargetAndReturnsItsRejection() async throws {
        let id = UUID()
        var calls = 0
        var dependencies = WindowDependencies()
        dependencies.openDraftWindowAsync = { target, tab, _, timeout in
            calls += 1
            #expect(target == id && tab && timeout == 3)
            return false
        }
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false), dependencies: dependencies)
        let result = try await WindowActionAdapter(model: model).performAsync(["operation": "openInNewTab", "value": ["uuid": id.uuidString]], timeout: 3)
        #expect(result as? Bool == false && calls == 1)
    }

    @Test func controllerRejectsUnavailableTargetsAndTabOriginsWithoutOpeningAScene() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let suite = "Draftly.OpeningTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = AppController(library: library, recentDrafts: RecentDraftStore(defaults: defaults))
        var opens = 0
        controller.openDraftLibrary = { _ in opens += 1 }
        #expect(try await controller.openDraftWindow(note.id, tab: true, origin: nil) == false)
        #expect(try await controller.openDraftWindow(UUID(), tab: false, origin: nil) == false)
        #expect(opens == 0 && controller.windows.allObjects.isEmpty)
    }

    @Test func closingAnUnattachedRequestedModelCancelsOnlyItsRequest() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let suite = "Draftly.OpeningTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = AppController(library: library, recentDrafts: RecentDraftStore(defaults: defaults))
        let started = AsyncStream.makeStream(of: UUID.self)
        controller.openDraftLibrary = { started.continuation.yield($0) }
        let task = Task {
            defer { started.continuation.finish() }
            return try await controller.openDraftWindow(note.id, tab: false, origin: nil)
        }
        defer { task.cancel() }
        var events = started.stream.makeAsyncIterator()
        let requestID = try #require(await events.next())
        let model = controller.makeWindowModel(library: library)
        controller.registerWindow(model, requestID: requestID)
        #expect(model.editor.noteID == nil)
        controller.unregisterWindow(model)
        do { _ = try await task.value; Issue.record("The closed request succeeded.") }
        catch { #expect(error is CancellationError) }
        controller.registerWindow(model, requestID: requestID)
        #expect(controller.windows.allObjects.isEmpty && model.editor.noteID == nil)
        #expect(library.notes.map(\.id) == [note.id])
    }
}
