import Foundation
import Combine
import AppKit
import Testing
import AgentContracts
@testable import DraftlyCore
@testable import Draftly

@Suite("Authenticated agent reads") @MainActor
struct AgentCommandServiceTests {
    @Test func actionSubmissionIsAvailableOnlyWithConnectedExecutorAndRegistry() async throws {
        let f = try Fixture()
        let (record, _) = try f.connect(capabilities: [.actionsRun, .actionsRead, .draftsRead])
        let action = DraftAction(name: "Neutral", steps: [])
        try f.library.saveAction(action)
        let note = try f.note("Neutral")
        let registry = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { false }, now: { f.wall })
        defer { registry.cancelAll() }
        var submissions = 0
        let service = try AgentCommandService(library: f.library, libraryID: f.libraryID, connections: f.connections,
            appVersion: "QA", validateHost: {}, isLocked: { false }, now: { f.wall },
            editors: f.editorRegistry, pendingEditorGeneration: { _ in "" }, operations: registry, submitAction: { request, grant in
                submissions += 1
                return try registry.startRequest(request, grant: grant) { _ in
                    .init(report: .notStarted(actionID: request.targets[0].id, reason: .cancelled, message: "Cancelled"),
                        noteID: nil, message: "Cancelled")
                }
            })
        let credential = try #require(f.secrets[record.id])
        let session = try service.authenticate(connectionID: record.id, credential: credential)
        let read = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "actions.get",
            targets: [.init(kind: .action, id: action.id)])
        let readResponse = try JSONDecoder().decode(AgentResponse.self,
            from: service.respond(to: JSONEncoder().encode(read), session: session))
        guard case .result(.object(let fields)) = readResponse.outcome,
              case .string(let version) = fields["versionToken"] else { Issue.record("Expected action version"); return }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "actions.run",
            targets: [.init(kind: .action, id: action.id), .init(kind: .draft, id: note.id)], expectedVersion: version)
        let response = try JSONDecoder().decode(AgentResponse.self,
            from: service.respond(to: JSONEncoder().encode(request), session: session))
        guard case .result(.object(let result)) = response.outcome else { Issue.record("Expected queued operation"); return }
        #expect(result["state"] == .string("queued") && submissions == 1)
        let stale = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "actions.run",
            targets: request.targets, expectedVersion: "stale-version")
        let denied = try JSONDecoder().decode(AgentResponse.self,
            from: service.respond(to: JSONEncoder().encode(stale), session: session))
        #expect(denied.outcome == .error(.versionConflict) && submissions == 1)
        let before = try service.actionExecutionSnapshot(request, connectionID: record.id)
        var changed = note; changed.content = "Changed"
        try f.library.saveNote(changed)
        let after = try service.actionExecutionSnapshot(request, connectionID: record.id)
        #expect(before["actionVersion"] == after["actionVersion"])
        #expect(before["draftVersion"] != after["draftVersion"])
        guard case .string(let rawID) = result["operationID"], let id = UUID(uuidString: rawID) else {
            Issue.record("Missing operation ID"); return
        }
        for _ in 0..<1000 where try !registry.snapshot(id, connectionID: record.id).state.isTerminal { await Task.yield() }
        let repeated = try JSONDecoder().decode(AgentResponse.self,
            from: service.respond(to: JSONEncoder().encode(request), session: session))
        guard case .result(.object(let recovered)) = repeated.outcome else { Issue.record("Missing recovered operation"); return }
        #expect(recovered["operationID"] == result["operationID"] && recovered["state"] == .string("cancelled"))
        #expect(submissions == 1)
    }
    @MainActor private final class Fixture {
        let library: LibraryStore
        let libraryID = UUID()
        var bytes: Data?
        var secrets: [UUID: Data] = [:]
        var wall = Date(timeIntervalSince1970: 1_700_000_000)
        var uptime: TimeInterval = 100
        var hostError: AgentErrorCode?
        var locked = false
        var generation = ""
        var editors: [WindowModel] = [] { didSet { editorRegistry.refreshMembership() } }
        let editorDefaultsName = "Draftly-Agent-Editor-Tests-" + UUID().uuidString
        lazy var editorRegistry = AgentEditorRegistry(library: library, models: { [weak self] in self?.editors ?? [] })
        var onGeneration: (() -> Void)?
        lazy var connections = AgentConnectionRegistry(metadata: .init(read: { [unowned self] in self.bytes },
            replace: { [unowned self] data, expected in
                guard self.bytes == expected else { throw AgentErrorCode.versionConflict }
                self.bytes = data
            }), credentials: .init(read: { [unowned self] in self.secrets[$0] },
                create: { [unowned self] in self.secrets[$0] = $1 },
                remove: { [unowned self] in self.secrets.removeValue(forKey: $0) }),
            now: { [unowned self] in self.wall }, authorityChanged: { _ in })
        var operations: AgentOperationRegistry?
        var deletionApprovals: AgentApprovalStore?
        var preferenceStorage: AgentPreferenceStorage?
        var nativePreferenceRead: ((String) throws -> AgentPreferenceReading)?
        var service: AgentCommandService!

        init() throws {
            library = try LibraryStore(inMemory: true, seed: false)
            service = try makeService()
            try connections.setEnabledFromUserInterface(true)
        }
        func makeService(withoutEditors: Bool = false) throws -> AgentCommandService {
            try AgentCommandService(library: library, libraryID: libraryID, connections: connections,
                appVersion: "QA", preferenceDefaults: try #require(UserDefaults(suiteName: editorDefaultsName)),
                preferenceStorage: preferenceStorage, nativePreferenceRead: nativePreferenceRead, validateHost: { [unowned self] in
                    if let error = self.hostError { throw error }
                }, isLocked: { [unowned self] in self.locked }, now: { [unowned self] in self.wall },
                uptime: { [unowned self] in self.uptime }, editors: withoutEditors ? nil : editorRegistry, pendingEditorGeneration: { [unowned self] _ in
                    self.onGeneration?(); return self.generation
                }, operations: operations, deletionApprovals: deletionApprovals)
        }
        func enablePreferenceWrites() throws {
            let defaults = try #require(UserDefaults(suiteName: editorDefaultsName))
            preferenceStorage = try AgentPreferenceStorage(defaults: defaults, domain: editorDefaultsName)
            service = try makeService()
        }
        func preparedMutation(_ request: AgentRequest, session: AgentCommandService.Session) throws -> AgentRequest {
            let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(request))
            let prepared = try values("mutations.prepare", session: session, parameters: ["request": frame])
            guard case .string(let key) = prepared["retryKey"] else { throw AgentErrorCode.invalidInput }
            return AgentRequest(requestID: request.requestID, libraryID: libraryID, operation: request.operation,
                targets: request.targets, expectedVersion: request.expectedVersion, retryKey: key, parameters: request.parameters)
        }
        func send(_ request: AgentRequest, session: AgentCommandService.Session) throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: service.respond(to: JSONEncoder().encode(request), session: session))
        }
        func connect(scope: AgentResourceScope = .library, capabilities: Set<AgentCapability> = [.draftsRead]) throws
            -> (AgentConnectionRecord, AgentCommandService.Session) {
            let record = try connections.connectFromUserInterface(name: "Neutral QA", libraryID: libraryID,
                capabilities: capabilities, scope: scope)
            return (record, try service.authenticate(connectionID: record.id, credential: #require(secrets[record.id])))
        }
        func note(_ content: String, tags: [String] = [], archived: Bool = false, trashed: Bool = false,
                  accessed: Date? = nil) throws -> Note {
            let value = Note(content: content, tags: tags, isArchived: archived, trashedAt: trashed ? wall : nil,
                             createdAt: wall, modifiedAt: wall, accessedAt: accessed)
            try library.saveNote(value, preserveRevision: false, preserveDates: true)
            return value
        }
        func window(_ note: Note, content: String? = nil, dirty: Bool = false, library: LibraryStore? = nil) throws -> WindowModel {
            var dependencies = WindowDependencies()
            dependencies.preferences = WindowPreferences(defaults: try #require(UserDefaults(suiteName: editorDefaultsName)))
            let model = WindowModel(library: library ?? self.library, dependencies: dependencies)
            model.editor.load(note, focusEditor: false)
            if let content { model.editor.content = content }
            model.hasUnsavedChanges = dirty
            return model
        }
        func cleanEditorPreferences() { UserDefaults.standard.removePersistentDomain(forName: editorDefaultsName) }
        func response(_ operation: String, session: AgentCommandService.Session,
                      targets: [AgentResourceReference] = [], parameters: [String: AgentJSONValue] = [:],
                      libraryID: UUID? = nil) throws -> AgentResponse {
            let request = AgentRequest(requestID: UUID(), libraryID: libraryID ?? self.libraryID, operation: operation,
                targets: targets, parameters: parameters)
            let data = try service.respond(to: JSONEncoder().encode(request), session: session)
            let result = try JSONDecoder().decode(AgentResponse.self, from: data)
            #expect(result.requestID == request.requestID)
            return result
        }
        func values(_ operation: String, session: AgentCommandService.Session,
                    targets: [AgentResourceReference] = [], parameters: [String: AgentJSONValue] = [:]) throws -> [String: AgentJSONValue] {
            let result = try response(operation, session: session, targets: targets, parameters: parameters)
            guard case .result(.object(let values)) = result.outcome else {
                Issue.record("Unexpected read outcome: \(result.outcome)"); throw AgentErrorCode.executionError
            }
            return values
        }
        func get(_ note: Note, session: AgentCommandService.Session, parameters: [String: AgentJSONValue] = [:]) throws -> [String: AgentJSONValue] {
            try values("drafts.get", session: session, targets: [.init(kind: .draft, id: note.id)], parameters: parameters)
        }
    }

    @Test(arguments: ["approve", "deny", "cancel", "session"])
    func workspaceDeletionUsesAcceptedReviewAndTerminalResults(decision: String) async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let workspace = Workspace(name: "Delete café 🐼")
        try f.library.saveWorkspace(workspace)
        let note = try f.note("Keep")
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { false }, now: { f.wall })
        let approvals = AgentApprovalStore(now: { f.wall }, currentGrant: { try? f.connections.grantForAuthenticatedConnection($0) }, isLocked: { false })
        defer { operations.cancelAll() }
        f.operations = operations; f.deletionApprovals = approvals
        f.service = try f.makeService(withoutEditors: true)
        let (record, session) = try f.connect(scope: .resources([.init(kind: .workspace, id: workspace.id)]),
            capabilities: [.workspacesRead, .workspacesManage, .destructiveRequest])
        let target = AgentResourceReference(kind: .workspace, id: workspace.id)
        let snapshot = try f.values("workspaces.get", session: session, targets: [target])
        guard case .string(let version) = snapshot["versionToken"] else { Issue.record("Missing version"); return }
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "workspaces.delete",
            targets: [target], expectedVersion: version)
        let request = try f.preparedMutation(intent, session: session)
        let accepted = try f.send(request, session: session)
        guard case .accepted(let id, _) = accepted.outcome else { Issue.record("Missing accepted operation: \(accepted)"); return }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        #expect(f.library.workspaces == [workspace])
        if decision == "cancel" {
            let response = try f.response("operations.cancel", session: session, targets: [.init(kind: .operation, id: id)])
            guard case .result = response.outcome else { Issue.record("Cancellation failed"); return }
        } else if decision == "deny" { try approvals.denyFromUserInterface(review.id) }
        else {
            if decision == "session" { f.service.invalidateAll() }
            try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        }
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: record.id).state.isTerminal {
            try await Task.sleep(for: .milliseconds(1))
        }
        let nextSession = decision == "session"
            ? try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id])) : session
        let repeated = try f.send(request, session: nextSession)
        if decision == "approve" {
            #expect(repeated.outcome == .result(.object(["deletedIDs": .array([.string(workspace.id.uuidString)])])))
            #expect(f.library.workspaces.isEmpty)
        } else {
            #expect(repeated.outcome == .error(decision == "cancel" ? .cancelled : .permissionDenied))
            #expect(f.library.workspaces == [workspace])
        }
        #expect(f.library.notes == [note] && approvals.pendingFromUserInterface().isEmpty)
        let currentGrant = try #require(try f.connections.grantForAuthenticatedConnection(record.id))
        #expect(try operations.existingRequest(request, grant: currentGrant) == id)
    }

    @Test func workspaceCreationUsesDefaultsOverridesAndDurableReceipts() throws {
        let f = try Fixture()
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        defer { defaults.removePersistentDomain(forName: f.editorDefaultsName) }
        var template = Workspace(name: "Default template")
        template.query = "café 🐼"; template.tags = ["inherited"]
        template.excludedTags = ["excluded"]; template.folder = .archive
        template.scriptMetadata = ["api": #"{"flaggedStatus":"flagged"}"#]
        try f.library.saveWorkspace(template)
        defaults.set(template.id.uuidString, forKey: WorkspaceDefaults.key)
        let (record, session) = try f.connect(capabilities: [.workspacesRead, .workspacesManage])
        let newID = UUID()
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.create",
            parameters: ["workspace": .object(["id": .string(newID.uuidString), "name": .string("New café 🐼"),
                "tags": .array([]), "excludedTags": .null])])
        let prepared = try f.preparedMutation(intent, session: session)
        #expect(f.library.workspaces == [template])
        let reply = try f.send(prepared, session: session)
        guard case .result = reply.outcome else { Issue.record("Create failed: \(reply.outcome)"); return }
        let created = try #require(f.library.workspaces.first { $0.id == newID })
        #expect(created.name == "New café 🐼" && created.query == template.query && created.folder == .archive)
        #expect(created.tags.isEmpty && created.excludedTags == nil && created.order == nil)
        #expect(created.scriptMetadata == template.scriptMetadata)
        #expect(try f.send(prepared, session: session) == reply && f.library.workspaces.count == 2)
        f.service = try f.makeService()
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let recovered = try f.preparedMutation(intent, session: reopened)
        #expect(try f.send(recovered, session: reopened) == reply && f.library.workspaces.count == 2)
    }

    @Test(arguments: [nil, "Named copy café 🐼"] as [String?])
    func workspaceDuplicationPreservesMetadataRejectsConflictsAndRecoversWithoutAnotherCopy(_ name: String?) throws {
        let f = try Fixture()
        var source = Workspace(name: "Source café 🐼")
        source.query = "tag:qa"; source.order = 7; source.tags = ["one"]
        source.excludedTags = ["two"]; source.matchAnyTag = true; source.tagged = true
        source.listOptions = DraftListOptions(); source.scriptMetadata = ["custom": "café 🐼"]
        try f.library.saveWorkspace(source)
        let target = AgentResourceReference(kind: .workspace, id: source.id)
        let (record, session) = try f.connect(capabilities: [.workspacesRead, .workspacesManage])
        let values = try f.values("workspaces.get", session: session, targets: [target])
        guard case .string(let version) = values["versionToken"] else { throw AgentErrorCode.invalidInput }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.duplicate",
            targets: [target], expectedVersion: version, parameters: name.map { ["name": .string($0)] } ?? [:])
        let prepared = try f.preparedMutation(intent, session: session)
        #expect(f.library.workspaces == [source])
        var changed = source; changed.query = "Concurrent change"
        try f.library.saveWorkspace(changed)
        #expect(try f.send(prepared, session: session).outcome == .error(.versionConflict))
        #expect(f.library.workspaces == [changed])
        try f.library.saveWorkspace(source)
        let reply = try f.send(prepared, session: session)
        guard case .result = reply.outcome else { Issue.record("Duplicate failed: \(reply.outcome)"); return }
        let copy = try #require(f.library.workspaces.first { $0.id != source.id })
        var expected = source; expected.id = copy.id; expected.name = name ?? (source.name + " Copy")
        #expect(copy == expected)
        try f.library.saveWorkspace(changed)
        #expect(try f.send(prepared, session: session) == reply && f.library.workspaces.count == 2)
        f.service = try f.makeService()
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let recovered = try f.preparedMutation(intent, session: reopened)
        #expect(try f.send(recovered, session: reopened) == reply && f.library.workspaces.count == 2)
    }

    @Test(arguments: ["workspaces.create", "workspaces.duplicate"])
    func newWorkspaceMutationsRequireLibraryScopeAndRollbackFailedCommits(_ operation: String) throws {
        let f = try Fixture(), source = Workspace(name: "Neutral source")
        try f.library.saveWorkspace(source)
        let target = AgentResourceReference(kind: .workspace, id: source.id)
        let (record, session) = try f.connect(capabilities: [.workspacesRead, .workspacesManage])
        let (_, scoped) = try f.connect(scope: .resources([target]), capabilities: [.workspacesRead, .workspacesManage])
        let (_, readOnly) = try f.connect(capabilities: [.workspacesRead])
        guard case .string(let version) = try f.values("workspaces.get", session: session, targets: [target])["versionToken"] else {
            throw AgentErrorCode.invalidInput
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: operation,
            targets: operation == "workspaces.create" ? [] : [target],
            expectedVersion: operation == "workspaces.create" ? nil : version,
            parameters: operation == "workspaces.create" ? ["workspace": .object(["name": .string("New")])] : [:])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        for denied in [scoped, readOnly] {
            #expect(try f.response("mutations.prepare", session: denied, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        }
        let prepared = try f.preparedMutation(intent, session: session)
        f.library.beforeBatchCommit = { throw AgentErrorCode.storageError }
        #expect(try f.send(prepared, session: session).outcome == .error(.storageError))
        #expect(f.library.workspaces == [source])
        f.library.beforeBatchCommit = nil
        let reply = try f.send(prepared, session: session)
        guard case .result = reply.outcome else { Issue.record("Retry failed: \(reply.outcome)"); return }
        #expect(f.library.workspaces.count == 2)
        _ = try f.connections.revokeFromUserInterface(record.id)
        #expect(try f.send(prepared, session: session).outcome == .error(.permissionDenied))
        #expect(f.library.workspaces.count == 2)
    }

    @Test(arguments: ["workspaces.create", "workspaces.duplicate"], ["revoke", "expire", "lock"])
    func workspaceCreationChecksAuthorityAgainBeforeCommit(_ operation: String, _ interruption: String) throws {
        let f = try Fixture(), source = Workspace(name: "Source")
        try f.library.saveWorkspace(source)
        let target = AgentResourceReference(kind: .workspace, id: source.id)
        let (record, session) = try f.connect(capabilities: [.workspacesRead, .workspacesManage])
        guard case .string(let version) = try f.values("workspaces.get", session: session, targets: [target])["versionToken"] else {
            throw AgentErrorCode.invalidInput
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: operation,
            targets: operation == "workspaces.create" ? [] : [target],
            expectedVersion: operation == "workspaces.create" ? nil : version,
            parameters: operation == "workspaces.create" ? ["workspace": .object(["name": .string("New")])] : [:])
        let prepared = try f.preparedMutation(intent, session: session)
        f.library.beforeBatchCommit = {
            switch interruption {
            case "revoke": _ = try f.connections.revokeFromUserInterface(record.id)
            case "expire": f.wall = record.expiresAt
            default: f.locked = true
            }
        }
        #expect(try f.send(prepared, session: session).outcome == .error(.permissionDenied))
        #expect(f.library.workspaces == [source])
        f.library.beforeBatchCommit = nil
        try f.library.reload()
        #expect(f.library.workspaces == [source])
    }

    @Test func workspaceCreationCannotOverwriteAnExistingIdentityOrSaveBlankNames() throws {
        let f = try Fixture(), source = Workspace(name: "Preserve me")
        try f.library.saveWorkspace(source)
        let (_, session) = try f.connect(capabilities: [.workspacesManage])
        for (definition, error) in [
            (["id": AgentJSONValue.string(source.id.uuidString), "name": .string("Overwrite")], AgentErrorCode.versionConflict),
            (["name": .string(" \n ")], AgentErrorCode.invalidInput)
        ] {
            let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.create",
                parameters: ["workspace": .object(definition)])
            let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
            #expect(try f.response("mutations.prepare", session: session, parameters: ["request": frame]).outcome == .error(error))
        }
        #expect(f.library.workspaces == [source])
    }

    @Test func workspaceOrderUsesACompleteSnapshotAndRecoversItsReceipt() throws {
        let f = try Fixture()
        let original = [Workspace(name: "A café 🐼"), Workspace(name: "B"), Workspace(name: "C")]
        try f.library.saveWorkspaces(original)
        let (record, session) = try f.connect(capabilities: [.workspacesRead, .workspacesManage])
        let listed = try f.values("workspaces.list", session: session)
        guard case .string(let version) = listed["orderVersion"] else { throw AgentErrorCode.invalidInput }
        let order = original.reversed().map(\.id)
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.reorder",
            targets: original.map { .init(kind: .workspace, id: $0.id) }, expectedVersion: version,
            parameters: ["order": .array(order.map { .string($0.uuidString) })])
        let prepared = try f.preparedMutation(intent, session: session)
        #expect(f.library.workspaces == original)
        f.library.beforeBatchCommit = { throw AgentErrorCode.storageError }
        #expect(try f.send(prepared, session: session).outcome == .error(.storageError))
        #expect(f.library.workspaces == original)
        f.library.beforeBatchCommit = nil
        let reply = try f.send(prepared, session: session)
        guard case .result(.object(let result)) = reply.outcome, case .array(let resources) = result["resources"] else {
            Issue.record("Missing order receipt: \(reply.outcome)"); return
        }
        #expect(f.library.workspaces.map(\.id) == order)
        #expect(f.library.workspaces.map(\.order) == [0, 1, 2])
        #expect(resources.compactMap { value -> String? in
            guard case .object(let fields) = value, case .string(let id) = fields["id"] else { return nil }; return id
        } == order.map(\.uuidString))
        #expect(try f.send(prepared, session: session) == reply)
        f.service = try f.makeService()
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let recovered = try f.preparedMutation(intent, session: reopened)
        #expect(try f.send(recovered, session: reopened) == reply)
        #expect(f.library.workspaces.map(\.id) == order)
    }

    @Test func workspaceOrderRejectsMissingMembersAndChangedSnapshots() throws {
        let f = try Fixture(), a = Workspace(name: "A"), b = Workspace(name: "B")
        try f.library.saveWorkspaces([a, b])
        let (_, session) = try f.connect(capabilities: [.workspacesRead, .workspacesManage])
        guard case .string(let version) = try f.values("workspaces.list", session: session)["orderVersion"] else {
            throw AgentErrorCode.invalidInput
        }
        let target = AgentResourceReference(kind: .workspace, id: a.id)
        let incomplete = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.reorder",
            targets: [target], expectedVersion: version, parameters: ["order": .array([.string(a.id.uuidString)])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(incomplete))
        #expect(try f.response("mutations.prepare", session: session, parameters: ["request": frame]).outcome == .error(.versionConflict))
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.reorder",
            targets: [target, .init(kind: .workspace, id: b.id)], expectedVersion: version,
            parameters: ["order": .array([.string(b.id.uuidString), .string(a.id.uuidString)])])
        let prepared = try f.preparedMutation(intent, session: session)
        var changed = b; changed.query = "Changed elsewhere"
        try f.library.saveWorkspace(changed)
        #expect(try f.send(prepared, session: session).outcome == .error(.versionConflict))
        #expect(f.library.workspaces == [a, changed])
    }

    @Test func workspaceOrderSnapshotIsPrivateToLibraryScopeAndInvalidatesPaging() throws {
        let f = try Fixture(), a = Workspace(name: "A"), b = Workspace(name: "B")
        try f.library.saveWorkspaces([a, b])
        let (_, session) = try f.connect(capabilities: [.workspacesRead, .workspacesManage])
        let target = AgentResourceReference(kind: .workspace, id: a.id)
        let (_, scoped) = try f.connect(scope: .resources([target]), capabilities: [.workspacesRead, .workspacesManage])
        #expect(try f.values("workspaces.list", session: scoped)["orderVersion"] == nil)
        let page = try f.values("workspaces.list", session: session, parameters: ["limit": .integer(1)])
        guard let cursor = page["nextCursor"], case .string(let version) = page["orderVersion"] else { throw AgentErrorCode.invalidInput }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.reorder",
            targets: [target], expectedVersion: version, parameters: ["order": .array([.string(a.id.uuidString)])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: scoped, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        try f.library.saveWorkspace(Workspace(name: "New member"))
        #expect(try f.response("workspaces.list", session: session, parameters: ["cursor": cursor]).outcome == .error(.versionConflict))
    }

    @Test func workspaceApplicationUsesNativeRulesWithoutEditingDraftsAndDoesNotReplay() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Stored café 🐼")
        let dirty = "Unsaved café 🐼 e\u{301}"
        let model = try f.window(note, content: dirty, dirty: true)
        model.editor.selection = NSRange(location: 2, length: 3)
        f.editors = [model]
        let windowID = try #require(f.editorRegistry.windowSnapshots().first?.id)
        var workspace = Workspace(name: "Apply café 🐼")
        workspace.query = "café"; workspace.tags = ["one"]; workspace.excludedTags = ["two"]
        workspace.folder = .all; workspace.sort = .title; workspace.ascending = true
        workspace.matchAnyTag = true; workspace.tagged = true
        try f.library.saveWorkspace(workspace)
        let target = AgentResourceReference(kind: .workspace, id: workspace.id)
        let window = AgentResourceReference(kind: .window, id: windowID)
        let (record, session) = try f.connect(scope: .resources([target, window]),
            capabilities: [.workspacesRead, .workspacesApply, .presentUI])
        guard case .string(let version) = try f.values("workspaces.get", session: session, targets: [target])["versionToken"] else {
            throw AgentErrorCode.invalidInput
        }
        let schemas = try f.values("server.schemas", session: session)
        guard case .array(let operations) = schemas["operations"] else { throw AgentErrorCode.invalidInput }
        #expect(operations.contains { value in
            guard case .object(let fields) = value else { return false }
            return fields["name"] == .string("mutations.prepare") && fields["available"] == .bool(true)
        })
        let tools = try AgentAvailableTools(capabilities: f.values("server.capabilities", session: session), schemas: schemas)
        #expect(tools.inputs["workspaces.apply"] != nil && tools.inputs["mutations.prepare"] != nil)
        #expect(tools.inputs["editor.get"] == nil && tools.inputs["drafts.get"] == nil)
        let before = try f.library.backupData()
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.apply",
            targets: [window, target], expectedVersion: version)
        let prepared = try f.preparedMutation(intent, session: session)
        #expect(model.selectedWorkspace == nil)
        let result = try f.send(prepared, session: session)
        #expect(result.outcome == .result(.object(["workspaceID": .string(workspace.id.uuidString), "windowID": .string(windowID.uuidString)])))
        #expect(model.selectedWorkspace == workspace.id && model.query == workspace.query)
        #expect(model.folder == .all && model.sort == .title && model.ascending)
        #expect(model.activeTagFilters == ["one"] && model.excludedTagFilters == ["two"] && model.tagPresence == true)
        #expect(model.editor.noteID == note.id && model.editor.content.utf8.elementsEqual(dirty.utf8))
        #expect(model.editor.selection == NSRange(location: 2, length: 3) && model.hasUnsavedChanges)
        #expect(try f.library.backupData() == before)
        #expect(try f.response("editor.get", session: session, targets: [window]).outcome == .error(.permissionDenied))
        #expect(try f.response("drafts.get", session: session, targets: [.init(kind: .draft, id: note.id)]).outcome == .error(.permissionDenied))
        model.query = "User changed this later"
        #expect(try f.send(prepared, session: session) == result)
        #expect(model.query == "User changed this later")
        let recovered = try f.preparedMutation(intent, session: session)
        #expect(try f.send(recovered, session: session) == result && model.query == "User changed this later")
        _ = try f.connections.revokeFromUserInterface(record.id)
        #expect(try f.send(recovered, session: session).outcome == .error(.permissionDenied))
    }

    @Test func workspaceApplicationRequiresBothResourcesAndCapabilitiesAndRejectsStaleOrClosedTargets() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Neutral"), model = try f.window(note)
        f.editors = [model]
        let windowID = try #require(f.editorRegistry.windowSnapshots().first?.id)
        let workspace = Workspace(name: "Target")
        try f.library.saveWorkspace(workspace)
        let target = AgentResourceReference(kind: .workspace, id: workspace.id), window = AgentResourceReference(kind: .window, id: windowID)
        let (_, session) = try f.connect(scope: .resources([target, window]), capabilities: [.workspacesRead, .workspacesApply, .presentUI])
        guard case .string(let version) = try f.values("workspaces.get", session: session, targets: [target])["versionToken"] else {
            throw AgentErrorCode.invalidInput
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.apply", targets: [target, window], expectedVersion: version)
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        for (scope, caps, error) in [
            (AgentResourceScope.resources([target]), Set<AgentCapability>([.workspacesApply, .presentUI]), AgentErrorCode.notFound),
            (.resources([window]), [.workspacesApply, .presentUI], .notFound),
            (.resources([target, window]), [.workspacesApply], .permissionDenied),
            (.resources([target, window]), [.presentUI], .permissionDenied)
        ] {
            let (_, denied) = try f.connect(scope: scope, capabilities: caps)
            #expect(try f.response("mutations.prepare", session: denied, parameters: ["request": frame]).outcome == .error(error))
        }
        let prepared = try f.preparedMutation(intent, session: session)
        var changed = workspace; changed.query = "Changed after prepare"
        try f.library.saveWorkspace(changed)
        #expect(try f.send(prepared, session: session).outcome == .error(.versionConflict))
        try f.library.saveWorkspace(workspace)
        f.editors = []
        #expect(try f.send(prepared, session: session).outcome == .error(.notFound))
        #expect(model.selectedWorkspace == nil)
    }

    @Test func workspaceApplicationDoesNotCancelRunningActions() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Neutral"), model = try f.window(note)
        f.editors = [model]
        let windowID = try #require(f.editorRegistry.windowSnapshots().first?.id)
        let workspace = Workspace(name: "Target")
        try f.library.saveWorkspace(workspace)
        let target = AgentResourceReference(kind: .workspace, id: workspace.id)
        let (_, session) = try f.connect(capabilities: [.workspacesRead, .workspacesApply, .presentUI])
        guard case .string(let version) = try f.values("workspaces.get", session: session, targets: [target])["versionToken"] else {
            throw AgentErrorCode.invalidInput
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.apply",
            targets: [target, .init(kind: .window, id: windowID)], expectedVersion: version)
        let prepared = try f.preparedMutation(intent, session: session)
        model.actionPending = true
        #expect(try f.send(prepared, session: session).outcome == .error(.busy))
        #expect(model.actionPending && model.selectedWorkspace == nil)
        model.actionPending = false
        guard case .result = try f.send(prepared, session: session).outcome else { Issue.record("Apply did not resume"); return }
        #expect(model.selectedWorkspace == workspace.id)
    }

    @Test(arguments: [false, true])
    func failedWorkspacePresentationCanRetryButAnUncertainApplicationCannotReplay(_ suspendSession: Bool) throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Neutral"), model = try f.window(note)
        f.editors = [model]
        let windowID = try #require(f.editorRegistry.windowSnapshots().first?.id)
        var workspace = Workspace(name: "Target")
        workspace.query = "New query"
        workspace.scriptMetadata = ["api": #"{"loadActionListGroup":{"name":"Missing group"}}"#]
        try f.library.saveWorkspace(workspace)
        let target = AgentResourceReference(kind: .workspace, id: workspace.id), window = AgentResourceReference(kind: .window, id: windowID)
        let (record, session) = try f.connect(scope: .resources([target, window]), capabilities: [.workspacesRead, .workspacesApply, .presentUI])
        guard case .string(let version) = try f.values("workspaces.get", session: session, targets: [target])["versionToken"] else {
            throw AgentErrorCode.invalidInput
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.apply", targets: [target, window], expectedVersion: version)
        let prepared = try f.preparedMutation(intent, session: session)
        #expect(try f.send(prepared, session: session).outcome == .error(.invalidInput))
        #expect(model.selectedWorkspace == nil && model.query.isEmpty)
        try f.library.saveActionGroup(ActionGroupRecord(name: "Missing group"))
        let changed = model.$query.dropFirst().sink { _ in
            if suspendSession { f.service.invalidateAll() }
            else { f.editors = [] }
        }
        #expect(try f.send(prepared, session: session).outcome == .error(.outcomeUnknown))
        changed.cancel()
        #expect(model.query == workspace.query)
        f.editors = [model]
        model.query = "User changed the view"
        let resumed = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        #expect(try f.send(prepared, session: resumed).outcome == .error(.outcomeUnknown))
        #expect(model.query == "User changed the view")
    }

    @Test func workspaceApplicationSupportsAnEmptyWindowWithoutDraftAccess() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: try #require(UserDefaults(suiteName: f.editorDefaultsName)))
        let model = WindowModel(library: f.library, dependencies: dependencies)
        f.editors = [model]
        let windowID = try #require(f.editorRegistry.windowSnapshots().first?.id)
        let workspace = Workspace(name: "Empty window")
        try f.library.saveWorkspace(workspace)
        let target = AgentResourceReference(kind: .workspace, id: workspace.id), window = AgentResourceReference(kind: .window, id: windowID)
        let (_, session) = try f.connect(scope: .resources([target, window]), capabilities: [.workspacesRead, .workspacesApply, .presentUI])
        guard case .string(let version) = try f.values("workspaces.get", session: session, targets: [target])["versionToken"] else {
            throw AgentErrorCode.invalidInput
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.apply", targets: [target, window], expectedVersion: version)
        let prepared = try f.preparedMutation(intent, session: session)
        let result = try f.send(prepared, session: session)
        guard case .result = result.outcome else { Issue.record("Empty window apply failed: \(result.outcome)"); return }
        #expect(model.selectedWorkspace == workspace.id && model.editor.noteID == nil && model.editor.content.isEmpty)
        #expect(f.library.notes.isEmpty)
    }

    @Test func workspaceUpdateRespectsScopeConflictsAndRecovers() throws {
        let f = try Fixture(), original = Workspace(name: "Original")
        try f.library.saveWorkspace(original)
        let target = AgentResourceReference(kind: .workspace, id: original.id)
        let (record, session) = try f.connect(scope: .resources([target]), capabilities: [.workspacesRead, .workspacesManage])
        let (_, denied) = try f.connect(scope: .resources([]), capabilities: [.workspacesManage])
        guard case .string(let version) = try f.values("workspaces.get", session: session, targets: [target])["versionToken"] else {
            Issue.record("Missing version"); return
        }
        var changed = original; changed.name = "Updated"
        let definition = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(changed))
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.update", targets: [target],
                                  expectedVersion: version, parameters: ["workspace": definition])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: denied, parameters: ["request": frame]).outcome == .error(.notFound))
        var reordered = changed; reordered.order = 99
        let reorderedDefinition = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(reordered))
        let reorderedIntent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "workspaces.update", targets: [target],
                                           expectedVersion: version, parameters: ["workspace": reorderedDefinition])
        let reorderedFrame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(reorderedIntent))
        #expect(try f.response("mutations.prepare", session: session, parameters: ["request": reorderedFrame]).outcome == .error(.invalidInput))
        let prepared = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        func signed(_ key: String) -> AgentRequest {
            AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
                         targets: intent.targets, expectedVersion: version, retryKey: key, parameters: intent.parameters)
        }
        func send(_ key: String, _ session: AgentCommandService.Session) throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed(key)), session: session))
        }
        var concurrent = original; concurrent.query = "Concurrent"
        try f.library.saveWorkspace(concurrent)
        #expect(try send(key, session).outcome == .error(.versionConflict))
        #expect(f.library.workspaces == [concurrent])
        try f.library.saveWorkspace(original)
        let reply = try send(key, session)
        guard case .result = reply.outcome else { Issue.record("Update failed: \(reply.outcome)"); return }
        #expect(f.library.workspaces == [changed])
        #expect(try send(key, session) == reply)
        f.service = try f.makeService()
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let recovered = try f.values("mutations.prepare", session: reopened, parameters: ["request": frame])
        guard case .string(let recoveredKey) = recovered["retryKey"] else { Issue.record("Missing recovery key"); return }
        #expect(try send(recoveredKey, reopened) == reply)
        _ = try f.connections.revokeFromUserInterface(record.id)
        #expect(try send(recoveredKey, reopened).outcome == .error(.permissionDenied))
    }

    @Test func workspaceQueryOnlyReturnsAuthorizedDrafts() throws {
        let f = try Fixture()
        let visible = try f.library.createNote(content: "Neutral visible")
        _ = try f.library.createNote(content: "Neutral hidden")
        let outsideQuery = try f.library.createNote(content: "Unrelated")
        var workspace = Workspace(name: "Neutral workspace"); workspace.query = "Neutral"
        try f.library.saveWorkspace(workspace)
        let target = AgentResourceReference(kind: .workspace, id: workspace.id)
        let scope: Set<AgentResourceReference> = [target, .init(kind: .draft, id: visible.id), .init(kind: .draft, id: outsideQuery.id)]
        let (_, session) = try f.connect(scope: .resources(scope), capabilities: [.workspacesRead, .draftsRead])
        let (_, noDraftRead) = try f.connect(scope: .resources(scope), capabilities: [.workspacesRead])
        let page = try f.values("workspaces.query", session: session, targets: [target])
        guard case .array(let items) = page["items"], case .object(let item) = items.first else { Issue.record("Missing draft"); return }
        #expect(items.count == 1 && item["id"] == .string(visible.id.uuidString))
        #expect(try f.response("workspaces.query", session: noDraftRead, targets: [target]).outcome == .error(.permissionDenied))
    }

    @Test func workspaceReadsRespectScopeAndReportChanges() throws {
        let f = try Fixture()
        var visible = Workspace(name: "Visible"); visible.query = "neutral"
        let hidden = Workspace(name: "Hidden")
        try f.library.saveWorkspaces([visible, hidden])
        let target = AgentResourceReference(kind: .workspace, id: visible.id)
        let (_, session) = try f.connect(scope: .resources([target]), capabilities: [.workspacesRead])
        let (_, denied) = try f.connect(capabilities: [.draftsRead])
        #expect(try f.response("workspaces.list", session: denied).outcome == .error(.permissionDenied))
        let list = try f.values("workspaces.list", session: session)
        guard case .array(let items) = list["items"], case .object(let summary) = items.first else { Issue.record("Missing workspace"); return }
        #expect(items.count == 1 && summary["id"] == .string(visible.id.uuidString))
        let detail = try f.values("workspaces.get", session: session, targets: [target])
        #expect(detail["versionToken"] == summary["versionToken"])
        #expect(try f.response("workspaces.get", session: session, targets: [.init(kind: .workspace, id: hidden.id)]).outcome == .error(.notFound))
        visible.query = "changed"; try f.library.saveWorkspace(visible)
        #expect(try f.values("workspaces.get", session: session, targets: [target])["versionToken"] != detail["versionToken"])
    }

    @Test func stepSchemasRequireActionReadAndMatchEditorCreationDefaults() throws {
        let f = try Fixture()
        let (_, session) = try f.connect(capabilities: [.actionsRead])
        let (_, denied) = try f.connect(capabilities: [.draftsRead])
        #expect(try f.response("actions.stepSchemas", session: denied).outcome == .error(.permissionDenied))
        let result = try f.values("actions.stepSchemas", session: session)
        guard case .array(let steps) = result["steps"] else { Issue.record("Missing step schemas"); return }
        let expected: [AgentJSONValue] = DraftAction.supportedSteps.sorted().map { type in
            .object(["type": .string(type), "creationDefaults": .object(
                ActionStepCreationDefaults.values(for: type).mapValues { .string($0) })])
        }
        #expect(steps == expected)
    }

    @Test func duplicateGroupRequiresFullScopeAndRecoversWithoutDuplicates() throws {
        let f = try Fixture()
        var action = DraftAction(name: "Original", steps: []); action.group = "Source"; action.shortcut = "k"
        try f.library.saveAction(action)
        let target = AgentResourceReference(kind: .actionGroup, id: try #require(f.library.actionGroupIdentifiers["Source"]))
        let (connection, session) = try f.connect(capabilities: [.actionsRead, .actionsManage])
        let (_, limited) = try f.connect(scope: .resources([target]), capabilities: [.actionsManage])
        let detail = try f.values("actionGroups.get", session: session, targets: [target])
        guard case .string(let version) = detail["versionToken"] else { Issue.record("Missing version"); return }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actionGroups.duplicate", targets: [target], expectedVersion: version)
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: limited, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        let prepared = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        let signed = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
                                  targets: intent.targets, expectedVersion: version, retryKey: key)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed), session: session))
        }
        let originalGroup = f.library.actionGroupRecord(named: "Source")
        var changedGroup = originalGroup; changedGroup.symbol = "star"
        try f.library.saveActionGroup(changedGroup)
        #expect(try send().outcome == .error(.versionConflict))
        #expect(f.library.actions == [action])
        try f.library.saveActionGroup(originalGroup)
        let result = try send()
        guard case .result = result.outcome else { Issue.record("Copy failed: \(result.outcome)"); return }
        #expect(try send() == result)
        let copies = f.library.actions.filter { $0.group == "Source Copy" }
        #expect(copies.count == 1 && copies[0].id != action.id && copies[0].shortcut.isEmpty)
        #expect(f.library.actions.contains(action))
        _ = try f.connections.revokeFromUserInterface(connection.id)
        #expect(try send().outcome == .error(.permissionDenied))
        #expect(f.library.actions.filter { $0.group == "Source Copy" }.count == 1)
    }

    @Test func renameGroupMovesActionsAtomicallyAndRecovers() throws {
        let f = try Fixture()
        var first = DraftAction(name: "First", steps: []); first.group = "Original"
        var second = DraftAction(name: "Second", steps: []); second.group = "Original"
        var untouched = DraftAction(name: "Other", steps: []); untouched.group = "Other"
        try f.library.saveActions([first, second, untouched])
        let groupID = try #require(f.library.actionGroupIdentifiers["Original"])
        let otherID = try #require(f.library.actionGroupIdentifiers["Other"])
        let target = AgentResourceReference(kind: .actionGroup, id: groupID)
        let (_, session) = try f.connect(capabilities: [.actionsRead, .actionsManage])
        let (_, limited) = try f.connect(scope: .resources([target]), capabilities: [.actionsManage])
        let detail = try f.values("actionGroups.get", session: session, targets: [target])
        guard case .string(let version) = detail["versionToken"], case .object(var group) = detail["group"] else {
            Issue.record("Missing group details"); return
        }
        group["name"] = .string("Renamed 🐼")
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actionGroups.update", targets: [target],
                                  expectedVersion: version, parameters: ["group": .object(group)])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: limited, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        let prepared = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        let signed = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
                                  targets: intent.targets, expectedVersion: version, retryKey: key, parameters: intent.parameters)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed), session: session))
        }
        let response = try send()
        guard case .result(.object(let result)) = response.outcome,
              case .object(let receipt) = result["resource"] else { Issue.record("Rename failed: \(response.outcome)"); return }
        let movedIDs = Set(f.library.actions.filter { $0.group == "Renamed 🐼" }.map(\.id))
        #expect(movedIDs == Set([first.id, second.id]))
        #expect(f.library.actionGroupIdentifiers["Renamed 🐼"] == groupID && f.library.actionGroupIdentifiers["Other"] == otherID)
        #expect(f.library.actions.contains(untouched))
        #expect(try f.values("actionGroups.get", session: session, targets: [target])["versionToken"] == receipt["versionToken"])
        #expect(try send() == response)
    }

    @Test func createGroupPreservesExistingIdentifiersAndRecoversWithoutDuplicates() throws {
        let f = try Fixture()
        var action = DraftAction(name: "Existing", steps: []); action.group = "Implicit"
        try f.library.saveAction(action)
        let existing = try #require(f.library.actionGroupIdentifiers["Implicit"])
        let (record, session) = try f.connect(capabilities: [.actionsRead, .actionsManage])
        let (_, limited) = try f.connect(scope: .resources([]), capabilities: [.actionsManage])
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actionGroups.create",
            parameters: ["group": .object(["name": .string("  QA Group 🐼  ")])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: limited, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        let prepared = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        func send(_ key: String, _ session: AgentCommandService.Session) throws -> AgentResponse {
            let request = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
                                       retryKey: key, parameters: intent.parameters)
            return try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        var concurrent = ActionGroupRecord(name: "QA Group 🐼"); concurrent.id = UUID()
        try f.library.saveActionGroup(concurrent)
        #expect(try send(key, session).outcome == .error(.versionConflict))
        #expect(f.library.actionGroups.filter { $0.name == concurrent.name }.count == 1)
        try f.library.removeActionGroup(concurrent.name, movingActionsTo: "Implicit")
        let response = try send(key, session)
        guard case .result = response.outcome else { Issue.record("Create group failed: \(response.outcome)"); return }
        #expect(f.library.groupNames.filter { $0 == "QA Group 🐼" }.count == 1)
        #expect(f.library.actionGroupIdentifiers["Implicit"] == existing)
        #expect(try send(key, session) == response)
        f.service = try f.makeService()
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let retry = try f.values("mutations.prepare", session: reopened, parameters: ["request": frame])
        guard case .string(let retryKey) = retry["retryKey"] else { Issue.record("Missing recovery key"); return }
        #expect(try send(retryKey, reopened) == response)
        #expect(f.library.groupNames.filter { $0 == "QA Group 🐼" }.count == 1)
        let collision = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actionGroups.create",
            parameters: ["group": .object(["id": .string(existing.uuidString), "name": .string("Collision")])])
        let collisionFrame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(collision))
        #expect(try f.response("mutations.prepare", session: reopened, parameters: ["request": collisionFrame]).outcome == .error(.versionConflict))
        #expect(f.library.actionGroupIdentifiers["Implicit"] == existing)
    }

    @Test func duplicateActionRequiresLibraryScopeAndDoesNotRepeatOnRecovery() throws {
        let f = try Fixture()
        var source = DraftAction(name: "Original", steps: [ActionStep("clipboard", ["template": "neutral"])])
        source.shortcut = "q"
        try f.library.saveAction(source)
        let target = AgentResourceReference(kind: .action, id: source.id)
        let (record, full) = try f.connect(capabilities: [.actionsRead, .actionsManage])
        let (_, limited) = try f.connect(scope: .resources([target]), capabilities: [.actionsManage])
        guard case .string(let version) = try f.values("actions.get", session: full, targets: [target])["versionToken"] else {
            Issue.record("Missing version"); return
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actions.duplicate", targets: [target], expectedVersion: version)
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: limited, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        let prepared = try f.values("mutations.prepare", session: full, parameters: ["request": frame])
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        func send(_ key: String, _ session: AgentCommandService.Session) throws -> AgentResponse {
            let request = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
                                       targets: intent.targets, expectedVersion: version, retryKey: key)
            return try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        var concurrent = source; concurrent.name = "Concurrent edit"
        try f.library.saveAction(concurrent)
        #expect(try send(key, full).outcome == .error(.versionConflict))
        #expect(f.library.actions == [concurrent])
        try f.library.saveAction(source)
        let response = try send(key, full)
        guard case .result = response.outcome else { Issue.record("Duplicate failed: \(response.outcome)"); return }
        let copy = try #require(f.library.actions.first(where: { $0.id != source.id }))
        #expect(copy.name == "Original Copy" && copy.steps == source.steps && copy.shortcut.isEmpty)
        #expect(try send(key, full) == response)
        f.service = try f.makeService()
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let retry = try f.values("mutations.prepare", session: reopened, parameters: ["request": frame])
        guard case .string(let retryKey) = retry["retryKey"] else { Issue.record("Missing recovery key"); return }
        #expect(try send(retryKey, reopened) == response)
        #expect(f.library.actions.count == 2)
        _ = try f.connections.revokeFromUserInterface(record.id)
        #expect(try send(retryKey, reopened).outcome == .error(.permissionDenied))
    }

    @Test func moveActionRequiresBothResourcesAndRecoversTheResult() throws {
        let f = try Fixture()
        var action = DraftAction(name: "Move", steps: []); action.group = "Source"
        var other = DraftAction(name: "Destination marker", steps: []); other.group = "Destination"
        try f.library.saveActions([action, other])
        let groupID = try #require(f.library.actionGroupIdentifiers["Destination"])
        let actionRef = AgentResourceReference(kind: .action, id: action.id)
        let groupRef = AgentResourceReference(kind: .actionGroup, id: groupID)
        let (_, session) = try f.connect(scope: .resources([actionRef, groupRef]), capabilities: [.actionsRead, .actionsManage])
        let (_, limited) = try f.connect(scope: .resources([actionRef]), capabilities: [.actionsManage])
        guard case .string(let version) = try f.values("actions.get", session: session, targets: [actionRef])["versionToken"] else {
            Issue.record("Missing version"); return
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actions.move",
                                  targets: [groupRef, actionRef], expectedVersion: version)
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: limited, parameters: ["request": frame]).outcome == .error(.notFound))
        let prepared = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        #expect(f.library.actions.first(where: { $0.id == action.id })?.group == "Source")
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        let signed = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
                                  targets: intent.targets, expectedVersion: version, retryKey: key)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed), session: session))
        }
        let reply = try send()
        guard case .result = reply.outcome else { Issue.record("Move failed: \(reply.outcome)"); return }
        #expect(f.library.actions.first(where: { $0.id == action.id })?.group == "Destination")
        #expect(try send() == reply)
        #expect(f.library.actions.count == 2)
    }

    @Test func preferenceServicePreparesWritesResetsAndRecoversWithoutReapplying() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        try f.enablePreferenceWrites()
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        let (_, session) = try f.connect(scope: .resources([]), capabilities: [.preferencesRead, .preferencesWrite])
        let params: [String: AgentJSONValue] = ["items": .array([.object(["id": .string("editor.fontSize")])])]
        guard case .string(let version) = try f.values("preferences.get", session: session, parameters: params)["versionToken"] else {
            Issue.record("Missing version"); return
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "preferences.update", expectedVersion: version,
            parameters: ["items": .array([.object(["id": .string("editor.fontSize"), "value": .integer(23)])])])
        let signed = try f.preparedMutation(intent, session: session)
        #expect(defaults.object(forKey: "editor.fontSize") == nil)
        let first = try f.send(signed, session: session)
        guard case .result = first.outcome else { Issue.record("Preference write failed: \(first.outcome)"); return }
        #expect(defaults.double(forKey: "editor.fontSize") == 23)
        defaults.set(31, forKey: "editor.fontSize")
        #expect(try f.send(signed, session: session) == first && defaults.double(forKey: "editor.fontSize") == 31)
        guard case .string(let current) = try f.values("preferences.get", session: session, parameters: params)["versionToken"] else {
            Issue.record("Missing updated version"); return
        }
        let reset = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "preferences.reset", expectedVersion: current, parameters: params)
        let preparedReset = try f.preparedMutation(reset, session: session)
        let restored = try f.send(preparedReset, session: session)
        guard case .result = restored.outcome else { Issue.record("Preference reset failed"); return }
        #expect(defaults.object(forKey: "editor.fontSize") == nil)
        let schemas = try f.values("server.schemas", session: session,
            parameters: ["operations": .array(["preferences.update", "preferences.reset", "mutations.prepare"].map(AgentJSONValue.string))])
        guard case .array(let operations) = schemas["operations"] else { Issue.record("Missing schemas"); return }
        #expect(operations.allSatisfy { if case .object(let value) = $0 { return value["available"] == .bool(true) }; return false })
    }

    @Test func preferenceWritesDoNotRequireAnEditorRegistry() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        try f.enablePreferenceWrites()
        f.service = try f.makeService(withoutEditors: true)
        let (_, session) = try f.connect(capabilities: [.preferencesRead, .preferencesWrite])
        let params: [String: AgentJSONValue] = ["items": .array([.object(["id": .string("editor.fontSize")])])]
        let values = try f.values("preferences.get", session: session, parameters: params)
        guard case .string(let version) = values["versionToken"] else { Issue.record("Missing version"); return }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "preferences.update", expectedVersion: version,
            parameters: ["items": .array([.object(["id": .string("editor.fontSize"), "value": .integer(24)])])])
        let signed = try f.preparedMutation(request, session: session)
        let response = try f.send(signed, session: session)
        guard case .result = response.outcome else { Issue.record("Preference write needs an editor"); return }
        #expect(UserDefaults(suiteName: f.editorDefaultsName)?.double(forKey: "editor.fontSize") == 24)
    }

    @Test func preferencePreparationCannotOverwriteChangedSharedStorage() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        try f.enablePreferenceWrites()
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        let (_, session) = try f.connect(capabilities: [.preferencesRead, .preferencesWrite])
        let address = AgentJSONValue.object(["id": .string("markdown.multi.smartQuotesEnabled")])
        let reading = try f.values("preferences.get", session: session, parameters: ["items": .array([address])])
        guard case .string(let version) = reading["versionToken"] else { Issue.record("Missing version"); return }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "preferences.update", expectedVersion: version,
            parameters: ["items": .array([.object(["id": .string("markdown.multi.smartQuotesEnabled"), "value": .bool(false)])])])
        let signed = try f.preparedMutation(request, session: session)
        let changed = #"{"future":{"keep":"café 🐼"}}"#
        defaults.set(changed, forKey: MarkdownPreferences.multiKey)
        #expect(try f.send(signed, session: session).outcome == .error(.versionConflict))
        #expect(defaults.string(forKey: MarkdownPreferences.multiKey) == changed)
    }

    @Test func nativePreferenceMutationStopsBeforeStorageWithoutHumanReview() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        f.nativePreferenceRead = { _ in .init(effectiveValue: .bool(false), origin: "system", hasOverride: false) }
        try f.enablePreferenceWrites()
        let (_, session) = try f.connect(capabilities: [.preferencesRead, .preferencesWrite])
        let address = AgentJSONValue.object(["id": .string("application.launchAtLogin")])
        let reading = try f.values("preferences.get", session: session, parameters: ["items": .array([address])])
        guard case .string(let version) = reading["versionToken"] else { Issue.record("Missing version"); return }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "preferences.update", expectedVersion: version,
            parameters: ["interactive": .bool(true), "items": .array([.object(["id": .string("application.launchAtLogin"), "value": .bool(true)])])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(request))
        #expect(try f.response("mutations.prepare", session: session, parameters: ["request": frame]).outcome == .error(.unavailable))
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        #expect(defaults.object(forKey: "application.launchAtLogin") == nil)
    }

    @Test func spotlightPreferenceReadDoesNotChangeTheIndex() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        defaults.set(true, forKey: SpotlightPreferences.enabledKey)
        var effects = 0
        let model = SpotlightPreferences(defaults: defaults, isAvailable: true,
            replace: { _ in effects += 1 }, clear: { effects += 1 })
        f.nativePreferenceRead = { id in
            #expect(id == SpotlightPreferences.enabledKey)
            return try AgentNativePreferenceAccess.readSpotlight(model,
                hasStoredOverride: defaults.object(forKey: SpotlightPreferences.enabledKey) != nil)
        }
        f.service = try f.makeService()
        let (_, session) = try f.connect(capabilities: [.preferencesRead])
        let params: [String: AgentJSONValue] = ["items": .array([.object(["id": .string(SpotlightPreferences.enabledKey)])])]
        let values = try f.values("preferences.get", session: session, parameters: params)
        guard case .array(let items) = values["items"], case .object(let item) = items.first else {
            Issue.record("Missing Spotlight reading"); return
        }
        #expect(item["effectiveValue"] == .bool(true) && item["valueOrigin"] == .string("stored"))
        #expect(effects == 0 && defaults.bool(forKey: SpotlightPreferences.enabledKey))
    }

    @Test func nativePreferenceReadsUseTheSystemModelWithoutRegistration() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        var status = LoginItemPreferences.Status.disabled, changes = 0
        let model = LoginItemPreferences(readStatus: { status }, register: { changes += 1 }, unregister: { changes += 1 })
        var reads = 0
        f.nativePreferenceRead = { id in
            #expect(id == "application.launchAtLogin"); reads += 1
            return try AgentNativePreferenceAccess.readLoginItem(model)
        }
        f.service = try f.makeService()
        let params: [String: AgentJSONValue] = ["items": .array([.object(["id": .string("application.launchAtLogin")])])]
        let (_, denied) = try f.connect()
        #expect(try f.response("preferences.get", session: denied, parameters: params).outcome == .error(.permissionDenied))
        #expect(reads == 0)
        let (_, session) = try f.connect(capabilities: [.preferencesRead])
        for (state, enabled) in [(LoginItemPreferences.Status.disabled, false), (.enabled, true)] {
            status = state
            let values = try f.values("preferences.get", session: session, parameters: params)
            guard case .array(let items) = values["items"], case .object(let item) = items.first else {
                Issue.record("Missing native preference"); return
            }
            #expect(item["effectiveValue"] == .bool(enabled) && item["valueOrigin"] == .string("system"))
        }
        status = .requiresApproval
        #expect(try f.response("preferences.get", session: session, parameters: params).outcome == .error(.interactionRequired))
        status = .unavailable
        #expect(try f.response("preferences.get", session: session, parameters: params).outcome == .error(.unavailable))
        #expect(changes == 0)
    }

    @Test func syntaxPreferenceReadsRequireAppearanceAccessAndResolveInheritance() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        defaults.set(25, forKey: "editor.fontSize")
        let address = AgentJSONValue.object(["id": .string("syntax.fontSize"),
            "syntax": .object(["type": .string("builtIn"), "name": .string("Markdown")])])
        let params: [String: AgentJSONValue] = ["items": .array([address])]
        let (_, denied) = try f.connect(capabilities: [.preferencesRead])
        #expect(try f.response("preferences.get", session: denied, parameters: params).outcome == .error(.permissionDenied))
        let (_, allowed) = try f.connect(capabilities: [.preferencesRead, .appearanceRead])
        func reading() throws -> [String: AgentJSONValue] {
            let value = try f.values("preferences.get", session: allowed, parameters: params)
            guard case .array(let items) = value["items"], case .object(let item) = items.first else {
                throw AgentErrorCode.invalidInput
            }
            return item
        }
        #expect(try reading()["effectiveValue"] == .integer(25))
        #expect(try reading()["valueOrigin"] == .string("inherited"))
        defaults.set(#"{"Markdown":{"fontSize":19,"future":true}}"#, forKey: EditorSyntaxFontPreferences.key)
        #expect(try reading()["effectiveValue"] == .integer(19))
        #expect(try reading()["valueOrigin"] == .string("stored"))
        let system = AgentJSONValue.object(["id": .string("syntax.autocorrection"),
            "syntax": .object(["type": .string("builtIn"), "name": .string("Markdown")])])
        let systemValue = try f.values("preferences.get", session: allowed, parameters: ["items": .array([system])])
        guard case .array(let items) = systemValue["items"], case .object(let item) = items.first else {
            Issue.record("Missing system preference"); return
        }
        #expect(item["effectiveValue"] == .null && item["valueOrigin"] == .string("system"))
    }

    @Test func installedSyntaxPreferencesRequireTheirResourceScope() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        var source = try ScriptSyntax.definition("Markdown").object
        source["name"] = "Neutral syntax"
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: source))
        try f.library.saveSyntax(syntax)
        let address = AgentJSONValue.object(["id": .string("syntax.spelling"),
            "syntax": .object(["type": .string("installed"), "id": .string(syntax.id.uuidString)])])
        let params: [String: AgentJSONValue] = ["items": .array([address])]
        let (_, denied) = try f.connect(scope: .resources([]), capabilities: [.preferencesRead, .appearanceRead])
        #expect(try f.response("preferences.get", session: denied, parameters: params).outcome == .error(.notFound))
        let target = AgentResourceReference(kind: .syntax, id: syntax.id)
        let (_, allowed) = try f.connect(scope: .resources([target]), capabilities: [.preferencesRead, .appearanceRead])
        let result = try f.values("preferences.get", session: allowed, parameters: params)
        guard case .array(let items) = result["items"], case .object(let item) = items.first else {
            Issue.record("Missing installed syntax preference"); return
        }
        #expect(item["valueOrigin"] == .string("default"))
        #expect(AgentLibraryResourceChoices(library: f.library).resolve([target]) == [target])
    }

    @Test func encodedPreferenceReadsPreserveUnknownDataAndInvalidStores() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        let (_, session) = try f.connect(capabilities: [.preferencesRead])
        let config = #"{"smartQuotesEnabled":false,"future":{"keep":"🐼"}}"#
        defaults.set(config, forKey: MarkdownPreferences.multiKey)
        let address = AgentJSONValue.object(["id": .string("markdown.multi.smartQuotesEnabled")])
        func reading() throws -> [String: AgentJSONValue] {
            let values = try f.values("preferences.get", session: session, parameters: ["items": .array([address])])
            guard case .array(let items) = values["items"], case .object(let item) = items.first else {
                throw AgentErrorCode.invalidInput
            }
            return item
        }
        #expect(try reading()["effectiveValue"] == .bool(false))
        #expect(try reading()["valueOrigin"] == .string("stored"))
        #expect(defaults.string(forKey: MarkdownPreferences.multiKey) == config)
        defaults.set(7, forKey: MarkdownPreferences.multiKey)
        #expect(try reading()["valueOrigin"] == .string("invalid"))
        #expect(defaults.integer(forKey: MarkdownPreferences.multiKey) == 7)
        let shortcut = AgentJSONValue.object(["id": .string("commands.shortcut"), "command": .string("New Draft")])
        let value = try f.values("preferences.get", session: session, parameters: ["items": .array([shortcut])])
        guard case .array(let items) = value["items"], case .object(let item) = items.first else {
            Issue.record("Missing shortcut"); return
        }
        #expect(item["valueOrigin"] == .string("default") && item["hasOverride"] == .bool(false))
    }

    @Test func defaultWorkspacePreferenceCannotExposeAnUnscopedReference() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        let workspace = Workspace(name: "Allowed workspace")
        try f.library.saveWorkspace(workspace)
        defaults.set(workspace.id.uuidString, forKey: WorkspaceDefaults.key)
        let params: [String: AgentJSONValue] = ["items": .array([.object(["id": .string(WorkspaceDefaults.key)])])]
        let (_, noWorkspaceRead) = try f.connect(capabilities: [.preferencesRead])
        let (_, unscoped) = try f.connect(scope: .resources([]), capabilities: [.preferencesRead, .workspacesRead])
        for session in [noWorkspaceRead, unscoped] {
            #expect(try f.response("preferences.get", session: session, parameters: params).outcome == .error(.notFound))
        }
        let (_, allowed) = try f.connect(scope: .resources([.init(kind: .workspace, id: workspace.id)]),
            capabilities: [.preferencesRead, .workspacesRead])
        let result = try f.values("preferences.get", session: allowed, parameters: params)
        guard case .array(let items) = result["items"], case .object(let item) = items.first else {
            Issue.record("Missing workspace preference"); return
        }
        #expect(item["effectiveValue"] == .string(workspace.id.uuidString))
        #expect(item["valueOrigin"] == .string("stored"))
    }

    @Test func listPreferenceReadUsesDeviceDefaultsAndRejectsPartialBatches() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        defaults.set(false, forKey: "list.showPreview")
        let (_, session) = try f.connect(capabilities: [.preferencesRead])
        let address = AgentJSONValue.object(["id": .string("list.showPreview")])
        let values = try f.values("preferences.get", session: session, parameters: ["items": .array([address])])
        guard case .array(let items) = values["items"], case .object(let item) = items.first else {
            Issue.record("Missing list reading"); return
        }
        #expect(item["effectiveValue"] == .bool(false) && item["hasOverride"] == .bool(true))
        #expect(item["valueOrigin"] == .string("stored"))
        let unsupported = AgentJSONValue.object(["id": .string("application.launchAtLogin")])
        #expect(try f.response("preferences.get", session: session,
            parameters: ["items": .array([address, unsupported])]).outcome == .error(.unavailable))
        #expect(defaults.object(forKey: "application.launchAtLogin") == nil)
    }

    @Test func typedPreferenceReadsRequirePermissionAndTrackOverrides() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        let (_, denied) = try f.connect()
        let (_, allowed) = try f.connect(scope: .resources([]), capabilities: [.preferencesRead])
        let params: [String: AgentJSONValue] = ["items": .array([.object(["id": .string("editor.fontSize")])])]
        #expect(try f.response("preferences.get", session: denied, parameters: params).outcome == .error(.permissionDenied))
        let initial = try f.values("preferences.get", session: allowed, parameters: params)
        #expect(try f.values("preferences.get", session: allowed, parameters: params) == initial)
        defaults.set(23, forKey: "editor.fontSize")
        let changed = try f.values("preferences.get", session: allowed, parameters: params)
        #expect(initial["versionToken"] != changed["versionToken"])
        guard case .array(let items) = changed["items"], case .object(let item) = items.first else {
            Issue.record("Missing preference reading"); return
        }
        #expect(item["effectiveValue"] == .integer(23) && item["valueOrigin"] == .string("stored"))
        #expect(item["hasOverride"] == .bool(true))
        defaults.set("invalid", forKey: "editor.fontSize")
        let invalid = try f.values("preferences.get", session: allowed, parameters: params)
        guard case .array(let invalidItems) = invalid["items"], case .object(let invalidItem) = invalidItems.first else {
            Issue.record("Missing invalid reading"); return
        }
        #expect(invalidItem["effectiveValue"] == .null && invalidItem["valueOrigin"] == .string("invalid"))
        #expect(defaults.string(forKey: "editor.fontSize") == "invalid")
        let unsupported: [String: AgentJSONValue] = ["items": .array([.object(["id": .string("application.launchAtLogin")])])]
        #expect(try f.response("preferences.get", session: allowed, parameters: unsupported).outcome == .error(.unavailable))
        f.locked = true
        #expect(try f.response("preferences.get", session: allowed, parameters: params).outcome == .error(.permissionDenied))
    }

    @Test func createActionUsesDefaultsAndRecoversWithoutDuplicates() throws {
        let f = try Fixture()
        let (record, session) = try f.connect(capabilities: [.actionsManage])
        let (_, limited) = try f.connect(scope: .resources([]), capabilities: [.actionsManage])
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actions.create",
            parameters: ["action": .object(["name": .string("Created 🐼"), "steps": .array([.object(["type": .string("script")])])])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: limited, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        let prepared = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        #expect(f.library.actions.isEmpty)
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        func send(_ key: String, _ session: AgentCommandService.Session) throws -> AgentResponse {
            let signed = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
                                      retryKey: key, parameters: intent.parameters)
            return try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed), session: session))
        }
        let reply = try send(key, session)
        guard case .result = reply.outcome else { Issue.record("Create failed: \(reply.outcome)"); return }
        let action = try #require(f.library.actions.first)
        #expect(f.library.actions.count == 1 && action.name == "Created 🐼")
        #expect(action.steps.first?.values == ActionStepCreationDefaults.values(for: "script"))
        #expect(try send(key, session) == reply)
        f.service = try f.makeService()
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let recovered = try f.values("mutations.prepare", session: reopened, parameters: ["request": frame])
        guard case .string(let recoveryKey) = recovered["retryKey"] else { Issue.record("Missing recovery key"); return }
        #expect(try send(recoveryKey, reopened) == reply)
        #expect(f.library.actions == [action])
        let collision = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actions.create",
            parameters: ["action": .object(["id": .string(action.id.uuidString), "name": .string("Replacement"), "steps": .array([])])])
        let collisionFrame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(collision))
        #expect(try f.response("mutations.prepare", session: reopened, parameters: ["request": collisionFrame]).outcome == .error(.versionConflict))
        #expect(f.library.actions == [action])
    }

    @Test func actionUpdateRequiresScopeAndRecoversACommittedResult() throws {
        let f = try Fixture(), original = DraftAction(name: "Original", steps: [])
        try f.library.saveAction(original)
        let target = AgentResourceReference(kind: .action, id: original.id)
        let (record, session) = try f.connect(scope: .resources([target]), capabilities: [.actionsRead, .actionsManage])
        let (_, denied) = try f.connect(scope: .resources([]), capabilities: [.actionsManage])
        guard case .string(let version) = try f.values("actions.get", session: session, targets: [target])["versionToken"] else {
            Issue.record("Missing version"); return
        }
        var changed = original; changed.name = "Updated 🐼"
        let definition = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(changed))
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actions.update", targets: [target],
                                  expectedVersion: version, parameters: ["action": definition])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: denied, parameters: ["request": frame]).outcome == .error(.notFound))
        let prepared = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        #expect(f.library.actions == [original])
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        func signed(_ key: String) -> AgentRequest {
            AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
                         targets: intent.targets, expectedVersion: version, retryKey: key, parameters: intent.parameters)
        }
        func send(_ request: AgentRequest, _ session: AgentCommandService.Session) throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        var concurrent = original; concurrent.name = "Concurrent edit"
        try f.library.saveAction(concurrent)
        #expect(try send(signed(key), session).outcome == .error(.versionConflict))
        #expect(f.library.actions == [concurrent])
        try f.library.saveAction(original)
        let reply = try send(signed(key), session)
        guard case .result = reply.outcome else { Issue.record("Update failed: \(reply.outcome)"); return }
        #expect(f.library.actions == [changed])
        #expect(try send(signed(key), session) == reply)
        f.service = try f.makeService()
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let retry = try f.values("mutations.prepare", session: reopened, parameters: ["request": frame])
        guard case .string(let retryKey) = retry["retryKey"] else { Issue.record("Missing recovery key"); return }
        #expect(try send(signed(retryKey), reopened) == reply)
        #expect(f.library.actions == [changed])
        _ = try f.connections.revokeFromUserInterface(record.id)
        #expect(try send(signed(retryKey), reopened).outcome == .error(.permissionDenied))
    }

    @Test func shortcutValidationUsesEditorRulesAndRequiresLibraryScope() throws {
        let f = try Fixture()
        var action = DraftAction(name: "Existing", steps: []); action.shortcut = "q"
        try f.library.saveAction(action)
        let (_, full) = try f.connect(capabilities: [.actionsManage])
        let (_, limited) = try f.connect(scope: .resources([.init(kind: .action, id: action.id)]), capabilities: [.actionsManage])
        let parameters: [String: AgentJSONValue] = ["key": .string("q")]
        #expect(try f.response("actions.validateShortcut", session: limited, parameters: parameters).outcome == .error(.permissionDenied))
        #expect(try f.values("actions.validateShortcut", session: full, parameters: parameters)["available"] == .bool(false))
        #expect(try f.values("actions.validateShortcut", session: full, parameters: ["key": .string("q"), "actionID": .string(action.id.uuidString)])["available"] == .bool(true))
        #expect(try f.response("actions.validateShortcut", session: full, parameters: ["key": .string("q"), "actionID": .string(UUID().uuidString)]).outcome == .error(.notFound))
        #expect(try f.values("actions.validateShortcut", session: full, parameters: ["key": .string("abc")])["available"] == .bool(false))
        #expect(f.library.actions == [action])
    }

    @Test func shortcutValidationDoesNotRevealActionsOutsideScope() throws {
        let f = try Fixture(), action = DraftAction(name: "Allowed", steps: [])
        var hidden = DraftAction(name: "Hidden", steps: []); hidden.shortcut = "q"
        try f.library.saveActions([action, hidden])
        let target = AgentResourceReference(kind: .action, id: action.id)
        let (_, limited) = try f.connect(scope: .resources([target]), capabilities: [.actionsRead, .actionsManage])
        let (_, full) = try f.connect(capabilities: [.actionsRead, .actionsManage])
        guard case .string(let version) = try f.values("actions.get", session: limited, targets: [target])["versionToken"] else {
            Issue.record("Missing version"); return
        }
        func prepare(_ key: String, _ session: AgentCommandService.Session) throws -> AgentResponse {
            var changed = action; changed.shortcut = key
            let definition = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(changed))
            let request = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actions.update", targets: [target],
                                       expectedVersion: version, parameters: ["action": definition])
            let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(request))
            return try f.response("mutations.prepare", session: session, parameters: ["request": frame])
        }
        #expect(try prepare("q", limited).outcome == .error(.permissionDenied))
        #expect(try prepare("z", limited).outcome == .error(.permissionDenied))
        #expect(try prepare("q", full).outcome == .error(.invalidInput))
        guard case .result = try prepare("z", full).outcome else { Issue.record("Expected available shortcut"); return }
        #expect(f.library.actions.contains(action) && f.library.actions.contains(hidden))
        try f.library.deleteAction(hidden.id)
        #expect(try prepare("z", limited).outcome == .error(.permissionDenied))
    }

    @Test func actionGetRequiresScopeAndReturnsTheListedVersion() throws {
        let f = try Fixture()
        var allowed = DraftAction(name: "Allowed", steps: [])
        let hidden = DraftAction(name: "Hidden", steps: [])
        try f.library.saveActions([allowed, hidden])
        let (_, session) = try f.connect(scope: .resources([.init(kind: .action, id: allowed.id)]), capabilities: [.actionsRead])
        let listed = try f.values("actions.list", session: session, parameters: ["surface": .string("all")])
        guard case .array(let items) = listed["items"], case .object(let summary) = items.first else { Issue.record("Missing action"); return }
        let read = try f.values("actions.get", session: session, targets: [.init(kind: .action, id: allowed.id)])
        #expect(read["versionToken"] == summary["versionToken"])
        #expect(try f.response("actions.get", session: session, targets: [.init(kind: .action, id: hidden.id)]).outcome == .error(.notFound))
        allowed.name = "Changed"
        try f.library.saveAction(allowed)
        let changed = try f.values("actions.get", session: session, targets: [.init(kind: .action, id: allowed.id)])
        #expect(changed["versionToken"] != read["versionToken"])
    }

    @Test func actionGroupsRequireExplicitScopeAndReadCapability() throws {
        let f = try Fixture()
        var first = DraftAction(name: "One", steps: []); first.group = "Allowed"
        var second = DraftAction(name: "Two", steps: []); second.group = "Hidden"
        try f.library.saveActions([first, second])
        let id = try #require(f.library.actionGroupIdentifiers["Allowed"])
        let (_, session) = try f.connect(scope: .resources([.init(kind: .actionGroup, id: id)]), capabilities: [.actionsRead])
        let (_, denied) = try f.connect(capabilities: [.draftsRead])
        #expect(try f.response("actions.groups", session: denied).outcome == .error(.permissionDenied))
        let page = try f.values("actions.groups", session: session)
        #expect(page["orderVersion"] == nil)
        guard case .array(let items) = page["items"], case .object(let item) = items.first else { Issue.record("Missing group"); return }
        #expect(items.count == 1 && item["id"] == .string(id.uuidString) && item["name"] == .string("Allowed"))
        let detail = try f.values("actionGroups.get", session: session, targets: [.init(kind: .actionGroup, id: id)])
        #expect(detail["versionToken"] == item["versionToken"])
        let hidden = try #require(f.library.actionGroupIdentifiers["Hidden"])
        #expect(try f.response("actionGroups.get", session: session, targets: [.init(kind: .actionGroup, id: hidden)]).outcome == .error(.notFound))
        try f.library.deleteAction(first.id)
        #expect(try f.values("actions.groups", session: session)["items"] == .array([]))
    }

    @Test func reorderGroupsRequiresWholeLibraryAndIsRecoverable() throws {
        let f = try Fixture()
        var a = DraftAction(name: "A", steps: []); a.group = "Alpha"
        var b = DraftAction(name: "B", steps: []); b.group = "Beta"
        try f.library.saveActions([a, b])
        let alpha = try #require(f.library.actionGroupIdentifiers["Alpha"]), beta = try #require(f.library.actionGroupIdentifiers["Beta"])
        let targets: [AgentResourceReference] = [.init(kind: .actionGroup, id: alpha), .init(kind: .actionGroup, id: beta)]
        let (_, full) = try f.connect(capabilities: [.actionsRead, .actionsManage])
        let (_, limited) = try f.connect(scope: .resources(Set(targets)), capabilities: [.actionsManage])
        guard case .string(let version) = try f.values("actions.groups", session: full)["orderVersion"] else { Issue.record("Missing version"); return }
        let incomplete = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actionGroups.reorder", targets: [targets[0]],
                                      expectedVersion: version, parameters: ["order": .array([.string(alpha.uuidString)])])
        let incompleteFrame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(incomplete))
        #expect(try f.response("mutations.prepare", session: full, parameters: ["request": incompleteFrame]).outcome == .error(.versionConflict))
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actionGroups.reorder", targets: targets,
                                  expectedVersion: version, parameters: ["order": .array([.string(beta.uuidString), .string(alpha.uuidString)])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: limited, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        let prepared = try f.values("mutations.prepare", session: full, parameters: ["request": frame])
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing retry key"); return }
        let signed = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
                                  targets: targets, expectedVersion: version, retryKey: key, parameters: intent.parameters)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed), session: full))
        }
        let original = f.library.actionGroupRecord(named: "Alpha")
        var changed = original; changed.symbol = "star"
        try f.library.saveActionGroup(changed)
        #expect(try send().outcome == .error(.versionConflict))
        #expect(f.library.groupNames == ["Alpha", "Beta"])
        try f.library.saveActionGroup(original)
        let response = try send()
        guard case .result = response.outcome else { Issue.record("Reorder failed: \(response.outcome)"); return }
        #expect(f.library.groupNames == ["Beta", "Alpha"])
        #expect(try send() == response)
    }

    @Test func groupOrderVersionBindsAllPagesAndDetectsChanges() throws {
        let f = try Fixture()
        var first = DraftAction(name: "One", steps: []); first.group = "Alpha"
        var second = DraftAction(name: "Two", steps: []); second.group = "Beta"
        try f.library.saveActions([first, second])
        let (_, session) = try f.connect(capabilities: [.actionsRead])
        let firstPage = try f.values("actions.groups", session: session, parameters: ["limit": .integer(1)])
        guard case .string(let cursor) = firstPage["nextCursor"], case .string(let version) = firstPage["orderVersion"] else {
            Issue.record("Missing cursor or order version"); return
        }
        let params: [String: AgentJSONValue] = ["limit": .integer(1), "cursor": .string(cursor)]
        #expect(try f.values("actions.groups", session: session, parameters: params)["orderVersion"] == .string(version))
        var group = f.library.actionGroupRecord(named: "Beta"); group.symbol = "star"
        try f.library.saveActionGroup(group)
        #expect(try f.response("actions.groups", session: session, parameters: params).outcome == .error(.versionConflict))
        #expect(try f.values("actions.groups", session: session)["orderVersion"] != .string(version))
    }

    @Test func groupPagesDoNotCrossSessionsAndRecheckDeletedGroups() throws {
        let f = try Fixture()
        var first = DraftAction(name: "One", steps: []); first.group = "Alpha"
        var second = DraftAction(name: "Two", steps: []); second.group = "Beta"
        try f.library.saveActions([first, second])
        let alpha = try #require(f.library.actionGroupIdentifiers["Alpha"])
        let beta = try #require(f.library.actionGroupIdentifiers["Beta"])
        let scope: Set<AgentResourceReference> = [.init(kind: .actionGroup, id: alpha), .init(kind: .actionGroup, id: beta)]
        let (_, session) = try f.connect(scope: .resources(scope), capabilities: [.actionsRead])
        let (_, other) = try f.connect(scope: .resources(scope), capabilities: [.actionsRead])
        let firstPage = try f.values("actions.groups", session: session, parameters: ["limit": .integer(1)])
        guard case .string(let cursor) = firstPage["nextCursor"] else { Issue.record("Missing group cursor"); return }
        let parameters: [String: AgentJSONValue] = ["limit": .integer(1), "cursor": .string(cursor)]
        #expect(try f.response("actions.groups", session: other, parameters: parameters).outcome == .error(.invalidInput))
        try f.library.deleteAction(second.id)
        let next = try f.values("actions.groups", session: session, parameters: parameters)
        #expect(next["items"] == .array([]) && next["nextCursor"] == .null)
    }

    @Test func reorderActionsRequiresWholeGroupAndRecovers() throws {
        let f = try Fixture()
        var a = DraftAction(name: "A", steps: []); a.group = "Alpha"
        var b = DraftAction(name: "B", steps: []); b.group = "Alpha"
        var other = DraftAction(name: "Other", steps: []); other.group = "Beta"
        try f.library.saveActions([a, b, other])
        let groupID = try #require(f.library.actionGroupIdentifiers["Alpha"])
        let targets: [AgentResourceReference] = [.init(kind: .action, id: a.id), .init(kind: .action, id: b.id)]
        let (_, full) = try f.connect(capabilities: [.actionsRead, .actionsManage])
        let (_, limited) = try f.connect(scope: .resources(Set(targets)), capabilities: [.actionsManage])
        let params: [String: AgentJSONValue] = ["groupID": .string(groupID.uuidString), "surface": .string("all")]
        guard case .string(let version) = try f.values("actions.list", session: full, parameters: params)["orderVersion"] else { Issue.record("Missing version"); return }
        let incomplete = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actions.reorder", targets: [targets[0]],
                                      expectedVersion: version, parameters: ["order": .array([.string(a.id.uuidString)])])
        let incompleteFrame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(incomplete))
        #expect(try f.response("mutations.prepare", session: full, parameters: ["request": incompleteFrame]).outcome == .error(.versionConflict))
        let intent = AgentRequest(requestID: UUID(), libraryID: nil, operation: "actions.reorder", targets: targets,
                                  expectedVersion: version, parameters: ["order": .array([.string(b.id.uuidString), .string(a.id.uuidString)])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        #expect(try f.response("mutations.prepare", session: limited, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        let prepared = try f.values("mutations.prepare", session: full, parameters: ["request": frame])
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        let signed = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
                                  targets: targets, expectedVersion: version, retryKey: key, parameters: intent.parameters)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed), session: full))
        }
        var changed = b; changed.name = "Changed"; try f.library.saveAction(changed)
        #expect(try send().outcome == .error(.versionConflict))
        try f.library.saveAction(b)
        let result = try send()
        guard case .result = result.outcome else { Issue.record("Reorder failed: \(result.outcome)"); return }
        #expect(f.library.orderedActions().filter { $0.group == "Alpha" }.map(\.id) == [b.id, a.id])
        #expect(f.library.actions.contains(other))
        #expect(try send() == result)
    }

    @Test func actionOrderVersionBindsCompleteGroupPages() throws {
        let f = try Fixture()
        var a = DraftAction(name: "A", steps: []); a.group = "Alpha"
        var b = DraftAction(name: "B", steps: []); b.group = "Alpha"
        try f.library.saveActions([a, b])
        let id = try #require(f.library.actionGroupIdentifiers["Alpha"])
        let (_, full) = try f.connect(capabilities: [.actionsRead])
        let (_, limited) = try f.connect(scope: .resources([.init(kind: .action, id: a.id)]), capabilities: [.actionsRead])
        let params: [String: AgentJSONValue] = ["groupID": .string(id.uuidString), "surface": .string("all"), "limit": .integer(1)]
        let page = try f.values("actions.list", session: full, parameters: params)
        guard case .string(let version) = page["orderVersion"], case .string(let cursor) = page["nextCursor"] else { Issue.record("Missing order version"); return }
        var next = params; next["cursor"] = .string(cursor)
        #expect(try f.values("actions.list", session: full, parameters: next)["orderVersion"] == .string(version))
        #expect(try f.values("actions.list", session: limited, parameters: params)["orderVersion"] == nil)
        b.name = "Changed"; try f.library.saveAction(b)
        #expect(try f.response("actions.list", session: full, parameters: next).outcome == .error(.versionConflict))
    }

    @Test func actionListFiltersScopeAndRechecksPages() throws {
        let f = try Fixture()
        let first = DraftAction(name: "Allowed A", steps: [])
        let second = DraftAction(name: "Allowed B", steps: [])
        let hidden = DraftAction(name: "Hidden", steps: [])
        try f.library.saveActions([first, second, hidden])
        let scope: Set<AgentResourceReference> = [.init(kind: .action, id: first.id), .init(kind: .action, id: second.id)]
        let (_, session) = try f.connect(scope: .resources(scope), capabilities: [.actionsRead])
        let (_, unauthorized) = try f.connect(capabilities: [.draftsRead])
        #expect(try f.response("actions.list", session: unauthorized).outcome == .error(.permissionDenied))
        let page = try f.values("actions.list", session: session, parameters: ["limit": .integer(1), "surface": .string("all")])
        guard case .array(let items) = page["items"], case .object(let item) = items.first,
              case .string(let cursor) = page["nextCursor"] else { Issue.record("Expected first action and cursor"); return }
        #expect(item["id"] == .string(first.id.uuidString))
        let (_, otherSession) = try f.connect(scope: .resources(scope), capabilities: [.actionsRead])
        #expect(try f.response("actions.list", session: otherSession, parameters: ["limit": .integer(1), "surface": .string("all"), "cursor": .string(cursor)]).outcome == .error(.invalidInput))
        try f.library.deleteAction(second.id)
        let next = try f.values("actions.list", session: session, parameters: ["limit": .integer(1), "surface": .string("all"), "cursor": .string(cursor)])
        #expect(next["items"] == .array([]))
        #expect(next["nextCursor"] == .null)
    }

    @Test func preferenceDescriptorsPageFromTheAuthoritativeCatalogWithoutReadingSettings() throws {
        let f = try Fixture(), (_, session) = try f.connect(capabilities: [.preferencesRead])
        let catalog = try AgentPreferenceCatalog.make()
        var returned: [AgentJSONValue] = [], cursor: AgentJSONValue?
        repeat {
            var parameters: [String: AgentJSONValue] = ["limit": .integer(7)]
            if let cursor { parameters["cursor"] = cursor }
            let page = try f.values("preferences.schema", session: session, parameters: parameters)
            guard case .array(let descriptors) = page["items"] else { throw AgentErrorCode.executionError }
            returned += descriptors
            cursor = page["nextCursor"] == .null ? nil : page["nextCursor"]
        } while cursor != nil
        let expected = try JSONDecoder().decode([AgentJSONValue].self,
            from: JSONEncoder().encode(catalog.fields.map { catalog.descriptor($0) }))
        #expect(returned == expected)
        #expect(AgentCommandService.implementedOperations.contains("preferences.schema"))
    }

    @Test func preferenceDiscoveryRequiresReadCapabilityAndValidKnownIDs() throws {
        let f = try Fixture(), (_, reader) = try f.connect(), (_, settings) = try f.connect(capabilities: [.preferencesRead])
        #expect(try f.response("preferences.schema", session: reader).outcome == .error(.permissionDenied))
        #expect(try f.response("preferences.schema", session: settings,
            parameters: ["ids": .array([.string("secret.credential")])]).outcome == .error(.invalidInput))
        let page = try f.values("preferences.schema", session: settings,
            parameters: ["ids": .array([.string("editor.fontSize")])])
        #expect(try items(page).map { $0["id"] } == [.string("editor.fontSize")])
    }

    @Test func preferenceCursorCannotCrossSessionsOrFiltersAndExpires() throws {
        let f = try Fixture(), (_, first) = try f.connect(capabilities: [.preferencesRead]),
            (_, other) = try f.connect(capabilities: [.preferencesRead])
        let page = try f.values("preferences.schema", session: first, parameters: ["limit": .integer(1)])
        let cursor = try #require(page["nextCursor"])
        #expect(cursor != .null)
        #expect(try f.response("preferences.schema", session: other,
            parameters: ["cursor": cursor]).outcome == .error(.invalidInput))
        #expect(try f.response("preferences.schema", session: first,
            parameters: ["cursor": cursor, "ids": .array([.string("editor.fontSize")])]).outcome == .error(.invalidInput))
        f.wall += 601; f.uptime += 601
        #expect(try f.response("preferences.schema", session: first,
            parameters: ["cursor": cursor]).outcome == .error(.invalidInput))
    }

    @Test func lostHostDeniesStartupAuthenticationAndExistingSessions() throws {
        let f = try Fixture(), (record, session) = try f.connect()
        f.hostError = .versionConflict
        #expect(throws: AgentErrorCode.versionConflict) { try f.service.permitsTransportStart() }
        #expect(throws: AgentErrorCode.versionConflict) {
            try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        }
        #expect(try f.response("server.status", session: session).outcome == .error(.versionConflict))
        f.hostError = nil
        #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
    }

    @Test func temporaryHostContentionDeniesOnlyTheCurrentAttempt() throws {
        let f = try Fixture(), (_, session) = try f.connect()
        f.hostError = .busy
        #expect(try f.response("server.status", session: session).outcome == .error(.busy))
        f.hostError = nil
        #expect(try f.values("server.status", session: session)["accessEnabled"] == .bool(true))
    }

    @Test func hostLostDuringReadingDiscardsContentAndInvalidatesTheSession() throws {
        let f = try Fixture(), note = try f.note("Neutral ownership"), (_, session) = try f.connect()
        f.onGeneration = { f.hostError = .versionConflict }
        #expect(try f.response("drafts.get", session: session,
            targets: [.init(kind: .draft, id: note.id)]).outcome == .error(.versionConflict))
        f.onGeneration = nil; f.hostError = nil
        #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
    }

    private func items(_ values: [String: AgentJSONValue]) throws -> [[String: AgentJSONValue]] {
        guard case .array(let items) = values["items"] else { throw AgentErrorCode.executionError }
        return try items.map { guard case .object(let fields) = $0 else { throw AgentErrorCode.executionError }; return fields }
    }
    private func summary(_ values: [String: AgentJSONValue]) throws -> [String: AgentJSONValue] {
        guard case .object(let value) = values["draft"] else { throw AgentErrorCode.executionError }; return value
    }

    @Test func currentReadsUsePendingEditorTextWithoutSavingOrChangingSelection() throws {
        let f = try Fixture(), note = try f.note("Stored\nold text"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let model = try f.window(note)
        model.editor.content = "Pending 🐼\ncurrent needle"
        model.editor.selection = NSRange(location: 8, length: 2)
        model.hasUnsavedChanges = true; f.editors = [model]
        var effects = 0
        model.editor.synchronizeScriptEdit = { effects += 1 }
        model.editor.performUndo = { _ in effects += 1 }
        let before = try f.library.backupData(), focus = model.editor.focusToken
        let value = try f.get(note, session: session)
        #expect(try summary(value)["title"] == .string("Pending 🐼"))
        guard case .object(let chunk) = value["content"] else { Issue.record("Missing text chunk"); return }
        #expect(chunk["text"] == .string(model.editor.content))
        let matches = try items(f.values("drafts.search", session: session, parameters: ["query": .string("needle")]))
        #expect(matches.count == 1 && matches.first?["id"] == .string(note.id.uuidString))
        #expect(model.editor.selection == NSRange(location: 8, length: 2) && model.editor.focusToken == focus)
        #expect(model.hasUnsavedChanges && f.library.notes.first?.content == note.content)
        #expect(effects == 0)
        #expect(try f.library.backupData() == before)
    }

    @Test func divergentPendingEditorsReturnConflictRatherThanStoredTextOrOneWindow() throws {
        let f = try Fixture(), note = try f.note("Stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        f.editors = try ["First neutral", "Second neutral"].map { try f.window(note, content: $0, dirty: true) }
        let before = try f.library.backupData()
        #expect(try f.response("drafts.get", session: session,
            targets: [.init(kind: .draft, id: note.id)]).outcome == .error(.editorConflict))
        #expect(try f.response("drafts.list", session: session).outcome == .error(.editorConflict))
        #expect(try f.library.backupData() == before)
    }

    @Test func matchingPendingWindowsIgnoreCleanStaleAndOtherLibraryEditors() throws {
        let f = try Fixture(), note = try f.note("Stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let foreign = try LibraryStore(inMemory: true, seed: false)
        let a = try f.window(note, content: "Matching 🐼", dirty: true)
        let b = try f.window(note, content: "Matching 🐼", dirty: true)
        var staleNote = note; staleNote.content = "Old clean text"
        let stale = try f.window(staleNote)
        let other = try f.window(note, content: "Foreign pending", dirty: true, library: foreign)
        f.editors = [stale, a, other, b]
        let first = try summary(f.get(note, session: session))
        #expect(first["title"] == .string("Matching 🐼"))
        f.editors.reverse()
        #expect(try summary(f.get(note, session: session)) == first)
        #expect(stale.editor.content == "Old clean text" && other.editor.content == "Foreign pending")
    }

    @Test func editorGenerationTracksUnobservedRevertsAndClosureButNotSelection() throws {
        let f = try Fixture(), note = try f.note("Stored 🐼"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let model = try f.window(note); f.editors = [model]
        let original = try summary(f.get(note, session: session))["versionToken"]
        model.editor.selection = NSRange(location: 7, length: 2); model.editor.focusToken = UUID()
        #expect(try summary(f.get(note, session: session))["versionToken"] == original)
        model.editor.content = "Intermediate"; model.hasUnsavedChanges = true
        model.editor.content = note.content
        let reverted = try summary(f.get(note, session: session))["versionToken"]
        #expect(reverted != original)
        f.editors = []
        let closed = try summary(f.get(note, session: session))["versionToken"]
        #expect(closed != original && closed != reverted)
        model.editor.content = "Disconnected editor"
        #expect(try summary(f.get(note, session: session))["versionToken"] == closed)
        #expect(f.library.notes.first?.content == note.content)
    }

    @Test func canonicallyEquivalentPendingStringsStillConflictWhenTheirCodeUnitsDiffer() throws {
        let f = try Fixture(), note = try f.note("Stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        f.editors = try ["café", "cafe\u{0301}"].map { try f.window(note, content: $0, dirty: true) }
        #expect(try f.response("drafts.get", session: session,
            targets: [.init(kind: .draft, id: note.id)]).outcome == .error(.editorConflict))
    }

    @Test func hiddenEditorConflictsDoNotChangeAuthorizedReadsOrVersionTokens() throws {
        let f = try Fixture(), allowed = try f.note("Allowed"), hidden = try f.note("Hidden")
        defer { f.cleanEditorPreferences() }
        let (_, session) = try f.connect(scope: .resources([.init(kind: .draft, id: allowed.id)]))
        f.editors = try ["First", "Second"].map { try f.window(hidden, content: $0, dirty: true) }
        let before = try summary(f.get(allowed, session: session))["versionToken"]
        let values = try items(f.values("drafts.list", session: session))
        #expect(values.count == 1 && values.first?["id"] == .string(allowed.id.uuidString))
        f.editors[0].editor.content = "Changed hidden text"
        #expect(try summary(f.get(allowed, session: session))["versionToken"] == before)
        #expect(try f.response("drafts.get", session: session,
            targets: [.init(kind: .draft, id: hidden.id)]).outcome == .error(.notFound))
    }

    @Test func pendingTextDoesNotHideChangesToStoredContentFromTheVersionToken() throws {
        let f = try Fixture(), note = try f.note("Original stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let model = try f.window(note, content: "Pending neutral", dirty: true); f.editors = [model]
        let first = try summary(f.get(note, session: session))["versionToken"]
        var stored = note; stored.accessedAt = f.wall.addingTimeInterval(5)
        try f.library.saveNote(stored, preserveRevision: false, preserveDates: true)
        #expect(try summary(f.get(note, session: session))["versionToken"] == first)
        stored.content = "Concurrent stored text"
        try f.library.saveNote(stored, preserveRevision: false, preserveDates: true)
        let values = try f.get(note, session: session)
        #expect(try summary(values)["versionToken"] != first)
        guard case .object(let chunk) = values["content"] else { Issue.record("Missing pending text"); return }
        #expect(chunk["text"] == .string("Pending neutral"))
        #expect(model.hasUnsavedChanges && model.editor.content == "Pending neutral")
    }

    @Test func aWindowOpenedEditedAndClosedBetweenReadsChangesTheVersion() throws {
        let f = try Fixture(), note = try f.note("Stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let before = try summary(f.get(note, session: session))["versionToken"]
        let model = try f.window(note); f.editors = [model]
        model.editor.content = "Intermediate"; model.hasUnsavedChanges = true
        model.editor.content = note.content; f.editors = []
        #expect(try summary(f.get(note, session: session))["versionToken"] != before)
        #expect(f.library.notes.first?.content == note.content)
    }

    @Test func codeUnitOnlyEditsAreReadEvenBeforeTheWindowDirtyFlagChanges() throws {
        let f = try Fixture(), note = try f.note("café"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let model = try f.window(note); f.editors = [model]
        model.editor.content = "cafe\u{0301}"
        #expect(!model.hasUnsavedChanges)
        let result = try f.get(note, session: session)
        guard case .object(let chunk) = result["content"], case .string(let text) = chunk["text"] else {
            Issue.record("Missing pending text"); return
        }
        #expect(Data(text.utf8) == Data(model.editor.content.utf8))
        #expect(Data(try #require(f.library.notes.first).content.utf8) == Data(note.content.utf8))
    }

    @Test func registryObservationDoesNotRetainClosedWindowModels() throws {
        let f = try Fixture(), note = try f.note("Stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        var model: WindowModel? = try f.window(note)
        weak var observed = model
        f.editors = [try #require(model)]
        _ = try f.get(note, session: session)
        f.editors = []; model = nil
        #expect(observed == nil)
        #expect(try summary(f.get(note, session: session))["title"] == .string("Stored"))
    }

    @Test func aRegistryForAnotherLibraryIsRejectedAtServiceConstruction() throws {
        let f = try Fixture(), other = try LibraryStore(inMemory: true, seed: false)
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentCommandService(library: other, libraryID: f.libraryID, connections: f.connections,
                appVersion: "QA", validateHost: {}, isLocked: { false }, editors: f.editorRegistry,
                pendingEditorGeneration: { _ in "" })
        }
    }

    @Test func scopedCountsSearchAndGetNeverExposeOtherNotesOrChangeAccess() throws {
        let f = try Fixture(), allowed = try f.note("Allowed\nneutral café 🐼", tags: ["work/one"])
        let hidden = try f.note("Secret\nneutral hidden"), trash = try f.note("Trash", trashed: true)
        let (_, session) = try f.connect(scope: .resources([.init(kind: .draft, id: allowed.id)]))
        let before = try f.library.backupData()
        #expect(try f.values("library.summary", session: session)["draftCount"] == .integer(1))
        let matches = try items(f.values("drafts.search", session: session, parameters: ["query": .string("neutral")]))
        #expect(matches.count == 1 && matches.first?["id"] == .string(allowed.id.uuidString))
        #expect(matches.first?["preview"] == .string("2: neutral café 🐼"))
        let listed = try items(f.values("drafts.list", session: session))
        #expect(listed.first?["preview"] == .string("neutral café 🐼"))
        #expect(try summary(f.get(allowed, session: session))["accessedAt"] == .null)
        for id in [hidden.id, trash.id, UUID()] {
            #expect(try f.response("drafts.get", session: session, targets: [.init(kind: .draft, id: id)]).outcome == .error(.notFound))
        }
        #expect(try f.library.backupData() == before)
    }

    @Test func listUsesWorkspaceFolderTagSortAndCaseRules() throws {
        let f = try Fixture(), a = try f.note("alpha\nneedle", tags: ["Work/one"])
        let b = try f.note("Beta\nNeedle", tags: ["work/two"], archived: true, accessed: f.wall)
        _ = try f.note("Trash\nneedle", tags: ["work"], trashed: true)
        let (_, session) = try f.connect()
        let params: [String: AgentJSONValue] = ["query": .string("needle"), "tags": .array([.string("work")]),
            "sort": .string("accessed"), "ascending": .bool(true)]
        #expect(try items(f.values("drafts.list", session: session, parameters: params)).map { $0["id"] } == [.string(b.id.uuidString), .string(a.id.uuidString)])
        var exact = params; exact["caseSensitive"] = .bool(true)
        #expect(try items(f.values("drafts.search", session: session, parameters: exact)).map { $0["id"] } == [.string(a.id.uuidString)])
        exact = params; exact["folder"] = .string("archive")
        #expect(try items(f.values("drafts.list", session: session, parameters: exact)).map { $0["id"] } == [.string(b.id.uuidString)])
        exact["excludedTags"] = .array([.string("work/two")])
        #expect(try items(f.values("drafts.list", session: session, parameters: exact)).isEmpty)
    }

    @Test func utf16ChunksRejectSplitScalarsAndNeverReturnANonprogressingPage() throws {
        let f = try Fixture(), note = try f.note("a🐼e\u{301}\n"), (_, session) = try f.connect()
        let first = try f.get(note, session: session, parameters: ["length": .integer(2)])
        guard case .object(let content) = first["content"] else { Issue.record("Missing chunk"); return }
        #expect(content["text"] == .string("a") && content["length"] == .integer(1) && content["hasMore"] == .bool(true))
        let emoji = try f.get(note, session: session, parameters: ["offset": .integer(1), "length": .integer(2)])
        guard case .object(let chunk) = emoji["content"] else { Issue.record("Missing chunk"); return }
        #expect(chunk["text"] == .string("🐼") && chunk["offset"] == .integer(1))
        for p: [String: AgentJSONValue] in [["offset": .integer(2)], ["offset": .integer(1), "length": .integer(1)],
                                           ["offset": .integer(100)], ["length": .integer(0)]] {
            #expect(try f.response("drafts.get", session: session, targets: [.init(kind: .draft, id: note.id)], parameters: p).outcome == .error(.invalidInput))
        }
        let empty = try f.note("")
        guard case .object(let end) = try f.get(empty, session: session)["content"] else { Issue.record("Missing empty chunk"); return }
        #expect(end["length"] == .integer(0) && end["hasMore"] == .bool(false))
    }

    @Test func paginationFreezesMembershipAndOrderButReadsFreshValues() throws {
        let f = try Fixture(), a = try f.note("a"), b = try f.note("b"), (_, session) = try f.connect()
        let params: [String: AgentJSONValue] = ["limit": .integer(1), "sort": .string("title"), "ascending": .bool(true)]
        let page = try f.values("drafts.list", session: session, parameters: params)
        #expect(try items(page).first?["id"] == .string(a.id.uuidString))
        let cursor = try #require(page["nextCursor"])
        _ = try f.note("aa")
        var updated = b; updated.content = "z\nfresh"
        try f.library.saveNote(updated, preserveRevision: false, preserveDates: true)
        var next = params; next["cursor"] = cursor
        let result = try f.values("drafts.list", session: session, parameters: next)
        #expect(try items(result).count == 1)
        #expect(try items(result).first?["title"] == .string("z"))
        #expect(result["nextCursor"] == .null)
        #expect(try f.values("drafts.list", session: session, parameters: next) == result)
    }

    @Test func cursorLivesForTenMinutesButNotBeyondEitherClockBoundary() throws {
        let f = try Fixture(); _ = try f.note("a"); _ = try f.note("b")
        let (_, session) = try f.connect()
        let cursor = try #require(f.values("drafts.list", session: session,
            parameters: ["limit": .integer(1)])["nextCursor"])
        f.wall += 599; f.uptime += 599
        #expect(try items(f.values("drafts.list", session: session,
            parameters: ["cursor": cursor])).count == 1)
        f.uptime += 1
        #expect(try f.response("drafts.list", session: session,
            parameters: ["cursor": cursor]).outcome == .error(.invalidInput))
    }

    @Test func cursorDoesNotExtendAShortGrantOrSurviveMonotonicRollback() throws {
        let f = try Fixture(); _ = try f.note("a"); _ = try f.note("b")
        let record = try f.connections.connectFromUserInterface(name: "Neutral short grant", libraryID: f.libraryID,
            scope: .library, expiresAt: f.wall.addingTimeInterval(90))
        let session = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let cursor = try #require(f.values("drafts.list", session: session,
            parameters: ["limit": .integer(1)])["nextCursor"])
        f.uptime -= 1
        #expect(try f.response("drafts.list", session: session,
            parameters: ["cursor": cursor]).outcome == .error(.invalidInput))
        f.wall += 90; f.uptime += 91
        #expect(try f.response("drafts.list", session: session,
            parameters: ["cursor": cursor]).outcome == .error(.permissionDenied))
    }

    @Test func cursorWallDeadlineCanExpireBeforeTheMonotonicDeadline() throws {
        let f = try Fixture(); _ = try f.note("a"); _ = try f.note("b")
        let (_, session) = try f.connect()
        let cursor = try #require(f.values("drafts.list", session: session,
            parameters: ["limit": .integer(1)])["nextCursor"])
        f.wall += 600
        #expect(try f.response("drafts.list", session: session,
            parameters: ["cursor": cursor]).outcome == .error(.invalidInput))
    }

    @Test func cursorsRejectOtherSessionsChangedQueriesForgeryExpiryAndRestart() throws {
        let f = try Fixture(); _ = try f.note("a"); _ = try f.note("b")
        let (record, session) = try f.connect(), (_, other) = try f.connect()
        let cursor = try #require(f.values("drafts.list", session: session, parameters: ["limit": .integer(1)])["nextCursor"])
        let parameters: [String: AgentJSONValue] = ["cursor": cursor]
        #expect(try f.response("drafts.list", session: other, parameters: parameters).outcome == .error(.invalidInput))
        var changed = parameters; changed["folder"] = .string("archive")
        #expect(try f.response("drafts.list", session: session, parameters: changed).outcome == .error(.invalidInput))
        #expect(try f.response("drafts.list", session: session, parameters: ["cursor": .string("forged")]).outcome == .error(.invalidInput))
        if case .string(let token) = cursor {
            var parts = token.split(separator: ".").map(String.init)
            parts[1] = "0"
            #expect(try f.response("drafts.list", session: session,
                parameters: ["cursor": .string(parts.joined(separator: "."))]).outcome == .error(.invalidInput))
        }
        f.uptime += 600
        #expect(try f.response("drafts.list", session: session, parameters: parameters).outcome == .error(.invalidInput))
        f.service = try f.makeService()
        #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        #expect(try f.response("drafts.list", session: reopened, parameters: parameters).outcome == .error(.invalidInput))
    }

    @Test func versionsRequireParentScopeAndNeverReadAnotherParentsContent() throws {
        let f = try Fixture(), parent = try f.note("Parent"), hidden = try f.note("Hidden")
        let revision = Revision(noteID: parent.id, content: "neutral revision 🐼")
        try f.library.saveRevision(revision); try f.library.saveRevision(Revision(noteID: hidden.id, content: "private"))
        let (_, session) = try f.connect(scope: .resources([.init(kind: .draft, id: parent.id)]))
        let target = [AgentResourceReference(kind: .draft, id: parent.id)]
        let metadata = try items(f.values("drafts.versions", session: session, targets: target))
        #expect(metadata.count == 1 && metadata.first?["content"] == nil)
        #expect(try items(f.values("drafts.versions", session: session, targets: target,
            parameters: ["includeContent": .bool(true)])).first?["content"] == .string(revision.content))
        #expect(try f.response("drafts.versions", session: session, targets: [.init(kind: .draft, id: hidden.id)]).outcome == .error(.notFound))
        let (_, revisionOnly) = try f.connect(scope: .resources([.init(kind: .revision, id: revision.id)]))
        #expect(try f.response("drafts.versions", session: revisionOnly, targets: target).outcome == .error(.notFound))
    }

    @Test func everyRequestRechecksExpiryRevocationReplacementDisableAndLock() throws {
        for change in 0..<5 {
            let f = try Fixture(), (record, session) = try f.connect()
            _ = try f.values("server.status", session: session)
            switch change {
            case 0: f.wall = record.expiresAt
            case 1: _ = try f.connections.revokeFromUserInterface(record.id)
            case 2: _ = try f.connections.replaceGrantFromUserInterface(record.id, capabilities: [.draftsRead], scope: .library)
            case 3: try f.connections.setEnabledFromUserInterface(false)
            default: f.locked = true
            }
            #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
            if change == 4 {
                f.locked = false
                #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
            }
        }
    }

    @Test func credentialsLibraryIdentityAndCapabilitiesCannotBeChosenByRequests() throws {
        let f = try Fixture(), (record, session) = try f.connect(capabilities: [])
        #expect(throws: AgentErrorCode.permissionDenied) {
            try f.service.authenticate(connectionID: record.id, credential: Data(repeating: 0, count: 32))
        }
        #expect(try f.response("server.status", session: session, libraryID: UUID()).outcome == .error(.permissionDenied))
        #expect(try f.response("library.summary", session: session).outcome == .error(.permissionDenied))
        #expect(throws: AgentErrorCode.invalidInput) { try f.service.respond(to: Data("{}".utf8), session: session) }
        f.service.close(session)
        #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
    }

    @Test func draftCreationRecoversWithoutDuplicatesAndRollsBackLostAuthority() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let (record, session) = try f.connect(capabilities: [.draftsRead, .draftsWrite])
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.create",
            parameters: ["content": .string("Created café 🐼"), "tags": .array([.string("One")])])
        let request = try f.preparedMutation(intent, session: session)
        let first = try f.send(request, session: session)
        #expect(try f.send(request, session: session) == first)
        #expect(f.library.notes.count == 1)
        try f.library.reload()
        f.service = try f.makeService()
        let resumed = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let recoveredRequest = try f.preparedMutation(intent, session: resumed)
        #expect(try f.send(recoveredRequest, session: resumed) == first)
        #expect(f.library.notes.count == 1)
        let next = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.create",
            parameters: ["content": .string("Must roll back")])
        let prepared = try f.preparedMutation(next, session: resumed)
        f.library.beforeBatchCommit = { _ = try f.connections.revokeFromUserInterface(record.id) }
        #expect(try f.send(prepared, session: resumed).outcome == .error(.permissionDenied))
        #expect(f.library.notes.count == 1)
    }

    @Test func draftDuplicateCopiesUnicodeAndRecoversWithoutCreatingAnotherCopy() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let (record, session) = try f.connect(capabilities: [.draftsRead, .draftsWrite])
        var original = try f.note("Duplicate café 🐼")
        original.tags = ["Focus"]; original.flag = 3; original.syntax = "TaskPaper"
        try f.library.saveNote(original)
        original = try #require(f.library.notes.first(where: { $0.id == original.id }))
        let revisionCount = f.library.revisions.count
        let source: [String: AgentJSONValue]
        do { source = try f.get(original, session: session) }
        catch { Issue.record("Source read failed: \(error)"); return }
        guard case .object(let draft) = source["draft"], case .string(let version) = draft["versionToken"] else {
            Issue.record("Missing source version"); return
        }
        guard case .object(let repeatedDraft) = try f.get(original, session: session)["draft"],
              case .string(let repeatedVersion) = repeatedDraft["versionToken"] else {
            Issue.record("Missing repeated source version"); return
        }
        #expect(repeatedVersion == version)
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "drafts.duplicate",
            targets: [.init(kind: .draft, id: original.id)], expectedVersion: version)
        let request: AgentRequest
        do { request = try f.preparedMutation(intent, session: session) }
        catch { Issue.record("Duplicate prepare failed: \(error)"); return }
        let first = try f.send(request, session: session)
        #expect(try f.send(request, session: session) == first)
        guard case .result(.object(let values)) = first.outcome,
              case .object(let resource) = values["resource"], case .string(let rawID) = resource["id"],
              let copyID = UUID(uuidString: rawID) else { Issue.record("Missing copy receipt"); return }
        #expect(copyID != original.id && f.library.notes.count == 2)
        let copy = try #require(f.library.notes.first(where: { $0.id == copyID }))
        #expect(copy.content == original.content && copy.tags == original.tags && copy.flag == original.flag)
        #expect(copy.syntax == original.syntax && copy.id != original.id)
        #expect(original.content == "Duplicate café 🐼" && f.library.revisions.count == revisionCount)
        try f.library.reload(); f.service = try f.makeService()
        let resumed = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let recovered = try f.preparedMutation(intent, session: resumed)
        #expect(try f.send(recovered, session: resumed) == first)
        #expect(f.library.notes.count == 2)
    }

    @Test func builtInSyntaxReadRequiresPermissionAndPreservesStorage() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let (_, allowed) = try f.connect(capabilities: [.appearanceRead])
        let (_, denied) = try f.connect(capabilities: [])
        let before = try f.library.backupData()
        for name in ScriptSyntax.names {
            let parameters: [String: AgentJSONValue] = ["name": .string(name)]
            #expect(try f.response("syntaxes.getBuiltIn", session: denied, parameters: parameters).outcome == .error(.permissionDenied))
            let value = try f.values("syntaxes.getBuiltIn", session: allowed, parameters: parameters)
            #expect(value["source"] == .string(try ScriptSyntax.definition(name).source))
            #expect(value == (try f.values("syntaxes.getBuiltIn", session: allowed, parameters: parameters)))
        }
        #expect(try f.library.backupData() == before)
    }

    @Test func builtInSyntaxExportFormatsAndChunks() throws {
        let f = try Fixture()
        let (_, allowed) = try f.connect(capabilities: [.appearanceRead])
        let (_, denied) = try f.connect(capabilities: [])
        let name = "GitHub Markdown"
        let before = try f.library.backupData()
        let parameters: [String: AgentJSONValue] = ["name": .string(name), "offset": .integer(0), "length": .integer(20)]
        #expect(try f.response("syntaxes.exportBuiltIn", session: denied, parameters: ["name": .string(name)]).outcome == .error(.permissionDenied))
        let source = try f.values("syntaxes.exportBuiltIn", session: allowed, parameters: parameters)
        guard case .object(let chunk) = source["content"] else { Issue.record("Missing source chunk"); return }
        #expect(source["format"] == .string("source") && source["name"] == .string(name))
        #expect(chunk["offset"] == .integer(0) && chunk["length"] == .integer(20) && chunk["hasMore"] == .bool(true))
        let url = try f.values("syntaxes.exportBuiltIn", session: allowed, parameters: [
            "name": .string(name), "format": .string("installationURL")
        ])
        guard case .object(let urlChunk) = url["content"], case .string(let text) = urlChunk["text"] else {
            Issue.record("Missing installation URL"); return
        }
        #expect(url["format"] == .string("installationURL"))
        #expect(try AgentImportSource.validate(.object(["kind": .string("installationURL"), "url": .string(text)]), installationEndpoint: "syntax") == "installationURL")
        #expect(url["versionToken"] == source["versionToken"])
        #expect(try f.library.backupData() == before)
    }

    @Test func syntaxListPaginatesOnlyGrantedInstalledDefinitions() throws {
        let f = try Fixture()
        var firstSource = try ScriptSyntax.definition("Markdown").object
        firstSource["name"] = "First syntax"
        let first = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: firstSource))
        var secondSource = try ScriptSyntax.definition("TaskPaper").object
        secondSource["name"] = "Second syntax"
        let second = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: secondSource))
        try f.library.saveSyntax(first); try f.library.saveSyntax(second)
        let firstTarget = AgentResourceReference(kind: .syntax, id: first.id)
        let secondTarget = AgentResourceReference(kind: .syntax, id: second.id)
        let (_, denied) = try f.connect(scope: .resources([]), capabilities: [])
        let (_, hidden) = try f.connect(scope: .resources([]), capabilities: [.appearanceRead])
        let (_, allowed) = try f.connect(scope: .resources([firstTarget, secondTarget]), capabilities: [.appearanceRead])
        let (_, limited) = try f.connect(scope: .resources([firstTarget]), capabilities: [.appearanceRead])
        #expect(try f.response("syntaxes.list", session: denied).outcome == .error(.permissionDenied))
        let empty = try f.values("syntaxes.list", session: hidden)
        #expect(empty["items"] == .array([]))
        #expect(empty["builtInNames"] == .array(ScriptSyntax.names.map(AgentJSONValue.string)))
        let page = try f.values("syntaxes.list", session: allowed, parameters: ["limit": .integer(1)])
        guard case .array(let items) = page["items"], case .object(let item) = items.first,
              case .string(let token) = item["versionToken"], case .string(let cursor) = page["nextCursor"] else {
            Issue.record("Missing scoped syntax or cursor"); return
        }
        #expect(items.count == 1 && item["id"] == .string(first.id.uuidString))
        #expect(item["name"] == .string("First syntax") && !token.isEmpty)
        let next = try f.values("syntaxes.list", session: allowed, parameters: ["limit": .integer(1), "cursor": .string(cursor)])
        guard case .array(let nextItems) = next["items"], case .object(let nextItem) = nextItems.first else {
            Issue.record("Missing next syntax page"); return
        }
        #expect(nextItems.count == 1 && nextItem["id"] == .string(second.id.uuidString))
        let limitedItems = try f.values("syntaxes.list", session: limited)["items"]
        #expect(limitedItems == .array([.object(item)]))
    }

    @Test func syntaxGetRequiresCapabilityAndResourceScopeAndTracksChanges() throws {
        let f = try Fixture()
        var source = try ScriptSyntax.definition("Markdown").object
        source["name"] = "Scoped syntax"
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: source))
        try f.library.saveSyntax(syntax)
        let target = AgentResourceReference(kind: .syntax, id: syntax.id)
        let (_, denied) = try f.connect(scope: .resources([target]), capabilities: [])
        let (_, hidden) = try f.connect(scope: .resources([]), capabilities: [.appearanceRead])
        let (_, allowed) = try f.connect(scope: .resources([target]), capabilities: [.appearanceRead])
        let before = try f.library.backupData()
        #expect(try f.response("syntaxes.get", session: denied, targets: [target]).outcome == .error(.permissionDenied))
        #expect(try f.response("syntaxes.get", session: hidden, targets: [target]).outcome == .error(.notFound))
        let value = try f.values("syntaxes.get", session: allowed, targets: [target])
        guard case .object(let definition) = value["definition"], case .string(let token) = value["versionToken"] else {
            Issue.record("Missing syntax definition"); return
        }
        #expect(definition["id"] == .string(syntax.id.uuidString))
        #expect(definition["name"] == .string("Scoped syntax") && definition["source"] == .string(syntax.source))
        #expect(!token.isEmpty)
        #expect(try f.values("syntaxes.get", session: allowed, targets: [target]) == value)
        #expect(try f.library.backupData() == before)
        source["name"] = "Updated syntax"
        try f.library.saveSyntax(try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: source), id: syntax.id))
        let changed = try f.values("syntaxes.get", session: allowed, targets: [target])
        #expect(changed["versionToken"] != value["versionToken"])
    }

    @Test func schemasReportActualHandlersAndUnsupportedOperationsNeverSimulateSuccess() throws {
        let f = try Fixture(), (_, session) = try f.connect(capabilities: [.draftsRead, .draftsWrite])
        let values = try f.values("server.schemas", session: session)
        guard case .array(let operations) = values["operations"] else { Issue.record("Missing schemas"); return }
        var available = Set(operations.compactMap { item -> String? in
            guard case .object(let fields) = item, fields["available"] == .bool(true), case .string(let name) = fields["name"] else { return nil }
            return name
        })
        #expect(available.remove("syntaxes.getBuiltIn") != nil)
        #expect(available.remove("syntaxes.exportBuiltIn") != nil)
        #expect(available.remove("syntaxes.list") != nil)
        #expect(available.remove("syntaxes.get") != nil)
        #expect(available.remove("drafts.duplicate") != nil)
        #expect(operations.count == 137 && available == AgentReadSchemas.operationNames.union(["preferences.schema", "preferences.get", AgentMutationSchemas.name, "drafts.create", "drafts.update", "drafts.patch", "drafts.restoreVersion", "editor.windows", "editor.get", "editor.setSelection", "editor.replaceRange", "editor.undo", "editor.redo", "editor.tasks", "editor.replaceAll", "editor.find", "editor.markers", "editor.links", "editor.listTasks", "actions.list", "actions.get", "actions.stepSchemas", "actions.create", "actions.update", "actions.duplicate", "actions.move", "actions.reorder", "actions.validateShortcut", "actions.groups", "actionGroups.get", "actionGroups.create", "actionGroups.update", "actionGroups.duplicate", "actionGroups.reorder", "workspaces.list", "workspaces.get", "workspaces.query", "workspaces.create", "workspaces.update", "workspaces.duplicate", "workspaces.reorder", "workspaces.apply"]) && available.count == 50)
        #expect(try f.response("drafts.create", session: session, parameters: ["content": .string("Not saved")]).outcome == .error(.invalidInput))
        #expect(f.library.notes.isEmpty)
        #expect(try f.values("server.capabilities", session: session)["capabilities"] == .array([.string("drafts.read"), .string("drafts.write")]))
    }

    @Test func versionTokensIgnoreAccessButTrackTextMetadataEditorGenerationAndRestart() throws {
        let f = try Fixture(), note = try f.note("Neutral"), (_, session) = try f.connect()
        let token = try summary(f.get(note, session: session))["versionToken"]
        try f.library.recordAccess(note.id, at: f.wall)
        #expect(try summary(f.get(note, session: session))["versionToken"] == token)
        f.generation = "pending-1"
        let pending = try summary(f.get(note, session: session))["versionToken"]
        #expect(pending != token)
        var updated = try #require(f.library.notes.first); updated.tags = ["new"]
        try f.library.saveNote(updated, preserveRevision: false, preserveDates: true)
        #expect(try summary(f.get(note, session: session))["versionToken"] != pending)
        f.service = try f.makeService()
        let (_, fresh) = try f.connect()
        #expect(try summary(f.get(note, session: fresh))["versionToken"] != token)
    }

    @Test func invalidQueriesAndParametersLeaveLibraryAndRevisionsUnchanged() throws {
        let f = try Fixture(); _ = try f.note("Neutral\ntext")
        let (_, session) = try f.connect(), before = try f.library.backupData()
        for query in ["/[/", "OR term", "term OR"] {
            #expect(try f.response("drafts.search", session: session, parameters: ["query": .string(query)]).outcome == .error(.invalidInput))
        }
        #expect(try f.response("drafts.list", session: session, parameters: ["limit": .integer(201)]).outcome == .error(.invalidInput))
        #expect(try f.response("server.status", session: session, parameters: ["credential": .string("untrusted")]).outcome == .error(.invalidInput))
        #expect(try f.library.backupData() == before)
    }

    @Test func pagedRevisionsSkipDeletedMembersWithoutAddingNewRevisions() throws {
        let f = try Fixture(), note = try f.note("Neutral"), (_, session) = try f.connect()
        var revisions = [Revision(noteID: note.id, content: "one"), Revision(noteID: note.id, content: "two"),
                         Revision(noteID: note.id, content: "three")]
        for index in revisions.indices { revisions[index].date = f.wall.addingTimeInterval(Double(index))
            try f.library.saveRevision(revisions[index]) }
        let targets = [AgentResourceReference(kind: .draft, id: note.id)]
        let page = try f.values("drafts.versions", session: session, targets: targets, parameters: ["limit": .integer(1)])
        #expect(try items(page).first?["id"] == .string(revisions[2].id.uuidString))
        try f.library.deleteRevision(revisions[1].id)
        try f.library.saveRevision(Revision(noteID: note.id, content: "new outside snapshot"))
        let next = try f.values("drafts.versions", session: session, targets: targets,
            parameters: ["cursor": #require(page["nextCursor"]), "limit": .integer(1)])
        #expect(try items(next).map { $0["id"] } == [.string(revisions[0].id.uuidString)])
        #expect(next["nextCursor"] == .null)
    }

    @Test func explicitInvalidationAndReplacementCannotReuseSessionsOrCursors() throws {
        let f = try Fixture(); _ = try f.note("a"); _ = try f.note("b")
        let (record, session) = try f.connect(), (_, other) = try f.connect()
        let page = try f.values("drafts.list", session: session, parameters: ["limit": .integer(1)])
        f.service.invalidate(connectionID: record.id)
        #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
        _ = try f.values("server.status", session: other)
        _ = try f.connections.replaceGrantFromUserInterface(record.id, capabilities: [.draftsRead], scope: .library)
        let renewed = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        #expect(try f.response("drafts.list", session: renewed, parameters: ["cursor": #require(page["nextCursor"])]).outcome == .error(.invalidInput))
        f.service.invalidateAll()
        #expect(try f.response("server.status", session: other).outcome == .error(.permissionDenied))
        f.locked = true
        #expect(throws: AgentErrorCode.permissionDenied) { try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id])) }
    }

    @Test func frameBudgetReturnsExplicitUnavailabilityInsteadOfTruncatedContent() throws {
        let f = try Fixture(), note = try f.note("Neutral"), (_, session) = try f.connect()
        try f.library.saveRevision(Revision(noteID: note.id, content: String(repeating: "n", count: AgentRequest.maximumBytes)))
        let before = try f.library.backupData()
        #expect(try f.response("drafts.versions", session: session, targets: [.init(kind: .draft, id: note.id)],
            parameters: ["includeContent": .bool(true)]).outcome == .error(.unavailable))
        #expect(try items(f.values("drafts.versions", session: session, targets: [.init(kind: .draft, id: note.id)])).count == 1)
        #expect(try f.library.backupData() == before)
    }

    @Test func authorityChangeDuringReadingDiscardsTheWholeResponse() throws {
        let f = try Fixture(), note = try f.note("Neutral"), (record, session) = try f.connect()
        f.onGeneration = {
            do { _ = try f.connections.revokeFromUserInterface(record.id) }
            catch { Issue.record(error) }
        }
        #expect(try f.response("drafts.get", session: session, targets: [.init(kind: .draft, id: note.id)]).outcome == .error(.permissionDenied))
    }

    @Test func unreadableAuthorityMetadataNeverFallsBackToAnOldGrant() throws {
        let f = try Fixture(), (_, session) = try f.connect()
        f.bytes = Data("invalid private authority metadata".utf8)
        #expect(try f.response("server.status", session: session).outcome == .error(.storageError))
    }

    @Test func largeUnicodeDraftCanBeReassembledExactlyAcrossTheMaximumChunkBoundary() throws {
        let f = try Fixture(), text = String(repeating: "x", count: 65_535) + "🐼" + String(repeating: "é", count: 34_465)
        let note = try f.note(text), (_, session) = try f.connect()
        var offset: Int64 = 0, recovered = ""
        while true {
            let value = try f.get(note, session: session, parameters: ["offset": .integer(offset)])
            guard case .object(let chunk) = value["content"], case .string(let part) = chunk["text"],
                  case .integer(let length) = chunk["length"] else { Issue.record("Missing chunk"); return }
            recovered += part; offset += length
            if chunk["hasMore"] == .bool(false) { break }
            #expect(length > 0)
            if length == 0 { return }
        }
        #expect(recovered == text && offset == Int64(text.utf16.count))
        #expect(f.library.notes.first?.accessedAt == nil && f.library.revisions.isEmpty)
    }
    @Test func editorSyntaxPagesRejectChangedRulesAndMissingScope() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("# One\n# Two\n- [ ] a\n- [x] b\n[[d:One]] [[d:Two]]")
        let model = try f.window(note); f.editors = [model]
        let (_, session) = try f.connect(capabilities: [.editorRead, .draftsRead])
        let id = try #require(f.editorRegistry.windowSnapshots().first).id
        let targets = [AgentResourceReference(kind: .window, id: id)]
        let (_, onlyWindow) = try f.connect(scope: .resources(Set(targets)), capabilities: [.editorRead, .draftsRead])
        for operation in ["editor.markers", "editor.links", "editor.listTasks"] {
            let page = try f.values(operation, session: session, targets: targets, parameters: ["limit": .integer(1)])
            #expect(try items(page).count == 1)
            let cursor = try #require(page["nextCursor"])
            #expect(cursor != .null)
            let next = try f.values(operation, session: session, targets: targets,
                parameters: ["limit": .integer(1), "cursor": cursor])
            #expect(try items(next).count == 1 && next["nextCursor"] == .null)
            #expect(try f.response(operation, session: onlyWindow, targets: targets).outcome == .error(.notFound))
        }
        let page = try f.values("editor.markers", session: session, targets: targets, parameters: ["limit": .integer(1)])
        var changed = note; changed.syntax = "Plain Text"
        try f.library.saveNote(changed, preserveRevision: false)
        #expect(try f.response("editor.markers", session: session, targets: targets,
            parameters: ["limit": .integer(1), "cursor": try #require(page["nextCursor"])]).outcome == .error(.invalidInput))
        #expect(try items(f.values("editor.markers", session: session, targets: targets)).isEmpty)
        changed.syntax = "Missing neutral grammar"
        try f.library.saveNote(changed, preserveRevision: false)
        for operation in ["editor.markers", "editor.links", "editor.listTasks"] {
            #expect(try f.response(operation, session: session, targets: targets).outcome == .error(.unavailable))
        }
        #expect(model.editor.content == note.content && !model.hasUnsavedChanges)
        #expect(f.library.revisions.isEmpty)
    }

    @Test func editorSyntaxReadsUsePendingTextAndPreserveCustomTaskStates() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let definition = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Neutral agent grammar", "patterns": [], "indentationPatterns": [],
            "featureKeys": [["id": "tasks", "name": "Tasks", "description": "Neutral tasks", "defaultValue": true]],
            "navigationPatterns": [["match": "^# (.*)", "rangeCapture": "0", "labelCapture": "1", "prefix": "H1", "level": 0]],
            "taskMarkDefinitions": [["match": #"(\[[ ~x]\])"#, "rangeType": "task",
                "captures": ["state": "1", "interactive": "1"], "states": ["[ ]", "[~]", "[x]"],
                "initialState": "[ ]", "completedState": ["[x]"], "featureKeys": "tasks"]],
            "linkDefinitions": [["match": #"(<<)((web):([^>]+))(>>)"#,
                "captures": ["prefix": "1", "link": "2", "key": "3", "value": "4", "suffix": "5"]]]]))
        try f.library.saveSyntax(definition)
        var note = try f.note("Stored neutral"); note.syntax = definition.name
        try f.library.saveNote(note, preserveRevision: false)
        let text = "# Café 🐼\n- [~] pending\n- [x] done\n<<web:café>>"
        let model = try f.window(note, content: text, dirty: true)
        defer { model.hasUnsavedChanges = false }
        f.editors = [model]
        let (_, session) = try f.connect(capabilities: [.editorRead, .draftsRead])
        let id = try #require(f.editorRegistry.windowSnapshots().first).id
        let targets = [AgentResourceReference(kind: .window, id: id)]
        let markers = try items(f.values("editor.markers", session: session, targets: targets))
        #expect(markers.first?["label"] == .string("Café 🐼"))
        #expect(markers.first?["range"] == .object(["offset": .integer(0), "length": .integer(9)]))
        let tasks = try items(f.values("editor.listTasks", session: session, targets: targets))
        #expect(tasks.first?["state"] == .string("[~]"))
        #expect(tasks.first?["isCompleted"] == .bool(false))
        let links = try items(f.values("editor.links", session: session, targets: targets))
        #expect(links.first?["key"] == .string("web") && links.first?["value"] == .string("café"))
        let taskPage = try f.values("editor.listTasks", session: session, targets: targets, parameters: ["limit": .integer(1)])
        let taskCursor = try #require(taskPage["nextCursor"])
        #expect(taskCursor != .null)
        model.dependencies.preferences.defaults.set(SyntaxFeaturePreferences.setting(false, feature: "tasks",
            syntax: definition.name, encoded: "{}"), forKey: SyntaxFeaturePreferences.key)
        #expect(try f.response("editor.listTasks", session: session, targets: targets,
            parameters: ["limit": .integer(1), "cursor": taskCursor]).outcome == .error(.invalidInput))
        #expect(try items(f.values("editor.listTasks", session: session, targets: targets)).isEmpty)
        #expect(model.editor.content == text && model.hasUnsavedChanges)
        #expect(f.library.notes.first?.content == "Stored neutral")
        #expect(f.library.revisions.isEmpty)
    }

    @Test func editorFindReadsPendingUnicodeAndRejectsStalePageWithoutMutating() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Stored neutral")
        let model = try f.window(note, content: "🐼 café CAFÉ café", dirty: true)
        defer { model.hasUnsavedChanges = false }
        model.editor.selection = NSRange(location: 3, length: 4)
        f.editors = [model]
        let (_, session) = try f.connect(capabilities: [.draftsRead, .editorRead])
        let snapshot = try #require(f.editorRegistry.windowSnapshots().first)
        let targets = [AgentResourceReference(kind: .window, id: snapshot.id)]
        let parameters: [String: AgentJSONValue] = ["query": .string("café"), "limit": .integer(1)]
        let first = try f.values("editor.find", session: session, targets: targets, parameters: parameters)
        #expect(try items(first) == [["range": .object(["offset": .integer(3), "length": .integer(4)])]])
        let cursor = try #require(first["nextCursor"])
        #expect(cursor != .null)
        var next = parameters; next["cursor"] = cursor
        let second = try f.values("editor.find", session: session, targets: targets, parameters: next)
        #expect(try items(second) == [["range": .object(["offset": .integer(8), "length": .integer(4)])]])
        #expect(try f.response("editor.find", session: session, targets: targets,
            parameters: ["query": .string("["), "regularExpression": .bool(true)]).outcome == .error(.invalidInput))
        #expect(try items(f.values("editor.find", session: session, targets: targets,
            parameters: ["query": .string("absent")])).isEmpty)
        #expect(try items(f.values("editor.find", session: session, targets: targets,
            parameters: ["query": .string("^"), "regularExpression": .bool(true)])) ==
            [["range": .object(["offset": .integer(0), "length": .integer(0)])]])
        let (_, windowOnly) = try f.connect(scope: .resources(Set(targets)), capabilities: [.draftsRead, .editorRead])
        #expect(try f.response("editor.find", session: windowOnly, targets: targets, parameters: parameters).outcome == .error(.notFound))
        #expect(model.editor.selection == NSRange(location: 3, length: 4) && model.hasUnsavedChanges)
        #expect(f.library.notes.first?.content == "Stored neutral")
        model.editor.content += " changed"
        #expect(try f.response("editor.find", session: session, targets: targets, parameters: next).outcome == .error(.invalidInput))
    }

    @Test func editorReadsUseExplicitWindowIDsAndKeepPendingTextUnchanged() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Stored neutral")
        let model = try f.window(note, content: "Pending e\u{0301} 🐼", dirty: true)
        model.editor.selection = NSRange(location: 8, length: 2)
        f.editors = [model]
        let (_, session) = try f.connect(capabilities: [.draftsRead, .editorRead])
        let entries = try items(f.values("editor.windows", session: session))
        #expect(entries.count == 1)
        guard let first = entries.first, case .string(let rawID) = first["windowID"], let id = UUID(uuidString: rawID) else {
            Issue.record("Missing editor identity"); return
        }
        let values = try f.values("editor.get", session: session, targets: [.init(kind: .window, id: id)])
        #expect(values["draftID"] == .string(note.id.uuidString))
        guard case .object(let content) = values["content"] else { Issue.record("Missing editor chunk"); return }
        #expect(content["text"] == .string(model.editor.content))
        #expect(values["selection"] == .object(["offset": .integer(8), "length": .integer(2)]))
        #expect(values["hasUnsavedChanges"] == .bool(true))
        #expect(try items(f.values("editor.windows", session: session)).first?["windowID"] == first["windowID"])
        #expect(f.library.notes.first?.content == note.content)
        #expect(model.hasUnsavedChanges && model.editor.selection == NSRange(location: 8, length: 2))
        model.hasUnsavedChanges = false
    }

    @Test func editorWindowEnumerationFiltersBothWindowAndDraftScopes() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Allowed neutral"), hidden = try f.note("Hidden neutral")
        let allowed = try f.window(note), other = try f.window(hidden)
        f.editors = [allowed, other]
        let (_, all) = try f.connect(capabilities: [.draftsRead, .editorRead])
        let entries = try items(f.values("editor.windows", session: all))
        let entry = try #require(entries.first { $0["draftID"] == .string(note.id.uuidString) })
        guard case .string(let rawID) = entry["windowID"], let id = UUID(uuidString: rawID) else { Issue.record("Missing window"); return }
        let window = AgentResourceReference(kind: .window, id: id)
        let (_, onlyWindow) = try f.connect(scope: .resources([window]), capabilities: [.draftsRead, .editorRead])
        #expect(try items(f.values("editor.windows", session: onlyWindow)).isEmpty)
        #expect(try f.response("editor.get", session: onlyWindow, targets: [window]).outcome == .error(.notFound))
        let (_, scoped) = try f.connect(scope: .resources([window, .init(kind: .draft, id: note.id)]), capabilities: [.draftsRead, .editorRead])
        #expect(try items(f.values("editor.windows", session: scoped)).count == 1)
        f.editors = []
        #expect(try f.response("editor.get", session: scoped, targets: [window]).outcome == .error(.notFound))
    }

    @Test func editorVersionsTrackSelectionAndReadsRejectSplitUTF16Scalars() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("A🐼B"), model = try f.window(note)
        f.editors = [model]
        let (_, session) = try f.connect(capabilities: [.draftsRead, .editorRead])
        let first = try #require(try items(f.values("editor.windows", session: session)).first)
        guard case .string(let rawID) = first["windowID"], let id = UUID(uuidString: rawID) else { Issue.record("Missing window"); return }
        let target = AgentResourceReference(kind: .window, id: id)
        let before = try f.values("editor.get", session: session, targets: [target])
        model.editor.selection = NSRange(location: 1, length: 2)
        let after = try f.values("editor.get", session: session, targets: [target])
        #expect(before["versionToken"] != after["versionToken"])
        model.editor.selection = NSRange(location: 0, length: 0)
        let reverted = try f.values("editor.get", session: session, targets: [target])
        #expect(reverted["versionToken"] != before["versionToken"])
        #expect(try f.response("editor.get", session: session, targets: [target],
            parameters: ["offset": .integer(2), "length": .integer(1)]).outcome == .error(.invalidInput))
        let chunk = try f.values("editor.get", session: session, targets: [target],
            parameters: ["offset": .integer(1), "length": .integer(2)])
        guard case .object(let content) = chunk["content"] else { Issue.record("Missing chunk"); return }
        #expect(content["text"] == .string("🐼"))
        f.editors = []
        f.editors = [model]
        let reopened = try #require(try items(f.values("editor.windows", session: session)).first)
        #expect(reopened["windowID"] != first["windowID"])
        #expect(try f.response("editor.get", session: session, targets: [target]).outcome == .error(.notFound))
        #expect(f.library.notes.first?.content == note.content && f.library.revisions.isEmpty)
    }

    @Test func preparedSelectionPreservesPendingTextAndRecoversWithoutMovingTheCursorAgain() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Stored"), model = try f.window(note, content: "A🐼e\u{301}", dirty: true)
        f.editors = [model]
        let window = try #require(f.editorRegistry.windowSnapshots().first).id
        let target = AgentResourceReference(kind: .window, id: window)
        let scope: AgentResourceScope = .resources([target, .init(kind: .draft, id: note.id)])
        let (connection, session) = try f.connect(scope: scope, capabilities: [.draftsRead, .draftsWrite, .editorRead, .editorWrite])
        let before = try f.library.backupData(), focus = model.editor.focusToken
        guard case .string(let version) = try f.values("editor.get", session: session, targets: [target])["versionToken"] else {
            Issue.record("Missing editor version"); return
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.setSelection", targets: [target],
            expectedVersion: version, parameters: ["range": .object(["offset": .integer(1), "length": .integer(2)])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        let prepared = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        #expect(model.editor.selection == NSRange(location: 0, length: 0))
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing retry key"); return }
        let request = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: version, retryKey: key, parameters: intent.parameters)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        let result = try send()
        guard case .result(.object(let fields)) = result.outcome else { Issue.record("Selection failed: \(result.outcome)"); return }
        #expect(model.editor.selectedText == "🐼" && fields["versionToken"] != .string(version))
        model.editor.selection = NSRange(location: 0, length: 1)
        #expect(try send().outcome == result.outcome)
        #expect(model.editor.selection == NSRange(location: 0, length: 1))
        #expect(model.editor.content == "A🐼e\u{301}" && model.hasUnsavedChanges && model.editor.focusToken == focus)
        #expect(try f.library.backupData() == before)
        let changed = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: version, parameters: ["range": .object(["offset": .integer(0), "length": .integer(0)])])
        let changedFrame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(changed))
        #expect(try f.response("mutations.prepare", session: session, parameters: ["request": changedFrame]).outcome == .error(.invalidInput))
        _ = try f.connections.replaceGrantFromUserInterface(connection.id,
            capabilities: [.draftsRead, .draftsWrite, .editorRead, .editorWrite], scope: .resources([target]))
        let reduced = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        #expect(try f.response("mutations.prepare", session: reduced, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        #expect(model.editor.selection == NSRange(location: 0, length: 1))
    }

    @Test(arguments: ["editor.setSelection", "editor.replaceRange"])
    func editorPreparationRejectsMissingScopeStaleVersionsAndSplitScalars(operation: String) throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("A🐼B"), model = try f.window(note)
        f.editors = [model]
        let target = AgentResourceReference(kind: .window, id: try #require(f.editorRegistry.windowSnapshots().first).id)
        let capabilities: Set<AgentCapability> = [.draftsRead, .draftsWrite, .editorRead, .editorWrite]
        let (_, session) = try f.connect(capabilities: capabilities)
        let (_, windowOnly) = try f.connect(scope: .resources([target]), capabilities: capabilities)
        let (_, readOnly) = try f.connect(capabilities: [.draftsRead, .editorRead])
        guard case .string(let version) = try f.values("editor.get", session: session, targets: [target])["versionToken"] else {
            Issue.record("Missing editor version"); return
        }
        func prepare(_ chosen: AgentCommandService.Session, offset: Int64 = 1, token: String? = nil) throws -> AgentResponse {
            var parameters: [String: AgentJSONValue] = ["range": .object(["offset": .integer(offset), "length": .integer(0)])]
            if operation == "editor.replaceRange" { parameters["text"] = .string("Replacement") }
            let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: operation, targets: [target],
                expectedVersion: token ?? version, parameters: parameters)
            let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(request))
            return try f.response("mutations.prepare", session: chosen, parameters: ["request": frame])
        }
        #expect(try prepare(windowOnly).outcome == .error(.notFound))
        #expect(try prepare(readOnly).outcome == .error(.permissionDenied))
        #expect(try prepare(session, offset: 2).outcome == .error(.invalidInput))
        #expect(try prepare(session, offset: 100).outcome == .error(.invalidInput))
        model.editor.selection = NSRange(location: 1, length: 0)
        #expect(try prepare(session).outcome == .error(.versionConflict))
        #expect(model.editor.content == note.content && f.library.notes.first?.content == note.content)
    }

    @Test(arguments: [false, true])
    func replaceAllUsesNativeSearchUndoAndReplay(regex: Bool) throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("café 12 🐼 CAFÉ 34"), model = try f.window(note)
        f.editors = [model]
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: { model.contentChanged() })
        let history = ScriptUndoEditorFixture(native, content: note.content)
        model.editor.selection = NSRange(location: 3, length: 4)
        model.editor.synchronizeScriptEdit?()
        history.text.manager.removeAllActions()
        model.editor.canApplyExternalEdit = { true }
        defer { model.pausePendingAutosave { true }; history.close(); model.editor.canApplyExternalEdit = nil }
        let target = AgentResourceReference(kind: .window, id: try #require(f.editorRegistry.windowSnapshots().first).id)
        let (_, session) = try f.connect(scope: .resources([target, .init(kind: .draft, id: note.id)]),
            capabilities: [.draftsRead, .draftsWrite, .editorRead, .editorWrite])
        guard case .string(let version) = try f.values("editor.get", session: session, targets: [target])["versionToken"] else {
            throw AgentErrorCode.executionError
        }
        let parameters: [String: AgentJSONValue] = ["query": .string(regex ? "(café) ([0-9]+)" : "café"),
            "regularExpression": .bool(regex), "replacement": .string(regex ? "$2-$1" : "$1🐼")]
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.replaceAll",
            targets: [target], expectedVersion: version, parameters: parameters)
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        let (_, reader) = try f.connect(scope: .resources([target, .init(kind: .draft, id: note.id)]),
            capabilities: [.draftsRead, .editorRead])
        #expect(try f.response("mutations.prepare", session: reader, parameters: ["request": frame]).outcome == .error(.permissionDenied))
        guard case .string(let key) = try f.values("mutations.prepare", session: session,
            parameters: ["request": frame])["retryKey"] else { throw AgentErrorCode.executionError }
        let request = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
            targets: [target], expectedVersion: version, retryKey: key, parameters: parameters)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        let reply = try send()
        guard case .result = reply.outcome else { Issue.record("Replace all failed: \(reply.outcome)"); return }
        #expect(model.editor.content == (regex ? "12-café 🐼 34-CAFÉ" : "$1🐼 12 🐼 $1🐼 34"))
        #expect(model.editor.selection == NSRange(location: 3, length: 4))
        model.editor.performUndo?(false)
        #expect(model.editor.content == note.content)
        #expect(try send().outcome == reply.outcome)
        #expect(model.editor.content == note.content)
    }

    @Test func editorVersionChangesWhenTaskSyntaxChangesWithoutTextEdits() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        var note = try f.note("- [ ] café 🐼")
        let model = try f.window(note); f.editors = [model]
        let target = AgentResourceReference(kind: .window, id: try #require(f.editorRegistry.windowSnapshots().first).id)
        let (_, session) = try f.connect(scope: .resources([target, .init(kind: .draft, id: note.id)]),
            capabilities: [.draftsRead, .editorRead])
        let before = try f.values("editor.get", session: session, targets: [target])["versionToken"]
        note.syntax = "Plain Text"; try f.library.saveNote(note)
        let after = try f.values("editor.get", session: session, targets: [target])["versionToken"]
        #expect(before != after && model.editor.content == note.content)
    }

    @Test(arguments: ["complete", "reset", "advance"])
    func taskMutationUsesSyntaxAndNativeUndoWithoutReplaying(operation: String) throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let initial = operation == "reset" ? "[x]" : "[ ]"
        let note = try f.note("- \(initial) café 🐼"), model = try f.window(note)
        f.editors = [model]
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: { model.contentChanged() })
        let history = ScriptUndoEditorFixture(native, content: note.content)
        model.editor.canApplyExternalEdit = { true }
        defer { model.pausePendingAutosave { true }; history.close(); model.editor.canApplyExternalEdit = nil }
        let target = AgentResourceReference(kind: .window, id: try #require(f.editorRegistry.windowSnapshots().first).id)
        let (_, session) = try f.connect(scope: .resources([target, .init(kind: .draft, id: note.id)]),
            capabilities: [.draftsRead, .draftsWrite, .editorRead, .editorWrite])
        guard case .string(let version) = try f.values("editor.get", session: session, targets: [target])["versionToken"] else {
            throw AgentErrorCode.executionError
        }
        func intent(state: String) -> AgentRequest {
            AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.tasks", targets: [target],
                expectedVersion: version, parameters: ["stateRange": .object(["offset": .integer(2), "length": .integer(3)]),
                    "state": .string(state), "operation": .string(operation)])
        }
        let wrong = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent(state: "wrong")))
        #expect(try f.response("mutations.prepare", session: session, parameters: ["request": wrong]).outcome == .error(.invalidInput))
        #expect(model.editor.content == note.content && !history.text.manager.canUndo)
        let planned = intent(state: initial)
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(planned))
        guard case .string(let key) = try f.values("mutations.prepare", session: session,
            parameters: ["request": frame])["retryKey"] else { throw AgentErrorCode.executionError }
        let request = AgentRequest(requestID: planned.requestID, libraryID: f.libraryID, operation: planned.operation,
            targets: [target], expectedVersion: version, retryKey: key, parameters: planned.parameters)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        var alternate = note; alternate.syntax = "Plain Text"
        try f.library.saveNote(alternate)
        #expect(try send().outcome == .error(.versionConflict))
        #expect(model.editor.content == note.content && !history.text.manager.canUndo)
        try f.library.saveNote(note)
        let reply = try send()
        guard case .result = reply.outcome else { Issue.record("Task change failed: \(reply.outcome)"); return }
        let expected = operation == "reset" ? "- [ ] café 🐼" : "- [x] café 🐼"
        #expect(model.editor.content == expected && history.text.manager.canUndo)
        model.editor.performUndo?(false)
        #expect(model.editor.content == note.content)
        #expect(try send().outcome == reply.outcome)
        #expect(model.editor.content == note.content)
    }

    @Test func undoAndRedoUseNativeHistoryAndReplayDoesNotUndoAgain() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Original café 🐼"), model = try f.window(note)
        f.editors = [model]
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: { model.contentChanged() })
        let history = ScriptUndoEditorFixture(native, content: note.content)
        model.editor.canApplyExternalEdit = { true }
        defer { model.pausePendingAutosave { true }; history.close(); model.editor.canApplyExternalEdit = nil }
        model.editor.content = "Changed 🐼"; model.editor.synchronizeScriptEdit?()
        let target = AgentResourceReference(kind: .window, id: try #require(f.editorRegistry.windowSnapshots().first).id)
        let (_, session) = try f.connect(scope: .resources([target, .init(kind: .draft, id: note.id)]),
            capabilities: [.draftsRead, .draftsWrite, .editorRead, .editorWrite])
        func prepare(_ operation: String) throws -> AgentRequest {
            guard case .string(let version) = try f.values("editor.get", session: session, targets: [target])["versionToken"] else {
                throw AgentErrorCode.executionError
            }
            let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: operation,
                targets: [target], expectedVersion: version)
            let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
            guard case .string(let key) = try f.values("mutations.prepare", session: session,
                parameters: ["request": frame])["retryKey"] else { throw AgentErrorCode.executionError }
            return AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: operation,
                targets: [target], expectedVersion: version, retryKey: key)
        }
        func send(_ request: AgentRequest) throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        let (_, reader) = try f.connect(scope: .resources([target, .init(kind: .draft, id: note.id)]),
            capabilities: [.draftsRead, .editorRead])
        let deniedIntent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.undo",
            targets: [target], expectedVersion: "untrusted-version")
        let deniedFrame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(deniedIntent))
        #expect(try f.response("mutations.prepare", session: reader, parameters: ["request": deniedFrame]).outcome == .error(.permissionDenied))
        #expect(model.editor.content == "Changed 🐼" && history.text.manager.canUndo)
        let undo = try prepare("editor.undo")
        let reply = try send(undo)
        guard case .result = reply.outcome else { Issue.record("Undo failed: \(reply.outcome)"); return }
        #expect(model.editor.content == note.content && history.text.manager.canRedo)
        #expect(try send(undo).outcome == reply.outcome)
        #expect(model.editor.content == note.content && history.text.manager.canRedo)
        let redo = try prepare("editor.redo")
        guard case .result = try send(redo).outcome else { Issue.record("Redo failed"); return }
        #expect(model.editor.content == "Changed 🐼")
        #expect(try send(undo).outcome == reply.outcome)
        #expect(model.editor.content == "Changed 🐼")
    }

    @Test func rangeReplacementUsesNativeUndoAndDoesNotRepeatAfterUserUndo() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("🐼 café\r\nTail"), model = try f.window(note)
        let originalSelection = NSRange(location: 3, length: 4)
        model.editor.selection = originalSelection
        f.editors = [model]
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: { model.contentChanged() })
        let coordinator = NativeEditor.Coordinator(native), text = TestUndoTextView(frame: .zero)
        text.string = note.content; text.setSelectedRange(originalSelection)
        text.manager.groupsByEvent = false; coordinator.textView = text
        coordinator.synchronizeScriptEdit()
        model.editor.synchronizeScriptEdit = {
            text.manager.beginUndoGrouping(); coordinator.synchronizeScriptEdit(); text.manager.endUndoGrouping()
        }
        model.editor.canApplyExternalEdit = { true }
        defer {
            model.pausePendingAutosave { true }
            model.editor.synchronizeScriptEdit = nil; model.editor.canApplyExternalEdit = nil
            coordinator.textView = nil; text.manager.removeAllActions()
        }
        let target = AgentResourceReference(kind: .window, id: try #require(f.editorRegistry.windowSnapshots().first).id)
        let (_, session) = try f.connect(scope: .resources([target, .init(kind: .draft, id: note.id)]),
            capabilities: [.draftsRead, .draftsWrite, .editorRead, .editorWrite])
        guard case .string(let version) = try f.values("editor.get", session: session, targets: [target])["versionToken"] else {
            Issue.record("Missing editor version"); return
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.replaceRange", targets: [target],
            expectedVersion: version, parameters: ["range": .object(["offset": .integer(3), "length": .integer(4)]), "text": .string("té")])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        guard case .string(let key) = try f.values("mutations.prepare", session: session, parameters: ["request": frame])["retryKey"] else {
            Issue.record("Missing retry key"); return
        }
        #expect(!text.manager.canUndo && text.string == note.content)
        let request = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: version, retryKey: key, parameters: intent.parameters)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        let reply = try send()
        guard case .result = reply.outcome else { Issue.record("Replacement failed: \(reply.outcome)"); return }
        #expect(text.string == "🐼 té\r\nTail" && model.editor.content == text.string)
        #expect(text.selectedRange() == NSRange(location: 5, length: 0) && model.hasUnsavedChanges)
        #expect(f.library.notes.first?.content == note.content)
        text.manager.undo()
        #expect(text.string == note.content && text.selectedRange() == originalSelection)
        #expect(try send().outcome == reply.outcome)
        #expect(text.string == note.content && text.manager.canRedo)
        text.manager.redo()
        #expect(text.string == "🐼 té\r\nTail" && model.editor.selection == NSRange(location: 5, length: 0))
        #expect(model.flush() && f.library.notes.first?.content == text.string)
        let revisions = f.library.revisions.count
        #expect(try send().outcome == reply.outcome)
        #expect(f.library.revisions.count == revisions && !model.hasUnsavedChanges)
    }

    @Test func interruptedNativeSynchronizationRetainsPendingTextWithoutReplay() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Original"), model = try f.window(note)
        f.editors = [model]
        model.editor.canApplyExternalEdit = { true }
        var synchronizations = 0
        model.editor.synchronizeScriptEdit = { synchronizations += 1; f.locked = true }
        defer {
            f.locked = false; model.pausePendingAutosave { true }
            model.editor.canApplyExternalEdit = nil; model.editor.synchronizeScriptEdit = nil
        }
        let target = AgentResourceReference(kind: .window, id: try #require(f.editorRegistry.windowSnapshots().first).id)
        let (connection, session) = try f.connect(capabilities: [.draftsRead, .draftsWrite, .editorRead, .editorWrite])
        var activeSession = session
        guard case .string(let version) = try f.values("editor.get", session: session, targets: [target])["versionToken"] else {
            Issue.record("Missing editor version"); return
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.replaceRange", targets: [target],
            expectedVersion: version, parameters: ["range": .object(["offset": .integer(0), "length": .integer(8)]), "text": .string("Retained")])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        guard case .string(let key) = try f.values("mutations.prepare", session: session, parameters: ["request": frame])["retryKey"] else {
            Issue.record("Missing retry key"); return
        }
        let request = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: version, retryKey: key, parameters: intent.parameters)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(request), session: activeSession))
        }
        #expect(try send().outcome == .error(.outcomeUnknown))
        #expect(model.editor.content == "Retained" && model.hasUnsavedChanges && f.library.notes.first?.content == note.content)
        f.locked = false
        activeSession = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        #expect(try send().outcome == .error(.outcomeUnknown))
        #expect(synchronizations == 1 && model.flush() && f.library.notes.first?.content == "Retained")
    }

    @Test(arguments: [("editor.replaceRange", false), ("editor.replaceRange", true), ("editor.setSelection", false)])
    func editorWritesWaitForNativeReadinessAndRejectBusyActions(operation: String, busy: Bool) throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Unchanged"), model = try f.window(note)
        f.editors = [model]
        model.editor.synchronizeScriptEdit = { Issue.record("Must not apply an edit") }
        model.editor.canApplyExternalEdit = { busy }
        model.actionPending = busy
        defer { model.actionPending = false; model.editor.synchronizeScriptEdit = nil; model.editor.canApplyExternalEdit = nil }
        let target = AgentResourceReference(kind: .window, id: try #require(f.editorRegistry.windowSnapshots().first).id)
        let (_, session) = try f.connect(capabilities: [.draftsRead, .draftsWrite, .editorRead, .editorWrite])
        guard case .string(let version) = try f.values("editor.get", session: session, targets: [target])["versionToken"] else {
            Issue.record("Missing editor version"); return
        }
        var parameters: [String: AgentJSONValue] = ["range": .object(["offset": .integer(0), "length": .integer(1)])]
        if operation == "editor.replaceRange" { parameters["text"] = .string("X") }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: operation, targets: [target],
            expectedVersion: version, parameters: parameters)
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(request))
        #expect(try f.response("mutations.prepare", session: session, parameters: ["request": frame]).outcome == .error(busy ? .busy : .interactionRequired))
        #expect(model.editor.content == note.content && f.library.notes.first?.content == note.content)
    }

    @Test(arguments: [false, true])
    func selectionCannotRedirectToAnotherDraftOrReplayAfterCallbackConflict(closeBeforeUpdate: Bool) throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let first = try f.note("First"), second = try f.note("Second")
        let model = try f.window(first), other = try f.window(second)
        f.editors = [model, other]
        let target = AgentResourceReference(kind: .window, id: try #require(f.editorRegistry.windowSnapshots().first { $0.draftID == first.id }).id)
        let (_, session) = try f.connect(capabilities: [.draftsRead, .draftsWrite, .editorRead, .editorWrite])
        guard case .string(let version) = try f.values("editor.get", session: session, targets: [target])["versionToken"] else {
            Issue.record("Missing editor version"); return
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "editor.setSelection", targets: [target],
            expectedVersion: version, parameters: ["range": .object(["offset": .integer(1), "length": .integer(2)])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        guard case .string(let key) = try f.values("mutations.prepare", session: session, parameters: ["request": frame])["retryKey"] else {
            Issue.record("Missing retry key"); return
        }
        var callbacks = 0
        let subscription = model.editor.$selection.dropFirst().sink { _ in
            callbacks += 1
            if callbacks == 1 { model.editor.load(second, focusEditor: false) }
        }
        defer { subscription.cancel() }
        if closeBeforeUpdate { f.editors = [other] }
        let request = AgentRequest(requestID: intent.requestID, libraryID: f.libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: version, retryKey: key, parameters: intent.parameters)
        func send() throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        let expected: AgentErrorCode = closeBeforeUpdate ? .notFound : .outcomeUnknown
        #expect(try send().outcome == .error(expected))
        let after = callbacks
        #expect(try send().outcome == .error(expected))
        #expect(callbacks == after && other.editor.selection == NSRange(location: 0, length: 0))
        #expect(f.library.notes.first { $0.id == first.id }?.content == first.content)
        #expect(f.library.notes.first { $0.id == second.id }?.content == second.content)
    }

    @Test func missingEditorTrackingKeepsMutationRoutesUnavailable() throws {
        let f = try Fixture()
        f.service = try AgentCommandService(library: f.library, libraryID: f.libraryID, connections: f.connections,
            appVersion: "QA", validateHost: {}, isLocked: { false }, now: { f.wall },
            uptime: { f.uptime }, pendingEditorGeneration: { _ in "" })
        let (_, session) = try f.connect(capabilities: [.draftsRead, .draftsWrite])
        let schemas = try f.values("server.schemas", session: session)
        guard case .array(let entries) = schemas["operations"] else { Issue.record("Missing schema entries"); return }
        for name in ["mutations.prepare", "drafts.update", "drafts.patch", "drafts.restoreVersion", "editor.setSelection", "editor.replaceRange"] {
            let entry = entries.first { value in
                guard case .object(let fields) = value else { return false }
                return fields["name"] == .string(name)
            }
            guard case .object(let fields) = entry else { Issue.record("Missing mutation descriptor"); continue }
            #expect(fields["available"] == .bool(false))
        }
        #expect(try f.response("mutations.prepare", session: session).outcome == .error(.unavailable))
        #expect(f.library.notes.isEmpty)
    }

    @Test func preparesAndExecutesAnAuthorizedUpdateWithoutChangingDuringPreparation() throws {
        let f = try Fixture(), note = try f.note("Neutral original 🐼")
        let (record, session) = try f.connect(scope: .resources([.init(kind: .draft, id: note.id)]), capabilities: [.draftsRead, .draftsWrite])
        guard case .string(let version) = try summary(f.get(note, session: session))["versionToken"] else { Issue.record("Missing version"); return }
        let mutation = AgentRequest(requestID: UUID(), libraryID: nil, operation: "drafts.update",
            targets: [.init(kind: .draft, id: note.id)], expectedVersion: version,
            parameters: ["changes": .object(["content": .string("Updated 🐼")])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(mutation))
        let prepared = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        #expect(f.library.notes.first?.content == note.content)
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        #expect(prepared["requestID"] == .string(mutation.requestID.uuidString))
        let signed = AgentRequest(requestID: mutation.requestID, libraryID: f.libraryID, operation: mutation.operation,
            targets: mutation.targets, expectedVersion: version, retryKey: key, parameters: mutation.parameters)
        let reply = try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed), session: session))
        guard case .result(.object(let result)) = reply.outcome else { Issue.record("Update failed: \(reply.outcome)"); return }
        #expect(f.library.notes.first?.content == "Updated 🐼")
        try AgentOperationSchemas.validateResult(result, for: signed)
        let recovered = try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed), session: session))
        #expect(recovered == reply)
        // Explicit preparation of the committed intent must recover, not edit again.
        let preparedAgain = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        guard case .string(let recoveryKey) = preparedAgain["retryKey"] else { Issue.record("Missing recovery key"); return }
        let recovery = AgentRequest(requestID: mutation.requestID, libraryID: f.libraryID, operation: mutation.operation,
            targets: mutation.targets, expectedVersion: version, retryKey: recoveryKey, parameters: mutation.parameters)
        let response = try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(recovery), session: session))
        #expect(response == reply)
        #expect(f.library.notes.first?.content == "Updated 🐼")
        f.service = try f.makeService()
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let oldKeyResponse = try JSONDecoder().decode(AgentResponse.self,
            from: f.service.respond(to: JSONEncoder().encode(signed), session: reopened))
        #expect(oldKeyResponse.outcome == .error(.invalidInput))
        let afterRestart = try f.values("mutations.prepare", session: reopened, parameters: ["request": frame])
        guard case .string(let freshKey) = afterRestart["retryKey"] else { Issue.record("Missing fresh key"); return }
        let fresh = AgentRequest(requestID: mutation.requestID, libraryID: f.libraryID, operation: mutation.operation,
            targets: mutation.targets, expectedVersion: version, retryKey: freshKey, parameters: mutation.parameters)
        let receipt = try JSONDecoder().decode(AgentResponse.self,
            from: f.service.respond(to: JSONEncoder().encode(fresh), session: reopened))
        #expect(receipt == reply)
        #expect(f.library.notes.first?.content == "Updated 🐼")
    }

    @Test func preparationCannotBypassWriteScopeOrRefreshAnExistingKey() throws {
        let f = try Fixture(), note = try f.note("Neutral unchanged")
        let (_, readSession) = try f.connect()
        let (_, writeSession) = try f.connect(capabilities: [.draftsRead, .draftsWrite])
        let (_, excludedSession) = try f.connect(scope: .resources([]), capabilities: [.draftsRead, .draftsWrite])
        guard case .string(let version) = try summary(f.get(note, session: readSession))["versionToken"] else {
            Issue.record("Missing version"); return
        }
        func frame(libraryID: UUID? = nil, retryKey: String? = nil, version: String? = nil) throws -> AgentJSONValue {
            let request = AgentRequest(requestID: UUID(), libraryID: libraryID, operation: "drafts.update",
                targets: [.init(kind: .draft, id: note.id)], expectedVersion: version,
                retryKey: retryKey, parameters: ["changes": .object(["content": .string("Not committed")])])
            return try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(request))
        }
        let intent = try frame(version: version)
        #expect(try f.response("mutations.prepare", session: readSession, parameters: ["request": intent]).outcome == .error(.permissionDenied))
        #expect(try f.response("mutations.prepare", session: excludedSession, parameters: ["request": intent]).outcome == .error(.notFound))
        let invalid: [(AgentJSONValue, AgentErrorCode)] = [
            (try frame(libraryID: UUID(), version: version), .permissionDenied),
            (try frame(retryKey: "existing-key", version: version), .invalidInput),
            (try frame(version: "stale-version"), .versionConflict)]
        for (intent, error) in invalid {
            #expect(try f.response("mutations.prepare", session: writeSession, parameters: ["request": intent]).outcome == .error(error))
        }
        #expect(f.library.notes.first?.content == note.content)
    }

}
