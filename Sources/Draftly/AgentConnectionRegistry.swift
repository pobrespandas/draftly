import Foundation
import CryptoKit
import AgentContracts

// Human-only management. The transport must not register these mutation methods.
@MainActor final class AgentConnectionRegistry {
    enum DisplayStatus { case active, paused, inactive, revoked, needsReview }

    func displayStatusFromUserInterface(_ record: AgentConnectionRecord, enabled: Bool) -> DisplayStatus {
        if record.revoked { return .revoked }
        if !isLive(record) { return .inactive }
        if blocked.contains(record.id) { return .needsReview }
        if !enabled || disabledUntilCommit { return .paused }
        return .active
    }

    struct MetadataAccess {
        let read: () throws -> Data?
        let replace: (Data, Data?) throws -> Void
    }
    struct CredentialAccess {
        let read: (UUID) throws -> Data?
        // Create-only. A duplicate account must fail without overwriting it.
        let create: (UUID, Data) throws -> Void
        let remove: (UUID) throws -> Void
    }
    struct Revocation {
        let credentialCleanupPending: Bool
    }

    private let metadata: MetadataAccess
    private let credentials: CredentialAccess
    private let now: () -> Date
    private let newCredential: () throws -> Data
    private let authorityChanged: (UUID) -> Void
    private var blocked: Set<UUID> = []
    private var disabledUntilCommit = false

    init(metadata: MetadataAccess, credentials: CredentialAccess, now: @escaping () -> Date = Date.init,
         newCredential: @escaping () throws -> Data = {
             SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
         }, authorityChanged: @escaping (UUID) -> Void) {
        self.metadata = metadata; self.credentials = credentials; self.now = now
        self.newCredential = newCredential; self.authorityChanged = authorityChanged
    }

    func configurationForUserInterface() throws -> AgentConnectionMetadata { try snapshot().configuration }

    func permitsTransportStart() throws -> Bool { try !disabledUntilCommit && snapshot().configuration.enabled }

    func setEnabledFromUserInterface(_ enabled: Bool) throws {
        let old = try snapshot()
        var updated = old.configuration
        updated.enabled = enabled
        disabledUntilCommit = true
        for record in updated.connections { authorityChanged(record.id) }
        try commit(updated.encoded(), expected: old.data)
        disabledUntilCommit = !enabled
    }

