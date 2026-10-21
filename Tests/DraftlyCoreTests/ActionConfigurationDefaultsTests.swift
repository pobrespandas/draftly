import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action configuration default policies") @MainActor
struct ActionConfigurationDefaultsTests {
    private var defaults: [(key: String, values: [String: String], text: String)] {
        [
            ("untyped", ["defaultStringValue": "Untyped"], "Untyped"),
            ("string", ["dataType": "string", "defaultStringValue": "Typed"], "Typed"),
            ("text", ["dataType": "text", "defaultTextValue": "café 🐼\nText"], "café 🐼\nText"),
            ("boolean", ["dataType": "boolean", "defaultBoolValue": "1"], "1"),
            ("number", ["dataType": "number", "defaultNumberValue": "2.5"], "2.5"),
            ("generic", ["defaultValue": "Generic", "defaultStringValue": "Ignored"], "Generic"),
            ("empty", ["dataType": "text", "defaultValue": "", "defaultTextValue": "Ignored"], ""),
            ("missing", [:], ""),
            ("wrongKey", ["dataType": "text", "defaultStringValue": "Ignored"], ""),
            ("false", ["dataType": "boolean", "defaultValue": "false", "defaultBoolValue": "true"], "false"),
            ("zero", ["dataType": "number", "defaultValue": "0", "defaultNumberValue": "7"], "0")
        ]
    }

