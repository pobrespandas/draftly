import Foundation
import Darwin
import Testing
import AgentContracts
@testable import Draftly

@Suite("Scoped local import input") @MainActor
struct AgentImportReadingTests {
    @Test(arguments: ["valid", "size", "scope", "capability", "parent", "symlink", "directory", "fifo", "revoked", "rootChanged", "bookmarkChanged", "finalSymlink"])
    func bookmarkInputStaysWithinItsGrant(mode: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "Draftly.ImportReading." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("granted")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let bytes = Data("café 🐼".utf8), file = directory.appendingPathComponent("input.json")
        try bytes.write(to: file)
        try bytes.write(to: root.appendingPathComponent("outside.json"))
        BookmarkPreferences.store(try BookmarkPreferences.data(for: directory), named: "QA", defaults: defaults)
        let record = try #require(try BookmarkPreferences.agentRecords(defaults: defaults).first)
        var path = "input.json"
        if mode == "parent" { path = "../outside.json" }
        if mode == "symlink" {
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("escape"), withDestinationURL: root)
            path = "escape/outside.json"
        }
        if mode == "finalSymlink" {
            path = "leaf"
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(path), withDestinationURL: root.appendingPathComponent("outside.json"))
        }
        if mode == "directory" { path = "folder"; try FileManager.default.createDirectory(at: directory.appendingPathComponent(path), withIntermediateDirectories: false) }
        if mode == "fifo" { path = "pipe"; #expect(mkfifo(directory.appendingPathComponent(path).path, 0o600) == 0) }
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: Date().addingTimeInterval(300),
            capabilities: mode == "capability" ? [] : [.filesRead], scope: .resources(mode == "scope" ? [] : [.init(kind: .bookmark, id: record.id)]))
        let source: AgentJSONValue = .object(["kind": .string("bookmark"), "bookmarkID": .string(record.id.uuidString), "path": .string(path)])
        let transfers = AgentTransferStore(now: Date.init, uptime: { ProcessInfo.processInfo.systemUptime })
        var checks = 0
        func read() throws -> Data {
            try AgentImportReading.data(source, grant: grant, defaults: defaults, transfers: transfers,
                maximumBytes: mode == "size" ? bytes.count - 1 : bytes.count, authorize: {
                    checks += 1
                    if mode == "rootChanged", checks == 2 {
                        try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("held"))
                        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: root)
                    }
                    if mode == "bookmarkChanged", checks == 3 {
                        BookmarkPreferences.store(Data("replacement permission".utf8), named: "QA", defaults: defaults)
                    }
                    if mode == "revoked", checks > 2 { throw AgentErrorCode.permissionDenied }
                })
        }
        if mode == "valid" { #expect(try read() == bytes) }
        else { #expect(throws: (any Error).self) { try read() } }
        #expect(try Data(contentsOf: mode == "rootChanged" ? root.appendingPathComponent("held/input.json") : file) == bytes)
        #expect(try Data(contentsOf: root.appendingPathComponent("outside.json")) == bytes)
    }
}
