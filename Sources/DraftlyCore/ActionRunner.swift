import Foundation
import JavaScriptCore
import Combine

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

    func checkCancellation() throws {
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
        let steps = try ActionStepExpansion.expand(action, actions: library.actions)
        guard !executing.contains(action.id) else { throw DraftlyError.message("An included action refers to itself.") }
        executing.insert(action.id); defer { executing.remove(action.id) }
        let runtime = try ActionScriptRuntime(dispatch: { [weak self] operation, values in
            guard let self else { throw DraftlyError.message("The action was closed.") }
            return try self.dispatch(operation, values: values)
        }, requireSource: { [weak self] path in
            guard let self else { throw DraftlyError.message("The action was closed.") }
            return try self.platform("requireScript", ["path": path]) as? String ?? ""
        })
        defer { runtime.close() }
        let context = runtime.context
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
        if let scriptError = runtime.scriptError { throw DraftlyError.message(scriptError) }
        for step in steps where step.isEnabled != false {
            try checkCancellation()
            activeSession?.enter(actionID: action.id, step: step)
            if context.objectForKeyedSubscript("__cancelled")?.toBool() == true { return false }
            if let failure = context.objectForKeyedSubscript("__failure"), !failure.isNull, !failure.isUndefined { throw DraftlyError.message(failure.toString()) }
            let text = step.values["template"] ?? step.values["text"] ?? "[[draft]]"
            let current = library.notes.first(where: { $0.id == note.id }) ?? note
            let rendered = try renderTemplate(text, note: current)
            guard try ActionStepExecutor(runner: self).perform(step, text: text, rendered: rendered, current: current,
                runtime: runtime, executeIncluded: { try self.execute($0, note: $1) }) else { return false }
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
    func renderURL(_ text: String, note: Note, encodeTags: Bool) throws -> String {
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
    static func limitExecution(_ context: JSContext, seconds: TimeInterval) throws {
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
    func json(_ object: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]), as: UTF8.self) }
    public func noteValue(_ note: Note) -> [String: Any] {
        ActionScriptValues.noteValue(note, syntaxes: library.syntaxes)
    }
    func decodedNote(_ values: [String: Any]) throws -> Note {
        try ActionScriptValues.decodedNote(values, notes: library.notes)
    }

    func appendScriptLog(_ message: String) { logs.append(message) }

    private func dispatch(_ operation: String, values: [String: Any]) throws -> Any? {
        if let command = try ScriptCommand(operation: operation, values: values) {
            return try perform(command)
        }
        return try dispatchAPI(operation, values: values)
    }
}
