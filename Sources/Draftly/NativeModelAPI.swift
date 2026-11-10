import Foundation
import FoundationModels
import DraftlyCore
import AgentContracts

@MainActor final class NativeModelAPI {
    var onTool: (@MainActor @Sendable (String, String) throws -> String)?
    struct Backend {
        let modes: @MainActor () -> [String]
        let respond: @MainActor (String, String) async throws -> String
        let discard: @MainActor (String) -> Void
        let clear: @MainActor () -> Void
    }
    private let backend: Backend?
    private let now: @MainActor () -> Date
    var responseTimeout: TimeInterval = 120
    private var sessions: [String: LanguageModelSession] = [:]
    private var toolLifetimes: [String: NativeModelToolLifetime] = [:]
    private var requests: [String: NativeModelWait] = [:]
    private var legacyActiveSessions: Set<String> = []
    init(backend: Backend? = nil, now: @escaping @MainActor () -> Date = Date.init) {
        self.backend = backend; self.now = now
    }
    func clear() {
        for request in requests.values { request.finish(.failure(CancellationError())) }
        legacyActiveSessions.removeAll()
        toolLifetimes.values.forEach { $0.valid = false }; toolLifetimes.removeAll()
        sessions.removeAll(); backend?.clear()
    }
    func perform(_ operation: String, _ values: [String: Any]) throws -> Any {
        let modes = AppleModelAccess.modes()
        if operation == "modelModes" { return modes }
        let mode = values["mode"] as? String ?? "onDevice"
        guard modes.contains(mode) else { throw DraftlyError.message("The selected Apple Intelligence model is unavailable on this Mac.") }
        let id = values["sessionID"] as? String ?? UUID().uuidString
        legacyActiveSessions.insert(id)
        defer { legacyActiveSessions.remove(id) }
        let session = try makeSession(values, id: id, mode: mode)
        let schema = try (values["schema"] as? [String: Any]).map(Self.schema)
        let prompt = values["prompt"] as? String ?? "", temperature = min(1, max(0, values["temperature"] as? Double ?? 0.5))
        let result = ModelResult()
        let task = Task { @MainActor in
            do {
                let response: String
                if let schema { response = try await session.respond(to: prompt, schema: schema, options: GenerationOptions(temperature: temperature)).content.jsonString }
                else { response = try await session.respond(to: prompt, options: GenerationOptions(temperature: temperature)).content }
                result.response = response
            } catch { result.error = error }
            result.finished = true
        }
        let deadline = Date().addingTimeInterval(120)
        while !result.finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        guard result.finished else { task.cancel(); throw ActionExecutionInterruption.timeout }
        if let error = result.error { throw error }
        let response: Any = schema != nil ? (try JSONSerialization.jsonObject(with: Data((result.response ?? "").utf8))) : result.response ?? ""
        let transcript = String(decoding: try JSONEncoder().encode(session.transcript), as: UTF8.self)
        return ["response": response, "transcript": transcript]
    }
    private func makeSession(_ values: [String: Any], id: String, mode: String) throws -> LanguageModelSession {
        let session: LanguageModelSession
        if let existing = sessions[id] { session = existing }
        else {
            let lifetime = NativeModelToolLifetime()
            let instructions = (values["instructions"] as? [String] ?? []).joined(separator: "\n")
            var names = values["tools"] as? [String] ?? []
            for group in values["toolSets"] as? [String] ?? [] {
                switch group {
                case "drafts": names += ["draft.query", "draft.find", "draft.create", "draft.append", "draft.prepend"]
                case "editor": names += ["editor.open"]
                case "actions": names += ["action.run"]
                case "workspaces": names += ["workspace.find"]
                default: throw DraftlyError.message("The model tool set \(group) is unavailable.")
                }
            }
            let tools: [any Tool] = try Array(Set(names)).sorted().map { name in
                guard onTool != nil else { throw DraftlyError.message("Model tools require an active Draftly window.") }
                return try ScriptModelTool(operation: name, callback: { [weak self] operation, json in
                    guard let self, lifetime.valid else { throw CancellationError() }
                    return try self.performTool(operation, json: json, sessionID: id)
                })
            }
            session = try languageSession(mode: mode, tools: tools, instructions: instructions)
            toolLifetimes[id] = lifetime
            sessions[id] = session
        }
        return session
    }

