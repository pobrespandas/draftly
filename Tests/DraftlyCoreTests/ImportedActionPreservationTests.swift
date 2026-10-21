import Foundation
import Testing
@testable import DraftlyCore

@Suite("Imported action payload recovery") @MainActor
struct ImportedActionPreservationTests {
    @Test func disabledUnknownPayloadSurvivesExportBackupAndRestore() async throws {
        let source = Data(#"{"name":"Future disabled","unknown":{"nullable":null,"unicode":"café 🐼","values":[1,true]},"steps":[{"type":"futureStep","isEnabled":false,"data":{"nested":{"keep":["x",null]},"futureOption":true}},{"type":"script","data":{"script":"context.addSuccessParameter('retained','yes');"}}]}"#.utf8)
        let action = try #require(ActionImporter.decode(source).first)
        let exported = try JSONEncoder().encode(action)
        let reimported = try #require(ActionImporter.decode(exported).first)
        #expect(reimported.rawPayload == action.rawPayload)
        #expect(reimported.steps == action.steps)
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveAction(reimported)
        let recovered = try LibraryStore(inMemory: true, seed: false)
        try recovered.restore(library.backupData())
        let restored = try #require(recovered.actions.first { $0.id == action.id })
        #expect(restored.rawPayload == action.rawPayload && restored.steps == action.steps)
        let originalJSON = try JSONSerialization.jsonObject(with: source) as? NSDictionary
        let recoveredJSON = try JSONSerialization.jsonObject(with: Data(try #require(restored.rawPayload).utf8)) as? NSDictionary
        #expect(recoveredJSON == originalJSON)
        let editor = EditorSession(); editor.load(try recovered.createNote(content: "Keep"))
        let report = await ActionRunner(library: recovered, editor: editor).runAsync(restored)
        #expect(report.reason == .success && report.successParameters["retained"] == "yes")
        #expect(editor.content == "Keep")
    }
    @Test func separatorIdentityOrderAndUnknownFieldsSurviveBackupRestoration() throws {
        let source = Data(#"{"name":"Section 🐼","backingIsSeparator":true,"steps":[],"unknown":{"keep":[false,null,"café"]}}"#.utf8)
        var separator = try #require(ActionImporter.decode(source).first)
        separator.group = "Neutral order"; separator.presentation.order = 1
        var before = DraftAction(name: "Before", steps: [])
        before.group = separator.group; before.presentation.order = 0
        var after = DraftAction(name: "After", steps: [])
        after.group = separator.group; after.presentation.order = 2
        let library = try LibraryStore(inMemory: true, seed: false)
        for action in [after, separator, before] { try library.saveAction(action) }
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.orderedActions().map(\.id) == [before.id, separator.id, after.id])
        let recovered = try #require(restored.actions.first { $0.id == separator.id })
        #expect(recovered.isSeparator && recovered.steps.isEmpty)
        #expect(recovered.rawPayload == separator.rawPayload)
        let reimport = try #require(ActionImporter.decode(JSONEncoder().encode(recovered)).first)
        #expect(reimport.id == separator.id && reimport.isSeparator && reimport.presentation.order == 1)
        #expect(reimport.rawPayload == separator.rawPayload)
    }

    @Test(arguments: [false, true])
    func nativeUnknownFieldsSurviveEditsRepeatedImportAndBackup(array: Bool) async throws {
        var disabled = ActionStep("futureStep", ["value": "Original"])
        disabled.isEnabled = false
        let script = ActionStep("script", ["script": "context.addSuccessParameter('retained','yes');"])
        var original = DraftAction(name: "Native future", steps: [disabled, script])
        original.options = ActionPresentation()
        original.rawPayload = #"{"originalForeign":"retained"}"#
        original.sourceURL = "fixture://native"
        let future: JSONValue = .object(["null": .null, "flag": .bool(false),
            "decimal": .number(123456789.125), "unicode": .string("café 🐼"),
            "nested": .array([.string("value"), .null, .bool(true)])])
        func object<T: Encodable>(_ value: T) throws -> [String: JSONValue] {
            try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(value))
        }
        var source = try object(original)
        var step = try object(disabled)
        var options = try object(original.presentation)
        step["futureStepMetadata"] = future
        options["futurePresentation"] = future
        source["futureAction"] = future
        source["steps"] = .array([.object(step), .object(try object(script))])
        source["options"] = .object(options)
        let input: JSONValue = array ? .array([.object(source)]) : .object(source)
        var imported = try #require(ActionImporter.decode(JSONEncoder().encode(input)).first)
        imported.name = "Edited native"
        imported.steps[0].values["value"] = "Edited literal"
        imported.presentation.description = "Edited description"
        for _ in 0..<2 {
            imported = try #require(ActionImporter.decode(JSONEncoder().encode(imported)).first)
        }
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveAction(imported)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        let recovered = try #require(restored.actions.first { $0.id == original.id })
        let output = try object(recovered)
        step["values"] = .object(["value": .string("Edited literal")])
        options["description"] = .string("Edited description")
        #expect(output["futureAction"] == future)
        #expect(output["unknownFields"] == nil)
        #expect(output["steps"] == .array([.object(step), .object(try object(script))]))
        #expect(output["options"] == .object(options))
        #expect(recovered.name == "Edited native" && recovered.rawPayload == original.rawPayload)
        #expect(recovered.sourceURL == original.sourceURL && recovered.unsupportedSteps.isEmpty)
        let editor = EditorSession(); editor.load(try restored.createNote(content: "Keep"))
        let report = await ActionRunner(library: restored, editor: editor).runAsync(recovered)
        #expect(report.reason == .success && report.successParameters["retained"] == "yes")
        #expect(editor.content == "Keep")
    }

    @Test(arguments: [(false, false, false), (false, false, true),
                      (false, true, false), (false, true, true),
                      (true, false, false), (true, false, true),
                      (true, true, false), (true, true, true)])
    func containersPreserveNativeEntriesAndForeignStepData(wrapped: Bool, mixed: Bool, nativeSeparator: Bool) throws {
        var native = DraftAction(name: "Native café 🐼", steps: [ActionStep("futureStep", ["value": "Keep"])])
        native.steps[0].isEnabled = false
        if nativeSeparator { native.scriptMetadata = ["isSeparator": "true"] }
        native.shortcut = "k"
        native.shortcutModifiers = ["command", "shift"]
        native.options = ActionPresentation()
        native.presentation.description = "Native options"
        native.sourceURL = "fixture://original"
        native.rawPayload = "original payload"
        native.unknownFields = ["future": .number(try #require(Decimal(string: "123456789.123456789")))]
        native.steps[0].unknownFields = ["futureStep": .array([.null, .bool(false)])]
        native.presentation.unknownFields = ["futureOption": .string("café 🐼")]
        let nativeJSON = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(native))
        let foreignID = UUID()
        let foreign: JSONValue = .object(["name": .string("Foreign"), "uuid": .string(foreignID.uuidString),
            "steps": .array([.object(["type": .string("script"),
                "data": .object(["script": .string("context.addSuccessParameter('foreign','kept');")])])])])
        let separatorID = UUID()
        let separator: JSONValue = .object(["name": .string("Foreign section"),
            "uuid": .string(separatorID.uuidString), "backingIsSeparator": .bool(true),
            "steps": .array([]), "unknown": .array([.null, .bool(false), .string("café 🐼")])])
        let entries: JSONValue = .array(mixed ? [foreign, separator, nativeJSON] : [nativeJSON])
        let input: JSONValue = wrapped ? .object(["actions": entries]) : entries
        let decoded = try ActionImporter.decode(JSONEncoder().encode(input), source: "fixture://new")
        #expect(decoded.count == (mixed ? 3 : 1))
        #expect(decoded.last == native)
        #expect(decoded.last?.isSeparator == nativeSeparator)
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveActions(decoded)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(Dictionary(uniqueKeysWithValues: restored.actions.map { ($0.id, $0) }) ==
                Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) }))
        if mixed {
            #expect(decoded[1].id == separatorID && decoded[1].isSeparator)
            let payload = try #require(decoded[1].rawPayload)
            #expect(try JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8)) == separator)
            #expect(decoded.first?.id == foreignID)
            #expect(decoded.first?.steps.first?.values["script"] == "context.addSuccessParameter('foreign','kept');")
        }
    }

