import Foundation
import Testing
import AgentContracts
@testable import DraftlyCore
@testable import Draftly

@Suite("Application-owned agent editor membership") @MainActor
struct AgentEditorWindowLifecycleTests {
    @MainActor private final class Fixture {
        let library: LibraryStore
        let domain = "Draftly-Agent-Window-Lifecycle-" + UUID().uuidString
        let defaults: UserDefaults
        var app: AppController?

        init() throws {
            library = try LibraryStore(inMemory: true, seed: false)
            defaults = try #require(UserDefaults(suiteName: domain))
            app = AppController(library: library, recentDrafts: RecentDraftStore(defaults: defaults))
        }
        func cleanup() { app = nil; defaults.removePersistentDomain(forName: domain) }
        func registry(_ target: LibraryStore? = nil) throws -> AgentEditorRegistry {
            let app = try #require(app)
            return try app.agentEditorRegistry(for: target ?? library)
        }
        func model(_ note: Note) -> WindowModel {
            var dependencies = WindowDependencies(); dependencies.preferences = WindowPreferences(defaults: defaults)
            let model = WindowModel(library: library, dependencies: dependencies)
            model.editor.load(note, focusEditor: false)
            return model
        }
    }

    @Test(arguments: [false, true])
    func registeredWindowsOpenedAndClosedBetweenReadsChangeTheVersion(requested: Bool) async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let app = try #require(f.app), note = try f.library.createNote(content: "Neutral stored")
        let registry = try f.registry(), before = try registry.snapshot(note).generation
        let model = f.model(note)
        let edit = {
            model.editor.content = "Transient neutral"; model.hasUnsavedChanges = true
            model.editor.content = note.content
        }
        if requested {
            app.openDraftLibrary = { [weak app] id in
                app?.registerWindow(model, requestID: id); edit(); app?.unregisterWindow(model)
            }
            await #expect(throws: CancellationError.self) {
                try await app.openDraftWindow(note.id, tab: false, origin: nil)
            }
        } else {
            app.registerWindow(model); edit(); app.unregisterWindow(model)
        }
        #expect(try registry.snapshot(note).generation != before)
        #expect(f.library.notes.first?.content == note.content && model.window == nil)
        #expect(app.agentSettings == nil)
    }

    @Test func changingLibrariesInvalidatesTheOldRegistryAndKeepsOneCurrentInstance() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let app = try #require(f.app), note = try f.library.createNote(content: "Neutral stored")
        let first = try f.registry()
        #expect(try f.registry() === first)
        let other = try LibraryStore(inMemory: true, seed: false)
        app.library = other
        #expect(throws: AgentErrorCode.cancelled) { try first.snapshot(note) }
        #expect(!first.isBound(to: f.library))
        #expect(throws: AgentErrorCode.invalidInput) { try f.registry(f.library) }
        let replacement = try f.registry(other)
        #expect(replacement !== first && replacement.isBound(to: other))
        app.library = f.library
        #expect(throws: AgentErrorCode.cancelled) { try replacement.snapshot(note) }
        #expect(try f.registry() !== first)
        first.refreshMembership()
        #expect(throws: AgentErrorCode.cancelled) { try first.snapshot(note) }
    }

    @Test func releasingTheApplicationInvalidatesARetainedRegistry() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let note = try f.library.createNote(content: "Neutral stored"), registry = try f.registry()
        weak var owner = f.app
        f.app = nil
        #expect(owner == nil)
        #expect(throws: AgentErrorCode.cancelled) { try registry.snapshot(note) }
    }
}
