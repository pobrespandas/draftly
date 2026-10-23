import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Inspector option editing")
struct ActionInspectorOptionEditingTests {
    @Test func allSupportedStepsExposeTheirAbsentExecutionInputsWithoutWritingDefaults() throws {
        let expected: [String: [String]] = [
            "script": ["script", "allowAsync"], "clipboard": ["template", "writeType"],
            "share": ["template"], "url": ["url", "encodeTags", "template"],
            "callbackUrl": ["url", "encodeTags", "waitForResponse", "template"],
            "insertText": ["template"], "createDraft": ["folder", "tags", "syntax", "flagged", "flagType", "template"],
            "file": ["fileNameTemplate", "folderTemplate", "useBookmark", "bookmarkName", "writeType", "template"],
            "export": ["name", "template"], "openIn": ["name", "template"],
            "runShortcut": ["name", "waitForResponse", "template"], "runAppleScript": ["script"],
            "htmlpreview": ["hideInterface", "template"], "defineTemplateTag": ["name", "template"],
            "configureWindow": WindowConfigurationOptions.referenceKeys,
            "prompt": ["key", "title", "message", "buttons", "textFieldDefault"],
            "configurationKey": [], "includeAction": ["uuid", "name"],
            "mail": ["subject", "toRecipients", "ccRecipients", "bccRecipients", "replyToRecipients", "isBodyHTML", "sendInBackground", "template"],
            "message": ["subject", "toRecipients", "template"], "listInReminders": ["list", "template"],
            "reminder": ["template"], "event": ["template"],
            "print": ["format", "topMargin", "bottomMargin", "leftMargin", "rightMargin", "template"],
            "speak": ["autoStart", "autoClose", "template"]
        ]
        #expect(Set(expected.keys) == DraftAction.supportedSteps)
        for (type, keys) in expected {
            var imported = ActionStep(type)
            imported.unknownFields = ["future": .object(["nested": .bool(false)])]
            let before = imported
            let fields = ActionStepInspectorFields.fields(for: imported)
            #expect(Set(fields.map(\.key)) == Set(keys), Comment(rawValue: type))
            for field in fields { _ = ActionStepInspectorFields.textValue(for: field.key, in: imported) }
            #expect(imported == before)
            #expect(try JSONDecoder().decode(ActionStep.self, from: JSONEncoder().encode(imported)) == before)
        }
    }

    @Test func aliasesStayEditableWithoutAddingKeysThatOverrideTheImportedValue() {
        let cases: [(String, String, String)] = [
            ("script", "source", "script"), ("script", "allowAsynchronous", "allowAsync"),
            ("clipboard", "text", "template"), ("file", "name", "fileNameTemplate"),
            ("createDraft", "location", "folder"), ("createDraft", "assignTags", "tags"),
            ("createDraft", "assignSyntax", "syntax"), ("defineTemplateTag", "tagName", "name"),
            ("listInReminders", "listTemplate", "list"), ("print", "printFormat", "format")
        ]
        for (type, alias, canonical) in cases {
            var step = ActionStep(type, [alias: "Imported café 🐼", "future": "Keep"])
            let id = step.id
            let keys = ActionStepInspectorFields.fields(for: step).map(\.key)
            #expect(keys.contains(alias) && !keys.contains(canonical), Comment(rawValue: type + ":" + alias))
            ActionStepInspectorFields.setText("Edited café 🐼", for: alias, in: &step)
            #expect(step.values[alias] == "Edited café 🐼" && step.values[canonical] == nil)
            #expect(step.values["future"] == "Keep" && step.id == id)
        }
        let syntax = ActionStep("createDraft", ["syntax": "", "assignSyntax": "TaskPaper"])
        #expect(ActionStepInspectorFields.textValue(for: "assignSyntax", in: syntax) == "TaskPaper")
    }

    @Test func booleansUseTheirExistingPoliciesAndChoicesRetainUnknownImports() throws {
        for raw in [String?.none, "true", "1", "false", "0", "future"] {
            for (type, key, enabled) in [
                ("script", "allowAsync", raw == "true" || raw == "1"),
                ("createDraft", "flagged", raw == "true" || raw == "1"),
                ("file", "useBookmark", raw == "true"), ("htmlpreview", "hideInterface", raw == "true"),
                ("speak", "autoStart", raw != "false"), ("runShortcut", "waitForResponse", raw != "false")
            ] {
                var step = ActionStep(type)
                step.values[key] = raw
                let before = step
                let field = try #require(ActionStepInspectorFields.fields(for: step).first { $0.key == key })
                #expect(ActionStepInspectorFields.toggleValue(for: field, in: step) == enabled)
                #expect(step == before)
            }
        }
        let unknown = ActionStep("clipboard", ["writeType": "futureMode"])
        #expect(ActionStepInspectorFields.textValue(for: "writeType", in: unknown) == "futureMode")
        #expect(ActionStepInspectorFields.fields(for: unknown).first { $0.key == "writeType" }?.control == .choice(["replace", "append", "prepend"]))
    }

