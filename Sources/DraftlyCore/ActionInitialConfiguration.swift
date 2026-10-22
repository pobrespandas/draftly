import Foundation
import CoreFoundation
import CryptoKit

struct ActionInitialConfiguration {
    static let confirmationKey = "_draftly.initialConfiguration"
    private struct Field {
        let step: ActionStep
        let key: String
        let type: String
    }
    private let action: DraftAction
    private let fields: [Field]
    let signature: String
    private let pending: Set<String>

    init(action: DraftAction, steps: [ActionStep]) throws {
        self.action = action
        let previous = action.scriptMetadata?[Self.confirmationKey].flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let confirmed = Set(previous)
        var fields: [Field] = []
        var required: Set<String> = []
        for step in steps where step.type == "configurationKey" && step.isEnabled != false {
            let definition = ActionConfigurationField(step)
            let key = definition.key, type = definition.dataType
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DraftlyError.message("The configured value key must not be empty.")
            }
            guard ActionStepValueRules.configurationTypes.contains(type) else {
                throw DraftlyError.message("The configured value type is not supported: " + type)
            }
            if ActionStepValueRules.requiresInitialConfiguration(step.values) {
                let identity = try JSONEncoder().encode([step.id.uuidString, key, type])
                let signature = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
                if !confirmed.contains(signature) {
                    required.insert(signature)
                    let field = Field(step: step, key: key, type: type)
                    if let index = fields.firstIndex(where: { $0.key == key }) { fields[index] = field }
                    else { fields.append(field) }
                }
            }
        }
        self.fields = fields
        pending = required
        signature = String(decoding: try JSONEncoder().encode(confirmed.union(required).sorted()), as: UTF8.self)
    }

    var needsPrompt: Bool {
        !pending.isEmpty
    }

    var prompt: [String: Any] {
        var controls: [[String: Any]] = []
        for field in fields {
            let values = field.step.values
            if let description = values["description"], !description.isEmpty {
                controls.append(["kind": "label", "label": description])
            }
            let value = ActionConfigurationField(field.step).textValue(configuredValues: action.configuredValues)
            var control: [String: Any] = ["key": field.key, "label": values["name"] ?? field.key,
                "kind": field.type == "boolean" ? "switch" : field.type == "text" ? "textView" : field.type == "number" ? "number" : "text",
                "value": field.type == "boolean" ? ActionStepValueRules.configurationBooleanValue(value) : value,
                "placeholder": values["exampleValue"] ?? ""]
            if field.type == "number" { control["allowDecimals"] = true }
            controls.append(control)
        }
        return ["title": "Configure " + action.name, "message": "Configure this action before its first run.",
            "isCancellable": true, "buttons": [["title": "Configure", "isDefault": true]], "fields": controls]
    }

    func configured(_ response: Any?) throws -> DraftAction {
        guard let result = response as? [String: Any], let index = result["index"] as? Int, index == 0 else {
            throw ActionExecutionInterruption.cancelled
        }
        guard let values = result["fields"] as? [String: Any] else {
            throw DraftlyError.message("The configuration response has no fields.")
        }
        var copy = action
        for field in fields {
            guard let value = values[field.key] else {
                throw DraftlyError.message("The configuration response is missing: " + field.key)
            }
            let text: String
            switch field.type {
            case "boolean":
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    throw DraftlyError.message("The configured value must be a boolean: " + field.key)
                }
                text = number.boolValue ? "true" : "false"
            case "number":
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
                    throw DraftlyError.message("The configured value must be a finite number: " + field.key)
                }
                text = number.stringValue
            default:
                guard let string = value as? String else {
                    throw DraftlyError.message("The configured value must be text: " + field.key)
                }
                text = string
            }
            copy.configuredValues[field.key] = text
        }
        var metadata = copy.scriptMetadata ?? [:]
        metadata[Self.confirmationKey] = signature
        copy.scriptMetadata = metadata
        return copy
    }
}
