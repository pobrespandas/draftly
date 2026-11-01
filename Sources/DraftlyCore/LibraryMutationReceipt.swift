import Foundation

package enum LibraryMutationReceiptError: Error, Equatable, Sendable {
    case invalidReceipt, requestConflict, retryWindowExpired, pendingChanges
}

package struct LibraryMutationIdentity: Codable, Equatable, Sendable {
    package let requestID: UUID
    package let connectionHash: String
    package let requestHash: String

    package init(requestID: UUID, connectionHash: String, requestHash: String) {
        self.requestID = requestID; self.connectionHash = connectionHash; self.requestHash = requestHash
    }

    func validate() throws {
        for hash in [connectionHash, requestHash] {
            guard hash.utf8.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw LibraryMutationReceiptError.invalidReceipt
            }
        }
    }
}

package struct LibraryMutationReceipt: Codable, Equatable, Sendable {
    package struct Resource: Codable, Equatable, Sendable {
        package let id: UUID
        package let versionToken: String
        package init(id: UUID, versionToken: String) { self.id = id; self.versionToken = versionToken }
    }
    let id: UUID
    package let mutation: LibraryMutationIdentity
    package let committedAt: Date
    package let resources: [Resource]

    func validate() throws {
        try mutation.validate()
        guard committedAt.timeIntervalSince1970.isFinite, !resources.isEmpty,
              Set(resources.map(\.id)).count == resources.count,
              resources.allSatisfy({ !$0.versionToken.isEmpty && $0.versionToken.unicodeScalars.count <= 4096 }) else {
            throw LibraryMutationReceiptError.invalidReceipt
        }
    }
}
