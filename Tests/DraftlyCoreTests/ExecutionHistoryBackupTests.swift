import Foundation
import Testing
@testable import DraftlyCore

@MainActor struct ExecutionHistoryBackupTests {
    private func run(noteID: UUID?, actionID: UUID? = nil, message: String = "Neutral café 🐼\nComplete") -> ActionRun {
        var value = ActionRun(actionName: "Neutral action", status: "success", message: message)
        value.date = Date(timeIntervalSince1970: 1_700_000_000.125)
        value.noteID = noteID; value.actionID = actionID
        return value
    }

    @Test func historyAndUnknownFieldsSurviveBackupAndDiskReopen() throws {
        let source = try LibraryStore(inMemory: true, seed: false)
        let note = try source.createNote(content: "Neutral source")
        let action = DraftAction(name: "Neutral action", steps: [])
        try source.saveAction(action)
        var value = run(noteID: note.id, actionID: action.id)
        value.unknownFields["future"] = .object(["values": .array([.null, .bool(true), .number(12.25), .string("café 🐼")])])
        source.log(value)
        let data = try source.backupData()
        #expect(try JSONDecoder().decode(Backup.self, from: data).runs == [value])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var destination: LibraryStore? = try LibraryStore(directory: directory, seed: false)
        try destination?.restore(data)
        #expect(destination?.runs == [value])
        destination = nil
        let reopened = try LibraryStore(directory: directory, seed: false)
        #expect(reopened.runs == [value])
        #expect(reopened.notes.first?.id == value.noteID)
        #expect(reopened.actions.first?.id == value.actionID)
        try reopened.restore(data)
        #expect(reopened.runs == [value])
    }

    @Test func oldBackupsAndOrphanHistoryDoNotRemoveExistingLogs() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let orphan = run(noteID: UUID(), actionID: UUID())
        library.log(orphan)
        let legacy = Backup(notes: [], revisions: [], workspaces: [], actions: [])
        let legacyData = try JSONEncoder().encode(legacy)
        let object = try #require(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
        #expect(object["runs"] == nil)
        try library.restore(legacyData)
        #expect(library.runs == [orphan])
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.runs == [orphan])
        #expect(restored.notes.isEmpty && restored.actions.isEmpty)
    }

    @Test func conflictingDraftAndRunKeepBothVariantsWithTheRestoredRelationship() throws {
        let source = try LibraryStore(inMemory: true, seed: false)
        let incoming = try source.createNote(content: "Backup text")
        let sourceRun = run(noteID: incoming.id)
        source.log(sourceRun)
        let destination = try LibraryStore(inMemory: true, seed: false)
        var current = incoming; current.content = "Current text"
        try destination.saveNote(current)
        var currentRun = sourceRun; currentRun.message = "Existing history"
        destination.log(currentRun)
        try destination.restore(source.backupData())
        #expect(destination.runs.count == 2)
        #expect(destination.runs.contains(currentRun))
        let restoredNote = try #require(destination.notes.first { $0.content == "Backup text" })
        let restoredRun = try #require(destination.runs.first { $0.message == sourceRun.message })
        #expect(restoredNote.id != current.id)
        #expect(restoredRun.id != currentRun.id)
        #expect(restoredRun.noteID == restoredNote.id)
        #expect(restoredRun.date == sourceRun.date)
    }

    @Test func failedRestoreRollsBackHistoryAndAllOtherWrites() throws {
        let source = try LibraryStore(inMemory: true, seed: false)
        let note = try source.createNote(content: "Incoming")
        source.log(run(noteID: note.id))
        try source.saveTheme(EditorThemeDefinition(name: "Incoming theme"))
        let destination = try LibraryStore(inMemory: true, seed: false)
        let existing = run(noteID: nil, message: "Keep this history")
        destination.log(existing)
        destination.beforeBatchCommit = { throw DraftlyError.message("Injected restore failure") }
        #expect(throws: (any Error).self) { try destination.restore(source.backupData()) }
        #expect(destination.runs == [existing])
        #expect(destination.notes.isEmpty && destination.themes.isEmpty)
    }

    @Test func duplicateExecutionIdentitiesAreRejectedBeforeAnyWrite() throws {
        let value = run(noteID: nil)
        let note = Note(content: "Must not be saved")
        let backup = Backup(notes: [note], revisions: [], workspaces: [], actions: [], runs: [value, value])
        let destination = try LibraryStore(inMemory: true, seed: false)
        #expect(throws: (any Error).self) { try destination.restore(JSONEncoder().encode(backup)) }
        #expect(destination.runs.isEmpty && destination.notes.isEmpty)
    }

    @Test func legacyRunShapeAndDateStrategiesStayCompatible() throws {
        let json = #"{"id":"CAA7908F-9AAF-45DA-900D-C4E070783AA2","date":123.125,"actionName":"Old","status":"future-status","message":"Neutral","future":{"value":9007199254740993}}"#
        let value = try JSONDecoder().decode(ActionRun.self, from: Data(json.utf8))
        #expect(value.noteID == nil && value.actionID == nil)
        #expect(value.date == Date(timeIntervalSinceReferenceDate: 123.125))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var dated = value; dated.date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(try decoder.decode(ActionRun.self, from: encoder.encode(dated)) == dated)
        #expect(try JSONDecoder().decode(ActionRun.self, from: JSONEncoder().encode(value)) == value)
    }
}
