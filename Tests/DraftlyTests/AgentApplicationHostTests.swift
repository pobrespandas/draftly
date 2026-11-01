import Combine
import Foundation
import CoreData
import Testing
import AgentContracts
@testable import DraftlyCore
@testable import Draftly

@Suite("Application-owned agent host shutdown") @MainActor
struct AgentApplicationHostTests {
    @MainActor private final class Secrets { var values: [UUID: Data] = [:] }
    @MainActor private final class Fixture {
        let root: URL
        let library: LibraryStore
        let defaults: UserDefaults
        let domain = "Draftly-Agent-Application-" + UUID().uuidString
        let secrets = Secrets()
        var app: AppController?

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Agent-Application-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            library = try LibraryStore(directory: root, seed: false)
            defaults = try #require(UserDefaults(suiteName: domain))
            app = AppController(library: library, recentDrafts: RecentDraftStore(defaults: defaults))
        }
        func cleanup() {
            app = nil; defaults.removePersistentDomain(forName: domain)
            library.container.viewContext.reset()
            for store in library.container.persistentStoreCoordinator.persistentStores {
                try? library.container.persistentStoreCoordinator.remove(store)
            }
            try? FileManager.default.removeItem(at: root)
        }
        func host(editors supplied: AgentEditorRegistry? = nil) throws -> AgentLocalHost {
            let app = try #require(app), secrets = secrets, library = library
            return try AgentLocalHost(library: library, appVersion: "Neutral QA",
                editors: supplied ?? app.agentEditorRegistry(for: library), isLocked: { false },
                pendingEditorGeneration: { _ in "" }, resolveTargets: { targets in
                    Set(targets.filter { target in target.kind == .draft && library.notes.contains(where: { $0.id == target.id }) })
                }, credentials: .init(read: { secrets.values[$0] }, create: { id, value in
                    guard secrets.values[id] == nil else { throw AgentErrorCode.versionConflict }
                    secrets.values[id] = value
                }, remove: { secrets.values.removeValue(forKey: $0) }), validateApplication: {}, validateHelper: { _ in })
        }
        func handToApplication(_ host: AgentLocalHost) throws {
            let app = try #require(app), settings = try host.makeSettingsModel(choices: { [] })
            try app.adoptAgentHost(host)
            app.agentSettings = settings
        }
        func session(_ host: AgentLocalHost) throws -> AgentCommandService.Session {
            try host.setEnabledFromUserInterface(true)
            let record = try host.connections.connectFromUserInterface(name: "Neutral QA", libraryID: host.libraryID, scope: .library)
            return try host.service.authenticate(connectionID: record.id, credential: #require(secrets.values[record.id]))
        }
        func prepareTermination() throws -> Bool {
            try #require(app).prepareForTermination()
        }
    }

    @Test func changingLibraryClosesTransportAndAllAuthorityBeforePublication() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let app = try #require(f.app), host = try f.host(); defer { host.close() }
        try f.handToApplication(host)
        let session = try f.session(host), challenge = try host.pairing.request(clientName: "Neutral pending")
        let path = try #require(host.endpoint)
        let observation = app.$library.dropFirst().sink { _ in
            #expect(host.endpoint == nil)
            #expect(throws: AgentErrorCode.cancelled) { try host.service.authorizedLibraryID(for: session) }
        }
        defer { observation.cancel() }
        app.library = nil
        #expect(host.endpoint == nil && !FileManager.default.fileExists(atPath: path))
        #expect(try host.pairing.state(challenge.id) == .invalidated)
        #expect(throws: AgentErrorCode.cancelled) { try host.resumeIfEnabled() }
        #expect(app.agentSettings == nil)
    }

    @Test func ownerReleaseClosesARetainedHost() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try f.handToApplication(host)
        let session = try f.session(host)
        weak var owner = f.app
        f.app = nil
        #expect(owner == nil && host.endpoint == nil)
        #expect(throws: AgentErrorCode.cancelled) { try host.service.authorizedLibraryID(for: session) }
    }

    @Test(arguments: [false, true])
    func terminationClosesOnlyAfterSuccessfulSave(fails: Bool) throws {
        let f = try Fixture(); defer { f.cleanup() }
        let app = try #require(f.app), note = try f.library.createNote(content: "Stored neutral")
        var hostAtSave: AgentLocalHost?
        var dependencies = WindowDependencies(); dependencies.preferences = WindowPreferences(defaults: f.defaults)
        let model = WindowModel(library: f.library, dependencies: dependencies, saveDraft: { note in
            #expect(hostAtSave?.endpoint != nil)
            if fails { throw DraftlyError.message("Neutral storage failure") }
            try f.library.saveNote(note)
        })
        model.editor.load(note, focusEditor: false); model.editor.content = "Pending neutral"; model.hasUnsavedChanges = true
        app.registerWindow(model)
        let host = try f.host(); defer { host.close() }
        hostAtSave = host
        try f.handToApplication(host)
        let session = try f.session(host)
        #expect(try f.prepareTermination() == !fails)
        if fails {
            #expect(host.endpoint != nil && model.hasUnsavedChanges)
            #expect(try host.service.authorizedLibraryID(for: session) == host.libraryID)
            #expect(f.library.notes.first?.content == note.content)
        } else {
            #expect(host.endpoint == nil && !model.hasUnsavedChanges)
            #expect(throws: AgentErrorCode.cancelled) { try host.service.authorizedLibraryID(for: session) }
            #expect(f.library.notes.first?.content == "Pending neutral")
        }
    }

    @Test func adoptionIsIdleAndIdempotentWithoutClosingTheActiveHost() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let app = try #require(f.app), host = try f.host(); defer { host.close() }
        try app.adoptAgentHost(host)
        #expect(host.endpoint == nil && app.agentSettings == nil)
        try f.handToApplication(host)
        let session = try f.session(host), settings = app.agentSettings
        try app.adoptAgentHost(host)
        #expect(host.endpoint != nil && app.agentSettings === settings)
        #expect(try host.service.authorizedLibraryID(for: session) == host.libraryID)
        app.closeAgentContext(); app.closeAgentContext()
        #expect(host.endpoint == nil && app.agentSettings == nil)
        #expect(throws: AgentErrorCode.cancelled) { try host.service.authorizedLibraryID(for: session) }
    }

    @Test func foreignClosedAndUntrackedHostsCannotReplaceTheApplicationContext() throws {
        let f = try Fixture(), other = try Fixture(); defer { f.cleanup(); other.cleanup() }
        let app = try #require(f.app)
        let tracked = try app.agentEditorRegistry(for: f.library)
        let untracked = AgentEditorRegistry(library: f.library, models: { [] })
        let mismatched = try f.host(editors: untracked)
        #expect(throws: AgentErrorCode.invalidInput) { try app.adoptAgentHost(mismatched) }
        mismatched.close()
        let invalid = try f.host()
        tracked.invalidate()
        #expect(throws: AgentErrorCode.invalidInput) { try app.adoptAgentHost(invalid) }
        invalid.close()
        #expect(throws: AgentErrorCode.invalidInput) { try app.adoptAgentHost(invalid) }
        let host = try f.host(); defer { host.close() }
        try f.handToApplication(host)
        let session = try f.session(host), settings = app.agentSettings
        let foreign = try other.host(); defer { foreign.close() }
        #expect(throws: AgentErrorCode.invalidInput) { try app.adoptAgentHost(foreign) }
        #expect(try host.service.authorizedLibraryID(for: session) == host.libraryID)
        #expect(host.endpoint != nil && app.agentSettings === settings)
    }
}
