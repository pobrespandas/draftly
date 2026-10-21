import Foundation
import Testing
@testable import DraftlyCore

@Suite("Execution scripting API") @MainActor
struct ExecutionActionAPITests {
    @Test(arguments: [false, true])
    func contextStopsLaterStepsButFinishesTheCurrentScript(worker: Bool) async throws {
        let cases: [(call: String, message: String, cancelled: Bool)] = [
            ("context.cancel('Reason')", "Reason", true),
            ("context.fail()", "Action failed", false),
            ("context.fail('')", "Action failed", false),
            ("context.fail('Reason café 🐼')", "Reason café 🐼", false)
        ]
        for item in cases {
            let (library, _, host, runner) = try makeAPIContext()
            var value = makeAPIAction("var result=" + item.call + ";app.setClipboard(typeof result);")
            value.presentation.notifyOnError = true
            value.steps.append(ActionStep("clipboard", ["template": "must not run"]))
            let succeeded = await ActionTestExecution.succeeds(value, runner: runner, worker: worker)
            #expect(!succeeded)
            let report = try #require(runner.lastReport)
            #expect(report.result == (item.cancelled ? .cancelled : .failure(item.message)))
            #expect(report.reason == (item.cancelled ? .cancelled : .error))
            #expect(host.clipboard == "undefined")
            #expect(host.calls.filter { $0.0 == "clipboard" }.count == 1)
            let runs = library.runs.filter { $0.actionID == value.id }
            try #require(runs.count == 1)
            #expect(runs[0].status == (item.cancelled ? "Cancelled" : "Error"))
            #expect(runs[0].message == item.message)
            let notifications = host.calls.filter { $0.0 == "actionNotification" }
            #expect(notifications.count == (item.cancelled ? 0 : 1))
            if !item.cancelled {
                let payload = try #require(notifications.first?.1)
                #expect(payload["title"] as? String == value.name)
                #expect(payload["message"] as? String == item.message)
            }
        }
    }

