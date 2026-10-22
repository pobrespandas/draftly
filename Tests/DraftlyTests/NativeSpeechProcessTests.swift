import Foundation
import Darwin
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Isolated speech processes") @MainActor
struct NativeSpeechProcessTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-SpeechTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func executable(_ source: String, root: URL) throws -> URL {
        let url = root.appendingPathComponent("helper")
        try ("#!/bin/sh\n" + source).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    @Test func helperModeIsRecognizedBeforeApplicationStartup() {
        #expect(NativeSpeechProcess.runHelperIfRequested(arguments: ["app"]) == nil)
        #expect(NativeSpeechProcess.runHelperIfRequested(arguments: ["app", NativeSpeechProcess.helperFlag]) == 64)
        #expect(NativeSpeechProcess.runHelperIfRequested(arguments: ["app", "wrong", NativeSpeechProcess.helperFlag, "output"]) == 64)
    }

    @Test(arguments: [true, false])
    func helperPreservesVoiceRateTextAndBooleanResult(success: Bool) throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input"), output = root.appendingPathComponent("output")
        let values: [String: Any] = ["text": "café 🐼\nquoted \"text\"", "voice": "exact.voice.identity", "rate": 130]
        try JSONSerialization.data(withJSONObject: values).write(to: input)
        let status = NativeSpeechProcess.runHelperIfRequested(arguments: ["app", NativeSpeechProcess.helperFlag, input.path, output.path]) { received in
            #expect(received["text"] as? String == values["text"] as? String)
            #expect(received["voice"] as? String == "exact.voice.identity")
            #expect(received["rate"] as? Int == 130)
            return success
        }
        #expect(status == 0)
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        #expect(envelope["success"] as? Bool == success)
    }

    @Test func helperFailureIsStructuredWithoutRunningTheApp() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input"), output = root.appendingPathComponent("output")
        try Data("{}".utf8).write(to: input)
        #expect(NativeSpeechProcess.runHelperIfRequested(arguments: ["app", NativeSpeechProcess.helperFlag, input.path, output.path]) { _ in
            throw DraftlyError.message("Neutral synthesis error")
        } == 0)
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        #expect(envelope["error"] as? String == "Neutral synthesis error")
    }

    @Test(arguments: [true, false])
    func processUsesPrivateFilesAndPreservesCompletion(success: Bool) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = try executable("""
            test "$1" = '--draftly-speech-helper' || exit 2
            /bin/cp "$2" "\(root.path)/captured.json"
            /usr/bin/stat -f '%Lp' "$2" > "\(root.path)/mode"
            printf '%s' '{"success":\(success)}' > "$3"
            """, root: root)
        let result = try await NativeSpeechRequest.run(
            ["text": "neutral 🐼\n--literal", "settings": ["voice": ["id": "voice.identity"], "rate": "fast"]],
            makeDriver: { SystemSpeechDriver(voice: $0, executable: helper, temporaryDirectory: root) },
            present: { _ in Issue.record("Default playback showed a notice."); return true })
        #expect(result == success)
        let values = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("captured.json"))) as? [String: Any])
        #expect(values["text"] as? String == "neutral 🐼\n--literal")
        #expect(values["voice"] as? String == "voice.identity" && values["rate"] as? Int == 240)
        #expect(try String(contentsOf: root.appendingPathComponent("mode"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "600")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix("Draftly-Speech-") })
    }

    @Test(arguments: ["printf '%s' '{\"error\":\"Neutral synthesis error\"}' > \"$3\"", "exit 7", "printf '%s' '{\"success\":1}' > \"$3\"", "printf '%s' 'invalid' > \"$3\""])
    func processErrorsNeverBecomeSuccess(source: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = try executable(source, root: root)
        do {
            _ = try await NativeSpeechProcess.run(text: "Neutral", voice: nil, rate: 180, executable: helper, temporaryDirectory: root)
            Issue.record("A failed helper returned success.")
        } catch {
            #expect(!(error is CancellationError))
            if source.contains("Neutral synthesis error") { #expect(error.localizedDescription == "Neutral synthesis error") }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix("Draftly-Speech-") })
    }

    @Test(arguments: [false, true])
    func interruptionReapsBlockedHelperBeforeRemovingInput(cancel: Bool) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = try executable("""
            trap '' TERM
            printf '%s' "$2" > "\(root.path)/input-path"
            printf '%s' "$$" > "\(root.path)/pid"
            /usr/bin/touch "\(root.path)/ready"
            exec /bin/sleep 30
            """, root: root)
        let task = Task {
            try await NativeSpeechRequest.run(
                ["text": "Neutral", "settings": ["autoClose": false]],
                makeDriver: { SystemSpeechDriver(voice: $0, executable: helper, timeout: cancel ? 10 : 1, temporaryDirectory: root) },
                present: { _ in Issue.record("Interrupted synthesis showed completion."); return true })
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("ready").path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(FileManager.default.fileExists(atPath: root.appendingPathComponent("ready").path))
        let pid = try #require(Int32(String(contentsOf: root.appendingPathComponent("pid"), encoding: .utf8)))
        defer { if getpgid(pid) == pid { _ = Darwin.kill(-pid, SIGKILL) } }
        let input = URL(fileURLWithPath: try String(contentsOf: root.appendingPathComponent("input-path"), encoding: .utf8))
        #expect(FileManager.default.fileExists(atPath: input.path))
        if cancel { task.cancel() }
        do { _ = try await task.value; Issue.record("Interrupted synthesis returned a result.") }
        catch {
            if cancel { #expect(error is CancellationError) }
            else { #expect(error as? ActionExecutionInterruption == .timeout) }
        }
        #expect(getpgid(pid) == -1)
        #expect(!FileManager.default.fileExists(atPath: input.deletingLastPathComponent().path))
    }
}
