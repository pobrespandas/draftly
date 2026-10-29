import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class WritingActionHost: ActionHost {
    var choice: Int? = 0
    var clipboardResult = true
    var promptFields: [String: Any]? = [:]
    var callbackStatus = "success"
    var failingOperation: String?
    var calls: [(String, [String: Any])] = []
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        calls.append((operation, values))
        if operation == failingOperation { throw NSError(domain: "WritingActionHost", code: 1) }
        if operation == "selectPrompt" { return choice.map { ["index": $0] } }
        if operation == "prompt" { return promptFields.map { ["index": 0, "fields": $0] } }
        if operation == "callbackURL" { return ["status": callbackStatus, "parameters": [:]] }
        if operation == "htmlToClipboard" { return clipboardResult }
        return true
    }
}

@Suite("Draftly writing actions") @MainActor
struct OwnWritingActionsTests {
    private func action(_ name: String) throws -> DraftAction {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try #require(ActionImporter.decode(Data(contentsOf: root.appendingPathComponent("website/public/actions/\(name).json"))).first)
    }

    @Test func actionFilesImportIntoLibrary() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["template", "transform", "rich-text", "sort-lines", "append-lines", "markdown-bold", "markdown-italic", "copy-html", "print-pdf", "things-draft", "things-taskpaper", "things-markdown", "add-to-list", "obsidian-save", "obsidian-daily"] {
            let data = try Data(contentsOf: root.appendingPathComponent("website/public/actions/\(name).json"))
            try LibraryFileImport.apply(data, fileExtension: "json", to: library)
        }
        #expect(library.actions.count == 15)
        #expect(library.actions.allSatisfy { $0.unsupportedSteps.isEmpty })
    }

    @Test(arguments: [false, true]) func template(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Hello café 🐼", tags: ["template", "work"])
        let editor = EditorSession(); editor.load(try library.createNote(content: "Original"))
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("template"), runner: runner, worker: asynchronous), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "Hello café 🐼")
        #expect(library.notes.first { $0.id == editor.noteID }?.tags == ["work"])
    }

    @Test(arguments: [false, true]) func transform(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "café 🐼 ok"))
        editor.selection = NSRange(location: 0, length: 4)
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("transform"), runner: runner, worker: asynchronous), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "CAFÉ 🐼 ok")
    }

    @Test(arguments: [false, true]) func richText(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "**café**"))
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("rich-text"), runner: runner, worker: asynchronous), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "htmlToClipboard" })
        #expect((call.1["html"] as? String)?.contains("<meta charset=\"utf-8\">") == true)
        #expect((call.1["html"] as? String)?.contains("<strong>café</strong>") == true)
    }

    @Test(arguments: [false, true]) func noSelectionAndCancellationPreserveText(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "café 🐼"))
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!(await ActionTestExecution.succeeds(try action("transform"), runner: runner, worker: asynchronous)))
        #expect(editor.content == "café 🐼")
        editor.selection = NSRange(location: 0, length: 4); host.choice = nil
        #expect(!(await ActionTestExecution.succeeds(try action("transform"), runner: runner, worker: asynchronous)))
        #expect(editor.content == "café 🐼")
    }

    @Test(arguments: [false, true]) func missingTemplateAndCancellationDoNotCreateDraft(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Original"))
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!(await ActionTestExecution.succeeds(try action("template"), runner: runner, worker: asynchronous)))
        #expect(library.notes.count == 1)
        _ = try library.createNote(content: "Template", tags: ["template"])
        host.choice = nil
        #expect(!(await ActionTestExecution.succeeds(try action("template"), runner: runner, worker: asynchronous)))
        #expect(library.notes.count == 2)
        #expect(editor.content == "Original")
    }

    @Test(arguments: [false, true]) func clipboardFailureIsReported(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "**text**"))
        let host = WritingActionHost(); host.clipboardResult = false
        let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!(await ActionTestExecution.succeeds(try action("rich-text"), runner: runner, worker: asynchronous)))
        #expect(editor.content == "**text**")
    }

    @Test(arguments: [false, true]) func sortLinesAndCancel(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "zebra\nalpha\n"))
        editor.selection = NSRange(location: 0, length: 11)
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("sort-lines"), runner: runner, worker: asynchronous), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "alpha\nzebra\n")
        editor.selection = NSRange(location: 0, length: 11); host.choice = nil
        #expect(!(await ActionTestExecution.succeeds(try action("sort-lines"), runner: runner, worker: asynchronous)))
        #expect(editor.content == "alpha\nzebra\n")
    }

    @Test(arguments: [false, true]) func appendLinesAndCancel(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "café\n🐼\n"))
        editor.selection = NSRange(location: 0, length: 7)
        let host = WritingActionHost(); host.promptFields = ["suffix": "!"]
        let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("append-lines"), runner: runner, worker: asynchronous), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "café!\n🐼!\n")
        editor.selection = NSRange(location: 0, length: 9); host.promptFields = nil
        #expect(!(await ActionTestExecution.succeeds(try action("append-lines"), runner: runner, worker: asynchronous)))
        #expect(editor.content == "café!\n🐼!\n")
    }

    @Test(arguments: ["markdown-bold", "markdown-italic"], [false, true]) func markdownWrap(name: String, worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "café 🐼"))
        editor.selection = NSRange(location: 0, length: 4)
        let runner = ActionRunner(library: library, editor: editor, host: WritingActionHost())
        #expect(await ActionTestExecution.succeeds(try action(name), runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == (name == "markdown-bold" ? "**café** 🐼" : "*café* 🐼"))
    }

    @Test(arguments: [false, true]) func copyHTML(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "**café**"))
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("copy-html"), runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "clipboard" })
        #expect((call.1["text"] as? String)?.contains("<strong>café</strong>") == true)
    }

    @Test(arguments: [false, true]) func printPDF(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "**café**"))
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("print-pdf"), runner: runner, worker: asynchronous), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "print" })
        #expect(call.1["format"] as? String == "html")
        #expect((call.1["text"] as? String)?.contains("<strong>café</strong>") == true)
    }

    @Test(arguments: [false, true]) func thingsDraft(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Buy café & tea\nNotes 🐼"))
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("things-draft"), runner: runner, worker: asynchronous), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "openURL" })
        let address = try #require(call.1["url"] as? String)
        let url = try #require(URLComponents(string: address))
        #expect(url.scheme == "things")
        #expect(url.queryItems?.first { $0.name == "title" }?.value == "Buy café & tea")
        #expect(url.queryItems?.first { $0.name == "notes" }?.value == "Notes 🐼")
    }

    @Test(arguments: [false, true]) func thingsTaskPaperRejectsUnsupportedSyntax(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "- café\n- tea 🐼"))
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("things-taskpaper"), runner: runner, worker: asynchronous), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "openURL" })
        let address = try #require(call.1["url"] as? String)
        let url = try #require(URLComponents(string: address))
        let payload = try #require(url.queryItems?.first { $0.name == "data" }?.value)
        let objects = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [[String: Any]])
        #expect(objects.count == 2)
        #expect((objects[0]["attributes"] as? [String: String])?["title"] == "café")
        host.calls.removeAll()
        editor.load(try library.createNote(content: "Project:\n- item @unknown(today)"))
        #expect(!(await ActionTestExecution.succeeds(try action("things-taskpaper"), runner: runner, worker: asynchronous)))
        #expect(!host.calls.contains { $0.0 == "openURL" })
        editor.load(try library.createNote(content: "- Meet {{date:name+1d}}"))
        #expect(!(await ActionTestExecution.succeeds(try action("things-taskpaper"), runner: runner, worker: asynchronous)))
        #expect(!host.calls.contains { $0.0 == "openURL" })
    }

    @Test(arguments: [false, true]) func taskPaperProjectAndMetadata(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "Project café: @area(Work)\n  Project note\n  Planning:\n    - Buy tea @when(today) @tags(home, work)\n      Task note\n      - Milk @done"))
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("things-taskpaper"), runner: runner, worker: asynchronous), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "openURL" })
        let address = try #require(call.1["url"] as? String)
        let url = try #require(URLComponents(string: address))
        let payload = try #require(url.queryItems?.first { $0.name == "data" }?.value)
        let objects = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [[String: Any]])
        let project = try #require(objects.first?["attributes"] as? [String: Any])
        #expect(project["title"] as? String == "Project café")
        #expect(project["area"] as? String == "Work")
        #expect(project["notes"] as? String == "Project note")
        let items = try #require(project["items"] as? [[String: Any]])
        #expect(items.count == 2 && items[0]["type"] as? String == "heading")
        let task = try #require(items.last?["attributes"] as? [String: Any])
        #expect(task["when"] as? String == "today")
        #expect(task["tags"] as? [String] == ["home", "work"])
        #expect(task["notes"] as? String == "Task note")
        let check = try #require((task["checklist-items"] as? [[String: Any]])?.first?["attributes"] as? [String: Any])
        #expect(check["title"] as? String == "Milk" && check["completed"] as? Bool == true)
    }

    @Test(arguments: [false, true]) func thingsMarkdownOutline(asynchronous: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "@ Work\n# Project café\n> Project note\n## Planning\nBuy tea 🐼\n> First note\n> Second note\n- Milk\n#errand\n:today\n!2026-12-01"))
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("things-markdown"), runner: runner, worker: asynchronous), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "callbackURL" })
        let address = try #require(call.1["url"] as? String)
        let url = try #require(URLComponents(string: address))
        let payload = try #require(url.queryItems?.first { $0.name == "data" }?.value)
        let objects = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [[String: Any]])
        let project = try #require(objects.first?["attributes"] as? [String: Any])
        #expect(project["title"] as? String == "Project café")
        #expect(project["area"] as? String == "Work")
        let items = try #require(project["items"] as? [[String: Any]])
        #expect(items.count == 2)
        let task = try #require(items.last?["attributes"] as? [String: Any])
        #expect(task["notes"] as? String == "First note\nSecond note")
        #expect(task["tags"] as? [String] == ["errand"])
        #expect(task["when"] as? String == "today")
        #expect((task["checklist-items"] as? [[String: Any]])?.count == 1)
    }

    @Test(arguments: [false, true], ["cancelled", "error"]) func thingsMarkdownCallbackFailure(worker: Bool, status: String) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Buy tea"))
        let host = WritingActionHost(); host.callbackStatus = status
        let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!(await ActionTestExecution.succeeds(try action("things-markdown"), runner: runner, worker: worker)))
        #expect(host.calls.contains { $0.0 == "callbackURL" })
    }

    @Test(arguments: [false, true]) func taskPaperMustachePrompt(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "- Meet {{name}}\n{{#bool:extra}}- Follow up{{/extra}}"))
        let host = WritingActionHost(); host.promptFields = ["name": "café", "extra": true]
        let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("things-taskpaper"), runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "openURL" })
        let address = try #require(call.1["url"] as? String)
        let url = try #require(URLComponents(string: address))
        let payload = try #require(url.queryItems?.first { $0.name == "data" }?.value)
        let items = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [[String: Any]])
        #expect(items.count == 2)
        #expect((items.first?["attributes"] as? [String: String])?["title"] == "Meet café")
    }

    @Test(arguments: [false, true]) func cancelledMustacheDoesNotOpenThings(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "- Meet {{name}}"))
        let host = WritingActionHost(); host.promptFields = nil
        let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!(await ActionTestExecution.succeeds(try action("things-taskpaper"), runner: runner, worker: worker)))
        #expect(!host.calls.contains { $0.0 == "openURL" })
        #expect(editor.content == "- Meet {{name}}")
    }

    @Test(arguments: [false, true]) func addToExistingListAndArchiveSource(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let list = try library.createNote(content: "# Shopping", tags: ["list"])
        let source = try library.createNote(content: " café 🐼 \n\ntea")
        let editor = EditorSession(); editor.load(source)
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action("add-to-list"), runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.id == list.id }?.content == "# Shopping\n- [ ] café 🐼\n- [ ] tea")
        #expect(library.notes.first { $0.id == source.id }?.isArchived == true)
    }

    @Test(arguments: [false, true]) func addToNewListAndCancel(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "Tea")
        let editor = EditorSession(); editor.load(source)
        let host = WritingActionHost(); host.promptFields = nil
        let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!(await ActionTestExecution.succeeds(try action("add-to-list"), runner: runner, worker: worker)))
        #expect(library.notes.count == 1 && library.notes.first?.isArchived == false)
        host.promptFields = ["name": "Weekend"]
        #expect(await ActionTestExecution.succeeds(try action("add-to-list"), runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
        let created = try #require(library.notes.first { $0.id != source.id })
        #expect(created.content == "# Weekend\n- [ ] Tea")
        #expect(created.tags == ["list"] && created.isArchived)
        #expect(library.notes.first { $0.id == source.id }?.isArchived == true)
    }

    @Test(arguments: [false, true]) func addToListRejectsEmptyInputAndInvalidName(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "  \n")
        let editor = EditorSession(); editor.load(source)
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!(await ActionTestExecution.succeeds(try action("add-to-list"), runner: runner, worker: worker)))
        #expect(!host.calls.contains { $0.0 == "selectPrompt" })
        #expect(library.notes.first { $0.id == source.id }?.isArchived == false)
        editor.load(try library.createNote(content: "Item")); host.promptFields = ["name": "\n"]
        let before = library.notes.count
        #expect(!(await ActionTestExecution.succeeds(try action("add-to-list"), runner: runner, worker: worker)))
        #expect(library.notes.count == before)
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
    }

    @Test(arguments: [false, true], ["obsidian-save", "obsidian-daily"]) func obsidianExport(worker: Bool, name: String) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "# Meeting café\nNotes 🐼")
        let editor = EditorSession(); editor.load(source)
        let host = WritingActionHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(await ActionTestExecution.succeeds(try action(name), runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "saveFile" })
        #expect(call.1["bookmark"] as? String == "Obsidian Vault")
        #expect(call.1["folder"] as? String == "")
        #expect(call.1["mode"] as? String == (name == "obsidian-save" ? "create" : "append"))
        #expect(call.1["text"] as? String == (name == "obsidian-save" ? "# Meeting café\nNotes 🐼" : "\n\n# Meeting café\nNotes 🐼"))
        if name == "obsidian-save" { #expect(call.1["name"] as? String == "Meeting café.md") }
        else {
            let filename = try #require(call.1["name"] as? String)
            #expect(filename.range(of: #"^\d{4}-\d{2}-\d{2}\.md$"#, options: .regularExpression) != nil)
        }
        #expect(editor.content == source.content)
    }

    @Test(arguments: [false, true], ["obsidian-save", "obsidian-daily"]) func obsidianExportFailurePreservesDraft(worker: Bool, name: String) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "# Keep café\n🐼")
        let editor = EditorSession(); editor.load(source)
        let host = WritingActionHost(); host.failingOperation = "saveFile"
        let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!(await ActionTestExecution.succeeds(try action(name), runner: runner, worker: worker)))
        #expect(editor.content == source.content)
        #expect(library.notes.first { $0.id == source.id }?.isArchived == false)
    }
}
