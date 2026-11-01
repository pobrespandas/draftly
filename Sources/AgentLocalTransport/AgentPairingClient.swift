import Foundation
import AgentContracts

// Owns one pairing conversation. It cannot create or read a credential.
package actor AgentPairingClient {
    package let challenge: AgentPairingHandshake.Reply
    private let channel: AgentUnixChannel
    private var inFlight = false
    private var waiting = false
    private var terminal: AgentPairingHandshake.Reply?

    private init(channel: AgentUnixChannel, challenge: AgentPairingHandshake.Reply) {
        self.channel = channel; self.challenge = challenge
    }

    package static func connect(path: String, name: String,
        validateServer: @escaping @Sendable (Data) throws -> Void) async throws -> AgentPairingClient {
        let start = try AgentPairingHandshake.encode(AgentPairingHandshake.Start(clientName: name))
        let channel = try await AgentUnixChannel.connect(path: path, validatePeer: validateServer)
        do {
            try await channel.writeFrame(start, timeout: 15)
            let reply = try AgentPairingHandshake.Reply.decode(await channel.readFrame(maximumBytes: AgentPairingHandshake.maximumBytes, timeout: 15))
            if let error = reply.error { throw error }
            guard reply.pairingID != nil, reply.code != nil, reply.expiresAt != nil, reply.state == nil else {
                throw AgentErrorCode.invalidInput
            }
            return AgentPairingClient(channel: channel, challenge: reply)
        } catch { channel.close(); throw error }
    }

    package func close() { channel.close() }

    package func poll() async throws -> AgentPairingHandshake.Reply { try await control(.poll) }
    package func cancel() async throws -> AgentPairingHandshake.Reply { try await control(.cancel) }

    package func waitForDecision(timeout: TimeInterval = 300) async throws -> AgentPairingHandshake.Reply {
        guard timeout.isFinite, timeout >= 0, timeout <= 300 else { throw AgentErrorCode.invalidInput }
        guard !waiting else { throw AgentErrorCode.busy }
        waiting = true; defer { waiting = false }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        do {
            while true {
                let deadlineReached = ProcessInfo.processInfo.systemUptime >= deadline
                let reply = try await control(deadlineReached ? .cancel : .poll)
                if reply.state != .pending {
                    // Approval can win the race with deadline cancellation. Report
                    // that completed effect instead of a false timeout.
                    if deadlineReached, reply.state == .cancelled { throw AgentErrorCode.timeout }
                    return reply
                }
                guard !deadlineReached else { throw AgentErrorCode.timeout }
                try await Task.sleep(for: .milliseconds(500))
            }
        } catch { channel.close(); throw error }
    }

    private func control(_ command: AgentPairingHandshake.Command) async throws -> AgentPairingHandshake.Reply {
        if let terminal { return terminal }
        guard !inFlight else { throw AgentErrorCode.busy }
        guard let id = challenge.pairingID else { throw AgentErrorCode.invalidInput }
        inFlight = true; defer { inFlight = false }
        do {
            try await channel.writeFrame(AgentPairingHandshake.encode(AgentPairingHandshake.Control(pairingID: id, command: command)), timeout: 15)
            let reply = try AgentPairingHandshake.Reply.decode(await channel.readFrame(maximumBytes: AgentPairingHandshake.maximumBytes, timeout: 15))
            if reply.state == nil, let error = reply.error { throw error }
            guard reply.pairingID == id, let state = reply.state else { throw AgentErrorCode.invalidInput }
            if state != .pending { terminal = reply; channel.close() }
            return reply
        } catch { channel.close(); throw error }
    }
}