    @Test(arguments: [false, true])
    func contextSuccessParametersAreExportedOnlyForSuccessfulRuns(worker: Bool) async throws {
        let (_, _, _, runner) = try makeAPIContext()
        let success = makeAPIAction(#"""
        check(context.addSuccessParameter('result','café + 🐼 &?%')===undefined,'void return');
        check(context.successParameters.result==='café + 🐼 &?%','raw value');
        context.addSuccessParameter('result','replaced');
        context.addSuccessParameter('','');
        for(const key of ['__proto__','constructor','toString']) {
            check(context.addSuccessParameter(key,'café + 🐼 &?%')===undefined,'reserved key return');
        }
        """#)
        #expect(await ActionTestExecution.succeeds(success, runner: runner, worker: worker),
                Comment(rawValue: runner.message ?? ""))
        #expect(runner.successParameters == ["result": "replaced", "": "",
            "__proto__": "café + 🐼 &?%", "constructor": "café + 🐼 &?%", "toString": "café + 🐼 &?%"])
        #expect(await ActionTestExecution.succeeds(makeAPIAction("check(Object.keys(context.successParameters).length===0,'fresh run');"),
                                                 runner: runner, worker: worker))
        #expect(runner.successParameters.isEmpty)
        for ending in ["context.cancel();", "context.fail('Neutral failure');", "throw new Error('stop');"] {
            let stopped = makeAPIAction("context.addSuccessParameter('result','secret');" + ending)
            #expect(!(await ActionTestExecution.succeeds(stopped, runner: runner, worker: worker)))
            #expect(runner.successParameters.isEmpty)
        }
        for arguments in ["42,'value'", "'key',42"] {
            #expect(!(await ActionTestExecution.succeeds(makeAPIAction("context.addSuccessParameter(\(arguments));"),
                                                        runner: runner, worker: worker)))
            #expect(runner.message?.contains("must be strings") == true)
            #expect(runner.successParameters.isEmpty)
        }
    }

    @Test func finalResultChoosesAndEncodesOnlyItsOwnCallback() throws {
        let targets = ["x-success": "test://success?keep=1&result=old", "x-cancel": "test://cancel", "x-error": "test://error"]
        let url = try #require(ActionExecutionResult.success.callbackURL(parameters: targets, successParameters: ["result": "café + 🐼"]))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.filter { $0.name == "result" }.map(\.value) == ["café + 🐼"])
        #expect(items.contains { $0.name == "keep" && $0.value == "1" })
        #expect(ActionExecutionResult.cancelled.callbackURL(parameters: targets, successParameters: ["result": "unused"])?.absoluteString == "test://cancel")
        let error = try #require(ActionExecutionResult.failure("Failed + café").callbackURL(parameters: targets))
        #expect(URLComponents(url: error, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Failed + café")
        #expect(ActionExecutionResult.success.callbackURL(parameters: [:]) == nil)
        #expect(ActionExecutionResult.success.callbackURL(parameters: ["x-success": "relative/path"]) == nil)
    }

    @Test func anotherWindowCannotRunActionsInTheSameLibraryDuringAHostCall() throws {
        let (library, editor, host, runner) = try makeAPIContext()
        let second = ActionRunner(library: library, editor: editor)
        var nested: ActionExecutionResult?
        host.onPerform = { operation in
            if operation == "clipboard" { nested = second.runResult(makeAPIAction("editor.setText('overwritten');")) }
        }
        let original = editor.content
        #expect(runner.run(makeAPIAction("app.setClipboard('outer');")))
        #expect(nested == .failure("An action is already running in this library."))
        #expect(editor.content == original)
        host.onPerform = nil
        #expect(second.run(makeAPIAction("editor.setText('after release');")))
        #expect(editor.content == "after release")
    }

    @Test func synchronousTimeoutStopsLaterStepsAndSuccessEffects() throws {
        let (library, editor, host, runner) = try makeAPIContext()
        runner.synchronousScriptTimeout = 0.02
        var value = makeAPIAction("while(true) {}")
        value.afterSuccess = "archive"
        value.steps.append(ActionStep("clipboard", ["template":"must not run"]))
        #expect(!runner.run(value))
        #expect(host.clipboard.isEmpty)
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
        runner.synchronousScriptTimeout = 0
        #expect(!runner.run(makeAPIAction("app.setClipboard('invalid timeout');")))
        #expect(runner.message?.contains("positive and finite") == true)
        #expect(host.clipboard.isEmpty)
    }

    @Test func shortcutResponsesReachContextInExecutionOrder() throws {
        let (_, _, host, runner) = try makeAPIContext()
        let value = DraftAction(name:"Shortcut context",steps:[
            ActionStep("runShortcut",["name":"Fixture","template":"Input"]),
            ActionStep("script",["script":"if(context.callbackResponses[0].result!=='Shortcut output')throw new Error('step response');let s=Shortcut.create('Fixture');if(!s.run('Other'))throw new Error('run');if(context.callbackResponses.length!==2 || context.callbackResponses[1].result!==s.result)throw new Error('script response');"])
        ])
        #expect(runner.run(value),Comment(rawValue:runner.message ?? ""))
        #expect(host.calls.filter { $0.0 == "shortcut" }.count == 2)
    }

    @Test func contextConfigurationDefaultsAndAppleScriptResponsesKeepTheirTypes() throws {
        let (_, _, host, runner) = try makeAPIContext()
        let value=DraftAction(name:"Context values",steps:[
            ActionStep("configurationKey",["key":"enabled","dataType":"boolean","defaultBoolValue":"true"]),
            ActionStep("configurationKey",["key":"count","dataType":"number","defaultNumberValue":"2.5"]),
            ActionStep("configurationKey",["key":"label","dataType":"string","defaultStringValue":"café"]),
            ActionStep("runAppleScript",["script":"fixture source"]),
            ActionStep("script",["script":"if(context.configuredValues.enabled!==true || context.configuredValues.count!==2.5 || context.configuredValues.label!=='café')throw new Error('typed defaults');if(action.configuredValues!==context.configuredValues)throw new Error('shared values');if(context.appleScriptResponses[0].value!==42)throw new Error('step response');const apple=AppleScript.create('fixture');if(!apple.execute('execute') || context.appleScriptResponses.length!==2 || context.appleScriptResponses[1].value!==42)throw new Error('script response');const p=new SelectPrompt();if(p.addItem(SelectPromptItem.create('legacy','Existing overload'))!==true)throw new Error('object overload');"])
        ])
        #expect(runner.run(value),Comment(rawValue:runner.message ?? ""))
        #expect(host.calls.filter { $0.0 == "appleScript" }.count == 2)
    }

    @Test func circularIncludesFailBeforeTheFirstSideEffect() throws {
        let (library, _, host, runner) = try makeAPIContext()
        let a = DraftAction(name:"Cycle A",steps:[ActionStep("clipboard",["text":"should not run"]),ActionStep("includeAction",["name":"Cycle B"])])
        let b = DraftAction(name:"Cycle B",steps:[ActionStep("includeAction",["name":"Cycle A"])])
        try library.saveAction(a);try library.saveAction(b)
        #expect(!runner.run(a));#expect(host.clipboard.isEmpty)
        #expect(runner.message?.contains("itself") == true)
    }

    @Test func failedDraftUpdateDoesNotApplySuccessDisposition() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        let original=editor.content
        runner.uiOperation = { _ in library.beforeBatchCommit = { throw DraftlyError.message("Storage unavailable") }; return true }
        var a=makeAPIAction("editor.pinningEnabled=true;draft.content='Unsaved';draft.update();")
        a.afterSuccess="archive"
        #expect(!runner.run(a))
        #expect(library.notes.first { $0.id == editor.noteID }?.content == original)
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
        #expect(editor.content == original)
    }

    @Test func grayFlagAndTrashKeepArchiveState() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        draft.flagType=7;draft.folder='archive';draft.update();
        check(Draft.flagged('gray')[0]===draft,'gray identity');
        draft.folder='trash';draft.update();check(draft.isArchived,'previous archive state');
        draft.folder='archive';draft.update();check(!draft.isTrashed,'restore');
        let caught=[];try{draft.folder='missing';}catch(e){caught.push(e);}
        check(caught.length===1,'invalid folder');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func finishedStepTimersCannotMutateTheNextStep() throws {
        let (_, _, host, runner) = try makeAPIContext()
        let value=DraftAction(name:"Timer isolation",steps:[
            ActionStep("script",["allowAsync":"true","script":"var stale=script;setTimeout(()=>app.setClipboard('late'),0);script.complete();"]),
            ActionStep("script",["allowAsync":"true","script":"stale.complete();setTimeout(()=>{app.setClipboard('current');script.complete();},10);"])
        ])
        #expect(runner.runResult(value) == .success)
        #expect(host.clipboard == "current")
        #expect(host.calls.filter { $0.0 == "clipboard" }.count == 1)
    }

    @Test func commonResultDistinguishesFailureCancellationAndSuccess() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.runResult(makeAPIAction("context.cancel();")) == .cancelled)
        #expect(runner.runResult(makeAPIAction("throw new Error('Expected');")) == .failure("Error: Expected"))
        #expect(runner.runResult(makeAPIAction("script.complete();script.complete();",async:true)) == .success)
        #expect(runner.run(makeAPIAction("Draft.query('', 'all', [], [], 'accessed');")))
    }

    @Test func successMetadataIsAppliedOnlyAfterSuccessfulSteps() throws {
        let (library, editor, host, runner) = try makeAPIContext()
        var value = makeAPIAction("editor.setText('Changed');")
        value.presentation.addTags = ["done"]; value.presentation.removeTags = ["old"]
        value.presentation.flagAfterSuccess = 7; value.presentation.notifyOnSuccess = true
        #expect(runner.run(value))
        #expect(library.notes.first { $0.id == editor.noteID }?.tags == ["done"])
        #expect(library.notes.first { $0.id == editor.noteID }?.flag == 7)
        #expect(host.calls.contains { $0.0 == "actionNotification" })
        value.steps = [ActionStep("script", ["script": "throw new Error('Stop');"])]
        value.presentation.addTags = ["should-not-appear"]; value.presentation.flagAfterSuccess = 1
        #expect(!runner.run(value))
        #expect(library.notes.first { $0.id == editor.noteID }?.tags == ["done"])
        #expect(library.notes.first { $0.id == editor.noteID }?.flag == 7)
    }
    @Test func cancelledConfirmationDoesNotRunStepsAndIsLogged() throws {
        let (library, editor, host, runner) = try makeAPIContext()
        var value = makeAPIAction("editor.setText('Do not run');")
        value.presentation.confirmBeforeRun = true; host.confirmation = false
        let before = editor.content
        #expect(!runner.run(value))
        #expect(editor.content == before)
        #expect(library.runs.first?.status == "Cancelled")
    }
    @Test func asyncCompletionWaitsAndSharesStateWithNextStep() throws {
        let (_, _, host, runner) = try makeAPIContext()
        var run = makeAPIAction("let answer; setTimeout(() => { answer = 'ready'; script.complete(); }, 5);", async: true)
        run.steps.append(ActionStep("script", ["script": "app.setClipboard(answer);"]))
        #expect(runner.run(run), Comment(rawValue: runner.message ?? ""))
        #expect(host.clipboard == "ready")
    }
    @Test func asyncPromiseRejectionAndTimeoutStopDisposition() throws {
        let (library, editor, host, runner) = try makeAPIContext()
        runner.scriptTimeout = 0.02
        var timedOut = makeAPIAction("Promise.resolve('unused');", async: true); timedOut.afterSuccess = "archive"
        timedOut.steps.append(ActionStep("clipboard", ["template": "must not run"]))
        #expect(!runner.run(timedOut))
        #expect(runner.message?.contains("timed out") == true)
        #expect(host.calls.isEmpty)
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
        #expect(!runner.run(makeAPIAction("Promise.reject(new Error('Async failure'));", async: true)))
        #expect(runner.message?.contains("Async failure") == true)
    }
    @Test func includedActionsShareJavaScriptAndDoNotApplyOwnDisposition() throws {
        let (library, editor, host, runner) = try makeAPIContext()
        var helper = DraftAction(name: "Helper", steps: [ActionStep("script", ["script": "function helper(value) { return value + '!'; }"])]); helper.afterSuccess = "trash"
        try library.saveAction(helper)
        let run = DraftAction(name: "Parent", steps: [ActionStep("includeAction", ["name": "Helper"]), ActionStep("script", ["script": "app.setClipboard(helper('works'));"])])
        #expect(runner.run(run), Comment(rawValue: runner.message ?? ""))
        #expect(host.clipboard == "works!")
        #expect(library.notes.first { $0.id == editor.noteID }?.trashedAt == nil)
    }
    @Test func includedUnknownStepIsRejectedBeforeAnySideEffect() throws {
        let (library, _, host, runner) = try makeAPIContext()
        try library.saveAction(DraftAction(name: "Unknown", steps: [ActionStep("future")]))
        let run = DraftAction(name: "Parent", steps: [ActionStep("clipboard", ["template": "must not run"]), ActionStep("includeAction", ["name": "Unknown"])])
        #expect(!runner.run(run)); #expect(host.calls.isEmpty)
    }
    @Test func disabledUnknownStepsSurviveImportAndDoNotBlockExecution() throws {
        let (_, _, host, runner) = try makeAPIContext()
        let data = Data(#"{"name":"Disabled","steps":[{"type":"future","isEnabled":false,"data":{"key":"keep"}},{"type":"clipboard","data":{"template":"ready"}}]}"#.utf8)
        let run = try #require(ActionImporter.decode(data).first)
        #expect(run.steps.count == 2 && run.steps[0].isEnabled == false)
        #expect(runner.run(run)); #expect(host.clipboard == "ready")
    }
    @Test func callbackAndPreviewResponsesReachLaterSteps() throws {
        let (_, _, host, runner) = try makeAPIContext()
        var run = makeAPIAction(#"""
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
        #expect(runner.run(makeAPIAction("if (!HTMLPreview.create().show('cancel')) context.cancel();")) == false)
    }
    @Test func cancellingAnActionStopsItsQueue() throws {
        let (library, _, host, runner) = try makeAPIContext()
        let next = makeAPIAction("app.setClipboard('must not run');")
        try library.saveAction(next)
        #expect(!runner.run(makeAPIAction("app.queueAction(Action.find('API contract'), draft); context.cancel();")))
        #expect(host.clipboard.isEmpty)
    }
    @Test func cancellingAQueuedActionStopsLaterActions() throws {
        let (library, _, host, runner) = try makeAPIContext()
        var cancel = makeAPIAction("context.cancel();"); cancel.name = "Cancel queued"
        var next = makeAPIAction("app.setClipboard('must not run');"); next.name = "After cancellation"
        try library.saveAction(cancel); try library.saveAction(next)
        #expect(!runner.run(makeAPIAction("app.queueAction(Action.find('Cancel queued'), draft); app.queueAction(Action.find('After cancellation'), draft);")))
        #expect(host.clipboard.isEmpty)
    }
}
