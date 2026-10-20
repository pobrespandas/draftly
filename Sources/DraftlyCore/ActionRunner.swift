import Foundation
import JavaScriptCore
import Combine
import Darwin

@MainActor
public final class EditorSession: ObservableObject {
    @Published public var noteID: UUID?
    @Published public var content = ""
    @Published public var selection = NSRange(location: 0, length: 0)
    @Published public var focusToken = UUID()
    @Published public var typewriterScrollingEnabled = false
    public var synchronizeScriptEdit: (() -> Void)?
    public var performUndo: ((Bool) -> Void)?
    public var focusForDictation: (() -> Bool)?
    public private(set) var recentNoteIDs: [UUID] = []
    public init() {}
    public func load(_ note: Note, focusEditor: Bool = true) { if let id = noteID, id != note.id { recentNoteIDs.removeAll { $0 == id }; recentNoteIDs.insert(id, at: 0) }; noteID = note.id; content = note.content; selection = NSRange(location: Int(note.scriptMetadata?["selectionStart"] ?? "0") ?? 0, length: Int(note.scriptMetadata?["selectionLength"] ?? "0") ?? 0); selection = safeSelection; if focusEditor { focusToken = UUID() } }
    public var safeSelection: NSRange {
        let count = (content as NSString).length
        let start = min(max(0, selection.location), count)
        return NSRange(location: start, length: min(max(0, selection.length), count - start))
    }
    public var selectedText: String { (content as NSString).substring(with: safeSelection) }
    public func replace(_ range: NSRange, with text: String) throws {
        guard range.location >= 0, range.length >= 0, range.location <= (content as NSString).length,
              range.length <= (content as NSString).length - range.location else { throw DraftlyError.message("The text range is outside the draft.") }
        content = (content as NSString).replacingCharacters(in: range, with: text)
        selection = NSRange(location: range.location + (text as NSString).length, length: 0)
    }
}

@MainActor
public protocol ActionHost: AnyObject {
    func perform(_ operation: String, values: [String: Any]) throws -> Any?
    func finishAction()
}

public extension ActionHost { func finishAction() {} }

public enum ActionExecutionResult: Equatable, Sendable {
    case success
    case cancelled
    case failure(String)
    public var succeeded: Bool { self == .success }
    public func callbackURL(parameters: [String: String], successParameters: [String: String] = [:]) -> URL? {
        let key: String
        var additions: [String: String] = [:]
        switch self {
        case .success: key = "x-success"; additions = successParameters
        case .cancelled: key = "x-cancel"
        case .failure(let message): key = "x-error"; additions = ["errorMessage": message]
        }
        guard let raw = parameters[key], var components = URLComponents(string: raw), components.scheme != nil else { return nil }
        if !additions.isEmpty {
            components.queryItems = (components.queryItems ?? []).filter { additions[$0.name] == nil }
                + additions.keys.sorted().map { URLQueryItem(name: $0, value: additions[$0]) }
        }
        return components.url
    }

}

@MainActor
public final class ActionRunner: ObservableObject {
    var markdownDefaults: UserDefaults = .standard
    private static var runningLibraries: Set<ObjectIdentifier> = []
    public internal(set) var successParameters: [String: String] = [:]
    public let library: LibraryStore
    public let editor: EditorSession
    public weak var host: (any ActionHost)?
    @Published public private(set) var isRunning = false
    @Published public var message: String?
    public var scriptTimeout: TimeInterval = 120
    public var synchronousScriptTimeout: TimeInterval = 10
    public var defaultWorkspace: (() -> Workspace)?
    public var currentWorkspace: (() -> Workspace)?
    public var uiOperation: (([String: Any]) throws -> Any?)?
    public var selectedDrafts: (() -> [Note])?
    public var applyWorkspace: ((Workspace) throws -> Void)?
    @Published public private(set) var activeSession: ActionExecutionSession?
    public private(set) var lastReport: ActionExecutionReport?
    private var terminationReason: ActionTerminationReason = .error
    private var runOutcome: ActionExecutionResult = .failure("The action did not complete.")
    var queued: [(DraftAction, Note)] = []
    private var logs: [String] = []
    var customTags: [String: String] = [:]
    private var executing: Set<UUID> = []
    public init(library: LibraryStore, editor: EditorSession, host: (any ActionHost)? = nil) {
        self.library = library; self.editor = editor; self.host = host
    }

