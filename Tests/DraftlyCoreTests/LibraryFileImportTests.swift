import Foundation
import Testing
@testable import DraftlyCore

@MainActor struct LibraryFileImportTests {
    @Test func failedActionFileRestoresReplacementsAndDoesNotKeepNewActions() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var existing = DraftAction(name: "Original", steps: [ActionStep("script", ["script": "void 0;"])])
        existing.unknownFields["content"] = .string("Future action field café 🐼")
        try library.saveAction(existing)
        let originalID = existing.id
        existing.name = "Replacement"
        let added = DraftAction(name: "New action", steps: [])
        let file = try JSONEncoder().encode([existing, added])
        library.beforeBatchCommit = { throw DraftlyError.message("Injected import failure") }
        #expect(throws: (any Error).self) { try LibraryFileImport.apply(file, fileExtension: "json", to: library) }
        #expect(library.actions.count == 1)
        #expect(library.actions.first?.id == originalID)
        #expect(library.actions.first?.name == "Original")
        #expect(library.actions.first?.steps.first?.values["script"] == "void 0;")
        var commits = 0
        library.beforeBatchCommit = { commits += 1 }
        try LibraryFileImport.apply(file, fileExtension: "json", to: library)
        #expect(commits == 1)
        #expect(Set(library.actions.map(\.name)) == ["Replacement", "New action"])
        #expect(library.actions.first { $0.id == originalID }?.unknownFields["content"] == existing.unknownFields["content"])
    }

    @Test func failedNoteFileRollsBackNotesAndRevisionsAndRetryKeepsConflicts() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = try library.createNote(content: "Current text")
        let notesBefore = library.notes, revisionsBefore = library.revisions.map(\.id)
        let json: [String: Any] = ["drafts": [
            ["uuid": original.id.uuidString, "content": "Backup café 🐼", "tags": ["neutral"], "flag": 7,
             "syntax": "TaskPaper", "createdAt": "2020-01-02T03:04:05Z", "modifiedAt": "2020-02-03T04:05:06Z"],
            ["content": "New text"]
        ]]
        let file = try JSONSerialization.data(withJSONObject: json)
        library.beforeBatchCommit = { throw DraftlyError.message("Injected import failure") }
        #expect(throws: (any Error).self) { try LibraryFileImport.apply(file, fileExtension: "json", to: library) }
        #expect(library.notes == notesBefore)
        #expect(library.revisions.map(\.id) == revisionsBefore)
        var commits = 0
        library.beforeBatchCommit = { commits += 1 }
        try LibraryFileImport.apply(file, fileExtension: "json", to: library)
        #expect(commits == 1)
        #expect(library.notes.count == 3)
        #expect(library.notes.contains(original))
        let copy = try #require(library.notes.first { $0.content == "Backup café 🐼" })
        #expect(copy.id != original.id && copy.tags == ["neutral"] && copy.flag == 7)
        #expect(copy.syntax == "TaskPaper")
        #expect(copy.modifiedAt == ISO8601DateFormatter().date(from: "2020-02-03T04:05:06Z"))
    }

    @Test func duplicateNoteIdentityWithinAFileKeepsDifferentContents() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let id = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["drafts": [
            ["uuid": id, "content": "First"], ["uuid": id, "content": "Second"]
        ]])
        try LibraryFileImport.apply(data, fileExtension: "json", to: library)
        #expect(Set(library.notes.map(\.content)) == ["First", "Second"])
        #expect(Set(library.notes.map(\.id)).count == 2)
    }

    @Test func backupRouteIncludesHistoryAndInvalidBackupCannotFallThroughToText() throws {
        let source = try LibraryStore(inMemory: true, seed: false)
        let note = try source.createNote(content: "Neutral backup")
        var run = ActionRun(actionName: "Neutral", status: "success", message: "Complete")
        run.noteID = note.id; source.log(run)
        let destination = try LibraryStore(inMemory: true, seed: false)
        try LibraryFileImport.apply(source.backupData(), fileExtension: "json", to: destination)
        #expect(destination.notes == source.notes && destination.runs == [run])
        let invalid = Data(#"{"version":99,"revisions":[],"notes":[],"actions":[],"workspaces":[]}"#.utf8)
        #expect(throws: (any Error).self) { try LibraryFileImport.apply(invalid, fileExtension: "txt", to: destination) }
        #expect(destination.notes == source.notes && destination.runs == [run])
    }

    @Test(arguments: [
        #"{"drafts":[{"content":"Must not save"},{"tags":[]}]}"#,
        #"[{"content":"Must not save"},{"tags":[]}]"#,
        #"{"actions":[{"name":"Must not save","steps":[{}]}]}"#,
        #"{"name":"Must not save","steps":[{}]}"#
    ])
    func recognizedInvalidJSONCannotFallThroughToPlainText(json: String) throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Keep café 🐼")
        let before = try library.backupData()
        #expect(throws: (any Error).self) {
            try LibraryFileImport.apply(Data(json.utf8), fileExtension: "txt", to: library)
        }
        #expect(try library.backupData() == before)
    }

    @Test func invalidSecondFileDoesNotKeepTheFirstFilesReplacementsOrNewRecords() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = DraftAction(name: "Keep action café 🐼", steps: [])
        try library.saveAction(original)
        _ = try library.createNote(content: "Keep note")
        let before = try library.backupData()
        var replacement = original; replacement.name = "Must not replace"
        let added = DraftAction(name: "Must not add", steps: [])
        let files = [LibraryFileImport.File(data: try JSONEncoder().encode([replacement, added]), fileExtension: "json"),
            .init(data: Data(#"{"drafts":[{"tags":[]}]}"#.utf8), fileExtension: "txt")]
        #expect(throws: (any Error).self) { try LibraryFileImport.apply(files, to: library) }
        #expect(try library.backupData() == before)
    }

    @Test func failedMultiFileCommitKeepsDiskStateAndRetryCommitsOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var library: LibraryStore? = try LibraryStore(directory: directory, seed: false)
        let original = DraftAction(name: "Original", steps: [])
        try library?.saveAction(original)
        var replacement = original; replacement.name = "Replacement"
        let files = [LibraryFileImport.File(data: Data(#"{"drafts":[{"content":"Imported café 🐼","tags":["neutral"],"flag":7,"syntax":"TaskPaper","modifiedAt":"2020-02-03T04:05:06Z"}]}"#.utf8), fileExtension: "json"),
            .init(data: try JSONEncoder().encode(replacement), fileExtension: "json")]
        let before = try #require(library).backupData()
        library?.beforeBatchCommit = { throw DraftlyError.message("Injected import commit failure") }
        #expect(throws: (any Error).self) { try LibraryFileImport.apply(files, to: #require(library)) }
        #expect(try library?.backupData() == before)
        library = nil
        let reopened = try LibraryStore(directory: directory, seed: false)
        #expect(try reopened.backupData() == before)
        var commits = 0
        reopened.beforeBatchCommit = { commits += 1 }
        try LibraryFileImport.apply(files, to: reopened)
        #expect(commits == 1)
        #expect(reopened.actions.first?.id == original.id && reopened.actions.first?.name == replacement.name)
        let note = try #require(reopened.notes.first)
        #expect(note.content == "Imported café 🐼" && note.tags == ["neutral"] && note.flag == 7 && note.syntax == "TaskPaper")
        #expect(note.modifiedAt == ISO8601DateFormatter().date(from: "2020-02-03T04:05:06Z"))
        #expect(reopened.revisions.filter { $0.noteID == note.id }.count == 1)
    }

    @Test(arguments: [false, true])
    func multiFileBackupPreservesAllCollectionsAndCommitsNoPartialGraph(failCommit: Bool) throws {
        let note = Note(content: "Backup café 🐼")
        let action = DraftAction(name: "Related action", steps: [])
        var run = ActionRun(actionName: action.name, status: "success", message: "Retained")
        run.noteID = note.id; run.actionID = action.id
        let syntax = try SyntaxDefinition(data: Data(#"{"name":"Batch syntax","patterns":[],"navigationPatterns":[],"linkDefinitions":[],"taskMarkDefinitions":[],"indentationPatterns":[]}"#.utf8))
        let backup = Backup(notes: [note], revisions: [Revision(noteID: note.id, content: note.content)],
            workspaces: [Workspace(name: "Batch workspace")], actions: [action],
            actionGroups: [ActionGroupRecord(name: "Batch group")], syntaxes: [syntax],
            themes: [EditorThemeDefinition(name: "Batch theme")], runs: [run])
        let files = [LibraryFileImport.File(data: try JSONEncoder().encode(backup), fileExtension: "json"),
            .init(data: Data("Additional text".utf8), fileExtension: "txt")]
        let destination = try LibraryStore(inMemory: true, seed: false)
        let before = try destination.backupData()
        var commits = 0
        destination.beforeBatchCommit = {
            commits += 1
            if failCommit { throw DraftlyError.message("Injected graph commit failure") }
        }
        if failCommit {
            #expect(throws: (any Error).self) { try LibraryFileImport.apply(files, to: destination) }
            #expect(try destination.backupData() == before)
        } else {
            try LibraryFileImport.apply(files, to: destination)
            #expect(destination.notes.contains(note) && destination.notes.contains { $0.content == "Additional text" })
            #expect(destination.revisions.contains(backup.revisions[0]))
            #expect(destination.actions == backup.actions && destination.workspaces == backup.workspaces)
            #expect(destination.actionGroups == backup.actionGroups && destination.syntaxes == backup.syntaxes)
            #expect(destination.themes == backup.themes && destination.runs == backup.runs)
        }
        #expect(commits == 1)
    }

    @Test func textAndMalformedJSONKeepTheirDistinctRoutes() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let text = "Neutral café 🐼\nSecond line"
        try LibraryFileImport.apply(Data(text.utf8), fileExtension: "txt", to: library)
        #expect(library.notes.first?.content == text)
        #expect(throws: (any Error).self) { try LibraryFileImport.apply(Data("{broken".utf8), fileExtension: "json", to: library) }
        #expect(library.notes.count == 1)
        let unclassified = #"{"shopping":["café 🐼"]}"#
        try LibraryFileImport.apply(Data(unclassified.utf8), fileExtension: "txt", to: library)
        #expect(library.notes.contains { $0.content == unclassified })
    }
}
