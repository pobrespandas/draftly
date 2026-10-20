import Foundation
import JavaScriptCore
import Combine

@MainActor
public final class ActionRunner: ObservableObject {
    var markdownDefaults: UserDefaults = .standard
    var httpTransport: @Sendable (String) async -> String = { await ScriptHTTP.requestSerialized($0) }
    private static let executionStates = CurrentValueSubject<Set<LibraryStore.ExecutionIdentity>, Never>([])
    private static var runningLibraries: Set<LibraryStore.ExecutionIdentity> = [] {
        didSet { executionStates.send(runningLibraries) }
    }
    public internal(set) var successParameters: [String: String] = [:]
    public let library: LibraryStore
    public let editor: EditorSession
    public weak var host: (any ActionHost)?
    @Published public private(set) var isRunning = false
    public private(set) var isApplyingScriptCommand = false
    @Published public var message: String?
    public var scriptTimeout: TimeInterval = 120
    public var hostOperationTimeout: TimeInterval = 120
    var hostOperationNow: () -> Date = Date.init
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

    public static func isExecuting(in library: LibraryStore) -> Bool {
        runningLibraries.contains(library.executionIdentity)
    }

    public static func executionBusyPublisher(in library: LibraryStore) -> AnyPublisher<Bool, Never> {
        let identity = library.executionIdentity
        return executionStates.map { $0.contains(identity) }.removeDuplicates().eraseToAnyPublisher()
    }

    public func flushEditor() throws {
        guard let id = editor.noteID, var note = library.notes.first(where: { $0.id == id }) else { return }
        try validateScriptNote(note.id)
        let contentChanged = note.content != editor.content
        note.content = editor.content
        let selection = editor.safeSelection
        note.scriptMetadata = note.scriptMetadata ?? [:]
        note.scriptMetadata?["selectionStart"] = String(selection.location)
        note.scriptMetadata?["selectionLength"] = String(selection.length)
        try library.saveNote(note, preserveDates: !contentChanged)
        recordScriptSave(note)
        editor.acknowledgeSaved(note)
    }

    @discardableResult public func run(_ action: DraftAction) -> Bool { runResult(action).succeeded }

    @discardableResult public func runResult(_ action: DraftAction) -> ActionExecutionResult {
        runReport(action).result
    }

    public func cancel() { activeSession?.cancel(); cancelWorker?(); cancelNativeOperation?() }
    var cancelWorker: (() -> Void)?
    var cancelNativeOperation: (() -> Void)?
    var bridgeStepID: UUID?
    var asyncExecutionID: UUID?
    var scriptNoteContents: [UUID: String] = [:]

    @discardableResult public func runReport(_ action: DraftAction) -> ActionExecutionReport {
        let session = ActionExecutionSession(actionID: action.id)
        guard !isRunning else {
            message = "An action is already running."
            return session.finish(.failure(message!), reason: .busy, successParameters: [:])
        }
        let libraryID = library.executionIdentity
        guard Self.runningLibraries.insert(libraryID).inserted else {
            message = "An action is already running in this library."
            return session.finish(.failure(message!), reason: .busy, successParameters: [:])
        }
        activeSession = session
        defer { Self.runningLibraries.remove(libraryID); activeSession = nil }
        terminationReason = .error
        successParameters = [:]
        _ = executeRun(action)
        if !runOutcome.succeeded { successParameters = [:]; queued = [] }
        let reason: ActionTerminationReason = runOutcome.succeeded ? .success : runOutcome == .cancelled ? .cancelled : terminationReason
        let report = session.finish(runOutcome, reason: reason, successParameters: successParameters)
        lastReport = report
        return report
    }

