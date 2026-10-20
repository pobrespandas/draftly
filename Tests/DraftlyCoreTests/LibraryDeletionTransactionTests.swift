import Foundation
import Testing
@testable import DraftlyCore

@Suite("Library deletion transactions") @MainActor
struct LibraryDeletionTransactionTests {
    @Test(arguments: ["action", "workspace"])
    func failedDeletionCannotLeakIntoALaterSaveAndRetryPersists(kind: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try LibraryStore(directory: directory, seed: false)
        let action = DraftAction(name: "Keep café 🐼", steps: [])
        var workspace = Workspace(name: "Keep workspace café 🐼")
        workspace.order = 7; workspace.tagged = true
        try library.saveAction(action); try library.saveWorkspace(workspace)
        var note = try library.createNote(content: "Before")
        func remove() throws {
            if kind == "action" { try library.deleteAction(action.id) }
            else { try library.deleteWorkspace(workspace.id) }
        }
        library.beforeBatchCommit = { throw DraftlyError.message("Injected deletion failure") }
        #expect(throws: (any Error).self) { try remove() }
        #expect(!library.container.viewContext.hasChanges)
        #expect(library.actions.contains(action) && library.workspaces.contains(workspace))
        library.beforeBatchCommit = nil
        note.content = "Unrelated save café 🐼"; try library.saveNote(note)
        let reopened = try LibraryStore(directory: directory, seed: false)
        #expect(reopened.actions.contains(action) && reopened.workspaces.contains(workspace))
        #expect(reopened.notes.contains { $0.id == note.id && $0.content == note.content })
        try remove()
        let final = try LibraryStore(directory: directory, seed: false)
        if kind == "action" {
            #expect(!final.actions.contains { $0.id == action.id })
            #expect(final.workspaces.contains(workspace))
        } else {
            #expect(!final.workspaces.contains { $0.id == workspace.id })
            #expect(final.actions.contains(action))
        }
        #expect(final.notes.contains { $0.id == note.id && $0.content == note.content })
    }
}
