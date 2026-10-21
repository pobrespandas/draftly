import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Isolated AppleScript processes") @MainActor
struct NativeAppleScriptProcessTests {
    private func folder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-AppleScriptTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private func executable(_ source: String, in directory: URL) throws -> URL {
        let script = directory.appendingPathComponent("helper")
        try ("#!/bin/sh\n" + source).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }
    private func helperResult(_ values: [String: Any]) throws -> [String: Any] {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.json"), output = directory.appendingPathComponent("output.json")
        try JSONSerialization.data(withJSONObject: values).write(to: input)
        #expect(NativeAppleScriptProcess.runHelperIfRequested(arguments: ["test", NativeAppleScriptProcess.helperFlag, input.path, output.path]) == 0)
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
    }

    @Test func dateDescriptorsRemainDatesAtRootAndInNestedValues() throws {
        let before = Date()
        let root = try NativeAutomationAdapter().executeAppleScript(["source": "return current date"])
        let stamp = try #require(root as? Date)
        #expect(stamp >= before.addingTimeInterval(-1) && stamp <= Date().addingTimeInterval(1))
        let nested = try NativeAutomationAdapter().executeAppleScript([
            "source": "set stamp to current date\nreturn {stamp, {nested:stamp, text:\"2020-01-02T03:04:05Z\"}}"
        ])
        let list = try #require(nested as? [Any])
        let record = try #require(list[1] as? [String: Any])
        #expect(list[0] is Date && record["nested"] is Date)
        #expect(record["text"] as? String == "2020-01-02T03:04:05Z")
    }

    @Test func helperJSONPreservesNativeDatesWithoutConvertingDateLikeText() throws {
        let envelope = try helperResult(["source": "set stamp to current date\nreturn {stamp, {nested:stamp, text:\"2020-01-02T03:04:05Z\"}}"])
        #expect(envelope["appleScriptDatePaths"] as? [String] == ["/0", "/1/nested"])
        let values = try #require(AppleScriptValueTransport.decode(envelope) as? [Any])
        let first = try #require(values[0] as? Date)
        let record = try #require(values[1] as? [String: Any])
        #expect(record["nested"] as? Date == first)
        #expect(record["text"] as? String == "2020-01-02T03:04:05Z")
        let root = try AppleScriptValueTransport.decode(helperResult(["source": "return current date"]))
        #expect(root is Date)
    }

    @Test func neutralSubroutineArgumentsAndDescriptorValuesMatchLegacy() throws {
        let argument: [String: Any] = ["text": "café 🐼\nquoted \"text\"", "values": [true, 3.5, NSNull(), []] as [Any], "nested": ["number": 7]]
        let values: [String: Any] = ["source": "on execute(payload)\nreturn payload\nend execute", "subroutine": "execute", "arguments": [argument]]
        let legacy = try NativeAutomationAdapter().executeAppleScript(values)
        let isolated = try #require(helperResult(values)["value"])
        let expected = try JSONSerialization.data(withJSONObject: ["value": legacy], options: [.sortedKeys])
        let actual = try JSONSerialization.data(withJSONObject: ["value": isolated], options: [.sortedKeys])
        #expect(expected == actual)
        let record = try #require(isolated as? [String: Any])
        #expect(record["text"] as? String == argument["text"] as? String)
        let items = try #require(record["values"] as? [Any])
        #expect(items.count == 4)
        #expect(items[0] as? Bool == true)
        #expect(items[1] as? Double == 3.5)
        #expect(items[2] is NSNull)
        #expect((items[3] as? [Any])?.isEmpty == true)
        #expect((record["nested"] as? [String: Any])?["number"] as? Double == 7)
    }

    @Test func builtInRecordTextAndNestedValuesAreNotDropped() throws {
        let envelope = try helperResult(["source": "return {text:\"AppleScript café 🐼\", values:{true,3.5,missing value,{}}}"])
        let record = try #require(envelope["value"] as? [String: Any])
        #expect(record["text"] as? String == "AppleScript café 🐼")
        let values = try #require(record["values"] as? [Any])
        #expect(values.count == 4)
        #expect(values[0] as? Bool == true)
        #expect(values[1] as? Double == 3.5)
        #expect(values[2] is NSNull)
        #expect((values[3] as? [Any])?.isEmpty == true)
    }

