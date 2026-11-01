import Foundation
import Testing
import AgentContracts
@testable import DraftlyCore
@testable import Draftly

@Suite("Authorized draft update receipts") @MainActor
struct AgentDraftWritingTests {
    @MainActor private final class Fixture {
        let library: LibraryStore
        let note: Note
        let libraryID = UUID(), connectionID = UUID()
        let preferences: TestPreferences
        var models: [WindowModel] = []
        var undo: [ScriptUndoEditorFixture] = []
        var wall = Date(timeIntervalSince1970: 1_700_000_000)
        var ticks: TimeInterval = 100
        var grant: AgentGrant?
        var admissionError: AgentErrorCode?
        lazy var editors = AgentEditorRegistry(library: library, models: { [unowned self] in self.models })
        lazy var reader = AgentDraftReading(library: library,
            pages: AgentReadPages(now: { [unowned self] in self.wall }, uptime: { [unowned self] in self.ticks }),
            editors: editors, pendingEditorGeneration: { _ in "" })
        lazy var keys = AgentRetryKeys(now: { [unowned self] in self.wall }, uptime: { [unowned self] in self.ticks },
            currentGrant: { [unowned self] id in id == self.connectionID ? self.grant : nil }, isLocked: { false })
        init() throws {
            preferences = try TestPreferences(prefix: "Draftly-Agent-Write-")
            library = try LibraryStore(inMemory: true, seed: false)
            var source = Note(content: "Original café 🐼")
            source.scriptMetadata = ["future": "keep"]
            try library.saveNote(source)
            note = try #require(library.notes.first)
            grant = AgentGrant(connectionID: connectionID, libraryID: libraryID,
                expiresAt: wall.addingTimeInterval(3600), capabilities: [.draftsRead, .draftsWrite], scope: .library)
        }
        func close() { undo.forEach { $0.close() }; editors.invalidate(); models.removeAll(); preferences.close() }
        func writer() throws -> AgentDraftWriting {
            try AgentDraftWriting(library: library, libraryID: libraryID, reader: reader, editors: editors, keys: keys,
                now: { [unowned self] in self.wall }, validateAdmission: { [unowned self] in
                    if let error = self.admissionError { throw error }
                })
        }
        func model() -> WindowModel {
            var dependencies = WindowDependencies()
            dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
            let model = WindowModel(library: library, dependencies: dependencies)
            model.editor.load(note, focusEditor: false)
            undo.append(ScriptUndoEditorFixture(NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
                lineSpacing: 2, markdown: false, onChange: { [weak model] in model?.contentChanged() }), content: note.content))
            models.append(model); editors.refreshMembership()
            return model
        }
        func token() throws -> String {
            let request = AgentRequest(requestID: UUID(), libraryID: libraryID, operation: "drafts.get", targets: [.init(kind: .draft, id: note.id)])
            let values = try reader.read(request, parameters: AgentOperationSchemas.validatedParameters(for: request),
                grant: #require(grant), sessionID: UUID())
            guard case .object(let draft) = values["draft"], case .string(let token) = draft["versionToken"] else { throw AgentErrorCode.storageError }
            return token
        }
        func request(_ changes: [String: AgentJSONValue]) throws -> AgentRequest {
            let input = AgentRequest(requestID: UUID(), libraryID: libraryID, operation: "drafts.update",
                targets: [.init(kind: .draft, id: note.id)], expectedVersion: try token(), parameters: ["changes": .object(changes)])
            let key = try keys.issue(input, connectionID: connectionID)
            return AgentRequest(requestID: input.requestID, libraryID: input.libraryID, operation: input.operation,
                targets: input.targets, expectedVersion: input.expectedVersion, retryKey: key.value, parameters: input.parameters)
        }
    }

