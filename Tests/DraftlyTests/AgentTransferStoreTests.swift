import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Scoped agent transfer storage") @MainActor
struct AgentTransferStoreTests {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_700_000_000)
        var tick: TimeInterval = 100
    }
    private func grant(_ date: Date, connectionID: UUID = UUID(), grantID: UUID = UUID(),
                       scope: AgentResourceScope = .library) -> AgentGrant {
        .init(connectionID: connectionID, libraryID: UUID(), expiresAt: date.addingTimeInterval(900),
              capabilities: [.filesRead, .filesWrite, .draftsRead], scope: scope, grantID: grantID)
    }
    private func id(_ metadata: AgentJSONValue) throws -> UUID {
        guard case .object(let fields) = metadata, case .string(let rawID) = fields["transferID"], let id = UUID(uuidString: rawID) else {
            throw AgentErrorCode.storageError
        }
        return id
    }
    private func request(_ name: String, id: UUID? = nil) -> AgentRequest {
        .init(requestID: UUID(), libraryID: nil, operation: name, targets: id.map { [.init(kind: .operation, id: $0)] } ?? [])
    }
    @Test func capacityIsReservedAndReleasedOnCancelExpiryAndInvalidation() throws {
        let clock = Clock(), access = grant(Date(timeIntervalSince1970: 1_700_000_000))
        let store = AgentTransferStore(now: { clock.date }, uptime: { clock.tick }, maximumEntries: 2, maximumReservedBytes: 6)
        let first = try id(store.export(Data([1, 2, 3, 4]), resources: [], grant: access))
        #expect(throws: AgentErrorCode.busy) { try store.export(Data([1, 2, 3]), resources: [], grant: access) }
        _ = try store.perform(request("transfers.cancel", id: first), parameters: [:], grant: access)
        _ = try store.export(Data([1, 2, 3]), resources: [], grant: access)
        store.remove(connectionID: access.connectionID)
        let current = try id(store.export(Data([1, 2, 3, 4, 5, 6]), resources: [], grant: access))
        clock.date -= 600; clock.tick += 301
        #expect(throws: AgentErrorCode.notFound) { try store.authorize(current, grant: access) }
        _ = try store.export(Data([1, 2, 3, 4, 5, 6]), resources: [], grant: access)
    }
    @Test func ownershipIncludesConnectionAndExactGrantAndSourceScope() throws {
        let clock = Clock(), source = AgentResourceReference(kind: .draft, id: UUID())
        let access = grant(clock.date, scope: .resources([source]))
        let store = AgentTransferStore(now: { clock.date }, uptime: { clock.tick })
        let transfer = try id(store.export(Data("Scoped".utf8), resources: [source], grant: access))
        let other = AgentGrant(connectionID: UUID(), libraryID: access.libraryID, expiresAt: access.expiresAt,
            capabilities: access.capabilities, scope: access.scope, grantID: access.grantID)
        #expect(throws: AgentErrorCode.notFound) { try store.authorize(transfer, grant: other) }
        let changed = AgentGrant(connectionID: access.connectionID, libraryID: access.libraryID, expiresAt: access.expiresAt,
            capabilities: access.capabilities, scope: .library, grantID: access.grantID)
        #expect(throws: AgentErrorCode.notFound) { try store.authorize(transfer, grant: changed) }
        let replaced = AgentGrant(connectionID: access.connectionID, libraryID: access.libraryID, expiresAt: access.expiresAt,
            capabilities: access.capabilities, scope: access.scope, grantID: UUID())
        #expect(throws: AgentErrorCode.notFound) { try store.authorize(transfer, grant: replaced) }
        try store.authorize(transfer, grant: access)
        #expect(throws: AgentErrorCode.invalidInput) {
            try store.export(Data("Hidden".utf8), resources: [.init(kind: .draft, id: UUID())], grant: access)
        }
        store.removeAll()
        #expect(throws: AgentErrorCode.notFound) { try store.authorize(transfer, grant: access) }
    }
    @Test func importsVerifyDigestAndPreserveByteOffsetsAcrossUnicodeBoundaries() throws {
        let clock = Clock(), access = grant(Date(timeIntervalSince1970: 1_700_000_000))
        let store = AgentTransferStore(now: { clock.date }, uptime: { clock.tick })
        let data = Data("🐼 café e\u{301}".utf8)
        let begun = try store.perform(request("transfers.beginImport"), parameters: ["byteLength": .integer(Int64(data.count)),
            "sha256": .string(AgentTransferStore.digest(data))], grant: access)
        let transfer = try id(#require(begun["transfer"]))
        #expect(throws: AgentErrorCode.invalidInput) { try store.importedData(transfer, grant: access) }
        for (offset, bytes) in [(0, data.prefix(2)), (2, data.dropFirst(2))] {
            _ = try store.perform(request("transfers.appendChunk", id: transfer),
                parameters: ["offset": .integer(Int64(offset)), "data": .string(Data(bytes).base64EncodedString())], grant: access)
        }
        #expect(throws: AgentErrorCode.versionConflict) {
            try store.perform(request("transfers.appendChunk", id: transfer),
                parameters: ["offset": .integer(0), "data": .string(Data([0, 0]).base64EncodedString())], grant: access)
        }
        _ = try store.perform(request("transfers.finishImport", id: transfer), parameters: [:], grant: access)
        #expect(try store.importedData(transfer, grant: access) == data)
        let wrong = try store.perform(request("transfers.beginImport"), parameters: ["byteLength": .integer(1),
            "sha256": .string(AgentTransferStore.digest(Data([1])))], grant: access)
        let wrongID = try id(#require(wrong["transfer"]))
        _ = try store.perform(request("transfers.appendChunk", id: wrongID), parameters: ["offset": .integer(0),
            "data": .string(Data([2]).base64EncodedString())], grant: access)
        #expect(throws: AgentErrorCode.invalidInput) {
            try store.perform(request("transfers.finishImport", id: wrongID), parameters: [:], grant: access)
        }
    }
    @Test func exportChunkOffsetsReassembleExactBytesAndRejectInvalidOffsets() throws {
        let clock = Clock(), access = grant(Date(timeIntervalSince1970: 1_700_000_000))
        let store = AgentTransferStore(now: { clock.date }, uptime: { clock.tick })
        let data = Data("🐼 e\u{301}".utf8)
        let transfer = try id(store.export(data, resources: [], grant: access))
        var restored = Data()
        while restored.count < data.count {
            let result = try store.perform(request("transfers.readChunk", id: transfer),
                parameters: ["offset": .integer(Int64(restored.count)), "length": .integer(2)], grant: access)
            guard case .string(let text) = result["data"], let bytes = Data(base64Encoded: text) else { throw AgentErrorCode.storageError }
            restored.append(bytes)
            #expect(result["hasMore"] == .bool(restored.count < data.count))
        }
        #expect(restored == data)
        #expect(throws: AgentErrorCode.invalidInput) {
            try store.perform(request("transfers.readChunk", id: transfer), parameters: ["offset": .integer(Int64(data.count + 1)),
                "length": .integer(2)], grant: access)
        }
    }
}
