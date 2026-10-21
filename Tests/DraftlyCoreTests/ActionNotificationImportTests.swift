import Foundation
import Testing
@testable import DraftlyCore

@Suite("Imported action notification policy") @MainActor
struct ActionNotificationImportTests {
    @Test(arguments: [0, 1, 2, 99], [false, true])
    func importedPolicyAppliesOnlyToItsFinalOutcome(mode: Int, worker: Bool) async throws {
        for ending in ["", "context.fail('Neutral error');", "context.cancel();", "while (true) {}", "setTimeout(() => { while (true) {} }, 0);"] {
            let (_, _, host, runner) = try makeAPIContext("Neutral source")
            if ending.contains("while") { runner.synchronousScriptTimeout = 0.02 }
            runner.scriptTimeout = 0.5
            let data = try JSONSerialization.data(withJSONObject: ["name": "Notification policy",
                "notificationType": mode, "steps": [["type": "script", "data": ["script": ending, "allowAsync": ending.hasPrefix("setTimeout") ? "true" : "false"]]]] as [String: Any])
            let imported = try #require(ActionImporter.decode(data).first)
            let action = try #require(ActionImporter.decode(JSONEncoder().encode(imported)).first)
            #expect(action.presentation.notifyOnSuccess == (mode == 2))
            #expect(action.presentation.notifyOnError == (mode == 1 || mode == 2))
            #expect(action.rawPayload == imported.rawPayload)
            let report = worker ? await runner.runAsync(action) : runner.runReport(action)
            #expect(report.reason == (ending.isEmpty ? .success : ending.contains("cancel") ? .cancelled : ending.contains("while") ? .timeout : .error))
            let expected = !ending.contains("cancel") && (ending.isEmpty ? mode == 2 : mode == 1 || mode == 2)
            #expect(host.calls.filter { $0.0 == "actionNotification" }.count == (expected ? 1 : 0))
        }
    }

    @Test func originalActionsImportTheirNotificationChoices() throws {
        for (id, success, error) in [("1VL", false, true), ("1Ga", false, false),
                                      ("1Bg", false, true), ("1qn", true, true), ("1DM", true, true)] {
            let url = try #require(Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Fixtures"))
            let action = try #require(ActionImporter.decode(Data(contentsOf: url)).first)
            #expect(action.presentation.notifyOnSuccess == success, Comment(rawValue: id))
            #expect(action.presentation.notifyOnError == error, Comment(rawValue: id))
        }
        let old = try #require(ActionImporter.decode(Data(#"{"name":"Old action","steps":[]}"#.utf8)).first)
        #expect(!old.presentation.notifyOnSuccess && !old.presentation.notifyOnError)
    }
}
