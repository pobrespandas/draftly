import Foundation
import Darwin
import Testing
import AgentContracts
import AgentLocalSecurity

@Suite("Private agent host discovery hints") @MainActor
struct AgentHostLocatorTests {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Locator-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return root
    }
    private func record(_ name: String = "neutral") throws -> AgentHostLocator.Endpoint {
        try .init(libraryID: UUID(), socketPath: "/tmp/da-" + name + "/s")
    }
    private func manifest(_ hosts: [AgentHostLocator.Endpoint], version: AgentJSONValue = .integer(1)) throws -> Data {
        try JSONEncoder().encode(AgentJSONValue.object(["version": version, "hosts": .array(hosts.map {
            .object(["libraryID": .string($0.libraryID.uuidString), "epochID": .string($0.epochID.uuidString), "socketPath": .string($0.socketPath)])
        })]))
    }

    @Test func readOnlyDiscoveryDoesNotCreateDirectoriesLocksOrMetadata() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: AgentErrorCode.notFound) { try AgentHostLocator(parentDirectory: root) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Agents").path))
        #expect(throws: AgentErrorCode.notFound) { try AgentHostLocator(parentDirectory: root.appendingPathComponent("missing")) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("missing").path))
        let publisher = try AgentHostLocator(parentDirectory: root, createIfMissing: true)
        let reader = try AgentHostLocator(parentDirectory: root)
        #expect(try publisher.endpoints().isEmpty && reader.endpoints().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Agents").path).isEmpty)
    }

    @Test func publicationAndExactEpochWithdrawalPreserveOtherLibrariesAndNewerOwners() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AgentHostLocator(parentDirectory: root, createIfMissing: true)
        let first = try record("first"), other = try record("other")
        try writer.publish(first); try writer.publish(other)
        let reader = try AgentHostLocator(parentDirectory: root)
        #expect(try reader.endpoints() == [first, other].sorted { $0.libraryID.uuidString < $1.libraryID.uuidString })
        let next = try AgentHostLocator.Endpoint(libraryID: first.libraryID, socketPath: "/tmp/da-next/s")
        try writer.publish(next)
        let bytes = try Data(contentsOf: root.appendingPathComponent("Agents/hosts.json"))
        #expect(try !writer.withdraw(first))
        #expect(try Data(contentsOf: root.appendingPathComponent("Agents/hosts.json")) == bytes)
        #expect(try Set(reader.endpoints().map(\.libraryID)) == [first.libraryID, other.libraryID])
        #expect(try writer.withdraw(next) && !writer.withdraw(next))
        #expect(try reader.endpoints() == [other])
        #expect(try writer.withdraw(other) && reader.endpoints().isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Agents/hosts.lock").path))
    }

    @Test func malformedUnknownOversizedAndDuplicateRecordsAreNotRepaired() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let locator = try AgentHostLocator(parentDirectory: root, createIfMissing: true), entry = try record()
        try locator.publish(entry)
        let file = root.appendingPathComponent("Agents/hosts.json")
        let unknown = Data("{\"version\":1,\"hosts\":[],\"credential\":\"forbidden\"}".utf8)
        let foreign = try manifest([.init(libraryID: UUID(), epochID: entry.epochID, socketPath: "/tmp/da-other/s"), entry])
        for invalid in [Data("not JSON".utf8), unknown, try manifest([entry], version: .bool(true)),
                        try manifest([entry], version: .integer(2)), try manifest([entry, entry]), foreign,
                        Data(repeating: 32, count: 65_537)] {
            try invalid.write(to: file)
            #expect(throws: AgentErrorCode.storageError) { try locator.endpoints() }
            #expect(throws: AgentErrorCode.storageError) { try locator.publish(record("replacement")) }
            #expect(try Data(contentsOf: file) == invalid)
        }
    }

    @Test func pathValidationUsesUtf8BytesAndRejectsRelativeAndNullPaths() throws {
        for path in ["relative/s", "/tmp/\0/s", "/" + String(repeating: "x", count: 104), "/" + String(repeating: "🐼", count: 27)] {
            #expect(throws: AgentErrorCode.invalidInput) { try AgentHostLocator.Endpoint(libraryID: UUID(), socketPath: path) }
        }
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let locator = try AgentHostLocator(parentDirectory: root, createIfMissing: true)
        let unicode = try AgentHostLocator.Endpoint(libraryID: UUID(), socketPath: "/tmp/da-café-🐼/s")
        try locator.publish(unicode)
        #expect(try locator.endpoints() == [unicode])
    }

    @Test func readSnapshotsRejectUnsafeFilesWithoutFollowingOrRepairingThem() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let locator = try AgentHostLocator(parentDirectory: root, createIfMissing: true), entry = try record()
        try locator.publish(entry)
        let file = root.appendingPathComponent("Agents/hosts.json"), target = root.appendingPathComponent("target")
        let bytes = try manifest([entry]); try bytes.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        #expect(throws: AgentErrorCode.permissionDenied) { try locator.endpoints() }
        #expect(try Data(contentsOf: target) == bytes)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.linkItem(at: target, to: file)
        #expect(throws: AgentErrorCode.permissionDenied) { try locator.endpoints() }
        try FileManager.default.removeItem(at: file)
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(throws: AgentErrorCode.permissionDenied) { try locator.endpoints() }
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o644)
        try FileManager.default.removeItem(at: file)
        #expect(mkfifo(file.path, 0o600) == 0)
        #expect(throws: AgentErrorCode.permissionDenied) { try locator.endpoints() }
    }

    @Test func aReplacedDirectoryDoesNotRedirectAPinnedReader() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let locator = try AgentHostLocator(parentDirectory: root, createIfMissing: true)
        try locator.publish(record())
        let directory = root.appendingPathComponent("Agents"), moved = root.appendingPathComponent("OldAgents")
        try FileManager.default.moveItem(at: directory, to: moved)
        let replacement = try AgentHostLocator(parentDirectory: root, createIfMissing: true)
        #expect(try replacement.endpoints().isEmpty)
        #expect(throws: AgentErrorCode.permissionDenied) { try locator.endpoints() }
    }

    @Test func catalogCapacityDoesNotEvictOtherLibrariesOrPreventAnOwnedReplacement() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let locator = try AgentHostLocator(parentDirectory: root, createIfMissing: true)
        var records: [AgentHostLocator.Endpoint] = []
        for index in 0..<64 { let entry = try record(String(index)); records.append(entry); try locator.publish(entry) }
        let file = root.appendingPathComponent("Agents/hosts.json"), bytes = try Data(contentsOf: file)
        #expect(throws: AgentErrorCode.busy) { try locator.publish(record("overflow")) }
        #expect(try Data(contentsOf: file) == bytes)
        let replacement = try AgentHostLocator.Endpoint(libraryID: records[0].libraryID, socketPath: "/tmp/da-replaced/s")
        try locator.publish(replacement)
        #expect(try locator.endpoints().count == 64 && locator.endpoints().contains(replacement))
    }
}
