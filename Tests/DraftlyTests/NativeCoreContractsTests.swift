import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Native core controls") @MainActor
struct NativeCoreContractsTests {
    @Test func selectPromptItemShowsOnlyAnExplicitValidSymbol() throws {
        let choices = SearchablePromptChoices(items: [
            ["title": "No symbol"],
            ["title": "Document", "symbolName": "doc.text"],
            ["title": "Unknown", "symbolName": "draftly.nonexistent.symbol"]])
        for (row, hasImage) in [(0, false), (1, true), (2, false)] {
            let cell = try #require(choices.tableView(choices.table, viewFor: nil, row: row) as? NSTableCellView)
            #expect((cell.imageView?.image != nil) == hasImage)
            #expect(cell.textField?.stringValue == ["No symbol", "Document", "Unknown"][row])
        }
    }
    @Test func invalidPromptDateAndHeightOptionsFailBeforeShowingAWindow() throws {
        let host = NativeActionHost()
        let date = APIValues.date(Date(timeIntervalSince1970: 100))
        let fields: [[String: Any]] = [
            ["kind": "date", "value": "invalid"],
            ["kind": "date", "value": date, "mode": "invalid"],
            ["kind": "date", "value": date, "minuteInterval": 7],
            ["kind": "date", "value": date, "minuteInterval": 2.5],
            ["kind": "date", "value": date, "minimumDate": APIValues.date(Date(timeIntervalSince1970: 200)), "maximumDate": date],
            ["kind": "textView", "height": -1]
        ]
        for field in fields { #expect(throws: (any Error).self) { try host.perform("prompt", values: ["fields": [field]]) } }
    }
    @Test func promptDateIntervalsHaveDefaultsAndValidateBounds() throws {
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        #expect(try PromptDatePolicy(interval: 1).normalize(date) == date)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let adjusted = try PromptDatePolicy(interval: 5).normalize(date, calendar: calendar)
        #expect(calendar.component(.minute, from: adjusted) % 5 == 0)
        #expect(calendar.component(.second, from: adjusted) == 0)
        #expect(calendar.isDate(date, inSameDayAs: adjusted))
        for invalid in [0, -1, 7, 31] { #expect(throws: (any Error).self) { try PromptDatePolicy(interval: invalid) } }
    }
    @Test func speechCallbackStateAcceptsBackgroundUpdates() async {
        let result = SpeechResult()
        await Task.detached {
            result.setAuthorized(true)
            result.update("Neutral speech", final: true, error: nil)
        }.value
        #expect(result.authorized == true && result.finished && result.text == "Neutral speech" && result.error == nil)
    }
    @Test func selectPromptFiltersSubtitlesAndReturnsOriginalIndex() {
        let choices = SearchablePromptChoices(items: [
            ["title": "First", "subtitle": "Unrelated"],
            ["title": "Second", "subtitle": "Café 🐼"],
            ["title": "Third", "subtitle": "Café"]])
        #expect(choices.selectedIndex == 0)
        choices.filter("cafe")
        #expect(choices.visibleIndices == [1, 2])
        #expect(choices.selectedIndex == 1)
        choices.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(choices.selectedIndex == 2)
        choices.filter("")
        #expect(choices.selectedIndex == 2)
        choices.filter("missing")
        #expect(choices.selectedIndex == nil)
    }
    @Test func scanDocumentUsesTheUnavailableCameraReturnWithoutOpeningAFilePicker() throws {
        let host = NativeActionHost()
        #expect(try host.perform("scanDocument", values: [:]) as? String == "")
    }
    @Test func workspaceReferencesSurviveGroupAndThemeRenames() throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        var group = ActionGroupRecord(name: "Original"); try model.library.saveActionGroup(group)
        var theme = EditorTheme(); theme.name = "Renamed theme"
        let defaults = UserDefaults.standard, original = defaults.object(forKey: "editor.themes")
        defer { if let original { defaults.set(original, forKey: "editor.themes") } else { defaults.removeObject(forKey: "editor.themes") } }
        defaults.set(String(decoding: try JSONEncoder().encode([theme]), as: UTF8.self), forKey: "editor.themes")
        var workspace = Workspace(name: "Identity")
        workspace.scriptMetadata = ["api": String(decoding: try JSONSerialization.data(withJSONObject: [
            "loadActionListGroup": ["uuid": group.id.uuidString, "name": "Original"],
            "loadActionBarGroup": ["uuid": group.id.uuidString, "name": "Original"],
            "preferredDarkTheme": ["uuid": theme.id.uuidString, "name": "Old theme", "type": "custom"]]), as: UTF8.self)]
        group.name = "Renamed"; try model.library.saveActionGroup(group)
        try model.applyScriptWorkspace(workspace)
        #expect(model.actionGroup == "Renamed" && model.actionBarGroup == "Renamed")
        #expect(WorkspaceThemeValues.preference(model.workspaceScriptMetadata, key: "preferredDarkTheme") == "Renamed theme")
        let note = try model.library.createNote(content: "Keep"); model.select(note.id)
        #expect(model.runner.run(DraftAction(name: "Theme discovery", steps: [ActionStep("script", ["script": "if(!Theme.find('custom','Renamed theme'))throw new Error('missing custom theme');"])])))
        model.folder = .archive
        var invalid = workspace.apiOptions; invalid["preferredDarkTheme"] = ["uuid": UUID().uuidString, "name": "Renamed theme", "type": "custom"]
        workspace.scriptMetadata = ["api": String(decoding: try JSONSerialization.data(withJSONObject: invalid), as: UTF8.self)]
        #expect(throws: (any Error).self) { try model.applyScriptWorkspace(workspace) }
        #expect(model.folder == .archive && model.editor.content == "Keep")
    }
    @Test func showDictateSchedulesTheEditorControlWithoutChangingText() async throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let note = try model.library.createNote(content: "Keep text"); model.select(note.id)
        model.host.dictationHandler = { _ in "" }
        var calls = 0
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            model.editor.focusForDictation = { calls += 1; continuation.resume(); return true }
            do {
                _ = try model.actionUIOperation(["operation": "showDictate"])
                #expect(calls == 0 && model.dictationActive)
                #expect(throws: (any Error).self) { try model.actionUIOperation(["operation": "showDictate"]) }
            } catch { Issue.record(error); continuation.resume() }
        }
        await model.dictationSession.wait()
        #expect(calls == 1 && model.editor.content == "Keep text")
        model.editor.focusForDictation = nil
        #expect(throws: (any Error).self) { try model.actionUIOperation(["operation": "showDictate"]) }
    }
    @Test func showDictateRecoversChangedDestinationsAndKeepsTextOnFailure() async throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let note = try model.library.createNote(content: "Original"); model.select(note.id)
        var recovered = ""
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            model.editor.focusForDictation = { true }
            model.recoverDictation = { recovered = $0; continuation.resume() }
            model.host.dictationHandler = { _ in model.editor.content = "Changed destination"; return "Recovered speech" }
            do { _ = try model.actionUIOperation(["operation": "showDictate"]) }
            catch { Issue.record(error); continuation.resume() }
        }
        await model.dictationSession.wait()
        #expect(recovered == "Recovered speech" && model.editor.content == "Changed destination" && !model.dictationActive)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            model.host.dictationHandler = { _ in continuation.resume(); throw DraftlyError.message("Expected input failure") }
            do { _ = try model.actionUIOperation(["operation": "showDictate"]) }
            catch { Issue.record(error); continuation.resume() }
        }
        await model.dictationSession.wait()
        #expect(model.library.error == "Expected input failure" && model.editor.content == "Changed destination")
    }
    @Test func configureWindowPreflightsReferencesAndAppliesAllControls() throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let note = try model.library.createNote(content: "Current"); model.select(note.id)
        model.editor.selection = NSRange(location: 1, length: 2)
        #expect(throws: (any Error).self) { try model.actionUIOperation(["operation": "configureWindow", "values": ["loadActionGroup": "Missing", "showTagEntry": "false"]]) }
        #expect(model.showTags)
        #expect(throws: (any Error).self) { try model.actionUIOperation(["operation": "configureWindow", "values": ["unknownOption": "true", "showTagEntry": "false"]]) }
        #expect(model.showTags)
        let options = ["showActionBar": "false", "showTagEntry": "false", "showActionList": "true", "pinCurrentDraft": "true", "linkMode": "true"]
        let step = DraftAction(name: "Configure contract", steps: [ActionStep("configureWindow", options)])
        #expect(model.runner.run(step), Comment(rawValue: model.runner.message ?? ""))
        #expect(!model.showActionBar && !model.showTags && model.showActions && model.linksEnabled && model.isDraftPinned)
        #expect(model.editor.noteID == note.id && model.editor.selection == NSRange(location: 1, length: 2))
    }
    @Test func customSyntaxStylingUsesTheSharedDefinition() throws {
        let data = Data(#"{"name":"Color test","patterns":[{"match":"(café)","captures":{"1":{"scope":"color.red"}}}],"navigationPatterns":[],"taskMarkDefinitions":[],"linkDefinitions":[],"indentationPatterns":[]}"#.utf8)
        let definition = try SyntaxDefinition(data: data)
        let session = EditorSession(); session.content = "🐼 café"
        let native = NativeEditor(session: session, fontName: "SFMono-Regular", fontSize: 15, lineSpacing: 2, markdown: false, syntax: "Color test", syntaxDefinition: definition, onChange: {})
        let coordinator = NativeEditor.Coordinator(native)
        let text = NSTextView(); text.string = session.content; coordinator.textView = text
        coordinator.highlight()
        #expect(text.textStorage?.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor == .systemRed)
        #expect(text.string == session.content)
    }
}
