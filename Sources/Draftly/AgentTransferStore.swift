import Foundation
import CryptoKit
import AgentContracts

// Transfers hold bytes. Import and export handlers own library work.
@MainActor final class AgentTransferStore {
    private struct Entry {
        let grant: AgentGrant
        let resources: Set<AgentResourceReference>
        let direction: String
        let byteLength: Int
        let sha256: String
        let expiresAt: Date
        let deadline: TimeInterval
        var data: Data
        var ready: Bool
    }
    private var entries: [UUID: Entry] = [:]
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let maximumEntries: Int
    private let maximumReservedBytes: Int

    init(now: @escaping () -> Date, uptime: @escaping () -> TimeInterval,
         maximumEntries: Int = 16, maximumReservedBytes: Int = 64 * 1024 * 1024) {
        self.now = now; self.uptime = uptime
        self.maximumEntries = maximumEntries; self.maximumReservedBytes = maximumReservedBytes
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func remove(connectionID: UUID) { entries = entries.filter { $0.value.grant.connectionID != connectionID } }
    func removeAll() { entries.removeAll() }
    private func prune() {
        let date = now(), tick = uptime()
        entries = entries.filter { $0.value.expiresAt > date && $0.value.deadline > tick }
    }
    private func entry(_ id: UUID, grant: AgentGrant) throws -> Entry {
        prune()
        guard let value = entries[id], AgentRequestBinding.grantValue(value.grant) == AgentRequestBinding.grantValue(grant),
              value.resources.allSatisfy({ grant.scope.permits($0) }) else { throw AgentErrorCode.notFound }
        return value
    }
    func authorize(_ id: UUID, grant: AgentGrant) throws {
        _ = try entry(id, grant: grant)
    }
    private func metadata(_ id: UUID, _ value: Entry) -> AgentJSONValue {
        .object(["transferID": .string(id.uuidString), "direction": .string(value.direction),
            "state": .string(value.ready ? "ready" : "receiving"), "byteLength": .integer(Int64(value.byteLength)),
            "receivedBytes": .integer(Int64(value.data.count)), "sha256": .string(value.sha256),
            "expiresAt": .string(ISO8601DateFormatter().string(from: value.expiresAt))])
    }
    private func insert(data: Data, byteLength: Int, sha256: String, direction: String,
                        resources: Set<AgentResourceReference>, grant: AgentGrant) throws -> AgentJSONValue {
        prune()
        guard byteLength >= 0, byteLength <= AgentTransferSchemas.maximumBytes,
              resources.allSatisfy({ grant.scope.permits($0) }), grant.expiresAt > now() else { throw AgentErrorCode.invalidInput }
        guard entries.count < maximumEntries,
              byteLength <= maximumReservedBytes - entries.values.reduce(0, { $0 + $1.byteLength }) else { throw AgentErrorCode.busy }
        let id = UUID(), date = now(), duration = min(300, grant.expiresAt.timeIntervalSince(date))
        let value = Entry(grant: grant, resources: resources, direction: direction,
            byteLength: byteLength, sha256: sha256, expiresAt: date.addingTimeInterval(duration),
            deadline: uptime() + duration, data: data, ready: direction == "export")
        entries[id] = value
        return metadata(id, value)
    }
    func export(_ data: Data, resources: Set<AgentResourceReference>, grant: AgentGrant) throws -> AgentJSONValue {
        guard data.count <= AgentTransferSchemas.maximumBytes else { throw AgentErrorCode.invalidInput }
        return try insert(data: data, byteLength: data.count, sha256: Self.digest(data), direction: "export",
            resources: resources, grant: grant)
    }
    func importedData(_ id: UUID, grant: AgentGrant) throws -> Data {
        let value = try entry(id, grant: grant)
        guard value.direction == "import", value.ready else { throw AgentErrorCode.invalidInput }
        return value.data
    }
    func perform(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant) throws -> [String: AgentJSONValue] {
        if request.operation == "transfers.beginImport" {
            guard case .integer(let length) = parameters["byteLength"], case .string(let hash) = parameters["sha256"] else {
                throw AgentErrorCode.invalidInput
            }
            return ["transfer": try insert(data: Data(), byteLength: Int(length), sha256: hash, direction: "import",
                resources: [], grant: grant)]
        }
        guard let id = request.targets.first?.id else { throw AgentErrorCode.invalidInput }
        var value = try entry(id, grant: grant)
        switch request.operation {
        case "transfers.appendChunk":
            guard value.direction == "import", !value.ready, case .integer(let offset) = parameters["offset"],
                  case .string(let text) = parameters["data"], let data = Data(base64Encoded: text),
                  !data.isEmpty, data.count <= AgentTransferSchemas.maximumChunkBytes,
                  data.base64EncodedString() == text, offset >= 0, offset <= Int64(value.data.count),
                  data.count <= value.byteLength - Int(offset) else { throw AgentErrorCode.invalidInput }
            if Int(offset) < value.data.count {
                guard Int(offset) + data.count <= value.data.count,
                      value.data.subdata(in: Int(offset)..<(Int(offset) + data.count)) == data else { throw AgentErrorCode.versionConflict }
            } else { value.data.append(data); entries[id] = value }
            return ["transfer": metadata(id, value)]
        case "transfers.finishImport":
            guard value.direction == "import", value.data.count == value.byteLength,
                  Self.digest(value.data) == value.sha256 else { throw AgentErrorCode.invalidInput }
            value.ready = true; entries[id] = value
            return ["transfer": metadata(id, value)]
        case "transfers.readChunk":
            guard value.direction == "export", value.ready, case .integer(let offset) = parameters["offset"],
                  case .integer(let length) = parameters["length"], offset >= 0, offset <= Int64(value.data.count),
                  length > 0, length <= AgentTransferSchemas.maximumChunkBytes else { throw AgentErrorCode.invalidInput }
            let start = Int(offset), end = start + min(Int(length), value.data.count - start)
            return ["transferID": .string(id.uuidString), "offset": .integer(offset),
                "byteLength": .integer(Int64(value.data.count)),
                "data": .string(value.data.subdata(in: start..<end).base64EncodedString()), "hasMore": .bool(end < value.data.count)]
        case "transfers.cancel":
            entries.removeValue(forKey: id)
            return ["transferID": .string(id.uuidString), "cancelled": .bool(true)]
        default: throw AgentErrorCode.unavailable
        }
    }
}
