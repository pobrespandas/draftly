import Foundation
import FoundationModels
import OSLog
import Security
import AgentContracts

// A cloud choice requires both Apple authorization and runtime availability.
@MainActor enum AppleModelAccess {
    static func modes() -> [String] {
        var result: [String] = []
        if SystemLanguageModel.default.isAvailable { result.append("onDevice") }
        #if compiler(>=6.4)
        if #available(macOS 27, *), hasCloudEntitlement(), PrivateCloudComputeLanguageModel().isAvailable {
            result.append("pcc")
        }
        #endif
        return result
    }

    static func hasCloudEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        var error: Unmanaged<CFError>?
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.private-cloud-compute" as CFString, &error)
        if let error { _ = error.takeRetainedValue(); return false }
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return (value as? NSNumber)?.boolValue == true
    }
}

final class AppleChatToolLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private let deadline: ContinuousClock.Instant
    init(timeout: TimeInterval) throws {
        guard timeout.isFinite, timeout > 0, timeout <= 3600 else { throw AgentErrorCode.invalidInput }
        deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    }
    func invalidate() { lock.withLock { closed = true } }
    func requireActive() throws {
        try Task.checkCancellation()
        guard !lock.withLock({ closed }) else { throw CancellationError() }
        guard ContinuousClock.now < deadline else { throw AgentErrorCode.timeout }
    }
}

// Discovery and execution use the same authorized catalog as CLI and MCP.
@MainActor final class AppleChatToolBridge {
    let lifetime: AppleChatToolLifetime
    private let session: AgentChatToolSession
    var currentDraftID: UUID? { session.currentDraftID }
    private let maximumCalls: Int
    private var calls = 0
    init(session: AgentChatToolSession, timeout: TimeInterval = 120, maximumCalls: Int = 32) throws {
        guard maximumCalls > 0, maximumCalls <= 256 else { throw AgentErrorCode.invalidInput }
        self.session = session; self.maximumCalls = maximumCalls
        lifetime = try AppleChatToolLifetime(timeout: timeout)
    }
    private func admit() throws {
        try lifetime.requireActive()
        guard calls < maximumCalls else { throw AgentErrorCode.unavailable }
        calls += 1
    }
    func catalog(name: String? = nil) async throws -> String {
        try admit()
        let definitions = try await session.tools(validateExecution: lifetime.requireActive)
        try lifetime.requireActive()
        let result: AgentJSONValue
        if let name {
            guard let definition = definitions.first(where: { $0.name == name }) else { throw AgentErrorCode.permissionDenied }
            result = .object(["name": .string(name), "description": .string(definition.summary), "inputSchema": definition.inputSchema])
        } else {
            result = .object(["tools": .array(definitions.map { .string($0.name) })])
        }
        let bytes = try JSONEncoder().encode(result)
        guard bytes.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.unavailable }
        return String(decoding: bytes, as: UTF8.self)
    }
    func execute(name: String, argumentsJSON: String) async throws -> String {
        try admit()
        let result = try await session.execute(callID: UUID().uuidString, tool: name, argumentsJSON: argumentsJSON,
            validateExecution: lifetime.requireActive)
        try lifetime.requireActive()
        return result
    }
    func modelTools() async throws -> [any Tool] {
        try admit()
        let names = try await session.tools(validateExecution: lifetime.requireActive).map(\.name)
        try lifetime.requireActive()
        guard !names.isEmpty else { throw AgentErrorCode.unavailable }
        var tools: [any Tool] = [try AppleCatalogTool(callback: { [weak self] name in
            guard let self else { throw CancellationError() }
            return try await self.catalog(name: name)
        }), try AppleCallTool(callback: { [weak self] name, arguments in
            guard let self else { throw CancellationError() }
            return try await self.execute(name: name, argumentsJSON: arguments)
        })]
        if names.contains("draftly_drafts_get") {
            if let currentDraftID {
                tools.append(AppleReadOpenDraftTool(draftID: currentDraftID, bridge: self))
            } else {
                tools.append(AppleReadDraftTool(bridge: self))
            }
        }
        if ["draftly_drafts_get", "draftly_drafts_update", "draftly_mutations_prepare"].allSatisfy(names.contains) {
            if let currentDraftID {
                tools.append(AppleEditOpenDraftTool(draftID: currentDraftID, bridge: self))
            } else {
                tools.append(AppleEditDraftTool(bridge: self))
            }
        }
        return tools
    }

    private var readVersions: [UUID: String] = [:]

    func readDraft(id: UUID) async throws -> String {
        let targets: AgentJSONValue = .array([.object(["kind": .string("draft"), "id": .string(id.uuidString)])])
        let bytes = try JSONEncoder().encode(AgentJSONValue.object(["targets": targets]))
        readVersions.removeValue(forKey: id)
        let result = try await execute(name: "draftly_drafts_get", argumentsJSON: String(decoding: bytes, as: UTF8.self))
        let response = try JSONDecoder().decode(AgentResponse.self, from: Data(result.utf8))
        if case .result(.object(let values)) = response.outcome,
           case .object(let draft) = values["draft"], case .string(let version) = draft["versionToken"] {
            readVersions[id] = version
        }
        return result
    }

    func editDraft(id: UUID, content: String) async throws -> String {
        guard let version = readVersions.removeValue(forKey: id) else {
            return #"{"error":"read_required","hint":"Read this draft with draftly_read_draft before editing."}"#
        }
        func invoke(_ name: String, _ fields: [String: AgentJSONValue]) async throws -> String {
            let bytes = try JSONEncoder().encode(AgentJSONValue.object(fields))
            return try await execute(name: name, argumentsJSON: String(decoding: bytes, as: UTF8.self))
        }
        let targets: AgentJSONValue = .array([.object(["kind": .string("draft"), "id": .string(id.uuidString)])])
        let requestID = AgentJSONValue.string(UUID().uuidString)
        let parameters: AgentJSONValue = .object(["changes": .object(["content": .string(content)])])
        let intent: AgentJSONValue = .object(["apiVersion": .integer(1), "requestID": requestID,
            "operation": .string("drafts.update"), "targets": targets, "expectedVersion": .string(version),
            "parameters": parameters])
        let prepared = try await invoke("draftly_mutations_prepare", [
            "requestID": .string(UUID().uuidString), "parameters": .object(["request": intent])])
        let reply = try JSONDecoder().decode(AgentResponse.self, from: Data(prepared.utf8))
        guard case .result(.object(let values)) = reply.outcome,
              case .string(let key) = values["retryKey"] else { return prepared }
        return try await invoke("draftly_drafts_update", ["requestID": requestID, "targets": targets,
            "expectedVersion": .string(version), "retryKey": .string(key), "parameters": parameters])
    }
}

