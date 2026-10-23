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

    @Test func featureDefaultsAndMultipleRequirementsControlAllSharedRulesWithoutChangingSource() throws {
        var object = source()
        object["featureKeys"] = [
            ["id": "enabled", "name": "Enabled", "description": "Neutral enabled feature", "defaultValue": true],
            ["id": "optional", "name": "Optional", "description": "Neutral optional feature", "defaultValue": false]]
        object["patterns"] = [["match": "Café", "captures": ["0": ["scope": "text.bold"]]]]
        for key in ["patterns", "navigationPatterns", "taskMarkDefinitions", "linkDefinitions"] {
            var rules = object[key] as? [[String: Any]] ?? []
            for index in rules.indices { rules[index]["featureKeys"] = "enabled, optional" }
            object[key] = rules
        }
        object["listCompletionDefinitions"] = [["match": #"^(\h*)(- )(.*)$"#,
            "captures": ["indent": "1", "prefix": "2", "line": "3"], "featureKeys": "enabled, optional"]]
        let syntax = try definition(object)
        let text = "! Café\n[ ] task <<note:café>>\n- item"
        #expect(syntax.features.map(\.id) == ["enabled", "optional"])
        #expect(syntax.tasks(in: text).isEmpty && syntax.markers(in: text).isEmpty && syntax.links(in: text).isEmpty)
        let enabled = syntax.resolvingFeatures(["optional": true])
        #expect(enabled.tasks(in: text).count == 1 && enabled.markers(in: text).count == 1 && enabled.links(in: text).count == 1)
        #expect(enabled.styledRanges(in: text).count == 1 && syntax.styledRanges(in: text).isEmpty)
        #expect(enabled.listContinuation(in: text, selection: NSRange(location: text.utf16.count, length: 0))?.text == "\n- ")
        let disabled = enabled.resolvingFeatures(["enabled": false, "optional": true])
        #expect(disabled.tasks(in: text).isEmpty && disabled.markers(in: text).isEmpty && disabled.links(in: text).isEmpty)
        #expect(disabled.listContinuation(in: text, selection: NSRange(location: text.utf16.count, length: 0)) == nil)
        #expect(enabled.source == syntax.source && enabled.id == syntax.id)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(enabled) == encoder.encode(syntax))
        let decoded = try JSONDecoder().decode(SyntaxDefinition.self, from: JSONEncoder().encode(enabled))
        #expect(decoded.featureValues.isEmpty && decoded.source == syntax.source)
        var invalid = object; invalid["featureKeys"] = [["id": "same", "defaultValue": true]]
        #expect(throws: (any Error).self) { try definition(invalid) }
    }

    @Test func featurePreferencesAreLocalPersistentAndPreserveUnknownValues() throws {
        let domain = "Draftly-FeatureTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        var object = source()
        object["featureKeys"] = [["id": "tasks", "name": "Tasks", "description": "Neutral tasks", "defaultValue": true]]
        var tasks = try #require(object["taskMarkDefinitions"] as? [[String: Any]])
        tasks[0]["featureKeys"] = "tasks"; object["taskMarkDefinitions"] = tasks
        let syntax = try definition(object), store = try LibraryStore(inMemory: true, seed: false)
        try store.saveSyntax(syntax)
        let backup = try store.backupData()
        let encoded = SyntaxFeaturePreferences.setting(false, feature: "tasks", syntax: syntax.name,
            encoded: "{\"Future syntax\":{\"data\":[1,2]},\"Neutral\":{\"future\":\"keep\"}}")
        defaults.set(encoded, forKey: SyntaxFeaturePreferences.key)
        let reopened = try #require(UserDefaults(suiteName: domain))
        #expect(try store.syntaxDefinition(named: syntax.name, defaults: reopened).tasks(in: "[ ] task").isEmpty)
        #expect(syntax.tasks(in: "[ ] task").count == 1)
        #expect(try store.backupData() == backup)
        let decoded = try #require(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        #expect(decoded["Future syntax"] != nil && (decoded["Neutral"] as? [String: Any])?["future"] as? String == "keep")
        #expect(SyntaxFeaturePreferences.values(for: "other", encoded: encoded).isEmpty)
        #expect(SyntaxFeaturePreferences.values(for: syntax.name, encoded: "invalid").isEmpty)
    }

    @Test func featureEditsDoNotReplaceMalformedConfigurationOrSyntaxValues() {
        for original in ["invalid", "[]", "null", #"{"Neutral":[],"other":{"keep":true}}"#,
                         #"{"Neutral":null}"#, #"{"Neutral":"future format"}"#, #"{"Neutral":false}"#] {
            #expect(SyntaxFeaturePreferences.setting(false, feature: "tasks", syntax: "Neutral", encoded: original) == original)
        }
        let fresh = SyntaxFeaturePreferences.setting(false, feature: "tasks", syntax: "Neutral", encoded: "{}")
        #expect(SyntaxFeaturePreferences.values(for: "Neutral", encoded: fresh) == ["tasks": false])
    }

    @Test func staticCompletionUsesUTF16TriggerCurrentTextAndTemplateOptions() throws {
        var object = source()
        object["featureKeys"] = [["id": "suggestions", "name": "Suggestions", "description": "Neutral options", "defaultValue": true]]
        object["autocompleteDefinitions"] = [["trigger": "!!", "type": "static", "featureKeys": "suggestions", "processTemplateTags": true,
            "items": [["label": "Current title", "value": "[[title]]", "prefix": "<", "suffix": ">"],
                      ["label": "Raw tags", "value": "[[draft]]", "processTemplateTags": false],
                      ["label": "café 🐼", "value": "First"], ["label": "café 🐼", "value": "Second"]]]]
        let syntax = try definition(object), current = Note(content: "Old title")
        let text = "Unsaved title 🐼\n!!"
        let request = try #require(syntax.completion(in: text, selection: NSRange(location: text.utf16.count, length: 0), drafts: [], current: current))
        #expect(request.range == (text as NSString).range(of: "!!"))
        #expect(request.items.map(\.value) == ["<Unsaved title 🐼>", "[[draft]]", "First", "Second"])
        #expect(request.items[0].label == "<Current title>" && request.items.allSatisfy { $0.draftID == nil })
        let filtered = "🐼 !!CAFE"
        let matches = try #require(syntax.completion(in: filtered, selection: NSRange(location: filtered.utf16.count, length: 0), drafts: [], current: current))
        #expect(matches.items.map(\.value) == ["First", "Second"])
        #expect(matches.range == NSRange(location: 3, length: 6))
        #expect(syntax.completion(in: "!!\nplain", selection: NSRange(location: 8, length: 0), drafts: [], current: current) == nil)
        #expect(syntax.completion(in: "!!", selection: NSRange(location: 0, length: 2), drafts: [], current: current) == nil)
        #expect(syntax.completion(in: "!!", selection: NSRange(location: Int.max, length: 0), drafts: [], current: current) == nil)
        #expect(syntax.resolvingFeatures(["suggestions": false]).completion(in: "!!", selection: NSRange(location: 2, length: 0), drafts: [], current: current) == nil)
        #expect(current.content == "Old title")
    }

    @Test func draftCompletionFiltersTitlesTextTagsAndPreservesDuplicateIdentities() throws {
        var object = source()
        object["autocompleteDefinitions"] = [["trigger": "[[", "type": "draft", "label": "[[display_title]]", "value": "[[body]]",
            "prefix": "[[", "suffix": "]]", "queryType": "title", "queryTagFilter": "blue, red"]]
        let current = Note(content: "Current"), now = Date(timeIntervalSince1970: 100)
        var first = Note(content: "# Café 🐼\nBody one"); first.tags = ["blue/sub", "red"]; first.modifiedAt = now
        var second = Note(content: "# Café 🐼\nBody two"); second.tags = ["blue", "red"]; second.modifiedAt = now.addingTimeInterval(-1)
        var bodyOnly = Note(content: "Other title\nCafé content"); bodyOnly.tags = ["blue", "red"]
        var missingTag = first; missingTag.id = UUID(); missingTag.tags = ["blue"]
        var trash = first; trash.id = UUID(); trash.trashedAt = now
        let drafts = [second, missingTag, trash, current, first, bodyOnly]
        let syntax = try definition(object), text = "🐼 [[cafe"
        let request = try #require(syntax.completion(in: text, selection: NSRange(location: text.utf16.count, length: 0), drafts: drafts, current: current))
        #expect(request.items.map(\.draftID) == [first.id, second.id])
        #expect(request.items.map(\.label) == ["[[Café 🐼]]", "[[Café 🐼]]"])
        #expect(request.items.map(\.value) == ["[[Body one]]", "[[Body two]]"])
        #expect(syntax.completion(in: "[[cafe]]", selection: NSRange(location: 8, length: 0), drafts: drafts, current: current) == nil)
        var rules = try #require(object["autocompleteDefinitions"] as? [[String: Any]])
        rules[0]["queryType"] = "fullText"; object["autocompleteDefinitions"] = rules
        #expect(try definition(object).completion(in: text, selection: NSRange(location: text.utf16.count, length: 0), drafts: drafts, current: current)?.items.contains { $0.draftID == bodyOnly.id } == true)
        rules[0]["enabled"] = false; object["autocompleteDefinitions"] = rules
        #expect(try definition(object).completion(in: text, selection: NSRange(location: text.utf16.count, length: 0), drafts: drafts, current: current) == nil)
        rules[0]["trigger"] = ""; object["autocompleteDefinitions"] = rules
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
    @Test func builtInWikiLinksResolveEncodedDestinations() throws {
        let value = "café 🐼 &/%#"
        let templates = ["": "draftly://open?title=", "d": "draftly://open?title=", "u": "draftly://open?uuid=",
            "s": "draftly://quickSearch?query=", "w": "draftly://workspace?name=",
            "google": "https://www.google.com/search?q=", "wikipedia": "https://en.wikipedia.org/wiki/",
            "bear": "bear://x-callback-url/open-note?title="]
        for name in ["Markdown", "MultiMarkdown", "GitHub Markdown"] {
            let syntax = try ScriptSyntax.definition(name)
            for (key, prefix) in templates {
                let inner = key.isEmpty ? value : key + ":" + value
                let source = "🐼 [[" + inner + "]]"
                let link = try #require(syntax.resolvedLinks(in: source).first)
                #expect(link.range == (source as NSString).range(of: inner))
                #expect(link.url.absoluteString.hasPrefix(prefix))
                #expect(link.url.absoluteString.contains("caf%C3%A9%20%F0%9F%90%BC%20%26%2F%25%23"))
                if key.isEmpty || key == "d" { #expect(link.url.absoluteString.hasSuffix("&allowCreate=true")) }
            }
            #expect(syntax.resolvedLinks(in: "[[unknown:value]]").isEmpty)
            #expect(syntax.links(in: "[[unknown:value]]").count == 1)
        }
        #expect(try ScriptSyntax.definition("Plain Text").resolvedLinks(in: "[[title]]").isEmpty)
    }
    @Test func hangingIndentationUsesUTF16PrefixesAndFeatureRules() throws {
        var object = source()
        object["indentationPatterns"] = [["match": #"^(🐼 +).*"#, "indentCapture": "1", "indentScope": "text.bold"],
            ["match": #"^(> +).*"#, "indentCapture": "1", "enabled": false]]
        let syntax = try definition(object), text = "🐼  café\r\n> quote\nplain"
        let values = syntax.indentations(in: text)
        #expect(values.count == 1)
        let first = try #require(values.first)
        #expect(first.prefix == NSRange(location: 0, length: 4))
        #expect(first.range == (text as NSString).lineRange(for: first.prefix))
        #expect(first.scope == "text.bold")
        object["indentationPatterns"] = [["match": "^x", "indentCapture": "2"]]
        #expect(throws: (any Error).self) { try definition(object) }
        object["indentationPatterns"] = [["match": "^x"]]
        #expect(throws: (any Error).self) { try definition(object) }
        for name in ["Markdown", "MultiMarkdown", "GitHub Markdown"] {
            let builtIn = try ScriptSyntax.definition(name)
            let prefixes = builtIn.indentations(in: "  - café\n10. item\n> quote\nplain")
            #expect(prefixes.map(\.prefix.length) == [4, 4, 2])
        }
    }
    @Test func builtInQuotationScopesUseSharedGrammarAndUTF16Ranges() throws {
        let text = "🐼 plain\r\n  >> café 🐼\nplain"
        for name in ["Markdown", "MultiMarkdown", "GitHub Markdown"] {
            let ranges = try ScriptSyntax.definition(name).styledRanges(in: text)
            let prefix = try #require(ranges.first { $0.1 == "markup.quotation" })
            let body = try #require(ranges.first { $0.1 == "text.quotation" })
            #expect(prefix.0 == (text as NSString).range(of: "  >> "))
            #expect(body.0 == (text as NSString).range(of: "café 🐼"))
            #expect(ranges.count == 2)
        }
        #expect(try ScriptSyntax.definition("Plain Text").styledRanges(in: text).isEmpty)
    }
    @Test func malformedRuleOptionsAndCapturesFailBeforeInstallation() throws {
        var invalid: [[String: Any]] = []
        for captures: Any in [["0": "text.bold"], ["0": ["scope": 12]], ["0": ["scope": "text.bold", "exclusive": "true"]]] {
            var value = source(); value["patterns"] = [["match": "x", "captures": captures]]; invalid.append(value)
        }
        for captures: [String: Any] in [["key": "1", "value": "2"], ["key": "1", "value": 2, "link": "0"]] {
            var value = source(); value["linkDefinitions"] = [["match": "(x)(y)", "captures": captures]]; invalid.append(value)
        }
        for option in ["enabled", "exclusive", "featureKeys"] {
            var value = source(); value["patterns"] = [["match": "x", option: 1, "captures": ["0": ["scope": "text.bold"]]]]; invalid.append(value)
        }
        var value = source(); value["linkDefinitions"] = [["match": "(x)(y)", "captures": ["key": "1", "value": "2", "link": "0"], "templates": ["x": 42]]]; invalid.append(value)
        for object in invalid { #expect(throws: (any Error).self) { try definition(object) } }
        let library = try LibraryStore(inMemory: true, seed: false)
        for object in invalid {
            #expect(throws: (any Error).self) {
                try LibraryFileImport.apply(JSONSerialization.data(withJSONObject: object), fileExtension: "draftsSyntax", to: library)
            }
        }
        #expect(library.syntaxes.isEmpty && library.notes.isEmpty)
    }
    @Test func validatedRulesRetainUnknownFieldsAndLegacyOptionalDefaults() throws {
        var object = source()
        object["patterns"] = [["match": "(café)", "enabled": true, "exclusive": false,
            "future": ["keep": 17], "captures": ["1": ["scope": "text.bold", "exclusive": false, "future": ["keep": true]]]]]
        object["rangeExtensionType"] = ["default": "lineExtended", "futurePlatform": "futureValue"]
        let original = try definition(object)
        let library = try LibraryStore(inMemory: true, seed: false)
        try LibraryFileImport.apply(Data(original.source.utf8), fileExtension: "draftsSyntax", to: library)
        let installed = try #require(library.syntaxes.first)
        #expect(installed.source == original.source)
        #expect(installed.styledRanges(in: "🐼 café").first?.0 == NSRange(location: 3, length: 4))
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.syntaxes == library.syntaxes)
        #expect(try definition().name == "Three states")
    }
    @Test func exclusiveCaptureProtectsOnlyItsTextFromLaterStyles() throws {
        var object = source()
        object["patterns"] = [
            ["match": "`([^`]+)`", "captures": ["1": ["scope": "code.inline", "exclusive": true]]],
            ["match": "^(.+)$", "captures": ["0": ["scope": "text.italic"]]]]
        let text = "🐼 before `café` after"
        let ranges = try definition(object).styledRanges(in: text)
        let protected = (text as NSString).range(of: "café")
        #expect(ranges.first?.0 == protected && ranges.first?.1 == "code.inline")
        let later = ranges.filter { $0.1 == "text.italic" }.map(\.0)
        #expect(later == [NSRange(location: 0, length: protected.location),
            NSRange(location: NSMaxRange(protected), length: text.utf16.count - NSMaxRange(protected))])
        #expect(later.allSatisfy { NSIntersectionRange($0, protected).length == 0 })
    }

    @Test func styleCapturesApplyInNumericOrderBeforeExclusionsAffectLaterRules() throws {
        var object = source()
        object["patterns"] = [
            ["match": "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)", "exclusive": true,
             "captures": Dictionary(uniqueKeysWithValues: (0...11).map { (String($0), ["scope": "capture.\($0)"]) })],
            ["match": "[a-k]", "captures": ["0": ["scope": "later"]]]]
        let ranges = try definition(object).styledRanges(in: "abcdefghijk")
        #expect(ranges.map(\.1) == (0...11).map { "capture.\($0)" })
        #expect(ranges.first?.0 == NSRange(location: 0, length: 11))
        #expect(ranges.dropFirst().map(\.0.location) == Array(0...10))
    }
    @Test func librarySyntaxLookupUsesInjectedFileAccess() throws {
        let suite = "Draftly.SyntaxLookup." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Neutral.draftsSyntax")
        let original = try definition()
        try Data(original.source.utf8).write(to: file)
        let fileSyntax = try SyntaxDefinition(data: Data(original.source.utf8), type: "file")
        let library = try LibraryStore(inMemory: true, seed: false)
        try SyntaxFileAccess.install(fileSyntax, from: file, in: library, defaults: defaults)
        #expect(try library.syntaxDefinition(named: fileSyntax.name, defaults: defaults).id == fileSyntax.id)
        defaults.removeObject(forKey: "syntax.file." + fileSyntax.id.uuidString)
        #expect(throws: (any Error).self) { try library.syntaxDefinition(named: fileSyntax.name, defaults: defaults) }
        #expect(library.syntaxes == [fileSyntax])
    }
    @Test(arguments: [false, true])
    func lineTasksHaveOneMatchPerLineWhileTaskMarksRemainIndependent(worker: Bool) async throws {
        var object = source()
        let rule: [String: Any] = ["match": #"(\*)([^*\r\n]*?)(\[[ ~x]\])"#, "rangeType": "line",
            "captures": ["interactive": "1", "label": "2", "state": "3"],
            "states": ["[ ]", "[~]", "[x]"], "initialState": "[ ]", "completedState": ["[x]"]]
        object["taskMarkDefinitions"] = [rule]
        let text = "🐼 *one[ ] *two[~]\r\n*three[x]"
        let syntax = try definition(object), tasks = syntax.tasks(in: text)
        #expect(tasks.count == 2)
        #expect(tasks.map { $0["stateRange"] as? [Int] } == [[7, 3], [26, 3]])
        #expect(tasks.map { $0["label"] as? String } == ["one", "three"])
        let first = try #require(tasks.first)
        let change = try syntax.taskChange(in: text, task: first, operation: "advance")
        #expect((text as NSString).replacingCharacters(in: change.0, with: change.1) == "🐼 *one[~] *two[~]\r\n*three[x]")
        var independent = rule; independent["rangeType"] = "task"
        object["taskMarkDefinitions"] = [independent]
        let marks = try definition(object).tasks(in: text)
        #expect(marks.count == 3)
        let ignored = try #require(marks.first { $0["stateRange"] as? [Int] == [15, 3] })
        #expect(throws: SyntaxTaskError.invalidSnapshot) { try syntax.taskChange(in: text, task: ignored, operation: "advance") }
        object["taskMarkDefinitions"] = [rule, rule]
        let installed = try definition(object)
        #expect(installed.tasks(in: text).count == 2)
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveSyntax(installed)
        var note = try library.createNote(content: text); note.syntax = installed.name; try library.saveNote(note)
        let editor = EditorSession(); editor.load(note)
        let runner = ActionRunner(library: library, editor: editor)
        let action = DraftAction(name: "Neutral line tasks", steps: [ActionStep("script", ["script": """
        if(draft.tasks.length!==2 || editor.tasks.length!==2)throw new Error('line count');
        if(editor.tasks[0].label!=='one' || editor.tasks[1].stateRange[0]!==26)throw new Error('line fields');
        if(editor.advanceTask(editor.tasks[0])!==true)throw new Error('advance');
        if(editor.tasks.length!==2 || draft.tasks[0].state!=='[~]')throw new Error('updated snapshot');
        """])])
        if worker { #expect(await runner.runAsync(action).reason == .success, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
        #expect(editor.content == "🐼 *one[~] *two[~]\r\n*three[x]")
    }
    @Test(arguments: [false, true])
    func taskModeIgnoresTheLineOnlyLabelCapture(worker: Bool) async throws {
        var object = source()
        let rule: [String: Any] = ["match": #"(\[[ ~x]\])"#, "rangeType": "task",
            "captures": ["interactive": "1", "state": "1", "label": "1"],
            "states": ["[ ]", "[~]", "[x]"]]
        object["taskMarkDefinitions"] = [rule]
        let syntax = try definition(object), text = "🐼 [ ] café\r\n[x] tail"
        let tasks = syntax.tasks(in: text)
        #expect(tasks.map { $0["label"] as? String } == ["café", "tail"])
        #expect(tasks.map { $0["labelRange"] as? [Int] } == [[7, 4], [17, 4]])
        var lineRule = rule; lineRule["rangeType"] = "line"
        object["taskMarkDefinitions"] = [lineRule]
        #expect(try definition(object).tasks(in: text).first?["label"] as? String == "[ ]")
        var captures = try #require(lineRule["captures"] as? [String: String]); captures.removeValue(forKey: "label")
        lineRule["captures"] = captures; object["taskMarkDefinitions"] = [lineRule]
        let legacy = try definition(object)
        #expect(legacy.tasks(in: text).first?["label"] as? String == "café")
        let legacyLibrary = try LibraryStore(inMemory: true, seed: false)
        try legacyLibrary.saveSyntax(legacy)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(legacyLibrary.backupData())
        #expect(try restored.syntaxDefinition(named: legacy.name).tasks(in: text).first?["label"] as? String == "café")
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveSyntax(syntax)
        var note = try library.createNote(content: text); note.syntax = syntax.name; try library.saveNote(note)
        let editor = EditorSession(); editor.load(note)
        let runner = ActionRunner(library: library, editor: editor)
        let action = DraftAction(name: "Neutral task labels", steps: [ActionStep("script", ["script": """
        if(draft.tasks[0].label!=='café' || editor.tasks[0].labelRange[0]!==7)throw new Error('label');
        if(editor.tasks[1].label!=='tail' || draft.tasks[1].labelRange[0]!==17)throw new Error('second label');
        if(editor.advanceTask(editor.tasks[0])!==true || draft.tasks[0].label!=='café')throw new Error('advance label');
        """])])
        if worker { #expect(await runner.runAsync(action).reason == .success, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
    }
}
