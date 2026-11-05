import AppKit
import Combine
import Testing
import AgentContracts
@testable import DraftlyCore
@testable import Draftly

@Suite("Authorized application window opening") @MainActor
struct AuthorizedWindowOpeningTests {
    @MainActor private final class Fixture {
        let library: LibraryStore
        let app: AppController
        let preferences: TestPreferences
        var models: [WindowModel] = []
        var windows: [NSWindow] = []
        init() throws {
            library = try LibraryStore(inMemory: true, seed: false)
            preferences = try TestPreferences(prefix: "Draftly-Authorized-Window-")
            app = AppController(library: library, recentDrafts: RecentDraftStore(defaults: preferences.defaults))
        }
        func model() -> WindowModel {
            var dependencies = WindowDependencies()
            dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
            let model = WindowModel(library: library, dependencies: dependencies)
            models.append(model)
            return model
        }
        func window() -> NSWindow {
            let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            windows.append(window)
            return window
        }
        func close() {
            app.openDraftLibrary = nil
            for model in models {
                app.unregisterWindow(model)
                model.editor.load(Note(), focusEditor: false); model.hasUnsavedChanges = false
            }
            windows.forEach { $0.close() }
            models.removeAll(); windows.removeAll(); preferences.close()
        }
    }

    @Test func authorizationRunsBeforeTargetLookupOrSceneCreation() async throws {
        let f = try Fixture(); defer { f.close() }
        var opens = 0
        f.app.openDraftLibrary = { _ in opens += 1 }
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await f.app.openAuthorizedDraftWindow(UUID(), focusEditor: false,
                authorize: { throw AgentErrorCode.permissionDenied })
        }
        #expect(opens == 0 && f.library.notes.isEmpty && f.library.revisions.isEmpty)
    }

    @Test(arguments: [false, true])
    func emptyRequestedWindowLoadsOnlyTheRequestedDraft(focus: Bool) async throws {
        let f = try Fixture(); defer { f.close() }
        let target = try f.library.createNote(content: "Allowed café 🐼")
        let hidden = try f.library.createNote(content: "Unrelated")
        let versions = f.library.revisions
        let model = f.model(), window = f.window(), initialFocus = model.editor.focusToken
        var sceneID: UUID?
        f.app.openDraftLibrary = { id in sceneID = id; f.app.registerWindow(model, window: window, requestID: id) }
        var validations = 0
        let result = try await f.app.openAuthorizedDraftWindow(target.id, focusEditor: focus, authorize: { validations += 1 })
        #expect(result === model && result.editor.noteID == target.id && result.editor.content == target.content)
        #expect((model.editor.focusToken != initialFocus) == focus)
        let finished = validations
        f.app.registerWindow(model, window: window, requestID: try #require(sceneID))
        #expect(validations == finished)
        #expect(f.library.notes.first { $0.id == hidden.id } == hidden && f.library.revisions == versions)
    }

    @Test(arguments: ["before", "duringAccess"])
    func authorityLossCannotLoadTheTarget(phase: String) async throws {
        let f = try Fixture(); defer { f.close() }
        let target = try f.library.createNote(content: "Allowed")
        let versions = f.library.revisions
        let model = f.model(), window = f.window()
        var allowed = true
        let observation = f.library.$notes.dropFirst().sink { _ in if phase == "duringAccess" { allowed = false } }
        defer { observation.cancel() }
        f.app.openDraftLibrary = { id in
            if phase == "before" { allowed = false }
            f.app.registerWindow(model, window: window, requestID: id)
        }
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await f.app.openAuthorizedDraftWindow(target.id, focusEditor: false, authorize: {
                guard allowed else { throw AgentErrorCode.permissionDenied }
            })
        }
        #expect(model.editor.noteID == nil && model.editor.content.isEmpty)
        #expect(f.library.notes.first?.content == target.content && f.library.revisions == versions)
    }

    @Test func unexpectedPendingEditorIsNotSavedOrReplaced() async throws {
        let f = try Fixture(); defer { f.close() }
        let target = try f.library.createNote(content: "Allowed"), hidden = try f.library.createNote(content: "Unrelated")
        let versions = f.library.revisions
        let model = f.model(), window = f.window()
        model.editor.load(hidden, focusEditor: false)
        model.editor.content = "Pending unrelated"; model.hasUnsavedChanges = true
        f.app.openDraftLibrary = { id in f.app.registerWindow(model, window: window, requestID: id) }
        await #expect(throws: AgentErrorCode.outcomeUnknown) {
            try await f.app.openAuthorizedDraftWindow(target.id, focusEditor: false, authorize: {})
        }
        #expect(model.editor.noteID == hidden.id && model.editor.content == "Pending unrelated" && model.hasUnsavedChanges)
        #expect(f.library.notes.contains(hidden) && f.library.notes.contains(target) && f.library.revisions == versions)
    }

    @Test func cancelledRequestCannotReuseALateWindowOrSaveItsPendingText() async throws {
        let f = try Fixture(); defer { f.close() }
        let target = try f.library.createNote(content: "Allowed"), hidden = try f.library.createNote(content: "Unrelated")
        let versions = f.library.revisions
        let model = f.model()
        let started = AsyncStream.makeStream(of: UUID.self)
        f.app.openDraftLibrary = { id in
            f.app.registerWindow(model, requestID: id)
            started.continuation.yield(id)
        }
        let task = Task {
            defer { started.continuation.finish() }
            return try await f.app.openAuthorizedDraftWindow(target.id, focusEditor: false, authorize: {})
        }
        defer { task.cancel(); started.continuation.finish() }
        var events = started.stream.makeAsyncIterator()
        let requestID = try #require(await events.next())
        model.editor.load(hidden, focusEditor: false)
        model.editor.content = "Pending unrelated"; model.hasUnsavedChanges = true
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled window request succeeded") }
        catch { #expect(error is CancellationError) }
        f.app.registerWindow(model, window: f.window(), requestID: requestID)
        #expect(model.editor.noteID == hidden.id && model.editor.content == "Pending unrelated" && model.hasUnsavedChanges)
        #expect(f.library.notes.contains(target) && f.library.notes.contains(hidden) && f.library.revisions == versions)
    }
}