private struct AppleReadOpenDraftTool: Tool {
    @Generable struct Arguments {}

    let name = "draftly_read_draft"
    let description = "Read the open draft. If hasMore is true, use the catalog to read the remaining text before replacing it."
    let draftID: UUID
    weak var bridge: AppleChatToolBridge?

    func call(arguments: Arguments) async throws -> String {
        guard let bridge else { throw CancellationError() }
        return try await bridge.readDraft(id: draftID)
    }
}

private struct AppleEditOpenDraftTool: Tool {
    @Generable struct Arguments {
        @Guide(description: "Complete updated draft text, including original text to keep")
        var content: String
    }

    let name = "draftly_edit_draft"
    let description = "Save the complete updated text of the open draft. Read it with draftly_read_draft first."
    let draftID: UUID
    weak var bridge: AppleChatToolBridge?

    func call(arguments: Arguments) async throws -> String {
        guard let bridge else { throw CancellationError() }
        return try await bridge.editDraft(id: draftID, content: arguments.content)
    }
}

private struct AppleReadDraftTool: Tool {
    @Generable struct Arguments {
        @Guide(description: "Exact UUID of the authorized draft")
        var draftID: String
    }

    let name = "draftly_read_draft"
    let description = "Read a bounded chunk of stored draft text and remember its version for draftly_edit_draft. If hasMore is true, use the catalog draft read to fetch the remaining text before replacing it."
    weak var bridge: AppleChatToolBridge?

    func call(arguments: Arguments) async throws -> String {
        guard let bridge else { throw CancellationError() }
        guard let id = UUID(uuidString: arguments.draftID) else { throw AgentErrorCode.invalidInput }
        return try await bridge.readDraft(id: id)
    }
}

private struct AppleEditDraftTool: Tool {
    @Generable struct Arguments {
        @Guide(description: "Exact UUID of the draft read with draftly_read_draft")
        var draftID: String
        @Guide(description: "Complete new draft text, including any original text to preserve")
        var content: String
    }

    let name = "draftly_edit_draft"
    let description = "Replace the entire stored text of a draft after reading it with draftly_read_draft. Include all text that must stay."
    weak var bridge: AppleChatToolBridge?

    func call(arguments: Arguments) async throws -> String {
        guard let bridge else { throw CancellationError() }
        guard let id = UUID(uuidString: arguments.draftID) else { throw AgentErrorCode.invalidInput }
        return try await bridge.editDraft(id: id, content: arguments.content)
    }
}

private func appleToolFields(_ content: GeneratedContent) throws -> [String: AgentJSONValue] {
    guard case .object(let fields) = try JSONDecoder().decode(AgentJSONValue.self, from: Data(content.jsonString.utf8)) else {
        throw AgentErrorCode.invalidInput
    }
    return fields
}

