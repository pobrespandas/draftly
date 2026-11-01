import Foundation
import JavaScriptCore

@MainActor
struct ActionStepExecutor {
    unowned let runner: ActionRunner

    func perform(_ step: ActionStep, text: String, rendered: String, current: Note,
                 runtime: ActionScriptRuntime,
                 executeIncluded: (DraftAction, Note) throws -> Bool) throws -> Bool {
        guard step.type == "script" else {
            return try performNative(step, text: text, rendered: rendered, current: current,
                evaluate: { runtime.context.evaluateScript($0) }, executeIncluded: executeIncluded)
        }
        let context = runtime.context
        func checkCancellation() throws { try runner.checkCancellation() }
        switch step.type {
        case "script":
            let asynchronous = ["true", "1"].contains(step.values["allowAsync"] ?? step.values["allowAsynchronous"] ?? "false")
            if asynchronous, !runner.scriptTimeout.isFinite || runner.scriptTimeout <= 0 {
                throw DraftlyError.message("The asynchronous script timeout must be positive and finite.")
            }
            context.evaluateScript("__beginStep();")
            defer { context.evaluateScript("__endStep();") }
            runtime.scriptError = nil
            let evaluationDeadline = ScriptExecutionDeadline()
            runtime.legacyExecutionDeadline = evaluationDeadline
            try ActionRunner.limitExecution(context, seconds: runner.synchronousScriptTimeout, deadline: evaluationDeadline)
            let evaluation = context.evaluateScript(step.values["script"] ?? step.values["source"] ?? "")
            if evaluationDeadline.timedOut { throw ActionExecutionInterruption.timeout }
            if asynchronous, let evaluation, evaluation.isObject, evaluation.objectForKeyedSubscript("then")?.isObject == true {
                context.setObject(evaluation, forKeyedSubscript: "__pendingResult" as NSString)
                context.evaluateScript("{ let epoch=__stepEpoch; __pendingResult.catch(error => { if(epoch===__stepEpoch)__failure = String(error); }); }")
            }
            if let scriptError = runtime.scriptError { throw DraftlyError.message(scriptError) }
            if asynchronous {
                let deadline = Date().addingTimeInterval(runner.scriptTimeout)
                while context.objectForKeyedSubscript("__completed")?.toBool() != true {
                    try checkCancellation()
                    if context.objectForKeyedSubscript("__cancelled")?.toBool() == true { return false }
                    if let failure = context.objectForKeyedSubscript("__failure"), !failure.isNull, !failure.isUndefined { throw DraftlyError.message(failure.toString()) }
                    if evaluationDeadline.timedOut { throw ActionExecutionInterruption.timeout }
                    if let scriptError = runtime.scriptError { throw DraftlyError.message(scriptError) }
                    guard Date() < deadline else { throw ActionExecutionInterruption.timeout }
                    context.evaluateScript("__drainTimers();")
                    RunLoop.current.run(until: Date().addingTimeInterval(0.005))
                }
            }
        default: break
        }
        return true
    }

