import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Local agent activity storage") @MainActor
struct AgentActivityStoreTests {
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
}
