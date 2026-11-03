import Foundation
import Testing
import Darwin
@testable import Draftly

@Suite("Codex process access limits") @MainActor
struct CodexProcessIsolationTests {
    private func run(_ executable: String, arguments: [String], home: URL) throws -> (Int32, Data) {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", try CodexProcessIsolation.profile(executable: URL(fileURLWithPath: executable), home: home),
                             executable] + arguments
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    @Test func contentAccessRejectsOutsideFilesSymlinksAndVolumeAliases() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let home = root.appendingPathComponent("owned")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inside = home.appendingPathComponent("inside"), outside = root.appendingPathComponent("outside")
        try Data("permitted".utf8).write(to: inside)
        try Data("outside".utf8).write(to: outside)
        let link = home.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let allowed = try run("/bin/cat", arguments: [inside.path], home: home)
        #expect(allowed.0 == 0 && allowed.1 == Data("permitted".utf8))
        var paths = [outside.path, link.path]
        let physical = try #require(realpath(outside.path, nil))
        defer { free(physical) }
        let alias = "/System/Volumes/Data" + String(cString: physical)
        if FileManager.default.fileExists(atPath: alias) { paths.append(alias) }
        for path in paths {
            let denied = try run("/bin/cat", arguments: [path], home: home)
            #expect(denied.0 != 0 && denied.1.isEmpty)
        }
        let child = try run("/usr/bin/env", arguments: ["/bin/cat", inside.path], home: home)
        #expect(child.0 != 0 && child.1.isEmpty)
        let writeInside = try run("/usr/bin/touch", arguments: [home.appendingPathComponent("created").path], home: home)
        #expect(writeInside.0 == 0)
        let writeOutside = try run("/usr/bin/touch", arguments: [outside.path], home: home)
        #expect(writeOutside.0 != 0)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DRAFTLY_CODEX_TEST_EXECUTABLE"] != nil))
    func realCodexCanReadItsEmptyAccountWithinTheProcessLimits() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["DRAFTLY_CODEX_TEST_EXECUTABLE"])
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let account = CodexAccountModel(home: home)
        account.executable = URL(fileURLWithPath: path)
        defer { account.disconnect() }
        await account.refresh()
        #expect(account.errorMessage == nil)
        #expect(!account.isSignedIn)
    }
}
