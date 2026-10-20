import Foundation
import Testing
import DraftlyCore
import Darwin
@testable import Draftly

@Suite("Asynchronous native processes")
@MainActor
struct NativeProcessExecutorTests {
    @Test func shellPreservesLiteralArgumentsStatusAndBothStreams() async throws {
        let result = try await NativeAutomationAdapter().executeShellAsync([
            "source": "printf '%s' \"$1\"; printf 'error 🐼' >&2; exit 7",
            "arguments": ["$(not-a-command) café 🐼"]
        ])
        #expect(result["status"] as? Int == 7)
        #expect(result["stdout"] as? String == "$(not-a-command) café 🐼")
        #expect(result["stderr"] as? String == "error 🐼")
    }

    @Test func largeOutputDoesNotFillAPipeAndBlockTermination() async throws {
        let result = try await NativeAutomationAdapter().executeShellAsync([
            "source": "i=0; while [ $i -lt 20000 ]; do printf 'stdout-line\\n'; printf 'stderr-line\\n' >&2; i=$((i+1)); done"
        ], timeout: 10)
        #expect(result["status"] as? Int == 0)
        #expect((result["stdout"] as? String)?.utf8.count == 240000)
        #expect((result["stderr"] as? String)?.utf8.count == 240000)
    }

    @Test func cancellationStopsAChildAndDoesNotBlockTheMainActor() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        let task = Task { try await NativeProcessExecutor.run(process, timeout: 60) }
        try await Task.sleep(for: .milliseconds(40))
        #expect(process.isRunning)
        task.cancel()
        do { _ = try await task.value; Issue.record("The cancelled process returned success.") }
        catch { #expect(error is CancellationError) }
        #expect(!process.isRunning)
    }

    @Test func timeoutStopsAChildAndReportsItsReason() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        do {
            _ = try await NativeProcessExecutor.run(process, timeout: 0.05)
            Issue.record("The timed out process returned success.")
        } catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(!process.isRunning)
    }

    @Test func timeoutEscalatesWhenTheScriptIgnoresTermination() async throws {
        do {
            _ = try await NativeAutomationAdapter().executeShellAsync([
                "source": "trap '' TERM; while :; do :; done"
            ], timeout: 0.05)
            Issue.record("The script ignored the timeout.")
        } catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
    }

    @Test func timeoutTerminatesDescendantsInTheIsolatedProcessGroup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let childFile = root.appendingPathComponent("child")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "/bin/sh -c 'trap \"\" TERM; exec /bin/sleep 30' & child=$!; printf '%s' \"$child\" > \"$1\"; wait", "fixture", childFile.path]
        do {
            _ = try await NativeProcessExecutor.run(process, timeout: 0.15)
            Issue.record("The descendant fixture exceeded its timeout without cancellation.")
        } catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        let childText = try String(contentsOf: childFile, encoding: .utf8)
        let child = try #require(Int32(childText))
        defer {
            if getpgid(child) == process.processIdentifier { _ = Darwin.kill(child, SIGKILL) }
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(getpgid(child) == -1)
        #expect(!process.isRunning)
    }

    @Test func launchFailureAndInvalidTimeoutReturnErrors() async {
        let missing = Process()
        missing.executableURL = URL(fileURLWithPath: "/draftly-missing-executable")
        do { _ = try await NativeProcessExecutor.run(missing, timeout: 1); Issue.record("The missing process started.") }
        catch { #expect(!(error is CancellationError)) }
        let invalid = Process()
        do { _ = try await NativeProcessExecutor.run(invalid, timeout: .nan); Issue.record("The invalid timeout was accepted.") }
        catch { #expect(error.localizedDescription == "The process timeout must be positive and finite.") }
    }

    @Test func shortcutUsesFilesAndLiteralNameWithAnInjectedFixture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("shortcut-fixture")
        try "#!/bin/sh\n[ \"$1\" = run ] || exit 2\n/bin/cat \"$4\" > \"$6\"\nprintf '%s' \"$2\" >> \"$6\"\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let result = try await NativeAutomationAdapter().runShortcutAsync(name: "neutral $(literal)", input: "café 🐼\n", executable: executable)
        #expect(result == "café 🐼\nneutral $(literal)")
    }
}

