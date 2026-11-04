import AppKit
import Combine
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Authorized direct editor opening") @MainActor
struct AgentEditorOpeningTests {
    @MainActor private final class Fixture {
        let f: AgentCommandServiceTests.Fixture
        let app: AppController
        let root: URL
        let journal: AgentOperationJournal
        let operations: AgentOperationRegistry
        var models: [WindowModel] = []
        var windows: [NSWindow] = []
        var initialFocus: [ObjectIdentifier: UUID] = [:]
        var opens = 0
        var delayed = false
        var scenes: [UUID] = []
        init() throws {
            let f = try AgentCommandServiceTests.Fixture()
            self.f = f
            let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
            app = AppController(library: f.library, recentDrafts: RecentDraftStore(defaults: defaults))
            f.editorRegistry = try app.agentEditorRegistry(for: f.library)
            root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Open-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            journal = try AgentOperationJournal(parentDirectory: root)
            operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
                validateHost: {}, isLocked: { f.locked }, now: { f.wall }, journal: journal)
            f.operations = operations; f.service = try f.makeService()
            app.openDraftLibrary = { [weak self] id in
                guard let self else { return }
                opens += 1; scenes.append(id)
                if !delayed { attach(id) }
            }
        }
        func existing(_ note: Note, dirty: Bool = false) throws -> WindowModel {
            let model = try f.window(note, content: dirty ? "Pending source café 🐼" : nil, dirty: dirty)
            models.append(model); initialFocus[ObjectIdentifier(model)] = model.editor.focusToken
            app.registerWindow(model)
            return model
        }
        func attach(_ id: UUID) {
            var dependencies = WindowDependencies()
            dependencies.preferences = WindowPreferences(defaults: UserDefaults(suiteName: f.editorDefaultsName)!)
            let model = WindowModel(library: f.library, dependencies: dependencies)
            models.append(model); initialFocus[ObjectIdentifier(model)] = model.editor.focusToken
            let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false; windows.append(window)
            app.registerWindow(model, window: window, requestID: id)
        }
        func snapshot(_ model: WindowModel) throws -> AgentEditorRegistry.WindowSnapshot {
            let values = try f.editorRegistry.windowSnapshots()
            return try #require(values.first { $0.draftID == model.editor.noteID })
        }
        func version(_ id: UUID, session: AgentCommandService.Session) throws -> String {
            guard case .string(let value) = try f.values("editor.get", session: session,
                targets: [.init(kind: .window, id: id)])["versionToken"] else { throw AgentErrorCode.storageError }
            return value
        }
        func wait(_ id: UUID, grant: AgentGrant) async throws -> AgentOperationState {
            for _ in 0..<2000 {
                if let saved = try journal.record(id, grant: grant)?.snapshot,
                   case .object(let fields) = saved, case .string(let raw) = fields["state"],
                   let state = AgentOperationState(rawValue: raw), state.isTerminal { return state }
                await Task.yield()
            }
            throw AgentErrorCode.timeout
        }
        func close() {
            operations.cancelAll(); f.operations?.cancelAll(); app.openDraftLibrary = nil
            for model in models { app.unregisterWindow(model); model.editor.load(Note(), focusEditor: false); model.hasUnsavedChanges = false }
            windows.forEach { $0.close() }
            f.service = nil; f.operations = nil
            f.cleanEditorPreferences()
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func bothFormsPreserveScopeAndRecoverWithoutReopening(newWindow: Bool, dirty: Bool) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, source = try f.note("Source"), target = try f.note("Target café 🐼")
        let current = try fixture.existing(source, dirty: dirty), window = try fixture.snapshot(current).id
        var scope: Set<AgentResourceReference> = [.init(kind: .draft, id: target.id)]
        var capabilities: Set<AgentCapability> = [.presentUI, .draftsRead, .editorRead]
        if !newWindow {
            scope.formUnion([.init(kind: .window, id: window), .init(kind: .draft, id: source.id)])
            if dirty { capabilities.insert(.draftsWrite) }
        }
        let (connection, session) = try f.connect(scope: .resources(scope), capabilities: capabilities)
        let grant = try #require(try f.connections.grantForAuthenticatedConnection(connection.id))
        let parameters: [String: AgentJSONValue] = newWindow ? ["newWindow": .bool(true)] : [
            "windowID": .string(window.uuidString), "expectedWindowVersion": .string(try fixture.version(window, session: session))]
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.open",
            targets: [.init(kind: .draft, id: target.id)], parameters: parameters)
        let tools = try AgentAvailableTools(capabilities: f.values("server.capabilities", session: session),
            schemas: f.values("server.schemas", session: session))
        #expect(tools.definitions.contains { $0.operation == "editor.open" })
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing open operation"); return }
        f.service.close(session)
        #expect(try await fixture.wait(id, grant: grant) == .succeeded)
        let result = try fixture.operations.snapshot(id, connectionID: connection.id)
        guard case .object(let values) = result.result, case .string(let raw) = values["windowID"], let openedID = UUID(uuidString: raw) else {
            Issue.record("Missing window identity"); return
        }
        #expect(result.effects.first?.resources == scope)
        let opened = try #require(fixture.models.first { $0.editor.noteID == target.id })
        #expect((openedID != window) == newWindow && fixture.opens == (newWindow ? 1 : 0))
        #expect(opened.editor.focusToken == fixture.initialFocus[ObjectIdentifier(opened)])
        if newWindow {
            #expect(current.editor.noteID == source.id && current.hasUnsavedChanges == dirty)
            #expect(f.library.notes.first { $0.id == source.id } == source)
        } else {
            #expect(opened === current)
            #expect(f.library.notes.first { $0.id == source.id }?.content == (dirty ? "Pending source café 🐼" : source.content))
        }
        let reopened = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: fixture.root))
        f.operations = reopened; f.service = try f.makeService()
        let next = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        if newWindow {
            #expect(try f.response("editor.get", session: next, targets: [.init(kind: .window, id: openedID)]).outcome == .error(.notFound))
        }
        opened.editor.load(source, focusEditor: false)
        #expect(try f.send(request, session: next).outcome == .result(.object(values)))
        #expect(opened.editor.noteID == source.id && fixture.opens == (newWindow ? 1 : 0))
    }

    @Test func explicitFocusOnTheCurrentDraftDoesNotSavePendingText() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, target = try f.note("Target")
        let model = try fixture.existing(target, dirty: true), window = try fixture.snapshot(model).id
        let before = model.editor.focusToken
        let (connection, session) = try f.connect(scope: .resources([.init(kind: .window, id: window), .init(kind: .draft, id: target.id)]),
            capabilities: [.presentUI, .draftsRead, .editorRead])
        let grant = try #require(try f.connections.grantForAuthenticatedConnection(connection.id))
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.open",
            targets: [.init(kind: .draft, id: target.id)], parameters: ["windowID": .string(window.uuidString),
                "expectedWindowVersion": .string(try fixture.version(window, session: session)), "focus": .bool(true)])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing open operation"); return }
        #expect(try await fixture.wait(id, grant: grant) == .succeeded)
        #expect(model.editor.focusToken != before && model.editor.content == "Pending source café 🐼" && model.hasUnsavedChanges)
        #expect(f.library.notes.contains(target) && f.library.revisions.isEmpty && fixture.opens == 0)
    }

    @Test(arguments: ["targetScope", "windowScope", "sourceScope", "version", "dirty", "edited", "revoked"])
    func existingWindowRejectsUnauthorizedOrStaleReplacement(reason: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, source = try f.note("Source"), target = try f.note("Target")
        let current = try fixture.existing(source, dirty: reason == "dirty"), window = try fixture.snapshot(current).id
        var scope: Set<AgentResourceReference> = [.init(kind: .window, id: window), .init(kind: .draft, id: source.id), .init(kind: .draft, id: target.id)]
        if reason == "targetScope" { scope.remove(.init(kind: .draft, id: target.id)) }
        let (connection, session) = try f.connect(scope: .resources(scope), capabilities: [.presentUI, .draftsRead, .editorRead])
        let grant = try #require(try f.connections.grantForAuthenticatedConnection(connection.id))
        let token = try fixture.version(window, session: session)
        if reason == "windowScope" || reason == "sourceScope" {
            scope.remove(.init(kind: reason == "windowScope" ? .window : .draft, id: reason == "windowScope" ? window : source.id))
            _ = try f.connections.replaceGrantFromUserInterface(connection.id, capabilities: grant.capabilities, scope: .resources(scope))
        }
        let active = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.open",
            targets: [.init(kind: .draft, id: target.id)], parameters: ["windowID": .string(window.uuidString),
                "expectedWindowVersion": .string(reason == "version" ? "stale" : token)])
        let response = try f.send(request, session: active)
        if reason == "edited" || reason == "revoked" {
            guard case .accepted(let id, _) = response.outcome else { Issue.record("Missing open operation"); return }
            if reason == "edited" { current.editor.content = "Changed pending text" }
            else { _ = try f.connections.revokeFromUserInterface(connection.id) }
            #expect(try await fixture.wait(id, grant: grant) == .failed)
        } else {
            let expected: AgentErrorCode = reason == "version" ? .versionConflict : reason == "dirty" ? .permissionDenied : .notFound
            #expect(response.outcome == .error(expected))
        }
        #expect(current.editor.noteID == source.id && fixture.opens == 0)
        #expect(f.library.notes.contains(source) && f.library.notes.contains(target))
    }

    @Test func authorityLossAfterSavingPreventsExistingWindowReplacement() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, source = try f.note("Source"), target = try f.note("Target")
        let model = try fixture.existing(source, dirty: true), window = try fixture.snapshot(model).id
        let (connection, session) = try f.connect(scope: .resources([.init(kind: .window, id: window),
            .init(kind: .draft, id: source.id), .init(kind: .draft, id: target.id)]),
            capabilities: [.presentUI, .draftsRead, .draftsWrite, .editorRead])
        let grant = try #require(try f.connections.grantForAuthenticatedConnection(connection.id))
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.open",
            targets: [.init(kind: .draft, id: target.id)], parameters: ["windowID": .string(window.uuidString),
                "expectedWindowVersion": .string(try fixture.version(window, session: session))])
        let observation = f.library.$notes.dropFirst().sink { [weak f] notes in
            if notes.contains(where: { $0.id == source.id && $0.content == "Pending source café 🐼" }) { f?.service.invalidateAll() }
        }
        defer { observation.cancel() }
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing open operation"); return }
        #expect(try await fixture.wait(id, grant: grant) == .outcomeUnknown)
        #expect(model.editor.noteID == source.id && f.library.notes.contains(target) && fixture.opens == 0)
        #expect(f.library.notes.first { $0.id == source.id }?.content == "Pending source café 🐼")
        let next = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        #expect(try f.send(request, session: next).outcome == .error(.outcomeUnknown))
        #expect(model.editor.noteID == source.id)
    }

    @Test(arguments: ["cancel", "expire", "stopWork"])
    func interruptedCreationCannotLoadALateScene(reason: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, target = try f.note("Allowed café 🐼")
        fixture.delayed = true
        let (connection, session) = try f.connect(scope: .resources([.init(kind: .draft, id: target.id)]), capabilities: [.presentUI, .draftsRead])
        let grant = try #require(try f.connections.grantForAuthenticatedConnection(connection.id))
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.open",
            targets: [.init(kind: .draft, id: target.id)], parameters: ["newWindow": .bool(true)])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing open operation"); return }
        for _ in 0..<1000 where fixture.scenes.isEmpty { await Task.yield() }
        let scene = try #require(fixture.scenes.first)
        if reason == "cancel" {
            #expect(try fixture.operations.cancel(id, connectionID: connection.id))
            #expect(try await fixture.wait(id, grant: grant) == .outcomeUnknown)
        } else if reason == "expire" { f.wall = grant.expiresAt }
        else { f.service.invalidateAll() }
        fixture.attach(scene)
        #expect(try await fixture.wait(id, grant: grant) == .outcomeUnknown)
        #expect(fixture.models.allSatisfy { $0.editor.noteID != target.id } && fixture.opens == 1)
        #expect(f.library.notes.contains(target))
    }
}
