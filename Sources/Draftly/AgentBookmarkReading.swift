import Foundation
import CryptoKit
import AgentContracts
import DraftlyCore

// The wire catalog contains aliases, not file paths or saved permission bytes.
@MainActor final class AgentBookmarkReading {
    static let operationNames: Set<String> = ["bookmarks.list"]
    static let reviewedOperations: Set<String> = ["bookmarks.requestAdd", "bookmarks.forget"]
    private let defaults: UserDefaults
    private let pages: AgentReadPages
    private let key = SymmetricKey(size: .bits256)

    init(defaults: UserDefaults, pages: AgentReadPages) { self.defaults = defaults; self.pages = pages }

    func read(_ request: AgentRequest, parameters: [String: AgentJSONValue], sessionID: UUID,
              grant: AgentGrant) throws -> [String: AgentJSONValue] {
        let records: [BookmarkPreferences.AgentRecord]
        do {
            records = try BookmarkPreferences.agentRecords(defaults: defaults).filter {
                grant.scope.permits(.init(kind: .bookmark, id: $0.id))
            }
        } catch { throw AgentErrorCode.storageError }
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try pages.page(owner: .init(connectionID: grant.connectionID, grantID: grant.grantID), request: request,
            parameters: parameters, expiresAt: grant.expiresAt, ids: { records.map(\.id) }, value: { id in
                guard let record = byID[id] else { return nil }
                return .object(try self.summary(record))
            })
    }

    private func summary(_ record: BookmarkPreferences.AgentRecord) throws -> [String: AgentJSONValue] {
        let id = AgentJSONValue.string(record.id.uuidString)
        let name = AgentJSONValue.string(record.name)
        let value = AgentJSONValue.object(["id": id, "name": name,
            "digest": .string(Data(SHA256.hash(data: record.data)).base64EncodedString())])
        let bytes = try AgentRequestBinding.encoded(value, maximum: AgentRequest.maximumBytes)
        let version = Data(HMAC<SHA256>.authenticationCode(for: bytes, using: key)).base64EncodedString()
        return ["id": id, "name": name, "versionToken": .string(version)]
    }

    func review(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant,
                operationID: UUID, approvals: AgentApprovalStore, operations: AgentOperationRegistry,
                authorize: @escaping () throws -> Void,
                select: NativeFileSelector) async throws -> [String: AgentJSONValue] {
        var submitted = false
        let effect = UUID()
        do {
            let adding = request.operation == "bookmarks.requestAdd"
            let name: String
            let target: UUID?
            if adding {
                guard case .string(let proposed) = parameters["name"], proposed.utf8.count <= 255,
                      !proposed.contains("\0") else { throw AgentErrorCode.invalidInput }
                guard parameters["interactive"] == .bool(true) else { throw AgentErrorCode.interactionRequired }
                name = proposed
                target = nil
            } else {
                guard let id = request.targets.first?.id else { throw AgentErrorCode.invalidInput }
                guard let record = try BookmarkPreferences.agentRecords(defaults: defaults).first(where: { $0.id == id }) else {
                    throw AgentErrorCode.notFound
                }
                name = record.name
                target = id
            }
            @MainActor func checkedRecord() throws -> BookmarkPreferences.AgentRecord? {
                try Task.checkCancellation()
                try authorize()
                if let target {
                    guard let record = try BookmarkPreferences.agentRecords(defaults: defaults).first(where: { $0.id == target }) else {
                        throw AgentErrorCode.notFound
                    }
                    guard try summary(record)["versionToken"] == request.expectedVersion.map(AgentJSONValue.string) else {
                        throw AgentErrorCode.versionConflict
                    }
                    return record
                }
                guard !BookmarkPreferences.names(defaults: defaults).contains(name) else {
                    throw AgentErrorCode.versionConflict
                }
                return nil
            }
            @MainActor func markSubmitted() throws {
                try Task.checkCancellation()
                try authorize()
                try operations.recordEffect(operationID, effectID: effect, kind: request.operation, outcome: "submitted")
                submitted = true
            }
            try operations.setWaitingForUser(operationID, waiting: true)
            try await approvals.waitForApproval(request, connectionID: grant.connectionID, resolveEffects: {
                let record = try checkedRecord()
                var snapshot: [String: AgentJSONValue] = ["bookmarkName": .string(name)]
                if let record { snapshot["bookmarkVersion"] = try self.summary(record)["versionToken"] }
                return .init(capabilities: [.preferencesWrite], targets: Set(request.targets),
                    requiresLibraryScope: false, snapshot: snapshot)
            })
            let result: [String: AgentJSONValue]
            if let record = try checkedRecord() {
                try operations.setWaitingForUser(operationID, waiting: false)
                try BookmarkPreferences.forgetForAgent(record, defaults: defaults, beforeCommit: markSubmitted)
                result = ["deletedIDs": .array([.string(record.id.uuidString)])]
            } else {
                guard let url = try await select(.folder(name: name)) else { throw AgentErrorCode.cancelled }
                try operations.setWaitingForUser(operationID, waiting: false)
                _ = try checkedRecord()
                let data = try BookmarkPreferences.data(for: url)
                let record = try BookmarkPreferences.addForAgent(data, named: name, defaults: defaults, beforeCommit: markSubmitted)
                result = ["bookmark": .object(try summary(record))]
            }
            try AgentBookmarkSchemas.validateResult(result, for: request)
            try operations.recordEffect(operationID, effectID: effect, kind: request.operation, outcome: "completed")
            return result
        } catch {
            if submitted { throw AgentErrorCode.outcomeUnknown }
            let code: AgentErrorCode
            if let interruption = error as? ActionExecutionInterruption {
                switch interruption {
                case .cancelled: code = .cancelled
                case .timeout: code = .timeout
                }
            } else {
                code = error is CancellationError ? .cancelled : (error as? AgentErrorCode ?? .storageError)
            }
            throw AgentOperationRegistry.FailureBeforeEffects(code: code)
        }
    }
}
