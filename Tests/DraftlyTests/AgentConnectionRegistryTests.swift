import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Local agent connections and credentials") @MainActor
struct AgentConnectionRegistryTests {
    @MainActor private final class Fixture {
        var bytes: Data?
        var secrets: [UUID: Data] = [:]
        var failWrite = false
        var discardWrite = false
        var failDelete = false
        var failCreate = false
        var secretReads = 0
        var deletions = 0
        var mutations: [UUID] = []
        var serial: UInt8 = 0
        var wall = Date(timeIntervalSince1970: 1_700_000_000)
        var onSecretRead: (() throws -> Void)?
        lazy var registry = makeRegistry()
        func makeRegistry() -> AgentConnectionRegistry {
            AgentConnectionRegistry(metadata: .init(read: { [unowned self] in self.bytes }, replace: { [unowned self] value, expected in
                if self.failWrite { throw AgentErrorCode.storageError }
                guard self.bytes == expected else { throw AgentErrorCode.versionConflict }
                if !self.discardWrite { self.bytes = value }
            }), credentials: .init(read: { [unowned self] id in
                self.secretReads += 1; try self.onSecretRead?(); return self.secrets[id]
            }, create: { [unowned self] id, value in
                guard !self.failCreate, self.secrets[id] == nil else { throw AgentErrorCode.storageError }
                self.secrets[id] = value
            }, remove: { [unowned self] id in
                self.deletions += 1
                if self.failDelete { throw AgentErrorCode.storageError }
                self.secrets.removeValue(forKey: id)
            }), now: { [unowned self] in self.wall }, newCredential: { [unowned self] in
                self.serial &+= 1; return Data(repeating: self.serial, count: 32)
            }, authorityChanged: { [unowned self] in self.mutations.append($0) })
        }
        func connect() throws -> AgentConnectionRecord {
            try registry.connectFromUserInterface(name: "QA 🐼", libraryID: UUID())
        }
        func authenticate(_ record: AgentConnectionRecord, using registry: AgentConnectionRegistry? = nil) throws -> AgentGrant {
            try (registry ?? self.registry).authenticate(record.id, candidate: #require(secrets[record.id]), libraryID: record.libraryID)
        }
    }

    @Test func newAccessStartsDisabledAndGrantsDefaultToSelectedReadOnly() throws {
        let fixture = Fixture()
        #expect(try !fixture.registry.configurationForUserInterface().enabled)
        #expect(fixture.bytes == nil)
        let record = try fixture.connect()
        #expect(record.grant.capabilities == [.draftsRead] && record.grant.scope == .resources([]))
        #expect(record.expiresAt == fixture.wall.addingTimeInterval(3600) && !record.renewable)
        #expect(throws: AgentErrorCode.permissionDenied) { try fixture.authenticate(record) }
        #expect(fixture.secretReads == 0)
        try fixture.registry.setEnabledFromUserInterface(true)
        #expect(try fixture.authenticate(record).grantID == record.grantID)
        #expect(fixture.secretReads == 1)
    }