    public func flushEditor() throws {
        guard let id = editor.noteID, var note = library.notes.first(where: { $0.id == id }) else { return }
        let contentChanged = note.content != editor.content
        note.content = editor.content
        let selection = editor.safeSelection
        note.scriptMetadata = note.scriptMetadata ?? [:]
        note.scriptMetadata?["selectionStart"] = String(selection.location)
        note.scriptMetadata?["selectionLength"] = String(selection.length)
        try library.saveNote(note, preserveDates: !contentChanged)
    }

    @discardableResult public func run(_ action: DraftAction) -> Bool { runResult(action).succeeded }

    @discardableResult public func runResult(_ action: DraftAction) -> ActionExecutionResult {
        runReport(action).result
    }

    public func cancel() { activeSession?.cancel() }

    @discardableResult public func runReport(_ action: DraftAction) -> ActionExecutionReport {
        let session = ActionExecutionSession(actionID: action.id)
        guard !isRunning else {
            message = "An action is already running."
            return session.finish(.failure(message!), reason: .busy, successParameters: [:])
        }
        let libraryID = ObjectIdentifier(library)
        guard Self.runningLibraries.insert(libraryID).inserted else {
            message = "An action is already running in this library."
            return session.finish(.failure(message!), reason: .busy, successParameters: [:])
        }
        activeSession = session
        defer { Self.runningLibraries.remove(libraryID); activeSession = nil }
        terminationReason = .error
        successParameters = [:]
        _ = executeRun(action)
        if !runOutcome.succeeded { successParameters = [:] }
        let reason: ActionTerminationReason = runOutcome.succeeded ? .success : runOutcome == .cancelled ? .cancelled : terminationReason
        let report = session.finish(runOutcome, reason: reason, successParameters: successParameters)
        lastReport = report
        return report
    }

    private func checkCancellation() throws {
        if activeSession?.cancellationRequested == true { throw ActionExecutionInterruption.cancelled }
    }

    private func executeRun(_ action: DraftAction) -> Bool {
        guard !isRunning else { message = "An action is already running."; return false }
        isRunning = true; queued = []; logs = []; customTags = [:]
        let sourceNoteID = editor.noteID
        defer { isRunning = false; executing = []; host?.finishAction() }
        do {
            try checkCancellation()
            if action.presentation.confirmBeforeRun {
                let response = try platform("confirmAction", ["name": action.name]) as? Bool ?? false
                guard response else {
                    message = "\(action.name) cancelled"
                    runOutcome = .cancelled
                    var run = ActionRun(actionName: action.name, status: "Cancelled", message: "Confirmation cancelled")
                    run.noteID = sourceNoteID; run.actionID = action.id; library.log(run)
                    return false
                }
            }
            try flushEditor()
            guard let id = editor.noteID, let note = library.notes.first(where: { $0.id == id }) else { throw DraftlyError.message("Create or select a draft first.") }
            var completed = try execute(action, note: note)
            var count = 0
            while completed && !queued.isEmpty {
                try checkCancellation()
                count += 1
                guard count <= 100 else { throw DraftlyError.message("The action queue exceeded 100 actions.") }
                let (next, queuedNote) = queued.removeFirst()
                try flushEditor()
                let note = library.notes.first(where: { $0.id == queuedNote.id }) ?? queuedNote
                try library.recordAccess(note.id)
                editor.load(note)
                completed = try execute(next, note: note)
            }
            try flushEditor()
            runOutcome = completed ? .success : .cancelled
            let status = completed ? "Success" : "Cancelled"
            message = completed ? (logs.last ?? "\(action.name) completed") : "\(action.name) cancelled"
            var run = ActionRun(actionName: action.name, status: status, message: logs.joined(separator: "\n")); run.noteID = note.id; run.actionID = action.id
            library.log(run)
            if completed && action.presentation.notifyOnSuccess { _ = try? platform("actionNotification", ["title": action.name, "message": message ?? "Complete"]) }
            return completed
        } catch {
            try? flushEditor()
            message = error.localizedDescription
            let cancelled = (error as? ActionExecutionInterruption) == .cancelled
            if (error as? ActionExecutionInterruption) == .timeout { terminationReason = .timeout }
            runOutcome = cancelled ? .cancelled : .failure(error.localizedDescription)
            var run = ActionRun(actionName: action.name, status: cancelled ? "Cancelled" : "Error", message: error.localizedDescription); run.noteID = sourceNoteID; run.actionID = action.id
            library.log(run)
            if !cancelled && action.presentation.notifyOnError { _ = try? platform("actionNotification", ["title": action.name, "message": error.localizedDescription]) }
            return false
        }
    }