@Suite("Shortcut launch without waiting") @MainActor
struct ShortcutLaunchTests {
    @Test func noWaitReturnsNoOutputAndKeepsInputUntilExit() async throws {
        let fixture = try ShortcutLaunchFixture(); defer { fixture.clean() }
        let result = try await NativeAutomationAdapter().runShortcutAsync(name: "Neutral", input: "café 🐼", waitForResponse: false, executable: fixture.executable, timeout: 5)
        #expect(result == nil)
        try await fixture.waitFor("started")
        let input = try fixture.inputPath()
        #expect(FileManager.default.fileExists(atPath: input.path))
        #expect(!fixture.exists("finished"))
        try fixture.release()
        try await fixture.waitFor("finished")
        try await fixture.waitForRemoval(input.deletingLastPathComponent())
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("result"), encoding: .utf8) == "café 🐼")
    }

    @Test func launchedShortcutSurvivesCancellationOfItsCallingAction() async throws {
        let fixture = try ShortcutLaunchFixture(); defer { fixture.clean() }
        var launchReturned = false
        let action = Task {
            let result = try await NativeAutomationAdapter().runShortcutAsync(name: "Neutral", input: "Retained input", waitForResponse: false, executable: fixture.executable, timeout: 5)
            launchReturned = result == nil
            try await Task.sleep(for: .seconds(60))
        }
        try await fixture.waitFor("started")
        #expect(launchReturned)
        let input = try fixture.inputPath()
        action.cancel()
        do { try await action.value; Issue.record("The calling task must be cancelled.") }
        catch { #expect(error is CancellationError) }
        #expect(FileManager.default.fileExists(atPath: input.path))
        try fixture.release()
        try await fixture.waitFor("finished")
        try await fixture.waitForRemoval(input.deletingLastPathComponent())
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("result"), encoding: .utf8) == "Retained input")
    }

    @Test func defaultWaitStillReturnsTheRealOutputAfterExit() async throws {
        let fixture = try ShortcutLaunchFixture(); defer { fixture.clean() }
        var finished = false
        let action = Task {
            let result = try await NativeAutomationAdapter().runShortcutAsync(name: "Neutral", input: "Actual result", executable: fixture.executable, timeout: 5)
            finished = true
            return result
        }
        try await fixture.waitFor("started")
        #expect(!finished)
        let input = try fixture.inputPath()
        try fixture.release()
        #expect(try await action.value == "Actual result")
        #expect(!FileManager.default.fileExists(atPath: input.deletingLastPathComponent().path))
    }

    @Test func legacyNoWaitAlsoTransfersInputOwnershipUntilExit() async throws {
        let fixture = try ShortcutLaunchFixture(); defer { fixture.clean() }
        let result = try NativeAutomationAdapter().runShortcut(name: "Neutral", input: "Legacy input", waitForResponse: false, executable: fixture.executable, timeout: 5)
        #expect(result == nil)
        try await fixture.waitFor("started")
        let input = try fixture.inputPath()
        #expect(FileManager.default.fileExists(atPath: input.path))
        try fixture.release()
        try await fixture.waitFor("finished")
        try await fixture.waitForRemoval(input.deletingLastPathComponent())
    }

    @Test func detachedShortcutTimeoutTerminatesTheProcessAndCleansInput() async throws {
        let fixture = try ShortcutLaunchFixture(); defer { fixture.clean() }
        _ = try await NativeAutomationAdapter().runShortcutAsync(name: "Neutral", input: "Timed input", waitForResponse: false, executable: fixture.executable, timeout: 1)
        try await fixture.waitFor("started")
        let input = try fixture.inputPath()
        try await fixture.waitForRemoval(input.deletingLastPathComponent())
        let pid = try fixture.pid()
        #expect(getpgid(pid) == -1)
        #expect(!fixture.exists("finished"))
    }

    @Test func detachedSpawnFailureIsExplicitAndCleansExactlyOnce() async throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/draftly-missing-shortcut-executable")
        var cleanups = 0
        #expect(throws: (any Error).self) {
            try NativeProcessExecutor.launchDetached(process, timeout: 1) { cleanups += 1 }
        }
        #expect(cleanups == 1 && !process.isRunning)
        do {
            _ = try await NativeAutomationAdapter().runShortcutAsync(name: "Neutral", input: "Input", waitForResponse: false, executable: try #require(process.executableURL))
            Issue.record("A missing Shortcut executable must not report launch success.")
        } catch { #expect(!(error is CancellationError)) }
    }
}

@MainActor private struct ShortcutLaunchFixture {
    let root: URL
    let executable: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        executable = root.appendingPathComponent("shortcut-fixture")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        #!/bin/sh
        root=$(/usr/bin/dirname "$0")
        printf '%s' "$4" > "$root/input-path"
        printf '%s' "$$" > "$root/pid"
        touch "$root/started"
        while [ ! -f "$root/release" ]; do /bin/sleep 0.01; done
        /bin/cat "$4" > "$root/result"
        /bin/cat "$4" > "$6"
        touch "$root/finished"
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) }
    func inputPath() throws -> URL { URL(fileURLWithPath: try String(contentsOf: root.appendingPathComponent("input-path"), encoding: .utf8)) }
    func pid() throws -> Int32 { try #require(Int32(String(contentsOf: root.appendingPathComponent("pid"), encoding: .utf8))) }
    func release() throws { try Data().write(to: root.appendingPathComponent("release")) }
    func waitFor(_ name: String) async throws { try await wait { exists(name) } }
    func waitForRemoval(_ url: URL) async throws { try await wait { !FileManager.default.fileExists(atPath: url.path) } }
    private func wait(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !ready(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(ready(), "The neutral Shortcut process did not reach its expected state.")
    }
    func clean() {
        if let pid = try? pid(), getpgid(pid) == pid, pid != getpgrp() { _ = Darwin.kill(-pid, SIGKILL) }
        try? FileManager.default.removeItem(at: root)
    }
}