    public func runAsync(_ action: DraftAction) async -> ActionExecutionReport {
        let session = ActionExecutionSession(actionID: action.id)
        guard !isRunning else {
            message = "An action is already running."
            return session.finish(.failure(message!), reason: .busy, successParameters: [:])
        }
        let libraryID = library.executionIdentity
        guard Self.runningLibraries.insert(libraryID).inserted else {
            message = "An action is already running in this library."
            return session.finish(.failure(message!), reason: .busy, successParameters: [:])
        }
        activeSession = session
        asyncExecutionID = session.id
        scriptNoteContents = [:]
        if let id = editor.noteID, let stored = library.notes.first(where: { $0.id == id }) {
            if let baseline = editor.persistedDraft, baseline.id == id, editor.content != stored.content {
                scriptNoteContents[id] = baseline.content
            } else { scriptNoteContents[id] = stored.content }
        }
        isRunning = true
        queued = []; logs = []; customTags = [:]; successParameters = [:]
        let sourceNoteID = editor.noteID
        defer {
            Self.runningLibraries.remove(libraryID)
            isRunning = false; activeSession = nil; bridgeStepID = nil; cancelWorker = nil; cancelNativeOperation = nil
            asyncExecutionID = nil; scriptNoteContents = [:]
            host?.finishAction()
        }
        return await withTaskCancellationHandler {
            let result: ActionExecutionResult
            let reason: ActionTerminationReason
            do {
                try Task.checkCancellation()
                try checkCancellation()
                if action.presentation.confirmBeforeRun,
                   try await nativeValue("confirmAction", ["name": action.name]) as? Bool != true {
                    throw ActionExecutionInterruption.cancelled
                }
                try flushEditor()
                guard let id = editor.noteID, let note = library.notes.first(where: { $0.id == id }) else {
                    throw DraftlyError.message("Create or select a draft first.")
                }
                try await executeAsync(action, note: note, session: session)
                var count = 0
                while !queued.isEmpty {
                    try checkCancellation()
                    count += 1
                    guard count <= 100 else { throw DraftlyError.message("The action queue exceeded 100 actions.") }
                    let (next, queuedNote) = queued.removeFirst()
                    try flushEditor()
                    let target = library.notes.first(where: { $0.id == queuedNote.id }) ?? queuedNote
                    try library.recordAccess(target.id)
                    editor.load(target)
                    try await executeAsync(next, note: target, session: session)
                }
                try checkCancellation()
                try Task.checkCancellation()
                try flushEditor()
                result = .success; reason = .success
                message = logs.last ?? "\(action.name) completed"
            } catch {
                try? flushEditor()
                if error is CancellationError || (error as? ActionExecutionInterruption) == .cancelled || session.cancellationRequested {
                    result = .cancelled; reason = .cancelled
                    message = "\(action.name) cancelled"
                } else {
                    result = .failure(error.localizedDescription)
                    reason = (error as? ActionExecutionInterruption) == .timeout ? .timeout : .error
                    message = error.localizedDescription
                }
            }
            if !result.succeeded { successParameters = [:]; queued = [] }
            var run = ActionRun(actionName: action.name, status: result.succeeded ? "Success" : result == .cancelled ? "Cancelled" : "Error",
                                message: result.succeeded ? logs.joined(separator: "\n") : message ?? "")
            run.noteID = sourceNoteID; run.actionID = action.id; library.log(run)
            if result.succeeded && action.presentation.notifyOnSuccess || reason == .error && action.presentation.notifyOnError || reason == .timeout && action.presentation.notifyOnError {
                _ = try? host?.perform("actionNotification", values: ["title": action.name, "message": message ?? ""])
            }
            let report = session.finish(result, reason: reason, successParameters: successParameters)
            lastReport = report
            return report
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.activeSession?.id == session.id else { return }
                self?.cancel()
            }
        }
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

