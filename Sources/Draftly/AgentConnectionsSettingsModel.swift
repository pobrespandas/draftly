import Foundation
import Combine
import AgentContracts

@MainActor final class AgentConnectionsSettingsModel: ObservableObject {
    struct ResourceChoice: Identifiable {
        let reference: AgentResourceReference
        let title: String
        var id: AgentResourceReference { reference }
        var accessibilityTitle: String { title + " · " + reference.kind.userTitle + " · " + reference.id.uuidString }
    }
    enum EditingContext {
        case connection(UUID)
        case pairing(AgentPairingCoordinator.Challenge)
    }

    @Published private(set) var configuration = AgentConnectionMetadata()
    @Published private(set) var pending: [AgentPairingCoordinator.Challenge] = []
    @Published private(set) var context: EditingContext?
    @Published private(set) var review: AgentPairingCoordinator.Review?
    @Published private(set) var lastError: AgentErrorCode?
    @Published private(set) var cleanupPendingIDs: Set<UUID> = []
    var cleanupPending: Bool { !cleanupPendingIDs.isEmpty }
    @Published private(set) var readable = false
    @Published private(set) var accessEnabled = false
    @Published var draft: AgentGrantEditingCopy? { didSet { review = nil } }

    let libraryID: UUID
    private let registry: AgentConnectionRegistry
    private let pairing: AgentPairingCoordinator
    private let now: () -> Date
    private let choices: () -> [ResourceChoice]
    private let initialTargets: () -> Set<AgentResourceReference>
    private let resolveTargets: (Set<AgentResourceReference>) throws -> Set<AgentResourceReference>
    // The host owns broker startup, shutdown, provisioning and lock observation.
    private let setAccessEnabled: (Bool) throws -> Void

    init(libraryID: UUID, registry: AgentConnectionRegistry, pairing: AgentPairingCoordinator,
         now: @escaping () -> Date = Date.init, choices: @escaping () -> [ResourceChoice],
         initialTargets: @escaping () -> Set<AgentResourceReference> = { [] },
         resolveTargets: @escaping (Set<AgentResourceReference>) throws -> Set<AgentResourceReference>,
         setAccessEnabled: @escaping (Bool) throws -> Void) throws {
        guard pairing.isBound(to: registry, libraryID: libraryID) else { throw AgentErrorCode.invalidInput }
        self.libraryID = libraryID; self.registry = registry; self.pairing = pairing; self.now = now
        self.choices = choices; self.initialTargets = initialTargets; self.resolveTargets = resolveTargets
        self.setAccessEnabled = setAccessEnabled
        refresh()
    }

    var connections: [AgentConnectionRecord] { configuration.connections.filter { $0.libraryID == libraryID } }
    var isPairing: Bool { if case .pairing = context { true } else { false } }
    var canReviewPairing: Bool {
        guard case .pairing(let challenge) = context else { return false }
        return readable && pending.contains { $0.id == challenge.id }
    }

    func resourceChoices() -> [ResourceChoice] {
        // Keep selected missing IDs visible. Never drop them silently while editing.
        var seen: Set<AgentResourceReference> = []
        var result = choices().filter { seen.insert($0.reference).inserted }
        for target in (draft?.targets ?? []).sorted(by: { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }) where seen.insert(target).inserted {
            result.append(ResourceChoice(reference: target, title: "Unavailable resource"))
        }
        return result
    }

    func refresh() {
        do {
            configuration = try registry.configurationForUserInterface()
            accessEnabled = try registry.permitsTransportStart()
            readable = true
        } catch { readable = false; accessEnabled = false; lastError = code(error) }
        pending = pairing.pendingFromUserInterface()
        if case .pairing(let challenge) = context, !pending.contains(where: { $0.id == challenge.id }) { review = nil }
    }

    func clearError() { lastError = nil }

    func setEnabled(_ enabled: Bool) throws {
        do {
            try setAccessEnabled(enabled)
            guard try registry.configurationForUserInterface().enabled == enabled,
                  try registry.permitsTransportStart() == enabled else { throw AgentErrorCode.outcomeUnknown }
            lastError = nil; refresh()
        } catch { refresh(); lastError = code(error); throw error }
    }

