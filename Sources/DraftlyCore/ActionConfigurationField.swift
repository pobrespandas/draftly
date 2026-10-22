import Foundation

struct ActionConfigurationField {
    private let values: [String: String]

    init(_ step: ActionStep) {
        values = step.values
    }

    var key: String { values["key"] ?? "" }
    var dataType: String { values["dataType"] ?? "string" }

    func textValue(configuredValues: [String: String]) -> String {
        let defaultKey = ActionStepValueRules.configurationDefaultKey(for: dataType) ?? "defaultStringValue"
        return configuredValues[key] ?? values["defaultValue"] ?? values[defaultKey] ?? ""
    }
}