    @Test func futureFieldsCannotReplaceIdentityOrExecutionSettings() throws {
        var step = ActionStep("futureStep")
        step.isEnabled = false
        step.unknownFields = ["id": .string(UUID().uuidString), "type": .string("clipboard"),
            "isEnabled": .bool(true), "futureStep": .array([.null, .bool(false)])]
        var options = ActionPresentation()
        options.unknownFields = ["showInList": .bool(false), "futureOptions": .string("café 🐼")]
        var action = DraftAction(name: "Typed name", steps: [step])
        action.options = options
        action.unknownFields = ["id": .string(UUID().uuidString), "name": .string("Wrong name"),
            "options": .null, "steps": .array([]), "futureAction": .bool(false),
            "unknownFields": .object(["external": .string("Retain this key too")])]
        let encoded = try JSONEncoder().encode(action)
        let recovered = try JSONDecoder().decode(DraftAction.self, from: encoded)
        #expect(recovered.id == action.id && recovered.name == action.name)
        #expect(recovered.steps.first?.id == step.id && recovered.steps.first?.type == "futureStep")
        #expect(recovered.steps.first?.isEnabled == false && recovered.presentation.showInList)
        #expect(recovered.unknownFields == ["futureAction": .bool(false),
            "unknownFields": .object(["external": .string("Retain this key too")])])
        #expect(recovered.steps.first?.unknownFields == ["futureStep": .array([.null, .bool(false)])])
        #expect(recovered.presentation.unknownFields == ["futureOptions": .string("café 🐼")])
    }

}
