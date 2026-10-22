import Foundation
import Testing
@testable import DraftlyCore

@Suite("Shared syntax contracts") @MainActor
struct SyntaxDefinitionTests {
    func source() -> [String: Any] {
        ["name": "Three states", "future": ["preserved": true], "patterns": [], "indentationPatterns": [],
         "navigationPatterns": [["match": #"^! (.*)$"#, "rangeCapture": "0", "labelCapture": "1", "level": 2, "prefix": "Section"]],
         "linkDefinitions": [["match": #"(<<)(([^:>]+):([^>]+))(>>)"#, "captures": ["prefix": "1", "link": "2", "key": "3", "value": "4", "suffix": "5"]]],
         "taskMarkDefinitions": [["match": #"(\[(?: |~|x)\])"#, "rangeType": "task", "captures": ["state": "1", "interactive": "1"], "states": ["[ ]", "[~]", "[x]"], "initialState": "[ ]", "completedState": ["[x]"]]]]
    }
    func definition(_ value: [String: Any]? = nil) throws -> SyntaxDefinition {
        try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: value ?? source()))
    }
    @Test func taskSnapshotFieldsHaveExactUTF16Values() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let text = "🐼\r\n- [ ] Café"
        let task = try #require(syntax.tasks(in: text).first)
        #expect(task["line"] as? String == "- [ ] Café")
        #expect(task["lineRange"] as? [Int] == [4, 10])
        #expect(task["label"] as? String == "Café")
        #expect(task["labelRange"] as? [Int] == [10, 4])
        #expect(task["state"] as? String == "[ ]")
        #expect(task["stateRange"] as? [Int] == [6, 3])
        #expect(task["interactive"] as? String == "[ ]")
        #expect(task["interactiveRange"] as? [Int] == [6, 3])
        #expect(task["isCompleted"] as? Bool == false)
        #expect(syntax.tasks(in: "").isEmpty)
        #expect(try ScriptSyntax.definition("Plain Text").tasks(in: text).isEmpty)
        let completed = try #require(syntax.tasks(in: "[X]").first)
        #expect(completed["isCompleted"] as? Bool == true)
        #expect(try syntax.taskChange(in: "[X]", task: completed, operation: "advance").1 == "[ ]")
    }
    @Test func markerAndLinkSnapshotFieldsUseCaptures() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let marker = try #require(syntax.markers(in: "🐼\n## Café").first)
        #expect(marker["label"] as? String == "Café")
        #expect(marker["prefix"] as? String == "H2")
        #expect(marker["location"] as? Int == 3)
        #expect(marker["length"] as? Int == 7)
        #expect(marker["level"] as? Int == 1)
        let link = try #require(syntax.links(in: "🐼 [[d:Café]]").first)
        #expect(link["key"] as? String == "d")
        #expect(link["value"] as? String == "Café")
        #expect(link["link"] as? String == "d:Café")
        #expect(link["prefix"] as? String == "[[")
        #expect(link["suffix"] as? String == "]]")
        #expect(link["location"] as? Int == 3)
        #expect(link["length"] as? Int == 10)
        #expect(syntax.markers(in: "").isEmpty && syntax.links(in: "").isEmpty)
    }
    @Test func customTasksCycleUseUTF16AndRejectStaleRanges() throws {
        let syntax = try definition(), text = "🐼 [ ] one [~] two [x] three\r\n"
        let tasks = syntax.tasks(in: text)
        #expect(tasks.count == 3)
        #expect(tasks[0]["stateRange"] as? [Int] == [3, 3])
        #expect(tasks[2]["isCompleted"] as? Bool == true)
        for (index, expected) in ["[~]", "[x]", "[ ]"].enumerated() {
            #expect(try syntax.taskChange(in: text, task: tasks[index], operation: "advance").1 == expected)
        }
        #expect(try syntax.taskChange(in: text, task: tasks[1], operation: "reset").1 == "[ ]")
        #expect(try syntax.taskChange(in: text, task: tasks[0], operation: "complete").1 == "[x]")
        #expect(throws: (any Error).self) { try syntax.taskChange(in: "changed", task: tasks[0], operation: "complete") }
    }
    @Test func markersLinksAndUnknownFieldsSurviveBackup() throws {
        let store = try LibraryStore(inMemory: true, seed: false), value = try definition()
        try store.saveSyntax(value)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(store.backupData())
        #expect(restored.syntaxes == [value])
        let syntax = try restored.syntaxDefinition(named: value.name)
        #expect((syntax.object["future"] as? [String: Bool])?["preserved"] == true)
        let markers = syntax.markers(in: "🐼\n! Café\n")
        #expect(markers[0]["location"] as? Int == 3)
        #expect(markers[0]["label"] as? String == "Café")
        #expect(markers[0]["level"] as? Int == 2)
        let links = syntax.links(in: "🐼 <<note:café>>")
        #expect(links[0]["location"] as? Int == 3)
        #expect(links[0]["key"] as? String == "note")
        #expect(links[0]["value"] as? String == "café")
        #expect(links[0]["prefix"] as? String == "<<")
    }
    @Test func invalidDefinitionsAndStorageFailuresDoNotInstall() throws {
        var invalid = source(); invalid["navigationPatterns"] = [["match": "[", "rangeCapture": "0"]]
        #expect(throws: (any Error).self) { try definition(invalid) }
        invalid = source(); invalid["navigationPatterns"] = [["match": "(a)", "rangeCapture": "2"]]
        #expect(throws: (any Error).self) { try definition(invalid) }
        invalid = source(); invalid["taskMarkDefinitions"] = [["match": "a", "states": []]]
        #expect(throws: (any Error).self) { try definition(invalid) }
        let store = try LibraryStore(inMemory: true, seed: false)
        store.beforeBatchCommit = { throw DraftlyError.message("Expected storage failure") }
        #expect(throws: (any Error).self) { try store.saveSyntax(definition()) }
        #expect(store.syntaxes.isEmpty)
    }
    @Test func omittedTaskDefaultsAndTaskPaperDatedCompletion() throws {
        var value = source(), rules = try #require(value["taskMarkDefinitions"] as? [[String: Any]])
        rules[0].removeValue(forKey: "initialState"); rules[0].removeValue(forKey: "completedState"); value["taskMarkDefinitions"] = rules
        let syntax = try definition(value), task = try #require(syntax.tasks(in: "[~]").first)
        #expect(try syntax.taskChange(in: "[~]", task: task, operation: "complete").1 == "[x]")
        let paper = try ScriptSyntax.definition("TaskPaper"), text = "- Café @done(2026-10-19)"
        let completed = try #require(paper.tasks(in: text).first)
        #expect(completed["isCompleted"] as? Bool == true)
        let change = try paper.taskChange(in: text, task: completed, operation: "advance")
        #expect((text as NSString).replacingCharacters(in: change.0, with: change.1) == "- Café")
    }
    @Test func scriptingAndNativeAnalysisUseTheSameDefinition() throws {
        let store = try LibraryStore(inMemory: true, seed: false), syntax = try definition()
        try store.saveSyntax(syntax)
        var note = try store.createNote(content: "! Café\n🐼 [ ] one [~] two\n<<note:café>>")
        note.syntax = syntax.name; try store.saveNote(note)
        let editor = EditorSession(); editor.load(note)
        let runner = ActionRunner(library: store, editor: editor)
        let action = DraftAction(name: "Custom syntax contract", steps: [ActionStep("script", ["script": """
        function check(v){if(!v)throw new Error('contract');}
        check(Syntax.find('custom','Three states').name==='Three states');
        check(draft.tasks.length===2 && editor.tasks.length===2);check(Object.isFrozen(editor.tasks[0]));
        check(draft.navigationMarkers[0].label==='Café' && editor.navigationMarkers[0].label==='Café');
        check(draft.linkedItems[0].value==='café');
        let originalTask=editor.tasks[0];check(editor.advanceTask(originalTask)===true);check(draft.tasks[0].state==='[~]');check(editor.advanceTask(originalTask)===false);
        check(editor.completeTask(editor.tasks[1])===true);check(draft.completedTasks.length===1);check(draft.syntax.type==='custom');
        """])])
        #expect(runner.run(action), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content.contains("[~] one [x] two"))
    }
    @Test func fileSyntaxReloadsChangesAndKeepsPermissionsOutsideBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Test.draftsSyntax")
        var object = source(); try JSONSerialization.data(withJSONObject: object).write(to: url)
        let syntax = try SyntaxDefinition(data: Data(contentsOf: url), type: "file")
        let defaults = try #require(UserDefaults(suiteName: "DraftlySyntaxTest-" + UUID().uuidString))
        try SyntaxFileAccess.register(url, id: syntax.id, defaults: defaults)
        object["future"] = ["updated": true]; try JSONSerialization.data(withJSONObject: object).write(to: url)
        let updated = try SyntaxFileAccess.read(syntax, defaults: defaults)
        #expect((updated.object["future"] as? [String: Bool])?["updated"] == true)
        #expect(updated.id == syntax.id && updated.type == "file")
        defaults.removeObject(forKey: "syntax.file." + syntax.id.uuidString)
        #expect(throws: (any Error).self) { try SyntaxFileAccess.read(syntax, defaults: defaults) }
        #expect(!String(decoding: try JSONEncoder().encode(syntax), as: UTF8.self).contains(directory.path))
    }
    @Test func fileSyntaxInstallationRetainsPreviousBookmarkOnStorageFailureAndRetries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "Draftly-SyntaxInstall-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = try LibraryStore(inMemory: true, seed: false)
        let originalURL = directory.appendingPathComponent("Original.draftsSyntax")
        let replacementURL = directory.appendingPathComponent("Replacement.draftsSyntax")
        var originalObject = source(); originalObject["future"] = ["version": "original"]
        let originalData = try JSONSerialization.data(withJSONObject: originalObject)
        try originalData.write(to: originalURL)
        let original = try SyntaxDefinition(data: originalData, type: "file")
        try SyntaxFileAccess.install(original, from: originalURL, in: store, defaults: defaults)
        let key = "syntax.file." + original.id.uuidString
        let bookmark = try #require(defaults.data(forKey: key))
        var replacementObject = source(); replacementObject["future"] = ["version": "replacement"]
        let replacementData = try JSONSerialization.data(withJSONObject: replacementObject)
        try replacementData.write(to: replacementURL)
        let replacement = try SyntaxDefinition(data: replacementData, type: "file", id: original.id)
        store.beforeBatchCommit = { throw DraftlyError.message("Expected storage failure") }
        #expect(throws: (any Error).self) {
            try SyntaxFileAccess.install(replacement, from: replacementURL, in: store, defaults: defaults)
        }
        #expect(store.syntaxes == [original] && defaults.data(forKey: key) == bookmark)
        #expect(try SyntaxFileAccess.read(original, defaults: defaults).source == original.source)
        let newID = UUID()
        var freshObject = replacementObject; freshObject["name"] = "Neutral new file syntax"
        let fresh = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: freshObject), type: "file", id: newID)
        #expect(throws: (any Error).self) {
            try SyntaxFileAccess.install(fresh, from: replacementURL, in: store, defaults: defaults)
        }
        #expect(defaults.data(forKey: "syntax.file." + newID.uuidString) == nil)
        store.beforeBatchCommit = nil
        try SyntaxFileAccess.install(replacement, from: replacementURL, in: store, defaults: defaults)
        #expect(store.syntaxes == [replacement])
        #expect(try SyntaxFileAccess.read(replacement, defaults: defaults).source == replacement.source)
        #expect(defaults.data(forKey: key) != bookmark)
        #expect(throws: (any Error).self) {
            try SyntaxFileAccess.install(definition(), from: replacementURL, in: store, defaults: defaults)
        }
        #expect(store.syntaxes == [replacement])
    }

    @Test func listContinuationUsesAssignedGrammarSequencesReplacementsAndUTF16() throws {
        let markdown = try ScriptSyntax.definition("Markdown")
        for (text, expected) in [("- café 🐼", "\n- "), ("\t+ [X] café", "\n\t+ [ ] "),
                                 ("9. café", "\n10. "), ("99. [x] café", "\n100. [ ] "),
                                 ("> café", "\n> ")] {
            let change = try #require(markdown.listContinuation(in: text, selection: NSRange(location: text.utf16.count, length: 0)))
            #expect(change.text == expected)
            #expect(change.range == NSRange(location: text.utf16.count, length: 0))
        }
        let text = "🐼\r\n- café"
        let selected = (text as NSString).range(of: "café")
        let change = try #require(markdown.listContinuation(in: text, selection: selected))
        #expect(change.range == selected && change.text == "\n- ")
        let empty = try #require(markdown.listContinuation(in: "\t- [ ] ", selection: NSRange(location: 7, length: 0)))
        #expect(empty.range == NSRange(location: 0, length: 7) && empty.text == "\n")
        #expect(markdown.listContinuation(in: "- café", selection: NSRange(location: 0, length: 0)) == nil)
        #expect(markdown.listContinuation(in: text, selection: NSRange(location: -1, length: 0)) == nil)
        #expect(markdown.listContinuation(in: text, selection: NSRange(location: Int.max, length: 1)) == nil)
        #expect(try ScriptSyntax.definition("Plain Text").listContinuation(in: "- café", selection: NSRange(location: 6, length: 0)) == nil)
        #expect(try ScriptSyntax.definition("TaskPaper").listContinuation(in: "\t- café", selection: NSRange(location: 7, length: 0))?.text == "\n\t- ")
        var object = source()
        object["listCompletionDefinitions"] = [["match": #"^(\h*)((\d+)\) \{done\} )(.*)$"#,
            "captures": ["indent": "1", "prefix": "2", "sequence": "3", "line": "4"],
            "sequencePadding": "2", "replacements": ["{done}": "{todo}"]]]
        let custom = try definition(object), customText = "  009) {done} café 🐼"
        #expect(custom.listContinuation(in: customText, selection: NSRange(location: customText.utf16.count, length: 0))?.text == "\n  010) {todo} ")
        var rules = try #require(object["listCompletionDefinitions"] as? [[String: Any]])
        rules[0]["enabled"] = false; object["listCompletionDefinitions"] = rules
        #expect(try definition(object).listContinuation(in: customText, selection: NSRange(location: customText.utf16.count, length: 0)) == nil)
        rules[0]["sequencePadding"] = "-1"; object["listCompletionDefinitions"] = rules
        #expect(throws: (any Error).self) { try definition(object) }
        rules[0]["sequencePadding"] = "2"
        rules[0]["captures"] = ["indent": "1", "prefix": "2", "line": "99"]
        object["listCompletionDefinitions"] = rules
        #expect(throws: (any Error).self) { try definition(object) }
    }

    @Test func customLinkTemplatesUseCapturedRangeAndEncodeValuesOnce() throws {
        var value = source()
        var rules = try #require(value["linkDefinitions"] as? [[String: Any]])
        rules[0]["templates"] = ["note": "https://example.invalid/?q=[[value]]&raw=[[value_unencoded]]"]
        value["linkDefinitions"] = rules
        let syntax = try definition(value)
        let text = "🐼 <<note:café &/>> <<unknown:x>>"
        let links = syntax.resolvedLinks(in: text)
        #expect(links.count == 1)
        let link = try #require(links.first)
        #expect(link.range == (text as NSString).range(of: "note:café &/"))
        #expect(link.url.absoluteString.contains("q=caf%C3%A9%20%26%2F&raw="))
        #expect(link.url.absoluteString.contains("raw=caf%C3%A9%20&/"))
        #expect(syntax.links(in: text).count == 2)
        rules[0]["enabled"] = false; value["linkDefinitions"] = rules
        #expect(try definition(value).resolvedLinks(in: text).isEmpty)
    }

    @Test func toggleTasksUsesCustomStatesAndRetainsAdjustedSelection() throws {
        var value = source()
        value["taskMarkDefinitions"] = [["match": #"(\[(?: |doing|x)\])"#, "rangeType": "task",
            "captures": ["state": "1", "interactive": "1"], "states": ["[ ]", "[doing]", "[x]"]]]
        let syntax = try definition(value)
        let store = try LibraryStore(inMemory: true, seed: false); try store.saveSyntax(syntax)
        let text = "🐼 [ ] outside\r\n[ ] one [doing] two [ ] three\r\n[ ] after"
        var note = try store.createNote(content: text); note.syntax = syntax.name; try store.saveNote(note)
        let editor = EditorSession(); editor.load(note)
        let selected = (text as NSString).range(of: "[ ] one [doing] two [ ] three")
        editor.selection = selected
        let runner = ActionRunner(library: store, editor: editor)
        #expect(runner.run(DraftAction(name: "Toggle custom", steps: [ActionStep("script", ["script": EditingScripts.toggleTasks])])), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "🐼 [ ] outside\r\n[doing] one [x] two [doing] three\r\n[ ] after")
        #expect(editor.selectedText == "[doing] one [x] two [doing] three")
        #expect(editor.selection.location == selected.location)
        #expect(store.notes.first?.content == editor.content)
    }

    @Test func toggleTasksUsesTaskPaperAndDoesNotInventPlainTextTasks() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        for syntax in ["TaskPaper", "Plain Text"] {
            var note = try store.createNote(content: "🐼\n- one\n- two @done(2026-10-19)\n- [ ] literal")
            note.syntax = syntax; try store.saveNote(note)
            let editor = EditorSession(); editor.load(note)
            let runner = ActionRunner(library: store, editor: editor)
            #expect(runner.run(DraftAction(name: "Toggle", steps: [ActionStep("script", ["script": EditingScripts.toggleTasks])])))
            let expected = syntax == "TaskPaper" ? "🐼\n- one @done\n- two\n- [ ] literal @done" : note.content
            #expect(editor.content == expected)
            #expect(editor.selectedText == expected)
        }
    }

    @Test func taskAndLinkScopesUseTheirDeclaredCapturesAndIgnoreDisabledRules() throws {
        var value = source()
        var taskRules = try #require(value["taskMarkDefinitions"] as? [[String: Any]])
        taskRules[0]["scopes"] = ["interactive": "text.monospace.bold", "future": "ignored"]
        value["taskMarkDefinitions"] = taskRules
        var linkRules = try #require(value["linkDefinitions"] as? [[String: Any]])
        linkRules[0]["scopes"] = ["key": "text.bold", "value": "color.red", "prefix": "markup", "suffix": "markup"]
        value["linkDefinitions"] = linkRules
        let syntax = try definition(value), text = "🐼 [~] <<note:café>>"
        let source = text as NSString
        let tasks = syntax.taskStyledRanges(in: text)
        #expect(tasks.count == 1 && tasks[0].0 == source.range(of: "[~]") && tasks[0].1 == "text.monospace.bold")
        let links = syntax.linkStyledRanges(in: text)
        #expect(links.count == 4)
        #expect(links.map { source.substring(with: $0.0) } == ["note", "café", "<<", ">>"])
        #expect(links.map { $0.1 } == ["text.bold", "color.red", "markup", "markup"])
        taskRules[0]["enabled"] = false; linkRules[0]["enabled"] = false
        value["taskMarkDefinitions"] = taskRules; value["linkDefinitions"] = linkRules
        let disabled = try definition(value)
        #expect(disabled.taskStyledRanges(in: text).isEmpty && disabled.linkStyledRanges(in: text).isEmpty)
        #expect((((disabled.object["taskMarkDefinitions"] as? [[String: Any]])?.first)?["scopes"] as? [String: String])?["future"] == "ignored")
    }

    @Test func defaultWorkspaceCopiesConfigurationWithANewIdentityAndFallsBackAfterDeletion() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        var workspace = Workspace(name: "Selected"); workspace.tags = ["work"]; workspace.sort = .accessed
        try store.saveWorkspace(workspace)
        let defaults = try #require(UserDefaults(suiteName: "DraftlyWorkspaceTest-" + UUID().uuidString))
        defaults.set(workspace.id.uuidString, forKey: WorkspaceDefaults.key)
        let copy = WorkspaceDefaults.make(in: store, defaults: defaults)
        #expect(copy.id != workspace.id && copy.name.isEmpty && copy.tags == ["work"] && copy.sort == .accessed)
        #expect(WorkspaceDefaults.make(in: store, defaults: defaults).id != copy.id)
        try store.deleteWorkspace(workspace.id)
        #expect(WorkspaceDefaults.make(in: store, defaults: defaults).tags.isEmpty)
        defaults.removeObject(forKey: WorkspaceDefaults.key)
    }
}
