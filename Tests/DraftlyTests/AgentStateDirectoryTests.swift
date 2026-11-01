import Foundation
import Darwin
import Testing
import AgentContracts
import AgentLocalSecurity

@Suite("Private local agent state directory") @MainActor
struct AgentStateDirectoryTests {
    private func parent() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Agent-State-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }

    @Test func independentMetadataFilesKeepCASAndBudgetsSeparate() throws {
        let root = try parent(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AgentStateDirectory(parentDirectory: root), a = Data("one".utf8), b = Data("two".utf8)
        try directory.replace("a.json", lockName: "a.lock", data: a, expected: nil, maximumBytes: 8)
        try directory.replace("b.json", lockName: "b.lock", data: b, expected: nil, maximumBytes: 8)
        #expect(try directory.read("a.json", lockName: "a.lock", maximumBytes: 8) == a)
        #expect(try directory.read("b.json", lockName: "b.lock", maximumBytes: 8) == b)
        #expect(throws: AgentErrorCode.versionConflict) {
            try directory.replace("a.json", lockName: "a.lock", data: b, expected: nil, maximumBytes: 8)
        }
        #expect(throws: AgentErrorCode.invalidInput) {
            try directory.replace("a.json", lockName: "a.lock", data: Data(repeating: 0, count: 9), expected: a, maximumBytes: 8)
        }
        #expect(throws: AgentErrorCode.storageError) { try directory.read("a.json", lockName: "a.lock", maximumBytes: 2) }
        #expect(try Data(contentsOf: root.appendingPathComponent("Agents/a.json")) == a)
    }

    @Test func lockLifetimeExcludesOtherOwnersAndDoesNotDeleteItsInode() throws {
        let root = try parent(); defer { try? FileManager.default.removeItem(at: root) }
        var directory: AgentStateDirectory? = try AgentStateDirectory(parentDirectory: root)
        let lease = try #require(directory).acquireLock("owner.lock")
        directory = nil
        try lease.validate()
        let other = try AgentStateDirectory(parentDirectory: root)
        #expect(throws: AgentErrorCode.busy) { try other.acquireLock("owner.lock") }
        lease.release(); lease.release()
        #expect(throws: AgentErrorCode.cancelled) { try lease.validate() }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Agents/owner.lock").path))
        let next = try other.acquireLock("owner.lock")
        try next.validate(); next.release()
    }

    @Test func lockIsExclusiveAcrossAnActualChildProcess() throws {
        let root = try parent(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AgentStateDirectory(parentDirectory: root), lease = try directory.acquireLock("owner.lock")
        defer { lease.release() }
        func attempt() throws -> Int32 {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-c", """
            import fcntl, sys
            with open(sys.argv[1], 'r+b') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    sys.exit(73)
            """, root.appendingPathComponent("Agents/owner.lock").path]
            process.standardOutput = Pipe(); process.standardError = Pipe()
            try process.run(); process.waitUntilExit()
            return process.terminationStatus
        }
        #expect(try attempt() == 73)
        lease.release()
        #expect(try attempt() == 0)
    }

    @Test func replacedLockAndDirectoryAreNotAcceptedAsTheHeldOwner() throws {
        let root = try parent(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AgentStateDirectory(parentDirectory: root), lease = try directory.acquireLock("owner.lock")
        defer { lease.release() }
        let path = root.appendingPathComponent("Agents/owner.lock")
        try FileManager.default.removeItem(at: path)
        try Data().write(to: path); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        #expect(throws: AgentErrorCode.permissionDenied) { try lease.validate() }
        let directoryLease = try directory.acquireLock("other.lock")
        defer { directoryLease.release() }
        try FileManager.default.moveItem(at: root.appendingPathComponent("Agents"), to: root.appendingPathComponent("Old"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Agents"), withIntermediateDirectories: false,
                                              attributes: [.posixPermissions: 0o700])
        #expect(throws: AgentErrorCode.permissionDenied) { try directory.validateCurrentLocation() }
        #expect(throws: AgentErrorCode.permissionDenied) { try directoryLease.validate() }
    }

    @Test func lockAliasesAndUnsafeModesAreRejectedWithoutRepair() throws {
        for kind in ["symlink", "hardlink", "mode", "fifo"] {
            let root = try parent(); defer { try? FileManager.default.removeItem(at: root) }
            let directory = try AgentStateDirectory(parentDirectory: root)
            let target = root.appendingPathComponent("untouched"), lock = root.appendingPathComponent("Agents/owner.lock")
            let bytes = Data("neutral".utf8); try bytes.write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            switch kind {
            case "symlink": try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: target)
            case "hardlink": try FileManager.default.linkItem(at: target, to: lock)
            case "mode":
                try bytes.write(to: lock)
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lock.path)
            default: #expect(mkfifo(lock.path, mode_t(0o600)) == 0)
            }
            #expect(throws: AgentErrorCode.permissionDenied) { try directory.acquireLock("owner.lock") }
            #expect(try Data(contentsOf: target) == bytes)
        }
    }

    @Test func invalidNamesAndBudgetsDoNotCreateOtherPaths() throws {
        let root = try parent(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AgentStateDirectory(parentDirectory: root)
        for name in ["", ".", "..", "../escape", "a/b", "a\0b", String(repeating: "a", count: 201)] {
            #expect(throws: AgentErrorCode.invalidInput) { try directory.acquireLock(name) }
            #expect(throws: AgentErrorCode.invalidInput) { try directory.read(name, lockName: "valid.lock", maximumBytes: 8) }
        }
        #expect(throws: AgentErrorCode.invalidInput) { try directory.read("same", lockName: "same", maximumBytes: 8) }
        #expect(throws: AgentErrorCode.invalidInput) { try directory.read("a", lockName: "b", maximumBytes: 0) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Agents").path).isEmpty)
    }
}