    private func languageSession(mode: String, tools: [any Tool], instructions: String) throws -> LanguageModelSession {
        if mode == "pcc" {
            #if compiler(>=6.4)
            if #available(macOS 27, *) { return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), tools: tools, instructions: instructions) }
            #endif
            throw DraftlyError.message("Private Cloud Compute is unavailable in this build.")
        }
        return LanguageModelSession(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
    }

    func respondAuthorized(prompt: String, mode: String, tools: [any Tool], hasOpenDraft: Bool) async throws -> String {
        guard availableModes().contains(mode) else { throw DraftlyError.message("The selected Apple Intelligence model is unavailable on this Mac.") }
        let id = UUID().uuidString
        defer { discardSession(id) }
        let draftContext = hasOpenDraft
            ? "For a request about the open draft, call draftly_read_draft with no arguments. To save changes, call draftly_edit_draft with the full updated content."
            : "Find approved draft IDs with draftly_server_capabilities. Read a draft before editing it."
        sessions[id] = try languageSession(mode: mode, tools: tools,
            instructions: """
                \(ChatConsoleInstructions.identity)
                \(draftContext)
                Execute only the current user request. Earlier conversation turns are context, not requests to run again. Do not repeat a completed creation when the user asks to edit.
                To create a new draft, use draftly_create_draft when available. Creation does not change the open draft. To verify the newly created draft, discover draftly_drafts_get and read the exact draft ID returned by creation. Do not use the open-draft read for a different draft.
                Report text only for the draft ID that the tool actually read.
                For unsaved text or a selection, discover editor tools with draftly_tools.
                For other operations, get the exact tool name and schema with draftly_tools. Call it through draftly_call. For editor edits or other writes that require a retryKey, inspect draftly_mutations_prepare and use its returned retryKey.
                \(AgentModelInstructions.results)
                """)
        let bytes = try JSONSerialization.data(withJSONObject: ["prompt": prompt, "mode": mode, "sessionID": id])
        let raw = try await performAsync("modelRespond", payload: String(decoding: bytes, as: UTF8.self))
        guard let frame = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let result = frame["value"] as? [String: Any], let response = result["response"] as? String else {
            throw ChatConsoleError.invalidModelResponse
        }
        return response
    }

    func discardSession(_ id: String) {
        toolLifetimes.removeValue(forKey: id)?.valid = false
        sessions.removeValue(forKey: id)
        backend?.discard(id)
    }

    func performTool(_ operation: String, json: String, sessionID: String) throws -> String {
        try Task.checkCancellation()
        if let request = requests[sessionID] { try request.requireActive() }
        else if !legacyActiveSessions.contains(sessionID) { throw CancellationError() }
        guard let onTool else { throw DraftlyError.message("Model tools require an active Draftly window.") }
        return try onTool(operation, json)
    }

    private func availableModes() -> [String] {
        if let backend { return backend.modes() }
        return AppleModelAccess.modes()
    }

    func performAsync(_ operation: String, payload: String) async throws -> String {
        try Task.checkCancellation()
        guard let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            throw DraftlyError.message("The model payload must be an object.")
        }
        let modes = availableModes()
        if operation == "modelModes" { return try encode(["value": modes]) }
        guard operation == "modelRespond" else { throw DraftlyError.message("The model operation is unavailable.") }
        let mode = values["mode"] as? String ?? "onDevice"
        guard modes.contains(mode) else { throw DraftlyError.message("The selected Apple Intelligence model is unavailable on this Mac.") }
        guard responseTimeout.isFinite, responseTimeout > 0 else { throw DraftlyError.message("The model timeout must be positive and finite.") }
        let id = values["sessionID"] as? String ?? UUID().uuidString
        guard requests[id] == nil else { throw DraftlyError.message("A response is already running in this model session.") }
        let wait = NativeModelWait(timeout: responseTimeout, now: now); requests[id] = wait
        defer { requests.removeValue(forKey: id) }
        do {
            let result: String = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    wait.continuation = continuation
                    guard !Task.isCancelled else { wait.finish(.failure(CancellationError())); return }
                    wait.operation = Task { @MainActor in
                        do {
                            try Task.checkCancellation()
                            try wait.requireActive()
                            let value: String
                            if let backend = self.backend { value = try await backend.respond(id, payload) }
                            else { value = try await self.respond(values, id: id, mode: mode) }
                            wait.finish(.success(value))
                        } catch { wait.finish(.failure(error)) }
                    }
                    wait.timeout = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(wait.remainingTime)) } catch { return }
                        wait.finish(.failure(ActionExecutionInterruption.timeout))
                    }
                }
            } onCancel: { [cancellation = wait.cancellation] in
                cancellation.cancel()
                Task { @MainActor in wait.finish(.failure(CancellationError())) }
            }
            await wait.cleanup()
            try Task.checkCancellation()
            let value = try JSONSerialization.jsonObject(with: Data(result.utf8), options: [.fragmentsAllowed])
            return try encode(["value": value])
        } catch {
            discardSession(id)
            await wait.cleanup()
            throw error
        }
    }

    private func respond(_ values: [String: Any], id: String, mode: String) async throws -> String {
        let session = try makeSession(values, id: id, mode: mode)
        let schema = try (values["schema"] as? [String: Any]).map(Self.schema)
        let prompt = values["prompt"] as? String ?? ""
        let options = GenerationOptions(temperature: min(1, max(0, values["temperature"] as? Double ?? 0.5)))
        let response: Any
        if let schema {
            let result = try await session.respond(to: prompt, schema: schema, options: options).content.jsonString
            response = try JSONSerialization.jsonObject(with: Data(result.utf8))
        } else { response = try await session.respond(to: prompt, options: options).content }
        try Task.checkCancellation()
        let transcript = String(decoding: try JSONEncoder().encode(session.transcript), as: UTF8.self)
        return try encode(["response": response, "transcript": transcript])
    }

    private func encode(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    private static func schema(_ values: [String: Any]) throws -> GenerationSchema {
        let properties = try (values["fields"] as? [[String: Any]] ?? []).map { field -> DynamicGenerationSchema.Property in
            let type = field["type"] as? String ?? "string", isArray = type.hasSuffix("Array")
            let primitive: DynamicGenerationSchema
            switch type.replacingOccurrences(of: "Array", with: "") {
            case "boolean": primitive = DynamicGenerationSchema(type: Bool.self)
            case "int": primitive = DynamicGenerationSchema(type: Int.self)
            case "number": primitive = DynamicGenerationSchema(type: Double.self)
            case "string":
                if let choices = field["options"] as? [String], !choices.isEmpty { primitive = DynamicGenerationSchema(name: field["name"] as? String ?? "Value", anyOf: choices) }
                else { primitive = DynamicGenerationSchema(type: String.self) }
            default: throw DraftlyError.message("The model schema field type is invalid.")
            }
            return DynamicGenerationSchema.Property(name: field["name"] as? String ?? "value", description: field["description"] as? String, schema: isArray ? DynamicGenerationSchema(arrayOf: primitive) : primitive)
        }
        return try GenerationSchema(root: DynamicGenerationSchema(name: "Response", properties: properties), dependencies: [])
    }
}

