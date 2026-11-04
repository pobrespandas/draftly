import Foundation
import FoundationModels
import Testing
import AgentContracts
@testable import Draftly

@Suite("Apple chat through authorized local tools") @MainActor
struct AppleChatToolsTests {
    @Test func catalogAndCallsKeepTheExistingScope() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        let session = AgentChatToolSession(backend: runtime.backend)
        defer { session.invalidate() }
        let bridge = try AppleChatToolBridge(session: session)
        let catalog = try await bridge.catalog()
        #expect(catalog.contains("draftly_drafts_get") && !catalog.contains("draftly_drafts_create"))
        #expect(!catalog.contains(runtime.hidden.content))
        let schema = try await bridge.catalog(name: "draftly_drafts_get")
        #expect(schema.contains("inputSchema") && schema.contains("targets"))
        let allowed = try await bridge.execute(name: "draftly_drafts_get", argumentsJSON: runtime.arguments(runtime.allowed.id))
        #expect(allowed.contains(runtime.allowed.content))
        let hidden = try await bridge.execute(name: "draftly_drafts_get", argumentsJSON: runtime.arguments(runtime.hidden.id))
        #expect(hidden.contains("not_found") && !hidden.contains(runtime.hidden.content))
        await #expect(throws: AgentErrorCode.permissionDenied) { try await bridge.catalog(name: "draftly_drafts_create") }
    }

    private func literalNames(_ value: AgentJSONValue, root: [String: AgentJSONValue],
                              references: Set<String> = []) -> Set<String>? {
        guard case .object(let fields) = value else { return nil }
        if case .string(let reference) = fields["$ref"] {
            guard reference.hasPrefix("#/$defs/"), !references.contains(reference),
                  case .object(let definitions) = root["$defs"],
                  let target = definitions[String(reference.dropFirst("#/$defs/".count))] else { return nil }
            return literalNames(target, root: root, references: references.union([reference]))
        }
        if case .array(let values) = fields["enum"] {
            let strings = values.compactMap { value -> String? in if case .string(let text) = value { return text }; return nil }
            return strings.count == values.count ? Set(strings) : nil
        }
        if case .string(let value) = fields["const"] { return [value] }
        if fields["type"] == .string("null") { return [] }
        for keyword in ["anyOf", "oneOf"] {
            if case .array(let alternatives) = fields[keyword], !alternatives.isEmpty {
                var result: Set<String> = []
                for alternative in alternatives {
                    guard let names = literalNames(alternative, root: root, references: references) else { return nil }
                    result.formUnion(names)
                }
                return result
            }
        }
        return nil
    }

    @Test func nameConstraintReaderRejectsAnUnconstrainedAlternative() {
        let names: AgentJSONValue = .object(["enum": .array([.string("allowed")])])
        let reference: AgentJSONValue = .object(["$ref": .string("#/$defs/Names")])
        let root: [String: AgentJSONValue] = ["$defs": .object(["Names": names])]
        #expect(literalNames(reference, root: root) == ["allowed"])
        #expect(literalNames(.object(["anyOf": .array([reference, .object(["type": .string("null")])])]), root: root) == ["allowed"])
        #expect(literalNames(.object(["oneOf": .array([.object(["const": .string("allowed")])])]), root: [:]) == ["allowed"])
        #expect(literalNames(.object(["anyOf": .array([names, .object(["type": .string("string")])])]), root: [:]) == nil)
        #expect(literalNames(reference, root: ["$defs": .object(["Names": reference])]) == nil)
    }

    @Test func modelToolSchemasConstrainNamesButTheGatewayStillChecksCalls() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        let session = AgentChatToolSession(backend: runtime.backend)
        defer { session.invalidate() }
        let bridge = try AppleChatToolBridge(session: session)
        let tools = try await bridge.modelTools()
        let encoded = try JSONEncoder().encode(tools.map(\.parameters))
        guard case .array(let schemas) = try JSONDecoder().decode(AgentJSONValue.self, from: encoded) else {
            Issue.record("Missing native schemas"); return
        }
        for schema in schemas {
            guard case .object(let root) = schema, case .object(let properties) = root["properties"],
                  let field = properties["name"], let choices = literalNames(field, root: root) else {
                Issue.record("Missing constrained tool names: \(String(decoding: try JSONEncoder().encode(schema), as: UTF8.self))"); return
            }
            let expected = Set(try await session.tools().map(\.name))
            #expect(choices == expected && choices.contains("draftly_drafts_get"))
            #expect(!choices.contains("draftly_drafts_create") && !choices.contains("draftly_tools"))
        }
        let catalog = try #require(tools.first { $0.name == "draftly_tools" } as? any Tool<GeneratedContent, String>)
        let description = try await catalog.call(arguments: GeneratedContent(json: "{\"name\":\"draftly_drafts_get\"}"))
        #expect(description.contains("inputSchema"))
        let call = try #require(tools.first { $0.name == "draftly_call" } as? any Tool<GeneratedContent, String>)
        let arguments: AgentJSONValue = .object(["name": .string("draftly_drafts_get"),
            "targets": .array([.object(["kind": .string("draft"), "id": .string(runtime.allowed.id.uuidString)])]),
            "parametersJSON": .null])
        let json = String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)
        #expect(try await call.call(arguments: GeneratedContent(json: json)).contains(runtime.allowed.content))
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await call.call(arguments: GeneratedContent(json: "{\"name\":\"draftly_drafts_create\"}"))
        }
    }

    @Test func nativeToolArgumentsPrepareEditAndRecoverWithoutOverwritingLaterText() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        let preferences = try TestPreferences(prefix: "Apple-Tool-Edit-")
        defer { preferences.close() }
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        let model = WindowModel(library: runtime.library, dependencies: dependencies)
        model.editor.load(runtime.allowed, focusEditor: false)
        let editors = AgentEditorRegistry(library: runtime.library, models: { [model] })
        defer { editors.invalidate() }
        runtime.service = try AgentCommandService(library: runtime.library, libraryID: runtime.libraryID, connections: runtime.registry,
            appVersion: "Apple bridge fixture", validateHost: {}, isLocked: { false }, editors: editors, pendingEditorGeneration: { _ in "" })
        let record = try runtime.registry.connectFromUserInterface(name: "Apple edit fixture", libraryID: runtime.libraryID,
            capabilities: [.draftsRead, .draftsWrite], scope: .resources([.init(kind: .draft, id: runtime.allowed.id)]))
        defer { _ = try? runtime.registry.revokeFromUserInterface(record.id) }
        runtime.session = try runtime.service.authenticate(connectionID: record.id, credential: #require(runtime.secrets[record.id]))
        let session = AgentChatToolSession(backend: runtime.backend)
        defer { session.invalidate() }
        let bridge = try AppleChatToolBridge(session: session)
        let tools = try await bridge.modelTools()
        let call = try #require(tools.first { $0.name == "draftly_call" } as? any Tool<GeneratedContent, String>)
        func invoke(_ name: String, _ fields: [String: AgentJSONValue]) async throws -> AgentResponse {
            var values = fields; values["name"] = .string(name)
            let data = try JSONEncoder().encode(AgentJSONValue.object(values))
            let result = try await call.call(arguments: GeneratedContent(json: String(decoding: data, as: UTF8.self)))
            return try JSONDecoder().decode(AgentResponse.self, from: Data(result.utf8))
        }
        let targets: AgentJSONValue = .array([.object(["kind": .string("draft"), "id": .string(runtime.allowed.id.uuidString)])])
        let read = try await invoke("draftly_drafts_get", ["targets": targets])
        guard case .result(.object(let result)) = read.outcome, case .object(let draft) = result["draft"],
              case .string(let version) = draft["versionToken"] else { Issue.record("Missing version"); return }
        let id = UUID()
        let parameters: AgentJSONValue = .object(["changes": .object(["content": .string("Apple bridge café 🐼")])])
        let intent: AgentJSONValue = .object(["apiVersion": .integer(1), "requestID": .string(id.uuidString),
            "operation": .string("drafts.update"), "targets": targets, "expectedVersion": .string(version), "parameters": parameters])
        let prepareJSON = String(decoding: try JSONEncoder().encode(AgentJSONValue.object(["request": intent])), as: UTF8.self)
        let prepared = try await invoke("draftly_mutations_prepare", ["requestID": .string(UUID().uuidString), "parametersJSON": .string(prepareJSON)])
        guard case .result(.object(let receipt)) = prepared.outcome, case .string(let key) = receipt["retryKey"] else {
            Issue.record("Missing retry key"); return
        }
        let write: [String: AgentJSONValue] = ["requestID": .string(id.uuidString), "targets": targets,
            "expectedVersion": .string(version), "retryKey": .string(key),
            "parametersJSON": .string(String(decoding: try JSONEncoder().encode(parameters), as: UTF8.self))]
        let written = try await invoke("draftly_drafts_update", write)
        guard case .result = written.outcome else { Issue.record("Write failed"); return }
        #expect(model.editor.content == "Apple bridge café 🐼" && !model.hasUnsavedChanges)
        #expect(runtime.library.notes.first { $0.id == runtime.hidden.id }?.content == runtime.hidden.content)
        model.editor.content = "Later pending text"; model.hasUnsavedChanges = true
        let revisions = runtime.library.revisions
        #expect(try await invoke("draftly_drafts_update", write) == written)
        #expect(model.editor.content == "Later pending text" && model.hasUnsavedChanges)
        #expect(runtime.library.revisions == revisions && runtime.library.notes.count == 2)
    }

    @Test(arguments: ["onDevice", "pcc"])
    func returningFromInferenceClosesRetainedToolCallbacks(mode: String) async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        let session = AgentChatToolSession(backend: runtime.backend)
        defer { session.invalidate() }
        var retained: AppleChatToolBridge?
        let responder = AppleChatResponder(generate: { _, selected, bridge in
            #expect(selected == mode)
            retained = bridge
            return try await bridge.execute(name: "draftly_drafts_get", argumentsJSON: runtime.arguments(runtime.allowed.id))
        })
        #expect(try await responder.respond(prompt: "Read neutral draft", mode: mode, session: session).contains(runtime.allowed.content))
        let bridge = try #require(retained), before = runtime.dispatches
        await #expect(throws: CancellationError.self) { try await bridge.catalog() }
        #expect(runtime.dispatches == before)
        #expect(try await session.tools().contains { $0.name == "draftly_drafts_get" })
    }

    @Test func cancellingInferenceBlocksLateToolsBeforeTheGeneratorReturns() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        let session = AgentChatToolSession(backend: runtime.backend)
        defer { session.invalidate() }
        var retained: AppleChatToolBridge?
        var continuation: CheckedContinuation<String, Never>?
        let responder = AppleChatResponder(generate: { _, _, bridge in
            retained = bridge
            return await withCheckedContinuation { continuation = $0 }
        })
        let response = Task { try await responder.respond(prompt: "Wait", mode: "onDevice", session: session) }
        for _ in 0..<1000 where continuation == nil { await Task.yield() }
        let pending = try #require(continuation), bridge = try #require(retained)
        response.cancel()
        let before = runtime.dispatches
        await #expect(throws: CancellationError.self) { try await bridge.execute(name: "draftly_drafts_get", argumentsJSON: runtime.arguments(runtime.allowed.id)) }
        #expect(runtime.dispatches == before)
        pending.resume(returning: "Late response")
        await #expect(throws: CancellationError.self) { try await response.value }
    }

    @Test func cancellingDuringDiscoveryDoesNotDispatchTheLaterRead() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        var held: CheckedContinuation<AgentResponse, Never>?
        var requests: [String] = []
        var heldResult: AgentResponse?
        let session = AgentChatToolSession(backend: { request in
            requests.append(request.operation)
            let result = try runtime.backend(request)
            if request.operation == "server.capabilities" {
                heldResult = result
                return await withCheckedContinuation { held = $0 }
            }
            return result
        })
        defer { session.invalidate() }
        let bridge = try AppleChatToolBridge(session: session)
        let read = Task { try await bridge.execute(name: "draftly_drafts_get", argumentsJSON: runtime.arguments(runtime.allowed.id)) }
        for _ in 0..<1000 where held == nil { await Task.yield() }
        let pending = try #require(held)
        bridge.lifetime.invalidate()
        pending.resume(returning: try #require(heldResult))
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(requests == ["server.capabilities"])
    }

    @Test func toolBudgetCannotBeBypassedWithAnotherToolName() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        let session = AgentChatToolSession(backend: runtime.backend)
        defer { session.invalidate() }
        let bridge = try AppleChatToolBridge(session: session, maximumCalls: 1)
        _ = try await bridge.catalog()
        let before = runtime.dispatches
        await #expect(throws: AgentErrorCode.unavailable) {
            try await bridge.execute(name: "draftly_drafts_get", argumentsJSON: runtime.arguments(runtime.allowed.id))
        }
        #expect(runtime.dispatches == before)
    }
    #if DRAFTLY_APPLE_LIVE_QA
    @Test
    func onDeviceInferenceReadsOnlyTheNeutralFixtureThroughTheGateway() async throws {
        try #require(AppleModelAccess.modes().contains("onDevice"))
        let runtime = try AgentChatToolSessionTests.Runtime()
        var reads = 0
        let session = AgentChatToolSession(backend: { request in
            if request.operation == "drafts.get" { reads += 1 }
            return try runtime.backend(request)
        })
        defer { session.invalidate() }
        let response = try await AppleChatResponder().respond(
            prompt: "Inspect the draftly_drafts_get schema with draftly_tools. Then use draftly_call to read draft "
                + runtime.allowed.id.uuidString + ". Return its exact content. You must use the tool; do not guess the content.",
            mode: "onDevice", session: session)
        #expect(reads > 0)
        #expect(response.contains(runtime.allowed.content))
        #expect(!response.contains(runtime.hidden.content))
    }
    #endif

}
