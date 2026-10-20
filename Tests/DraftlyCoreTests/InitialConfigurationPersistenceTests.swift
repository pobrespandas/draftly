import Foundation
import Testing
@testable import DraftlyCore

@Suite("Initial configuration persistence") @MainActor
struct InitialConfigurationPersistenceTests {
    @Test(arguments: ["export", "backup"])
    func restoredConfirmationRetainsFalseAndZeroAndPromptsOnlyNewRequiredKey(transport: String) async throws {
        let host = ConfigurationPersistenceHost()
        let source = try ScriptTestFixture(content: "Source", host: host)
        let bool = ActionStep("configurationKey", ["key": "enabled", "name": "Enabled", "dataType": "boolean", "defaultBoolValue": "true", "requiresInitialConfiguration": "true"])
        let number = ActionStep("configurationKey", ["key": "count", "name": "Count", "dataType": "number", "defaultNumberValue": "7", "requiresInitialConfiguration": "true"])
        var original = DraftAction(name: "Persistent confirmation", steps: [bool, number,
            ActionStep("script", ["script": "if(context.configuredValues.enabled!==false||context.configuredValues.count!==0)throw new Error('False or zero lost');editor.setText('false|0');"])])
        original.rawPayload = #"{"unknown":{"keep":true}}"#
        try source.library.saveAction(original)
        host.fields = ["enabled": false, "count": 0]
        #expect(await source.runner.runAsync(original).reason == .success)
        let confirmed = try #require(source.library.actions.first { $0.id == original.id })
        let destination = try LibraryStore(inMemory: true, seed: false)
        if transport == "export" {
            let decoded = try #require(ActionImporter.decode(JSONEncoder().encode(confirmed)).first)
            try destination.saveActions([decoded])
        } else { try destination.restore(source.library.backupData()) }
        let restored = try #require(destination.actions.first { $0.id == original.id })
        #expect(restored == confirmed)
        #expect(restored.configuredValues["enabled"] == "false" && restored.configuredValues["count"] == "0")
        let receivingHost = ConfigurationPersistenceHost()
        let receiving = try ScriptTestFixture(content: "Receiver", host: receivingHost, library: destination)
        #expect(await receiving.runner.runAsync(restored).reason == .success)
        #expect(receivingHost.promptKeys.isEmpty && receiving.editor.content == "false|0")
        var extended = restored
        extended.steps.insert(ActionStep("configurationKey", ["key": "newLabel", "name": "New label", "dataType": "string", "defaultStringValue": "Default", "requiresInitialConfiguration": "true"]), at: 2)
        try destination.saveActions([extended])
        receivingHost.fields = ["newLabel": "New accepted"]
        let report = await receiving.runner.runAsync(extended)
        #expect(report.reason == .success, Comment(rawValue: receiving.runner.message ?? ""))
        #expect(receivingHost.promptKeys == [["newLabel"]])
        let saved = try #require(destination.actions.first { $0.id == original.id })
        #expect(saved.configuredValues["enabled"] == "false" && saved.configuredValues["count"] == "0")
        #expect(saved.configuredValues["newLabel"] == "New accepted" && saved.rawPayload == original.rawPayload)
        #expect(saved.steps.prefix(2).map(\.id) == original.steps.prefix(2).map(\.id))
        #expect(await receiving.runner.runAsync(saved).reason == .success)
        #expect(receivingHost.promptKeys == [["newLabel"]])
    }
}

@MainActor private final class ConfigurationPersistenceHost: ActionHost {
    var fields: [String: Any] = [:]
    var promptKeys: [[String]] = []
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        guard operation == "prompt" else { throw DraftlyError.message("Unexpected persistence test operation: \(operation)") }
        promptKeys.append((values["fields"] as? [[String: Any]] ?? []).compactMap { $0["key"] as? String })
        return ["index": 0, "fields": fields]
    }
}
