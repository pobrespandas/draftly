import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class AppMessageHost: ActionHost {
    let fallback = APIContractHost()
    private(set) var banners: [[String: Any]] = []
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "displayMessage" { banners.append(values); return nil }
        return try fallback.perform(operation, values: values)
    }
}

@Suite("App message contracts") @MainActor
struct AppMessageContractTests {
    @Test(arguments: [false, true], ["displayInfoMessage", "displaySuccessMessage", "displayWarningMessage", "displayErrorMessage"])
    func messageMethodsReturnVoidAndPreserveTheExactMessage(worker: Bool, method: String) async throws {
        for message in ["", "Neutral café 🐼 +&?%\nSecond line"] {
            let fixture = try ScriptTestFixture(content: "Keep café 🐼", host: AppMessageHost())
            let library = fixture.library, editor = fixture.editor, runner = fixture.runner
            let host = fixture.host
            let notes = library.notes
            let revisions = library.revisions
            let literal = String(decoding: try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed]), as: UTF8.self)
            let action = makeAPIAction("var returned=app.\(method)(\(literal));app.setClipboard(typeof returned);")
            #expect(await ActionTestExecution.succeeds(action, runner: runner, worker: worker),
                    Comment(rawValue: runner.message ?? ""))
            #expect(host.fallback.clipboard == "undefined")
            try #require(host.banners.count == 1)
            #expect(host.banners[0]["message"] as? String == message)
            let severity = ["displayInfoMessage": "info", "displaySuccessMessage": "success",
                "displayWarningMessage": "warning", "displayErrorMessage": "error"][method]
            #expect(host.banners[0]["severity"] as? String == severity)
            let run = try #require(library.runs.first { $0.actionID == action.id })
            #expect(run.status == "Success" && run.message == message)
            #expect(editor.content == "Keep café 🐼")
            #expect(library.notes.map(\.content) == notes.map(\.content))
            #expect(library.notes.map(\.tags) == notes.map(\.tags))
            #expect(library.notes.map(\.flag) == notes.map(\.flag))
            #expect(library.revisions == revisions)
            #expect(library.actions.isEmpty && library.workspaces.isEmpty)
        }
    }
}
