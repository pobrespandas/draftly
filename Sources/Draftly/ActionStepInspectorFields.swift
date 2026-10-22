import Foundation
import DraftlyCore

enum ActionStepInspectorFields {
    struct Field: Identifiable, Equatable {
        let key: String
        let isMultiline: Bool
        let minHeight: CGFloat?
        var allowsTagInsertion: Bool { isMultiline }
        var id: String { key }
    }

    static func textValue(for key: String, in step: ActionStep) -> String {
        step.values[key] ?? (step.type == "prompt" ? ActionStepCreationDefaults.promptDefaults[key] : nil) ?? ""
    }

    static func title(for key: String, in step: ActionStep) -> String {
        if step.type == "configureWindow" { return WindowConfigurationOptions.title(for: key) }
        if step.type == "includeAction", key == "uuid" { return "Action UUID" }
        if step.type == "prompt" {
            switch key {
            case "key": return "Key"
            case "title": return "Title"
            case "message": return "Message"
            case "buttons": return "Buttons (separate with |)"
            case "textFieldDefault": return "Text Field Default"
            default: break
            }
        }
        return key
    }

    static let configurationTypes = ["string", "text", "boolean", "number"]
    static func configurationDefaultKey(for type: String) -> String? {
        switch type {
        case "string": "defaultStringValue"
        case "text": "defaultTextValue"
        case "boolean": "defaultBoolValue"
        case "number": "defaultNumberValue"
        default: nil
        }
    }

    static func fields(for step: ActionStep) -> [Field] {
        var excludedKeys: Set<String> = ["data", "parameters", "values", "uuid", "isEnabled", "platforms"]
        if step.type == "configurationKey" {
            excludedKeys.formUnion(["key", "name", "description", "dataType", "exampleValue",
                "requiresInitialConfiguration", "defaultValue"])
            excludedKeys.formUnion(configurationTypes.compactMap(configurationDefaultKey))
        }
        if step.type == "createDraft" { excludedKeys.insert("openInEditor") }
        if step.type == "configureWindow" { excludedKeys.formUnion(WindowConfigurationOptions.toggleKeys) }
        if step.type == "prompt" { excludedKeys.formUnion(["includeTextField", "includeCancelButton"]) }
        var keys = Set(step.values.keys)
        if step.type == "prompt" { keys.formUnion(ActionStepCreationDefaults.promptDefaults.keys) }
        if step.type == "configureWindow" { keys.formUnion(WindowConfigurationOptions.referenceKeys) }
        if step.type == "includeAction" {
            excludedKeys.remove("uuid")
            keys.formUnion(["uuid", "name"])
        }
        return keys.filter { !excludedKeys.contains($0) }.sorted().map { key in
            let isMultiline = ["template", "script", "source"].contains(key) || (step.type == "prompt" && key == "message")
            return Field(key: key, isMultiline: isMultiline,
                         minHeight: isMultiline ? (key == "message" ? 100 : key == "template" ? 180 : 360) : nil)
        }
    }
}
