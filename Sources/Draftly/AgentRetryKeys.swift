import Foundation
import CryptoKit
import AgentContracts

// A retry key binds work to authority. It never grants access or approves effects.
@MainActor final class AgentRetryKeys {
    struct Ticket {
        let value: String
        let requestHash: String
        let connectionHash: String
        let expiresAt: Date
    }
    private struct Payload: Codable {
        let version: Int
        let epoch: UUID
        let requestHash: String
        let connectionHash: String
        let grantFingerprint: String
        let wallBits: UInt64
        let uptimeBits: UInt64
    }
    static let lifetime: TimeInterval = 30 * 86400
    private let epoch: UUID
    private let key: SymmetricKey
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let currentGrant: (UUID) -> AgentGrant?
    private let isLocked: () -> Bool
    private var closed = false

    init(epoch: UUID = UUID(), key: SymmetricKey = SymmetricKey(size: .bits256),
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         currentGrant: @escaping (UUID) -> AgentGrant?, isLocked: @escaping () -> Bool) {
        self.epoch = epoch; self.key = key; self.now = now; self.uptime = uptime
        self.currentGrant = currentGrant; self.isLocked = isLocked
    }

    func issue(_ request: AgentRequest, connectionID: UUID) throws -> Ticket {
        let wall = now(), ticks = uptime()
        let binding = try binding(request, connectionID: connectionID, at: wall)
        guard wall.timeIntervalSince1970.isFinite, ticks.isFinite, ticks >= 0 else { throw AgentErrorCode.unavailable }
        let payload = Payload(version: 1, epoch: epoch, requestHash: binding.requestHash,
            connectionHash: binding.connectionHash, grantFingerprint: binding.grantFingerprint,
            wallBits: wall.timeIntervalSince1970.bitPattern, uptimeBits: ticks.bitPattern)
        let data = try AgentRequestBinding.encoded(payload, maximum: 2048)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
        return Ticket(value: data.base64EncodedString() + "." + signature.base64EncodedString(),
            requestHash: binding.requestHash, connectionHash: binding.connectionHash,
            expiresAt: wall.addingTimeInterval(Self.lifetime))
    }

    func verify(_ value: String, request: AgentRequest, connectionID: UUID) throws -> Ticket {
        let wall = now(), ticks = uptime()
        let binding = try binding(request, connectionID: connectionID, at: wall)
        guard value.utf8.count <= 4096 else { throw AgentErrorCode.invalidInput }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let data = Data(base64Encoded: String(parts[0])),
              let signature = Data(base64Encoded: String(parts[1])), signature.count == 32,
              data.base64EncodedString() == parts[0], signature.base64EncodedString() == parts[1],
              HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: data, using: key) else {
            throw AgentErrorCode.invalidInput
        }
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw AgentErrorCode.invalidInput }
        guard payload.version == 1, payload.epoch == epoch else { throw AgentErrorCode.invalidInput }
        guard payload.connectionHash == binding.connectionHash,
              payload.grantFingerprint == binding.grantFingerprint else { throw AgentErrorCode.permissionDenied }
        guard payload.requestHash == binding.requestHash else { throw AgentErrorCode.invalidInput }
        let issued = Double(bitPattern: payload.wallBits), started = Double(bitPattern: payload.uptimeBits)
        let wallAge = wall.timeIntervalSince1970 - issued, elapsed = ticks - started
        guard issued.isFinite, started.isFinite, wallAge.isFinite, elapsed.isFinite,
              wallAge >= 0, elapsed >= 0, wallAge < Self.lifetime, elapsed < Self.lifetime else {
            throw AgentErrorCode.retryWindowExpired
        }
        return Ticket(value: value, requestHash: binding.requestHash, connectionHash: binding.connectionHash,
            expiresAt: Date(timeIntervalSince1970: issued).addingTimeInterval(Self.lifetime))
    }

    func close() { closed = true }

    private func binding(_ request: AgentRequest, connectionID: UUID, at wall: Date) throws
        -> (requestHash: String, connectionHash: String, grantFingerprint: String) {
        guard !closed else { throw AgentErrorCode.cancelled }
        guard !isLocked() else { throw AgentErrorCode.interactionRequired }
        guard wall.timeIntervalSince1970.isFinite, let grant = currentGrant(connectionID) else {
            throw AgentErrorCode.permissionDenied
        }
        if case .denied(let error) = AgentPermissionPolicy.evaluate(request, connectionID: connectionID, grant: grant, now: wall) {
            throw error
        }
        guard let operation = AgentOperationCatalog.operation(named: request.operation), !operation.isReadOnly else {
            throw AgentErrorCode.invalidInput
        }
        let preferences = try AgentPreferenceCatalog.make()
        let prepared: AgentRequestBinding.Prepared
        do { prepared = try AgentRequestBinding.prepare(request, preferences: preferences) }
        catch let error as AgentErrorCode { throw error }
        catch { throw AgentErrorCode.invalidInput }
        let data = try AgentRequestBinding.encoded(prepared.value, maximum: AgentRequest.maximumBytes * 2)
        let grantData = try AgentRequestBinding.encoded(AgentRequestBinding.grantValue(grant))
        return (hex(SHA256.hash(data: data)),
            hex(SHA256.hash(data: Data(("draftly-connection-v1:" + connectionID.uuidString.lowercased()).utf8))),
            hex(HMAC<SHA256>.authenticationCode(for: grantData, using: key)))
    }

    private func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
