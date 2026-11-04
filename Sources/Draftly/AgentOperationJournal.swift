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
        var operationName: String? = nil
        var snapshot: AgentJSONValue?
    }

    private let directory: AgentStateDirectory
    private let legacyLimit = 128
    private let name = "operations.json"
    private let lock = "operations.lock"

    init(parentDirectory: URL) throws {
        directory = try AgentStateDirectory(parentDirectory: parentDirectory)
        try locked { try migrateLegacy() }
    }

    func reserve(_ request: AgentRequest, grant: AgentGrant, operationID: UUID) throws -> (record: Record, isNew: Bool) {
        guard Self.supports(request.operation), request.libraryID == grant.libraryID else { throw AgentErrorCode.invalidInput }
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        let requestFingerprint = try fingerprint(prepared.value)
        let grantFingerprint = try fingerprint(AgentRequestBinding.grantValue(grant))
        return try locked {
            if let old = try loadRequest(connectionID: grant.connectionID, requestID: request.requestID) {
                try validateGrant(old, grant: grant, fingerprint: grantFingerprint)
                guard old.requestFingerprint == requestFingerprint else { throw AgentErrorCode.versionConflict }
                return (old, false)
            }
            guard try loadOperation(operationID) == nil else { throw AgentErrorCode.busy }
            let record = Record(connectionID: grant.connectionID, libraryID: grant.libraryID,
                requestID: request.requestID, operationID: operationID, requestFingerprint: requestFingerprint,
                grantFingerprint: grantFingerprint, operationName: request.operation)
            try write(record)
            return (record, true)
        }
    }

    func record(_ operationID: UUID, grant: AgentGrant) throws -> Record? {
        try locked {
            guard let record = try loadOperation(operationID), record.connectionID == grant.connectionID else { return nil }
            try validateGrant(record, grant: grant, fingerprint: fingerprint(AgentRequestBinding.grantValue(grant)))
            return record
        }
    }

    func existingRequest(_ request: AgentRequest, grant: AgentGrant) throws -> Record? {
        guard Self.supports(request.operation), request.libraryID == grant.libraryID else { throw AgentErrorCode.invalidInput }
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        return try locked {
            guard let record = try loadRequest(connectionID: grant.connectionID, requestID: request.requestID) else { return nil }
            try validateGrant(record, grant: grant, fingerprint: fingerprint(AgentRequestBinding.grantValue(grant)))
            guard record.requestFingerprint == (try fingerprint(prepared.value)) else { throw AgentErrorCode.versionConflict }
            return record
        }
    }

    func save(_ snapshot: AgentJSONValue, operationID: UUID, grant: AgentGrant) throws {
        try validateSnapshot(snapshot, operationID: operationID)
        let grantFingerprint = try fingerprint(AgentRequestBinding.grantValue(grant))
        try locked {
            guard var record = try loadOperation(operationID), record.connectionID == grant.connectionID else {
                throw AgentErrorCode.notFound
            }
            try validateGrant(record, grant: grant, fingerprint: grantFingerprint)
            try validateSnapshot(snapshot, operationID: operationID, name: record.operationName ?? "actions.run")
            if let previous = record.snapshot, previous != snapshot,
               case .object(let fields) = previous, case .string(let raw) = fields["state"],
               let state = AgentOperationState(rawValue: raw), state.isTerminal {
                throw AgentErrorCode.versionConflict
            }
            record.snapshot = snapshot
            try write(record)
        }
    }

    // The app calls this only after it reads an atomic deletion receipt.
    func recoverDeletion(_ snapshot: AgentJSONValue, request: AgentRequest, grant: AgentGrant) throws {
        guard ["workspaces.delete", "drafts.purge", "actions.delete", "actionGroups.delete"].contains(request.operation), request.libraryID == grant.libraryID,
              case .object(let fields) = snapshot, fields["state"] == .string("succeeded"),
              case .string(let rawID) = fields["operationID"], let operationID = UUID(uuidString: rawID),
              case .object(let result) = fields["result"] else { throw AgentErrorCode.invalidInput }
        try AgentOperationSchemas.validateResult(result, for: request, preferences: AgentPreferenceCatalog.make())
        try validateSnapshot(snapshot, operationID: operationID, name: request.operation)
        let prepared = try AgentRequestBinding.prepare(request, preferences: AgentPreferenceCatalog.make())
        let requestFingerprint = try fingerprint(prepared.value)
        let grantFingerprint = try fingerprint(AgentRequestBinding.grantValue(grant))
        try locked {
            guard var record = try loadOperation(operationID), record.connectionID == grant.connectionID else {
                throw AgentErrorCode.notFound
            }
            try validateGrant(record, grant: grant, fingerprint: grantFingerprint)
            guard record.requestID == request.requestID, record.operationName == request.operation,
                  record.requestFingerprint == requestFingerprint else { throw AgentErrorCode.versionConflict }
            guard case .object(let previous) = record.snapshot,
                  previous["state"] == .string("outcome_unknown") else { throw AgentErrorCode.versionConflict }
            record.snapshot = snapshot
            try write(record)
        }
    }

    private func fingerprint(_ value: AgentJSONValue) throws -> String {
        Data(SHA256.hash(data: try AgentRequestBinding.encoded(value, maximum: AgentRequest.maximumBytes * 2))).base64EncodedString()
    }

    static func supports(_ name: String) -> Bool {
        guard let operation = AgentOperationCatalog.operation(named: name) else { return false }
        // Backup readers can own a reviewed HTTPS input effect.
        return operation.requiresEffectAuthorization || operation.requiresHumanApproval
            || ["backups.validate", "backups.previewRestore"].contains(name)
    }

    private func validateSnapshot(_ value: AgentJSONValue, operationID: UUID, name: String? = nil) throws {
        try AgentExecutionSchemas.validateResult(["operation": value], for: "operations.get")
        guard case .object(let fields) = value,
              fields["operationID"] == .string(operationID.uuidString),
              case .string(let actualName) = fields["name"], Self.supports(actualName),
              name == nil || name == actualName else {
            throw AgentErrorCode.invalidInput
        }
        if actualName != "actions.run", fields["state"] == .string("succeeded") {
            guard case .object(let result) = fields["result"] else { throw AgentErrorCode.invalidInput }
            try AgentOperationSchemas.validateResult(result, for: actualName, preferences: AgentPreferenceCatalog.make())
        }
    }

    private struct Format: Codable, Equatable { let format: Int }

    private struct OperationIndex: Codable, Equatable {
        let connectionID: UUID
        let requestID: UUID
    }

    private func requestName(connectionID: UUID, requestID: UUID) -> String {
        "operation-request-" + connectionID.uuidString + "-" + requestID.uuidString + ".json"
    }

    private func operationName(_ id: UUID) -> String { "operation-index-" + id.uuidString + ".json" }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        let lease = try directory.acquireLock(lock)
        return try withExtendedLifetime(lease, body)
    }

    private func validateGrant(_ record: Record, grant: AgentGrant, fingerprint: String) throws {
        guard record.libraryID == grant.libraryID, record.grantFingerprint == fingerprint else {
            throw AgentErrorCode.permissionDenied
        }
    }

    private func validateRecord(_ record: Record) throws {
        guard Data(base64Encoded: record.requestFingerprint)?.count == 32,
              Data(base64Encoded: record.grantFingerprint)?.count == 32,
              Self.supports(record.operationName ?? "actions.run") else { throw AgentErrorCode.storageError }
        if let snapshot = record.snapshot {
            try validateSnapshot(snapshot, operationID: record.operationID, name: record.operationName ?? "actions.run")
        }
    }

    // A format barrier prevents older apps from ignoring the new request records.
    private func migrateLegacy() throws {
        let old = try directory.readSnapshot(name, maximumBytes: AgentRequest.maximumBytes)
        if let old, (try? JSONDecoder().decode(Format.self, from: old)) == Format(format: 2) {
            _ = try readLegacy()
            return
        }
        let preserved = try directory.readSnapshot("operations-legacy.json", maximumBytes: AgentRequest.maximumBytes)
        let data = old ?? preserved ?? Data("[]".utf8)
        _ = try decodeLegacy(data)
        try replace("operations-legacy.json", data: data, maximumBytes: AgentRequest.maximumBytes)
        try replace(name, data: JSONEncoder().encode(Format(format: 2)), maximumBytes: AgentRequest.maximumBytes)
    }

    private func readLegacy() throws -> [Record] {
        guard let marker = try directory.readSnapshot(name, maximumBytes: AgentRequest.maximumBytes),
              (try? JSONDecoder().decode(Format.self, from: marker)) == Format(format: 2),
              let data = try directory.readSnapshot("operations-legacy.json", maximumBytes: AgentRequest.maximumBytes) else {
            throw AgentErrorCode.storageError
        }
        return try decodeLegacy(data)
    }

    private func decodeLegacy(_ data: Data) throws -> [Record] {
        do {
            let records = try JSONDecoder().decode([Record].self, from: data)
            guard records.count <= legacyLimit, Set(records.map(\.operationID)).count == records.count,
                  Set(records.map { $0.connectionID.uuidString + "/" + $0.requestID.uuidString }).count == records.count else {
                throw AgentErrorCode.storageError
            }
            for record in records { try validateRecord(record) }
            return records
        } catch { throw AgentErrorCode.storageError }
    }

    private func loadRequest(connectionID: UUID, requestID: UUID) throws -> Record? {
        let legacy = try readLegacy().first { $0.connectionID == connectionID && $0.requestID == requestID }
        guard let data = try directory.readSnapshot(requestName(connectionID: connectionID, requestID: requestID),
            maximumBytes: AgentRequest.maximumBytes) else { return legacy }
        do {
            let record = try JSONDecoder().decode(Record.self, from: data)
            try validateRecord(record)
            guard record.connectionID == connectionID, record.requestID == requestID else { throw AgentErrorCode.storageError }
            if let legacy {
                guard record.operationID == legacy.operationID, record.libraryID == legacy.libraryID,
                      record.requestFingerprint == legacy.requestFingerprint,
                      record.grantFingerprint == legacy.grantFingerprint,
                      (record.operationName ?? "actions.run") == (legacy.operationName ?? "actions.run") else {
                    throw AgentErrorCode.storageError
                }
            }
            return record
        } catch { throw AgentErrorCode.storageError }
    }

    private func loadOperation(_ id: UUID) throws -> Record? {
        guard let data = try directory.readSnapshot(operationName(id), maximumBytes: 1024) else {
            guard let legacy = try readLegacy().first(where: { $0.operationID == id }) else { return nil }
            return try loadRequest(connectionID: legacy.connectionID, requestID: legacy.requestID)
        }
        do {
            let index = try JSONDecoder().decode(OperationIndex.self, from: data)
            guard let record = try loadRequest(connectionID: index.connectionID, requestID: index.requestID),
                  record.operationID == id else { throw AgentErrorCode.storageError }
            return record
        } catch { throw AgentErrorCode.storageError }
    }

    private func replace(_ name: String, data: Data, maximumBytes: Int) throws {
        let old = try directory.readSnapshot(name, maximumBytes: maximumBytes)
        guard old != data else { return }
        try directory.replace(name, lockName: "operations-data.lock", data: data, expected: old, maximumBytes: maximumBytes)
    }

    private func write(_ record: Record) throws {
        try validateRecord(record)
        let index = OperationIndex(connectionID: record.connectionID, requestID: record.requestID)
        let indexName = operationName(record.operationID)
        if let old = try directory.readSnapshot(indexName, maximumBytes: 1024) {
            guard (try? JSONDecoder().decode(OperationIndex.self, from: old)) == index else {
                throw AgentErrorCode.storageError
            }
        }
        // Publish the index first. Work starts only after both writes are durable.
        // A failed second write cannot submit work. Keep its index as evidence.
        try replace(indexName, data: JSONEncoder().encode(index), maximumBytes: 1024)
        try replace(requestName(connectionID: record.connectionID, requestID: record.requestID),
            data: JSONEncoder().encode(record), maximumBytes: AgentRequest.maximumBytes)
    }
}