    func beginEditing(_ id: UUID) throws {
        do {
            let record = try currentRecord(id)
            guard !record.revoked else { throw AgentErrorCode.permissionDenied }
            context = .connection(id); draft = AgentGrantEditingCopy(record: record); lastError = nil
        } catch { lastError = code(error); throw error }
    }

    func beginPairing(_ id: UUID) throws {
        refresh()
        do {
            guard readable, let challenge = pending.first(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
            let selection = initialTargets()
            guard try resolveTargets(selection) == selection else { throw AgentErrorCode.notFound }
            context = .pairing(challenge)
            draft = AgentGrantEditingCopy(name: challenge.clientName, selectedTargets: selection, now: now())
            lastError = nil
        } catch { lastError = code(error); throw error }
    }

    func cancelEditing() { draft = nil; context = nil; review = nil; lastError = nil }

    func changeReviewChoices() { review = nil }

    func saveExisting() throws {
        do {
            guard case .connection(let id) = context, let draft else { throw AgentErrorCode.invalidInput }
            let current = try currentRecord(id)
            guard current.grantID == draft.originalGrantID else { throw AgentErrorCode.versionConflict }
            guard !current.revoked else { throw AgentErrorCode.permissionDenied }
            // Renaming is not part of the registry's grant replacement command.
            guard draft.name == current.name else { throw AgentErrorCode.invalidInput }
            try validate(draft)
            _ = try registry.replaceGrantFromUserInterface(id, capabilities: draft.capabilities, scope: draft.scope,
                                                           expiresAt: draft.expiresAt, renewable: draft.renewable)
            cancelEditing(); lastError = nil; refresh()
        } catch { refresh(); lastError = code(error); throw error }
    }

    func preparePairingReview() throws {
        do {
            guard case .pairing(let challenge) = context, let draft else { throw AgentErrorCode.invalidInput }
            try validate(draft)
            review = try pairing.prepareReviewFromUserInterface(challenge.id, name: draft.name,
                capabilities: draft.capabilities, scope: draft.scope, grantExpiresAt: draft.expiresAt, renewable: draft.renewable)
            lastError = nil
        } catch { review = nil; refresh(); lastError = code(error); throw error }
    }

    func approvePairing(codesMatch: Bool) throws -> AgentConnectionRecord {
        do {
            guard codesMatch else { throw AgentErrorCode.interactionRequired }
            guard case .pairing(let challenge) = context, let review,
                  review.challenge.id == challenge.id else { throw AgentErrorCode.invalidInput }
            let result = try pairing.approveFromUserInterface(challenge.id, reviewID: review.id,
                                                              displayedChallenge: review.challenge.code)
            cancelEditing(); lastError = nil; refresh()
            return result
        } catch { refresh(); lastError = code(error); throw error }
    }

    func denyPairing(_ id: UUID) throws {
        do { try pairing.denyFromUserInterface(id); lastError = nil; refresh() }
        catch { refresh(); lastError = code(error); throw error }
    }

    func revoke(_ id: UUID) throws {
        do {
            _ = try currentRecord(id)
            let result = try registry.revokeFromUserInterface(id)
            if result.credentialCleanupPending { cleanupPendingIDs.insert(id) }
            else { cleanupPendingIDs.remove(id) }
            lastError = nil; refresh()
        } catch { refresh(); lastError = code(error); throw error }
    }

    func status(_ record: AgentConnectionRecord) -> AgentConnectionRegistry.DisplayStatus {
        guard let current = connections.first(where: { $0.id == record.id }) else { return .inactive }
        return registry.displayStatusFromUserInterface(current, enabled: accessEnabled)
    }

    private func currentRecord(_ id: UUID) throws -> AgentConnectionRecord {
        guard let record = try registry.configurationForUserInterface().connections.first(where: { $0.id == id && $0.libraryID == libraryID }) else {
            throw AgentErrorCode.notFound
        }
        return record
    }

    private func validate(_ draft: AgentGrantEditingCopy) throws {
        guard AgentConnectionName.isValid(draft.name), draft.expiresAt.timeIntervalSince1970.isFinite,
              draft.expiresAt > now() else { throw AgentErrorCode.invalidInput }
        if case .resources(let targets) = draft.scope {
            guard try resolveTargets(targets) == targets else { throw AgentErrorCode.notFound }
        }
    }

    private func code(_ error: any Error) -> AgentErrorCode { (error as? AgentErrorCode) ?? .storageError }
}
