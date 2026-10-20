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
            try ActionRunner.limitExecution(context, seconds: runner.synchronousScriptTimeout)
            let evaluation = context.evaluateScript(step.values["script"] ?? step.values["source"] ?? "")
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
                let parameters = response["parameters"] as? [String: String] ?? [:]
                for (key, value) in parameters { runner.customTags["callback_" + key] = value }
                evaluate("context.callbackResponses.push(\(try json(parameters)));")
            } else { _ = try platform("openURL", ["url": url]) }
        case "insertText": try editor.replace(editor.safeSelection, with: rendered); try flushEditor()
        case "createDraft":
            let location = step.values["folder"] ?? step.values["location"] ?? "inbox"
            guard ["inbox", "archive"].contains(location) else { throw DraftlyError.message("The new draft location is invalid.") }
            let syntax = ["syntax", "assignSyntax", "syntaxName", "grammarName", "grammarType"].compactMap { step.values[$0] }.first { !$0.isEmpty } ?? "Markdown"
            _ = try library.syntaxDefinition(named: syntax)
            let open = step.values["openInEditor"] != "false"
            var created = Note(content: rendered, tags: TagRules.normalize((try renderTemplate(step.values["tags"] ?? step.values["assignTags"] ?? "", note: current)).split(separator: ",").map(String.init)), flag: ["true", "1"].contains(step.values["flagged"] ?? "false") ? 1 : 0, isArchived: location == "archive", syntax: syntax, accessedAt: open ? Date() : nil)
            if let flag = step.values["flagType"].flatMap(Int.init) { guard (0...7).contains(flag) else { throw DraftlyError.message("The new draft flag is invalid.") }; created.flag = flag }
            try library.saveNote(created, preserveRevision: false, preserveDates: true)
            if open { editor.load(created) }
        case "file":
            let name = try renderTemplate(step.values["fileNameTemplate"] ?? step.values["name"] ?? "[[safe_title]].md", note: current)
            _ = try platform("saveFile", ["text": rendered, "name": name, "bookmark": step.values["useBookmark"] == "true" ? step.values["bookmarkName"] ?? "" : "", "folder": try renderTemplate(step.values["folderTemplate"] ?? "", note: current), "mode": step.values["writeType"] ?? "create"])
        case "runShortcut":
            let result = try platform("shortcut", ["name": step.values["name"] ?? "", "text": rendered])
            if let result {
                runner.customTags["shortcut_result"] = String(describing: result)
                if step.values["waitForResponse"] != "false" {
                    evaluate("context.callbackResponses.push(\(try json(["result": result])));")
                }
            }
        case "runAppleScript":
            let result = try platform("appleScript", ["source": step.values["script"] ?? step.values["source"] ?? "", "subroutine": "execute", "arguments": [noteValue(current)]])
            evaluate("context.appleScriptResponses.push(\(try json(result ?? NSNull())));")
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
            let key = step.values["key"] ?? "prompt"
            let titles = (step.values["buttons"] ?? "OK").split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard !key.isEmpty, !titles.contains(where: { $0.isEmpty }) else { throw DraftlyError.message("The prompt key and button titles must not be empty.") }
            let includeText = ["true", "1"].contains(step.values["includeTextField"] ?? "false")
            let fields: [[String: Any]] = includeText ? [["key": "text", "label": "", "kind": "text", "value": try renderTemplate(step.values["textFieldDefault"] ?? "", note: current)]] : []
            let response = try platform("prompt", ["title": try renderTemplate(step.values["title"] ?? "Prompt", note: current), "message": try renderTemplate(step.values["message"] ?? "", note: current), "isCancellable": step.values["includeCancelButton"] != "false", "fields": fields, "buttons": titles.map { ["title": $0] }]) as? [String: Any]
            guard let response else { return false }
            guard let index = response["index"] as? Int, titles.indices.contains(index) else { throw DraftlyError.message("The prompt returned an invalid button.") }
            runner.customTags[key + "_button"] = titles[index]
            runner.customTags[key + "_text"] = (response["fields"] as? [String: Any])?["text"] as? String ?? ""
        case "mail", "message":
            var values: [String: Any] = ["subject": try renderTemplate(step.values["subject"] ?? "", note: current), "body": rendered]
            for key in ["toRecipients", "ccRecipients", "bccRecipients", "replyToRecipients"] { values[key] = try renderTemplate(step.values[key] ?? "", note: current).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            values["isBodyHTML"] = step.values["isBodyHTML"] == "true"; values["sendInBackground"] = step.values["sendInBackground"] == "true"
            let response = try platform(step.type == "mail" ? "composeMail" : "composeMessage", values) as? [String: String] ?? [:]
            if response["status"] == "userCancelled" { return false }
            guard response["status"] == "sent" else { throw DraftlyError.message("Message composition failed: \(response["status"] ?? "unknownError")") }
        case "listInReminders":
            let listName = try renderTemplate(step.values["list"] ?? step.values["listTemplate"] ?? "Reminders", note: current)
            guard let list = try platform("eventAPI", ["entity": "list", "operation": "findOrCreate", "title": listName]) as? [String: Any] else { throw DraftlyError.message("The Reminders list was not found.") }
            for line in rendered.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                _ = try platform("eventAPI", ["entity": "reminder", "operation": "update", "value": ["title": line, "list": list]])
            }
        case "export": _ = try platform("saveFile", ["text": rendered, "name": try renderTemplate(step.values["name"] ?? "[[safe_title]].txt", note: current)])
        case "openIn": _ = try platform("shareFile", ["text": rendered, "name": try renderTemplate(step.values["name"] ?? "[[safe_title]].txt", note: current)])
        case "print":
            if try platform("print", step.values.merging(["text": rendered], uniquingKeysWith: { _, new in new })) as? Bool == false { return false }
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
