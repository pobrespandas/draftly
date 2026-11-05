import Foundation
import CoreData
import Testing
import AgentContracts
import AgentLocalTransport
import AgentLocalSecurity
@testable import DraftlyCore
@testable import Draftly

@Suite("Loaded local agent host lifetime") @MainActor
struct AgentLocalHostTests {
    @MainActor private final class Fixture {
        let root: URL
        let library: LibraryStore
        let preferences: TestPreferences
        var locked = false
        var applicationError: AgentErrorCode?
        var onApplicationCheck: (() throws -> Void)?
        var secrets: [UUID: Data] = [:]
        var credentialReads = 0
        var applicationChecks = 0
        var connectionAttempts = 0

        init() throws {
            preferences = try TestPreferences(prefix: "Draftly-Local-Host-Preferences-")
            root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Local-Host-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            library = try LibraryStore(directory: root, seed: false)
        }
        func cleanup() {
            preferences.close()
            library.container.viewContext.reset()
            for store in library.container.persistentStoreCoordinator.persistentStores {
                try? library.container.persistentStoreCoordinator.remove(store)
            }
            try? FileManager.default.removeItem(at: root)
        }
        func host(editors: AgentEditorRegistry? = nil, enableReviewedActions: Bool = false,
                  enableReviewedMutations: Bool = false, nativeHost: (@MainActor () -> any ActionHost)? = nil,
                  socketParent: URL = FileManager.default.temporaryDirectory) throws -> AgentLocalHost {
            try AgentLocalHost(library: library, appVersion: "Neutral QA", editors: editors,
                enableReviewedActions: enableReviewedActions, nativeHost: nativeHost, enableReviewedMutations: enableReviewedMutations, preferenceDefaults: preferences.defaults, isLocked: { [self] in self.locked },
                pendingEditorGeneration: { _ in "" }, resolveTargets: { [self] targets in
                    AgentLibraryResourceChoices(library: self.library, editors: editors, bookmarkDefaults: self.preferences.defaults).resolve(targets)
                }, socketParentDirectory: socketParent,
                credentials: .init(read: { [self] id in self.credentialReads += 1; return self.secrets[id] },
                    create: { [self] id, value in
                        guard self.secrets[id] == nil else { throw AgentErrorCode.versionConflict }
                        self.secrets[id] = value
                    }, remove: { [self] in self.secrets.removeValue(forKey: $0) }),
                validateApplication: { [self] in
                    self.applicationChecks += 1
                    try self.onApplicationCheck?()
                    if let error = self.applicationError { throw error }
                }, validateHelper: { _ in })
        }
        // Stored notes have no collection-order contract. Compare every backup
        // field while keeping only that collection independent of fetch order.
        func backupSnapshot(_ supplied: Data? = nil) throws -> AgentJSONValue {
            let data = try supplied ?? library.backupData()
            guard case .object(var fields) = try JSONDecoder().decode(AgentJSONValue.self, from: data),
                  case .array(let notes) = fields["notes"] else { throw AgentErrorCode.storageError }
            let identified = try notes.map { value -> (String, AgentJSONValue) in
                guard case .object(let note) = value, case .string(let id) = note["id"], UUID(uuidString: id) != nil else {
                    throw AgentErrorCode.storageError
                }
                return (id, value)
            }
            fields["notes"] = .array(identified.sorted { $0.0 < $1.0 }.map { $0.1 })
            return .object(fields)
        }

        func connect(_ host: AgentLocalHost, scope: AgentResourceScope = .library) throws -> AgentConnectionRecord {
            try host.connections.connectFromUserInterface(name: "Neutral QA", libraryID: host.libraryID, scope: scope)
        }
        func client(_ host: AgentLocalHost, record: AgentConnectionRecord) async throws -> AgentLocalClient {
            try await AgentLocalClient.connect(path: #require(host.endpoint), connectionID: record.id,
                credential: #require(secrets[record.id]), validateServer: { _ in })
        }
        func request(_ operation: String, session: AgentCommandService.Session, service: AgentCommandService) throws -> AgentResponse {
            let request = AgentRequest(requestID: UUID(), libraryID: nil, operation: operation)
            return try JSONDecoder().decode(AgentResponse.self, from: service.respond(to: JSONEncoder().encode(request), session: session))
        }
    }

    @Test func nativeReviewAndRecoveryWorkAcrossRealLocalTransports() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let native = AgentNativeServiceTests.DirectNativeHost()
        let host = try f.host(enableReviewedActions: true, nativeHost: { native }); defer { host.close() }
        #expect(host.endpoint == nil)
        try host.setEnabledFromUserInterface(true)
        let record = try host.connections.connectFromUserInterface(name: "Native transport QA", libraryID: host.libraryID,
            capabilities: [.nativeUse], scope: .resources([]))
        let first = try await f.client(host, record: record)
        let request = AgentRequest(requestID: UUID(), libraryID: host.libraryID, operation: "native.share",
            parameters: ["text": .string("Neutral café 🐼")])
        let data = try JSONEncoder().encode(request)
        let accepted = try JSONDecoder().decode(AgentResponse.self, from: await first.request(data))
        guard case .accepted = accepted.outcome else { Issue.record("Missing native operation"); return }
        for _ in 0..<1000 where host.approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(host.approvals.pendingFromUserInterface().first)
        #expect(native.calls.isEmpty)
        await first.close()
        let polling = try await f.client(host, record: record)
        try host.approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        var response = accepted
        for _ in 0..<1000 {
            response = try JSONDecoder().decode(AgentResponse.self, from: await polling.request(data))
            if case .result = response.outcome { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(response.outcome == .result(.object(["completed": .bool(true)])) && native.calls.count == 1)
        await polling.close()
        let second = try await f.client(host, record: record)
        let recovered = try JSONDecoder().decode(AgentResponse.self, from: await second.request(data))
        #expect(recovered == response && native.calls.count == 1)
        await second.close()
    }

    @Test func chatGrantRequiresEnabledHostAndClosesWithoutRevokingOtherConnections() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let note = Note(content: "Chat grant café 🐼"), hidden = Note(content: "Hidden")
        try f.library.saveNotes([note, hidden], preserveRevision: false)
        let host = try f.host(); defer { host.close() }
        let targets: Set<AgentResourceReference> = [.init(kind: .draft, id: note.id)]
        #expect(throws: AgentErrorCode.permissionDenied) {
            try host.makeChatToolsFromUserInterface(capabilities: [.draftsRead], targets: targets,
                onRevocationError: { _ in Issue.record("Unexpected cleanup error") })
        }
        try host.setEnabledFromUserInterface(true)
        let other = try f.connect(host)
        let tools = try host.makeChatToolsFromUserInterface(capabilities: [.draftsRead], targets: targets,
            onRevocationError: { _ in Issue.record("Unexpected cleanup error") })
        let configuration = try host.connections.configurationForUserInterface()
        let record = try #require(configuration.connections.first { $0.id != other.id })
        #expect(Set(record.resources) == targets)
        #expect(record.expiresAt.timeIntervalSinceNow > 0 && record.expiresAt.timeIntervalSinceNow <= 900)
        #expect(try await tools.tools().contains { $0.name == "draftly_drafts_get" })
        tools.invalidate()
        let remaining = try host.connections.configurationForUserInterface().connections
        #expect(!remaining.contains { $0.id == record.id })
        #expect(remaining.first { $0.id == other.id }?.revoked == false)
        #expect(f.secrets[record.id] == nil && f.secrets[other.id] != nil)
        let externallyRevoked = try host.makeChatToolsFromUserInterface(capabilities: [.draftsRead], targets: targets,
            onRevocationError: { _ in Issue.record("Unexpected cleanup error") })
        let beforeRevocation = try host.connections.configurationForUserInterface()
        let revokedID = try #require(beforeRevocation.connections.first { $0.id != other.id }?.id)
        var revocationNotifications = 0
        externallyRevoked.onInvalidated = { revocationNotifications += 1 }
        _ = try host.connections.revokeFromUserInterface(revokedID)
        #expect(revocationNotifications == 1)
        #expect(try host.connections.configurationForUserInterface().connections.first { $0.id == revokedID }?.revoked == true)
        let stopped = try host.makeChatToolsFromUserInterface(capabilities: [.draftsRead], targets: targets,
            onRevocationError: { _ in Issue.record("Unexpected cleanup error") })
        var notified = false
        stopped.onInvalidated = { notified = true }
        host.suspend()
        #expect(notified)
        await #expect(throws: AgentErrorCode.cancelled) { try await stopped.tools() }
    }