    private func execute(_ action: DraftAction, note: Note) throws -> Bool {
        let steps = try expandedSteps(action)
        guard !executing.contains(action.id) else { throw DraftlyError.message("An included action refers to itself.") }
        executing.insert(action.id); defer { executing.remove(action.id) }
        let context = JSContext()!
        var scriptError: String?
        context.exceptionHandler = { _, value in scriptError = value?.toString() ?? "JavaScript error" }
        var acceptingCalls = true
        defer { acceptingCalls = false }
        let bridge: @convention(block) (String, String) -> String = { [weak self] operation, text in
            guard let self, acceptingCalls else { return "{\"error\":\"The action was closed.\"}" }
            do {
                let values = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
                let result = try self.dispatch(operation, values: values)
                let data = try JSONSerialization.data(withJSONObject: ["value": result ?? NSNull()], options: [.fragmentsAllowed])
                return String(decoding: data, as: UTF8.self)
            } catch {
                let data = try! JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])
                return String(decoding: data, as: UTF8.self)
            }
        }
        context.setObject(bridge, forKeyedSubscript: "__host" as NSString)
        let require: @convention(block) (String) -> JSValue? = { [weak self, weak context] path in
            guard let self, let context, acceptingCalls else { return nil }
            do {
                let source = try self.platform("requireScript", ["path": path]) as? String ?? ""
                return context.evaluateScript(source, withSourceURL: URL(fileURLWithPath: path))
            } catch {
                context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
                return nil
            }
        }
        context.setObject(require, forKeyedSubscript: "__require" as NSString)
        guard let url = Bundle.module.url(forResource: "Bridge", withExtension: "js") else { throw DraftlyError.message("The JavaScript bridge is missing.") }
        for name in ["datejs", "mustache"] {
            guard let resource = Bundle.module.url(forResource: name, withExtension: "js") else { throw DraftlyError.message("The \(name) runtime is missing.") }
            context.evaluateScript(try String(contentsOf: resource, encoding: .utf8))
        }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        let noteJSON = try json(noteValue(note))
        var configured: [String: Any] = action.configuredValues
        for step in steps where step.type == "configurationKey" {
            let key = step.values["key"] ?? ""
            let dataType = step.values["dataType"] ?? "string"
            let defaultKey = dataType == "boolean" ? "defaultBoolValue" : dataType == "number" ? "defaultNumberValue" : dataType == "text" ? "defaultTextValue" : "defaultStringValue"
            let value = action.configuredValues[key] ?? step.values["defaultValue"] ?? step.values[defaultKey] ?? ""
            configured[key] = value
            if step.values["dataType"] == "boolean" { configured[key] = value == "true" || value == "1" }
            if step.values["dataType"] == "number" { configured[key] = Double(value) ?? 0 }
        }
        let values = try json(configured)
        context.evaluateScript("var draft = new Draft(\(noteJSON)); var action = new Action(\(try json(actionValue(action)))); context.configuredValues = \(values); action.configuredValues = context.configuredValues;")
        if let scriptError { throw DraftlyError.message(scriptError) }
        for step in steps where step.isEnabled != false {
            try checkCancellation()
            activeSession?.enter(actionID: action.id, step: step)
            if context.objectForKeyedSubscript("__cancelled")?.toBool() == true { return false }
            if let failure = context.objectForKeyedSubscript("__failure"), !failure.isNull, !failure.isUndefined { throw DraftlyError.message(failure.toString()) }
            let text = step.values["template"] ?? step.values["text"] ?? "[[draft]]"
            let current = library.notes.first(where: { $0.id == note.id }) ?? note
            let rendered = try renderTemplate(text, note: current)
            switch step.type {
            case "configurationKey": break
            case "script":
                let asynchronous = ["true", "1"].contains(step.values["allowAsync"] ?? step.values["allowAsynchronous"] ?? "false")
                if asynchronous, !scriptTimeout.isFinite || scriptTimeout <= 0 {
                    throw DraftlyError.message("The asynchronous script timeout must be positive and finite.")
                }
                context.evaluateScript("__beginStep();")
                defer { context.evaluateScript("__endStep();") }
                scriptError = nil
                try Self.limitExecution(context, seconds: synchronousScriptTimeout)
                let evaluation = context.evaluateScript(step.values["script"] ?? step.values["source"] ?? "")
                if asynchronous, let evaluation, evaluation.isObject, evaluation.objectForKeyedSubscript("then")?.isObject == true {
                    context.setObject(evaluation, forKeyedSubscript: "__pendingResult" as NSString)
                    context.evaluateScript("{ let epoch=__stepEpoch; __pendingResult.catch(error => { if(epoch===__stepEpoch)__failure = String(error); }); }")
                }
                if let scriptError { throw DraftlyError.message(scriptError) }
                if asynchronous {
                    let deadline = Date().addingTimeInterval(scriptTimeout)
                    while context.objectForKeyedSubscript("__completed")?.toBool() != true {
                        try checkCancellation()
                        if context.objectForKeyedSubscript("__cancelled")?.toBool() == true { return false }
                        if let failure = context.objectForKeyedSubscript("__failure"), !failure.isNull, !failure.isUndefined { throw DraftlyError.message(failure.toString()) }
                        if let scriptError { throw DraftlyError.message(scriptError) }
                        guard Date() < deadline else { throw ActionExecutionInterruption.timeout }
                        context.evaluateScript("__drainTimers();")
                        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
                    }
                }
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
                    for (key, value) in parameters { customTags["callback_" + key] = value }
                    context.evaluateScript("context.callbackResponses.push(\(try json(parameters)));")
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
                    customTags["shortcut_result"] = String(describing: result)
                    if step.values["waitForResponse"] != "false" {
                        context.evaluateScript("context.callbackResponses.push(\(try json(["result": result])));")
                    }
                }
            case "runAppleScript":
                let result = try platform("appleScript", ["source": step.values["script"] ?? step.values["source"] ?? "", "subroutine": "execute", "arguments": [noteValue(current)]])
                context.evaluateScript("context.appleScriptResponses.push(\(try json(result ?? NSNull())));")
            case "htmlpreview":
                let html = rendered.range(of: "<[^>]+>", options: .regularExpression) == nil ? MarkdownRenderer.page(try MarkdownPreferences.render(rendered, defaults: markdownDefaults)) : rendered
                let result = try platform("htmlPreview", ["html": html, "hideInterface": step.values["hideInterface"] == "true"])
                if result as? Bool == false || (result as? [String: Any])?["success"] as? Bool == false { return false }
                if let fields = (result as? [String: Any])?["values"] as? [String: Any] { context.evaluateScript("context.previewValues = \(try json(fields));") }
            case "defineTemplateTag":
                customTags[step.values["name"] ?? step.values["tagName"] ?? ""] = rendered
            case "configureWindow":
                guard let uiOperation else { throw DraftlyError.message("Window configuration needs an open editor window.") }
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
                customTags[key + "_button"] = titles[index]
                customTags[key + "_text"] = (response["fields"] as? [String: Any])?["text"] as? String ?? ""
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
                if try !execute(included, note: current) { return false }
            default: throw DraftlyError.message("Unsupported step: \(step.type)")
            }
            context.evaluateScript("__tags = \(try json(customTags));")
        }
        try checkCancellation()
        if context.objectForKeyedSubscript("__cancelled")?.toBool() == true { return false }
        if let failure = context.objectForKeyedSubscript("__failure"), !failure.isNull, !failure.isUndefined { throw DraftlyError.message(failure.toString()) }
        try flushEditor()
        if var original = library.notes.first(where: { $0.id == note.id }) {
            switch action.afterSuccess {
            case "archive", "1": original.isArchived = true
            case "trash", "2": original.trashedAt = Date()
            default: break
            }
            original.tags = TagRules.normalize(original.tags + action.presentation.addTags)
                .filter { !TagRules.normalize(action.presentation.removeTags).contains($0) }
            if let flag = action.presentation.flagAfterSuccess { original.flag = min(7, max(0, flag)) }
            try library.saveNote(original)
        }
        return true
    }

    private func expandedSteps(_ action: DraftAction, path: Set<UUID> = []) throws -> [ActionStep] {
        guard !path.contains(action.id) else { throw DraftlyError.message("An included action refers to itself.") }
        guard path.count < 50 else { throw DraftlyError.message("The included action depth exceeded 50.") }
        guard action.unsupportedSteps.isEmpty else { throw DraftlyError.message("Unsupported steps: \(action.unsupportedSteps.joined(separator: ", ")). No steps were run.") }
        var result: [ActionStep] = []
        for step in action.steps where step.isEnabled != false {
            if step.type == "includeAction" {
                guard let included = library.actions.first(where: { $0.name == step.values["name"] }) else { throw DraftlyError.message("The included action was not found.") }
                result += try expandedSteps(included, path: path.union([action.id]))
            } else { result.append(step) }
        }
        return result
    }
    func renderTemplate(_ text: String, note: Note, tags: [String: String]? = nil) throws -> String {
        var values = tags ?? customTags
        if text.contains("[[clipboard]]") { values["clipboard"] = try platform("getClipboard", [:]) as? String ?? "" }
        if text.contains("[[latitude]]") || text.contains("[[longitude]]"), let location = try platform("location", [:]) as? [String: Double] {
            values["latitude"] = String(location["latitude"] ?? 0); values["longitude"] = String(location["longitude"] ?? 0)
        }
        var loadError: Error?
        let result = try Templates.renderConfigured(text, note: note, selection: editor.selectedText, custom: values, selectionRange: editor.safeSelection, defaults: markdownDefaults, loadTemplate: { path in
            do { return try self.platform("fileAPI", ["operation": "readString", "storage": "local", "path": "Templates/" + path]) as? String }
            catch { loadError = error; return nil }
        })
        if let loadError { throw loadError }; return result
    }
    private func renderURL(_ text: String, note: Note, encodeTags: Bool) throws -> String {
        guard encodeTags else { return try renderTemplate(text, note: note) }
        let regex = try NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result), let original = Range(match.range, in: text) else { continue }
            let replacement = try renderTemplate(String(text[original]), note: note)
            result.replaceSubrange(range, with: replacement.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? replacement)
        }
        return result
    }
    private static func limitExecution(_ context: JSContext, seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds > 0 else { throw DraftlyError.message("The synchronous script timeout must be positive and finite.") }
        // JavaScriptCore exports this limit on macOS. Do not require a private symbol at link time.
        typealias Callback = @convention(c) (JSContextRef?, UnsafeMutableRawPointer?) -> Bool
        typealias Limit = @convention(c) (JSContextGroupRef?, Double, Callback?, UnsafeMutableRawPointer?) -> Void
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit") {
            let limit = unsafeBitCast(symbol, to: Limit.self)
            limit(JSContextGetGroup(context.jsGlobalContextRef), seconds, { _, _ in true }, nil)
        }
    }

    func platform(_ operation: String, _ values: [String: Any]) throws -> Any? {
        try checkCancellation()
        guard let host else { throw DraftlyError.message("The operation \(operation) is unavailable.") }
        return try host.perform(operation, values: values)
    }
    private func json(_ object: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]), as: UTF8.self) }
    public func noteValue(_ note: Note) -> [String: Any] {
        var result: [String: Any] = ["uuid": note.id.uuidString, "content": note.content, "tags": note.tags, "isArchived": note.isArchived,
            "isTrashed": note.trashedAt != nil, "isFlagged": note.flag > 0, "flagType": note.flag, "syntax": ["name": note.syntax, "type": library.syntaxes.first(where: { $0.name == note.syntax })?.type ?? "builtIn"],
            "createdAt": APIValues.date(note.createdAt), "modifiedAt": APIValues.date(note.modifiedAt)]
        for key in ["createdLatitude", "createdLongitude", "modifiedLatitude", "modifiedLongitude", "selectionStart", "selectionLength"] {
            result[key] = Double(note.scriptMetadata?[key] ?? "0") ?? 0
        }
        return result
    }
    func decodedNote(_ values: [String: Any]) throws -> Note {
        guard let uuid = values["uuid"] as? String, let id = UUID(uuidString: uuid) else { throw DraftlyError.message("The draft ID is invalid.") }
        var note = library.notes.first(where: { $0.id == id }) ?? Note(id: id)
        note.content = values["content"] as? String ?? note.content
        note.tags = values["tags"] as? [String] ?? note.tags
        note.isArchived = values["isArchived"] as? Bool ?? note.isArchived
        if let flagged = values["isFlagged"] as? Bool { note.flag = flagged ? 1 : 0 }
        note.syntax = values["syntax"] as? String ?? (values["syntax"] as? [String: Any])?["name"] as? String ?? note.syntax
        if let flag = values["flagType"] as? Int { note.flag = min(7, max(0, flag)) }
        if let trashed = values["isTrashed"] as? Bool { note.trashedAt = trashed ? note.trashedAt ?? Date() : nil }
        note.createdAt = APIValues.parseDate(values["createdAt"]) ?? note.createdAt
        note.modifiedAt = APIValues.parseDate(values["modifiedAt"]) ?? note.modifiedAt
        for key in ["createdLatitude", "createdLongitude", "modifiedLatitude", "modifiedLongitude"] {
            if let value = values[key] as? NSNumber { note.scriptMetadata = note.scriptMetadata ?? [:]; note.scriptMetadata?[key] = value.stringValue }
        }
        return note
    }

    private func dispatch(_ operation: String, values: [String: Any]) throws -> Any? {
        switch operation {
        case "newDraft": return noteValue(Note())
        case "findDraft":
            guard let id = (values["uuid"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            return library.notes.first(where: { $0.id == id }).map(noteValue)
        case "queryDrafts":
            var workspace = Workspace(name: "Script")
            workspace.query = values["query"] as? String ?? ""
            if let error = DraftQuery(workspace.query).error { throw DraftlyError.message(error) }
            guard let folder = NoteFolder(rawValue: values["folder"] as? String ?? "all") else { throw DraftlyError.message("The draft query folder is invalid.") }
            workspace.folder = folder
            workspace.tags = values["tags"] as? [String] ?? []
            workspace.excludedTags = values["omitTags"] as? [String] ?? []
            let sortName = values["sort"] as? String ?? "modified"
            guard ["name", "title", "modified", "created", "accessed"].contains(sortName) else { throw DraftlyError.message("The draft query sort is invalid.") }
            workspace.sort = sortName == "name" ? .title : NoteSort(rawValue: sortName) ?? .modified
            workspace.ascending = !(values["descending"] as? Bool ?? true)
            var notes = workspace.filter(library.notes).filter { !(values["omitFlagged"] as? Bool ?? false) || $0.flag == 0 }
            if values["flaggedToTop"] as? Bool == true { notes = notes.filter { $0.flag > 0 } + notes.filter { $0.flag == 0 } }
            return notes.map(noteValue)
        case "updateDraft":
            let note = try decodedNote(values); try library.saveNote(note, preserveDates: values["_preserveDates"] as? Bool ?? false)
            if editor.noteID == note.id { editor.content = note.content; editor.selection = editor.safeSelection; editor.synchronizeScriptEdit?() }
            return library.notes.first(where: { $0.id == note.id }).map(noteValue)
        case "loadDraft":
            try flushEditor(); let requested = try decodedNote(values)
            guard let note = library.notes.first(where: { $0.id == requested.id }) else { throw DraftlyError.message("Save the draft before loading it into the editor.") }
            try library.recordAccess(note.id)
            editor.load(note); editor.synchronizeScriptEdit?(); return true
        case "editorText": return editor.content
        case "setEditorText": editor.content = values["text"] as? String ?? ""; editor.selection = editor.safeSelection; try flushEditor(); editor.synchronizeScriptEdit?(); return true
        case "selection": return editor.selectedText
        case "selectionRange": return [editor.safeSelection.location, editor.safeSelection.length]
        case "lineRange":
            let text = (values["text"] as? String ?? editor.content) as NSString
            let range = NSRange(location: values["location"] as? Int ?? 0, length: values["length"] as? Int ?? 0)
            guard range.location >= 0, range.length >= 0, range.location <= text.length, range.length <= text.length - range.location else { throw DraftlyError.message("The text range is outside the draft.") }
            let expanded = text.lineRange(for: range)
            return [expanded.location, expanded.length]
        case "setSelection":
            editor.selection = NSRange(location: values["location"] as? Int ?? 0, length: values["length"] as? Int ?? 0)
            editor.selection = editor.safeSelection; editor.synchronizeScriptEdit?(); return true
        case "replaceSelection": try editor.replace(editor.safeSelection, with: values["text"] as? String ?? ""); try flushEditor(); editor.synchronizeScriptEdit?(); return true
        case "textInRange", "replaceRange":
            let range = NSRange(location: values["location"] as? Int ?? 0, length: values["length"] as? Int ?? 0)
            guard range.location >= 0, range.length >= 0, range.location <= (editor.content as NSString).length, range.length <= (editor.content as NSString).length - range.location else { throw DraftlyError.message("The text range is outside the draft.") }
            if operation == "textInRange" { return (editor.content as NSString).substring(with: range) }
            try editor.replace(range, with: values["text"] as? String ?? ""); try flushEditor(); editor.synchronizeScriptEdit?(); return true
        case "template": return try renderTemplate(values["text"] as? String ?? "", note: decodedNote(values["note"] as? [String: Any] ?? [:]), tags: values["tags"] as? [String: String] ?? [:])
        case "setTemplateTag": customTags[values["key"] as? String ?? ""] = values["value"] as? String ?? ""; return true
        case "activate":
            editor.focusToken = UUID()
            if let uiOperation { _ = try uiOperation(["operation": "activate"]) }
            return nil
        case "message": logs.append(values["message"] as? String ?? ""); return true
        case "findAction":
            return library.actions.first(where: { $0.name == values["name"] as? String }).map(actionValue)
        case "queueAction":
            let details = values["action"] as? [String: Any] ?? [:]
            guard let action = library.actions.first(where: { $0.id.uuidString == details["uuid"] as? String }) else { throw DraftlyError.message("The queued action was not found.") }
            queued.append((action, try decodedNote(values["draft"] as? [String: Any] ?? [:]))); return true
        case "findWorkspace":
            return library.workspaces.first(where: { $0.name == values["name"] as? String }).map(workspaceValue)
        case "applyWorkspace":
            guard let applyWorkspace else { throw DraftlyError.message("Workspace application requires an open window.") }; try applyWorkspace(try decodeWorkspace(values)); return true
        case "base64Encode": return Data((values["text"] as? String ?? "").utf8).base64EncodedString()
        case "base64Decode": return Data(base64Encoded: values["text"] as? String ?? "").flatMap { String(data: $0, encoding: .utf8) }
        default: return try dispatchAPI(operation, values: values)
        }
    }
}
