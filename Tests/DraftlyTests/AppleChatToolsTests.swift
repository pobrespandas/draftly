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
        await #expect(throws: AgentErrorCode.permissionDenied) { try await bridge.createDraft(content: "Denied") }
        #expect(!runtime.library.notes.contains { $0.content == "Denied" })
    }

    @Test func compactModelSchemasKeepGatewayAuthorization() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        let session = AgentChatToolSession(backend: runtime.backend)
        defer { session.invalidate() }
        let bridge = try AppleChatToolBridge(session: session)
        let tools = try await bridge.modelTools()
        // Keep valid names constrained for the small local model.
        let encoded = try JSONEncoder().encode(tools.map(\.parameters))
        #expect(String(decoding: encoded, as: UTF8.self).contains("draftly_drafts_get"))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("draftly_drafts_create"))
        let listing = try JSONDecoder().decode(AgentJSONValue.self, from: Data(try await bridge.catalog().utf8))
        guard case .object(let fields) = listing, case .array(let names) = fields["tools"] else {
            Issue.record("Missing compact catalog"); return
        }
        #expect(names.contains(.string("draftly_drafts_get")))
        #expect(!names.contains(.string("draftly_drafts_create")))
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

    @Test func libraryCatalogLoadsDescriptionsOnlyForTheChosenOperation() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        let editors = AgentEditorRegistry(library: runtime.library, models: { [] })
        defer { editors.invalidate() }
        runtime.service = try AgentCommandService(library: runtime.library, libraryID: runtime.libraryID,
            connections: runtime.registry, appVersion: "Catalog QA", validateHost: {}, isLocked: { false },
            editors: editors, pendingEditorGeneration: { _ in "" })
        let record = try runtime.registry.connectFromUserInterface(name: "Library catalog QA", libraryID: runtime.libraryID,
            capabilities: runtime.service.availableCapabilities, scope: .library)
        runtime.session = try runtime.service.authenticate(connectionID: record.id, credential: #require(runtime.secrets[record.id]))
        let session = AgentChatToolSession(backend: runtime.backend)
        defer { session.invalidate() }
        let bridge = try AppleChatToolBridge(session: session)
        let definitions = try await session.tools()
        #expect(definitions.contains { $0.name == "draftly_drafts_update" })
        let catalog = try await bridge.catalog()
        #expect(!catalog.contains("inputSchema"))
        let detail = try await bridge.catalog(name: "draftly_drafts_get")
        #expect(detail.contains("inputSchema") && detail.contains("description"))
        let nativeSchemas = try JSONEncoder().encode(try await bridge.modelTools().map(\.parameters))
        // Bound transport bytes, not model tokens. Real-model QA checks context use.
        #expect(catalog.utf8.count < 8_000)
        #expect(nativeSchemas.count < 32_000)
        let created = try await bridge.createDraft(content: "Created café 🐼")
        #expect(created.contains("result"))
        #expect(runtime.library.notes.contains { $0.content == "Created café 🐼" })
        _ = try runtime.registry.revokeFromUserInterface(record.id)
        await #expect(throws: AgentErrorCode.permissionDenied) { try await bridge.catalog() }
    }

    #if DRAFTLY_APPLE_LIVE_QA
    @Test func onDeviceLibraryCatalogCreatesAndReadsNeutralDraft() async throws {
        try #require(AppleModelAccess.modes().contains("onDevice"))
        let runtime = try AgentChatToolSessionTests.Runtime()
        let editors = AgentEditorRegistry(library: runtime.library, models: { [] })
        defer { editors.invalidate() }
        runtime.service = try AgentCommandService(library: runtime.library, libraryID: runtime.libraryID,
            connections: runtime.registry, appVersion: "Catalog live QA", validateHost: {}, isLocked: { false },
            editors: editors, pendingEditorGeneration: { _ in "" })
        let record = try runtime.registry.connectFromUserInterface(name: "Live catalog QA", libraryID: runtime.libraryID,
            capabilities: runtime.service.availableCapabilities, scope: .library)
        runtime.session = try runtime.service.authenticate(connectionID: record.id, credential: #require(runtime.secrets[record.id]))
        var operations: [String] = []
        let session = AgentChatToolSession(backend: { request in
            operations.append(request.operation)
            return try runtime.backend(request)
        })
        defer { session.invalidate() }
        let response = try await AppleChatResponder().respond(
            prompt: "Creá una nota nueva con el texto exacto: QA Apple café 🐼. Usá las herramientas de Draftly y después leé la nota creada.",
            mode: "onDevice", session: session)
        #expect(runtime.library.notes.contains { $0.content == "QA Apple café 🐼" }, Comment(rawValue: "Operations: \(operations). Response: \(response)"))
        #expect(operations.contains("drafts.create"))
        #expect(operations.contains("drafts.get"), Comment(rawValue: "Operations: \(operations). Response: \(response)"))
        #expect(!response.isEmpty)
    }

    @Test
    func onDeviceModelEditsTheAuthorizedDraft() async throws {
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
        let session = AgentChatToolSession(backend: runtime.backend, currentDraftID: runtime.allowed.id)
        defer { session.invalidate() }
        let response = try await AppleChatResponder().respond(
            prompt: "Reemplazá el texto del draft abierto por una sola línea: Apple QA café 🐼. Decime si quedó guardada.",
            mode: "onDevice", session: session)
        #expect(runtime.library.notes.first { $0.id == runtime.allowed.id }?.content == "Apple QA café 🐼", Comment(rawValue: response))
        #expect(runtime.library.notes.first { $0.id == runtime.hidden.id }?.content == runtime.hidden.content)
    }

    #endif

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
        let malformed = try GeneratedContent(json: #"{"name":"draftly_mutations_prepare"}"#)
        let feedback = try await call.call(arguments: malformed)
        #expect(feedback.contains("invalid_input") && feedback.contains("requestID"))
        #expect(model.editor.content == runtime.allowed.content)
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

    @Test func wrappedToolFailureKeepsTheSchemaOutOfTheChat() async throws {
        let runtime = try AgentChatToolSessionTests.Runtime()
        let session = AgentChatToolSession(backend: runtime.backend)
        defer { session.invalidate() }
        let responder = AppleChatResponder(generate: { _, _, bridge in
            let tools = try await bridge.modelTools()
            let tool = try #require(tools.first { $0.name == "draftly_call" })
            throw LanguageModelSession.ToolCallError(tool: tool, underlyingError: AgentErrorCode.invalidInput)
        })
        do {
            _ = try await responder.respond(prompt: "Edit neutral draft", mode: "onDevice", session: session)
            Issue.record("Expected the tool call to fail")
        } catch {
            #expect(error.localizedDescription ==
                "Apple Intelligence could not complete the Draftly tool call. Check the draft before trying again.")
        }
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
