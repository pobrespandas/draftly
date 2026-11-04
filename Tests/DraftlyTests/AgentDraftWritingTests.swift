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
        var onAdmission: (() throws -> Void)?
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
        func writer(resolveSyntax: (([String: AgentJSONValue], UUID) throws -> SyntaxDefinition)? = nil) throws -> AgentDraftWriting {
            try AgentDraftWriting(library: library, libraryID: libraryID, reader: reader, editors: editors, keys: keys,
                now: { [unowned self] in self.wall }, validateAdmission: { [unowned self] in
                    if let error = self.admissionError { throw error }
                    try self.onAdmission?()
                }, resolveSyntax: resolveSyntax ?? { [unowned self] parameters, _ in
                    guard let grant = self.grant else { throw AgentErrorCode.permissionDenied }
                    return try AgentDraftWriting.syntaxDefinition(parameters, grant: grant, library: self.library)
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
        func token(_ id: UUID? = nil) throws -> String {
            let request = AgentRequest(requestID: UUID(), libraryID: libraryID, operation: "drafts.get", targets: [.init(kind: .draft, id: id ?? note.id)])
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

    @Test(arguments: ["drafts.archive", "drafts.trash", "drafts.restore", "drafts.flag", "drafts.tags", "drafts.syntax"])
    func metadataBatchCommitsAllDraftsAndRecoversWithoutRepeating(operation: String) throws {
        let f = try Fixture(); defer { f.close() }
        var first = f.note; first.isArchived = true; first.trashedAt = f.wall; first.tags = ["keep"]
        let second = Note(content: "Second 語法", tags: ["keep"], isArchived: true, trashedAt: f.wall)
        try f.library.saveNotes([first, second])
        let originalNotes = f.library.notes, originalRevisions = f.library.revisions
        let model = f.model(); model.editor.content = "Pending café 🐼"; model.hasUnsavedChanges = true
        let versions = try [first.id: f.token(first.id), second.id: f.token(second.id)]
        let parameters: [String: AgentJSONValue] = operation == "drafts.flag" ? ["flag": .integer(3)]
            : operation == "drafts.tags" ? ["mode": .string("add"), "tags": .array([.string(" Café "), .string("keep")])]
            : operation == "drafts.syntax" ? ["name": .string("TaskPaper")] : [:]
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: operation,
            targets: [second.id, first.id].map { .init(kind: .draft, id: $0) },
            expectedVersion: try AgentDraftSchemas.expectedVersion(for: versions), parameters: parameters)
        let writer = try f.writer(), ticket = try writer.prepare(intent, connectionID: f.connectionID)
        let request = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: operation,
            targets: intent.targets, expectedVersion: intent.expectedVersion, retryKey: ticket.value, parameters: parameters)
        f.library.beforeBatchCommit = { throw AgentErrorCode.storageError }
        #expect(throws: AgentErrorCode.storageError) { try writer.update(request, connectionID: f.connectionID) }
        #expect(f.library.notes.sorted { $0.id.uuidString < $1.id.uuidString } == originalNotes.sorted { $0.id.uuidString < $1.id.uuidString })
        #expect(f.library.revisions.sorted { $0.id.uuidString < $1.id.uuidString } == originalRevisions.sorted { $0.id.uuidString < $1.id.uuidString })
        #expect(model.editor.content == "Pending café 🐼" && model.hasUnsavedChanges)
        f.library.beforeBatchCommit = nil
        let receipt = try writer.update(request, connectionID: f.connectionID)
        #expect(Set(receipt.resources.map(\.id)) == [first.id, second.id])
        #expect(f.library.notes.first { $0.id == first.id }?.content == "Pending café 🐼")
        #expect(!model.hasUnsavedChanges)
        for note in f.library.notes {
            switch operation {
            case "drafts.archive": #expect(note.isArchived && note.trashedAt == nil)
            case "drafts.trash": #expect(note.isArchived && note.trashedAt == f.wall)
            case "drafts.restore": #expect(note.isArchived && note.trashedAt == nil)
            case "drafts.flag": #expect(note.flag == 3 && note.isArchived)
            case "drafts.syntax": #expect(note.syntax == "TaskPaper")
            case "drafts.tags": #expect(note.tags == TagRules.normalize(["keep", "Café"]))
            default: Issue.record("Unexpected operation")
            }
        }
        var changed = try #require(f.library.notes.first { $0.id == second.id }); changed.flag = 7
        try f.library.saveNote(changed)
        let after = f.library.notes, revisions = f.library.revisions
        #expect(try writer.update(request, connectionID: f.connectionID) == receipt)
        #expect(f.library.notes == after && f.library.revisions == revisions)
    }

    @Test(arguments: ["version", "editor", "revoke", "storage", "pending"])
    func metadataBatchFailuresPreserveAllDraftsAndPendingEdits(boundary: String) throws {
        let f = try Fixture(); defer { f.close() }
        let second = try f.library.createNote(content: "Other")
        let model = f.model(); model.editor.content = "Pending café 🐼"; model.hasUnsavedChanges = true
        let versions = try [f.note.id: f.token(), second.id: f.token(second.id)]
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.flag",
            targets: [f.note.id, second.id].map { .init(kind: .draft, id: $0) },
            expectedVersion: try AgentDraftSchemas.expectedVersion(for: versions), parameters: ["flag": .integer(4)])
        let writer = try f.writer(), ticket = try writer.prepare(intent, connectionID: f.connectionID)
        let request = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: intent.expectedVersion, retryKey: ticket.value, parameters: intent.parameters)
        var expectedNotes = f.library.notes
        if boundary == "version" {
            var changed = second; changed.flag = 1; try f.library.saveNote(changed)
            expectedNotes = f.library.notes
        } else if boundary == "editor" {
            let other = f.model(); other.editor.content = "Conflicting"; other.hasUnsavedChanges = true
        } else {
            f.library.beforeBatchCommit = {
                if boundary == "revoke" { f.grant = nil }
                if boundary == "storage" { throw AgentErrorCode.storageError }
                if boundary == "pending" { model.editor.content = "New edit during commit" }
            }
        }
        let error: AgentErrorCode = boundary == "version" ? .versionConflict
            : boundary == "revoke" ? .permissionDenied : boundary == "storage" ? .storageError : .editorConflict
        #expect(throws: error) { try writer.update(request, connectionID: f.connectionID) }
        #expect(f.library.notes.sorted { $0.id.uuidString < $1.id.uuidString } == expectedNotes.sorted { $0.id.uuidString < $1.id.uuidString })
        #expect(model.editor.content == (boundary == "pending" ? "New edit during commit" : "Pending café 🐼"))
        #expect(model.hasUnsavedChanges)
        let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        #expect(try f.library.mutationReceipt(for: identity, at: f.wall) == nil)
    }

    @Test(arguments: ["name", "source", "identity", "type"])
    func syntaxChangeDuringCommitRollsBackEveryDraft(change: String) throws {
        let f = try Fixture(); defer { f.close() }
        let second = try f.library.createNote(content: "Other syntax target")
        var object = try ScriptSyntax.definition("Plain Text").object
        object["name"] = "QA Café"
        let source = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: object))
        var resolved = source
        let writer = try f.writer(resolveSyntax: { _, _ in resolved })
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.syntax",
            targets: [f.note.id, second.id].map { .init(kind: .draft, id: $0) },
            expectedVersion: try AgentDraftSchemas.expectedVersion(for: [f.note.id: f.token(), second.id: f.token(second.id)]),
            parameters: ["syntaxID": .string(source.id.uuidString)])
        let ticket = try writer.prepare(intent, connectionID: f.connectionID)
        let request = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: intent.expectedVersion, retryKey: ticket.value, parameters: intent.parameters)
        let before = f.library.notes.sorted { $0.id.uuidString < $1.id.uuidString }
        f.library.beforeBatchCommit = {
            var changed = source.object
            if change == "name" { changed["name"] = "Renamed" }
            if change == "source" { changed["future"] = "Changed source" }
            resolved = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: changed),
                type: change == "type" ? "file" : "custom", id: change == "identity" ? UUID() : source.id)
        }
        #expect(throws: AgentErrorCode.versionConflict) { try writer.update(request, connectionID: f.connectionID) }
        #expect(f.library.notes.sorted { $0.id.uuidString < $1.id.uuidString } == before)
        let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        #expect(try f.library.mutationReceipt(for: mutation, at: f.wall) == nil)
    }

    @Test func createPersistsOneDraftWithoutARevisionAndRecoversItsReceipt() throws {
        let f = try Fixture(); defer { f.close() }
        let writer = try f.writer()
        let revisionsBefore = f.library.revisions
        let input = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.create",
            parameters: ["content": .string("Created café 🐼"), "tags": .array([.string("One"), .string("one")]),
                "flag": .integer(2), "folder": .string("archive"), "syntax": .string("Markdown")])
        let ticket = try writer.prepare(input, connectionID: f.connectionID)
        let request = AgentRequest(requestID: input.requestID, libraryID: input.libraryID, operation: input.operation,
            retryKey: ticket.value, parameters: input.parameters)
        let receipt = try writer.update(request, connectionID: f.connectionID)
        let created = try #require(f.library.notes.first(where: { $0.id != f.note.id }))
        #expect(created.content == "Created café 🐼" && created.tags == ["one"])
        #expect(created.flag == 2 && created.isArchived && created.syntax == "Markdown")
        #expect(f.library.revisions == revisionsBefore)
        #expect(receipt.resources.first?.id == created.id)
        #expect(try writer.update(request, connectionID: f.connectionID) == receipt)
        #expect(f.library.notes.filter { $0.content == "Created café 🐼" }.count == 1)
    }

    @Test func failedCreationCanRetryWithoutLeavingADraftOrReceipt() throws {
        let f = try Fixture(); defer { f.close() }
        let writer = try f.writer()
        let input = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.create",
            parameters: ["content": .string("Storage recovery 🐼")])
        let ticket = try writer.prepare(input, connectionID: f.connectionID)
        let signed = AgentRequest(requestID: input.requestID, libraryID: input.libraryID,
            operation: input.operation, retryKey: ticket.value, parameters: input.parameters)
        f.library.beforeBatchCommit = { throw AgentErrorCode.storageError }
        #expect(throws: AgentErrorCode.storageError) { try writer.update(signed, connectionID: f.connectionID) }
        #expect(f.library.notes.count == 1)
        f.library.beforeBatchCommit = nil
        let receipt = try writer.update(signed, connectionID: f.connectionID)
        #expect(try writer.update(signed, connectionID: f.connectionID) == receipt)
        #expect(f.library.notes.count == 2)
    }

    @Test func patchUsesOneUTF16SnapshotAndOneUndoableCommit() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model(), writer = try f.writer()
        let edits: AgentJSONValue = .array([
            .object(["offset": .integer(9), "length": .integer(4), "text": .string("e\u{0301}")]),
            .object(["offset": .integer(0), "length": .integer(8), "text": .string("New")]),
            .object(["offset": .integer(14), "length": .integer(2), "text": .string("🐻")])])
        let input = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.patch",
            targets: [.init(kind: .draft, id: f.note.id)], expectedVersion: try f.token(), parameters: ["edits": edits])
        let ticket = try writer.prepare(input, connectionID: f.connectionID)
        let request = AgentRequest(requestID: input.requestID, libraryID: input.libraryID, operation: input.operation,
            targets: input.targets, expectedVersion: input.expectedVersion, retryKey: ticket.value, parameters: input.parameters)
        let receipt = try writer.update(request, connectionID: f.connectionID)
        #expect(f.library.notes.first?.content.utf8.elementsEqual("New e\u{0301} 🐻".utf8) == true)
        #expect(model.editor.content == "New e\u{0301} 🐻")
        #expect(f.library.notes.first?.scriptMetadata == f.note.scriptMetadata)
        let revisions = f.library.revisions
        #expect(try writer.update(request, connectionID: f.connectionID) == receipt)
        #expect(f.library.revisions == revisions)
        model.editor.performUndo?(false)
        #expect(model.editor.content == f.note.content)
        _ = model.flush()
    }

    @Test func patchRejectsSplitScalarsAndOutOfBoundsWithoutACommit() throws {
        for (offset, length) in [(15, 0), (14, 1), (17, 0), (16, 1)] {
            let f = try Fixture(); defer { f.close() }
            let writer = try f.writer()
            let input = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.patch",
                targets: [.init(kind: .draft, id: f.note.id)], expectedVersion: try f.token(), parameters: ["edits": .array([
                    .object(["offset": .integer(Int64(offset)), "length": .integer(Int64(length)), "text": .string("x")])])])
            #expect(throws: AgentErrorCode.invalidInput) { try writer.prepare(input, connectionID: f.connectionID) }
            let key = try f.keys.issue(input, connectionID: f.connectionID)
            let signed = AgentRequest(requestID: input.requestID, libraryID: input.libraryID, operation: input.operation,
                targets: input.targets, expectedVersion: input.expectedVersion, retryKey: key.value, parameters: input.parameters)
            #expect(throws: AgentErrorCode.invalidInput) { try writer.update(signed, connectionID: f.connectionID) }
            #expect(f.library.notes.first?.content == f.note.content)
        }
    }

    @Test func patchAllowsAnInsertionAtTheEndOfEmptyAndNonemptyDrafts() throws {
        for content in ["", "cafe\u{0301} 🐼"] {
            let f = try Fixture(); defer { f.close() }
            var source = f.note; source.content = content; try f.library.saveNote(source)
            let writer = try f.writer()
            let input = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.patch",
                targets: [.init(kind: .draft, id: source.id)], expectedVersion: try f.token(), parameters: ["edits": .array([
                    .object(["offset": .integer(Int64(content.utf16.count)), "length": .integer(0), "text": .string(" appended")])])])
            let ticket = try writer.prepare(input, connectionID: f.connectionID)
            let signed = AgentRequest(requestID: input.requestID, libraryID: input.libraryID, operation: input.operation,
                targets: input.targets, expectedVersion: input.expectedVersion, retryKey: ticket.value, parameters: input.parameters)
            _ = try writer.update(signed, connectionID: f.connectionID)
            #expect(f.library.notes.first?.content.utf8.elementsEqual((content + " appended").utf8) == true)
        }
    }

    @Test func restoringARevisionUsesItsParentRegardlessOfTargetOrder() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model(), writer = try f.writer()
        let revision = Revision(noteID: f.note.id, content: "Old e\u{0301} 🐼")
        try f.library.saveRevision(revision)
        f.grant = AgentGrant(connectionID: f.connectionID, libraryID: f.libraryID,
            expiresAt: f.wall.addingTimeInterval(3600), capabilities: [.draftsRead, .draftsWrite],
            scope: .resources([.init(kind: .draft, id: f.note.id), .init(kind: .revision, id: revision.id)]))
        let input = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.restoreVersion",
            targets: [.init(kind: .revision, id: revision.id), .init(kind: .draft, id: f.note.id)], expectedVersion: try f.token())
        let key = try writer.prepare(input, connectionID: f.connectionID)
        let signed = AgentRequest(requestID: input.requestID, libraryID: input.libraryID, operation: input.operation,
            targets: input.targets, expectedVersion: input.expectedVersion, retryKey: key.value)
        let receipt = try writer.update(signed, connectionID: f.connectionID)
        #expect(f.library.notes.first?.content.utf8.elementsEqual(revision.content.utf8) == true)
        #expect(f.library.notes.first?.scriptMetadata == f.note.scriptMetadata)
        #expect(model.editor.content.utf8.elementsEqual(revision.content.utf8))
        try AgentDraftSchemas.validateResult(["resource": .object(["id": .string(f.note.id.uuidString),
            "versionToken": .string(try #require(receipt.resources.first?.versionToken))])], for: signed)
        let revisions = f.library.revisions
        #expect(try writer.update(signed, connectionID: f.connectionID) == receipt)
        #expect(f.library.revisions == revisions)
        model.editor.performUndo?(false)
        #expect(model.editor.content == f.note.content)
        _ = model.flush()
    }

    @Test func restorationRollsBackOnSaveFailureAndCanRetryTheSameRequest() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model(), writer = try f.writer()
        let revision = Revision(noteID: f.note.id, content: "Neutral old content")
        try f.library.saveRevision(revision)
        let input = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.restoreVersion",
            targets: [.init(kind: .draft, id: f.note.id), .init(kind: .revision, id: revision.id)], expectedVersion: try f.token())
        let key = try writer.prepare(input, connectionID: f.connectionID)
        let signed = AgentRequest(requestID: input.requestID, libraryID: input.libraryID, operation: input.operation,
            targets: input.targets, expectedVersion: input.expectedVersion, retryKey: key.value)
        f.library.beforeBatchCommit = { throw AgentErrorCode.storageError }
        #expect(throws: AgentErrorCode.storageError) { try writer.update(signed, connectionID: f.connectionID) }
        #expect(model.editor.content == f.note.content && f.library.notes.first?.content == f.note.content)
        f.library.beforeBatchCommit = nil
        let receipt = try writer.update(signed, connectionID: f.connectionID)
        #expect(model.editor.content == revision.content)
        #expect(try writer.update(signed, connectionID: f.connectionID) == receipt)
        _ = model.flush()
    }

    @Test func restorationRejectsASourceChangedAfterResolutionBeforeStaging() throws {
        let f = try Fixture(); defer { f.close() }
        var revision = Revision(noteID: f.note.id, content: "Neutral old revision")
        try f.library.saveRevision(revision)
        let writer = try f.writer()
        let input = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.restoreVersion",
            targets: [.init(kind: .draft, id: f.note.id), .init(kind: .revision, id: revision.id)], expectedVersion: try f.token())
        let key = try writer.prepare(input, connectionID: f.connectionID)
        let signed = AgentRequest(requestID: input.requestID, libraryID: input.libraryID, operation: input.operation,
            targets: input.targets, expectedVersion: input.expectedVersion, retryKey: key.value)
        var admissions = 0
        f.onAdmission = {
            admissions += 1
            if admissions == 2 {
                revision.content = "Concurrent neutral revision"
                try f.library.saveRevision(revision)
            }
        }
        #expect(throws: AgentErrorCode.versionConflict) { try writer.update(signed, connectionID: f.connectionID) }
        #expect(admissions >= 2)
        #expect(f.library.notes.first?.content == f.note.content)
        #expect(f.library.revisions.first { $0.id == revision.id }?.content == revision.content)
    }

    @Test func restorationRejectsARevisionFromAnotherDraft() throws {
        let f = try Fixture(); defer { f.close() }
        let revision = Revision(noteID: UUID(), content: "Unrelated neutral revision")
        try f.library.saveRevision(revision)
        let input = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.restoreVersion",
            targets: [.init(kind: .draft, id: f.note.id), .init(kind: .revision, id: revision.id)], expectedVersion: try f.token())
        #expect(throws: AgentErrorCode.notFound) { try f.writer().prepare(input, connectionID: f.connectionID) }
        #expect(f.library.notes.first?.content == f.note.content)
    }

    @Test func restorationRechecksRevisionScopeAndExistenceBeforeWriting() throws {
        for missing in [false, true] {
            let f = try Fixture(); defer { f.close() }
            let revision = Revision(noteID: f.note.id, content: "Neutral prior version")
            try f.library.saveRevision(revision)
            let writer = try f.writer()
            let input = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.restoreVersion",
                targets: [.init(kind: .draft, id: f.note.id), .init(kind: .revision, id: revision.id)], expectedVersion: try f.token())
            let key = try writer.prepare(input, connectionID: f.connectionID)
            let signed = AgentRequest(requestID: input.requestID, libraryID: input.libraryID, operation: input.operation,
                targets: input.targets, expectedVersion: input.expectedVersion, retryKey: key.value)
            if missing { try f.library.deleteRevision(revision.id) }
            else {
                f.grant = AgentGrant(connectionID: f.connectionID, libraryID: f.libraryID,
                    expiresAt: f.wall.addingTimeInterval(3600), capabilities: [.draftsRead, .draftsWrite],
                    scope: .resources([.init(kind: .draft, id: f.note.id)]))
            }
            #expect(throws: AgentErrorCode.notFound) { try writer.update(signed, connectionID: f.connectionID) }
            #expect(f.library.notes.first?.content == f.note.content)
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
