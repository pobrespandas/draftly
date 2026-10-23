import Foundation
@_spi(ActionEditing) import DraftlyCore

enum ActionStepInspectorFields {
    enum Control: Equatable {
        case text
        case toggle(defaultValue: Bool, acceptsOne: Bool)
        case choice([String])
        case number
    }

    struct Field: Identifiable, Equatable {
        let key: String
        let isMultiline: Bool
        let minHeight: CGFloat?
        var control: Control = .text
        var allowsTagInsertion: Bool { isMultiline }
        var id: String { key }
    }

    static func textValue(for key: String, in step: ActionStep) -> String {
        if step.type == "prompt" { return ActionStepValueRules.promptTextValue(for: key, in: step.values) }
        return step.values[key] ?? defaults(for: step)[key] ?? ""
    }

    static func title(for key: String, in step: ActionStep) -> String {
        if isShadowedAlias(key, in: step) { return "Inactive Imported Alias: " + key }
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
        let titles = ["allowAsync": "Allow Asynchronous Script", "allowAsynchronous": "Allow Asynchronous Script",
            "encodeTags": "Encode Tags", "waitForResponse": "Wait for Response", "writeType": "Write Mode",
            "template": "Template", "text": "Text", "script": "Script", "source": "Source",
            "folder": "Folder", "location": "Folder", "tags": "Tags", "assignTags": "Tags",
            "syntax": "Syntax", "assignSyntax": "Syntax", "syntaxName": "Syntax", "grammarName": "Syntax", "grammarType": "Syntax",
            "flagged": "Flag New Draft", "flagType": "Flag Color", "fileNameTemplate": "File Name", "name": "Name",
            "folderTemplate": "Folder Template", "useBookmark": "Use Bookmark", "bookmarkName": "Bookmark Name",
            "hideInterface": "Hide Preview Interface", "tagName": "Tag Name", "listTemplate": "List", "list": "List",
            "toRecipients": "To", "ccRecipients": "CC", "bccRecipients": "BCC", "replyToRecipients": "Reply-To",
            "subject": "Subject", "isBodyHTML": "HTML Body", "sendInBackground": "Send in Background",
            "format": "Print Format", "printFormat": "Print Format", "topMargin": "Top Margin", "bottomMargin": "Bottom Margin",
            "leftMargin": "Left Margin", "rightMargin": "Right Margin", "autoStart": "Start Automatically", "autoClose": "Close Automatically"]
        return titles[key] ?? key
    }

    // Pick the stored alias that the executor reads first. Do not add a shadow key.
    private static func key(_ aliases: [String], in step: ActionStep) -> String {
        aliases.first { step.values[$0] != nil } ?? aliases[0]
    }

    static func isShadowedAlias(_ candidate: String, in step: ActionStep) -> Bool {
        var groups = [["template", "text"]]
        switch step.type {
        case "script": groups += [["script", "source"], ["allowAsync", "allowAsynchronous"]]
        case "runAppleScript": groups += [["script", "source"]]
        case "createDraft": groups += [["folder", "location"], ["tags", "assignTags"], ["syntax", "assignSyntax", "syntaxName", "grammarName", "grammarType"]]
        case "file": groups += [["fileNameTemplate", "name"]]
        case "print": groups += [["format", "printFormat"]]
        case "defineTemplateTag": groups += [["name", "tagName"]]
        case "listInReminders": groups += [["list", "listTemplate"]]
        default: break
        }
        guard let group = groups.first(where: { $0.contains(candidate) }) else { return false }
        let active: String
        if step.type == "createDraft", group.contains("syntax") {
            active = group.first { !(step.values[$0] ?? "").isEmpty } ?? key(group, in: step)
        } else { active = key(group, in: step) }
        return candidate != active
    }

    static func defaults(for step: ActionStep) -> [String: String] {
        let content = key(["template", "text"], in: step)
        var values: [String: String] = [:]
        switch step.type {
        case "script":
            values[key(["script", "source"], in: step)] = ""
            values[key(["allowAsync", "allowAsynchronous"], in: step)] = "false"
        case "runAppleScript": values[key(["script", "source"], in: step)] = ""
        case "configurationKey", "configureWindow", "includeAction", "prompt": break
        default:
            if DraftAction.supportedSteps.contains(step.type) { values[content] = "[[draft]]" }
        }
        switch step.type {
        case "clipboard": values["writeType"] = "replace"
        case "url", "callbackUrl":
            // A missing URL uses the common unrendered content, not a blank URL.
            values["url"] = step.values["template"] ?? step.values["text"] ?? "[[draft]]"
            values["encodeTags"] = "true"
            if step.type == "callbackUrl" { values["waitForResponse"] = "true" }
        case "createDraft":
            values[key(["folder", "location"], in: step)] = "inbox"
            values[key(["tags", "assignTags"], in: step)] = ""
            let syntaxKeys = ["syntax", "assignSyntax", "syntaxName", "grammarName", "grammarType"]
            let syntaxKey = syntaxKeys.first { !(step.values[$0] ?? "").isEmpty } ?? key(syntaxKeys, in: step)
            values[syntaxKey] = "Markdown"
            values["flagged"] = "false"; values["flagType"] = ""
        case "file":
            values[key(["fileNameTemplate", "name"], in: step)] = "[[safe_title]].md"
            values["folderTemplate"] = ""; values["useBookmark"] = "false"
            values["bookmarkName"] = ""; values["writeType"] = "create"
        case "export", "openIn": values["name"] = "[[safe_title]].txt"
        case "runShortcut": values["name"] = ""; values["waitForResponse"] = "true"
        case "htmlpreview": values["hideInterface"] = "false"
        case "defineTemplateTag": values[key(["name", "tagName"], in: step)] = ""
        case "mail", "message":
            for name in ["subject", "toRecipients"] { values[name] = "" }
            if step.type == "mail" {
                for name in ["ccRecipients", "bccRecipients", "replyToRecipients"] { values[name] = "" }
                values["isBodyHTML"] = "false"; values["sendInBackground"] = "false"
            }
        case "listInReminders": values[key(["list", "listTemplate"], in: step)] = "Reminders"
        case "print":
            values[key(["format", "printFormat"], in: step)] = "Text"
            for name in ["topMargin", "bottomMargin", "leftMargin", "rightMargin"] { values[name] = "72" }
        case "speak": values["autoStart"] = "true"; values["autoClose"] = "true"
        default: break
        }
        return values
    }

