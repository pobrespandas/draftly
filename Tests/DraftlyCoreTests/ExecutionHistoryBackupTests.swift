import Foundation
import Testing
@testable import DraftlyCore

@MainActor struct ExecutionHistoryBackupTests {
    private func canonicalRecords(_ data: Data) throws -> Data {
        let decoded = try JSONSerialization.jsonObject(with: data)
        var object = try #require(decoded as? [String: Any])
        for (key, value) in object {
            if let records = value as? [[String: Any]] {
                object[key] = records.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
            }
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

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

    @Test func repeatedSuccessfulConflictRestoreReusesItsGraphAcrossReopenAndAccess() throws {
        let source = try LibraryStore(inMemory: true, seed: false)
        let incoming = try source.createNote(content: "Backup café 🐼")
        source.log(run(noteID: incoming.id))
        let data = try source.backupData()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var destination: LibraryStore? = try LibraryStore(directory: directory, seed: false)
        var current = incoming; current.content = "Current text"
        try destination?.saveNote(current)
        try destination?.restore(data)
        let copy = try #require(destination?.notes.first { $0.id != current.id })
        try destination?.recordAccess(copy.id, at: Date(timeIntervalSince1970: 2_000_000_000))
        let snapshot = try canonicalRecords(#require(destination).backupData())
        destination = nil
        let reopened = try LibraryStore(directory: directory, seed: false)
        try reopened.restore(data)
        #expect(try canonicalRecords(reopened.backupData()) == snapshot)
        var edited = copy; edited.content = "Edited recovery"
        try reopened.saveNote(edited)
        try reopened.restore(data)
        #expect(reopened.notes.count == 3)
        #expect(reopened.notes.contains { $0.id == copy.id && $0.content == edited.content })
        #expect(reopened.notes.contains { $0.id == current.id && $0.content == current.content })
        let afterEdit = try canonicalRecords(reopened.backupData())
        try reopened.restore(data)
        #expect(try canonicalRecords(reopened.backupData()) == afterEdit)
        #expect(reopened.runs.count == 2)
        for recovered in reopened.notes where recovered.id != current.id {
            #expect(reopened.runs.contains { $0.noteID == recovered.id })
            #expect(reopened.revisions.contains { $0.noteID == recovered.id })
        }
    }

    @Test func recoveryDoesNotReuseAnUnrelatedIdenticalNote() throws {
        let source = try LibraryStore(inMemory: true, seed: false)
        let incoming = try source.createNote(content: "Same text café 🐼")
        let destination = try LibraryStore(inMemory: true, seed: false)
        var current = incoming; current.content = "Current text"
        try destination.saveNote(current)
        var unrelated = incoming; unrelated.id = UUID()
        try destination.saveNote(unrelated, preserveRevision: false, preserveDates: true)
        try destination.restore(source.backupData())
        #expect(destination.notes.count == 3)
        #expect(destination.notes.contains(unrelated))
        #expect(destination.notes.filter { $0.content == incoming.content }.count == 2)
        let snapshot = try canonicalRecords(destination.backupData())
        try destination.restore(source.backupData())
        #expect(try canonicalRecords(destination.backupData()) == snapshot)
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

    @Test func failedConflictRestoreKeepsTheExistingGraphOnDiskAndRetryCommitsOnce() throws {
        let source = try LibraryStore(inMemory: true, seed: false)
        let incoming = try source.createNote(content: "Backup café 🐼")
        let incomingRun = run(noteID: incoming.id)
        source.log(incomingRun)
        let data = try source.backupData()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var destination: LibraryStore? = try LibraryStore(directory: directory, seed: false)
        var current = incoming; current.content = "Current café 🐼"
        try destination?.saveNote(current)
        var currentRun = incomingRun; currentRun.message = "Current history"
        destination?.log(currentRun)
        let beforeData = try destination?.backupData()
        let before = try #require(beforeData)
        destination?.beforeBatchCommit = { throw DraftlyError.message("Injected conflict commit failure") }
        #expect(throws: (any Error).self) { try destination?.restore(data) }
        #expect(try destination?.backupData() == before)
        destination = nil

        let reopened = try LibraryStore(directory: directory, seed: false)
        #expect(try reopened.backupData() == before)
        try reopened.restore(data)
        #expect(reopened.notes.count == 2)
        #expect(reopened.runs.count == 2)
        #expect(reopened.runs.contains(currentRun))
        let copy = try #require(reopened.notes.first { $0.content == incoming.content })
        let copiedRun = try #require(reopened.runs.first { $0.id != currentRun.id })
        #expect(copiedRun.noteID == copy.id)
        #expect(copiedRun.message == incomingRun.message)
        let copiedRevisions = reopened.revisions.filter { $0.noteID == copy.id }
        #expect(copiedRevisions.count == source.revisions.count)
        #expect(Set(reopened.revisions.map(\.id)).count == reopened.revisions.count)
        #expect(reopened.notes.contains { $0.id == current.id && $0.content == current.content })
    }

    @Test(arguments: ["notes", "revisions", "workspaces", "actions", "actionGroups", "syntaxes", "themes", "runs"])
    func duplicateBackupIdentitiesAreRejectedBeforeAnyWrite(collection: String) throws {
        let note = Note(content: "Must not be saved")
        let syntax = try SyntaxDefinition(data: Data(#"{"name":"Neutral syntax","patterns":[],"navigationPatterns":[],"linkDefinitions":[],"taskMarkDefinitions":[],"indentationPatterns":[]}"#.utf8))
        let backup = Backup(notes: [note], revisions: [Revision(noteID: note.id, content: note.content)],
            workspaces: [Workspace(name: "Neutral workspace")], actions: [DraftAction(name: "Neutral action", steps: [])],
            actionGroups: [ActionGroupRecord(name: "Neutral group")], syntaxes: [syntax],
            themes: [EditorThemeDefinition(name: "Neutral theme")], runs: [run(noteID: note.id)])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(backup)) as? [String: Any])
        let values = try #require(object[collection] as? [[String: Any]])
        object[collection] = values + values
        let destination = try LibraryStore(inMemory: true, seed: false)
        _ = try destination.createNote(content: "Existing text café 🐼")
        let before = try destination.backupData()
        var commits = 0
        destination.beforeBatchCommit = { commits += 1 }
        #expect(throws: (any Error).self) { try destination.restore(JSONSerialization.data(withJSONObject: object)) }
        #expect(commits == 0)
        #expect(try destination.backupData() == before)
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
