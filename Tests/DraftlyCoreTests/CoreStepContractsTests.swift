import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class StepPromptHost: ActionHost {
    var prompt: [String: Any] = [:]
    var cancel = false
    var button = 0
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        guard operation == "prompt" else { throw DraftlyError.message("Unexpected host call") }
        prompt = values
        return cancel ? nil : ["index": button, "fields": ["text": "Café 🐼"]]
    }
}

@Suite("Core action steps") @MainActor
struct CoreStepContractsTests {
    @Test func createDraftAppliesOptionsWithoutOpeningOrChangingSource() throws {
        let store = try LibraryStore(inMemory: true, seed: false), editor = EditorSession()
        let original = try store.createNote(content: "Source"); editor.load(original)
        editor.selection = NSRange(location: 1, length: 2)
        let runner = ActionRunner(library: store, editor: editor)
        let step = ActionStep("createDraft", ["template": "Café 🐼", "folder": "archive", "flagged": "true", "tags": "One, one, TWO", "grammarType": "TaskPaper", "openInEditor": "false"])
        #expect(runner.run(DraftAction(name: "Create contract", steps: [step])), Comment(rawValue: runner.message ?? ""))
        let created = try #require(store.notes.first { $0.id != original.id })
        #expect(created.isArchived && created.flag == 1 && created.syntax == "TaskPaper")
        #expect(created.tags == ["one", "two"] && created.accessedAt == nil)
        #expect(editor.noteID == original.id && editor.selection == NSRange(location: 1, length: 2))
        #expect(store.notes.first { $0.id == original.id }?.content == "Source")
    }
    @Test func createDraftDefaultsOpenInboxAndFailureDoesNotCreate() throws {
        let store = try LibraryStore(inMemory: true, seed: false), editor = EditorSession(), runner: ActionRunner
        runner = ActionRunner(library: store, editor: editor)
        let source = try store.createNote(content: "Source"); editor.load(source)
        #expect(runner.run(DraftAction(name: "Default create", steps: [ActionStep("createDraft", ["template": "New"])])))
        let created = try #require(store.notes.first { $0.id != source.id })
        #expect(editor.noteID == created.id && created.accessedAt != nil)
        #expect(!created.isArchived && created.flag == 0 && created.syntax == "Markdown" && created.tags.isEmpty)
        #expect(!runner.run(DraftAction(name: "Invalid create", steps: [ActionStep("createDraft", ["location": "missing"])])))
        #expect(store.notes.count == 2)
        store.beforeBatchCommit = { throw DraftlyError.message("Expected storage failure") }
        #expect(!runner.run(DraftAction(name: "Failed create", steps: [ActionStep("createDraft", ["template": "Not saved"])])))
        #expect(store.notes.count == 2 && editor.noteID == created.id)
    }
    @Test func promptChoicesTextAndCustomKeysReachScriptsAndTemplates() throws {
        let store = try LibraryStore(inMemory: true, seed: false), editor = EditorSession(), host = StepPromptHost()
        editor.load(try store.createNote(content: "Source")); host.button = 1
        let runner = ActionRunner(library: store, editor: editor, host: host)
        let action = DraftAction(name: "Prompt contract", steps: [
            ActionStep("prompt", ["key": "choice", "buttons": "First|Second", "includeTextField": "true", "textFieldDefault": "[[title]]", "includeCancelButton": "false"]),
            ActionStep("script", ["script": "if(draft.getTemplateTag('choice_button')!=='Second'||draft.getTemplateTag('choice_text')!=='Café 🐼')throw new Error('tags');"]),
            ActionStep("createDraft", ["template": "[[choice_button]]: [[choice_text]]", "openInEditor": "false"])])
        #expect(runner.run(action), Comment(rawValue: runner.message ?? ""))
        #expect(host.prompt["isCancellable"] as? Bool == false)
        #expect((host.prompt["fields"] as? [[String: Any]])?.first?["value"] as? String == "Source")
        #expect(store.notes.contains { $0.content == "Second: Café 🐼" })
    }
    @Test func promptDefaultsAndCancellationStopLaterSteps() throws {
        let store = try LibraryStore(inMemory: true, seed: false), editor = EditorSession(), host = StepPromptHost()
        editor.load(try store.createNote(content: "Source"))
        let runner = ActionRunner(library: store, editor: editor, host: host)
        #expect(runner.run(DraftAction(name: "Default prompt", steps: [ActionStep("prompt", [:])])) )
        #expect((host.prompt["fields"] as? [[String: Any]])?.isEmpty == true)
        #expect((host.prompt["buttons"] as? [[String: String]])?.first?["title"] == "OK")
        #expect(host.prompt["isCancellable"] as? Bool == true)
        host.cancel = true
        #expect(runner.runResult(DraftAction(name: "Cancel prompt", steps: [ActionStep("prompt", [:]), ActionStep("createDraft", ["template": "Must not exist"])])) == .cancelled)
        #expect(store.notes.count == 1 && editor.content == "Source")
    }
    @Test func restoreFailureRollsBackSyntaxAndDraftRecords() throws {
        let source = try LibraryStore(inMemory: true, seed: false)
        _ = try source.createNote(content: "Backup draft")
        let data = try source.backupData(), destination = try LibraryStore(inMemory: true, seed: false)
        destination.beforeBatchCommit = { throw DraftlyError.message("Expected restore failure") }
        #expect(throws: (any Error).self) { try destination.restore(data) }
        #expect(destination.notes.isEmpty && destination.syntaxes.isEmpty)
        try destination.reload(); #expect(destination.notes.isEmpty)
    }
}
