import Foundation
import Testing
@testable import DraftlyCore

@Suite("Initial action configuration execution") @MainActor
struct InitialConfigurationExecutionTests {
    private func action(required: String = "true", enabled: Bool = true) -> DraftAction {
        var key = ActionStep("configurationKey", ["key": "label", "name": "Neutral label", "description": "Test configuration", "dataType": "string", "defaultStringValue": "Default", "requiresInitialConfiguration": required])
        key.isEnabled = enabled
        var action = DraftAction(name: "Initial configuration", steps: [key,
            ActionStep("script", ["script": "editor.setText(context.configuredValues.label || 'No configuration');"])])
        action.configuredValues = ["label": "Default"]
        action.rawPayload = #"{"unknown":{"keep":"neutral"},"steps":[]}"#
        return action
    }

    @Test(arguments: [false, true])
    func importedDefaultsRequireConfirmationAndAcceptedValuesPersistBeforeExecution(asynchronous: Bool) async throws {
        let host = InitialConfigurationHost(), f = try ScriptTestFixture(content: "Keep", host: host)
        let original = action(); try f.library.saveAction(original)
        host.fields = ["label": "Confirmed café 🐼"]
        let first = asynchronous ? await f.runner.runAsync(original) : f.runner.runReport(original)
        #expect(first.reason == .success, Comment(rawValue: f.runner.message ?? ""))
        #expect(host.prompts == 1 && f.editor.content == "Confirmed café 🐼")
        let saved = try #require(f.library.actions.first { $0.id == original.id })
        #expect(saved.configuredValues["label"] == "Confirmed café 🐼" && saved.rawPayload == original.rawPayload)
        let second = asynchronous ? await f.runner.runAsync(saved) : f.runner.runReport(saved)
        #expect(second.reason == .success && host.prompts == 1)
    }

    @Test(arguments: [false, true])
    func newlyRequiredKeyInvalidatesPriorConfirmation(asynchronous: Bool) async throws {
        let host = InitialConfigurationHost(), f = try ScriptTestFixture(content: "Keep", host: host)
        let original = action(); try f.library.saveAction(original)
        host.fields = ["label": "First accepted"]
        let first = asynchronous ? await f.runner.runAsync(original) : f.runner.runReport(original)
        #expect(first.reason == .success && host.prompts == 1)
        var changed = try #require(f.library.actions.first { $0.id == original.id })
        changed.steps.insert(ActionStep("configurationKey", ["key": "newKey", "name": "New required key", "dataType": "string", "defaultStringValue": "New default", "requiresInitialConfiguration": "true"]), at: 1)
        try f.library.saveAction(changed)
        host.fields = ["newKey": "New accepted"]
        let second = asynchronous ? await f.runner.runAsync(changed) : f.runner.runReport(changed)
        #expect(second.reason == .success && host.prompts == 2)
        let saved = try #require(f.library.actions.first { $0.id == original.id })
        #expect(saved.configuredValues["newKey"] == "New accepted" && f.editor.content == "First accepted")
        let third = asynchronous ? await f.runner.runAsync(saved) : f.runner.runReport(saved)
        #expect(third.reason == .success && host.prompts == 2)
    }

    @Test(arguments: [false, true], ["cancel", "save failure"])
    func rejectedConfigurationDoesNotPersistOrExecute(asynchronous: Bool, rejection: String) async throws {
        let host = InitialConfigurationHost(), f = try ScriptTestFixture(content: "Keep", host: host)
        var original = action(); original.afterSuccess = "archive"
        try f.library.saveAction(original)
        host.fields = ["label": "Must not persist"]
        if rejection == "cancel" { host.accept = false }
        else { host.onPrompt = { f.library.beforeBatchCommit = { throw DraftlyError.message("Configuration save failure") } } }
        defer { f.library.beforeBatchCommit = nil }
        let report = asynchronous ? await f.runner.runAsync(original) : f.runner.runReport(original)
        #expect(report.reason == (rejection == "cancel" ? .cancelled : .error), Comment(rawValue: f.runner.message ?? ""))
        #expect(host.prompts == 1 && report.successParameters.isEmpty)
        #expect(f.library.actions.first { $0.id == original.id } == original)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.content == "Keep")
        #expect(f.library.notes.first?.isArchived == false)
    }

