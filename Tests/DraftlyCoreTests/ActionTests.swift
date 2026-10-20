import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class TestHost: ActionHost {
    var calls: [(String, [String: Any])] = []
    var promptIndex: Int? = 0
    var promptFields: [String: Any] = [:]
    var failOperation: String?
    var credentials: [String: String]?
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        calls.append((operation, values))
        if failOperation == operation { throw DraftlyError.message("Permission denied") }
        switch operation {
        case "getCredential": return credentials
        case "setCredential": credentials = values["values"] as? [String: String]; return true
        case "prompt": return promptIndex.map { ["index": $0, "fields": promptFields] }
        case "selectPrompt": return promptIndex.map { ["index": $0] }
        case "markdown": return MarkdownRenderer.render(values["text"] as? String ?? "")
        default: return true
        }
    }
}

@Suite("Original Drafts actions") @MainActor
struct ActionTests {
    private func fixture(_ id: String) throws -> DraftAction {
        let url = try #require(Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Fixtures"))
        return try #require(ActionImporter.decode(Data(contentsOf: url), source: "https://actions.getdrafts.com/a/" + id).first)
    }
    @Test func createFromOriginalTemplateAction() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "# Meeting\nNotes for [[date|yyyy]]\n<|name>", tags: ["template", "work"])
        let editor = EditorSession(); editor.load(try library.createNote(content: "Source"))
        let host = TestHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = try fixture("1VL")
        #expect(action.configuredValues["templateTag"] == "template")
        #expect(runner.run(action), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content.hasPrefix("Notes for "))
        #expect(editor.selectedText == "<|name>")
        #expect(library.notes.first { $0.id == editor.noteID }?.tags == ["work"])
    }
    @Test func originalAddToListSharesVariablesBetweenStepsAndArchivesSource() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let list = try library.createNote(content: "# Shopping", tags: ["list"])
        let source = try library.createNote(content: "Milk\nEggs")
        let editor = EditorSession(); editor.load(source)
        let host = TestHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(runner.run(try fixture("1Ga")), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.id == list.id }?.content == "# Shopping\n- [ ] Milk\n- [ ] Eggs")
        #expect(library.notes.first { $0.id == source.id }?.isArchived == true)
    }
    @Test func originalTextModifierUsesSelection() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "hello world"))
        editor.selection = NSRange(location: 0, length: 5)
        let host = TestHost(); host.promptIndex = 7
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = try fixture("1Bg")
        #expect(action.shortcut == "t")
        #expect(action.shortcutModifiers == ["option", "shift"])
        #expect(runner.run(action), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "HELLO world")
        #expect(editor.selection == NSRange(location: 5, length: 0))
    }
    @Test func originalCopyRichTextCallsHTMLClipboard() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "# Heading\n**Bold**"))
        let host = TestHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(runner.run(try fixture("1DM")), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "htmlToClipboard" })
        #expect((call.1["html"] as? String)?.contains("<strong>Bold</strong>") == true)
    }
    @Test func originalObsidianExportPreservesBookmarkAndFilename() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "# Meeting\nBody", tags: ["work"]))
        let host = TestHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(runner.run(try fixture("1qn")), Comment(rawValue: runner.message ?? ""))
        let call = try #require(host.calls.first { $0.0 == "saveFile" })
        #expect(call.1["name"] as? String == "Meeting.md")
        #expect(call.1["bookmark"] as? String == "Obsidian Vault")
        #expect(call.1["text"] as? String == "# Meeting\nBody\n\nwork\n")
    }
    @Test func htmlPreviewStepUsesConfiguredMarkdownAndPreservesExplicitHTML() throws {
        let name = "Draftly-HTMLPreview-Step-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("github", forKey: MarkdownPreferences.engineKey)
        defaults.set(#"{"strikethrough":true,"sourcePOS":false}"#, forKey: MarkdownPreferences.githubKey)
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        let source = try library.createNote(content: "~~Café 🐼~~")
        editor.load(source)
        let host = TestHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        runner.markdownDefaults = defaults
        let data = Data(#"{"name":"Preview contract","steps":[{"type":"htmlpreview","data":{"template":"[[draft]]"}}]}"#.utf8)
        let action = try #require(ActionImporter.decode(data).first)
        #expect(runner.run(action), Comment(rawValue: runner.message ?? ""))
        let enabled = try #require(host.calls.last { $0.0 == "htmlPreview" }?.1["html"] as? String)
        #expect(enabled.contains("<del>Café 🐼</del>"))
        defaults.set(#"{"strikethrough":false,"sourcePOS":false}"#, forKey: MarkdownPreferences.githubKey)
        #expect(runner.run(action))
        let disabled = try #require(host.calls.last { $0.0 == "htmlPreview" }?.1["html"] as? String)
        #expect(!disabled.contains("<del>"))
        #expect(editor.content == source.content)
        let html = "<html><body><strong>Neutral café 🐼</strong></body></html>"
        editor.load(try library.createNote(content: html))
        #expect(runner.run(action))
        #expect(host.calls.last { $0.0 == "htmlPreview" }?.1["html"] as? String == html)
    }

    @Test func templateMarkdownPreferencesReachActionStepsAndScripting() throws {
        let name = "Draftly-Template-Step-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("github", forKey: MarkdownPreferences.engineKey)
        defaults.set(#"{"strikethrough":true,"sourcePOS":false}"#, forKey: MarkdownPreferences.githubKey)
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "~~Café 🐼~~"))
        let host = TestHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        runner.markdownDefaults = defaults
        let data = Data(#"{"name":"Template preferences","steps":[{"type":"clipboard","data":{"template":"%%[[draft]]%%"}},{"type":"script","data":{"script":"if (!draft.processTemplate('%%[[draft]]%%').includes('<del>Café 🐼</del>')) throw new Error('Template preferences missing');"}}]}"#.utf8)
        let action = try #require(ActionImporter.decode(data).first)
        #expect(runner.run(action), Comment(rawValue: runner.message ?? ""))
        let html = try #require(host.calls.first { $0.0 == "clipboard" }?.1["text"] as? String)
        #expect(html.contains("<del>Café 🐼</del>"))
    }

    @Test func cancellationDoesNotArchiveOrRunLaterSteps() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Do not archive")
        let editor = EditorSession(); editor.load(note)
        let host = TestHost(); host.promptIndex = nil
        let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!runner.run(try fixture("1Ga")))
        #expect(library.notes.first { $0.id == note.id }?.isArchived == false)
        #expect(library.runs.first?.status == "Cancelled")
        #expect(library.notes.count == 1)
    }
    @Test func unknownStepPreventsAllExecutionAndSurvivesExport() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Safe"))
        let host = TestHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        let data = Data(#"{"name":"Future","steps":[{"type":"clipboard","data":{"template":"[[draft]]"}},{"type":"future","data":{"value":"keep"}}]}"#.utf8)
        let action = try #require(ActionImporter.decode(data).first)
        #expect(!runner.run(action))
        #expect(host.calls.isEmpty)
        #expect(try JSONDecoder().decode(DraftAction.self, from: JSONEncoder().encode(action)).steps[1].values["value"] == "keep")
    }
    @Test func permissionErrorIsLoggedWithoutLosingText() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Before")); editor.content = "Unsaved text"
        let host = TestHost(); host.failOperation = "saveFile"
        let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!runner.run(try fixture("1qn")))
        #expect(library.runs.first?.status == "Error")
        #expect(library.notes[0].content == "Unsaved text")
    }
    @Test func contextFailOnFinalStepIsAnError() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Safe"))
        let runner = ActionRunner(library: library, editor: editor)
        let action = DraftAction(name: "Fail", steps: [ActionStep("script", ["script": "context.fail('Expected failure')"])])
        #expect(!runner.run(action))
        #expect(runner.message == "Expected failure")
    }
    @Test func installationURLPreservesPlusSignsAndRawBrackets() throws {
        let payload = #"{"name":"Test","steps":[{"type":"script","data":{"script":"var x = [1,2]; x[0] + 1;"}}]}"#
        var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "&=?#")
        let encoded = try #require(payload.addingPercentEncoding(withAllowedCharacters: allowed))
        let url = try #require(URL(string: "drafts5://action?data=" + encoded))
        let action = try #require(ActionImporter.installationActions(url).first)
        #expect(action.steps[0].values["script"] == "var x = [1,2]; x[0] + 1;")
    }
    @Test func credentialsStayOutsideLibraryBackups() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Safe"))
        let host = TestHost(); host.promptFields = ["token": "test-secret-value"]
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = DraftAction(name: "Authorize", steps: [ActionStep("script", ["script": "let c = Credential.create('Example', 'Test'); c.addPasswordField('token', 'Token'); if (!c.authorize()) context.cancel();"])])
        #expect(runner.run(action))
        #expect(host.credentials?["token"] == "test-secret-value")
        #expect(!String(decoding: try library.backupData(), as: UTF8.self).contains("test-secret-value"))
    }
    @Test func scriptTemplateTagsReachLaterNativeSteps() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Safe"))
        let host = TestHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = DraftAction(name: "Tags", steps: [ActionStep("script", ["script": "draft.setTemplateTag('result', 'value')"]), ActionStep("clipboard", ["template": "[[result]]"])])
        #expect(runner.run(action))
        #expect(host.calls.first { $0.0 == "clipboard" }?.1["text"] as? String == "value")
    }
    @Test func taskActionsTransformOnlyTheSelectedText() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Header\nMilk\nEggs\nFooter"))
        editor.selection = NSRange(location: 7, length: 9)
        let runner = ActionRunner(library: library, editor: editor)
        #expect(runner.run(DraftAction(name: "Make Tasks", steps: [ActionStep("script", ["script": EditingScripts.makeTasks])])))
        #expect(editor.content == "Header\n- [ ] Milk\n- [ ] Eggs\nFooter")
        editor.selection = NSRange(location: 0, length: 0)
        #expect(runner.run(DraftAction(name: "Toggle Tasks", steps: [ActionStep("script", ["script": EditingScripts.toggleTasks])])))
        #expect(editor.content == "Header\n- [x] Milk\n- [x] Eggs\nFooter")
    }
}
