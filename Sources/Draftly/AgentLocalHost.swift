import Foundation
import DraftlyCore
import AgentContracts
import AgentLocalSecurity

// One loaded library, authority registry and transport lifetime. Normal startup
// must still provide editor/lock adapters and a provisioned signed helper.
@MainActor final class AgentLocalHost {
    let libraryID: UUID
    let connections: AgentConnectionRegistry
    let pairing: AgentPairingCoordinator
    let service: AgentCommandService
    private let lease: AgentHostLease
    private let socketParentDirectory: URL
    private let validateApplication: () throws -> Void
    private let validateHelper: @Sendable (Data) throws -> Void
    private let isLocked: () -> Bool
    private let resolveTargets: (Set<AgentResourceReference>) throws -> Set<AgentResourceReference>
    private var broker: AgentSocketBroker?
    private var closed = false

    var endpoint: String? { broker?.path }

    init(library: LibraryStore, appVersion: String,
         isLocked: @escaping () -> Bool,
         pendingEditorGeneration: @escaping (UUID) -> String,
         resolveTargets: @escaping (Set<AgentResourceReference>) throws -> Set<AgentResourceReference>,
         socketParentDirectory: URL = FileManager.default.temporaryDirectory,
         credentials: AgentConnectionRegistry.CredentialAccess? = nil,
         validateApplication: @escaping () throws -> Void = { try AgentCredentialIdentity.validateCurrentProcess(.application) },
         validateHelper: @escaping @Sendable (Data) throws -> Void = { try AgentPeerIdentity.validate($0, role: .helper) }) throws {
        // Reject unprovisioned application builds before creating local state.
        try validateApplication()
        let lease = try AgentHostLease(location: AgentLibraryLocation(library: library))
        let file: AgentConnectionFile
        do { file = try AgentConnectionFile(parentDirectory: lease.location.url.deletingLastPathComponent()) }
        catch { lease.close(); throw error }
        weak var owner: AgentLocalHost?
        let validateOwner: () throws -> Void = {
            guard let owner else { throw AgentErrorCode.cancelled }
            try owner.validateOwnership()
        }
        let registry = AgentConnectionRegistry(metadata: .init(read: {
            try validateOwner(); return try file.read()
        }, replace: { data, expected in
            try validateOwner(); try file.replace(data, expected: expected)
        }), credentials: credentials ?? AgentCredentialKeychain(role: .application).registryAccess,
            authorityChanged: { id in owner?.authorityChanged(id) })
        self.lease = lease; libraryID = lease.libraryID; connections = registry
        self.socketParentDirectory = socketParentDirectory
        self.validateApplication = validateApplication; self.validateHelper = validateHelper
        self.isLocked = isLocked; self.resolveTargets = resolveTargets
        do {
            service = try AgentCommandService(library: library, libraryID: lease.libraryID, connections: registry,
                appVersion: appVersion, validateHost: validateOwner, isLocked: isLocked,
                pendingEditorGeneration: pendingEditorGeneration)
        } catch { lease.close(); throw error }
        pairing = AgentPairingCoordinator(registry: registry, libraryID: lease.libraryID,
            validateHost: validateOwner, isLocked: isLocked, resolveTargets: resolveTargets)
        owner = self
        do { _ = try registry.configurationForUserInterface() }
        catch { close(); throw error }
    }

    // Explicit close is the normal shutdown path. This is a fallback for a
    // discarded host; it preserves the same ordering on MainActor.
    isolated deinit { close() }

    func close() {
        guard !closed else { return }; closed = true
        suspend()
        lease.close()
    }

    func suspend() {
        broker?.stop(); broker = nil
        service.invalidateAll(); pairing.invalidatePending()
    }

    // Reopen only by an explicit lifecycle command. Construction never listens.
    func resumeIfEnabled() throws {
        do {
            try requireReady()
            guard try connections.permitsTransportStart() else { suspend(); return }
            guard broker == nil else { return }
            broker = try AgentSocketBroker(service: service, parentDirectory: socketParentDirectory,
                pairing: pairing, validateHelper: validateHelper)
        } catch {
            if (error as? AgentErrorCode) != .busy { suspend() }
            throw error
        }
    }

    func setEnabledFromUserInterface(_ enabled: Bool) throws {
        if !enabled {
            suspend()
            try connections.setEnabledFromUserInterface(false)
            return
        }
        try requireReady()
        let previouslyEnabled = try connections.configurationForUserInterface().enabled
        try connections.setEnabledFromUserInterface(true)
        do { try resumeIfEnabled() }
        catch {
            let failure = error
            suspend()
            if !previouslyEnabled {
                do { try connections.setEnabledFromUserInterface(false) }
                catch { throw AgentErrorCode.outcomeUnknown }
            }
            throw failure
        }
    }

    func makeSettingsModel(choices: @escaping () -> [AgentConnectionsSettingsModel.ResourceChoice],
                           initialTargets: @escaping () -> Set<AgentResourceReference> = { [] }) throws -> AgentConnectionsSettingsModel {
        try validateOwnership()
        return try AgentConnectionsSettingsModel(libraryID: libraryID, registry: connections, pairing: pairing,
            choices: choices, initialTargets: initialTargets, resolveTargets: resolveTargets,
            setAccessEnabled: { [weak self] enabled in
                guard let self else { throw AgentErrorCode.cancelled }
                try self.setEnabledFromUserInterface(enabled)
            })
    }

    private func requireReady() throws {
        do {
            try validateOwnership()
            guard !isLocked() else { throw AgentErrorCode.permissionDenied }
            try validateApplication()
        } catch {
            if (error as? AgentErrorCode) != .busy { suspend() }
            throw error
        }
    }

    private func validateOwnership() throws {
        guard !closed else { throw AgentErrorCode.cancelled }
        do { try lease.validate() }
        catch {
            if (error as? AgentErrorCode) != .busy { suspend() }
            throw error
        }
    }

    private func authorityChanged(_ id: UUID) {
        service.invalidate(connectionID: id)
        pairing.invalidatePending()
    }
}
