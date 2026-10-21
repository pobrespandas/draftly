import Foundation
import Testing
@testable import DraftlyCore

@Suite("Library persistence") @MainActor
struct LibraryTests {
    @Test func reopenPreservesContentAndRevisions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var library: LibraryStore? = try LibraryStore(directory: folder, seed: false)
        var note = try library!.createNote(content: "# First\nHello 👩🏽‍💻", tags: ["work", "work", "  personal "])
        note.content += "\nSaved"
        try library!.saveNote(note)
        #expect(library!.revisions.count == 2)
        library = nil
        let reopened = try LibraryStore(directory: folder, seed: false)
        #expect(reopened.notes.count == 1)
        #expect(reopened.notes[0].content == note.content)
        #expect(reopened.notes[0].tags == ["personal", "work"])
        #expect(reopened.revisions.contains { $0.content == "# First\nHello 👩🏽‍💻" })
    }

    @Test func archiveTrashAndWorkspaceFilters() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let inbox = try library.createNote(content: "Buy café", tags: ["personal"])
        var archived = try library.createNote(content: "Archived", tags: ["personal"])
        archived.isArchived = true; archived.flag = 2; try library.saveNote(archived)
        var deleted = try library.createNote(content: "Deleted")
        deleted.trashedAt = Date(); try library.saveNote(deleted)
        var workspace = Workspace(name: "Personal")
        #expect(workspace.filter(library.notes).map(\.id) == [inbox.id])
        workspace.folder = .all; workspace.tags = ["personal"]; workspace.query = "cafe"
        #expect(workspace.filter(library.notes).map(\.id) == [inbox.id])
        workspace.query = ""; workspace.folder = .flagged
        #expect(workspace.filter(library.notes).map(\.id) == [archived.id])
        workspace.folder = .trash; workspace.tags = []
        #expect(workspace.filter(library.notes).map(\.id) == [deleted.id])
    }

    @Test func backupRoundTripAndConflictPreservesBothNotes() throws {
        let source = try LibraryStore(inMemory: true, seed: false)
        let note = try source.createNote(content: "Original")
        var workspace = Workspace(name: "Work"); workspace.tags = ["work"]
        try source.saveWorkspace(workspace)
        try source.saveAction(DraftAction(name: "Unknown", steps: [ActionStep("futureStep", ["token": "keep this"])]))
        let data = try source.backupData()
        let destination = try LibraryStore(inMemory: true, seed: false)
        try destination.restore(data)
        #expect(destination.notes == source.notes)
        #expect(destination.revisions == source.revisions)
        #expect(destination.actions == source.actions)
        #expect(destination.workspaces == source.workspaces)
        var changed = note; changed.content = "Local change"; try destination.saveNote(changed)
        try destination.restore(data)
        #expect(Set(destination.notes.map(\.content)) == ["Original", "Local change"])
        let copied = try #require(destination.notes.first { $0.content == "Original" })
        #expect(destination.revisions.contains { $0.noteID == copied.id && $0.content == "Original" })
    }

    @Test func unsupportedBackupVersionLeavesStoreUntouched() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Safe")
        var backup = Backup(notes: [], revisions: [], workspaces: [], actions: []); backup.version = 99
        #expect(throws: (any Error).self) { try library.restore(JSONEncoder().encode(backup)) }
        #expect(library.notes[0].content == "Safe")
    }

    @Test func templatesPreserveUnknownTagsAndEscapeFilename() {
        let note = Note(content: "# A/B:C\nBody", tags: ["work"])
        let rendered = Templates.render("[[title]]|[[body]]|[[selection]]|[[safe_title]]|[[unknown]]", note: note, selection: "chosen")
        #expect(rendered == "# A/B:C|Body|chosen|A-B-C|[[unknown]]")
    }

    @Test func unicodeSelectionUsesUTF16() throws {
        let session = EditorSession(); session.load(Note(content: "a👩🏽‍💻b"))
        session.selection = NSRange(location: 1, length: ("👩🏽‍💻" as NSString).length)
        #expect(session.selectedText == "👩🏽‍💻")
        try session.replace(session.safeSelection, with: "é")
        #expect(session.content == "aéb")
        #expect(throws: (any Error).self) { try session.replace(NSRange(location: 99, length: 1), with: "x") }
    }
    @Test func templateSupportsDraftsDateFormats() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let text = Templates.render("[[date|%Y-%m-%d]]", note: Note(), now: now)
        #expect(text.range(of: "^2023-11-[0-9]{2}$", options: .regularExpression) != nil)
    }
    @Test func taggedFilterSurvivesWorkspaceEncoding() throws {
        let notes = [Note(content: "Tagged", tags: ["work"]), Note(content: "Untagged")]
        var workspace = Workspace(name: "Tagged")
        workspace.folder = .all; workspace.tagged = true
        let restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        #expect(restored.filter(notes).map(\.title) == ["Tagged"])
        workspace.tagged = false
        #expect(workspace.filter(notes).map(\.title) == ["Untagged"])
        workspace.tagged = nil
        #expect(workspace.filter(notes).count == 2)
    }

    @Test func tenThousandNotesAndLargeDocument() throws {
        let notes = (0..<10_000).map { Note(content: "Note \($0)\nSearchable content", tags: $0 % 2 == 0 ? ["even"] : []) }
        var workspace = Workspace(name: "Scale"); workspace.folder = .all; workspace.tags = ["even"]; workspace.query = "Searchable"
        #expect(workspace.filter(notes).count == 5_000)
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.restore(JSONEncoder().encode(Backup(notes: notes, revisions: [], workspaces: [], actions: [])))
        let document = String(repeating: "a", count: 100_000)
        let note = try library.createNote(content: document)
        #expect(library.notes.first { $0.id == note.id }?.content.count == 100_000)
    }

    @Test func markdownEscapesRawHTML() {
        let html = MarkdownRenderer.render("# Heading\n**Bold** and *italic*\n<script>alert(1)</script>\n- item")
        #expect(html.contains("<h1>Heading</h1>"))
        #expect(html.contains("<strong>Bold</strong>"))
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>"))
    }
}
