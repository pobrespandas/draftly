import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Local agent activity storage") @MainActor
struct AgentActivityStoreTests {
    @Test func batchesPreserveEventsAndRejectInvalidBatchesAtomically() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Activity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: parent) }
        let now = Date(timeIntervalSince1970: 2_000_000_000), library = UUID(), connection = UUID()
        let store = try AgentActivityStore(parentDirectory: parent, now: { now })
        func entry(_ operation: String, _ date: Date) -> AgentActivityStore.Entry {
            .init(id: UUID(), libraryID: library, connectionID: connection, requestID: UUID(),
                  operation: operation, date: date, result: "success")
        }
        let first = entry("server.status", now.addingTimeInterval(-1))
        let second = entry("drafts.get", now)
        let expired = entry("server.status", now.addingTimeInterval(-31 * 24 * 60 * 60))
        try store.append([first, second, expired])
        let saved = try store.entries(libraryID: library)
        #expect(saved == [second, first])
        let valid = entry("server.status", now)
        let invalid = entry("private text", now)
        #expect(throws: AgentErrorCode.invalidInput) { try store.append([valid, invalid]) }
        #expect(throws: AgentErrorCode.invalidInput) { try store.append([valid, first]) }
        #expect(try store.entries(libraryID: library) == saved)
    }

    @Test func activityIsPrivatePersistentScopedAndClearable() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Activity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: parent) }
        let library = UUID(), other = UUID(), connection = UUID(), request = UUID()
        var clock = Date(timeIntervalSince1970: 2_000_000_000)
        let store = try AgentActivityStore(parentDirectory: parent, now: { clock })
        #expect(try store.entries(libraryID: library).isEmpty)
        try store.append(libraryID: library, connectionID: connection, requestID: request, operation: "drafts.get", result: "success")
        try store.append(libraryID: other, connectionID: connection, requestID: UUID(), operation: "drafts.get", result: "permission_denied")
        let reopened = try AgentActivityStore(parentDirectory: parent, now: { clock })
        let entries = try reopened.entries(libraryID: library)
        #expect(entries.count == 1 && entries[0].requestID == request && entries[0].result == "success")
        let file = parent.appendingPathComponent("Agents/activity.json")
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let bytes = try Data(contentsOf: file)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("draft content"))
        try reopened.clear(libraryID: library)
        #expect(try reopened.entries(libraryID: library).isEmpty)
        #expect(try reopened.entries(libraryID: other).count == 1)
        clock = clock.addingTimeInterval(31 * 24 * 60 * 60)
        #expect(try reopened.entries(libraryID: other).isEmpty)
        let pruned = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(!pruned.contains(other.uuidString))
        try reopened.append(libraryID: library, connectionID: connection, requestID: UUID(), operation: "server.status", result: "success")
        #expect(try reopened.entries(libraryID: other).isEmpty)
    }

    @Test func malformedHistoryAndInvalidOperationsAreNotOverwritten() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Activity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = try AgentActivityStore(parentDirectory: parent), library = UUID(), connection = UUID()
        #expect(throws: AgentErrorCode.invalidInput) {
            try store.append(libraryID: library, connectionID: connection, requestID: UUID(), operation: "private text", result: "success")
        }
        let file = parent.appendingPathComponent("Agents/activity.json"), invalid = Data("invalid".utf8)
        try invalid.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(throws: AgentErrorCode.storageError) { try store.clear(libraryID: library) }
        #expect(try Data(contentsOf: file) == invalid)
    }

    @Test func newerBoundedIdentifiersRemainReadableWithoutAllowingArbitraryNewWrites() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Activity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: parent) }
        let library = UUID(), connection = UUID(), now = Date()
        let store = try AgentActivityStore(parentDirectory: parent, now: { now })
        let newer = AgentActivityStore.Entry(id: UUID(), libraryID: library, connectionID: connection,
            requestID: UUID(), operation: "future.operation", date: now, result: "future_result")
        let file = parent.appendingPathComponent("Agents/activity.json")
        try JSONEncoder().encode([newer]).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(try store.entries(libraryID: library) == [newer])
        #expect(throws: AgentErrorCode.invalidInput) {
            try store.append(libraryID: library, connectionID: connection, requestID: UUID(), operation: "future.operation", result: "success")
        }
        try store.append(libraryID: library, connectionID: connection, requestID: UUID(), operation: "server.status", result: "success")
        #expect(try store.entries(libraryID: library).contains(newer))
    }
}
