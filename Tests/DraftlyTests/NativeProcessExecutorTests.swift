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
