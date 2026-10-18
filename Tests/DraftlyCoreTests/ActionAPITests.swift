import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class APIHost: ActionHost {
    var calls: [(String, [String: Any])] = []
    var clipboard = ""
    var previewSuccess = true
    var callbackStatus = "success"
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        calls.append((operation, values))
        switch operation {
        case "clipboard": clipboard = values["text"] as? String ?? ""; return true
        case "getClipboard": return clipboard
        case "prompt":
            var fields: [String: Any] = [:]
            for field in values["fields"] as? [[String: Any]] ?? [] { if let key = field["key"] as? String { fields[key] = field["value"] } }
            return ["index": 0, "fields": fields]
        case "htmlPreview": return ["success": previewSuccess, "values": ["answer": ["value": 42]]]
        case "callbackURL": return ["status": callbackStatus, "parameters": ["result": "Returned + café"]]
        case "requireScript": return "function loadedHelper(value) { return value.toUpperCase(); }"
        case "shortcut": return "Shortcut output"
        case "appleScript": return ["value": 42]
        case "markdown": return MarkdownRenderer.render(values["text"] as? String ?? "")
        default: throw DraftlyError.message("Unexpected test operation: \(operation)")
        }
    }
}

@Suite("Action API contracts") @MainActor
struct ActionAPITests {
    private func setup(_ content: String = "# Source\nBody") throws -> (LibraryStore, EditorSession, APIHost, ActionRunner) {
        let library = try LibraryStore(inMemory: true, seed: false), editor = EditorSession(), host = APIHost()
        editor.load(try library.createNote(content: content))
        return (library, editor, host, ActionRunner(library: library, editor: editor, host: host))
    }
    private func action(_ script: String, async: Bool = false) -> DraftAction {
        DraftAction(name: "API contract", steps: [ActionStep("script", ["script": "function check(value,label) { if (!value) throw new Error(label); }\n" + script, "allowAsync": async ? "true" : "false"])])
    }
    @Test func draftMetadataDatesSyntaxAndQueriesRoundTrip() throws {
        let (library, _, _, runner) = try setup()
        let source = #"""
        let d = Draft.create();
        d.content = '# Meeting\nNotes'; d.addTag(' WORK '); d.flagType = 5;
        d.createdAt = new Date('2020-01-02T03:04:05Z'); d.modifiedAt = new Date('2021-02-03T04:05:06Z');
        d.syntax = Syntax.find('builtIn','Markdown'); d.createdLatitude = 12.5; d.folder = 'archive'; d.update();
        check(d.title === '# Meeting' && d.displayTitle === 'Meeting', 'titles');
        let found = Draft.queryByTitle('meet')[0];
        check(found.createdAt instanceof Date && found.modifiedAt.getUTCFullYear() === 2021, 'dates');
        check(found.syntax.name === 'Markdown' && found.flagType === 5 && found.folder === 'archive', 'metadata');
        check(found.hasTag('Work') && found.createdLatitude === 12.5, 'tags and location');
        check(Draft.flagged('red').length === 1, 'flag query');
        found.folder = 'trash'; found.update();
        check(Draft.query('', 'trash').length === 1, 'trash query');
        """#
        #expect(runner.run(action(source)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.title == "Meeting" }?.trashedAt != nil)
    }
    @Test func workspacePersistsFiltersDatesAndFolderSorts() throws {
        let (library, _, _, runner) = try setup()
        _ = try library.createNote(content: "# Zulu", tags: ["project", "omit"])
        _ = try library.createNote(content: "# Alpha", tags: ["project"])
        let source = #"""
        let w = Workspace.create(); w.name = 'Projects'; w.tagFilter = 'project, !omit';
        w.tagFilterRequireAll = true; w.setAllSort('name',false,true); w.showTags = false;
        w.startDate.type = 'relative'; w.startDate.days = -1; w.update();
        let loaded = Workspace.find('Projects');
        check(loaded.showTags === false && loaded.startDate.days === -1, 'workspace persistence');
        check(loaded.query('all').length === 1 && loaded.query('all')[0].displayTitle === 'Alpha', 'workspace filters');
        check(Workspace.getAll().length === 1, 'workspace listing');
        """#
        #expect(runner.run(action(source)), Comment(rawValue: runner.message ?? ""))
        #expect(library.workspaces.count == 1)
    }
    @Test func versionsTagsAndRecentActionsAreQueryable() throws {
        let (library, editor, _, runner) = try setup()
        let first = action("draft.addTag('old'); draft.update(); draft.saveVersion();")
        try library.saveAction(first)
        #expect(runner.run(first))
        #expect(runner.run(action(#"""
        check(draft.actionLogs.length === 1, 'draft logs');
        check(Action.recent()[0].name === 'API contract', 'recent action');
        check(new Tag().renameTag('old','new') === 1, 'rename count');
        check(Tag.query('new')[0] === 'new', 'query tags');
        let version = draft.versions[0];
        check(version.createdAt instanceof Date && version.draft.uuid === draft.uuid, 'version metadata');
        let count = draft.versions.length; version.delete(); check(draft.versions.length === count-1,'delete version');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.id == editor.noteID }?.tags == ["new"])
    }
    @Test func editorTasksAndLineRangesUseUTF16() throws {
        let (_, editor, _, runner) = try setup("# Heading\n- [ ] Café 😀\n- [x] Done\nTail")
        #expect(runner.run(action(#"""
        check(editor.tasks.length === 2 && editor.incompleteTasks.length === 1, 'task parsing');
        check(editor.navigationMarkers.length === 1 && draft.navigationMarkers[0].location === 0, 'navigation markers');
        let task = editor.incompleteTasks[0]; editor.completeTask(task);
        check(editor.completedTasks.length === 2, 'task completion');
        editor.setSelectedRange(task.labelRange[0],task.labelRange[1]);
        check(editor.getSelectedText() === 'Café 😀', 'UTF16 task range');
        check(editor.getSelectedLineRange()[0] === 10, 'line range');
        let d = Draft.create(); d.content = 'Next'; d.update(); editor.load(d);
        check(editor.recentDrafts[0].displayTitle === 'Heading', 'recent drafts');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "Next")
    }
    @Test func asyncCompletionWaitsAndSharesStateWithNextStep() throws {
        let (_, _, host, runner) = try setup()
        var run = action("let answer; setTimeout(() => { answer = 'ready'; script.complete(); }, 5);", async: true)
        run.steps.append(ActionStep("script", ["script": "app.setClipboard(answer);"]))
        #expect(runner.run(run), Comment(rawValue: runner.message ?? ""))
        #expect(host.clipboard == "ready")
    }
    @Test func asyncPromiseRejectionAndTimeoutStopDisposition() throws {
        let (library, editor, host, runner) = try setup()
        runner.scriptTimeout = 0.02
        var timedOut = action("Promise.resolve('unused');", async: true); timedOut.afterSuccess = "archive"
        timedOut.steps.append(ActionStep("clipboard", ["template": "must not run"]))
        #expect(!runner.run(timedOut))
        #expect(runner.message?.contains("timed out") == true)
        #expect(host.calls.isEmpty)
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
        #expect(!runner.run(action("Promise.reject(new Error('Async failure'));", async: true)))
        #expect(runner.message?.contains("Async failure") == true)
    }
    @Test func includedActionsShareJavaScriptAndDoNotApplyOwnDisposition() throws {
        let (library, editor, host, runner) = try setup()
        var helper = DraftAction(name: "Helper", steps: [ActionStep("script", ["script": "function helper(value) { return value + '!'; }"])]); helper.afterSuccess = "trash"
        try library.saveAction(helper)
        let run = DraftAction(name: "Parent", steps: [ActionStep("includeAction", ["name": "Helper"]), ActionStep("script", ["script": "app.setClipboard(helper('works'));"])])
        #expect(runner.run(run), Comment(rawValue: runner.message ?? ""))
        #expect(host.clipboard == "works!")
        #expect(library.notes.first { $0.id == editor.noteID }?.trashedAt == nil)
    }
    @Test func includedUnknownStepIsRejectedBeforeAnySideEffect() throws {
        let (library, _, host, runner) = try setup()
        try library.saveAction(DraftAction(name: "Unknown", steps: [ActionStep("future")]))
        let run = DraftAction(name: "Parent", steps: [ActionStep("clipboard", ["template": "must not run"]), ActionStep("includeAction", ["name": "Unknown"])])
        #expect(!runner.run(run)); #expect(host.calls.isEmpty)
    }
    @Test func disabledUnknownStepsSurviveImportAndDoNotBlockExecution() throws {
        let (_, _, host, runner) = try setup()
        let data = Data(#"{"name":"Disabled","steps":[{"type":"future","isEnabled":false,"data":{"key":"keep"}},{"type":"clipboard","data":{"template":"ready"}}]}"#.utf8)
        let run = try #require(ActionImporter.decode(data).first)
        #expect(run.steps.count == 2 && run.steps[0].isEnabled == false)
        #expect(runner.run(run)); #expect(host.clipboard == "ready")
    }
    @Test func callbackAndPreviewResponsesReachLaterSteps() throws {
        let (_, _, host, runner) = try setup()
        var run = action(#"""
        let cb = CallbackURL.create(); cb.baseURL = 'example://run'; cb.addParameter('text','a+b & café');
        check(cb.url.includes('%2B') || cb.url.includes('a+b'), 'callback query');
        check(cb.open() && cb.callbackResponse.result === 'Returned + café', 'callback response');
        let preview = HTMLPreview.create(); check(preview.show('<b>Preview</b>'), 'preview success');
        check(context.previewValues.answer.value === 42, 'preview values');
        check(context.callbackResponses[0].result === 'Returned + café', 'callback context');
        """#)
        run.steps.append(ActionStep("clipboard", ["template": "[[callback_result]]"]))
        #expect(runner.run(run), Comment(rawValue: runner.message ?? "")); #expect(host.clipboard == "Returned + café")
        host.previewSuccess = false
        #expect(runner.run(action("if (!HTMLPreview.create().show('cancel')) context.cancel();")) == false)
    }
    @Test func promptValuesRetainNativeTypesAndRequireLoadsHelpers() throws {
        let (_, _, host, runner) = try setup()
        #expect(runner.run(action(#"""
        let p = Prompt.create(); p.addDatePicker('date','Date',new Date('2020-01-02T03:04:05Z'));
        p.addNumberField('count','Count',2,true); p.addSwitch('flag','Flag',true); p.addSelect('tags','Tags',['a','b'],['a','b'],true); p.addButton('Use',42);
        check(p.show() && p.buttonPressed === 42, 'prompt button value');
        check(p.fieldValues.date instanceof Date && p.fieldValues.count === 2 && p.fieldValues.flag === true && p.fieldValues.tags.length === 2, 'prompt types');
        require('helpers'); app.setClipboard(loadedHelper('loaded'));
        """#)), Comment(rawValue: runner.message ?? "")); #expect(host.clipboard == "LOADED")
    }
    @Test func templateRangesEscapesDatesAndMarkup() {
        let note = Note(content: "# Title\nOne\nTwo\nThree")
        let value = Templates.render(#"[[title]]|[[display_title]]|[[line|2..-1]]|[[selection]]|\[[title]]|{{a+b & café}}"#, note: note)
        #expect(value == "# Title|Title|One\nTwo\nThree|# Title\nOne\nTwo\nThree|[[title]]|a%2Bb%20%26%20caf%C3%A9")
        #expect(Templates.render("[[date|+1 day|%Y-%m-%d]]", note: note, now: Date(timeIntervalSince1970: 0)).contains("1970-01-0"))
        #expect(Templates.render("[[line|..2]]", note: note) == "# Title\nOne")
    }
    @Test func mustacheUsesNestedContextsAndEscaping() throws {
        let data: [String: Any] = ["name": "<World>", "items": [["value": "one"], ["value": "two"]]]
        let rendered = try MustacheRenderer.render("{{name}}|{{{name}}}|{{#items}}{{value}}/{{name}};{{/items}}{{^missing}}empty{{/missing}}", data: data)
        #expect(rendered == "&lt;World&gt;|<World>|one/&lt;World&gt;;two/&lt;World&gt;;empty")
    }
    @Test func markdownEnginesRenderRepeatedDocuments() throws {
        for _ in 0..<20 {
            let multi = try ScriptMarkdown.render("# Heading\n\nText[^1]\n\n[^1]: Footnote", engine: "multi")
            #expect(multi.contains("<h1") && multi.contains("Footnote"))
            let github = try ScriptMarkdown.render("- [x] Done\n\n~~Removed~~", engine: "github")
            #expect(github.contains("checkbox") && github.contains("<del>Removed</del>"))
        }
    }
    @Test func cancellingAnActionStopsItsQueue() throws {
        let (library, _, host, runner) = try setup()
        let next = action("app.setClipboard('must not run');")
        try library.saveAction(next)
        #expect(!runner.run(action("app.queueAction(Action.find('API contract'), draft); context.cancel();")))
        #expect(host.clipboard.isEmpty)
    }
    @Test func cancellingAQueuedActionStopsLaterActions() throws {
        let (library, _, host, runner) = try setup()
        var cancel = action("context.cancel();"); cancel.name = "Cancel queued"
        var next = action("app.setClipboard('must not run');"); next.name = "After cancellation"
        try library.saveAction(cancel); try library.saveAction(next)
        #expect(!runner.run(action("app.queueAction(Action.find('Cancel queued'), draft); app.queueAction(Action.find('After cancellation'), draft);")))
        #expect(host.clipboard.isEmpty)
    }
}
