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
        var keys = Set(step.values.keys)
        if step.type == "includeAction" {
            excludedKeys.remove("uuid")
            keys.formUnion(["uuid", "name"])
        }
        return keys.filter { !excludedKeys.contains($0) }.sorted().map { key in
            let isMultiline = ["template", "script", "source"].contains(key)
            return Field(key: key, isMultiline: isMultiline,
                         minHeight: isMultiline ? (key == "template" ? 180 : 360) : nil)
        }
    }
}