    private func execute(_ initialAction: DraftAction, note: Note) throws -> Bool {
        let steps = try ActionStepExpansion.expand(initialAction, actions: library.actions)
        var configurationSteps = steps
        var action = try prepareInitialConfiguration(initialAction, steps: steps)
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
        context.evaluateScript(try bootstrapSource(action, note: note, steps: steps))
        if let scriptError = runtime.scriptError { throw DraftlyError.message(scriptError) }
        func performSteps(_ items: [ActionStep], owner: UUID, path: Set<UUID>) throws -> Bool {
            for step in items where step.isEnabled != false {
                try checkCancellation()
                activeSession?.enter(actionID: owner, step: step)
                if context.objectForKeyedSubscript("__cancelled")?.toBool() == true { return false }
                if let failure = context.objectForKeyedSubscript("__failure"), !failure.isNull, !failure.isUndefined { throw DraftlyError.message(failure.toString()) }
                let text = step.values["template"] ?? step.values["text"] ?? "[[draft]]"
                let current = library.notes.first(where: { $0.id == note.id }) ?? note
                if step.type == "includeAction" {
                    let included = try ActionStepExpansion.resolve(step, actions: library.actions) { try renderTemplate($0, note: current) }
                    let includedSteps = try ActionStepExpansion.expand(included, actions: library.actions, path: path)
                    configurationSteps += includedSteps
                    action = try prepareInitialConfiguration(action, steps: configurationSteps)
                    context.evaluateScript(try additionalConfigurationSource(action, steps: includedSteps))
                    guard try performSteps(included.steps, owner: included.id, path: path.union([included.id])) else { return false }
                    continue
                }
                let rendered = try renderTemplate(text, note: current)
                guard try ActionStepExecutor(runner: self).perform(step, text: text, rendered: rendered, current: current,
                    runtime: runtime, executeIncluded: { try self.execute($0, note: $1) }) else { return false }
                context.evaluateScript(try templateTagsSource())
            }
            return true
        }
        guard try performSteps(action.steps, owner: action.id, path: [action.id]) else { return false }
        try checkCancellation()
        if context.objectForKeyedSubscript("__cancelled")?.toBool() == true { return false }
        if let failure = context.objectForKeyedSubscript("__failure"), !failure.isNull, !failure.isUndefined { throw DraftlyError.message(failure.toString()) }
        try flushEditor()
        try applySuccessEffects(action, noteID: note.id)
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
    nonisolated static func limitExecution(_ context: JSContext, seconds: TimeInterval, deadline: ScriptExecutionDeadline? = nil) throws {
        guard seconds.isFinite, seconds > 0 else { throw DraftlyError.message("The synchronous script timeout must be positive and finite.") }
        // JavaScriptCore exports this limit on macOS. Do not require a private symbol at link time.
        typealias Callback = @convention(c) (JSContextRef?, UnsafeMutableRawPointer?) -> Bool
        typealias Limit = @convention(c) (JSContextGroupRef?, Double, Callback?, UnsafeMutableRawPointer?) -> Void
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit") {
            let limit = unsafeBitCast(symbol, to: Limit.self)
            limit(JSContextGetGroup(context.jsGlobalContextRef), seconds, { _, state in
                if let state { Unmanaged<ScriptExecutionDeadline>.fromOpaque(state).takeUnretainedValue().recordTimeout() }
                return true
            }, deadline.map { Unmanaged.passUnretained($0).toOpaque() })
        }
    }

    func platform(_ operation: String, _ values: [String: Any]) throws -> Any? {
        try checkCancellation()
        guard let host else { throw DraftlyError.message("The operation \(operation) is unavailable.") }
        return try host.perform(operation, values: values)
    }
    func templateTagsSource() throws -> String {
        let encoded = try json(customTags)
        return "__tags=Object.assign(Object.create(null),JSON.parse(\(try json(encoded))));"
    }

    func json(_ object: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]), as: UTF8.self) }
    public func noteValue(_ note: Note) -> [String: Any] {
        if asyncExecutionID != nil, scriptNoteContents[note.id] == nil { scriptNoteContents[note.id] = note.content }
        return ActionScriptValues.noteValue(note, syntaxes: library.syntaxes)
    }
    func decodedNote(_ values: [String: Any]) throws -> Note {
        try ActionScriptValues.decodedNote(values, notes: library.notes)
    }

    func appendScriptLog(_ message: String) { logs.append(message) }

    func withScriptMutation<T>(_ body: () throws -> T) rethrows -> T {
        let wasApplying = isApplyingScriptCommand
        isApplyingScriptCommand = true
        defer { isApplyingScriptCommand = wasApplying }
        return try body()
    }

    func dispatch(_ operation: String, values: [String: Any]) throws -> Any? {
        let wasApplying = isApplyingScriptCommand
        isApplyingScriptCommand = true
        defer { isApplyingScriptCommand = wasApplying }
        if let command = try ScriptCommand(operation: operation, values: values) {
            return try perform(command)
        }
        return try dispatchAPI(operation, values: values)
    }
}
