import Foundation
import Testing
@testable import DraftlyCore

@Suite("Script command boundary") @MainActor
struct ScriptCommandTests {
    @Test func omittedAndWrongTypeValuesKeepLegacyDefaults() throws {
        let fixture = try ScriptTestFixture(content: "Source 🐼", host: APIContractHost())
        let command = try #require(try ScriptCommand(operation: "setEditorText", values: ["text": 42]))
        #expect(try fixture.runner.perform(command) as? Bool == true)
        #expect(fixture.editor.content.isEmpty)
        #expect(fixture.library.notes.first?.content == "")
        let find = try #require(try ScriptCommand(operation: "findDraft", values: ["uuid": "invalid"]))
        #expect(try fixture.runner.perform(find) == nil)
        let encoded = try #require(try ScriptCommand(operation: "base64Encode", values: [:]))
        #expect(try fixture.runner.perform(encoded) as? String == "")
    }

    @Test func queryDefaultsAndErrorsRemainAtTheWireBoundary() throws {
        let command = try #require(try ScriptCommand(operation: "queryDrafts", values: [:]))
        guard case .queryDrafts(let query) = command else { Issue.record("Expected a draft query"); return }
        #expect(query.workspace.folder == .all)
        #expect(query.workspace.sort == .modified && !query.workspace.ascending)
        #expect(!query.omitFlagged && !query.flaggedToTop)
        for values: [String: Any] in [["folder": "unknown"], ["sort": "unknown"]] {
            #expect(throws: DraftlyError.self) { try ScriptCommand(operation: "queryDrafts", values: values) }
        }
    }

    @Test func rangeValidationUsesUTF16AndRejectsOverflowWithoutChangingText() throws {
        let text = "🐼 café\r\n"
        let length = (text as NSString).length
        #expect(try ScriptTextRange([:]).validated(in: text) == NSRange(location: 0, length: 0))
        #expect(try ScriptTextRange(["location": length]).validated(in: text) == NSRange(location: length, length: 0))
        let fixture = try ScriptTestFixture(content: text, host: APIContractHost())
        var synchronizations = 0
        fixture.editor.synchronizeScriptEdit = { synchronizations += 1 }
        for range in [NSRange(location: -1, length: 0), NSRange(location: 0, length: -1),
                      NSRange(location: length + 1, length: 0), NSRange(location: 1, length: Int.max)] {
            let command = try #require(try ScriptCommand(operation: "replaceRange", values: ["location": range.location, "length": range.length, "text": "Rejected"]))
            #expect(throws: DraftlyError.self) { try fixture.runner.perform(command) }
            #expect(fixture.editor.content == text && fixture.library.notes.first?.content == text)
        }
        #expect(synchronizations == 0)
    }

    @Test func selectionClampsWhileTextRangeCommandsRejectInvalidRanges() throws {
        let fixture = try ScriptTestFixture(content: "🐼", host: APIContractHost())
        let command = try #require(try ScriptCommand(operation: "setSelection", values: ["location": 100, "length": 100]))
        #expect(try fixture.runner.perform(command) as? Bool == true)
        #expect(fixture.editor.selection == NSRange(location: 2, length: 0))
        let read = try #require(try ScriptCommand(operation: "textInRange", values: ["location": 100]))
        #expect(throws: DraftlyError.self) { try fixture.runner.perform(read) }
    }

    @Test func draftLoadSavesBeforeResolvingItsInputAndStopsOnSaveFailure() throws {
        let fixture = try ScriptTestFixture(content: "Original", host: APIContractHost())
        let noteID = try #require(fixture.editor.noteID)
        let command = try #require(try ScriptCommand(operation: "loadDraft", values: ["uuid": noteID.uuidString]))
        fixture.editor.content = "Pending 🐼"
        #expect(try fixture.runner.perform(command) as? Bool == true)
        #expect(fixture.editor.content == "Pending 🐼")
        #expect(fixture.library.notes.first?.content == "Pending 🐼")

        fixture.editor.content = "Keep unsaved"
        fixture.library.beforeBatchCommit = { throw DraftlyError.message("Command save failed") }
        defer { fixture.library.beforeBatchCommit = nil }
        #expect(throws: DraftlyError.self) { try fixture.runner.perform(command) }
        #expect(fixture.editor.content == "Keep unsaved" && fixture.editor.noteID == noteID)
        #expect(fixture.library.notes.first?.content == "Pending 🐼")
    }

    @Test func missingWindowAndQueueTargetsKeepTheirErrorPrecedence() throws {
        let fixture = try ScriptTestFixture(content: "Source", host: APIContractHost())
        let apply = try #require(try ScriptCommand(operation: "applyWorkspace", values: ["loadFolder": "invalid"]))
        do {
            _ = try fixture.runner.perform(apply)
            Issue.record("Workspace application must require a window")
        } catch { #expect(error.localizedDescription == "Workspace application requires an open window.") }
        let queue = try #require(try ScriptCommand(operation: "queueAction", values: ["draft": ["uuid": "invalid"]]))
        do {
            _ = try fixture.runner.perform(queue)
            Issue.record("Queueing must require an existing action")
        } catch { #expect(error.localizedDescription == "The queued action was not found.") }
        #expect(fixture.runner.queued.isEmpty)
    }

    @Test func commandsOutsideTheTypedCoreStillReachTheCapabilityHost() throws {
        let host = ForwardedCommandHost()
        let fixture = try ScriptTestFixture(content: "Source", host: host)
        #expect(try ScriptCommand(operation: "futureCapability", values: [:]) == nil)
        #expect(fixture.runner.run(ScriptTestAction.make("""
        const response=JSON.parse(__host('futureCapability',JSON.stringify({text:'Neutral 🐼',enabled:false,nested:{version:2}})));
        check(response.value==='Forwarded','capability response');
        """, name: "Command forwarding")), Comment(rawValue: fixture.runner.message ?? ""))
        #expect(host.operation == "futureCapability")
        #expect(host.values["text"] as? String == "Neutral 🐼")
        #expect(host.values["enabled"] as? Bool == false)
        #expect((host.values["nested"] as? [String: Int])?["version"] == 2)
    }
}

@MainActor private final class ForwardedCommandHost: ActionHost {
    var operation: String?
    var values: [String: Any] = [:]

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        self.operation = operation
        self.values = values
        return "Forwarded"
    }
}
