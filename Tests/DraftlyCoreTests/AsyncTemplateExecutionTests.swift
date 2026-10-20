import Foundation
import Testing
@testable import DraftlyCore

@Suite("Awaited action template execution") @MainActor
struct AsyncTemplateExecutionTests {
    @Test func firstPartyAndScriptTemplatesAwaitNestedNativeValues() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: TemplateExecutionHost())
        let action = DraftAction(name: "Templates", steps: [
            ActionStep("defineTemplateTag", ["name": "result", "template": "[[template|neutral]]"]),
            ActionStep("script", ["script": "editor.setText(draft.processTemplate('[[result]] / [[template|neutral]]'));"])
        ])
        let report = await f.runner.runAsync(action)
        #expect(report.reason == .success, "\(report) calls=\(f.host.calls)")
        #expect(f.editor.content == "café 🐼 1.5 / café 🐼 1.5")
        #expect(f.host.calls == ["fileAPI", "location", "fileAPI", "location"])
    }

    @Test func fileFieldsAndCreatedDraftTagsUseTheAwaitedRenderer() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: TemplateExecutionHost())
        let report = await f.runner.runAsync(DraftAction(name: "Fields", steps: [
            ActionStep("export", ["name": "[[template|neutral]].txt"]),
            ActionStep("createDraft", ["template": "Created", "assignTags": "[[template|neutral]], extra", "openInEditor": "false"])
        ]))
        #expect(report.reason == .success, "\(report) calls=\(f.host.calls)")
        #expect(f.host.exportName == "café 🐼 1.5.txt")
        #expect(f.library.notes.first { $0.content == "Created" }?.tags == ["café 🐼 1.5", "extra"])
        #expect(f.editor.content == "Keep")
    }

    @Test func nativeTemplateFailureStopsStepsAndSuccessEffects() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: TemplateExecutionHost())
        f.host.failure = ActionExecutionInterruption.timeout
        var action = DraftAction(name: "Failed template", steps: [
            ActionStep("insertText", ["template": "[[template|neutral]]"]),
            ActionStep("insertText", ["template": "Late"])
        ])
        action.afterSuccess = "archive"
        #expect(await f.runner.runAsync(action).reason == .timeout)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
        #expect(f.host.calls == ["fileAPI"])
    }
}

@MainActor private final class TemplateExecutionHost: ActionHost {
    var calls: [String] = []
    var exportName: String?
    var failure: Error?
    func supportsAsync(_ operation: String) -> Bool { ["fileAPI", "location", "saveFile"].contains(operation) }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "device" { return [String: String]() }
        Issue.record("A template used the synchronous host."); return nil
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        calls.append(operation)
        await Task.yield()
        if let failure { throw failure }
        switch operation {
        case "fileAPI": return #"{"value":"café 🐼 [[latitude]]"}"#
        case "location": return #"{"value":{"latitude":1.5,"longitude":2.5}}"#
        case "saveFile":
            let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
            exportName = values?["name"] as? String
            return #"{"value":true}"#
        default: throw DraftlyError.message("Unexpected template fixture request.")
        }
    }
}
