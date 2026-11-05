import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Chat tools through the local permission service") @MainActor
struct AgentChatToolSessionTests {
    @MainActor final class Runtime {
        var metadata: Data?
        var secrets: [UUID: Data] = [:]
        let libraryID = UUID()
        let library: LibraryStore
        let allowed = Note(content: "Allowed café 🐼")
        let hidden = Note(content: "Hidden private content")
        var record: AgentConnectionRecord!
        var service: AgentCommandService!
        var session: AgentCommandService.Session!
        var dispatches = 0
        lazy var registry = AgentConnectionRegistry(metadata: .init(read: { self.metadata }, replace: { data, _ in self.metadata = data }),
            credentials: .init(read: { self.secrets[$0] }, create: { self.secrets[$0] = $1 },
                               remove: { self.secrets.removeValue(forKey: $0) }), authorityChanged: { _ in })
        init() throws {
            library = try LibraryStore(inMemory: true, seed: false)
            try library.saveNotes([allowed, hidden], preserveRevision: false)
            try registry.setEnabledFromUserInterface(true)
            record = try registry.connectFromUserInterface(name: "Chat QA", libraryID: libraryID,
                capabilities: [.draftsRead], scope: .resources([.init(kind: .draft, id: allowed.id)]))
            service = try AgentCommandService(library: library, libraryID: libraryID, connections: registry,
                appVersion: "QA", validateHost: {}, isLocked: { false }, pendingEditorGeneration: { _ in "" })
            session = try service.authenticate(connectionID: record.id, credential: #require(secrets[record.id]))
        }
        func backend(_ request: AgentRequest) throws -> AgentResponse {
            dispatches += 1
            let bound = AgentRequest(requestID: request.requestID, libraryID: libraryID, operation: request.operation,
                targets: request.targets, expectedVersion: request.expectedVersion, retryKey: request.retryKey,
                parameters: request.parameters)
            return try JSONDecoder().decode(AgentResponse.self, from: service.respond(to: JSONEncoder().encode(bound), session: session))
        }
        func arguments(_ id: UUID) throws -> String {
            let value: AgentJSONValue = .object(["targets": .array([.object([
                "kind": .string("draft"), "id": .string(id.uuidString)
            ])])])
            return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        }
    }

    @Test func realServiceFiltersReadsAndRejectsReplayAndRevocation() async throws {
        let runtime = try Runtime()
        let tools = AgentChatToolSession(service: runtime.service, session: runtime.session)
        let names = try await tools.tools().map(\.name)
        #expect(names.contains("draftly_drafts_get") && !names.contains("draftly_drafts_create"))
        let result = try await tools.execute(callID: "allowed", tool: "draftly_drafts_get", argumentsJSON: runtime.arguments(runtime.allowed.id))
        #expect(result.contains("Allowed café 🐼"))
        let hidden = try await tools.execute(callID: "hidden", tool: "draftly_drafts_get", argumentsJSON: runtime.arguments(runtime.hidden.id))
        #expect(!hidden.contains(runtime.hidden.content))
        #expect(hidden.contains("not_found"))
        await #expect(throws: AgentErrorCode.invalidInput) {
            try await tools.execute(callID: "allowed", tool: "draftly_drafts_get", argumentsJSON: runtime.arguments(runtime.allowed.id))
        }
        _ = try runtime.registry.revokeFromUserInterface(runtime.record.id)
        await #expect(throws: AgentErrorCode.permissionDenied) { try await tools.tools() }
    }

    @Test func changedContextEndsAccessBeforeAnyRequest() async throws {
        var calls = 0, disconnects = 0, invalidations = 0
        let tools = AgentChatToolSession(backend: { _ in
            calls += 1; throw AgentErrorCode.unavailable
        }, onDisconnect: { disconnects += 1 }, validateContext: { throw AgentErrorCode.permissionDenied })
        tools.onInvalidated = { invalidations += 1 }
        await #expect(throws: AgentErrorCode.permissionDenied) { try await tools.tools() }
        await #expect(throws: AgentErrorCode.cancelled) { try await tools.tools() }
        #expect(calls == 0 && disconnects == 1 && invalidations == 1)
    }

    @Test func invalidationDiscardsLateResultsAndBlocksNewCalls() async throws {
        let runtime = try Runtime()
        var toolSession: AgentChatToolSession!
        toolSession = AgentChatToolSession(backend: { request in
            let result = try runtime.backend(request)
            if request.operation == "drafts.get" { toolSession.invalidate() }
            return result
        })
        await #expect(throws: AgentErrorCode.cancelled) {
            try await toolSession.execute(callID: "one", tool: "draftly_drafts_get", argumentsJSON: runtime.arguments(runtime.allowed.id))
        }
        let count = runtime.dispatches
        await #expect(throws: AgentErrorCode.cancelled) { try await toolSession.tools() }
        #expect(runtime.dispatches == count)
    }
}