    static func toggleValue(for field: Field, in step: ActionStep) -> Bool {
        guard case .toggle(let defaultValue, let acceptsOne) = field.control else { return false }
        let raw = step.values[field.key]
        if defaultValue { return raw != "false" }
        return raw == "true" || (acceptsOne && raw == "1")
    }

    static func setText(_ text: String, for key: String, in step: inout ActionStep) {
        step.values[key] = text
    }

    static func appendTag(_ tag: String, for key: String, in step: inout ActionStep) {
        step.values[key] = textValue(for: key, in: step) + "[[" + tag + "]]"
    }

    static func limitation(for step: ActionStep) -> String? {
        var messages: [String] = []
        switch step.type {
        case "mail", "message": messages.append("Confirmed message delivery is unavailable through the current macOS service.")
        case "reminder", "event": messages.append("This step uses the content template. Separate imported title, notes and list options are retained but are not applied.")
        case "runShortcut": messages.append("The imported Return to Drafts option is retained but is not applied.")
        case "listInReminders": messages.append("Imported note delimiters and first-line list overrides are retained but are not applied.")
        case "file":
            if ["local", "tagsTemplate", "setDateAttributes"].contains(where: { step.values[$0] != nil }) {
                messages.append("Imported local, tags and date options are retained but are not applied.")
            }
        default: break
        }
        if step.values["platforms"] != nil || step.unknownFields["platforms"] != nil {
            messages.append("Imported platform data is retained. Platform filtering is not applied by the current runtime.")
        }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private static func control(for key: String, in step: ActionStep) -> Control {
        if isShadowedAlias(key, in: step) { return .text }
        switch (step.type, key) {
        case ("script", "allowAsync"), ("script", "allowAsynchronous"), ("createDraft", "flagged"):
            return .toggle(defaultValue: false, acceptsOne: true)
        case ("file", "useBookmark"), ("htmlpreview", "hideInterface"), ("mail", "isBodyHTML"), ("mail", "sendInBackground"):
            return .toggle(defaultValue: false, acceptsOne: false)
        case ("url", "encodeTags"), ("callbackUrl", "encodeTags"), ("callbackUrl", "waitForResponse"),
             ("runShortcut", "waitForResponse"), ("speak", "autoStart"), ("speak", "autoClose"):
            return .toggle(defaultValue: true, acceptsOne: false)
        case ("clipboard", "writeType"): return .choice(["replace", "append", "prepend"])
        case ("file", "writeType"): return .choice(["create", "replace", "append", "prepend"])
        case ("createDraft", "folder"), ("createDraft", "location"): return .choice(["inbox", "archive"])
        case ("createDraft", "flagType"): return .choice([""] + (0...7).map(String.init))
        case ("print", "format"), ("print", "printFormat"): return .choice(["Text", "HTML"])
        case ("print", "topMargin"), ("print", "bottomMargin"), ("print", "leftMargin"), ("print", "rightMargin"): return .number
        default: return .text
        }
    }

    static let configurationTypes = ActionStepValueRules.configurationTypes
    static func configurationDefaultKey(for type: String) -> String? {
        ActionStepValueRules.configurationDefaultKey(for: type)
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
        var keys = Set(step.values.keys).union(defaults(for: step).keys)
        if step.type == "prompt" { keys.formUnion(ActionStepValueRules.promptDefaults.keys) }
        if step.type == "configureWindow" { keys.formUnion(WindowConfigurationOptions.referenceKeys) }
        if step.type == "includeAction" {
            excludedKeys.remove("uuid")
            keys.formUnion(["uuid", "name"])
        }
        return keys.filter { !excludedKeys.contains($0) }.sorted().map { key in
            let isMultiline = ["template", "text", "script", "source"].contains(key) || (step.type == "prompt" && key == "message")
            return Field(key: key, isMultiline: isMultiline,
                         minHeight: isMultiline ? (key == "message" ? 100 : ["template", "text"].contains(key) ? 180 : 360) : nil,
                         control: control(for: key, in: step))
        }
    }
}