    @Test func reviewedWorkspaceDeletionIsExplicitAndStopWorkCancelsPendingReview() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let workspace = Workspace(name: "Keep until approved")
        try f.library.saveWorkspace(workspace)
        let host = try f.host(enableReviewedMutations: true)
        defer { host.close() }
        #expect(host.service.availableCapabilities.contains(.destructiveRequest))
        #expect(!host.service.availableCapabilities.contains(.actionsRun))
        try host.setEnabledFromUserInterface(true)
        let record = try host.connections.connectFromUserInterface(name: "Delete review", libraryID: host.libraryID,
            capabilities: [.workspacesRead, .workspacesManage, .destructiveRequest],
            scope: .resources([.init(kind: .workspace, id: workspace.id)]))
        let session = try host.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        func send(_ request: AgentRequest) throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self, from: host.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        let target = AgentResourceReference(kind: .workspace, id: workspace.id)
        let read = try send(.init(requestID: UUID(), libraryID: host.libraryID, operation: "workspaces.get", targets: [target]))
        guard case .result(.object(let values)) = read.outcome, case .string(let version) = values["versionToken"] else {
            Issue.record("Missing version"); return
        }
        let intent = AgentRequest(requestID: UUID(), libraryID: host.libraryID, operation: "workspaces.delete", targets: [target], expectedVersion: version)
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(intent))
        let prepared = try send(.init(requestID: UUID(), libraryID: host.libraryID, operation: "mutations.prepare", parameters: ["request": frame]))
        guard case .result(.object(let ticket)) = prepared.outcome, case .string(let key) = ticket["retryKey"] else {
            Issue.record("Missing retry key"); return
        }
        let accepted = try send(.init(requestID: intent.requestID, libraryID: host.libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: version, retryKey: key))
        guard case .accepted(let operationID, _) = accepted.outcome else { Issue.record("Missing accepted operation"); return }
        for _ in 0..<1000 where host.approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        #expect(host.approvals.pendingFromUserInterface().count == 1)
        try host.setEnabledFromUserInterface(false)
        for _ in 0..<1000 where !host.approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        #expect(host.approvals.pendingFromUserInterface().isEmpty && f.library.workspaces == [workspace])
        #expect(try host.connections.configurationForUserInterface().enabled == false)
        try host.setEnabledFromUserInterface(true)
        for _ in 0..<1000 where try !host.operations.snapshot(operationID, connectionID: record.id).state.isTerminal { await Task.yield() }
        #expect(try host.operations.snapshot(operationID, connectionID: record.id).state == .cancelled)
    }

    @Test func reviewedActionAdmissionRequiresAnExplicitAuthorizedEditorWindow() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let note = try f.library.createNote(content: "Unchanged")
        let action = DraftAction(name: "Neutral", steps: [ActionStep("insertText", ["template": " café 🐼"])])
        try f.library.saveAction(action)
        let model = WindowModel(library: f.library); model.select(note.id)
        let editors = AgentEditorRegistry(library: f.library, models: { [model] })
        let host = try f.host(editors: editors, enableReviewedActions: true)
        defer { host.close() }
        #expect(host.service.availableCapabilities.isSuperset(of: [.actionsRun, .draftsWrite, .editorWrite, .nativeUse]))
        try host.setEnabledFromUserInterface(true)
        let record = try host.connections.connectFromUserInterface(name: "Admission", libraryID: host.libraryID,
            capabilities: [.actionsRead, .actionsRun, .draftsRead, .draftsWrite, .editorRead, .editorWrite], scope: .library)
        let session = try host.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        func response(_ request: AgentRequest) throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self,
                from: host.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        let read = try response(.init(requestID: UUID(), libraryID: host.libraryID, operation: "actions.get",
            targets: [.init(kind: .action, id: action.id)]))
        guard case .result(.object(let values)) = read.outcome,
              case .string(let version) = values["versionToken"] else { Issue.record("Missing action version"); return }
        let before = try f.backupSnapshot()
        for parameters: [String: AgentJSONValue] in [[:], ["windowID": .string(UUID().uuidString)]] {
            let result = try response(.init(requestID: UUID(), libraryID: host.libraryID, operation: "actions.run",
                targets: [.init(kind: .action, id: action.id), .init(kind: .draft, id: note.id)],
                expectedVersion: version, parameters: parameters))
            let expected: AgentErrorCode = parameters.isEmpty ? .interactionRequired : .notFound
            #expect(result.outcome == .error(expected))
        }
        #expect(try f.backupSnapshot() == before)
        #expect(host.approvals.pendingFromUserInterface().isEmpty)
        let window = try #require(editors.windowSnapshots().first)
        let admitted = try response(.init(requestID: UUID(), libraryID: host.libraryID, operation: "actions.run",
            targets: [.init(kind: .action, id: action.id), .init(kind: .draft, id: note.id)],
            expectedVersion: version, parameters: ["windowID": .string(window.id.uuidString)]))
        guard case .result(.object(let submission)) = admitted.outcome,
              case .string(let rawID) = submission["operationID"], let id = UUID(uuidString: rawID) else {
            Issue.record("Expected an accepted operation: \(admitted.outcome)"); return
        }
        for _ in 0..<1000 {
            if try host.operations.snapshot(id, connectionID: record.id).state.isTerminal { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let finished = try host.operations.snapshot(id, connectionID: record.id)
        #expect(finished.state == .succeeded)
        #expect(finished.output?.report.reason == .success)
        let polled = try response(.init(requestID: UUID(), libraryID: host.libraryID, operation: "operations.get",
            targets: [.init(kind: .operation, id: id)]))
        guard case .result = polled.outcome else { Issue.record("Missing completed operation"); return }
        #expect(model.editor.content.contains(" café 🐼"))
        #expect(f.library.notes.first?.content == model.editor.content)
    }

    @Test(arguments: ["stopWork", "removeEditor", "timeout"])
    func hostActionCannotContinueAfterInterruption(interruption: String) async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let note = try f.library.createNote(content: "Private neutral text")
        let action = DraftAction(name: "Reviewed share", steps: [
            ActionStep("share", ["template": "[[draft]]"]),
            ActionStep("insertText", ["template": "ERROR: continued after Stop Work"])
        ])
        try f.library.saveAction(action)
        let model = WindowModel(library: f.library); model.select(note.id)
        var registeredModels = [model]
        let editors = AgentEditorRegistry(library: f.library, models: { registeredModels })
        let host = try f.host(editors: editors, enableReviewedActions: true)
        defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let record = try host.connections.connectFromUserInterface(name: "Reviewed execution", libraryID: host.libraryID,
            capabilities: [.actionsRead, .actionsRun, .draftsRead, .draftsWrite, .editorWrite, .nativeUse], scope: .library)
        let session = try host.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        func response(_ request: AgentRequest) throws -> AgentResponse {
            try JSONDecoder().decode(AgentResponse.self,
                from: host.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        let read = try response(.init(requestID: UUID(), libraryID: host.libraryID, operation: "actions.get",
            targets: [.init(kind: .action, id: action.id)]))
        guard case .result(.object(let values)) = read.outcome,
              case .string(let version) = values["versionToken"] else { Issue.record("Missing action version"); return }
        let window = try #require(editors.windowSnapshots().first)
        let admitted = try response(.init(requestID: UUID(), libraryID: host.libraryID, operation: "actions.run",
            targets: [.init(kind: .action, id: action.id), .init(kind: .draft, id: note.id)], expectedVersion: version,
            parameters: ["windowID": .string(window.id.uuidString), "interactive": .bool(true),
                         "timeoutSeconds": .integer(interruption == "timeout" ? 1 : 120)]))
        guard case .result(.object(let submission)) = admitted.outcome,
              case .string(let rawID) = submission["operationID"], let id = UUID(uuidString: rawID) else {
            Issue.record("Expected an accepted operation"); return
        }
        for _ in 0..<1000 where host.approvals.pendingFromUserInterface().isEmpty {
            try await Task.sleep(for: .milliseconds(1))
        }
        let review = try #require(host.approvals.pendingFromUserInterface().first)
        #expect(review.effects.snapshot["nativeOperation"] == .string("share"))
        #expect(try host.operations.snapshot(id, connectionID: record.id).state == .waitingForUser)
        if interruption == "stopWork" {
            try host.makeLibrarySettingsModel().stopWork()
        } else if interruption == "removeEditor" {
            registeredModels = []
            editors.refreshMembership()
            try host.approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        }
        for _ in 0..<3000 {
            if !model.runner.isRunning && !model.actionPending { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(!model.runner.isRunning && !model.actionPending)
        if interruption == "stopWork" {
            #expect(throws: AgentErrorCode.permissionDenied) { try host.operations.snapshot(id, connectionID: record.id) }
        } else {
            for _ in 0..<1000 {
                if try host.operations.snapshot(id, connectionID: record.id).state.isTerminal { break }
                try await Task.sleep(for: .milliseconds(1))
            }
            let finished = try host.operations.snapshot(id, connectionID: record.id)
            #expect(finished.state == (interruption == "timeout" ? .timedOut : .failed))
            #expect(finished.output?.outcomeUnknown == false)
            _ = try finished.wireValue()
        }
        #expect(host.approvals.pendingFromUserInterface().isEmpty)
        #expect(model.editor.content == note.content)
        #expect(f.library.notes.first?.content == note.content)
    }

    @Test func hostRejectsAnotherLibraryEditorRegistryBeforeCreatingPrivateState() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let other = try LibraryStore(inMemory: true, seed: false)
        let editors = AgentEditorRegistry(library: other, models: { [] })
        #expect(throws: AgentErrorCode.invalidInput) { try f.host(editors: editors) }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Agents").path))
    }

    @Test func socketReadsUseTheInjectedEditorRegistryWithoutSavingPendingText() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let domain = "Draftly-Agent-Host-Editor-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let note = try f.library.createNote(content: "Stored neutral")
        var dependencies = WindowDependencies(); dependencies.preferences = WindowPreferences(defaults: defaults)
        let model = WindowModel(library: f.library, dependencies: dependencies)
        model.editor.load(note, focusEditor: false)
        model.editor.content = "Pending neutral 🐼"; model.hasUnsavedChanges = true
        let editors = AgentEditorRegistry(library: f.library, models: { [model] })
        let before = try f.backupSnapshot(), host = try f.host(editors: editors)
        defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let record = try f.connect(host), client = try await f.client(host, record: record)
        do {
            let request = AgentRequest(requestID: UUID(), libraryID: nil, operation: "drafts.get", targets: [.init(kind: .draft, id: note.id)])
            let response = try JSONDecoder().decode(AgentResponse.self, from: await client.request(JSONEncoder().encode(request)))
            guard case .result(.object(let values)) = response.outcome,
                  case .object(let chunk) = values["content"] else { throw AgentErrorCode.executionError }
            #expect(chunk["text"] == .string(model.editor.content))
            #expect(model.hasUnsavedChanges && f.library.notes.first?.content == note.content)
            #expect(try f.backupSnapshot() == before)
            await client.close()
        } catch { await client.close(); throw error }
    }

    @Test func hostCallbacksRetainTheirFixtureWhilePairingCanStillUseIt() async throws {
        var fixture: Fixture? = try Fixture()
        weak var retained = fixture
        let host = try #require(fixture).host()
        defer { host.close(); retained?.cleanup() }
        try host.setEnabledFromUserInterface(true)
        fixture = nil
        // Closed sockets can still finish a broker callback on MainActor.
        // Its injected state must live as long as those callbacks can use it.
        _ = try #require(retained)
        let peer = try await AgentPairingClient.connect(path: #require(host.endpoint), name: "Neutral QA", validateServer: { _ in })
        do {
            #expect(try await peer.cancel().state == .cancelled)
            await peer.close()
        } catch { await peer.close(); throw error }
    }

    @Test func libraryDestinationBindsPairingWhileExplicitSocketKeepsItsLegacyChallenge() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        for destination: AgentHostDestination in [.library(host.libraryID, stateParent: f.root.path),
            .socket(try #require(host.endpoint))] {
            let peer = try await destination.pair(name: "Neutral QA", validateServer: { _ in })
            let challenge = await peer.challenge
            let expected: UUID? = if case .library = destination { host.libraryID } else { nil }
            #expect(challenge.libraryID == expected && challenge.code != nil)
            await peer.close()
        }
        #expect(f.secrets.isEmpty)
    }

    @Test func explicitSocketDestinationStillAuthenticatesWithoutADiscoveryCatalog() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let record = try f.connect(host), catalog = f.root.appendingPathComponent("Agents/hosts.json")
        try FileManager.default.removeItem(at: catalog)
        let destination = AgentHostDestination.socket(try #require(host.endpoint))
        let client = try await destination.connect(connectionID: record.id, credential: #require(f.secrets[record.id]), validateServer: { _ in })
        #expect(await client.libraryID == host.libraryID)
        #expect(!FileManager.default.fileExists(atPath: catalog.path))
        await client.close()
    }

    @Test func misleadingLocatorCannotPairOrAuthenticateAgainstAnotherLibrary() async throws {
        let f = try Fixture(), other = try Fixture(); defer { f.cleanup(); other.cleanup() }
        let first = try f.host(), second = try other.host(); defer { first.close(); second.close() }
        try first.setEnabledFromUserInterface(true); try second.setEnabledFromUserInterface(true)
        let locator = try AgentHostLocator(parentDirectory: f.root)
        try locator.publish(.init(libraryID: first.libraryID, socketPath: #require(second.endpoint)))
        let destination = AgentHostDestination.library(first.libraryID, stateParent: f.root.path)
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await destination.pair(name: "Neutral QA", validateServer: { _ in })
        }
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await destination.connect(connectionID: UUID(), credential: Data(repeating: 7, count: 32), validateServer: { _ in })
        }
        #expect(second.pairing.pendingFromUserInterface().isEmpty)
        #expect(other.credentialReads == 0 && other.secrets.isEmpty && f.secrets.isEmpty)
    }

    @Test func aLaterExplicitRequestResolvesTheReopenedHostWithoutReplayingAFailedRequest() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let first = try f.host(); defer { first.close() }
        try first.setEnabledFromUserInterface(true)
        let record = try f.connect(first), credential = try #require(f.secrets[record.id])
        let destination = AgentHostDestination.library(first.libraryID, stateParent: f.root.path)
        let helper = AgentHelperConnection(connect: {
            await MainActor.run { f.connectionAttempts += 1 }
            return try await destination.connect(connectionID: record.id, credential: credential, validateServer: { _ in })
        })
        do {
            let request = AgentRequest(requestID: UUID(), libraryID: nil, operation: "server.status")
            let initial = try await helper.request(request)
            guard case .result = initial.outcome else { throw AgentErrorCode.executionError }
            first.close()
            let next = try f.host(); defer { next.close() }
            try next.resumeIfEnabled()
            await #expect(throws: AgentErrorCode.unavailable) { try await helper.request(request) }
            #expect(f.connectionAttempts == 1)
            let response = try await helper.request(.init(requestID: UUID(), libraryID: nil, operation: "server.status"))
            #expect(f.connectionAttempts == 2)
            guard case .result = response.outcome else { throw AgentErrorCode.executionError }
            await helper.close()
        } catch { await helper.close(); throw error }
    }

    @Test func onlyListeningHostsPublishAndResumingUsesAFreshEpoch() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        let locator = try AgentHostLocator(parentDirectory: f.root)
        #expect(try locator.endpoints().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Agents/hosts.lock").path))
        try host.setEnabledFromUserInterface(true)
        let first = try #require(locator.endpoints().first)
        #expect(first.libraryID == host.libraryID && first.socketPath == host.endpoint)
        host.suspend()
        #expect(try locator.endpoints().isEmpty && host.locatorCleanupError == nil)
        try host.resumeIfEnabled()
        let next = try #require(locator.endpoints().first)
        #expect(next.libraryID == first.libraryID && next.epochID != first.epochID && next.socketPath != first.socketPath)
        host.close()
        #expect(try locator.endpoints().isEmpty)
    }

    @Test func locatorCleanupContentionIsVisibleAndDoesNotKeepTheSocketAlive() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let locator = try AgentHostLocator(parentDirectory: f.root), entry = try #require(locator.endpoints().first)
        let directory = try AgentStateDirectory(parentDirectory: f.root), lock = try directory.acquireLock("hosts.lock")
        defer { lock.release() }
        // Readers use the complete atomic snapshot even while a writer lock is held.
        #expect(try locator.endpoints() == [entry])
        host.suspend()
        #expect(host.endpoint == nil && host.locatorCleanupError == .busy)
        #expect(!FileManager.default.fileExists(atPath: entry.socketPath))
        #expect(try locator.endpoints() == [entry])
        lock.release(); host.suspend()
        #expect(try locator.endpoints().isEmpty && host.locatorCleanupError == nil)
    }

    @Test func stoppingAnOldPublicationDoesNotRemoveADifferentEpoch() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let locator = try AgentHostLocator(parentDirectory: f.root)
        let replacement = try AgentHostLocator.Endpoint(libraryID: host.libraryID, socketPath: "/tmp/da-neutral-other/s")
        try locator.publish(replacement)
        host.suspend()
        #expect(try locator.endpoints() == [replacement] && host.locatorCleanupError == nil)
    }

    @Test func retryingOldCloseAfterCleanupContentionDoesNotDeleteTheNewHostHint() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let first = try f.host(); try first.setEnabledFromUserInterface(true)
        let locator = try AgentHostLocator(parentDirectory: f.root), old = try #require(locator.endpoints().first)
        let directory = try AgentStateDirectory(parentDirectory: f.root), lock = try directory.acquireLock("hosts.lock")
        defer { lock.release() }
        first.close()
        #expect(first.endpoint == nil && first.locatorCleanupError == .busy)
        lock.release()
        let next = try f.host(); defer { next.close() }
        try next.resumeIfEnabled()
        let current = try #require(locator.endpoints().first)
        #expect(current.libraryID == old.libraryID && current.epochID != old.epochID)
        first.close()
        #expect(try first.locatorCleanupError == nil && locator.endpoints() == [current])
        #expect(next.endpoint == current.socketPath)
    }

    @Test func corruptLocatorPreventsListeningWithoutRepairingTheCatalog() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true); host.suspend()
        let file = f.root.appendingPathComponent("Agents/hosts.json"), invalid = Data("not a locator".utf8)
        try invalid.write(to: file)
        #expect(throws: AgentErrorCode.storageError) { try host.resumeIfEnabled() }
        #expect(host.endpoint == nil && f.secrets.isEmpty)
        #expect(try Data(contentsOf: file) == invalid)
        host.close()
        #expect(throws: AgentErrorCode.storageError) { try f.host() }
    }

    @Test func constructionBindsTheLoadedLibraryWithoutEnablingOrWritingPreferences() throws {
        let f = try Fixture(); defer { f.cleanup() }
        _ = try f.library.createNote(content: "Neutral preserved 🐼")
        let before = try f.backupSnapshot(), host = try f.host(); defer { host.close() }
        #expect(host.endpoint == nil && f.applicationChecks == 1 && f.credentialReads == 0 && f.secrets.isEmpty)
        #expect(try AgentConnectionFile(parentDirectory: f.root).read() == nil)
        #expect(try f.backupSnapshot() == before)
        #expect(throws: AgentErrorCode.busy) { try f.host() }
        host.close()
        let next = try f.host(); defer { next.close() }
        #expect(next.libraryID == host.libraryID && next.endpoint == nil)
    }

    @Test func draftSettingsChoicesTrackHostLibraryWithoutStartingAccess() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        let model = try host.makeDraftSettingsModel()
        #expect(!model.accessEnabled && host.endpoint == nil)
        #expect(model.resourceChoices().isEmpty)
        let note = try f.library.createNote(content: "Visible choice 🐼")
        let target = AgentResourceReference(kind: .draft, id: note.id)
        #expect(model.resourceChoices().map(\.reference) == [target])
        #expect(model.resourceChoices().first?.title == note.title)
        #expect(!model.accessEnabled && host.endpoint == nil && f.secrets.isEmpty)
    }

    @Test func librarySettingsOffersActionsWithoutStartingAccess() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let action = DraftAction(name: "Scoped action", steps: [])
        try f.library.saveAction(action)
        let host = try f.host(); defer { host.close() }
        let model = try host.makeLibrarySettingsModel()
        #expect(model.resourceChoices().contains { $0.reference == .init(kind: .action, id: action.id) && $0.title == action.name })
        #expect(!model.accessEnabled && host.endpoint == nil && f.secrets.isEmpty)
        try f.library.deleteAction(action.id)
        #expect(model.resourceChoices().isEmpty)
    }

    @Test func pairingCommandQuotesPathsAndUsesTheLoadedLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly QA ' " + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Draftly.app")
        let executable = bundle.appendingPathComponent("Contents/Helpers/DraftlyAgent.app/Contents/MacOS/draftly-agent")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\"\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let id = UUID(), command = try #require(AgentLocalHost.pairingCommand(libraryID: id, stateDirectory: root, bundleURL: bundle))
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]; process.standardOutput = pipe
        try process.run(); process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0)
        #expect(output == "connect\n--name\nLocal agent\n--library\n\(id.uuidString)\n--state-parent\n\(root.path)\n")
        let connectionID = UUID()
        let json = try #require(AgentLocalHost.mcpConfiguration(connectionID: connectionID, libraryID: id, stateDirectory: root, bundleURL: bundle))
        let parsed = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let servers = try #require(parsed["mcpServers"] as? [String: [String: Any]])
        let server = try #require(servers["draftly-" + connectionID.uuidString.lowercased()])
        #expect(server["command"] as? String == executable.path)
        #expect(server["args"] as? [String] == ["mcp", "--connection", connectionID.uuidString, "--library", id.uuidString, "--state-parent", root.path])
        #expect(!json.contains("credential"))
        try FileManager.default.removeItem(at: executable)
        #expect(AgentLocalHost.pairingCommand(libraryID: id, stateDirectory: root, bundleURL: bundle) == nil)
        #expect(AgentLocalHost.mcpConfiguration(connectionID: connectionID, libraryID: id, stateDirectory: root, bundleURL: bundle) == nil)
    }

    @Test func settingsShowsSuspendedAccessAsOffAndCanResumeIt() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let first = try f.host()
        try first.setEnabledFromUserInterface(true)
        first.close()
        let host = try f.host(); defer { host.close() }
        let model = try host.makeLibrarySettingsModel()
        #expect(try host.connections.configurationForUserInterface().enabled)
        #expect(host.endpoint == nil && !model.accessEnabled)
        try model.setEnabled(true)
        #expect(host.endpoint != nil && model.accessEnabled)
        host.suspend(); model.refresh()
        #expect(!model.accessEnabled && host.endpoint == nil)
        try model.setEnabled(true)
        #expect(model.accessEnabled && host.endpoint != nil)
    }

    @Test func stopWorkClosesSessionsAndPendingPairingWithoutRevokingGrants() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        let model = try host.makeLibrarySettingsModel()
        try model.setEnabled(true)
        let record = try f.connect(host)
        let credential = try #require(f.secrets[record.id])
        let session = try host.service.authenticate(connectionID: record.id, credential: credential)
        let challenge = try host.pairing.request(clientName: "Pending client")
        let endpoint = try #require(host.endpoint)
        try model.stopWork()
        #expect(host.endpoint == nil && !model.accessEnabled)
        #expect(!FileManager.default.fileExists(atPath: endpoint))
        #expect(try host.pairing.state(challenge.id) == .invalidated)
        #expect(throws: AgentErrorCode.permissionDenied) { try host.service.authorizedLibraryID(for: session) }
        #expect(try host.connections.configurationForUserInterface().connections.contains { $0.id == record.id && !$0.revoked })
        try model.setEnabled(true)
        #expect(throws: AgentErrorCode.permissionDenied) { try host.service.authorizedLibraryID(for: session) }
        _ = try host.service.authenticate(connectionID: record.id, credential: credential)
    }

    @Test func operationReviewRequiresLiveHostAndStopWorkInvalidatesIt() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        let model = try host.makeLibrarySettingsModel()
        try model.setEnabled(true)
        let record = try host.connections.connectFromUserInterface(name: "Review test", libraryID: host.libraryID,
            capabilities: [.preferencesRead, .preferencesWrite], scope: .library)
        let request = AgentRequest(requestID: UUID(), libraryID: host.libraryID, operation: "preferences.update",
            expectedVersion: "version", parameters: ["items": .array([.object([
                "id": .string(SpotlightPreferences.enabledKey), "value": .bool(true)
            ])])])
        let effects = AgentApprovalStore.Effects(capabilities: [.preferencesWrite], targets: [],
            requiresLibraryScope: false, snapshot: ["value": .bool(true)])
        let review = try host.approvals.requestReview(request, connectionID: record.id, effects: effects)
        model.refresh()
        #expect(model.pendingOperationReviews.map(\.id) == [review.id])
        try model.stopWork()
        #expect(model.pendingOperationReviews.isEmpty)
        #expect(throws: AgentErrorCode.permissionDenied) { try model.decideOperation(review, approved: true) }
        try model.setEnabled(true)
        #expect(throws: AgentErrorCode.versionConflict) { try model.decideOperation(review, approved: true) }
    }

    @Test func humanDecisionInSettingsReleasesWaitingOperationOnce() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        let model = try host.makeLibrarySettingsModel()
        try model.setEnabled(true)
        let record = try host.connections.connectFromUserInterface(name: "Review test", libraryID: host.libraryID,
            capabilities: [.preferencesRead, .preferencesWrite], scope: .library)
        let request = AgentRequest(requestID: UUID(), libraryID: host.libraryID, operation: "preferences.update",
            expectedVersion: "version", parameters: ["items": .array([.object([
                "id": .string(SpotlightPreferences.enabledKey), "value": .bool(true)
            ])])])
        let effects = AgentApprovalStore.Effects(capabilities: [.preferencesWrite], targets: [],
            requiresLibraryScope: false, snapshot: ["value": .bool(true)])
        let task = Task { @MainActor in
            try await host.approvals.waitForApproval(request, connectionID: record.id, resolveEffects: { effects })
        }
        for _ in 0..<100 where model.pendingOperationReviews.isEmpty {
            await Task.yield(); model.refresh()
        }
        let review = try #require(model.pendingOperationReviews.first)
        try model.decideOperation(review, approved: true)
        try await task.value
        #expect(try host.approvals.statusForConnection(review.id, connectionID: record.id) == .consumed)
        #expect(throws: AgentErrorCode.permissionDenied) { try model.decideOperation(review, approved: true) }
    }

    @Test func stopWorkCancelsRunningAgentOperations() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        let model = try host.makeLibrarySettingsModel(); try model.setEnabled(true)
        let record = try host.connections.connectFromUserInterface(name: "Operation test", libraryID: host.libraryID,
            capabilities: [.actionsRun, .draftsRead], scope: .library)
        let currentGrant = try host.connections.grantForAuthenticatedConnection(record.id)
        let grant = try #require(currentGrant)
        var started = false, cancelled = false
        let operationID = try host.operations.start(grant: grant, targets: []) {
            started = true
            do { try await Task.sleep(for: .seconds(30)) } catch { cancelled = true }
            let report = ActionExecutionReport.notStarted(actionID: UUID(), reason: .cancelled, message: "Cancelled")
            return .init(report: report, noteID: nil, message: "Cancelled")
        }
        for _ in 0..<100 where !started { await Task.yield() }
        #expect(started)
        let session = try host.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let request = AgentRequest(requestID: UUID(), libraryID: host.libraryID, operation: "operations.get",
            targets: [.init(kind: .operation, id: operationID)])
        let response = try JSONDecoder().decode(AgentResponse.self,
            from: host.service.respond(to: JSONEncoder().encode(request), session: session))
        guard case .result = response.outcome else { Issue.record("Expected an operation snapshot"); return }
        try model.stopWork()
        for _ in 0..<1000 where !cancelled { await Task.yield() }
        #expect(cancelled)
    }

    @Test func authenticatedRequestsRecordMetadataWithoutChangingTheirResultOnStorageFailure() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        let model = try host.makeLibrarySettingsModel()
        try host.setEnabledFromUserInterface(true)
        let record = try f.connect(host)
        let session = try host.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        func status() throws -> AgentResponse {
            let request = AgentRequest(requestID: UUID(), libraryID: host.libraryID, operation: "server.status")
            return try JSONDecoder().decode(AgentResponse.self, from: host.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        let reply = try status()
        guard case .result = reply.outcome else { Issue.record("Expected a successful response: \(reply.outcome)"); return }
        for _ in 0..<100 where try host.recentActivity().isEmpty { await Task.yield() }
        let entries = try host.recentActivity()
        #expect(entries.count == 1 && entries[0].connectionID == record.id)
        #expect(entries[0].operation == "server.status" && entries[0].result == "success")
        model.refresh()
        #expect(model.activity == entries && model.activityError == nil)
        let deniedRequest = AgentRequest(requestID: UUID(), libraryID: host.libraryID, operation: "actions.list")
        let denied = try JSONDecoder().decode(AgentResponse.self, from: host.service.respond(to: JSONEncoder().encode(deniedRequest), session: session))
        #expect(denied.outcome == .error(.permissionDenied))
        for _ in 0..<100 where try host.recentActivity().count < 2 { await Task.yield() }
        #expect(try host.recentActivity().contains { $0.requestID == deniedRequest.requestID && $0.result == "permission_denied" })
        let file = f.root.appendingPathComponent("Agents/activity.json"), invalid = Data("invalid".utf8)
        try invalid.write(to: file)
        let next = try status()
        guard case .result = next.outcome else { Issue.record("Activity failure changed the response"); return }
        for _ in 0..<100 where host.activityRecordingError == nil { await Task.yield() }
        #expect(host.activityRecordingError == .storageError)
        model.refresh()
        #expect(model.activityError == .storageError)
        #expect(try Data(contentsOf: file) == invalid)
    }

    @Test func clearingActivityDiscardsQueuedRecordsButKeepsFutureRequests() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        let model = try host.makeLibrarySettingsModel()
        try host.setEnabledFromUserInterface(true)
        let record = try f.connect(host)
        let session = try host.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        func request() throws -> AgentResponse {
            let request = AgentRequest(requestID: UUID(), libraryID: host.libraryID, operation: "server.status")
            return try JSONDecoder().decode(AgentResponse.self, from: host.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        guard case .result = try request().outcome else { Issue.record("Expected success"); return }
        try model.clearActivity()
        for _ in 0..<10 { await Task.yield() }
        #expect(try host.recentActivity().isEmpty)
        guard case .result = try request().outcome else { Issue.record("Expected success"); return }
        for _ in 0..<100 where try host.recentActivity().isEmpty { await Task.yield() }
        #expect(try host.recentActivity().count == 1)
    }

    @Test func closingHostFlushesQueuedActivityBeforeReleasingTheLibrary() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host()
        try host.setEnabledFromUserInterface(true)
        let record = try f.connect(host)
        let session = try host.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let requests = (0..<20).map { _ in AgentRequest(requestID: UUID(), libraryID: host.libraryID, operation: "server.status") }
        for request in requests {
            let response = try JSONDecoder().decode(AgentResponse.self, from: host.service.respond(to: JSONEncoder().encode(request), session: session))
            guard case .result = response.outcome else { Issue.record("Expected success"); return }
        }
        host.close()
        let reopened = try f.host(); defer { reopened.close() }
        let saved = try reopened.recentActivity().filter { $0.result == "success" }
        #expect(Set(saved.map(\.requestID)) == Set(requests.map(\.requestID)))
    }

    @Test func activityListOnlyExposesTheCurrentConnectionAndGrant() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let first = try f.connect(host), second = try f.connect(host)
        let firstSecret = try #require(f.secrets[first.id]), secondSecret = try #require(f.secrets[second.id])
        let session = try host.service.authenticate(connectionID: first.id, credential: firstSecret)
        let other = try host.service.authenticate(connectionID: second.id, credential: secondSecret)
        func request(_ name: String, _ session: AgentCommandService.Session) throws -> AgentResponse {
            let request = AgentRequest(requestID: UUID(), libraryID: host.libraryID, operation: name)
            return try JSONDecoder().decode(AgentResponse.self, from: host.service.respond(to: JSONEncoder().encode(request), session: session))
        }
        let own = try request("server.status", session), hidden = try request("server.status", other)
        for _ in 0..<100 where try host.recentActivity().count < 2 { await Task.yield() }
        let result = try request("activity.list", session)
        guard case .result(.object(let page)) = result.outcome, case .array(let items) = page["items"] else {
            Issue.record("Expected activity page: \(result.outcome)"); return
        }
        #expect(items.count == 1)
        guard case .object(let item) = items[0] else { Issue.record("Expected activity entry"); return }
        #expect(item["requestID"] == .string(own.requestID.uuidString))
        #expect(item["requestID"] != .string(hidden.requestID.uuidString))
        _ = try host.connections.replaceGrantFromUserInterface(first.id, capabilities: [.draftsRead], scope: .library)
        let renewed = try host.service.authenticate(connectionID: first.id, credential: firstSecret)
        let fresh = try request("activity.list", renewed)
        guard case .result(.object(let freshPage)) = fresh.outcome else { Issue.record("Expected fresh activity page"); return }
        #expect(freshPage["items"] == .array([]))
    }

    @Test func closingAnEditorBeforePairingApprovalInvalidatesTheReview() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let preferences = try TestPreferences(prefix: "Draftly-Agent-Window-Grant-")
        defer { preferences.close() }
        let note = try f.library.createNote(content: "Editor draft")
        var dependencies = WindowDependencies(); dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        let window = WindowModel(library: f.library, dependencies: dependencies)
        window.editor.load(note, focusEditor: false)
        var windows = [window]
        let editors = AgentEditorRegistry(library: f.library, models: { windows })
        defer { editors.invalidate() }
        let host = try f.host(editors: editors); defer { host.close() }
        let model = try host.makeLibrarySettingsModel()
        try model.setEnabled(true)
        let challenge = try host.pairing.request(clientName: "Editor client")
        try model.beginPairing(challenge.id)
        let target = try #require(model.resourceChoices().first(where: { $0.reference.kind == .window })?.reference)
        model.draft?.targets = [target, .init(kind: .draft, id: note.id)]
        model.draft?.capabilities.insert(.editorRead)
        try model.preparePairingReview()
        windows.removeAll()
        #expect(throws: AgentErrorCode.notFound) { try model.approvePairing(codesMatch: true) }
        #expect(try host.pairing.state(challenge.id) == .invalidated)
        #expect(f.secrets.isEmpty && model.connections.isEmpty)
    }

    @Test func realPairingSettingsAndSocketReadsShareOneAuthorityAndLibrary() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let note = try f.library.createNote(content: "Allowed 🐼")
        _ = try f.library.createNote(content: "Hidden neutral")
        let before = try f.backupSnapshot(), host = try f.host(); defer { host.close() }
        let target = AgentResourceReference(kind: .draft, id: note.id)
        let model = try host.makeSettingsModel(choices: { [.init(reference: target, title: "Allowed 🐼")] }, initialTargets: { [target] })
        try model.setEnabled(true)
        let peer = try await AgentPairingClient.connect(path: #require(host.endpoint), name: "Neutral client", validateServer: { _ in })
        let challenge = await peer.challenge
        try model.beginPairing(#require(challenge.pairingID))
        model.cancelEditing()
        #expect(f.secrets.isEmpty)
        try model.beginPairing(#require(challenge.pairingID))
        #expect(model.availableCapabilities.contains(.actionsRead))
        #expect(!model.availableCapabilities.contains(.actionsRun))
        var unsupported = try #require(model.draft)
        unsupported.capabilities.insert(.actionsRun); model.draft = unsupported
        #expect(throws: AgentErrorCode.unavailable) { try model.preparePairingReview() }
        unsupported.capabilities.remove(.actionsRun); model.draft = unsupported
        try model.preparePairingReview()
        let record = try model.approvePairing(codesMatch: true)
        let decision = try await peer.poll()
        #expect(decision.connectionID == record.id && record.libraryID == host.libraryID)
        let client = try await f.client(host, record: record)
        #expect(await client.libraryID == host.libraryID)
        let response = try JSONDecoder().decode(AgentResponse.self, from: await client.request(JSONEncoder().encode(
            AgentRequest(requestID: UUID(), libraryID: nil, operation: "library.summary"))))
        guard case .result(.object(let values)) = response.outcome else { Issue.record("Expected scoped summary"); return }
        #expect(values["draftCount"] == .integer(1))
        #expect(try f.backupSnapshot() == before)
        try model.revoke(record.id)
        let denied = try JSONDecoder().decode(AgentResponse.self, from: await client.request(JSONEncoder().encode(
            AgentRequest(requestID: UUID(), libraryID: nil, operation: "server.status"))))
        #expect(denied.outcome == .error(.permissionDenied))
        await client.close(); await peer.close()
        try model.setEnabled(false)
        #expect(host.endpoint == nil && !model.accessEnabled)
    }

    @Test func reopenRetainsIdentityAndGrantsButDoesNotAutomaticallyListen() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let first = try f.host(); try first.setEnabledFromUserInterface(true)
        let oldPath = try #require(first.endpoint), record = try f.connect(first), id = first.libraryID
        first.close()
        #expect(!FileManager.default.fileExists(atPath: oldPath))
        let next = try f.host(); defer { next.close() }
        #expect(next.libraryID == id && next.endpoint == nil)
        #expect(try next.connections.configurationForUserInterface().connections.first?.id == record.id)
        #expect(try next.connections.configurationForUserInterface().enabled)
        try next.resumeIfEnabled()
        let client = try await f.client(next, record: record)
        #expect(await client.libraryID == id)
        await client.close()
    }

    @Test func closeStopsTheSocketAndInvalidatesRetainedServicesBeforeReleasingOwnership() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); try host.setEnabledFromUserInterface(true)
        let record = try f.connect(host), service = host.service, pairing = host.pairing
        let session = try service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let challenge = try pairing.request(clientName: "Neutral")
        let path = try #require(host.endpoint)
        host.close(); host.close()
        #expect(host.endpoint == nil && !FileManager.default.fileExists(atPath: path))
        #expect(try f.request("server.status", session: session, service: service).outcome == .error(.cancelled))
        #expect(try pairing.state(challenge.id) == .invalidated)
        #expect(throws: AgentErrorCode.cancelled) { try host.resumeIfEnabled() }
        let replacement = try f.host(); defer { replacement.close() }
        #expect(replacement.libraryID == host.libraryID)
    }

    @Test func discardingTheHostDoesNotLeaveRetainedSettingsOrSessionsActive() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var host: AgentLocalHost? = try f.host()
        try #require(host).setEnabledFromUserInterface(true)
        let path = try #require(host?.endpoint), service = try #require(host?.service)
        let record = try f.connect(#require(host))
        let session = try service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let model = try #require(host).makeSettingsModel(choices: { [] })
        weak var old = host
        host = nil
        #expect(old == nil && !FileManager.default.fileExists(atPath: path))
        #expect(try f.request("server.status", session: session, service: service).outcome == .error(.cancelled))
        #expect(throws: AgentErrorCode.cancelled) { try model.setEnabled(true) }
        let replacement = try f.host(); defer { replacement.close() }
    }

    @Test func ownershipLossStopsTheTransportAndInvalidatesPairingWithoutDroppingTheLeaseEarly() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let challenge = try host.pairing.request(clientName: "Neutral"), path = try #require(host.endpoint)
        let location = try AgentLibraryLocation(library: f.library)
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("Agents").appendingPathComponent(location.locationKey + ".identity.json"))
        #expect(throws: AgentErrorCode.versionConflict) { try host.service.permitsTransportStart() }
        #expect(host.endpoint == nil && !FileManager.default.fileExists(atPath: path))
        #expect(try host.pairing.state(challenge.id) == .invalidated)
        #expect(throws: AgentErrorCode.busy) { try f.host() }
    }

    @Test func lockSuspendsAndExplicitResumeCreatesANewTransportWithoutChangingThePreference() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let path = try #require(host.endpoint)
        f.locked = true
        #expect(throws: AgentErrorCode.permissionDenied) { try host.resumeIfEnabled() }
        #expect(host.endpoint == nil && !FileManager.default.fileExists(atPath: path))
        f.locked = false
        #expect(try host.connections.configurationForUserInterface().enabled)
        try host.resumeIfEnabled()
        #expect(host.endpoint != nil && host.endpoint != path)
    }

    @Test func failedListenerCreationRestoresADisabledPreferenceAndLeavesNoEndpoint() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(socketParent: f.root.appendingPathComponent("missing")); defer { host.close() }
        #expect(throws: AgentErrorCode.invalidInput) { try host.setEnabledFromUserInterface(true) }
        #expect(host.endpoint == nil && f.secrets.isEmpty)
        #expect(try !host.connections.configurationForUserInterface().enabled)
    }

    @Test func unprovisionedApplicationIsRejectedBeforeAnyAgentStateIsCreated() throws {
        let f = try Fixture(); defer { f.cleanup() }
        #expect(throws: AgentErrorCode.permissionDenied) {
            try AgentLocalHost(library: f.library, appVersion: "Neutral QA", isLocked: { false },
                pendingEditorGeneration: { _ in "" }, resolveTargets: { $0 })
        }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Agents").path))
    }

    @Test func unreadableMetadataDoesNotRepairItOrLeaveOwnershipHeldAfterFailedConstruction() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let first = try f.host(); try first.setEnabledFromUserInterface(false); first.close()
        let file = f.root.appendingPathComponent("Agents/connections.json"), invalid = Data("not metadata".utf8)
        try invalid.write(to: file)
        #expect(throws: AgentErrorCode.storageError) { try f.host() }
        #expect(try Data(contentsOf: file) == invalid)
        let lease = try AgentHostLease(location: AgentLibraryLocation(library: f.library)); lease.close()
    }

    @Test func temporaryIdentityContentionKeepsTheBrokerAndAuthenticatedSession() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let record = try f.connect(host), path = try #require(host.endpoint)
        let client = try await f.client(host, record: record)
        let location = try AgentLibraryLocation(library: f.library)
        let directory = try AgentStateDirectory(parentDirectory: f.root)
        let lock = try directory.acquireLock(location.locationKey + ".identity.lock")
        defer { lock.release() }
        let request = try JSONEncoder().encode(AgentRequest(requestID: UUID(), libraryID: nil, operation: "server.status"))
        let busy = try JSONDecoder().decode(AgentResponse.self, from: await client.request(request))
        #expect(busy.outcome == .error(.busy) && host.endpoint == path)
        lock.release()
        let next = try JSONDecoder().decode(AgentResponse.self, from: await client.request(request))
        guard case .result = next.outcome else { Issue.record("Expected recovered session"); return }
        #expect(host.endpoint == path)
        await client.close()
    }

    @Test func failedDisableStillStopsTheTransportWithoutRepairingUnreadableMetadata() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let record = try f.connect(host), service = host.service
        let session = try service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let path = try #require(host.endpoint), file = f.root.appendingPathComponent("Agents/connections.json")
        let saved = try Data(contentsOf: file), invalid = Data("not metadata".utf8)
        try invalid.write(to: file)
        #expect(throws: AgentErrorCode.storageError) { try host.setEnabledFromUserInterface(false) }
        #expect(host.endpoint == nil && !FileManager.default.fileExists(atPath: path))
        #expect(try Data(contentsOf: file) == invalid)
        try saved.write(to: file)
        #expect(try f.request("server.status", session: session, service: service).outcome == .error(.permissionDenied))
        try host.resumeIfEnabled()
        #expect(host.endpoint != nil)
    }

    @Test func failedEnableCompensationReportsUncertaintyWithoutClaimingADisabledPreference() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        let model = try host.makeSettingsModel(choices: { [] })
        let file = f.root.appendingPathComponent("Agents/connections.json")
        f.onApplicationCheck = { [unowned f] in
            if f.applicationChecks == 3 {
                try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: file.path)
                throw AgentErrorCode.unavailable
            }
        }
        #expect(throws: AgentErrorCode.outcomeUnknown) { try model.setEnabled(true) }
        #expect(host.endpoint == nil && model.lastError == .outcomeUnknown && !model.readable)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(try host.connections.configurationForUserInterface().enabled)
        #expect(f.secrets.isEmpty)
    }

    @Test func lostApplicationReadinessStopsAnExistingListener() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let host = try f.host(); defer { host.close() }
        try host.setEnabledFromUserInterface(true)
        let path = try #require(host.endpoint)
        f.applicationError = .permissionDenied
        #expect(throws: AgentErrorCode.permissionDenied) { try host.setEnabledFromUserInterface(true) }
        #expect(host.endpoint == nil && !FileManager.default.fileExists(atPath: path))
    }
    @Test func backupPreservationIgnoresNoteFetchOrderButDetectsAllChangedPayload() throws {
        let f = try Fixture(); defer { f.cleanup() }
        _ = try f.library.createNote(content: "Neutral alpha 🐼")
        _ = try f.library.createNote(content: "Neutral beta café")
        let expected = try f.backupSnapshot()
        guard case .object(var root) = try JSONDecoder().decode(AgentJSONValue.self, from: f.library.backupData()),
              case .array(let notes) = root["notes"] else { throw AgentErrorCode.storageError }
        root["notes"] = .array(notes.reversed())
        #expect(try f.backupSnapshot(JSONEncoder().encode(AgentJSONValue.object(root))) == expected)
        try f.library.reload()
        #expect(try f.backupSnapshot() == expected)
        for (key, changed) in [("content", AgentJSONValue.string("Changed")), ("id", .string(UUID().uuidString)),
                               ("tags", .array([.string("changed")])), ("modifiedAt", .integer(0)),
                               ("unknownImported", .object(["keep": .bool(true)]))] {
            var changedNotes = notes
            guard case .object(var note) = changedNotes[0] else { throw AgentErrorCode.storageError }
            note[key] = changed; changedNotes[0] = .object(note); root["notes"] = .array(changedNotes)
            #expect(try f.backupSnapshot(JSONEncoder().encode(AgentJSONValue.object(root))) != expected)
        }
    }

}
