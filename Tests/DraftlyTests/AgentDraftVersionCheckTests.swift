import Foundation
import Testing
import AgentContracts
@testable import DraftlyCore
@testable import Draftly

@Suite("Agent draft expected-version checks") @MainActor
struct AgentDraftVersionCheckTests {
    @MainActor private final class Fixture {
        let library: LibraryStore
        let preferences: TestPreferences
        let note: Note
        var models: [WindowModel] = []
        lazy var editors = AgentEditorRegistry(library: library, models: { [unowned self] in self.models })
        lazy var reader = AgentDraftReading(library: library, pages: AgentReadPages(now: Date.init, uptime: { ProcessInfo.processInfo.systemUptime }), editors: editors,
            pendingEditorGeneration: { _ in "" })
        init() throws {
            preferences = try TestPreferences(prefix: "Draftly-Agent-Version-")
            library = try LibraryStore(inMemory: true, seed: false)
            note = try library.createNote(content: "Neutral café 🐼")
        }
        func close() { editors.invalidate(); models.removeAll(); preferences.close() }
        func model() -> WindowModel {
            var dependencies = WindowDependencies()
            dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
            let model = WindowModel(library: library, dependencies: dependencies)
            model.editor.load(note, focusEditor: false)
            models.append(model); editors.refreshMembership()
            return model
        }
        func token() throws -> String {
            let request = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "drafts.get",
                targets: [.init(kind: .draft, id: note.id)])
            let grant = AgentGrant(connectionID: UUID(), libraryID: request.libraryID!,
                expiresAt: Date().addingTimeInterval(600), capabilities: [.draftsRead], scope: .library)
            let values = try reader.read(request, parameters: AgentOperationSchemas.validatedParameters(for: request),
                grant: grant, sessionID: UUID())
            guard case .object(let draft) = values["draft"], case .string(let token) = draft["versionToken"] else {
                throw AgentErrorCode.storageError
            }
            return token
        }
    }

    @Test func readVersionChecksTheSameSnapshotWithoutSavingOrSelecting() throws {
        let f = try Fixture(); defer { f.close() }
        let token = try f.token(), before = try f.library.backupData()
        let state = try f.reader.checkedSnapshot(for: f.note.id, expectedVersion: token)
        #expect(state.note == f.note && state.storedNote == f.note)
        #expect(try f.library.backupData() == before)
    }

    @Test func accessDoesNotConflictButStoredMetadataDoes() throws {
        let f = try Fixture(); defer { f.close() }
        let token = try f.token()
        try f.library.recordAccess(f.note.id)
        _ = try f.reader.checkedSnapshot(for: f.note.id, expectedVersion: token)
        var changed = try #require(f.library.notes.first)
        changed.tags = ["new 🐼"]
        try f.library.saveNote(changed)
        #expect(throws: AgentErrorCode.versionConflict) {
            try f.reader.checkedSnapshot(for: f.note.id, expectedVersion: token)
        }
    }

    @Test func pendingTextIsCheckedWithoutHidingAStoredChange() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model()
        model.editor.content = "Pending 🐼"; model.hasUnsavedChanges = true
        let token = try f.token()
        let state = try f.reader.checkedSnapshot(for: f.note.id, expectedVersion: token)
        #expect(state.note.content == "Pending 🐼" && state.storedNote.content == f.note.content)
        var stored = f.note; stored.content = "Concurrent stored text"
        try f.library.saveNote(stored)
        #expect(throws: AgentErrorCode.versionConflict) {
            try f.reader.checkedSnapshot(for: f.note.id, expectedVersion: token)
        }
        #expect(model.editor.content == "Pending 🐼")
    }

    @Test func editingAndRevertingStillInvalidatesTheReadVersion() throws {
        let f = try Fixture(); defer { f.close() }
        let model = f.model(), token = try f.token()
        model.editor.content = "Temporary"
        model.editor.content = f.note.content
        #expect(throws: AgentErrorCode.versionConflict) {
            try f.reader.checkedSnapshot(for: f.note.id, expectedVersion: token)
        }
    }

    @Test func divergentEditorsAndMissingDraftsHaveDistinctErrors() throws {
        let f = try Fixture(); defer { f.close() }
        let first = f.model(), second = f.model(), token = try f.token()
        first.editor.content = "Café"; second.editor.content = "Cafe\u{0301}"
        #expect(throws: AgentErrorCode.editorConflict) {
            try f.reader.checkedSnapshot(for: f.note.id, expectedVersion: token)
        }
        #expect(throws: AgentErrorCode.notFound) {
            try f.reader.checkedSnapshot(for: UUID(), expectedVersion: token)
        }
    }
    @Test func emptyAndOversizedExpectedVersionsAreInvalidInput() throws {
        let f = try Fixture(); defer { f.close() }
        for value in ["", String(repeating: "x", count: 4097)] {
            #expect(throws: AgentErrorCode.invalidInput) {
                try f.reader.checkedSnapshot(for: f.note.id, expectedVersion: value)
            }
        }
    }

}
