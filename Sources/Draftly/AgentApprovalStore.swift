import Foundation
import CryptoKit
import AgentContracts

// App-owned approvals. No transport operation may call the human-decision methods.
@MainActor final class AgentApprovalStore {
    enum State: Equatable { case pending, approved, denied, consumed, cancelled, expired, invalidated }

    struct Effects {
        let capabilities: Set<AgentCapability>
        let targets: Set<AgentResourceReference>
        let requiresLibraryScope: Bool
        // A fresh snapshot from the trusted effect resolver, never request-supplied authority.
        let snapshot: [String: AgentJSONValue]
    }

    struct Review {
        let id: UUID
        let connectionID: UUID
        let operation: String
        let targets: [AgentResourceReference]
        let fingerprint: String
        let expiresAt: Date
    }

    private struct Entry {
        let review: Review
        let requestID: UUID
        let libraryID: UUID
        let grantID: UUID
        let grantFingerprint: String
        let issuedAt: Date
        let issuedUptime: TimeInterval
        var state: State
    }

    private let epoch: UUID
    private let key = SymmetricKey(size: .bits256)
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let currentGrant: (UUID) -> AgentGrant?
    private let isLocked: () -> Bool
    private let capacity: Int
    private var entries: [UUID: Entry] = [:]
    static let lifetime: TimeInterval = 300
    // The binding budget does not reduce the wire limit.
    private static let maximumBindingBytes = AgentRequest.maximumBytes * 4

    init(epoch: UUID = UUID(), capacity: Int = 256,
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         currentGrant: @escaping (UUID) -> AgentGrant?, isLocked: @escaping () -> Bool) {
        self.epoch = epoch; self.capacity = max(1, capacity)
        self.now = now; self.uptime = uptime; self.currentGrant = currentGrant; self.isLocked = isLocked
    }

    func requestReview(_ request: AgentRequest, connectionID: UUID, effects: Effects) throws -> Review {
        let binding = try binding(request, connectionID: connectionID, effects: effects)
        refreshEntries()
        if let existing = entries.values.first(where: { $0.review.connectionID == connectionID && $0.requestID == request.requestID }) {
            guard existing.review.fingerprint == binding.fingerprint else {
                invalidate(existing.review.id)
                throw AgentErrorCode.versionConflict
            }
            try requireUsable(existing, approved: false)
            return existing.review
        }
        makeRoom()
        guard entries.count < capacity else { throw AgentErrorCode.busy }
        let wall = now(), elapsed = uptime()
        guard wall.timeIntervalSince1970.isFinite, elapsed.isFinite else { throw AgentErrorCode.unavailable }
        let review = Review(id: UUID(), connectionID: connectionID, operation: request.operation,
            targets: request.targets, fingerprint: binding.fingerprint,
            expiresAt: min(wall.addingTimeInterval(Self.lifetime), binding.grant.expiresAt))
        entries[review.id] = Entry(review: review, requestID: request.requestID, libraryID: binding.grant.libraryID,
            grantID: binding.grant.grantID, grantFingerprint: binding.grantFingerprint,
            issuedAt: wall, issuedUptime: elapsed, state: .pending)
        return review
    }

    func approveFromUserInterface(_ id: UUID, reviewedFingerprint: String) throws {
        let entry = try liveEntry(id)
        guard entry.review.fingerprint == reviewedFingerprint else {
            invalidate(id); throw AgentErrorCode.versionConflict
        }
        try requireUsable(entry, approved: false)
        entries[id]?.state = .approved
    }

    func denyFromUserInterface(_ id: UUID) throws {
        let entry = try liveEntry(id)
        try requireUsable(entry, approved: false)
        entries[id]?.state = .denied
    }

    func consume(_ id: UUID, request: AgentRequest, connectionID: UUID, effects: Effects) throws {
        guard entries[id]?.review.connectionID == connectionID else { throw AgentErrorCode.notFound }
        let entry = try liveEntry(id)
        let current = try binding(request, connectionID: connectionID, effects: effects)
        guard current.fingerprint == entry.review.fingerprint else {
            invalidate(id); throw AgentErrorCode.versionConflict
        }
        try requireUsable(entry, approved: true)
        entries[id]?.state = .consumed
    }

    func cancelFromConnection(_ id: UUID, connectionID: UUID) throws {
        guard entries[id]?.review.connectionID == connectionID else { throw AgentErrorCode.notFound }
        let entry = try liveEntry(id)
        try requireUsable(entry, approved: false)
        entries[id]?.state = .cancelled
    }

    func statusForConnection(_ id: UUID, connectionID: UUID) throws -> State {
        guard entries[id]?.review.connectionID == connectionID else { throw AgentErrorCode.notFound }
        return try liveEntry(id).state
    }

