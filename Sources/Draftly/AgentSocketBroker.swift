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
    private var clients: [UUID: (AgentUnixChannel, Task<Void, Never>)] = [:]

    init(service: AgentCommandService, parentDirectory: URL,
         validateHelper: @escaping @Sendable (Data) throws -> Void = { try AgentPeerIdentity.validate($0, role: .helper) }) throws {
        guard try service.permitsTransportStart() else { throw AgentErrorCode.permissionDenied }
        let listener = try AgentUnixListener(parentDirectory: parentDirectory)
        self.listener = listener; self.path = listener.path; self.service = service
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
        clients.removeAll(); service.invalidateAll()
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
                channel.close(); self?.clients.removeValue(forKey: id)
            }
            do {
                try await channel.validatePeer(validateHelper)
                let hello = try AgentLocalHandshake.Hello.decode(await channel.readFrame(maximumBytes: AgentLocalHandshake.maximumBytes, timeout: 15))
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
}
