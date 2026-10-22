// The app uses this SPI to display execution values without changing imports.
@_spi(ActionEditing)
public enum ActionStepValueRules {
    public static let promptDefaults = ["key": "prompt", "title": "Prompt", "message": "", "buttons": "OK",
        "includeTextField": "false", "textFieldDefault": "", "includeCancelButton": "true"]

    public static func promptTextValue(for key: String, in values: [String: String]) -> String {
        values[key] ?? promptDefaults[key] ?? ""
    }

    public static func promptIncludesTextField(_ values: [String: String]) -> Bool {
        configurationBooleanValue(values["includeTextField"])
    }

    public static func promptIncludesCancelButton(_ values: [String: String]) -> Bool {
        values["includeCancelButton"] != "false"
    }

    public static func createdDraftOpensInEditor(_ values: [String: String]) -> Bool {
        values["openInEditor"] != "false"
    }

    public static func requiresInitialConfiguration(_ values: [String: String]) -> Bool {
        configurationBooleanValue(values["requiresInitialConfiguration"])
    }

    public static func configurationBooleanValue(_ value: String?) -> Bool {
        value == "true" || value == "1"
    }

    public static let configurationTypes = ["string", "text", "boolean", "number"]

    public static func configurationDefaultKey(for type: String) -> String? {
        switch type {
        case "string": "defaultStringValue"
        case "text": "defaultTextValue"
        case "boolean": "defaultBoolValue"
        case "number": "defaultNumberValue"
        default: nil
        }
    }
}
