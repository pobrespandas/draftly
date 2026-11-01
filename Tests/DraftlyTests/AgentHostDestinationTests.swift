import Foundation
import Testing
import AgentContracts
import AgentLocalSecurity
import AgentLocalTransport

@Suite("Library-specific agent host resolution") @MainActor
struct AgentHostDestinationTests {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Destination-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return root
    }

    @Test func libraryResolutionUsesOnlyTheRequestedIdentityAndLatestPublication() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let locator = try AgentHostLocator(parentDirectory: root, createIfMissing: true)
        let first = try AgentHostLocator.Endpoint(libraryID: UUID(), socketPath: "/tmp/da-first/s")
        let other = try AgentHostLocator.Endpoint(libraryID: UUID(), socketPath: "/tmp/da-other/s")
        try locator.publish(first); try locator.publish(other)
        let destination = AgentHostDestination.library(first.libraryID, stateParent: root.path)
        #expect(try destination.resolve().socketPath == first.socketPath)
        #expect(try destination.resolve().expectedLibraryID == first.libraryID)
        let next = try AgentHostLocator.Endpoint(libraryID: first.libraryID, socketPath: "/tmp/da-next/s")
        try locator.publish(next)
        #expect(try destination.resolve().socketPath == next.socketPath)
        try locator.withdraw(next)
        #expect(throws: AgentErrorCode.unavailable) { try destination.resolve() }
        #expect(try locator.endpoints() == [other])
    }

    @Test func missingStateReturnsUnavailableWithoutCreatingDirectoriesOrFallingBack() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        for parent in [root, root.appendingPathComponent("missing")] {
            #expect(throws: AgentErrorCode.unavailable) {
                try AgentHostDestination.library(UUID(), stateParent: parent.path).resolve()
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func corruptCatalogIsNotRepairedOrReplacedByADifferentHost() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let locator = try AgentHostLocator(parentDirectory: root, createIfMissing: true)
        let entry = try AgentHostLocator.Endpoint(libraryID: UUID(), socketPath: "/tmp/da-neutral/s")
        try locator.publish(entry)
        let file = root.appendingPathComponent("Agents/hosts.json"), invalid = Data("invalid".utf8)
        try invalid.write(to: file)
        #expect(throws: AgentErrorCode.storageError) {
            try AgentHostDestination.library(entry.libraryID, stateParent: root.path).resolve()
        }
        #expect(try Data(contentsOf: file) == invalid)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(throws: AgentErrorCode.permissionDenied) {
            try AgentHostDestination.library(entry.libraryID, stateParent: root.path).resolve()
        }
        #expect(try Data(contentsOf: file) == invalid)
    }

    @Test func explicitSocketRemainsUnboundAndProgrammaticDestinationsAreValidated() throws {
        let resolved = try AgentHostDestination.socket("/tmp/not-created-neutral/s").resolve()
        #expect(resolved.socketPath == "/tmp/not-created-neutral/s" && resolved.expectedLibraryID == nil)
        #expect(throws: AgentErrorCode.invalidInput) { try AgentHostDestination.socket("relative").resolve() }
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentHostDestination.library(UUID(), stateParent: "relative").resolve()
        }
    }
}