private struct AppleCatalogTool: Tool {
    typealias Arguments = GeneratedContent
    let name = "draftly_tools"
    let description = "Omit name to list authorized operation names. Pass one exact name to load its description and input schema."
    let parameters: GenerationSchema
    let callback: @MainActor @Sendable (String?) async throws -> String
    init(callback: @escaping @MainActor @Sendable (String?) async throws -> String) throws {
        self.callback = callback
        parameters = try GenerationSchema(root: DynamicGenerationSchema(name: "DraftlyCatalogArguments", properties: [
            .init(name: "name", description: "An authorized target tool name. Omit to list tools.",
                schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ]), dependencies: [])
    }
    func call(arguments: GeneratedContent) async throws -> String {
        let fields = try appleToolFields(arguments)
        if let name = fields["name"], name != .null {
            guard case .string(let name) = name else { throw AgentErrorCode.invalidInput }
            return try await callback(name)
        }
        return try await callback(nil)
    }
}

private struct AppleCallTool: Tool {
    typealias Arguments = GeneratedContent
    let name = "draftly_call"
    let description = "Execute an authorized operation by its exact name from draftly_tools. Pass targets, requestID, expectedVersion, and retryKey as separate fields when needed. Encode only the schema’s parameters object in parametersJSON."
    let parameters: GenerationSchema
    let callback: @MainActor @Sendable (String, String) async throws -> String
    init(callback: @escaping @MainActor @Sendable (String, String) async throws -> String) throws {
        self.callback = callback
        let reference = DynamicGenerationSchema(name: "DraftlyResource", properties: [
            .init(name: "kind", schema: DynamicGenerationSchema(name: "ResourceKind", anyOf: AgentResourceKind.allCases.map(\.rawValue))),
            .init(name: "id", description: "Exact authorized resource UUID.", schema: DynamicGenerationSchema(type: String.self))
        ])
        parameters = try GenerationSchema(root: DynamicGenerationSchema(name: "DraftlyCallArguments", properties: [
            .init(name: "name", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "targets", description: "Resources used by this operation. A draft read needs kind draft and its exact UUID.", schema: DynamicGenerationSchema(arrayOf: reference), isOptional: true),
            .init(name: "requestID", description: "Fresh UUID for a write intent. Keep it unchanged when preparing and retrying that intent.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "expectedVersion", description: "Exact versionToken from a read, or batchVersion for the exact target set.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "retryKey", description: "Exact key returned by mutations.prepare. Do not invent it.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "parametersJSON", description: "Only operation-specific parameters as JSON object text. Omit for defaults. Read their schema with draftly_tools.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ]), dependencies: [])
    }
    func call(arguments: GeneratedContent) async throws -> String {
        var fields = try appleToolFields(arguments)
        guard case .string(let name) = fields.removeValue(forKey: "name") else { throw AgentErrorCode.invalidInput }
        fields = fields.filter { $0.value != .null }
        let json = String(decoding: try JSONEncoder().encode(AgentJSONValue.object(fields)), as: UTF8.self)
        do {
            return try await callback(name, json)
        } catch AgentErrorCode.invalidInput {
            return #"{"error":"invalid_input","hint":"Check the exact tool schema with draftly_tools. Supply a top-level requestID for every write and for mutations.prepare."}"#
        }
    }
}

@MainActor final class AppleChatResponder {
    typealias Generate = @MainActor (String, String, AppleChatToolBridge) async throws -> String
    private let generate: Generate
    let timeout: TimeInterval
    init(timeout: TimeInterval = 120, generate: Generate? = nil) {
        self.timeout = timeout
        self.generate = generate ?? { prompt, mode, bridge in
            let models = NativeModelAPI()
            models.responseTimeout = timeout
            return try await models.respondAuthorized(prompt: prompt, mode: mode, tools: try await bridge.modelTools(),
                                                      hasOpenDraft: bridge.currentDraftID != nil)
        }
    }
    func respond(prompt: String, mode: String, session: AgentChatToolSession) async throws -> String {
        guard ["onDevice", "pcc"].contains(mode) else { throw AgentErrorCode.invalidInput }
        let bridge = try AppleChatToolBridge(session: session, timeout: timeout)
        defer { bridge.lifetime.invalidate() }
        return try await withTaskCancellationHandler {
            do {
                let result = try await generate(prompt, mode, bridge)
                try bridge.lifetime.requireActive()
                return result
            } catch let error as LanguageModelSession.ToolCallError {
                try Task.checkCancellation()
                if error.underlyingError is CancellationError { throw CancellationError() }
                let underlying = error.underlyingError as NSError
                Logger(subsystem: "com.pobrespandas.draftly", category: "AppleChat")
                    .error("Apple tool invocation failed: \(underlying.domain, privacy: .public) (\(underlying.code))")
                throw AppleChatToolInvocationError()
            }
        } onCancel: { [lifetime = bridge.lifetime] in lifetime.invalidate() }
    }
}

private struct AppleChatToolInvocationError: LocalizedError {
    var errorDescription: String? {
        "Apple Intelligence could not complete the Draftly tool call. Check the draft before trying again."
    }
}