    @Test func everyUpdateFieldPersistsAndReceiptMatchesTheNextRead() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model(), writer = try f.writer()
        let request = try f.request(["content": .string("Cafe\u{0301} 🐼"), "tags": .array([.string("one"), .string("one")]),
            "flag": .number(3), "syntax": .string("TaskPaper"), "isArchived": .bool(true),
            "trashedAt": .string("2020-02-03T04:05:06Z"), "createdAt": .string("2019-01-01T00:00:00Z"),
            "modifiedAt": .string("2020-02-03T04:05:07Z"), "scriptMetadata": .object(["future": .string("new 🐼")])])
        let receipt = try writer.update(request, connectionID: f.connectionID)
        let stored = try #require(f.library.notes.first)
        #expect(stored.content.utf8.elementsEqual("Cafe\u{0301} 🐼".utf8))
        #expect(stored.tags == ["one"] && stored.flag == 3 && stored.syntax == "TaskPaper" && stored.isArchived)
        #expect(stored.trashedAt == APIValues.parseDate("2020-02-03T04:05:06Z"))
        #expect(stored.createdAt == APIValues.parseDate("2019-01-01T00:00:00Z"))
        #expect(stored.modifiedAt == APIValues.parseDate("2020-02-03T04:05:07Z"))
        #expect(stored.scriptMetadata == ["future": "new 🐼"])
        #expect(model.editor.content.utf8.elementsEqual(stored.content.utf8) && !model.hasUnsavedChanges)
        #expect(try f.token() == receipt.resources.first?.versionToken)
    }

    @Test func lostReplyRecoveryDoesNotRepeatEditsRevisionsOrUndo() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model(), writer = try f.writer(), request = try f.request(["content": .string("Committed 🐼")])
        let first = try writer.update(request, connectionID: f.connectionID), revisions = f.library.revisions
        model.editor.content = "Later user edit"; model.contentChanged()
        let recovered = try writer.update(request, connectionID: f.connectionID)
        #expect(recovered == first && f.library.revisions == revisions)
        #expect(model.editor.content == "Later user edit")
        model.editor.performUndo?(false)
        #expect(model.editor.content == f.note.content)
        _ = model.flush()
    }

    @Test func aFailedStoreLeavesNoReceiptAndTheSameRequestCanRetry() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model(), writer = try f.writer(), request = try f.request(["content": .string("Retry 🐼")])
        f.library.beforeBatchCommit = { throw AgentErrorCode.storageError }
        #expect(throws: AgentErrorCode.storageError) { try writer.update(request, connectionID: f.connectionID) }
        #expect(model.editor.content == f.note.content && !f.undo[0].text.manager.canUndo)
        f.library.beforeBatchCommit = nil
        let receipt = try writer.update(request, connectionID: f.connectionID)
        #expect(receipt.resources.first?.id == f.note.id)
        #expect(f.library.notes.first?.content == "Retry 🐼")
    }

    @Test func aRevokedGrantCannotRecoverAPreviousReceipt() throws {
        let f = try Fixture(); defer { f.close() }
        let writer = try f.writer(), request = try f.request(["flag": .integer(2)])
        _ = try writer.update(request, connectionID: f.connectionID)
        f.grant = nil
        #expect(throws: AgentErrorCode.permissionDenied) { try writer.update(request, connectionID: f.connectionID) }
    }

    @Test func revocationAtTheCommitBoundaryRollsBackTheNoteAndReceipt() throws {
        let f = try Fixture(); defer { f.close() }
        let writer = try f.writer(), request = try f.request(["flag": .integer(2)])
        f.library.beforeBatchCommit = { f.grant = nil }
        #expect(throws: AgentErrorCode.permissionDenied) { try writer.update(request, connectionID: f.connectionID) }
        #expect(f.library.notes.first?.flag == f.note.flag)
        f.library.beforeBatchCommit = nil
    }

    @Test func staleVersionsAndHostFailureStopBeforeStorage() throws {
        let f = try Fixture(); defer { f.close() }
        let writer = try f.writer(), request = try f.request(["flag": .integer(2)])
        var changed = f.note; changed.content = "Concurrent stored text"
        try f.library.saveNote(changed)
        #expect(throws: AgentErrorCode.versionConflict) { try writer.update(request, connectionID: f.connectionID) }
        f.admissionError = .busy
        #expect(throws: AgentErrorCode.busy) { try writer.update(request, connectionID: f.connectionID) }
        #expect(f.library.notes.first?.flag == f.note.flag)
    }
    @Test func aPendingOwnerIsPreservedAndSynchronizedToItsCleanPeer() throws {
        let f = try Fixture(); defer { f.close() }
        let owner = f.model(), peer = f.model(), writer = try f.writer()
        owner.editor.content = "Pending owner text 🐼"; owner.contentChanged()
        let request = try f.request(["flag": .integer(4)])
        let receipt = try writer.update(request, connectionID: f.connectionID)
        #expect(f.library.notes.first?.content == "Pending owner text 🐼")
        #expect(owner.editor.content == peer.editor.content && !owner.hasUnsavedChanges && !peer.hasUnsavedChanges)
        #expect(f.library.notes.first?.scriptMetadata == ["future": "keep"])
        #expect(try f.token() == receipt.resources.first?.versionToken)
        _ = owner.flush(); _ = peer.flush()
    }

    @Test func anEditAtTheCommitBoundaryRollsBackWithoutDiscardingTheNewText() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model(), writer = try f.writer(), request = try f.request(["content": .string("Agent replacement")])
        f.library.beforeBatchCommit = {
            model.editor.content = "New neutral human edit"; model.contentChanged()
        }
        #expect(throws: AgentErrorCode.editorConflict) { try writer.update(request, connectionID: f.connectionID) }
        #expect(f.library.notes.first?.content == f.note.content)
        #expect(model.editor.content == "New neutral human edit" && model.hasUnsavedChanges)
        let ticket = try f.keys.verify(#require(request.retryKey), request: request, connectionID: f.connectionID)
        #expect(try f.library.mutationReceipt(for: .init(requestID: request.requestID,
            connectionHash: ticket.connectionHash, requestHash: ticket.requestHash), at: f.wall) == nil)
        f.library.beforeBatchCommit = nil; _ = model.flush()
    }

    @Test func nullMetadataClearsOnlyTheExplicitNullableFields() throws {
        let f = try Fixture(); defer { f.close() }
        var trashed = f.note; trashed.trashedAt = f.wall.addingTimeInterval(-60)
        try f.library.saveNote(trashed)
        let writer = try f.writer(), request = try f.request(["scriptMetadata": .null, "trashedAt": .null])
        _ = try writer.update(request, connectionID: f.connectionID)
        let stored = try #require(f.library.notes.first)
        #expect(stored.scriptMetadata == nil && stored.trashedAt == nil)
        #expect(stored.content == f.note.content && stored.id == f.note.id)
    }

    @Test func aWrongLibraryOrConnectionCannotExecuteTheSignedRequest() throws {
        let f = try Fixture(); defer { f.close() }
        let writer = try f.writer(), request = try f.request(["flag": .integer(1)])
        let wrongLibrary = AgentRequest(requestID: request.requestID, libraryID: UUID(), operation: request.operation,
            targets: request.targets, expectedVersion: request.expectedVersion, retryKey: request.retryKey, parameters: request.parameters)
        #expect(throws: AgentErrorCode.permissionDenied) { try writer.update(wrongLibrary, connectionID: f.connectionID) }
        #expect(throws: AgentErrorCode.permissionDenied) { try writer.update(request, connectionID: UUID()) }
        let changedInput = AgentRequest(requestID: request.requestID, libraryID: request.libraryID, operation: request.operation,
            targets: request.targets, expectedVersion: request.expectedVersion, retryKey: request.retryKey,
            parameters: ["changes": .object(["flag": .integer(6)])])
        #expect(throws: AgentErrorCode.invalidInput) { try writer.update(changedInput, connectionID: f.connectionID) }
        #expect(f.library.notes.first?.flag == f.note.flag)
    }

    @Test func selectedDraftAuthorityWorksAndCannotBeReusedAfterScopeRemoval() throws {
        let f = try Fixture(); defer { f.close() }
        f.grant = AgentGrant(connectionID: f.connectionID, libraryID: f.libraryID,
            expiresAt: f.wall.addingTimeInterval(3600), capabilities: [.draftsRead, .draftsWrite],
            scope: .resources([.init(kind: .draft, id: f.note.id)]))
        let writer = try f.writer(), request = try f.request(["flag": .integer(2)])
        _ = try writer.update(request, connectionID: f.connectionID)
        #expect(f.library.notes.first?.flag == 2)
        f.grant = AgentGrant(connectionID: f.connectionID, libraryID: f.libraryID,
            expiresAt: f.wall.addingTimeInterval(3600), capabilities: [.draftsRead, .draftsWrite], scope: .resources([]))
        #expect(throws: AgentErrorCode.notFound) { try writer.update(request, connectionID: f.connectionID) }
        let missingKey = AgentRequest(requestID: request.requestID, libraryID: request.libraryID, operation: request.operation,
            targets: request.targets, expectedVersion: request.expectedVersion, parameters: request.parameters)
        #expect(throws: AgentErrorCode.invalidInput) { try writer.update(missingKey, connectionID: f.connectionID) }
    }

}
