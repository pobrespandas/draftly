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

    static func fields(for step: ActionStep) -> [Field] {
        let excludedKeys: Set<String> = ["data", "parameters", "values", "uuid", "isEnabled", "platforms"]
        return step.values.keys.filter { !excludedKeys.contains($0) }.sorted().map { key in
            let isMultiline = ["template", "script", "source"].contains(key)
            return Field(key: key, isMultiline: isMultiline,
                         minHeight: isMultiline ? (key == "template" ? 180 : 360) : nil)
        }
    }
}
