import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class WritingActionHost: ActionHost {
    var choice: Int? = 0
    var clipboardResult = true
    var calls: [(String, [String: Any])] = []
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        calls.append((operation, values))
        if operation == "selectPrompt" { return choice.map { ["index": $0] } }
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
        for name in ["template", "transform", "rich-text"] {
            let data = try Data(contentsOf: root.appendingPathComponent("website/public/actions/\(name).json"))
            try LibraryFileImport.apply(data, fileExtension: "json", to: library)
        }
        #expect(library.actions.count == 3)
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
}
