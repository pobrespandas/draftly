import Foundation

struct ActionConfigurationField {
    private let values: [String: String]

    init(_ step: ActionStep) {
        values = step.values
    }

    var key: String { values["key"] ?? "" }
    var dataType: String { values["dataType"] ?? "string" }

    func textValue(configuredValues: [String: String]) -> String {
        let defaultKey: String
        switch dataType {
        case "boolean": defaultKey = "defaultBoolValue"
        case "number": defaultKey = "defaultNumberValue"
        case "text": defaultKey = "defaultTextValue"
        default: defaultKey = "defaultStringValue"
        }
        return configuredValues[key] ?? values["defaultValue"] ?? values[defaultKey] ?? ""
    }
}