    func performNative(_ step: ActionStep, text: String, rendered: String, current: Note,
                       evaluate: (String) -> Void,
                       executeIncluded: (DraftAction, Note) throws -> Bool) throws -> Bool {
        let library = runner.library, editor = runner.editor
        func platform(_ operation: String, _ values: [String: Any]) throws -> Any? { try runner.platform(operation, values) }
        func renderTemplate(_ text: String, note: Note) throws -> String { try runner.renderTemplate(text, note: note) }
        func renderURL(_ text: String, note: Note, encodeTags: Bool) throws -> String { try runner.renderURL(text, note: note, encodeTags: encodeTags) }
        func json(_ object: Any) throws -> String { try runner.json(object) }
        func noteValue(_ note: Note) -> [String: Any] { runner.noteValue(note) }
        func flushEditor() throws { try runner.flushEditor() }
        func checkCancellation() throws { try runner.checkCancellation() }
        switch step.type {
        case "configurationKey": break
        case "clipboard":
            if ["html", "richText"].contains(step.values["output"] ?? "") {
                let html = try MarkdownPreferences.render(rendered, defaults: runner.markdownDefaults)
                _ = try platform("htmlToClipboard", ["html": html])
                break
            }
            let mode = step.values["writeType"] ?? "replace"
            guard ["replace", "append", "prepend"].contains(mode) else { throw DraftlyError.message("Unsupported clipboard write type: \(mode)") }
            let previous = mode == "replace" ? "" : try platform("getClipboard", [:]) as? String ?? ""
            let result = mode == "append" ? previous + rendered : mode == "prepend" ? rendered + previous : rendered
            _ = try platform("clipboard", ["text": result])
        case "share": _ = try platform("share", ["text": rendered])
        case "url", "callbackUrl":
            let raw = step.values["url"] ?? text
            let url = try renderURL(raw, note: current, encodeTags: step.values["encodeTags"] != "false")
            if step.type == "callbackUrl" {
                let response = try platform("callbackURL", ["url": url, "waitForResponse": step.values["waitForResponse"] != "false"]) as? [String: Any] ?? [:]
                let status = response["status"] as? String ?? "error"
                if status == "cancelled" { return false }
                guard status == "success" else { throw DraftlyError.message("The callback URL returned \(status).") }
                if step.values["waitForResponse"] != "false" {
                    let parameters = response["parameters"] as? [String: String] ?? [:]
                    for (key, value) in parameters { runner.customTags["callback_" + key] = value }
                    let parametersJSON = try json(parameters)
                    evaluate("context.callbackResponses.push(JSON.parse(\(try json(parametersJSON))));")
                }
            } else { _ = try platform("openURL", ["url": url]) }
        case "insertText": try editor.replace(editor.safeSelection, with: rendered); try flushEditor()
        case "createDraft":
            let creation = try ActionCreateDraftStep(step, text: rendered, validateSyntax: { _ = try library.syntaxDefinition(named: $0) }) { try renderTemplate($0, note: current) }
            try library.saveNote(creation.note, preserveRevision: false, preserveDates: true)
            if creation.opensInEditor { editor.load(creation.note) }
        case "file", "export":
            let file = try ActionFileStep(step, text: rendered) { try renderTemplate($0, note: current) }
            _ = try platform("saveFile", file.values)
        case "runShortcut":
            let result = try platform("shortcut", ["name": step.values["name"] ?? "", "text": rendered, "waitForResponse": step.values["waitForResponse"] != "false"])
            if step.values["waitForResponse"] != "false", let result {
                runner.customTags["shortcut_result"] = String(describing: result)
                evaluate("context.callbackResponses.push(\(try json(["result": result])));")
            }
        case "runAppleScript":
            let result = try platform("appleScript", ["source": step.values["script"] ?? step.values["source"] ?? "", "subroutine": "execute", "arguments": [noteValue(current)]])
            evaluate("context.appleScriptResponses.push(__appleScriptValue(\(try json(AppleScriptValueTransport.encode(result ?? NSNull())))));")
        case "htmlpreview":
            let html = rendered.range(of: "<[^>]+>", options: .regularExpression) == nil ? MarkdownRenderer.page(try MarkdownPreferences.render(rendered, defaults: runner.markdownDefaults)) : rendered
            let result = try platform("htmlPreview", ["html": html, "hideInterface": step.values["hideInterface"] == "true"])
            if result as? Bool == false || (result as? [String: Any])?["success"] as? Bool == false { return false }
            if let fields = (result as? [String: Any])?["values"] as? [String: Any] { evaluate("context.previewValues = \(try json(fields));") }
        case "defineTemplateTag":
            runner.customTags[step.values["name"] ?? step.values["tagName"] ?? ""] = rendered
        case "configureWindow":
            guard let uiOperation = runner.uiOperation else { throw DraftlyError.message("Window configuration needs an open editor window.") }
            _ = try uiOperation(["operation": "configureWindow", "values": step.values])
        case "prompt":
            let prompt = try ActionPromptStep(step) { try renderTemplate($0, note: current) }
            guard let tags = try prompt.tags(from: platform("prompt", prompt.values)) else { return false }
            runner.customTags.merge(tags) { _, new in new }
        case "mail", "message":
            let body = step.values["renderMarkdown"] == "true"
                ? try MarkdownPreferences.render(rendered, defaults: runner.markdownDefaults) : rendered
            var resolved = step
            if step.values["renderMarkdown"] == "true" { resolved.values["isBodyHTML"] = "true" }
            let message = try ActionMessageStep(resolved, text: body) { try renderTemplate($0, note: current) }
            if try !message.accepted(platform(message.operation, message.values)) { return false }
        case "listInReminders":
            let listName = try renderTemplate(step.values["list"] ?? step.values["listTemplate"] ?? "Reminders", note: current)
            guard let list = try platform("eventAPI", ["entity": "list", "operation": "findOrCreate", "title": listName]) as? [String: Any] else { throw DraftlyError.message("The Reminders list was not found.") }
            for line in rendered.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                _ = try platform("eventAPI", ["entity": "reminder", "operation": "update", "value": ["title": line, "list": list]])
            }
        case "openIn": _ = try platform("shareFile", ["text": rendered, "name": try renderTemplate(step.values["name"] ?? "[[safe_title]].txt", note: current)])
        case "print":
            let markdown = step.values["format"] == "markdown"
            let body = markdown ? try MarkdownPreferences.render(rendered, defaults: runner.markdownDefaults) : rendered
            let values = step.values.merging(["text": body, "format": markdown ? "html" : step.values["format"] ?? "plainText"], uniquingKeysWith: { _, new in new })
            if try platform("print", values) as? Bool == false { return false }
        case "speak":
            if try platform("speak", ["text": rendered, "settings": ["autoStart": step.values["autoStart"] != "false", "autoClose": step.values["autoClose"] != "false"]]) as? Bool == false { return false }
        case "reminder", "event": _ = try platform(step.type, ["text": rendered])
        case "includeAction":
            guard let included = library.actions.first(where: { $0.name == step.values["name"] }) else { throw DraftlyError.message("The included action was not found.") }
            if try !executeIncluded(included, current) { return false }
        default: throw DraftlyError.message("Unsupported step: \(step.type)")
        }
        return true
    }
}
