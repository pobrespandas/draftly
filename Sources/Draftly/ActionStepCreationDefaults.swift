@_spi(ActionEditing) import DraftlyCore

// Creation defaults do not fill missing fields in imported steps.
enum ActionStepCreationDefaults {
    static func values(for type: String) -> [String: String] {
        switch type {
        case "script": ["script": "// Write JavaScript here.\n", "allowAsync": "false"]
        case "runAppleScript": ["source": "return \"Hello\""]
        case "url", "callbackUrl": ["url": "https://example.com"]
        case "runShortcut", "includeAction": ["name": "", "template": "[[draft]]"]
        case "file": ["name": "[[safe_title]].md", "template": "[[draft]]"]
        case "createDraft": ["template": "[[draft]]", "openInEditor": "true"]
        case "prompt": ActionStepValueRules.promptDefaults
        case "configurationKey": ["key": "", "dataType": "string", "defaultStringValue": "",
                                  "description": "", "exampleValue": "", "requiresInitialConfiguration": "true"]
        default: ["template": "[[draft]]"]
        }
    }
}