    @Test func reloadKeepsGrantIdentityAndNeverStoresTheCredentialInMetadata() throws {
        let fixture = Fixture(), first = try fixture.connect(), second = try fixture.connect()
        #expect(fixture.secrets[first.id] != fixture.secrets[second.id])
        try fixture.registry.setEnabledFromUserInterface(true)
        let reopened = fixture.makeRegistry()
        #expect(try fixture.authenticate(first, using: reopened).grantID == first.grantID)
        let text = String(decoding: try #require(fixture.bytes), as: UTF8.self)
        #expect(!text.contains(try #require(fixture.secrets[first.id]).base64EncodedString()))
        #expect(!text.contains("credential"))
        #expect(try reopened.configurationForUserInterface().connections.map(\.id) == [first.id, second.id])
    }

    @Test func unknownWrongExpiredAndRevokedAuthenticationFailWithoutLeakingSecrets() throws {
        let fixture = Fixture(), record = try fixture.connect()
        try fixture.registry.setEnabledFromUserInterface(true)
        #expect(throws: AgentErrorCode.permissionDenied) {
            try fixture.registry.authenticate(UUID(), candidate: Data(repeating: 1, count: 32), libraryID: record.libraryID)
        }
        #expect(throws: AgentErrorCode.permissionDenied) {
            try fixture.registry.authenticate(record.id, candidate: Data(), libraryID: record.libraryID)
        }
        #expect(throws: AgentErrorCode.permissionDenied) {
            try fixture.registry.authenticate(record.id, candidate: Data(repeating: 0, count: 32), libraryID: UUID())
        }
        #expect(fixture.secretReads == 0)
        #expect(throws: AgentErrorCode.permissionDenied) {
            try fixture.registry.authenticate(record.id, candidate: Data(repeating: 0, count: 32), libraryID: record.libraryID)
        }
        fixture.wall = record.expiresAt
        #expect(throws: AgentErrorCode.permissionDenied) { try fixture.authenticate(record) }
        #expect(try fixture.registry.grantForAuthenticatedConnection(record.id) == nil)
    }

    @Test func revocationCommitsBeforeCredentialCleanupAndSurvivesReload() throws {
        let fixture = Fixture(), record = try fixture.connect()
        try fixture.registry.setEnabledFromUserInterface(true)
        fixture.failDelete = true
        let result = try fixture.registry.revokeFromUserInterface(record.id)
        #expect(result.credentialCleanupPending && fixture.secrets[record.id] != nil)
        #expect(fixture.mutations.contains(record.id))
        #expect(try fixture.registry.grantForAuthenticatedConnection(record.id) == nil)
        let reopened = fixture.makeRegistry()
        #expect(throws: AgentErrorCode.permissionDenied) { try fixture.authenticate(record, using: reopened) }
        #expect(try reopened.configurationForUserInterface().connections.first?.revoked == true)
    }

    @Test func failedCreationCleansUpOrphansAndSilentDiscardDoesNotReturnSuccess() throws {
        for discard in [false, true] {
            let fixture = Fixture()
            fixture.failWrite = !discard; fixture.discardWrite = discard
            #expect(throws: AgentErrorCode.storageError) { try fixture.connect() }
            #expect(fixture.secrets.isEmpty && fixture.deletions == 1 && fixture.bytes == nil)
        }
        let uncertain = Fixture(); uncertain.failWrite = true; uncertain.failDelete = true
        #expect(throws: AgentErrorCode.outcomeUnknown) { try uncertain.connect() }
        #expect(uncertain.bytes == nil && uncertain.secrets.count == 1)
        let denied = Fixture(); denied.failCreate = true
        #expect(throws: AgentErrorCode.storageError) { try denied.connect() }
        #expect(denied.bytes == nil && denied.secrets.isEmpty)
    }

    @Test func failedRevocationBlocksImmediatelyAndDoesNotPromiseDurability() throws {
        let fixture = Fixture(), record = try fixture.connect()
        try fixture.registry.setEnabledFromUserInterface(true)
        fixture.failWrite = true; fixture.failDelete = true
        #expect(throws: AgentErrorCode.outcomeUnknown) { try fixture.registry.revokeFromUserInterface(record.id) }
        #expect(throws: AgentErrorCode.permissionDenied) { try fixture.authenticate(record) }
        #expect(try fixture.registry.grantForAuthenticatedConnection(record.id) == nil)
        fixture.failWrite = false
        try fixture.registry.setEnabledFromUserInterface(true)
        #expect(throws: AgentErrorCode.permissionDenied) { try fixture.authenticate(record) }
        fixture.failDelete = false
        #expect(try !fixture.registry.revokeFromUserInterface(record.id).credentialCleanupPending)
        #expect(fixture.secrets[record.id] == nil)
    }

    @Test func replacementRotatesAuthorizationButKeepsTheConnectionCredential() throws {
        let fixture = Fixture(), record = try fixture.connect()
        try fixture.registry.setEnabledFromUserInterface(true)
        let originalSecret = fixture.secrets[record.id]
        let draft = AgentResourceReference(kind: .draft, id: UUID())
        let replacement = try fixture.registry.replaceGrantFromUserInterface(record.id,
            capabilities: [.draftsRead, .draftsWrite], scope: .resources([draft]), renewable: true)
        #expect(replacement.grantID != record.grantID && replacement.id == record.id)
        #expect(replacement.grant.scope == .resources([draft]) && replacement.renewable)
        #expect(fixture.secrets[record.id] == originalSecret)
        #expect(try fixture.authenticate(replacement).grantID == replacement.grantID)
        #expect(fixture.mutations.contains(record.id))
    }

    @Test func metadataChangesDuringCredentialReadCannotAuthenticateAStaleGrant() throws {
        let fixture = Fixture(), record = try fixture.connect()
        try fixture.registry.setEnabledFromUserInterface(true)
        fixture.onSecretRead = {
            var data = try AgentConnectionMetadata.decode(fixture.bytes)
            data.connections[0].revoked = true
            fixture.bytes = try data.encoded()
        }
        #expect(throws: AgentErrorCode.permissionDenied) { try fixture.authenticate(record) }
    }

    @Test func clockRollbackDuringCredentialReadCannotReturnALiveGrant() throws {
        let fixture = Fixture(), record = try fixture.connect()
        try fixture.registry.setEnabledFromUserInterface(true)
        fixture.onSecretRead = { fixture.wall = fixture.wall.addingTimeInterval(-1) }
        #expect(throws: AgentErrorCode.permissionDenied) { try fixture.authenticate(record) }
    }

    @Test func unsupportedMetadataAndUnknownPermissionFieldsFailClosedWithoutOverwrite() throws {
        let fixture = Fixture(), record = try fixture.connect()
        try fixture.registry.setEnabledFromUserInterface(true)
        let original = try #require(fixture.bytes)
        for change in 0..<3 {
            var root = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
            if change == 0 { root["version"] = 99 }
            else {
                var records = try #require(root["connections"] as? [[String: Any]])
                if change == 1 { records[0]["capabilities"] = ["future.unrestricted"] }
                else { records[0]["nativePolicy"] = ["unknownRestriction": true] }
                root["connections"] = records
            }
            fixture.bytes = try JSONSerialization.data(withJSONObject: root)
            let invalid = fixture.bytes
            #expect(throws: AgentErrorCode.storageError) { try fixture.registry.configurationForUserInterface() }
            #expect(throws: AgentErrorCode.storageError) { try fixture.authenticate(record) }
            #expect(fixture.bytes == invalid)
        }
    }

    @Test func realPrivateFileSupportsAReopenedRegistryWithStableGrantIdentity() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Connection-Integration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: parent) }
        let file = try AgentConnectionFile(parentDirectory: parent)
        var secrets: [UUID: Data] = [:]
        let credentials = AgentConnectionRegistry.CredentialAccess(read: { secrets[$0] }, create: { secrets[$0] = $1 }, remove: { secrets.removeValue(forKey: $0) })
        let metadata = AgentConnectionRegistry.MetadataAccess(read: file.read, replace: file.replace)
        let registry = AgentConnectionRegistry(metadata: metadata, credentials: credentials, authorityChanged: { _ in })
        let record = try registry.connectFromUserInterface(name: "Local QA", libraryID: UUID())
        try registry.setEnabledFromUserInterface(true)
        let reopened = AgentConnectionRegistry(metadata: metadata, credentials: credentials, authorityChanged: { _ in })
        let authenticated = try reopened.authenticate(record.id, candidate: #require(secrets[record.id]), libraryID: record.libraryID)
        #expect(authenticated.grantID == record.grantID)
        #expect(authenticated.expiresAt == record.expiresAt)
    }
    @Test func failedDisableAndFailedGrantChangesRemainBlockedInTheCurrentProcess() throws {
        let fixture = Fixture(), record = try fixture.connect()
        try fixture.registry.setEnabledFromUserInterface(true)
        fixture.failWrite = true
        #expect(throws: AgentErrorCode.storageError) { try fixture.registry.setEnabledFromUserInterface(false) }
        #expect(throws: AgentErrorCode.permissionDenied) { try fixture.authenticate(record) }
        fixture.failWrite = false
        try fixture.registry.setEnabledFromUserInterface(true)
        #expect(try fixture.authenticate(record).grantID == record.grantID)
        fixture.failWrite = true
        #expect(throws: AgentErrorCode.storageError) {
            try fixture.registry.replaceGrantFromUserInterface(record.id, capabilities: [], scope: .resources([]))
        }
        #expect(fixture.secrets[record.id] == nil)
        #expect(try fixture.registry.grantForAuthenticatedConnection(record.id) == nil)
    }

}
