import Foundation
import Combine
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Authorized agent draft navigation") @MainActor
struct AgentEditorNavigationTests {
    private typealias Fixture = AgentCommandServiceTests.Fixture

    private func version(_ f: Fixture, window: UUID, session: AgentCommandService.Session) throws -> String {
        let values = try f.values("editor.get", session: session, targets: [.init(kind: .window, id: window)])
        guard case .string(let token) = values["versionToken"] else { throw AgentErrorCode.storageError }
        return token
    }

    @Test(arguments: ["previous", "next"], [false, true])
    func navigationUsesListOrderAndRecoversWithoutRepeating(direction: String, dirty: Bool) async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let notes = try ["A café 🐼", "B neutral", "C final"].map { try f.note($0) }
        let source = notes[1], destination = notes[direction == "previous" ? 0 : 2]
        let model = try f.window(source, content: dirty ? "B pending café 🐼" : nil, dirty: dirty)
        model.sort = .title; model.ascending = true
        f.editors = [model]
        let window = try #require(f.editorRegistry.windowSnapshots().first).id
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Navigate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: root))
        f.operations = operations; f.service = try f.makeService()
        defer { operations.cancelAll() }
        var capabilities: Set<AgentCapability> = [.presentUI, .draftsRead, .editorRead]
        if dirty { capabilities.insert(.draftsWrite) }
        let (connection, session) = try f.connect(scope: .resources([.init(kind: .window, id: window),
            .init(kind: .draft, id: source.id), .init(kind: .draft, id: destination.id)]), capabilities: capabilities)
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.navigate",
            targets: [.init(kind: .window, id: window)], expectedVersion: try version(f, window: window, session: session),
            parameters: ["direction": .string(direction)])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else {
            Issue.record("Missing navigation"); return
        }
        f.service.close(session)
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: connection.id).state.isTerminal { await Task.yield() }
        let result = try operations.snapshot(id, connectionID: connection.id)
        #expect(result.state == .succeeded && model.editor.noteID == destination.id)
        #expect(model.editor.content == destination.content && !model.hasUnsavedChanges)
        #expect(f.library.notes.first { $0.id == source.id }?.content == (dirty ? "B pending café 🐼" : source.content))
        #expect(f.library.revisions.contains { $0.noteID == source.id } == dirty)
        #expect(result.effects.first?.resources == [.init(kind: .window, id: window), .init(kind: .draft, id: source.id), .init(kind: .draft, id: destination.id)])
        let reopened = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: root))
        f.operations = reopened; f.service = try f.makeService()
        defer { reopened.cancelAll() }
        model.editor.load(source, focusEditor: false)
        let next = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        guard case .object(let saved) = result.result else { Issue.record("Missing result"); return }
        #expect(try f.send(request, session: next).outcome == .result(.object(saved)))
        #expect(model.editor.noteID == source.id)
    }

    @Test(arguments: ["destination", "destinationDirty", "destinationDirtyReadOnly", "dirty", "storedChange", "edited", "listChange", "composition", "arrangement", "peerConflict", "closed", "revoked", "stopWork"])
    func unsafeNavigationNeverSavesOrChangesSelection(reason: String) async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let source = try f.note("A source"), destination = try f.note("B destination")
        let pending = ["dirty", "destinationDirty", "destinationDirtyReadOnly", "peerConflict"].contains(reason)
        let model = try f.window(source, content: pending ? "A pending" : nil, dirty: pending)
        model.sort = .title; model.ascending = true
        f.editors = [model]
        if reason == "peerConflict" { f.editors.append(try f.window(source, content: "Other pending", dirty: true)) }
        let window = try #require(f.editorRegistry.windowSnapshots().first { $0.draftID == source.id }).id
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall })
        f.operations = operations; f.service = try f.makeService()
        defer { operations.cancelAll() }
        var targets: Set<AgentResourceReference> = [.init(kind: .window, id: window), .init(kind: .draft, id: source.id)]
        if !["destination", "destinationDirty", "destinationDirtyReadOnly"].contains(reason) { targets.insert(.init(kind: .draft, id: destination.id)) }
        let (connection, session) = try f.connect(scope: .resources(targets),
            capabilities: ["peerConflict", "storedChange", "destinationDirty"].contains(reason) ? [.presentUI, .draftsRead, .editorRead, .draftsWrite] : [.presentUI, .draftsRead, .editorRead])
        let token = try version(f, window: window, session: session)
        if reason == "storedChange" { var changed = source; changed.content = "Concurrent stored text"; try f.library.saveNote(changed) }
        if reason == "arrangement" { _ = model.arrangementSession.begin() }
        if reason == "composition" { model.editor.canApplyExternalEdit = { false } }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.navigate",
            targets: [.init(kind: .window, id: window)], expectedVersion: token, parameters: ["direction": .string("next")])
        let reply = try f.send(request, session: session)
        if ["destination", "destinationDirty", "destinationDirtyReadOnly", "dirty", "storedChange", "composition", "arrangement", "peerConflict"].contains(reason) {
            let expected: AgentErrorCode = ["destination", "destinationDirty", "destinationDirtyReadOnly"].contains(reason) ? .notFound : reason == "dirty" ? .permissionDenied
                : reason == "storedChange" ? .versionConflict : reason == "composition" ? .interactionRequired : reason == "arrangement" ? .busy : .editorConflict
            #expect(reply.outcome == .error(expected))
        } else {
            guard case .accepted(let id, _) = reply.outcome else { Issue.record("Missing navigation"); return }
            if reason == "edited" { model.editor.content = "Changed editor" }
            if reason == "listChange" { model.query = "A source" }
            if reason == "closed" { f.editors = [] }
            if reason == "revoked" { _ = try f.connections.revokeFromUserInterface(connection.id) }
            if reason == "stopWork" { f.service.invalidateAll() }
            for _ in 0..<1000 { await Task.yield() }
            if reason != "revoked" { #expect(try operations.snapshot(id, connectionID: connection.id).state == .failed) }
        }
        #expect(model.editor.noteID == source.id)
        #expect(f.library.notes.first { $0.id == destination.id }?.content == destination.content)
        if reason != "storedChange" { #expect(f.library.notes.first { $0.id == source.id }?.content == source.content) }
    }
    @Test func authorityLossAfterSavingCannotLoadTheDestinationOrReplay() async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let source = try f.note("A source"), destination = try f.note("B destination")
        let model = try f.window(source, content: "A pending", dirty: true)
        model.sort = .title; model.ascending = true
        f.editors = [model]
        let window = try #require(f.editorRegistry.windowSnapshots().first).id
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall })
        f.operations = operations; f.service = try f.makeService()
        defer { operations.cancelAll() }
        let (connection, session) = try f.connect(capabilities: [.presentUI, .draftsRead, .editorRead, .draftsWrite])
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.navigate",
            targets: [.init(kind: .window, id: window)], expectedVersion: try version(f, window: window, session: session),
            parameters: ["direction": .string("next")])
        let observation = f.library.$notes.dropFirst().sink { [weak f] notes in
            if notes.contains(where: { $0.id == source.id && $0.content == "A pending" }) { f?.service.invalidateAll() }
        }
        defer { observation.cancel() }
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing navigation"); return }
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: connection.id).state.isTerminal { await Task.yield() }
        let result = try operations.snapshot(id, connectionID: connection.id)
        #expect(result.state == .outcomeUnknown && result.result == nil && result.effects.map(\.outcome) == ["unknown"])
        #expect(model.editor.noteID == source.id)
        #expect(f.library.notes.first { $0.id == source.id }?.content == "A pending")
        #expect(f.library.notes.first { $0.id == destination.id } == destination)
        let next = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        #expect(try f.send(request, session: next).outcome == .error(.outcomeUnknown))
        #expect(model.editor.noteID == source.id)
    }

    @Test func listBoundaryDoesNotSavePendingTextWithReadOnlyAccess() async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("A source"), model = try f.window(note, content: "Pending", dirty: true)
        f.editors = [model]
        let window = try #require(f.editorRegistry.windowSnapshots().first).id
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall })
        f.operations = operations; f.service = try f.makeService()
        defer { operations.cancelAll() }
        let (connection, session) = try f.connect(capabilities: [.presentUI, .draftsRead, .editorRead])
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.navigate",
            targets: [.init(kind: .window, id: window)], expectedVersion: try version(f, window: window, session: session),
            parameters: ["direction": .string("next")])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing navigation"); return }
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: connection.id).state.isTerminal { await Task.yield() }
        #expect(try operations.snapshot(id, connectionID: connection.id).state == .succeeded)
        #expect(model.editor.noteID == note.id && model.editor.content == "Pending" && model.hasUnsavedChanges)
        #expect(f.library.notes == [note] && f.library.revisions.isEmpty)
    }

}