    func invalidateConnection(_ connectionID: UUID) {
        for entry in entries.values where entry.review.connectionID == connectionID { invalidate(entry.review.id) }
    }

    func invalidateForScreenLock() {
        for id in entries.keys { invalidate(id) }
    }

    private func invalidate(_ id: UUID) {
        guard let state = entries[id]?.state, state == .pending || state == .approved else { return }
        entries[id]?.state = .invalidated
    }

    private func requireUsable(_ entry: Entry, approved: Bool) throws {
        switch entry.state {
        case .pending:
            if approved { throw AgentErrorCode.interactionRequired }
        case .approved: break
        case .expired: throw AgentErrorCode.timeout
        case .cancelled: throw AgentErrorCode.cancelled
        case .invalidated: throw AgentErrorCode.versionConflict
        case .consumed, .denied: throw AgentErrorCode.permissionDenied
        }
    }

    private func liveEntry(_ id: UUID) throws -> Entry {
        guard var entry = entries[id] else { throw AgentErrorCode.notFound }
        if isLocked() { invalidateForScreenLock(); throw AgentErrorCode.interactionRequired }
        guard let grant = currentGrant(entry.review.connectionID), !grant.revoked,
              grant.connectionID == entry.review.connectionID, grant.libraryID == entry.libraryID,
              grant.grantID == entry.grantID, grant.expiresAt > now(),
              (try? grantDigest(grant)) == entry.grantFingerprint else {
            invalidate(id); throw AgentErrorCode.permissionDenied
        }
        if entry.state == .pending || entry.state == .approved {
            let wall = now(), elapsed = uptime()
            if !wall.timeIntervalSince1970.isFinite || !elapsed.isFinite || wall < entry.issuedAt
                || elapsed < entry.issuedUptime {
                entry.state = .invalidated
            } else if wall >= entry.review.expiresAt || elapsed - entry.issuedUptime >= Self.lifetime {
                entry.state = .expired
            }
            entries[id] = entry
        }
        return entry
    }

    private func refreshEntries() {
        for id in Array(entries.keys) { _ = try? liveEntry(id) }
    }

    private func makeRoom() {
        let terminal = entries.values.filter { $0.state != .pending && $0.state != .approved }
            .sorted { $0.issuedUptime < $1.issuedUptime }
        for entry in terminal where entries.count >= capacity { entries.removeValue(forKey: entry.review.id) }
    }

    private func binding(_ request: AgentRequest, connectionID: UUID, effects: Effects) throws
        -> (fingerprint: String, grantFingerprint: String, grant: AgentGrant) {
        guard !isLocked() else { invalidateForScreenLock(); throw AgentErrorCode.interactionRequired }
        // Reuse the wire and operation validators, including request-local defaults.
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        let checked = prepared.request
        guard let grant = currentGrant(connectionID) else { throw AgentErrorCode.permissionDenied }
        if case .denied(let code) = AgentPermissionPolicy.evaluate(checked, connectionID: connectionID, grant: grant, now: now()) {
            throw code
        }
        guard grant.capabilities.isSuperset(of: effects.capabilities),
              effects.targets.allSatisfy(grant.scope.permits),
              !effects.requiresLibraryScope || grant.scope == .library else { throw AgentErrorCode.permissionDenied }
        let requestValue = prepared.value
        let effectValue = AgentJSONValue.object([
            "capabilities": .array(effects.capabilities.map(\.rawValue).sorted().map(AgentJSONValue.string)),
            "targets": references(effects.targets), "requiresLibraryScope": .bool(effects.requiresLibraryScope),
            "snapshot": .object(effects.snapshot)
        ])
        _ = try encoded(effectValue)
        let grantFingerprint = try grantDigest(grant)
        let value = AgentJSONValue.object(["epoch": .string(epoch.uuidString), "grant": .string(grantFingerprint),
            "request": requestValue, "effects": effectValue])
        return (try digest(value, maximum: Self.maximumBindingBytes), grantFingerprint, grant)
    }

    private func grantDigest(_ grant: AgentGrant) throws -> String {
        try digest(AgentRequestBinding.grantValue(grant))
    }

    private func references(_ values: Set<AgentResourceReference>) -> AgentJSONValue {
        AgentRequestBinding.references(values)
    }

    private func encoded<T: Encodable>(_ value: T, maximum: Int = AgentRequest.maximumBytes) throws -> Data {
        try AgentRequestBinding.encoded(value, maximum: maximum)
    }

    private func digest(_ value: AgentJSONValue, maximum: Int = AgentRequest.maximumBytes) throws -> String {
        HMAC<SHA256>.authenticationCode(for: try encoded(value, maximum: maximum), using: key)
            .map { String(format: "%02x", $0) }.joined()
    }
}
