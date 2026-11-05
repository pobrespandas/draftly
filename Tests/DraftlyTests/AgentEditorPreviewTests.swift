import Foundation
import Combine
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Authorized agent editor preview") @MainActor
struct AgentEditorPreviewTests {
    private typealias Fixture = AgentCommandServiceTests.Fixture

    @Test(arguments: [false, true])
    func previewPreservesPendingTextAndRecoversWithoutRepeating(visible: Bool) async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let note = try f.note("Stored café 🐼"), hidden = try f.note("Outside scope")
        let model = try f.window(note, content: "Pending café 🐼", dirty: true)
        let other = try f.window(hidden)
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: {})
        let undo = ScriptUndoEditorFixture(native, content: note.content)
        defer { undo.close() }
        model.editor.synchronizeScriptEdit?()
        #expect(undo.text.manager.canUndo)
        model.showPreview = !visible
        f.editors = [model, other]
        let snapshot = try #require(f.editorRegistry.windowSnapshots().first { $0.draftID == note.id })
        let journal = try AgentOperationJournal(parentDirectory: root)
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall }, journal: journal)
        f.operations = operations; f.service = try f.makeService()
        defer { operations.cancelAll() }
        let (connection, session) = try f.connect(scope: .resources([.init(kind: .window, id: snapshot.id), .init(kind: .draft, id: note.id)]),
            capabilities: [.presentUI, .draftsRead])
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.preview",
            targets: [.init(kind: .window, id: snapshot.id)], parameters: ["visible": .bool(visible)])
        let stored = f.library.notes, versions = f.library.revisions
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else {
            Issue.record("Missing accepted preview"); return
        }
        f.service.close(session)
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: connection.id).state.isTerminal { await Task.yield() }
        #expect(try operations.snapshot(id, connectionID: connection.id).state == .succeeded)
        #expect(model.showPreview == visible && !other.showPreview)
        #expect(model.editor.content == "Pending café 🐼" && model.hasUnsavedChanges)
        #expect(model.editor.safeSelection == snapshot.selection)
        #expect(f.library.notes == stored && f.library.revisions == versions)
        // A retry reports the old result and must not restore the old UI state.
        model.showPreview = !visible
        let reopened = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: root))
        f.operations = reopened; f.service = try f.makeService()
        defer { reopened.cancelAll() }
        let next = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        #expect(try f.send(request, session: next).outcome == .result(.object([
            "windowID": .string(snapshot.id.uuidString), "draftID": .string(note.id.uuidString), "visible": .bool(visible)])))
        #expect(model.showPreview == !visible && f.library.notes == stored)
        #expect(undo.text.manager.canUndo)
        undo.text.manager.undo()
        #expect(model.editor.content == note.content)
        undo.text.manager.redo()
        #expect(model.editor.content == "Pending café 🐼")
    }

    @Test(arguments: ["scope", "windowScope", "capability", "readCapability", "composition", "customPreview", "action", "changed", "edited", "closed", "revoked", "stopWork"])
    func previewRejectsUnsafeOrStaleContexts(decision: String) async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Neutral"), hidden = try f.note("Not authorized")
        let model = try f.window(note)
        f.editors = [model]
        let window = try #require(f.editorRegistry.windowSnapshots().first).id
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall })
        f.operations = operations; f.service = try f.makeService()
        defer { operations.cancelAll() }
        let scope: AgentResourceScope = .resources(decision == "scope" ? [.init(kind: .window, id: window)]
            : decision == "windowScope" ? [.init(kind: .draft, id: note.id)]
            : [.init(kind: .window, id: window), .init(kind: .draft, id: note.id)])
        let (connection, session) = try f.connect(scope: scope,
            capabilities: decision == "capability" ? [.draftsRead] : decision == "readCapability" ? [.presentUI] : [.presentUI, .draftsRead])
        if decision == "action" { model.actionPending = true }
        if decision == "composition" { model.editor.canApplyExternalEdit = { false } }
        if decision == "customPreview" { model.previewHTML = "Other presentation" }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.preview",
            targets: [.init(kind: .window, id: window)], parameters: ["visible": .bool(true)])
        let reply = try f.send(request, session: session)
        if ["scope", "windowScope", "capability", "readCapability", "composition", "customPreview", "action"].contains(decision) {
            let expected: AgentErrorCode = ["scope", "windowScope"].contains(decision) ? .notFound : ["capability", "readCapability"].contains(decision) ? .permissionDenied
                : decision == "composition" ? .interactionRequired : .busy
            #expect(reply.outcome == .error(expected))
        } else {
            guard case .accepted(let id, _) = reply.outcome else { Issue.record("Missing preview"); return }
            if decision == "edited" { model.editor.content = "New pending content" }
            if decision == "closed" { f.editors = [] }
            if decision == "changed" { model.editor.load(hidden, focusEditor: false) }
            if decision == "revoked" { _ = try f.connections.revokeFromUserInterface(connection.id) }
            if decision == "stopWork" { f.service.invalidateAll() }
            for _ in 0..<1000 { await Task.yield() }
            if decision != "revoked" { #expect(try operations.snapshot(id, connectionID: connection.id).state == .failed) }
        }
        #expect(!model.showPreview)
        #expect(f.library.notes.first { $0.id == note.id }?.content == note.content)
    }
    @Test func authorityChangeDuringPresentationReturnsUnknownOutcome() async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Neutral"), model = try f.window(note)
        f.editors = [model]
        let window = try #require(f.editorRegistry.windowSnapshots().first).id
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall })
        f.operations = operations; f.service = try f.makeService()
        defer { operations.cancelAll() }
        let (connection, session) = try f.connect(capabilities: [.presentUI, .draftsRead])
        let observation = model.$showPreview.dropFirst().sink { [weak f] visible in
            if visible { f?.service.invalidateAll() }
        }
        defer { observation.cancel() }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.preview",
            targets: [.init(kind: .window, id: window)], parameters: ["visible": .bool(true)])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else {
            Issue.record("Missing preview"); return
        }
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: connection.id).state.isTerminal { await Task.yield() }
        let result = try operations.snapshot(id, connectionID: connection.id)
        #expect(model.showPreview && result.state == .outcomeUnknown && result.result == nil)
        #expect(result.effects.map(\.outcome) == ["unknown"])
        #expect(f.library.notes == [note])
    }

}
