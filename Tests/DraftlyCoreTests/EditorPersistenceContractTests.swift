import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class EditorPersistenceHost: ActionHost {
    var onClipboard: ((String) throws -> Void)?
    var clipboard = ""

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        guard operation == "clipboard" else {
            throw DraftlyError.message("Unexpected editor contract operation: \(operation)")
        }
        let text = values["text"] as? String ?? ""
        clipboard = text
        try onClipboard?(text)
        return true
    }
}

@Suite("Editor persistence contracts") @MainActor
struct EditorPersistenceContractTests {
    private func setup() throws -> (LibraryStore, EditorSession, EditorPersistenceHost, ActionRunner) {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "🐼 café"))
        editor.selection = NSRange(location: 3, length: 4)
        let host = EditorPersistenceHost()
        return (library, editor, host, ActionRunner(library: library, editor: editor, host: host))
    }

    private func action(_ script: String) -> DraftAction {
        DraftAction(name: "Editor persistence contract", steps: [ActionStep("script", ["script": """
        function check(value,label){if(!value)throw new Error(label);}
        \(script)
        """])])
    }

    @Test func savePersistsPendingTextAndSelectionBeforeTheActionFinishes() throws {
        let (library, editor, host, runner) = try setup()
        let id = try #require(editor.noteID)
        var observed: Note?
        host.onClipboard = { phase in
            if phase == "stage" {
                editor.content = "Pending 🐼\r\n日本語"
                editor.selection = NSRange(location: 8, length: 2)
            } else if phase == "inspect" {
                observed = try #require(library.notes.first { $0.id == id })
            }
        }
        #expect(runner.run(action("""
        app.setClipboard('stage');
        check(editor.save()===undefined,'save returns void');
        app.setClipboard('inspect');
        """)), Comment(rawValue: runner.message ?? ""))
        let storedBeforeCompletion = try #require(observed)
        #expect(storedBeforeCompletion.content == "Pending 🐼\r\n日本語")
        #expect(storedBeforeCompletion.scriptMetadata?["selectionStart"] == "8")
        #expect(storedBeforeCompletion.scriptMetadata?["selectionLength"] == "2")
        #expect(editor.noteID == id)
        #expect(editor.selection == NSRange(location: 8, length: 2))
    }

    @Test func newSavesPendingPreviousTextAndSelectionBeforeLoadingTheBlankDraft() throws {
        let (library, editor, host, runner) = try setup()
        let previousID = try #require(editor.noteID)
        var observedPrevious: Note?
        var observedCurrentID: UUID?
        var observedCurrentText: String?
        var observedCurrentSelection: NSRange?
        host.onClipboard = { phase in
            if phase == "stage" {
                editor.content = "Pending 🐼\nPrevious draft"
                editor.selection = NSRange(location: 8, length: 2)
            } else if phase == "inspect" {
                observedPrevious = try #require(library.notes.first { $0.id == previousID })
                observedCurrentID = editor.noteID
                observedCurrentText = editor.content
                observedCurrentSelection = editor.selection
            }
        }
        #expect(runner.run(action("""
        app.setClipboard('stage');
        check(editor.new()===undefined,'new returns void');
        app.setClipboard('inspect');
        """)), Comment(rawValue: runner.message ?? ""))
        let previousBeforeCompletion = try #require(observedPrevious)
        #expect(previousBeforeCompletion.content == "Pending 🐼\nPrevious draft")
        #expect(previousBeforeCompletion.scriptMetadata?["selectionStart"] == "8")
        #expect(previousBeforeCompletion.scriptMetadata?["selectionLength"] == "2")
        let currentBeforeCompletion = try #require(observedCurrentID)
        #expect(currentBeforeCompletion != previousID)
        #expect(observedCurrentText == "")
        #expect(observedCurrentSelection == NSRange(location: 0, length: 0))
        #expect(library.notes.count == 2)
    }

    @Test func mutationStorageFailuresKeepTheStoredDraftAndPendingSelection() throws {
        let cases: [(script: String, text: String, selection: NSRange)] = [
            ("editor.setText('Pending 🐼')", "Pending 🐼", NSRange(location: 3, length: 4)),
            ("editor.setSelectedText('Pending 🐼')", "🐼 Pending 🐼", NSRange(location: 13, length: 0)),
            ("editor.setTextInRange(3,4,'Pending 🐼')", "🐼 Pending 🐼", NSRange(location: 13, length: 0))
        ]
        for item in cases {
            let (library, editor, host, runner) = try setup()
            let id = try #require(editor.noteID)
            var beforeFailure: Note?
            var revisionsBeforeFailure: [Revision] = []
            host.onClipboard = { phase in
                guard phase == "arm" else { return }
                beforeFailure = try #require(library.notes.first { $0.id == id })
                revisionsBeforeFailure = library.revisions
                library.beforeBatchCommit = { throw DraftlyError.message("Editor mutation storage failure") }
            }
            defer { library.beforeBatchCommit = nil }
            #expect(!runner.run(action("app.setClipboard('arm');\(item.script);app.setClipboard('must not run');")))
            #expect(runner.message?.contains("Editor mutation storage failure") == true)
            #expect(host.clipboard == "arm")
            #expect(editor.noteID == id)
            #expect(editor.content == item.text)
            #expect(editor.selection == item.selection)
            #expect(library.notes.first { $0.id == id } == beforeFailure)
            #expect(library.revisions == revisionsBeforeFailure)
        }
    }

    @Test func saveStorageFailureKeepsStoredContentAndThePendingSelection() throws {
        let (library, editor, host, runner) = try setup()
        let id = try #require(editor.noteID)
        var beforeFailure: Note?
        host.onClipboard = { phase in
            guard phase == "arm" else { return }
            beforeFailure = try #require(library.notes.first { $0.id == id })
            editor.content = "Pending 🐼"
            editor.selection = NSRange(location: 8, length: 2)
            library.beforeBatchCommit = { throw DraftlyError.message("Explicit editor save failure") }
        }
        defer { library.beforeBatchCommit = nil }
        #expect(!runner.run(action("app.setClipboard('arm');editor.save();app.setClipboard('must not run');")))
        #expect(runner.message?.contains("Explicit editor save failure") == true)
        #expect(host.clipboard == "arm")
        #expect(editor.content == "Pending 🐼")
        #expect(editor.selection == NSRange(location: 8, length: 2))
        #expect(library.notes.first { $0.id == id } == beforeFailure)
    }
}
