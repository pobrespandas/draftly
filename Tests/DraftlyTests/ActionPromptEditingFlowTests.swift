import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@MainActor private final class PromptEditingHost: ActionHost {
    var response: Any?
    var prompts: [[String: Any]] = []

    init(response: Any?) { self.response = response }

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        guard operation == "prompt" else { throw DraftlyError.message("Unexpected prompt editing operation: \(operation)") }
        prompts.append(values)
        return response
    }
}

@MainActor private struct PromptEditingFixture {
    private let execution: ActionEditingExecutionFixture
    var library: LibraryStore { execution.library }
    var editor: EditorSession { execution.editor }
    var source: Note { execution.source }
    let host: PromptEditingHost
    let original: DraftAction

    init(response: Any?) throws {
        host = PromptEditingHost(response: response)
        execution = try ActionEditingExecutionFixture(host: host)
        var imported = ActionStep("prompt", ["futureOption": "Keep café 🐼"])
        imported.isEnabled = false
        imported.unknownFields = ["future": .object(["keep": .bool(true)])]
        var value = DraftAction(name: "Neutral prompt editing", steps: [imported])
        value.rawPayload = "{\"future\":true}"
        value.unknownFields = ["futureAction": .string("Keep")]
        original = value
        try library.saveAction(original)
    }

    func newCopy() -> ActionEditingCopy {
        var copy = ActionEditingCopy(action: original)
        copy.addStep("prompt")
        return copy
    }

