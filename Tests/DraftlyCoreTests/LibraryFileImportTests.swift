import Foundation
import Testing
@testable import DraftlyCore

@MainActor struct LibraryFileImportTests {
    @Test func failedActionFileRestoresReplacementsAndDoesNotKeepNewActions() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var existing = DraftAction(name: "Original", steps: [ActionStep("script", ["script": "void 0;"])])
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

    @Test func textAndMalformedJSONKeepTheirDistinctRoutes() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let text = "Neutral café 🐼\nSecond line"
        try LibraryFileImport.apply(Data(text.utf8), fileExtension: "txt", to: library)
        #expect(library.notes.first?.content == text)
        #expect(throws: (any Error).self) { try LibraryFileImport.apply(Data("{broken".utf8), fileExtension: "json", to: library) }
        #expect(library.notes.count == 1)
    }
}
