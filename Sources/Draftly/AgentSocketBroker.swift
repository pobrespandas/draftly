import Foundation
import AgentContracts
import AgentLocalSecurity
import AgentLocalTransport

// Construct only after local access has been approved. No app route starts it yet.
@MainActor final class AgentSocketBroker {
    let path: String
    private let listener: AgentUnixListener
    private let service: AgentCommandService
    private var accepting: Task<Void, Never>?
    private let pairing: AgentPairingCoordinator?
    private var pairingClients: Set<UUID> = []
    private var clients: [UUID: (AgentUnixChannel, Task<Void, Never>)] = [:]

    init(service: AgentCommandService, parentDirectory: URL, pairing: AgentPairingCoordinator? = nil,
         validateHelper: @escaping @Sendable (Data) throws -> Void = { try AgentPeerIdentity.validate($0, role: .helper) }) throws {
        guard try service.permitsTransportStart() else { throw AgentErrorCode.permissionDenied }
        let listener = try AgentUnixListener(parentDirectory: parentDirectory)
        self.listener = listener; self.path = listener.path; self.service = service; self.pairing = pairing
        accepting = Task { [weak self, listener] in
            while !Task.isCancelled {
                do {
                    let channel = try await listener.accept()
                    guard let self else { channel.close(); break }
                    self.accept(channel, validateHelper: validateHelper)
                } catch AgentErrorCode.timeout { continue }
                catch { break }
            }
        }
    }

    func stop() {
        accepting?.cancel(); accepting = nil; listener.close()
        for (channel, task) in clients.values { task.cancel(); channel.close() }
        clients.removeAll(); pairingClients.removeAll(); pairing?.invalidatePending(); service.invalidateAll()
    }

    deinit {
        accepting?.cancel(); listener.close()
        for (channel, task) in clients.values { task.cancel(); channel.close() }
    }

    private func accept(_ channel: AgentUnixChannel, validateHelper: @escaping @Sendable (Data) throws -> Void) {
        guard clients.count < 8 else { channel.close(); return }
        let id = UUID(), service = service
        let task = Task { [weak self] in
            var session: AgentCommandService.Session?
            defer {
                if let session { service.close(session) }
                channel.close(); self?.clients.removeValue(forKey: id); self?.pairingClients.remove(id)
            }
            do {
                try await channel.validatePeer(validateHelper)
                let intro = try AgentPairingHandshake.Introduction.decode(await channel.readFrame(maximumBytes: AgentPairingHandshake.maximumBytes, timeout: 15))
                let hello: AgentLocalHandshake.Hello
                switch intro {
                case .authenticate(let value): hello = value
                case .pair(let start):
                    let candidate: Result<AgentPairingCoordinator, any Error>
                    do {
                        guard let coordinator = try self?.reservePairingSlot(id) else { throw AgentErrorCode.cancelled }
                        candidate = .success(coordinator)
                    } catch { candidate = .failure(error) }
                    await Self.handlePairing(start, channel: channel, candidate: candidate)
                    return
                }
                let authenticated: AgentCommandService.Session, libraryID: UUID
                do {
                    authenticated = try service.authenticate(connectionID: hello.connectionID, credential: hello.credential)
                    session = authenticated
                    libraryID = try service.authorizedLibraryID(for: authenticated)
                }
                catch {
                    let code = (error as? AgentErrorCode) ?? .storageError
                    try await channel.writeFrame(JSONEncoder().encode(AgentLocalHandshake.Welcome(error: code)), timeout: 15)
                    return
                }
                try await channel.writeFrame(JSONEncoder().encode(AgentLocalHandshake.Welcome(libraryID: libraryID)), timeout: 15)
                while !Task.isCancelled {
                    let request = try await channel.readFrame()
                    try await channel.writeFrame(service.respond(to: request, session: authenticated))
                }
            } catch { /* A failed or disconnected peer has no reusable session. */ }
        }
        clients[id] = (channel, task)
    }

    private func reservePairingSlot(_ id: UUID) throws -> AgentPairingCoordinator {
        guard let pairing else { throw AgentErrorCode.unavailable }
        // Keep pairing waits from occupying all normal operation slots.
        guard pairingClients.count < 2 else { throw AgentErrorCode.busy }
        pairingClients.insert(id)
        return pairing
    }

    private static func handlePairing(_ start: AgentPairingHandshake.Start, channel: AgentUnixChannel,
                                      candidate: Result<AgentPairingCoordinator, any Error>) async {
        do {
            let pairing = try candidate.get()
            let challenge = try pairing.request(clientName: start.clientName)
            defer { try? pairing.cancel(challenge.id) }
            try await channel.writeFrame(AgentPairingHandshake.encode(AgentPairingHandshake.Reply(
                pairingID: challenge.id, code: challenge.code, expiresAt: challenge.expiresAt)), timeout: 15)
            while !Task.isCancelled {
                let control = try AgentPairingHandshake.Control.decode(await channel.readFrame(maximumBytes: AgentPairingHandshake.maximumBytes, timeout: 15))
                guard control.pairingID == challenge.id else { throw AgentErrorCode.invalidInput }
                if control.command == .cancel { try pairing.cancel(challenge.id) }
                let reply = pairingReply(try pairing.state(challenge.id), id: challenge.id)
                try await channel.writeFrame(AgentPairingHandshake.encode(reply), timeout: 15)
                if reply.state != .pending { return }
            }
        } catch {
            let code = (error as? AgentErrorCode) ?? .storageError
            try? await channel.writeFrame(AgentPairingHandshake.encode(AgentPairingHandshake.Reply(error: code)), timeout: 15)
        }
    }

    private static func pairingReply(_ state: AgentPairingCoordinator.State, id: UUID) -> AgentPairingHandshake.Reply {
        switch state {
        case .pending: .init(pairingID: id, state: .pending)
        case .approved(let connection): .init(pairingID: id, state: .approved, connectionID: connection)
        case .denied: .init(pairingID: id, state: .denied)
        case .cancelled: .init(pairingID: id, state: .cancelled)
        case .expired: .init(pairingID: id, state: .expired)
        case .invalidated: .init(pairingID: id, state: .invalidated)
        case .failed(let code): .init(pairingID: id, state: .failed, error: code)
        }
    }

}