    @Test func importerRetainsStringDefaultsForDisabledFieldsAndLastDuplicate() throws {
        var steps = defaults.map { row -> [String: Any] in
            ["type": "configurationKey", "data": row.values.merging(["key": row.key]) { _, new in new }]
        }
        steps += [
            ["type": "configurationKey", "isEnabled": false,
             "data": ["key": "disabled", "dataType": "unknown", "defaultStringValue": "Disabled default"]],
            ["type": "configurationKey", "data": ["key": "duplicate", "defaultStringValue": "First"]],
            ["type": "configurationKey", "data": ["key": "duplicate", "dataType": "number", "defaultNumberValue": "6.25"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: ["name": "Neutral defaults", "steps": steps])
        let action = try #require(ActionImporter.decode(data).first)
        var expected = Dictionary(uniqueKeysWithValues: defaults.map { ($0.key, $0.text) })
        expected["disabled"] = "Disabled default"; expected["duplicate"] = "6.25"

        #expect(action.configuredValues == expected)
        #expect(action.steps[defaults.count].isEnabled == false)
        #expect(action.scriptMetadata?[ActionInitialConfiguration.confirmationKey] == nil)
        var native = action; native.configuredValues = ["nativeOnly": "Keep"]
        let decodedNative = try #require(ActionImporter.decode(JSONEncoder().encode(native)).first)
        #expect(decodedNative.configuredValues == ["nativeOnly": "Keep"])
    }

    @Test(arguments: [false, true])
    func runtimePrefersStoredTextThenConvertsOnlyKnownTypes(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Neutral", host: APIContractHost())
        var steps = defaults.map { field($0.key, values: $0.values) }
        steps += [
            field("storedEmpty", values: ["defaultValue": "Ignored", "defaultStringValue": "Also ignored"]),
            field("storedFalse", values: ["dataType": "boolean", "defaultBoolValue": "true"]),
            field("storedZero", values: ["dataType": "number", "defaultNumberValue": "12"]),
            field("invalidNumber", values: ["dataType": "number", "defaultNumberValue": "invalid"]),
            field("trueWord", values: ["dataType": "boolean", "defaultBoolValue": "true"]),
            field("upperBoolean", values: ["dataType": "boolean", "defaultBoolValue": "TRUE"]),
            field("spacedBoolean", values: ["dataType": "boolean", "defaultBoolValue": " true "])
        ]
        let script = ScriptTestAction.make(#"""
        const v=context.configuredValues;
        check(v.untyped==='Untyped' && v.string==='Typed' && v.text==='café 🐼\nText','string type defaults');
        check(v.boolean===true && v.number===2.5,'typed boolean and number');
        check(v.generic==='Configured' && v.empty==='' && v.missing==='' && v.wrongKey==='','text precedence');
        check(v.false===false && v.zero===0,'generic false and zero override typed defaults');
        check(v.storedEmpty==='' && v.storedFalse===false && v.storedZero===0,'stored empty false and zero');
        check(v.invalidNumber===0,'invalid number fallback');
        check(v.trueWord===true && v.upperBoolean===false && v.spacedBoolean===false,'exact boolean spelling');
        check(v.unknownStored==='Keep' && action.configuredValues===v,'unknown stored value and shared context');
        """#, name: "Default assertions")
        steps += script.steps
        var action = DraftAction(name: "Runtime defaults", steps: steps)
        action.configuredValues = ["generic": "Configured", "storedEmpty": "", "storedFalse": "false",
            "storedZero": "0", "unknownStored": "Keep"]

        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
            Comment(rawValue: fixture.runner.message ?? ""))
    }

    @Test func promptKeepsNumberDefaultsAsTextAndBooleanDefaultsAsBooleans() throws {
        let steps = defaults.map { field($0.key, values: $0.values, required: true) } + [
            field("storedEmpty", values: ["defaultStringValue": "Ignored"], required: true),
            field("storedFalse", values: ["dataType": "boolean", "defaultBoolValue": "true"], required: true),
            field("storedZero", values: ["dataType": "number", "defaultNumberValue": "12"], required: true)
        ]
        var action = DraftAction(name: "Prompt defaults", steps: steps)
        action.configuredValues = ["generic": "Configured", "storedEmpty": "", "storedFalse": "false", "storedZero": "0"]
        let definition = try ActionInitialConfiguration(action: action, steps: steps)
        let controls = try #require(definition.prompt["fields"] as? [[String: Any]])
        let byKey = Dictionary(uniqueKeysWithValues: controls.map { ($0["key"] as? String ?? "", $0) })
        var expectedText = Dictionary(uniqueKeysWithValues: defaults.filter { !["boolean", "false"].contains($0.key) }.map { ($0.key, $0.text) })
        expectedText["generic"] = "Configured"; expectedText["storedEmpty"] = ""; expectedText["storedZero"] = "0"
        for (key, value) in expectedText { #expect(byKey[key]?["value"] as? String == value) }
        #expect(controls.count == steps.count)
        #expect(byKey["boolean"]?["value"] as? Bool == true)
        #expect(byKey["false"]?["value"] as? Bool == false && byKey["storedFalse"]?["value"] as? Bool == false)
        #expect(byKey["number"]?["kind"] as? String == "number" && byKey["number"]?["allowDecimals"] as? Bool == true)
        #expect(byKey["text"]?["kind"] as? String == "textView" && byKey["untyped"]?["kind"] as? String == "text")
    }

    @Test func initialConfigurationIgnoresDisabledInvalidFieldsButRejectsEnabledUnknownTypes() throws {
        var disabled = field(" ", values: ["dataType": "unknown", "defaultStringValue": "Ignored"], required: true)
        disabled.isEnabled = false
        let action = DraftAction(name: "Definition policies", steps: [disabled])
        let definition = try ActionInitialConfiguration(action: action, steps: action.steps)
        #expect(!definition.needsPrompt && (definition.prompt["fields"] as? [[String: Any]])?.isEmpty == true)
        let optionalUnknown = field("optional", values: ["dataType": "unknown", "defaultStringValue": "Text"])
        #expect(throws: (any Error).self) { try ActionInitialConfiguration(action: action, steps: [optionalUnknown]) }
    }

    private func field(_ key: String, values: [String: String] = [:], required: Bool = false) -> ActionStep {
        ActionStep("configurationKey", values.merging(["key": key, "requiresInitialConfiguration": required ? "true" : "false"]) { _, new in new })
    }
}
