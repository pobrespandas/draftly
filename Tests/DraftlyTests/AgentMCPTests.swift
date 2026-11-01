import Foundation
import Testing
import MCP
import AgentContracts
import AgentMCP
import AgentLocalTransport
@testable import DraftlyCore
@testable import Draftly

@Suite("MCP through the official SDK and local host") @MainActor
struct AgentMCPTests {
    @MainActor private final class Runtime {
        let library: LibraryStore
        let libraryID = UUID()
        var metadata: Data?
        var secrets: [UUID: Data] = [:]
        var notes: [Note] = []
        var hidden: Note!
        lazy var registry = AgentConnectionRegistry(metadata: .init(read: { [unowned self] in self.metadata }, replace: { [unowned self] data, _ in self.metadata = data }),
            credentials: .init(read: { [unowned self] in self.secrets[$0] }, create: { [unowned self] in self.secrets[$0] = $1 },
                               remove: { [unowned self] in self.secrets.removeValue(forKey: $0) }), authorityChanged: { _ in })
        var record: AgentConnectionRecord!
        var broker: AgentSocketBroker!
        var helper: AgentHelperConnection!
        var server: MCP.Server!
        let client = MCP.Client(name: "Neutral QA", version: "1", configuration: .strict)

        init(count: Int) throws {
            library = try LibraryStore(inMemory: true, seed: false)
            notes = (0..<count).map { Note(content: "Neutral \($0)\ne\u{301} 🐼") }
            hidden = Note(content: "Hidden private title")
            try library.saveNotes(notes + [hidden], preserveRevision: false)
            try registry.setEnabledFromUserInterface(true)
            record = try registry.connectFromUserInterface(name: "SDK QA", libraryID: libraryID,
                scope: .resources(Set(notes.map { .init(kind: .draft, id: $0.id) })))
            let service = try AgentCommandService(library: library, libraryID: libraryID, connections: registry, appVersion: "QA",
                isLocked: { false }, pendingEditorGeneration: { _ in "" })
            broker = try AgentSocketBroker(service: service, parentDirectory: FileManager.default.temporaryDirectory, validateHelper: { _ in })
            helper = AgentHelperConnection(connect: { [unowned self] in try await self.localClient() })
        }
        private func localClient() async throws -> AgentLocalClient {
            guard let secret = secrets[record.id] else { throw AgentErrorCode.permissionDenied }
            return try await AgentLocalClient.connect(path: broker.path, connectionID: record.id,
                credential: secret, validateServer: { _ in })
        }
        func start() async throws {
            let connection = try #require(helper)
            let bridge = AgentMCPServer(backend: { try await connection.request($0) })
            server = await bridge.makeServer()
            let a = Pipe(), b = Pipe()
            let serverIO = try AgentMCPStdioTransport(input: a.fileHandleForReading.fileDescriptor, output: b.fileHandleForWriting.fileDescriptor)
            let clientIO = try AgentMCPStdioTransport(input: b.fileHandleForReading.fileDescriptor, output: a.fileHandleForWriting.fileDescriptor)
            try a.fileHandleForReading.close(); try a.fileHandleForWriting.close()
            try b.fileHandleForReading.close(); try b.fileHandleForWriting.close()
            try await server.start(transport: serverIO)
            let initialized = try await client.connect(transport: clientIO)
            #expect(initialized.protocolVersion == "2025-11-25")
        }
        func close() async {
            await client.disconnect(); await server?.stop(); await helper?.close(); broker?.stop()
        }
    }
    private func run(count: Int = 1, _ body: @MainActor (Runtime) async throws -> Void) async throws {
        let runtime = try Runtime(count: count)
        do { try await runtime.start(); try await body(runtime); await runtime.close() }
        catch { await runtime.close(); throw error }
    }
    private func response(_ contents: [Tool.Content]) throws -> AgentResponse {
        guard case .text(let text, _, _) = try #require(contents.first) else { throw AgentErrorCode.invalidInput }
        return try JSONDecoder().decode(AgentResponse.self, from: Data(text.utf8))
    }