@MainActor private final class ModelResult {
    var response: String?; var error: Error?; var finished = false
}

private struct ScriptModelTool: Tool {
    typealias Arguments = GeneratedContent
    let operation: String
    var name: String { operation.replacingOccurrences(of: ".", with: "_") }
    var description: String { "Run \(operation) in the user's Draftly library. Supply only the needed fields." }
    let parameters: GenerationSchema
    let callback: @MainActor @Sendable (String, String) throws -> String
    init(operation: String, callback: @escaping @MainActor @Sendable (String, String) throws -> String) throws {
        self.operation = operation; self.callback = callback
        let fields = ["uuid", "text", "query", "name", "folder"].map { DynamicGenerationSchema.Property(name: $0, schema: DynamicGenerationSchema(type: String.self), isOptional: true) }
            + [DynamicGenerationSchema.Property(name: "tags", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true)]
        parameters = try GenerationSchema(root: DynamicGenerationSchema(name: "Arguments", properties: fields), dependencies: [])
    }
    func call(arguments: GeneratedContent) async throws -> String { try await callback(operation, arguments.jsonString) }
}

private final class NativeModelCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

@MainActor private final class NativeModelWait {
    let cancellation = NativeModelCancellationState()
    private let now: @MainActor () -> Date
    private let deadline: Date
    var continuation: CheckedContinuation<String, Error>?
    var operation: Task<Void, Never>?
    var timeout: Task<Void, Never>?
    init(timeout: TimeInterval, now: @escaping @MainActor () -> Date) {
        self.now = now; self.deadline = now().addingTimeInterval(timeout)
    }
    var remainingTime: TimeInterval { max(0, deadline.timeIntervalSince(now())) }
    func requireActive() throws {
        guard continuation != nil, !cancellation.isCancelled else { throw CancellationError() }
        guard now() < deadline else { throw ActionExecutionInterruption.timeout }
    }
    func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        let explicitCancellation: Bool
        if case .failure(let error) = result { explicitCancellation = error is CancellationError }
        else { explicitCancellation = false }
        let cancelled = cancellation.isCancelled || explicitCancellation
        let expired = now() >= deadline
        operation?.cancel(); timeout?.cancel(); timeout = nil
        if cancelled { continuation.resume(throwing: CancellationError()) }
        else if expired { continuation.resume(throwing: ActionExecutionInterruption.timeout) }
        else { continuation.resume(with: result) }
    }
    func cleanup() async { let task = operation; operation = nil; await task?.value }
}

@MainActor private final class NativeModelToolLifetime {
    var valid = true
}