    func save(_ copy: ActionEditingCopy) throws -> DraftAction {
        #expect(library.actions.first { $0.id == original.id } == original)
        let discarded = ActionEditingCopy(action: try #require(library.actions.first { $0.id == original.id }))
        #expect(discarded.action == original && discarded.action.steps.count == 1)
        #expect(discarded.action.steps[0].values["key"] == nil)
        #expect(discarded.action.steps[0].values["includeCancelButton"] == nil)
        try library.saveAction(copy.action)
        try library.reload()
        let saved = try #require(library.actions.first { $0.id == original.id })
        #expect(saved == copy.action && saved.id == original.id)
        #expect(saved.steps.first == original.steps.first)
        #expect(saved.steps.first?.values["key"] == nil)
        #expect(saved.rawPayload == original.rawPayload && saved.unknownFields == original.unknownFields)
        let promptID = try #require(copy.selectedStep)
        #expect(promptID != original.steps[0].id)
        #expect(saved.steps.contains { $0.id == promptID && $0.type == "prompt" })
        return saved
    }

    func run(_ action: DraftAction, asynchronous: Bool) async -> ActionExecutionReport {
        await execution.run(action, asynchronous: asynchronous)
    }

    func expectSourceUnchanged() {
        #expect(editor.noteID == source.id && editor.content == source.content)
        #expect(editor.selection == NSRange(location: 7, length: 4))
        #expect(library.notes.first { $0.id == source.id }?.content == source.content)
        #expect(library.notes.first { $0.id == source.id }?.isArchived == false)
    }
}

@Suite("Prompt editing flow") @MainActor
struct ActionPromptEditingFlowTests {
    @Test(arguments: [false, true])
    func newlySavedPromptUsesDocumentedDefaultsAndPublishesDefaultTags(asynchronous: Bool) async throws {
        let fixture = try PromptEditingFixture(response: ["index": 0, "fields": [:] as [String: Any]])
        var copy = fixture.newCopy()
        #expect(copy.action.steps[1].values == ["key": "prompt", "title": "Prompt", "message": "", "buttons": "OK",
            "includeTextField": "false", "textFieldDefault": "", "includeCancelButton": "true"])
        copy.action.steps.append(ActionStep("createDraft", ["template": "[[prompt_button]]: [[prompt_text]]", "openInEditor": "false"]))
        let saved = try fixture.save(copy)
        #expect((await fixture.run(saved, asynchronous: asynchronous)).reason == .success)
        let prompt = try #require(fixture.host.prompts.first)
        #expect(fixture.host.prompts.count == 1)
        #expect(prompt["title"] as? String == "Prompt" && prompt["message"] as? String == "")
        #expect(prompt["isCancellable"] as? Bool == true)
        #expect((prompt["fields"] as? [[String: Any]])?.isEmpty == true)
        #expect(prompt["buttons"] as? [[String: String]] == [["title": "OK"]])
        #expect(fixture.library.notes.count == 2)
        #expect(fixture.library.notes.first { $0.id != fixture.source.id }?.content == "OK: ")
        fixture.expectSourceUnchanged()
    }

    @Test(arguments: [false, true])
    func savedTextAndSecondButtonUseCustomTagsAndRenderedOptions(asynchronous: Bool) async throws {
        let fixture = try PromptEditingFixture(response: ["index": 1, "fields": ["text": "Chosen café 🐼"]])
        var copy = fixture.newCopy()
        copy.action.steps[1].values = ["key": "choice", "title": "Choose [[title]]", "message": "[[draft]]", "buttons": "First|Second",
            "includeTextField": "true", "textFieldDefault": "[[title]]", "includeCancelButton": "false", "futureOption": "Keep"]
        copy.action.steps[1].unknownFields = ["futurePrompt": .array([.bool(false), .null])]
        copy.action.steps.append(ActionStep("createDraft", ["template": "[[choice_button]]: [[choice_text]]", "openInEditor": "false"]))
        let saved = try fixture.save(copy)
        #expect((await fixture.run(saved, asynchronous: asynchronous)).reason == .success)
        let prompt = try #require(fixture.host.prompts.first)
        #expect(fixture.host.prompts.count == 1)
        #expect(prompt["title"] as? String == "Choose " + fixture.source.content)
        #expect(prompt["message"] as? String == fixture.source.content)
        #expect(prompt["isCancellable"] as? Bool == false)
        #expect(prompt["buttons"] as? [[String: String]] == [["title": "First"], ["title": "Second"]])
        let field = try #require((prompt["fields"] as? [[String: Any]])?.first)
        #expect(field["key"] as? String == "text" && field["kind"] as? String == "text")
        #expect(field["value"] as? String == fixture.source.content)
        #expect(fixture.library.notes.count == 2)
        #expect(fixture.library.notes.first { $0.id != fixture.source.id }?.content == "Second: Chosen café 🐼")
        #expect(fixture.library.actions.first { $0.id == saved.id } == saved)
        fixture.expectSourceUnchanged()
    }

    @Test(arguments: [false, true])
    func cancellationStopsLaterStepsAndAnAlreadyQueuedActionWithoutArchiving(asynchronous: Bool) async throws {
        let fixture = try PromptEditingFixture(response: nil)
        let queued = DraftAction(name: "Neutral queued prompt tail", steps: [ActionStep("insertText", ["template": "Must not run"])])
        try fixture.library.saveAction(queued)
        var copy = fixture.newCopy()
        copy.action.steps.insert(ActionStep("script", ["script": "app.queueAction(Action.find('\(queued.name)'),draft);"]), at: 1)
        copy.action.steps.append(ActionStep("createDraft", ["template": "Must not exist", "openInEditor": "false"]))
        copy.action.afterSuccess = "archive"
        let saved = try fixture.save(copy)
        let report = await fixture.run(saved, asynchronous: asynchronous)
        #expect(report.reason == .cancelled && report.result == .cancelled)
        #expect(fixture.host.prompts.count == 1)
        #expect(fixture.library.notes.count == 1)
        #expect(fixture.library.actions.first { $0.id == saved.id } == saved)
        fixture.expectSourceUnchanged()
    }

    @Test(arguments: ["key", "buttons"], [false, true])
    func invalidEmptyKeysAndButtonTitlesFailBeforeHostOrLaterEffects(key: String, asynchronous: Bool) async throws {
        let fixture = try PromptEditingFixture(response: ["index": 0, "fields": [:] as [String: Any]])
        var copy = fixture.newCopy()
        copy.action.steps[1].values[key] = ""
        copy.action.steps.append(ActionStep("createDraft", ["template": "Must not exist", "openInEditor": "false"]))
        copy.action.afterSuccess = "archive"
        let saved = try fixture.save(copy)
        let report = await fixture.run(saved, asynchronous: asynchronous)
        #expect(report.reason == .error)
        if case .failure(let message) = report.result {
            #expect(message.contains("prompt key and button titles must not be empty"))
        } else { Issue.record("The invalid prompt did not return an error.") }
        #expect(fixture.host.prompts.isEmpty)
        #expect(fixture.library.notes.count == 1)
        fixture.expectSourceUnchanged()
    }
}
