import Foundation
import CryptoKit
import AgentContracts

// The wire catalog contains aliases, not file paths or saved permission bytes.
@MainActor final class AgentBookmarkReading {
    static let operationNames: Set<String> = ["bookmarks.list"]
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
                let value: AgentJSONValue = .object(["id": .string(id.uuidString), "name": .string(record.name),
                    "digest": .string(Data(SHA256.hash(data: record.data)).base64EncodedString())])
                let bytes = try AgentRequestBinding.encoded(value, maximum: AgentRequest.maximumBytes)
                let version = Data(HMAC<SHA256>.authenticationCode(for: bytes, using: self.key)).base64EncodedString()
                return .object(["id": .string(id.uuidString), "name": .string(record.name), "versionToken": .string(version)])
            })
    }
}
