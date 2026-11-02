import Foundation
import CryptoKit
import AgentContracts
import AgentLocalSecurity

// Reserve request identities before execution. Never persist request payloads.
@MainActor final class AgentOperationJournal {
    struct Record: Codable, Equatable {
        let connectionID: UUID
        let libraryID: UUID
        let requestID: UUID
        let operationID: UUID
        let requestFingerprint: String
        let grantFingerprint: String
        var snapshot: AgentJSONValue?
    }

    private let directory: AgentStateDirectory
    private let limit = 128
    private let name = "operations.json"
    private let lock = "operations.lock"

    init(parentDirectory: URL) throws {
        directory = try AgentStateDirectory(parentDirectory: parentDirectory)
        _ = try read()
    }

    func reserve(_ request: AgentRequest, grant: AgentGrant, operationID: UUID) throws -> (record: Record, isNew: Bool) {
        guard request.operation == "actions.run", request.libraryID == grant.libraryID else { throw AgentErrorCode.invalidInput }
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        let requestFingerprint = try fingerprint(prepared.value)
        let grantFingerprint = try fingerprint(AgentRequestBinding.grantValue(grant))
        var selected: Record?
        var isNew = false
        try update { records in
            isNew = false
            if let old = records.first(where: { $0.connectionID == grant.connectionID && $0.requestID == request.requestID }) {
                guard old.libraryID == grant.libraryID, old.grantFingerprint == grantFingerprint else {
                    throw AgentErrorCode.permissionDenied
                }
                guard old.requestFingerprint == requestFingerprint else { throw AgentErrorCode.versionConflict }
                selected = old
            } else {
                guard records.count < limit, !records.contains(where: { $0.operationID == operationID }) else {
                    throw AgentErrorCode.busy
                }
                let record = Record(connectionID: grant.connectionID, libraryID: grant.libraryID,
                    requestID: request.requestID, operationID: operationID, requestFingerprint: requestFingerprint,
                    grantFingerprint: grantFingerprint)
                records.append(record); selected = record; isNew = true
            }
        }
        guard let selected else { throw AgentErrorCode.storageError }
        return (selected, isNew)
    }

    func record(_ operationID: UUID, grant: AgentGrant) throws -> Record? {
        guard let record = try read().records.first(where: { $0.operationID == operationID && $0.connectionID == grant.connectionID }) else {
            return nil
        }
        guard record.libraryID == grant.libraryID,
              record.grantFingerprint == (try fingerprint(AgentRequestBinding.grantValue(grant))) else {
            throw AgentErrorCode.permissionDenied
        }
        return record
    }

    func save(_ snapshot: AgentJSONValue, operationID: UUID, grant: AgentGrant) throws {
        try validateSnapshot(snapshot, operationID: operationID)
        let grantFingerprint = try fingerprint(AgentRequestBinding.grantValue(grant))
        try update { records in
            guard let index = records.firstIndex(where: { $0.operationID == operationID && $0.connectionID == grant.connectionID }) else {
                throw AgentErrorCode.notFound
            }
            guard records[index].libraryID == grant.libraryID, records[index].grantFingerprint == grantFingerprint else {
                throw AgentErrorCode.permissionDenied
            }
            records[index].snapshot = snapshot
        }
    }

    private func fingerprint(_ value: AgentJSONValue) throws -> String {
        Data(SHA256.hash(data: try AgentRequestBinding.encoded(value, maximum: AgentRequest.maximumBytes * 2))).base64EncodedString()
    }

    private func validateSnapshot(_ value: AgentJSONValue, operationID: UUID) throws {
        try AgentExecutionSchemas.validateResult(["operation": value], for: "operations.get")
        guard case .object(let fields) = value,
              fields["operationID"] == .string(operationID.uuidString), fields["name"] == .string("actions.run") else {
            throw AgentErrorCode.invalidInput
        }
    }

    private func read() throws -> (data: Data?, records: [Record]) {
        let data = try directory.read(name, lockName: lock, maximumBytes: AgentRequest.maximumBytes)
        guard let data else { return (nil, []) }
        do {
            let records = try JSONDecoder().decode([Record].self, from: data)
            guard records.count <= limit, Set(records.map(\.operationID)).count == records.count,
                  Set(records.map { $0.connectionID.uuidString + "/" + $0.requestID.uuidString }).count == records.count else {
                throw AgentErrorCode.storageError
            }
            for record in records {
                guard Data(base64Encoded: record.requestFingerprint)?.count == 32,
                      Data(base64Encoded: record.grantFingerprint)?.count == 32 else { throw AgentErrorCode.storageError }
                if let snapshot = record.snapshot { try validateSnapshot(snapshot, operationID: record.operationID) }
            }
            return (data, records)
        } catch { throw AgentErrorCode.storageError }
    }

    private func update(_ change: (inout [Record]) throws -> Void) throws {
        for _ in 0..<3 {
            let old = try read()
            var records = old.records; try change(&records)
            guard records != old.records else { return }
            do {
                try directory.replace(name, lockName: lock, data: JSONEncoder().encode(records),
                    expected: old.data, maximumBytes: AgentRequest.maximumBytes)
                return
            } catch AgentErrorCode.versionConflict { continue }
        }
        throw AgentErrorCode.busy
    }
}
