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
        var allowedAction: DraftAction?
        var hiddenAction: DraftAction?
        var allowedGroup: UUID?
        var activityRoot: URL?
        var activityStore: AgentActivityStore?
        var activityRequestID: UUID?
        var editorModels: [WindowModel] = []
        var editorPreferences: TestPreferences?
        lazy var registry = AgentConnectionRegistry(metadata: .init(read: { [unowned self] in self.metadata }, replace: { [unowned self] data, _ in self.metadata = data }),
            credentials: .init(read: { [unowned self] in self.secrets[$0] }, create: { [unowned self] in self.secrets[$0] = $1 },
                               remove: { [unowned self] in self.secrets.removeValue(forKey: $0) }), authorityChanged: { _ in })
        var record: AgentConnectionRecord!
        var broker: AgentSocketBroker!
        var helper: AgentHelperConnection!
        var server: MCP.Server!
        let client = MCP.Client(name: "Neutral QA", version: "1", configuration: .strict)

        init(count: Int, writeAccess: Bool = false, revisionAccess: Bool = false, editorAccess: Bool = false, actionAccess: Bool = false, activityAccess: Bool = false, fileAccess: Bool = false) throws {
            library = try LibraryStore(inMemory: true, seed: false)
            notes = (0..<count).map { Note(content: "Neutral \($0)\ne\u{301} 🐼") }
            hidden = Note(content: "Hidden private title")
            try library.saveNotes(notes + [hidden], preserveRevision: false)
            if revisionAccess, let note = notes.first {
                let value = Revision(noteID: note.id, content: "Restored e\u{0301} 🐼")
                try library.saveRevision(value); revision = value
            }
            let editors: AgentEditorRegistry?
            if editorAccess {
                let preferences = try TestPreferences(prefix: "Draftly-Agent-SDK-Editor-")
                editorPreferences = preferences
                for note in notes + [try #require(hidden)] {
                    var dependencies = WindowDependencies()
                    dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
                    let model = WindowModel(library: library, dependencies: dependencies)
                    model.editor.load(note, focusEditor: false)
                    model.editor.content = "Pending " + note.content
                    model.hasUnsavedChanges = true
                    editorModels.append(model)
                }
                editors = AgentEditorRegistry(library: library, models: { [weak self] in self?.editorModels ?? [] })
            } else { editors = writeAccess ? AgentEditorRegistry(library: library, models: { [] }) : nil }
            var resources = notes.map { AgentResourceReference(kind: .draft, id: $0.id) }
            resources += revision.map { [.init(kind: .revision, id: $0.id)] } ?? []
            if editorAccess { resources += try editors?.windowSnapshots().map { .init(kind: .window, id: $0.id) } ?? [] }
            if actionAccess {
                var allowed = DraftAction(name: "Allowed action", steps: []); allowed.group = "Allowed group"
                var hidden = DraftAction(name: "Hidden action", steps: []); hidden.group = "Hidden group"
                try library.saveActions([allowed, hidden])
                let group = try #require(library.actionGroupIdentifiers[allowed.group])
                allowedAction = allowed; hiddenAction = hidden; allowedGroup = group
                resources += [.init(kind: .action, id: allowed.id), .init(kind: .actionGroup, id: group)]
            }
            try registry.setEnabledFromUserInterface(true)
            var capabilities: Set<AgentCapability> = writeAccess ? [.draftsRead, .draftsWrite] : [.draftsRead]
            if editorAccess { capabilities.insert(.editorRead) }
            if actionAccess { capabilities.insert(.actionsRead) }
            if fileAccess { capabilities.formUnion([.filesRead, .filesWrite]) }
            record = try registry.connectFromUserInterface(name: "SDK QA", libraryID: libraryID,
                capabilities: capabilities, scope: .resources(Set(resources)))
            let activityReader: ((UUID, UUID) throws -> [AgentActivityStore.Entry])?
            if activityAccess {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-MCP-Activity-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                activityRoot = root
                let store = try AgentActivityStore(parentDirectory: root), own = UUID()
                activityStore = store
                activityRequestID = own
                try store.append(libraryID: libraryID, connectionID: record.id, grantID: record.grantID,
                                 requestID: own, operation: "server.status", result: "success")
                try store.append(libraryID: libraryID, connectionID: record.id, grantID: UUID(),
                                 requestID: UUID(), operation: "drafts.get", result: "success")
                try store.append(libraryID: libraryID, connectionID: UUID(), grantID: record.grantID,
                                 requestID: UUID(), operation: "drafts.get", result: "success")
                let id = libraryID
                activityReader = { _, _ in try store.entries(libraryID: id, inRecordingOrder: true) }
            } else { activityReader = nil }
            let service = try AgentCommandService(library: library, libraryID: libraryID, connections: registry, appVersion: "QA",
                validateHost: {}, isLocked: { false }, editors: editors, pendingEditorGeneration: { _ in "" }, readActivity: activityReader)
            broker = try AgentSocketBroker(service: service, parentDirectory: FileManager.default.temporaryDirectory, validateHelper: { _ in })
            helper = AgentHelperConnection(connect: { [unowned self] in try await self.localClient() })
        }
        private func localClient() async throws -> AgentLocalClient {
            guard let secret = secrets[record.id] else { throw AgentErrorCode.permissionDenied }
            return try await AgentLocalClient.connect(path: broker.path, connectionID: record.id,
                credential: secret, validateServer: { _ in })
        }
        func oneShotCall(_ operation: String, arguments: [String: AgentJSONValue]) async throws -> AgentResponse {
            let client = try await localClient()
            do {
                var values = arguments; values["requestID"] = .string(UUID().uuidString)
                let input = try JSONEncoder().encode(AgentJSONValue.object(values))
                let request = try AgentCLIRequest.make(mode: "call", operationName: operation, readInput: { input })
                let bytes = try await client.request(JSONEncoder().encode(request))
                await client.close()
                return try JSONDecoder().decode(AgentResponse.self, from: bytes)
            } catch { await client.close(); throw error }
        }
        func start(toolPageLimit: Int = AgentRequest.maximumBytes - 4096) async throws {
            let connection = try #require(helper)
            let bridge = AgentMCPServer(toolPageLimit: toolPageLimit, backend: { try await connection.request($0) })
            server = await bridge.makeServer()
            let a = Pipe(), b = Pipe()
            let serverIO = try AgentMCPStdioTransport(input: a.fileHandleForReading.fileDescriptor, output: b.fileHandleForWriting.fileDescriptor)
            let clientIO = try AgentMCPStdioTransport(input: b.fileHandleForReading.fileDescriptor, output: a.fileHandleForWriting.fileDescriptor)
            try a.fileHandleForReading.close(); try a.fileHandleForWriting.close()
            try b.fileHandleForReading.close(); try b.fileHandleForWriting.close()
            try await server.start(transport: serverIO)
            let initialized = try await client.connect(transport: clientIO)
            #expect(initialized.protocolVersion == "2025-11-25")
            #expect(initialized.instructions?.contains(AgentModelInstructions.results) == true)
        }
        func close() async {
            await client.disconnect(); await server?.stop(); await helper?.close(); broker?.stop()
            editorModels.forEach { $0.hasUnsavedChanges = false }
            editorModels.removeAll(); editorPreferences?.close()
            if let activityRoot { try? FileManager.default.removeItem(at: activityRoot) }
        }
    }
    private func run(count: Int = 1, writeAccess: Bool = false, revisionAccess: Bool = false, editorAccess: Bool = false, actionAccess: Bool = false, activityAccess: Bool = false, fileAccess: Bool = false, _ body: @MainActor (Runtime) async throws -> Void) async throws {
        let runtime = try Runtime(count: count, writeAccess: writeAccess, revisionAccess: revisionAccess, editorAccess: editorAccess, actionAccess: actionAccess, activityAccess: activityAccess, fileAccess: fileAccess)
        do { try await runtime.start(); try await body(runtime); await runtime.close() }
        catch { await runtime.close(); throw error }
    }
    private func response(_ contents: [Tool.Content]) throws -> AgentResponse {
        guard case .text(let text, _, _) = try #require(contents.first) else { throw AgentErrorCode.invalidInput }
        return try JSONDecoder().decode(AgentResponse.self, from: Data(text.utf8))
    }

    @Test func fullCatalogFitsDefaultTransportAndForcedPagesKeepEverySchema() async throws {
        let preferences = try AgentPreferenceCatalog.make()
        let rows = try AgentOperationCatalog.operations.map { operation -> AgentJSONValue in
            let schema = try #require(AgentOperationSchemas.schema(for: operation.name, preferences: preferences))
            return .object(["name": .string(operation.name), "available": .bool(true),
                "inputSchema": schema.parameters.jsonSchema, "resultSchema": schema.result.jsonSchema])
        }
        let backend: AgentMCPServer.Backend = { request in
            let result: [String: AgentJSONValue]
            switch request.operation {
            case "server.schemas": result = ["operations": .array(rows)]
            case "server.capabilities":
                result = ["capabilities": .array(AgentCapability.allCases.map { .string($0.rawValue) }),
                    "scope": .object(["allResources": .bool(true), "resources": .array([])]),
                    "expiresAt": .string("2099-01-01T00:00:00Z")]
            default: throw AgentErrorCode.invalidInput
            }
            return try AgentResponse(requestID: request.requestID, outcome: .result(.object(result)))
        }
        let all = try await AgentMCPServer(backend: backend).tools()
        #expect(all.nextCursor == nil)
        let expected = AgentOperationCatalog.operations.map(\.name).sorted().map(AgentToolInput.name)
        #expect(all.tools.map(\.name) == expected && Set(expected).count == 139)

        let paged = AgentMCPServer(toolPageLimit: 32_768, backend: backend)
        var page = try await paged.tools()
        var tools = page.tools
        _ = try #require(page.nextCursor)
        while let cursor = page.nextCursor {
            #expect(try JSONEncoder().encode(page).count <= 32_768)
            page = try await paged.tools(cursor: cursor)
            tools.append(contentsOf: page.tools)
            guard tools.count <= expected.count else { break }
        }
        #expect(tools == all.tools)
        #expect(try JSONEncoder().encode(page).count <= 32_768)
    }

    @Test func toolPagesKeepStableOrderAndRejectInvalidCursors() async throws {
        let runtime = try Runtime(count: 1)
        do {
            try await runtime.start(toolPageLimit: 4_096)
            let first = try await runtime.client.listTools()
            var names = first.tools.map(\.name)
            let firstCursor = try #require(first.nextCursor)
            var cursor = firstCursor
            while true {
                let page = try await runtime.client.listTools(cursor: cursor)
                names.append(contentsOf: page.tools.map(\.name))
                guard let next = page.nextCursor else { break }
                #expect(names.count < AgentReadSchemas.operationNames.union(AgentHelpSchemas.operationNames).count)
                guard names.count < AgentReadSchemas.operationNames.union(AgentHelpSchemas.operationNames).count else { break }
                cursor = next
            }
            #expect(names == AgentReadSchemas.operationNames.union(AgentHelpSchemas.operationNames).sorted().map(AgentToolInput.name))
            await #expect(throws: MCPError.self) {
                try await runtime.client.listTools(cursor: "1.invalid")
            }
            _ = try runtime.registry.revokeFromUserInterface(runtime.record.id)
            await #expect(throws: MCPError.self) {
                try await runtime.client.listTools(cursor: firstCursor)
            }
            await runtime.close()
        } catch {
            await runtime.close()
            throw error
        }
    }

    @Test func activityChangesResumesWithoutRepeatingAndRejectsExpiredAnchor() async throws {
        try await run(activityAccess: true) { runtime in
            let first = try await runtime.client.callTool(name: "draftly_activity_changes")
            guard case .result(.object(let page)) = try response(first.content).outcome,
                  case .array(let items) = page["items"], items.count == 1,
                  case .string(let cursor) = page["nextCursor"] else {
                Issue.record("Expected a scoped activity checkpoint"); return
            }
            let next = try await runtime.client.callTool(name: "draftly_activity_changes",
                arguments: ["parameters": .object(["cursor": .string(cursor)])])
            #expect(try response(next.content).outcome == .result(.object([
                "items": .array([]), "nextCursor": .string(cursor)
            ])))
            let invalid = try await runtime.client.callTool(name: "draftly_activity_changes",
                arguments: ["parameters": .object(["cursor": .string(cursor + "x")])])
            #expect(try response(invalid.content).outcome == .error(.versionConflict))
            let store = try #require(runtime.activityStore)
            let newRequest = UUID()
            try store.append(libraryID: runtime.libraryID, connectionID: runtime.record.id,
                grantID: runtime.record.grantID, requestID: newRequest, operation: "drafts.get", result: "success")
            let fresh = try await runtime.oneShotCall("activity.changes", arguments: ["parameters": .object(["cursor": .string(cursor)])])
            guard case .result(.object(let freshPage)) = fresh.outcome,
                  case .array(let newItems) = freshPage["items"], newItems.count == 1,
                  case .object(let entry) = newItems.first else {
                Issue.record("Expected one new activity entry"); return
            }
            #expect(entry["requestID"] == .string(newRequest.uuidString))
            try store.clear(libraryID: runtime.libraryID)
            let cleared = try await runtime.oneShotCall("activity.changes", arguments: ["parameters": .object(["cursor": .string(cursor)])])
            #expect(cleared.outcome == .error(.versionConflict))
        }
    }

    @Test func bundledHelpAndSkillAreReadableThroughMCPAndCLI() async throws {
        try await run { r in
            let before = r.library.notes
            let tools = try await r.client.listTools().tools
            #expect(tools.contains { $0.name == "draftly_help_search" && $0.annotations.readOnlyHint == true })
            let found = try await r.client.callTool(name: "draftly_help_search", arguments: ["parameters": .object([
                "query": .string("Undo"), "limit": .int(30)])])
            guard case .result(.object(let page)) = try response(found.content).outcome,
                  case .array(let items) = page["items"] else { Issue.record("Missing help page"); return }
            #expect(!items.isEmpty)
            let skill = try await r.oneShotCall("help.get", arguments: ["parameters": .object(["id": .string("agent-skill")])])
            guard case .result(.object(let article)) = skill.outcome else { Issue.record("Missing skill"); return }
            #expect(article["markdown"] == .string(try HelpGuide.agentSkill().markdown))
            let missing = try await r.oneShotCall("help.get", arguments: ["parameters": .object(["id": .string("missing")])])
            #expect(missing.outcome == .error(.notFound))
            #expect(r.library.notes == before)
        }
    }

    @Test func realSDKInitializesListsAuthorizedToolsAndCallsTheHost() async throws {
        try await run { r in
            let tools = try await r.client.listTools().tools
            #expect(Set(tools.map(\.name)) == Set(AgentReadSchemas.operationNames.union(AgentHelpSchemas.operationNames).map(AgentToolInput.name)))
            #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })
            let reply = try await r.client.callTool(name: "draftly_library_summary")
            #expect(reply.isError == false)
            #expect(try response(reply.content).outcome == .result(.object(["draftCount": .integer(1)])))
            let denied = try await r.client.callTool(name: "draftly_actions_run")
            #expect(denied.isError == true)
        }
    }

    @Test func oneShotCLICommandsCanReadTheNextPageWithoutReadingHiddenDrafts() async throws {
        try await run(count: 2) { r in
            let first = try await r.oneShotCall("drafts.list", arguments: ["parameters": .object([
                "limit": .integer(1), "sort": .string("title"), "ascending": .bool(true)])])
            guard case .result(.object(let page)) = first.outcome,
                  case .string(let cursor) = page["nextCursor"], case .array(let initial) = page["items"],
                  case .object(let item) = initial.first else { throw AgentErrorCode.storageError }
            let next = try await r.oneShotCall("drafts.list", arguments: ["parameters": .object([
                "limit": .integer(1), "sort": .string("title"), "ascending": .bool(true), "cursor": .string(cursor)])])
            guard case .result(.object(let last)) = next.outcome, case .array(let items) = last["items"],
                  case .object(let second) = items.first else { throw AgentErrorCode.storageError }
            #expect(initial.count == 1 && items.count == 1 && last["nextCursor"] == .null)
            let returned = [item["id"], second["id"]].compactMap { value -> String? in
                guard case .string(let id) = value else { return nil }; return id
            }
            #expect(Set(returned) == Set(r.notes.map { $0.id.uuidString }))
            #expect(second["id"] != .string(r.hidden.id.uuidString))
        }
    }

    @Test func oneShotCLIExportSurvivesTransportClosureAndIsReadableThroughMCP() async throws {
        try await run(fileAccess: true) { r in
            let note = try #require(r.notes.first), before = try r.library.backupData()
            let targets: AgentJSONValue = .array([.object(["kind": .string("draft"), "id": .string(note.id.uuidString)])])
            let export = try await r.oneShotCall("exports.drafts", arguments: ["targets": targets,
                "parameters": .object(["format": .string("text")])])
            guard case .result(.object(let fields)) = export.outcome,
                  case .object(let metadata) = fields["transfer"], case .string(let id) = metadata["transferID"] else {
                Issue.record("Missing CLI export transfer"); return
            }
            let transfer: AgentJSONValue = .array([.object(["kind": .string("operation"), "id": .string(id)])])
            let read = try await r.oneShotCall("transfers.readChunk", arguments: ["targets": transfer,
                "parameters": .object(["offset": .integer(0)])])
            guard case .result(.object(let chunk)) = read.outcome, case .string(let text) = chunk["data"] else {
                Issue.record("Missing resumed CLI bytes"); return
            }
            #expect(Data(base64Encoded: text) == Data(note.content.utf8))
            let mcp = try await r.client.callTool(name: "draftly_transfers_readChunk", arguments: [
                "requestID": .string(UUID().uuidString), "targets": .array([.object(["kind": .string("operation"), "id": .string(id)])]),
                "parameters": .object(["offset": .int(0)])])
            #expect(try response(mcp.content).outcome == read.outcome)
            let cancelled = try await r.oneShotCall("transfers.cancel", arguments: ["targets": transfer])
            #expect(cancelled.outcome == .result(.object(["transferID": .string(id), "cancelled": .bool(true)])))
            let missing = try await r.oneShotCall("transfers.readChunk", arguments: ["targets": transfer,
                "parameters": .object(["offset": .integer(0)])])
            #expect(missing.outcome == .error(.notFound))
            let denied = try await r.oneShotCall("exports.drafts", arguments: ["targets": .array([
                .object(["kind": .string("draft"), "id": .string(r.hidden.id.uuidString)])])])
            let after = try r.library.backupData()
            #expect(denied.outcome == .error(.notFound) && after == before)
        }
    }

    @Test func actionReadsThroughMCPRespectResourceScope() async throws {
        try await run(actionAccess: true) { r in
            let allowed = try #require(r.allowedAction), hidden = try #require(r.hiddenAction), group = try #require(r.allowedGroup)
            let names = Set(try await r.client.listTools().tools.map(\.name))
            #expect(names.contains("draftly_actions_get") && names.contains("draftly_actionGroups_get"))
            #expect(!names.contains("draftly_actions_run"))
            func target(_ kind: String, _ id: UUID) -> [String: MCP.Value] {
                ["targets": .array([.object(["kind": .string(kind), "id": .string(id.uuidString)])])]
            }
            let good = try await r.client.callTool(name: "draftly_actions_get", arguments: target("action", allowed.id))
            #expect(good.isError == false)
            let denied = try await r.client.callTool(name: "draftly_actions_get", arguments: target("action", hidden.id))
            #expect(denied.isError == true)
            #expect(try response(denied.content).outcome == .error(.notFound))
            let groupResult = try await r.client.callTool(name: "draftly_actionGroups_get", arguments: target("actionGroup", group))
            #expect(groupResult.isError == false)
        }
    }

    @Test func activityThroughMCPExcludesOtherConnectionsAndEarlierGrants() async throws {
        try await run(activityAccess: true) { r in
            let tools = try await r.client.listTools().tools
            let tool = try #require(tools.first { $0.name == "draftly_activity_list" })
            #expect(tool.annotations.readOnlyHint == true)
            let response = try await r.client.callTool(name: "draftly_activity_list")
            guard case .result(.object(let page)) = try self.response(response.content).outcome,
                  case .array(let items) = page["items"], case .object(let entry) = items.first else {
                Issue.record("Expected an activity page"); return
            }
            let expectedID = try #require(r.activityRequestID)
            #expect(items.count == 1 && entry["requestID"] == .string(expectedID.uuidString))
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
            #expect(t.tools.count == AgentReadSchemas.operationNames.union(AgentHelpSchemas.operationNames).count && d.resources.count == 1 && p.prompts.count == 1)
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

    @Test func sdkReadsSyntaxMetadataFromPendingEditorWithoutSaving() async throws {
        try await run(editorAccess: true) { r in
            let tools = try await r.client.listTools().tools
            for name in ["draftly_editor_markers", "draftly_editor_links", "draftly_editor_listTasks"] {
                #expect(try #require(tools.first { $0.name == name }).annotations.readOnlyHint == true)
            }
            let listed = try await r.client.callTool(name: "draftly_editor_windows")
            guard case .result(.object(let page)) = try response(listed.content).outcome,
                  case .array(let entries) = page["items"], entries.count == 1,
                  case .object(let entry) = entries[0], case .string(let id) = entry["windowID"] else {
                Issue.record("Missing scoped editor"); return
            }
            let model = try #require(r.editorModels.first)
            let content = "# Café 🐼\n- [x] neutral\n[[d:Café]]"
            model.editor.content = content
            let selection = model.editor.selection
            for name in ["draftly_editor_markers", "draftly_editor_links", "draftly_editor_listTasks"] {
                let read = try await r.client.callTool(name: name, arguments: [
                    "targets": .array([.object(["kind": .string("window"), "id": .string(id)])])])
                #expect(read.isError == false)
                guard case .result(.object(let values)) = try response(read.content).outcome,
                      case .array(let items) = values["items"] else { Issue.record("Missing syntax items"); return }
                #expect(items.count == 1)
            }
            #expect(model.editor.content == content && model.editor.selection == selection && model.hasUnsavedChanges)
            #expect(r.library.notes.first { $0.id == r.notes[0].id }?.content == r.notes[0].content)
            #expect(r.library.revisions.isEmpty)
        }
    }

    @Test func sdkFindsPendingUnicodeWithoutSavingOrSelecting() async throws {
        try await run(editorAccess: true) { r in
            let tools = try await r.client.listTools().tools
            #expect(try #require(tools.first { $0.name == "draftly_editor_find" }).annotations.readOnlyHint == true)
            let listed = try await r.client.callTool(name: "draftly_editor_windows")
            guard case .result(.object(let page)) = try response(listed.content).outcome,
                  case .array(let entries) = page["items"], entries.count == 1,
                  case .object(let entry) = entries[0], case .string(let id) = entry["windowID"] else {
                Issue.record("Missing scoped editor"); return
            }
            let model = try #require(r.editorModels.first)
            let selection = model.editor.selection
            let found = try await r.client.callTool(name: "draftly_editor_find", arguments: [
                "targets": .array([.object(["kind": .string("window"), "id": .string(id)])]),
                "parameters": .object(["query": .string("🐼")])])
            #expect(found.isError == false)
            guard case .result(.object(let values)) = try response(found.content).outcome else {
                Issue.record("Missing search result"); return
            }
            let expected = (model.editor.content as NSString).range(of: "🐼")
            #expect(values["items"] == .array([.object(["range": .object([
                "offset": .integer(Int64(expected.location)), "length": .integer(2)])])]))
            #expect(model.editor.selection == selection && model.hasUnsavedChanges)
            #expect(r.library.notes.first { $0.id == r.notes[0].id }?.content == r.notes[0].content)
            #expect(r.library.revisions.isEmpty)
        }
    }

    @Test func sdkReadsOnlyAuthorizedPendingEditorsWithoutSavingThem() async throws {
        try await run(editorAccess: true) { r in
            let tools = try await r.client.listTools().tools
            let names = Set(["draftly_editor_windows", "draftly_editor_get"])
            #expect(tools.filter { names.contains($0.name) }.count == 2)
            #expect(tools.filter { names.contains($0.name) }.allSatisfy { $0.annotations.readOnlyHint == true })
            let listed = try await r.client.callTool(name: "draftly_editor_windows")
            guard case .result(.object(let page)) = try response(listed.content).outcome,
                  case .array(let entries) = page["items"], entries.count == 1,
                  case .object(let entry) = entries[0], case .string(let id) = entry["windowID"] else {
                Issue.record("Missing scoped window"); return
            }
            let read = try await r.client.callTool(name: "draftly_editor_get", arguments: ["targets": .array([
                .object(["kind": .string("window"), "id": .string(id)])])])
            guard case .result(.object(let values)) = try response(read.content).outcome,
                  case .object(let content) = values["content"] else { Issue.record("Missing editor content"); return }
            #expect(content["text"] == .string("Pending " + (try #require(r.notes.first)).content))
            #expect(values["hasUnsavedChanges"] == .bool(true))
            #expect(r.library.notes.first { $0.id == r.notes[0].id }?.content == r.notes[0].content)
            #expect(r.library.revisions.isEmpty)
            #expect(r.editorModels.allSatisfy { $0.hasUnsavedChanges })
        }
    }

}
