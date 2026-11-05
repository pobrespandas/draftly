import Foundation
import CryptoKit
import AgentContracts

// Freeze membership and order, not content. Cursors never contain draft data.
@MainActor final class AgentReadPages {
    struct Owner: Equatable {
        let connectionID: UUID
        let grantID: UUID
    }
    private struct Snapshot {
        let owner: Owner
        let query: Data
        let ids: [UUID]
        let revision: String?
        let expiresAt: Date
        let startedAt: TimeInterval
    }
    private static let lifetime: TimeInterval = 600
    private var snapshots: [UUID: Snapshot] = [:]
    private let key = SymmetricKey(size: .bits256)
    private let now: () -> Date
    private let uptime: () -> TimeInterval

    init(now: @escaping () -> Date, uptime: @escaping () -> TimeInterval) {
        self.now = now; self.uptime = uptime
    }

    func remove(connectionID: UUID) { snapshots = snapshots.filter { $0.value.owner.connectionID != connectionID } }
    func removeAll() { snapshots.removeAll() }

    func page(owner: Owner, request: AgentRequest, parameters: [String: AgentJSONValue],
              expiresAt: Date, ids: () throws -> [UUID],
              value: (UUID) throws -> AgentJSONValue?, revision: (() throws -> String)? = nil) throws -> [String: AgentJSONValue] {
        snapshots = snapshots.filter { live($0.value) }
        var query = parameters
        query.removeValue(forKey: "cursor"); query.removeValue(forKey: "limit")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let binding = try encoder.encode(AgentJSONValue.object([
            "operation": .string(request.operation), "parameters": .object(query),
            "targets": .array(request.targets.map { .object(["kind": .string($0.kind.rawValue), "id": .string($0.id.uuidString)]) })
        ]))
        let id: UUID, snapshot: Snapshot, offset: Int
        if case .string(let cursor) = parameters["cursor"] {
            let parts = cursor.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, let parsedID = UUID(uuidString: String(parts[0])),
                  let parsedOffset = Int(parts[1]), parsedOffset >= 0,
                  let proof = Data(base64Encoded: String(parts[2])),
                  HMAC<SHA256>.isValidAuthenticationCode(proof,
                    authenticating: Data("\(parts[0]).\(parts[1])".utf8), using: key),
                  let stored = snapshots[parsedID], stored.owner == owner,
                  stored.query == binding, parsedOffset <= stored.ids.count else { throw AgentErrorCode.invalidInput }
            id = parsedID; snapshot = stored; offset = parsedOffset
        } else {
            guard snapshots.count < 64 else { throw AgentErrorCode.busy }
            let members = try ids()
            guard members.count <= 1_000_000 - snapshots.values.reduce(0, { $0 + $1.ids.count }) else {
                throw AgentErrorCode.busy
            }
            id = UUID(); offset = 0
            snapshot = Snapshot(owner: owner, query: binding, ids: members, revision: try revision?(),
                expiresAt: min(expiresAt, now().addingTimeInterval(Self.lifetime)), startedAt: uptime())
        }
        if let expected = snapshot.revision {
            guard let revision, try revision() == expected else { throw AgentErrorCode.versionConflict }
        } else if revision != nil { throw AgentErrorCode.invalidInput }
        let limit = Int(try AgentTextShapes.count(parameters["limit"]))
        var index = offset, items: [AgentJSONValue] = []
        while index < snapshot.ids.count && items.count < limit {
            let member = snapshot.ids[index]; index += 1
            if let item = try value(member) { items.append(item) }
        }
        let next: AgentJSONValue
        if index < snapshot.ids.count {
            let message = "\(id.uuidString).\(index)"
            let signature = Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)).base64EncodedString()
            next = .string(message + "." + signature)
        } else { next = .null }
        // Do not retain a new snapshot after a failed or single-page read.
        if offset == 0 && next != .null { snapshots[id] = snapshot }
        var result: [String: AgentJSONValue] = ["items": .array(items), "nextCursor": next]
        if let revision = snapshot.revision { result["orderVersion"] = .string(revision) }
        return result
    }

    private func live(_ snapshot: Snapshot) -> Bool {
        let timestamp = now(), elapsed = uptime() - snapshot.startedAt
        return timestamp.timeIntervalSinceReferenceDate.isFinite && elapsed.isFinite && elapsed >= 0
            && elapsed < Self.lifetime && timestamp < snapshot.expiresAt
    }
}