    @Test(arguments: [false, true], ["false", "disabled"])
    func optionalOrDisabledConfigurationDoesNotPrompt(asynchronous: Bool, mode: String) async throws {
        let host = InitialConfigurationHost(), f = try ScriptTestFixture(content: "Keep", host: host)
        let original = action(required: mode == "false" ? "false" : "true", enabled: mode != "disabled")
        try f.library.saveAction(original)
        let report = asynchronous ? await f.runner.runAsync(original) : f.runner.runReport(original)
        #expect(report.reason == .success && host.prompts == 0)
    }

    @Test(arguments: [false, true])
    func concurrentActionEditDuringPromptIsNotOverwritten(asynchronous: Bool) async throws {
        let host = InitialConfigurationHost(), f = try ScriptTestFixture(content: "Keep", host: host)
        let original = action(); try f.library.saveAction(original)
        var concurrent = original; concurrent.name = "Concurrent name"; concurrent.configuredValues["label"] = "Concurrent value"
        let external = concurrent
        host.fields = ["label": "Stale response"]
        host.onPrompt = { try? f.library.saveAction(external) }
        let report = asynchronous ? await f.runner.runAsync(original) : f.runner.runReport(original)
        #expect(report.reason == .error, Comment(rawValue: f.runner.message ?? ""))
        #expect(f.library.actions.first { $0.id == original.id } == external)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.content == "Keep")
    }

    @Test(arguments: [false, true], [false, true])
    func includedRequiredConfigurationCancelsBeforeChildEffects(asynchronous: Bool, dynamic: Bool) async throws {
        let host = InitialConfigurationHost(), f = try ScriptTestFixture(content: "Keep", host: host)
        var child = action(); child.name = "Required helper"
        child.steps.append(ActionStep("clipboard", ["template": "Child must not run"]))
        try f.library.saveAction(child)
        let include = dynamic ? ["name": "[[helper]]"] : ["uuid": child.id.uuidString]
        var root = DraftAction(name: "Configuration owner", steps: [
            ActionStep("script", ["script": "draft.setTemplateTag('helper','Required helper');app.setClipboard('Completed root effect');"]),
            ActionStep("includeAction", include),
            ActionStep("script", ["script": "editor.setText('Root must not continue');"])
        ])
        root.afterSuccess = "archive"
        try f.library.saveAction(root)
        host.accept = false
        var effectsAtPrompt: [String] = []
        host.onPrompt = { effectsAtPrompt = host.clipboardWrites }
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.reason == .cancelled && host.prompts == 1)
        let expected = dynamic ? ["Completed root effect"] : []
        #expect(effectsAtPrompt == expected && host.clipboardWrites == expected)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
        #expect(f.library.actions.first { $0.id == root.id } == root)
        #expect(f.library.actions.first { $0.id == child.id } == child)
    }

    @Test(arguments: [false, true])
    func ephemeralActionUsesAcceptedCopyWithoutInstallingIt(asynchronous: Bool) async throws {
        let host = InitialConfigurationHost(), f = try ScriptTestFixture(content: "Keep", host: host)
        host.fields = ["label": "Ephemeral value"]
        let original = action()
        let report = asynchronous ? await f.runner.runAsync(original) : f.runner.runReport(original)
        #expect(report.reason == .success && host.prompts == 1)
        #expect(f.editor.content == "Ephemeral value" && f.library.actions.isEmpty)
    }
}

@MainActor private final class InitialConfigurationHost: ActionHost {
    var prompts = 0
    var fields: [String: Any] = [:]
    var accept = true
    var onPrompt: (() -> Void)?
    var clipboardWrites: [String] = []
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "clipboard" { clipboardWrites.append(values["text"] as? String ?? ""); return true }
        guard operation == "prompt" else { throw DraftlyError.message("Unexpected configuration operation: \(operation)") }
        prompts += 1
        onPrompt?()
        guard accept else { return ["index": -1, "fields": [:]] as [String: Any] }
        return ["index": 0, "fields": fields]
    }
}