    @Test func shadowedAliasesKeepTheirRawValuesAndShowWhichControlIsInactive() throws {
        let step = ActionStep("script", ["allowAsync": "false", "allowAsynchronous": "true", "script": "", "source": "Imported"])
        let original = step
        let field = try #require(ActionStepInspectorFields.fields(for: step).first { $0.key == "allowAsynchronous" })
        #expect(field.control == .text)
        #expect(ActionStepInspectorFields.title(for: field.key, in: step).contains("Inactive"))
        #expect(ActionStepInspectorFields.textValue(for: field.key, in: step) == "true")
        #expect(ActionStepInspectorFields.isShadowedAlias("source", in: step))
        #expect(!ActionStepInspectorFields.isShadowedAlias("script", in: step))
        #expect(step == original)
    }

    @Test func insertingATagAppendsToTheVisibleDefaultRatherThanDiscardingIt() {
        var step = ActionStep("clipboard")
        #expect(step.values.isEmpty)
        ActionStepInspectorFields.appendTag("title", for: "template", in: &step)
        #expect(step.values == ["template": "[[draft]][[title]]"])
        var alias = ActionStep("clipboard", ["text": "Keep café 🐼 "])
        ActionStepInspectorFields.appendTag("uuid", for: "text", in: &alias)
        #expect(alias.values == ["text": "Keep café 🐼 [[uuid]]"])
    }

    @Test func printDefaultsMatchTheNativeConsumerWithoutMaterializingValues() throws {
        let step = ActionStep("print")
        let defaults = ActionStepInspectorFields.defaults(for: step)
        let consumer = try NativePrintConfiguration([:])
        #expect(defaults["format"]?.lowercased() == consumer.format.rawValue)
        #expect(Double(try #require(defaults["topMargin"])) == Double(consumer.topMargin))
        #expect(step.values.isEmpty)
        #expect(ActionStepInspectorFields.limitation(for: ActionStep("future", ["platforms": "3"]))?.contains("not applied") == true)
        #expect(ActionStepInspectorFields.limitation(for: ActionStep("mail"))?.contains("unavailable") == true)
    }

    @MainActor @Test func failedSaveKeepsTheEditingCopyAndStoredActionForRetry() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = DraftAction(name: "Before failed save", steps: [ActionStep("file")])
        try library.saveAction(original)
        var copy = ActionEditingCopy(action: original)
        copy.action.name = "Retained edited café 🐼"
        ActionStepInspectorFields.setText("append", for: "writeType", in: &copy.action.steps[0])
        let edited = copy.action
        library.beforeBatchCommit = { throw DraftlyError.message("Injected inspector save failure") }
        #expect(throws: (any Error).self) { try copy.save(to: library) }
        #expect(library.actions == [original] && copy.action == edited)
        library.beforeBatchCommit = nil
        try copy.save(to: library)
        try library.reload()
        #expect(library.actions == [edited])
    }

    @MainActor @Test(arguments: [false, true])
    func editedFileAndClipboardOptionsReachTheExecutorAndRoundTrip(asynchronous: Bool) async throws {
        let host = InspectorOptionHost()
        let fixture = try ActionEditingExecutionFixture(host: host)
        var original = DraftAction(name: "Imported option flow", steps: [ActionStep("clipboard"), ActionStep("file")])
        original.rawPayload = "{\"future\":false}"
        original.unknownFields = ["extra": .array([.null, .bool(true)])]
        try fixture.library.saveAction(original)
        var copy = ActionEditingCopy(action: original)
        ActionStepInspectorFields.setText("Edited café 🐼", for: "template", in: &copy.action.steps[0])
        ActionStepInspectorFields.setText("append", for: "writeType", in: &copy.action.steps[0])
        for (key, value) in ["fileNameTemplate": "neutral.txt", "template": "File café 🐼", "useBookmark": "true", "bookmarkName": "QA", "folderTemplate": "sub", "writeType": "prepend"] {
            ActionStepInspectorFields.setText(value, for: key, in: &copy.action.steps[1])
        }
        #expect(fixture.library.actions.first == original)
        try fixture.library.saveAction(copy.action)
        let backup = try fixture.library.backupData()
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(backup)
        #expect(restored.actions.first == copy.action)
        #expect(await fixture.run(copy.action, asynchronous: asynchronous).reason == .success)
        #expect(host.clipboard == "Before Edited café 🐼")
        let file = try #require(host.file)
        #expect(file["name"] as? String == "neutral.txt" && file["text"] as? String == "File café 🐼")
        #expect(file["bookmark"] as? String == "QA" && file["folder"] as? String == "sub" && file["mode"] as? String == "prepend")
        #expect(fixture.library.actions.first == copy.action)
    }
}

@MainActor private final class InspectorOptionHost: ActionHost {
    var clipboard = "Before "
    var file: [String: Any]?
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        switch operation {
        case "getClipboard": return clipboard
        case "clipboard": clipboard = values["text"] as? String ?? ""; return true
        case "saveFile": file = values; return true
        default: throw DraftlyError.message("Unexpected host operation: " + operation)
        }
    }
}
