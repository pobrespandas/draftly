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
        var revision: Revision?
        lazy var registry = AgentConnectionRegistry(metadata: .init(read: { [unowned self] in self.metadata }, replace: { [unowned self] data, _ in self.metadata = data }),
            credentials: .init(read: { [unowned self] in self.secrets[$0] }, create: { [unowned self] in self.secrets[$0] = $1 },
                               remove: { [unowned self] in self.secrets.removeValue(forKey: $0) }), authorityChanged: { _ in })
        var record: AgentConnectionRecord!
        var broker: AgentSocketBroker!
        var helper: AgentHelperConnection!
        var server: MCP.Server!
        let client = MCP.Client(name: "Neutral QA", version: "1", configuration: .strict)

        init(count: Int, writeAccess: Bool = false, revisionAccess: Bool = false) throws {
            library = try LibraryStore(inMemory: true, seed: false)
            notes = (0..<count).map { Note(content: "Neutral \($0)\ne\u{301} 🐼") }
            hidden = Note(content: "Hidden private title")
            try library.saveNotes(notes + [hidden], preserveRevision: false)
            if revisionAccess, let note = notes.first {
                let value = Revision(noteID: note.id, content: "Restored e\u{0301} 🐼")
                try library.saveRevision(value); revision = value
            }
            try registry.setEnabledFromUserInterface(true)
            record = try registry.connectFromUserInterface(name: "SDK QA", libraryID: libraryID,
                capabilities: writeAccess ? [.draftsRead, .draftsWrite] : [.draftsRead], scope: .resources(Set(notes.map { AgentResourceReference(kind: .draft, id: $0.id) } + (revision.map { [.init(kind: .revision, id: $0.id)] } ?? []))))
            let service = try AgentCommandService(library: library, libraryID: libraryID, connections: registry, appVersion: "QA",
                validateHost: {}, isLocked: { false },
                editors: writeAccess ? AgentEditorRegistry(library: library, models: { [] }) : nil,
                pendingEditorGeneration: { _ in "" })
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
    private func run(count: Int = 1, writeAccess: Bool = false, revisionAccess: Bool = false, _ body: @MainActor (Runtime) async throws -> Void) async throws {
        let runtime = try Runtime(count: count, writeAccess: writeAccess, revisionAccess: revisionAccess)
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
    @Test func sdkPreparesExecutesAndRecoversAScopedDraftUpdate() async throws {
        try await run(writeAccess: true) { r in
            let note = try #require(r.notes.first)
            let tools = try await r.client.listTools().tools
            #expect(tools.contains { $0.name == "draftly_mutations_prepare" })
            #expect(tools.contains { $0.name == "draftly_drafts_update" })
            let targets: MCP.Value = .array([.object(["kind": .string("draft"), "id": .string(note.id.uuidString)])])
            let read = try await r.client.callTool(name: "draftly_drafts_get", arguments: ["targets": targets])
            guard case .result(.object(let value)) = try response(read.content).outcome,
                  case .object(let draft) = value["draft"], case .string(let version) = draft["versionToken"] else {
                Issue.record("Missing read version"); return
            }
            let mutation = AgentRequest(requestID: UUID(), libraryID: nil, operation: "drafts.update",
                targets: [.init(kind: .draft, id: note.id)], expectedVersion: version,
                parameters: ["changes": .object(["content": .string("SDK update e\u{0301} 🐼")])])
            let frame = try JSONDecoder().decode(MCP.Value.self, from: JSONEncoder().encode(mutation))
            let prepared = try await r.client.callTool(name: "draftly_mutations_prepare", arguments: [
                "requestID": .string(UUID().uuidString), "parameters": .object(["request": frame])])
            guard case .result(.object(let fields)) = try response(prepared.content).outcome,
                  case .string(let key) = fields["retryKey"] else { Issue.record("Preparation failed"); return }
            #expect(r.library.notes.first { $0.id == note.id }?.content == note.content)
            let arguments: [String: MCP.Value] = ["requestID": .string(mutation.requestID.uuidString), "targets": targets,
                "expectedVersion": .string(version), "retryKey": .string(key),
                "parameters": .object(["changes": .object(["content": .string("SDK update e\u{0301} 🐼")])])]
            let changed = try await r.client.callTool(name: "draftly_drafts_update", arguments: arguments)
            #expect(changed.isError == false)
            #expect(r.library.notes.first { $0.id == note.id }?.content == "SDK update e\u{0301} 🐼")
            let revisions = r.library.revisions
            let recovered = try await r.client.callTool(name: "draftly_drafts_update", arguments: arguments)
            #expect(try response(recovered.content) == response(changed.content))
            #expect(r.library.revisions == revisions)
            #expect(r.library.notes.first { $0.id == r.hidden.id }?.content == r.hidden.content)
        }
    }

    @Test func cliNamedCallsPrepareAndExecuteThroughTheRealLocalSocket() async throws {
        try await run(writeAccess: true) { r in
            let note = try #require(r.notes.first)
            func call(_ operation: String, _ arguments: [String: AgentJSONValue]) async throws -> AgentResponse {
                let input = try JSONEncoder().encode(AgentJSONValue.object(arguments))
                let request = try AgentCLIRequest.make(mode: "call", operationName: operation, readInput: { input })
                return try await r.helper.request(request)
            }
            let targets: AgentJSONValue = .array([.object(["kind": .string("draft"), "id": .string(note.id.uuidString)])])
            guard case .result(.object(let values)) = try await call("drafts.get", ["targets": targets]).outcome,
                  case .object(let draft) = values["draft"], case .string(let version) = draft["versionToken"] else {
                Issue.record("Missing CLI read version"); return
            }
            let mutation = AgentRequest(requestID: UUID(), libraryID: nil, operation: "drafts.update",
                targets: [.init(kind: .draft, id: note.id)], expectedVersion: version,
                parameters: ["changes": .object(["flag": .integer(3)])])
            let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(mutation))
            guard case .result(.object(let prepared)) = try await call("mutations.prepare", [
                "requestID": .string(UUID().uuidString), "parameters": .object(["request": frame])]).outcome,
                  case .string(let key) = prepared["retryKey"] else { Issue.record("Missing CLI retry key"); return }
            let reply = try await call("drafts.update", ["requestID": .string(mutation.requestID.uuidString),
                "targets": targets, "expectedVersion": .string(version), "retryKey": .string(key), "parameters": .object(mutation.parameters)])
            guard case .result = reply.outcome else { Issue.record("CLI mutation failed"); return }
            #expect(r.library.notes.first { $0.id == note.id }?.flag == 3)
            #expect(r.library.notes.first { $0.id == r.hidden.id }?.flag == r.hidden.flag)
            guard case .result(.object(let current)) = try await call("drafts.get", ["targets": targets]).outcome,
                  case .object(let draft) = current["draft"], case .string(let patchVersion) = draft["versionToken"] else {
                Issue.record("Missing patch version"); return
            }
            let patch = AgentRequest(requestID: UUID(), libraryID: nil, operation: "drafts.patch",
                targets: mutation.targets, expectedVersion: patchVersion, parameters: ["edits": .array([
                    .object(["offset": .integer(0), "length": .integer(0), "text": .string("🐼 e\u{0301} ")])])])
            let patchFrame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(patch))
            guard case .result(.object(let ticket)) = try await call("mutations.prepare", [
                "requestID": .string(UUID().uuidString), "parameters": .object(["request": patchFrame])]).outcome,
                  case .string(let patchKey) = ticket["retryKey"] else { Issue.record("Missing patch key"); return }
            let result = try await call("drafts.patch", ["requestID": .string(patch.requestID.uuidString),
                "targets": targets, "expectedVersion": .string(patchVersion), "retryKey": .string(patchKey),
                "parameters": .object(patch.parameters)])
            guard case .result = result.outcome else { Issue.record("CLI patch failed"); return }
            #expect(r.library.notes.first { $0.id == note.id }?.content.utf8.elementsEqual(("🐼 e\u{0301} " + note.content).utf8) == true)
            #expect(r.library.notes.first { $0.id == r.hidden.id }?.content == r.hidden.content)
        }
    }

    @Test func sdkRestoresAnAuthorizedRevisionThroughTheLocalHost() async throws {
        try await run(writeAccess: true, revisionAccess: true) { r in
            let note = try #require(r.notes.first), revision = try #require(r.revision)
            let read = try await r.client.callTool(name: "draftly_drafts_get", arguments: ["targets": .array([
                .object(["kind": .string("draft"), "id": .string(note.id.uuidString)])])])
            guard case .result(.object(let values)) = try response(read.content).outcome,
                  case .object(let draft) = values["draft"], case .string(let token) = draft["versionToken"] else {
                Issue.record("Missing restore version"); return
            }
            let input = AgentRequest(requestID: UUID(), libraryID: nil, operation: "drafts.restoreVersion",
                targets: [.init(kind: .revision, id: revision.id), .init(kind: .draft, id: note.id)], expectedVersion: token)
            let frame = try JSONDecoder().decode(MCP.Value.self, from: JSONEncoder().encode(input))
            let prepared = try await r.client.callTool(name: "draftly_mutations_prepare", arguments: [
                "requestID": .string(UUID().uuidString), "parameters": .object(["request": frame])])
            guard case .result(.object(let ticket)) = try response(prepared.content).outcome,
                  case .string(let key) = ticket["retryKey"] else { Issue.record("Restore preparation failed"); return }
            let targets = try JSONDecoder().decode(MCP.Value.self, from: JSONEncoder().encode(input.targets))
            let result = try await r.client.callTool(name: "draftly_drafts_restoreVersion", arguments: [
                "requestID": .string(input.requestID.uuidString), "targets": targets,
                "expectedVersion": .string(token), "retryKey": .string(key)])
            #expect(result.isError == false)
            #expect(r.library.notes.first { $0.id == note.id }?.content.utf8.elementsEqual(revision.content.utf8) == true)
            #expect(r.library.notes.first { $0.id == r.hidden.id }?.content == r.hidden.content)
        }
    }

}
