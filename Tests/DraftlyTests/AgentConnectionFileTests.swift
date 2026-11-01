import Foundation
import Darwin
import Testing
import AgentContracts
@testable import Draftly

@Suite("Private agent connection metadata files") @MainActor
struct AgentConnectionFileTests {
    private func parent() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Agent-File-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        return url
    }
    private func permissions(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber).intValue
    }

    @Test func privateRoundTripAtomicReplacementAndStaleWrite() throws {
        let parent = try parent(); defer { try? FileManager.default.removeItem(at: parent) }
        let file = try AgentConnectionFile(parentDirectory: parent)
        #expect(try file.read() == nil)
        let first = Data("neutral one".utf8), second = Data("neutral two".utf8)
        try file.replace(first, expected: nil)
        #expect(try file.read() == first)
        #expect(try permissions(parent.appendingPathComponent("Agents")) == 0o700)
        #expect(try permissions(parent.appendingPathComponent("Agents/connections.json")) == 0o600)
        try file.replace(second, expected: first)
        #expect(throws: AgentErrorCode.versionConflict) { try file.replace(first, expected: first) }
        #expect(try file.read() == second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.appendingPathComponent("Agents").path).sorted()
            == ["connections.json", "connections.lock"])
    }

    @Test func directoryAndFileSymlinksNeverFollowTheirTargets() throws {
        let parent = try parent(); defer { try? FileManager.default.removeItem(at: parent) }
        let other = parent.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let agents = parent.appendingPathComponent("Agents")
        try FileManager.default.createSymbolicLink(at: agents, withDestinationURL: other)
        #expect(throws: AgentErrorCode.permissionDenied) { try AgentConnectionFile(parentDirectory: parent) }
        try FileManager.default.removeItem(at: agents)
        let file = try AgentConnectionFile(parentDirectory: parent)
        let target = other.appendingPathComponent("target")
        let data = Data("untouched".utf8); try data.write(to: target)
        try FileManager.default.createSymbolicLink(at: agents.appendingPathComponent("connections.json"), withDestinationURL: target)
        #expect(throws: AgentErrorCode.permissionDenied) { try file.read() }
        #expect(throws: AgentErrorCode.permissionDenied) { try file.replace(Data(), expected: nil) }
        #expect(try Data(contentsOf: target) == data)
    }

    @Test func hardLinksUnsafeModesAndFIFOsAreRejected() throws {
        let parent = try parent(); defer { try? FileManager.default.removeItem(at: parent) }
        let file = try AgentConnectionFile(parentDirectory: parent)
        let target = parent.appendingPathComponent("Agents/connections.json")
        try file.replace(Data("neutral".utf8), expected: nil)
        try FileManager.default.linkItem(at: target, to: parent.appendingPathComponent("hardlink"))
        #expect(throws: AgentErrorCode.permissionDenied) { try file.read() }
        try FileManager.default.removeItem(at: parent.appendingPathComponent("hardlink"))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        #expect(throws: AgentErrorCode.permissionDenied) { try file.read() }
        try FileManager.default.removeItem(at: target)
        #expect(mkfifo(target.path, mode_t(0o600)) == 0)
        #expect(throws: AgentErrorCode.permissionDenied) { try file.read() }
    }

    @Test func metadataLockContentionDoesNotClobberTheFile() throws {
        let parent = try parent(); defer { try? FileManager.default.removeItem(at: parent) }
        let file = try AgentConnectionFile(parentDirectory: parent)
        #expect(try file.read() == nil)
        let descriptor = Darwin.open(parent.appendingPathComponent("Agents/connections.lock").path, O_RDWR | O_CLOEXEC)
        #expect(descriptor >= 0)
        defer { Darwin.close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        #expect(throws: AgentErrorCode.busy) { try file.replace(Data(), expected: nil) }
        #expect(flock(descriptor, LOCK_UN) == 0)
        #expect(try file.read() == nil)
    }

    @Test func extendedAllowACLIsRejectedEvenWithPrivateModeBits() throws {
        let parent = try parent(); defer { try? FileManager.default.removeItem(at: parent) }
        let file = try AgentConnectionFile(parentDirectory: parent)
        let data = Data("neutral".utf8)
        try file.replace(data, expected: nil)
        let target = parent.appendingPathComponent("Agents/connections.json")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "everyone allow read", target.path]
        process.standardOutput = Pipe(); process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(throws: AgentErrorCode.permissionDenied) { try file.read() }
        #expect(try Data(contentsOf: target) == data)
    }
    @Test func unsafeParentPermissionsAreNotRepairedOrAdopted() throws {
        let parent = try parent(); defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: parent.path)
        #expect(throws: AgentErrorCode.permissionDenied) { try AgentConnectionFile(parentDirectory: parent) }
        #expect(try permissions(parent) == 0o777)
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("Agents").path))
    }

    @Test func aDenyOnlyACLDoesNotMakePrivateMetadataUnavailable() throws {
        let parent = try parent(); defer { try? FileManager.default.removeItem(at: parent) }
        let file = try AgentConnectionFile(parentDirectory: parent)
        let data = Data("neutral".utf8)
        try file.replace(data, expected: nil)
        let target = parent.appendingPathComponent("Agents/connections.json")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "everyone deny delete", target.path]
        defer {
            let cleanup = Process(); cleanup.executableURL = URL(fileURLWithPath: "/bin/chmod")
            cleanup.arguments = ["-N", target.path]
            cleanup.standardOutput = Pipe(); cleanup.standardError = Pipe()
            do { try cleanup.run(); cleanup.waitUntilExit() }
            catch { Issue.record("The fixture ACL could not be removed.") }
        }
        process.standardOutput = Pipe(); process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try file.read() == data)
    }

}
