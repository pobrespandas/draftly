import Foundation
import FoundationModels
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
            result = .object(["tools": .array(definitions.map {
                .object(["name": .string($0.name), "description": .string($0.summary)])
            })])
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
        return [try AppleCatalogTool(names: names, callback: { [weak self] name in
            guard let self else { throw CancellationError() }
            return try await self.catalog(name: name)
        }), try AppleCallTool(names: names, callback: { [weak self] name, arguments in
            guard let self else { throw CancellationError() }
            return try await self.execute(name: name, argumentsJSON: arguments)
        })]
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
    let description = "List authorized Draftly tools when name is omitted. Supply the target tool's name to read its input schema. This catalog's own name is not a target tool."
    let parameters: GenerationSchema
    let callback: @MainActor @Sendable (String?) async throws -> String
    init(names: [String], callback: @escaping @MainActor @Sendable (String?) async throws -> String) throws {
        self.callback = callback
        parameters = try GenerationSchema(root: DynamicGenerationSchema(name: "DraftlyCatalogArguments", properties: [
            .init(name: "name", description: "An authorized target tool name. Omit to list tools.",
                schema: DynamicGenerationSchema(name: "AuthorizedTool", anyOf: names), isOptional: true)
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
    let description = "Call the authorized operation in name. Supply targets and version/retry fields directly. parametersJSON contains only operation-specific parameters, not a request envelope. Inspect draftly_tools for those parameters. Never replay an outcome_unknown effect."
    let parameters: GenerationSchema
    let callback: @MainActor @Sendable (String, String) async throws -> String
    init(names: [String], callback: @escaping @MainActor @Sendable (String, String) async throws -> String) throws {
        self.callback = callback
        let reference = DynamicGenerationSchema(name: "DraftlyResource", properties: [
            .init(name: "kind", schema: DynamicGenerationSchema(name: "ResourceKind", anyOf: AgentResourceKind.allCases.map(\.rawValue))),
            .init(name: "id", description: "Exact authorized resource UUID.", schema: DynamicGenerationSchema(type: String.self))
        ])
        parameters = try GenerationSchema(root: DynamicGenerationSchema(name: "DraftlyCallArguments", properties: [
            .init(name: "name", schema: DynamicGenerationSchema(name: "AuthorizedTool", anyOf: names)),
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
        return try await callback(name, json)
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
            return try await models.respondAuthorized(prompt: prompt, mode: mode, tools: try await bridge.modelTools())
        }
    }
    func respond(prompt: String, mode: String, session: AgentChatToolSession) async throws -> String {
        guard ["onDevice", "pcc"].contains(mode) else { throw AgentErrorCode.invalidInput }
        let bridge = try AppleChatToolBridge(session: session, timeout: timeout)
        defer { bridge.lifetime.invalidate() }
        return try await withTaskCancellationHandler {
            let result = try await generate(prompt, mode, bridge)
            try bridge.lifetime.requireActive()
            return result
        } onCancel: { [lifetime = bridge.lifetime] in lifetime.invalidate() }
    }
}
