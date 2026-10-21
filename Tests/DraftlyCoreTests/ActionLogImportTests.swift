import Foundation
import Testing
@testable import DraftlyCore

@Suite("Imported action log policy") @MainActor
struct ActionLogImportTests {
    @Test(arguments: [0, 1, 2, 99], [false, true])
    func importedLevelControlsFinalHistoryWithoutChangingTheResult(level: Int, worker: Bool) async throws {
        for ending in ["", "context.fail('Neutral error');", "context.cancel();", "while (true) {}", "setTimeout(() => { while (true) {} }, 0);"] {
            let (library, editor, _, runner) = try makeAPIContext("Neutral source")
            if ending.contains("while") { runner.synchronousScriptTimeout = 0.02 }
            runner.scriptTimeout = 0.5
            let data = try JSONSerialization.data(withJSONObject: ["name": "Log policy",
                "logLevel": level, "steps": [["type": "script", "data": ["script": ending, "allowAsync": ending.hasPrefix("setTimeout") ? "true" : "false"]]]] as [String: Any])
            let imported = try #require(ActionImporter.decode(data).first)
            try library.saveAction(imported)
            let restored = try LibraryStore(inMemory: true, seed: false)
            try restored.restore(library.backupData())
            let action = try #require(restored.actions.first { $0.id == imported.id })
            #expect(action.presentation.logLevel == level)
            #expect(action.rawPayload == imported.rawPayload)
            let report = worker ? await runner.runAsync(action) : runner.runReport(action)
            let expected = level != 0 && (level != 1 || ending.contains("fail") || ending.contains("while"))
            #expect(library.runs.count == (expected ? 1 : 0))
            #expect(report.reason == (ending.isEmpty ? .success : ending.contains("cancel") ? .cancelled : ending.contains("while") ? .timeout : .error))
            #expect(editor.content == "Neutral source")
        }
    }
    @Test(arguments: [false, true])
    func oldActionsKeepCompleteHistory(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext("Neutral source")
        let action = try #require(ActionImporter.decode(Data(#"{"name":"Old action","steps":[]}"#.utf8)).first)
        #expect(action.presentation.logLevel == nil)
        let native = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(action)) as? [String: Any])
        let options = try #require(native["options"] as? [String: Any])
        #expect(options["logLevel"] == nil)
        let recovered = try #require(ActionImporter.decode(JSONSerialization.data(withJSONObject: native)).first)
        #expect(recovered.presentation.logLevel == nil)
        let report = worker ? await runner.runAsync(recovered) : runner.runReport(recovered)
        #expect(report.reason == .success && library.runs.count == 1)
    }

}
