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
        var locked = false
        var applicationError: AgentErrorCode?
        var onApplicationCheck: (() throws -> Void)?
        var secrets: [UUID: Data] = [:]
        var credentialReads = 0
        var applicationChecks = 0

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Local-Host-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            library = try LibraryStore(directory: root, seed: false)
        }
        func cleanup() {
            library.container.viewContext.reset()
            for store in library.container.persistentStoreCoordinator.persistentStores {
                try? library.container.persistentStoreCoordinator.remove(store)
            }
            try? FileManager.default.removeItem(at: root)
        }
        func host(socketParent: URL = FileManager.default.temporaryDirectory) throws -> AgentLocalHost {
            try AgentLocalHost(library: library, appVersion: "Neutral QA", isLocked: { [unowned self] in self.locked },
                pendingEditorGeneration: { _ in "" }, resolveTargets: { [unowned self] targets in
                    Set(targets.filter { target in target.kind == .draft && self.library.notes.contains { $0.id == target.id } })
                }, socketParentDirectory: socketParent,
                credentials: .init(read: { [unowned self] id in self.credentialReads += 1; return self.secrets[id] },
                    create: { [unowned self] id, value in
                        guard self.secrets[id] == nil else { throw AgentErrorCode.versionConflict }
                        self.secrets[id] = value
                    }, remove: { [unowned self] in self.secrets.removeValue(forKey: $0) }),
                validateApplication: { [unowned self] in
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