    func connectFromUserInterface(name: String, libraryID: UUID, capabilities: Set<AgentCapability> = [.draftsRead],
                                  scope: AgentResourceScope = .resources([]), expiresAt: Date? = nil,
                                  renewable: Bool = false) throws -> AgentConnectionRecord {
        let old = try snapshot(), timestamp = now()
        let expiry = expiresAt ?? timestamp.addingTimeInterval(3600)
        guard AgentConnectionMetadata.validName(name), timestamp.timeIntervalSinceReferenceDate.isFinite,
              expiry.timeIntervalSinceReferenceDate.isFinite, expiry > timestamp else { throw AgentErrorCode.invalidInput }
        guard old.configuration.connections.count < 256 else { throw AgentErrorCode.busy }
        let kind: AgentConnectionRecord.ScopeKind
        let targets: Set<AgentResourceReference>
        switch scope { case .library: kind = .library; targets = []
        case .resources(let values): kind = .resources; targets = values }
        let record = AgentConnectionRecord(id: UUID(), name: name, createdAt: timestamp, grantID: UUID(), libraryID: libraryID,
            expiresAt: expiry, revoked: false, renewable: renewable,
            capabilities: capabilities.sorted { $0.rawValue < $1.rawValue }, scopeKind: kind,
            resources: targets.sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) })
        var updated = old.configuration
        updated.connections.append(record)
        let data = try updated.encoded(), credential = try newCredential()
        guard credential.count == 32 else { throw AgentErrorCode.storageError }
        try credentials.create(record.id, credential)
        do { try commit(data, expected: old.data) }
        catch {
            // An unreferenced or revoked credential cannot authorize a connection.
            blocked.insert(record.id)
            do { try credentials.remove(record.id) }
            catch { throw AgentErrorCode.outcomeUnknown }
            throw error
        }
        return record
    }

    func grantForAuthenticatedConnection(_ id: UUID) throws -> AgentGrant? {
        guard !disabledUntilCommit, !blocked.contains(id) else { return nil }
        let value = try snapshot().configuration
        guard value.enabled, let record = value.connections.first(where: { $0.id == id }), isLive(record) else { return nil }
        return record.grant
    }

    func authenticate(_ id: UUID, candidate: Data, libraryID: UUID) throws -> AgentGrant {
        guard candidate.count == 32, !disabledUntilCommit, !blocked.contains(id) else { throw AgentErrorCode.permissionDenied }
        let old = try snapshot()
        guard old.configuration.enabled,
              let record = old.configuration.connections.first(where: { $0.id == id }),
              record.libraryID == libraryID, isLive(record),
              let expected = try credentials.read(id), expected.count == 32 else { throw AgentErrorCode.permissionDenied }
        let message = Data("Draftly local credential comparison v1".utf8)
        let proof = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: candidate))
        guard HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: message, using: SymmetricKey(data: expected)) else {
            throw AgentErrorCode.permissionDenied
        }
        guard try metadata.read() == old.data, !disabledUntilCommit, !blocked.contains(id), isLive(record) else {
            throw AgentErrorCode.permissionDenied
        }
        return record.grant
    }

    func revokeFromUserInterface(_ id: UUID) throws -> Revocation {
        let old = try snapshot()
        guard let index = old.configuration.connections.firstIndex(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
        blocked.insert(id); authorityChanged(id)
        var updated = old.configuration
        updated.connections[index].revoked = true
        updated.connections[index].grantID = UUID()
        do { try commit(updated.encoded(), expected: old.data) }
        catch {
            // Keep the connection blocked in this process even if both stores fail.
            do { try credentials.remove(id) }
            catch { throw AgentErrorCode.outcomeUnknown }
            throw error
        }
        do { try credentials.remove(id); return Revocation(credentialCleanupPending: false) }
        catch { return Revocation(credentialCleanupPending: true) }
    }

    func replaceGrantFromUserInterface(_ id: UUID, capabilities: Set<AgentCapability>, scope: AgentResourceScope,
                                       expiresAt: Date? = nil, renewable: Bool = false) throws -> AgentConnectionRecord {
        let old = try snapshot()
        guard let index = old.configuration.connections.firstIndex(where: { $0.id == id }),
              !old.configuration.connections[index].revoked else { throw AgentErrorCode.notFound }
        let expiry = expiresAt ?? now().addingTimeInterval(3600)
        guard expiry.timeIntervalSinceReferenceDate.isFinite, expiry > now() else { throw AgentErrorCode.invalidInput }
        blocked.insert(id); authorityChanged(id)
        guard let credential = try credentials.read(id), credential.count == 32 else { throw AgentErrorCode.permissionDenied }
        var updated = old.configuration
        updated.connections[index].grantID = UUID()
        updated.connections[index].capabilities = capabilities.sorted { $0.rawValue < $1.rawValue }
        updated.connections[index].expiresAt = expiry
        updated.connections[index].renewable = renewable
        switch scope {
        case .library: updated.connections[index].scopeKind = .library; updated.connections[index].resources = []
        case .resources(let targets):
            updated.connections[index].scopeKind = .resources
            updated.connections[index].resources = targets.sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }
        }
        do { try commit(updated.encoded(), expected: old.data) }
        catch {
            do { try credentials.remove(id) }
            catch { throw AgentErrorCode.outcomeUnknown }
            throw error
        }
        blocked.remove(id)
        return updated.connections[index]
    }

    private func isLive(_ record: AgentConnectionRecord) -> Bool {
        let timestamp = now()
        return !record.revoked && timestamp.timeIntervalSinceReferenceDate.isFinite
            && record.createdAt <= timestamp && record.expiresAt > timestamp
    }

    private func commit(_ data: Data, expected: Data?) throws {
        try metadata.replace(data, expected)
        guard try metadata.read() == data else { throw AgentErrorCode.storageError }
    }

    private func snapshot() throws -> (configuration: AgentConnectionMetadata, data: Data?) {
        let data = try metadata.read()
        do { return (try AgentConnectionMetadata.decode(data), data) }
        catch { throw AgentErrorCode.storageError }
    }
}