    @Test func realSDKInitializesListsAuthorizedToolsAndCallsTheHost() async throws {
        try await run { r in
            let tools = try await r.client.listTools().tools
            #expect(Set(tools.map(\.name)) == Set(AgentReadSchemas.operationNames.map(AgentToolInput.name)))
            #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })
            let reply = try await r.client.callTool(name: "draftly_library_summary")
            #expect(reply.isError == false)
            #expect(try response(reply.content).outcome == .result(.object(["draftCount": .integer(1)])))
            let denied = try await r.client.callTool(name: "draftly_actions_run")
            #expect(denied.isError == true)
        }
    }

    @Test func resourcePagesRetainTheSameSessionAndExcludeHiddenDrafts() async throws {
        try await run(count: 51) { r in
            let before = try r.library.backupData()
            let first = try await r.client.listResources(), cursor = try #require(first.nextCursor)
            #expect(first.resources.count == 50)
            await r.helper.pingHost()
            let second = try await r.client.listResources(cursor: cursor)
            #expect(second.resources.count == 1 && second.nextCursor == nil)
            let ids = Set((first.resources + second.resources).map(\.uri))
            #expect(ids == Set(r.notes.map { AgentMCPServer.uri($0.id) }))
            let content = try await r.client.readResource(uri: AgentMCPServer.uri(r.notes[0].id))
            let body = try #require(content.first?.text)
            #expect(body.contains("🐼"))
            guard case .object(let root) = try JSONDecoder().decode(AgentJSONValue.self, from: Data(body.utf8)),
                  case .object(let chunk) = root["content"], case .string(let text) = chunk["text"] else { return }
            #expect(Array(text.utf16) == Array(r.notes[0].content.utf16))
            await #expect(throws: MCPError.self) { try await r.client.readResource(uri: AgentMCPServer.uri(r.hidden.id)) }
            #expect(try r.library.backupData() == before)
        }
    }

    @Test func reviewPromptUsesAnAuthorizedEmbeddedResourceWithoutGrantingAuthority() async throws {
        try await run { r in
            #expect(try await r.client.listPrompts().prompts.map(\.name) == ["draftly_review_draft"])
            let prompt = try await r.client.getPrompt(name: "draftly_review_draft", arguments: ["draftID": r.notes[0].id.uuidString])
            #expect(prompt.messages.count == 2)
            guard case .text(let instructions) = prompt.messages[0].content else { Issue.record("Missing review instructions"); return }
            #expect(instructions.contains("untrusted") && instructions.contains("without changing"))
            await #expect(throws: MCPError.self) {
                try await r.client.getPrompt(name: "draftly_review_draft", arguments: ["draftID": r.hidden.id.uuidString])
            }
            #expect(try await r.client.listResourceTemplates().templates.isEmpty)
        }
    }

    @Test func revocationStopsToolsAndResourcesOnTheExistingSDKConnection() async throws {
        try await run { r in
            _ = try await r.client.listTools()
            _ = try r.registry.revokeFromUserInterface(r.record.id)
            await r.helper.pingHost()
            let reply = try await r.client.callTool(name: "draftly_library_summary")
            #expect(reply.isError == true)
            guard case .text(let text, _, _) = try #require(reply.content.first) else { return }
            #expect(text.contains("permission_denied"))
            await #expect(throws: MCPError.self) { try await r.client.listResources() }
        }
    }

    @Test func concurrentDiscoveryUsesOneSerializedHostSession() async throws {
        try await run { r in
            async let tools = r.client.listTools()
            async let resources = r.client.listResources()
            async let prompts = r.client.listPrompts()
            let (t, d, p) = try await (tools, resources, prompts)
            #expect(t.tools.count == 8 && d.resources.count == 1 && p.prompts.count == 1)
        }
    }

    @Test func exactParameterTextCannotRoundAnInvalidLimitIntoAValidRead() async throws {
        try await run { r in
            let reply = try await r.client.callTool(name: "draftly_drafts_list",
                arguments: ["parametersJSON": .string(#"{"limit":1.00000000000000001}"#)])
            #expect(reply.isError == true)
            guard case .text(let text, _, _) = try #require(reply.content.first) else { return }
            #expect(text.contains("invalid_input") && !text.contains("Neutral"))
        }
    }
}