    @Test func commonPropertiesHaveNamesAndUnknownKeywordsKeepTheirCodes() throws {
        let envelope = try helperResult(["source": "return {name:\"Neutral\", contents:\"Body\", id:7, «class zzzz»:\"Unknown\"}"])
        let record = try #require(envelope["value"] as? [String: Any])
        #expect(record["name"] as? String == "Neutral")
        #expect(record["contents"] as? String == "Body")
        #expect(record["id"] as? Double == 7)
        #expect(record["zzzz"] as? String == "Unknown")
    }

    @Test func collidingDecodedRecordKeysFailExplicitly() throws {
        let envelope = try helperResult(["source": "return {text:\"Built-in\", «class text»:\"Raw code\"}"])
        #expect(envelope["error"] as? String == "The AppleScript record has a duplicate field: text")
        #expect(envelope["value"] == nil)
    }

    @Test func missingValueResultsAndNullArgumentsRemainJSONNull() throws {
        #expect(try helperResult(["source": "return missing value"])["value"] is NSNull)
        let envelope = try helperResult(["source": "on execute(payload)\nreturn payload\nend execute", "subroutine": "execute", "arguments": [NSNull()]])
        #expect(envelope["value"] is NSNull)
    }

    @Test func ordinaryReturnAndEmptyListsKeepTheirTypes() throws {
        let envelope = try helperResult(["source": "return {true, 12, 3.5, \"café 🐼\", {}}"])
        let values = try #require(envelope["value"] as? [Any])
        #expect(values.count == 5)
        #expect(values[0] as? Bool == true)
        #expect(values[1] as? Double == 12)
        #expect(values[2] as? Double == 3.5)
        #expect(values[3] as? String == "café 🐼")
        #expect((values[4] as? [Any])?.isEmpty == true)
    }

    @Test func scriptErrorsHaveTheSameMessageAsLegacy() throws {
        let values = ["source": "error \"Neutral failure\" number 7"]
        let isolated = try helperResult(values)
        do { _ = try NativeAutomationAdapter().executeAppleScript(values); Issue.record("Failing AppleScript succeeded.") }
        catch { #expect(isolated["error"] as? String == error.localizedDescription) }
        #expect(isolated["value"] == nil)
    }

    @Test func malformedHelperInvocationNeverFallsThroughToApplicationStartup() {
        #expect(NativeAppleScriptProcess.runHelperIfRequested(arguments: ["app"]) == nil)
        #expect(NativeAppleScriptProcess.runHelperIfRequested(arguments: ["app", NativeAppleScriptProcess.helperFlag]) == 64)
        #expect(NativeAppleScriptProcess.runHelperIfRequested(arguments: ["app", "wrong", NativeAppleScriptProcess.helperFlag, "output"]) == 64)
    }

    @Test func processArgumentsAndStructuredResultsUseFiles() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let script = try executable("test \"$1\" = '--draftly-applescript-helper' || exit 2\ntest -r \"$2\" || exit 3\nprintf '%s' '{\"value\":{\"text\":\"neutral\",\"number\":7}}' > \"$3\"", in: directory)
        let value = try await NativeAppleScriptProcess.run(["source": "return 7"], executable: script)
        let result = try #require(value as? [String: Any])
        #expect(result["text"] as? String == "neutral" && result["number"] as? Int == 7)
    }

    @Test func structuredErrorsAndProcessFailuresRemainErrors() async throws {
        for source in ["printf '%s' '{\"error\":\"Neutral script error\"}' > \"$3\"", "printf '%s' 'Neutral process error' >&2; exit 9"] {
            let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
            let script = try executable(source, in: directory)
            do { _ = try await NativeAppleScriptProcess.run([:], executable: script); Issue.record("Failed helper succeeded.") }
            catch { #expect(error.localizedDescription.hasPrefix("Neutral")) }
        }
    }

    @Test func timeoutTerminatesTheHelperProcess() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let script = try executable("sleep 20", in: directory)
        do { _ = try await NativeAppleScriptProcess.run([:], executable: script, timeout: 0.02); Issue.record("Timed out helper succeeded.") }
        catch { #expect(error as? ActionExecutionInterruption == .timeout) }
    }

    @Test func cancellationTerminatesTheHelperProcess() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let ready = directory.appendingPathComponent("ready")
        let escaped = "'" + ready.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = try executable("touch " + escaped + "\nsleep 20", in: directory)
        let task = Task { @MainActor in
            do { _ = try await NativeAppleScriptProcess.run([:], executable: script); return false }
            catch { return error is CancellationError }
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: ready.path), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(FileManager.default.fileExists(atPath: ready.path))
        task.cancel()
        #expect(await task.value)
    }
}
