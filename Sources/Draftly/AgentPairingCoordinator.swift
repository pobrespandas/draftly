import Foundation
import AgentContracts

// Owns temporary pairing decisions. Transport adapters cannot approve a request.
@MainActor final class AgentPairingCoordinator {
    enum State: Equatable {
        case pending, approved(connectionID: UUID), denied, cancelled, expired, invalidated
        case failed(AgentErrorCode)
    }

    struct Challenge: Identifiable, Equatable {
        let id: UUID
        let clientName: String
        // A comparison code, not a credential or proof of client identity.
        let code: String
        let expiresAt: Date
    }

    struct Review: Identifiable {
        let id: UUID
        let challenge: Challenge
        let name: String
        let capabilities: Set<AgentCapability>
        let scope: AgentResourceScope
        let grantExpiresAt: Date
        let renewable: Bool
    }

    private struct Entry {
        let challenge: Challenge
        let issuedAt: Date
        let issuedUptime: TimeInterval
        var state: State = .pending
        var review: Review?
    }

    static let lifetime: TimeInterval = 300
    private let registry: AgentConnectionRegistry
    private let libraryID: UUID
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let isLocked: () -> Bool
    // Resolve exact IDs in this library. A saved query must be resolved by the UI
    // before this call; future query matches never expand the grant.
    private let resolveTargets: (Set<AgentResourceReference>) throws -> Set<AgentResourceReference>
    private let capacity: Int
    private var entries: [UUID: Entry] = [:]

    init(registry: AgentConnectionRegistry, libraryID: UUID, capacity: Int = 32,
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         isLocked: @escaping () -> Bool,
         resolveTargets: @escaping (Set<AgentResourceReference>) throws -> Set<AgentResourceReference>) {
        self.registry = registry; self.libraryID = libraryID; self.capacity = max(1, capacity)
        self.now = now; self.uptime = uptime; self.isLocked = isLocked; self.resolveTargets = resolveTargets
    }

    // Called only after the pairing transport has verified the signed helper.
    // The supplied name remains an untrusted display label.
    func request(clientName: String) throws -> Challenge {
        try requireAvailable()
        guard AgentConnectionMetadata.validName(clientName) else { throw AgentErrorCode.invalidInput }
        refresh()
        // Retain terminal entries until their challenge expires so polling is stable.
        entries = entries.filter { !hasExpired($0.value) }
        guard entries.count < capacity else { throw AgentErrorCode.busy }
        let wall = now(), elapsed = uptime()
        guard wall.timeIntervalSince1970.isFinite, elapsed.isFinite else { throw AgentErrorCode.unavailable }
        let challenge = Challenge(id: UUID(), clientName: clientName, code: UUID().uuidString,
                                  expiresAt: wall.addingTimeInterval(Self.lifetime))
        entries[challenge.id] = Entry(challenge: challenge, issuedAt: wall, issuedUptime: elapsed)
        return challenge
    }

    func state(_ id: UUID) throws -> State {
        refresh()
        guard let entry = entries[id] else { throw AgentErrorCode.notFound }
        return entry.state
    }

    func pendingFromUserInterface() -> [Challenge] {
        refresh()
        return entries.values.filter { $0.state == .pending }.map(\.challenge)
            .sorted { ($0.expiresAt, $0.id.uuidString) < ($1.expiresAt, $1.id.uuidString) }
    }

    func prepareReviewFromUserInterface(_ id: UUID, name: String,
        capabilities: Set<AgentCapability> = [.draftsRead], scope: AgentResourceScope = .resources([]),
        grantExpiresAt: Date? = nil, renewable: Bool = false) throws -> Review {
        try requirePending(id)
        let expiry = grantExpiresAt ?? now().addingTimeInterval(3600)
        guard AgentConnectionMetadata.validName(name), expiry.timeIntervalSince1970.isFinite,
              expiry > now() else { throw AgentErrorCode.invalidInput }
        try validateScope(scope)
        guard let challenge = entries[id]?.challenge else { throw AgentErrorCode.notFound }
        let review = Review(id: UUID(), challenge: challenge, name: name,
                            capabilities: capabilities, scope: scope, grantExpiresAt: expiry, renewable: renewable)
        entries[id]?.review = review
        return review
    }

    func approveFromUserInterface(_ id: UUID, reviewID: UUID, displayedChallenge: String) throws -> AgentConnectionRecord {
        try requirePending(id)
        guard let review = entries[id]?.review, review.id == reviewID,
              review.challenge.code == displayedChallenge else { throw AgentErrorCode.versionConflict }
        guard review.grantExpiresAt > now() else { throw AgentErrorCode.invalidInput }
        do { try validateScope(review.scope) }
        catch {
            entries[id]?.state = .invalidated; entries[id]?.review = nil
            throw error
        }
        // The registry verifies durable metadata and credentials before success.
        // A failed attempt is terminal; polling or a second click must not retry it.
        do {
            let record = try registry.connectFromUserInterface(name: review.name, libraryID: libraryID,
                capabilities: review.capabilities, scope: review.scope, expiresAt: review.grantExpiresAt,
                renewable: review.renewable)
            entries[id]?.state = .approved(connectionID: record.id); entries[id]?.review = nil
            return record
        } catch {
            entries[id]?.state = .failed((error as? AgentErrorCode) ?? .storageError)
            entries[id]?.review = nil
            throw error
        }
    }

    func denyFromUserInterface(_ id: UUID) throws {
        try requirePending(id)
        entries[id]?.state = .denied; entries[id]?.review = nil
    }

    func cancel(_ id: UUID) throws {
        refresh()
        guard entries[id] != nil else { throw AgentErrorCode.notFound }
        if entries[id]?.state == .pending { entries[id]?.state = .cancelled; entries[id]?.review = nil }
    }

    func invalidatePending() {
        for id in entries.keys where entries[id]?.state == .pending {
            entries[id]?.state = .invalidated; entries[id]?.review = nil
        }
    }

    private func requirePending(_ id: UUID) throws {
        refresh()
        try requireAvailable()
        guard let entry = entries[id] else { throw AgentErrorCode.notFound }
        guard entry.state == .pending else { throw AgentErrorCode.permissionDenied }
    }

    private func requireAvailable() throws {
        do {
            guard !isLocked(), try registry.permitsTransportStart() else { throw AgentErrorCode.permissionDenied }
        } catch {
            invalidatePending()
            throw error
        }
    }

    private func validateScope(_ scope: AgentResourceScope) throws {
        if case .resources(let targets) = scope {
            guard try resolveTargets(targets) == targets else { throw AgentErrorCode.notFound }
        }
    }

    private func hasExpired(_ entry: Entry) -> Bool {
        let wall = now(), elapsed = uptime()
        return !wall.timeIntervalSince1970.isFinite || !elapsed.isFinite || wall < entry.issuedAt
            || elapsed < entry.issuedUptime || wall >= entry.challenge.expiresAt
            || elapsed - entry.issuedUptime >= Self.lifetime
    }

    private func refresh() {
        let available = !isLocked() && ((try? registry.permitsTransportStart()) == true)
        for id in entries.keys {
            guard let entry = entries[id] else { continue }
            if entry.state == .pending {
                if hasExpired(entry) { entries[id]?.state = .expired }
                else if !available { entries[id]?.state = .invalidated }
                if entries[id]?.state != .pending { entries[id]?.review = nil }
            } else if case .approved(let connectionID) = entry.state,
                      (try? registry.grantForAuthenticatedConnection(connectionID)) == nil {
                entries[id]?.state = .invalidated
            }
        }
    }
}
