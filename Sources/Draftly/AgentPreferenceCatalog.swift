import Foundation
import AgentContracts
import DraftlyCore

// Trusted metadata only. Storage and native effects belong to command handlers.
@MainActor enum AgentPreferenceCatalog {
    static func make() throws -> AgentPreferenceRegistry {
        var fields: [AgentPreferenceField] = []
        func literal(_ id: String, _ title: String, _ shape: AgentValueShape,
                     _ value: AgentJSONValue, context: AgentPreferenceField.Context = .device,
                     writable: Bool = true, approval: Bool = false) {
            fields.append(.init(id: id, title: title, context: context, value: shape,
                defaultSource: .literal, defaultValue: value, writable: writable,
                requiresHumanApproval: approval))
        }
        func inherited(_ id: String, _ shape: AgentValueShape) {
            fields.append(.init(id: id, title: id, context: .syntax, value: shape,
                defaultSource: .inherited))
        }
        literal(ApplicationAppearance.preferenceKey, "Appearance",
            .string(choices: ApplicationAppearance.allCases.map(\.rawValue)),
            .string(ApplicationAppearance.resolved("").rawValue))
        for (key, title, value) in [
            (GeneralPreferences.showInMenuBarKey, "Show in menu bar", GeneralPreferences.defaultMenuBarVisibility),
            (GeneralPreferences.showMainWindowAtLaunchKey, "Show main window at launch", GeneralPreferences.defaultMainWindowVisibility),
            (GeneralPreferences.advancedFindKey, "Prefer advanced find", GeneralPreferences.defaultAdvancedFind),
            (GeneralPreferences.showCustomTouchBarKey, "Custom Touch Bar", GeneralPreferences.defaultTouchBar)
        ] { literal(key, title, .boolean, .bool(value)) }
        literal(ActionMoveNavigation.preferenceKey, "After moving a draft",
            .string(choices: ActionMoveNavigation.allCases.map(\.rawValue)),
            .string(ActionMoveNavigation.resolved(nil).rawValue))
        literal("capture.newDraftAfter", "New draft interval", .number(minimum: 0), .number(Decimal(CaptureDefaults.newDraftAfter)))
        fields.append(.init(id: "application.launchAtLogin", title: "Launch at login", context: .device,
            value: .boolean, defaultSource: .system, requiresHumanApproval: true))
        literal(SpotlightPreferences.enabledKey, "Index drafts in Spotlight", .boolean,
            .bool(SpotlightPreferences.defaultEnabled), approval: true)
        for (id, value) in [("fontName", EditorPreferenceDefaults.fontName),
                            ("monospaceFontName", EditorPreferenceDefaults.monospaceFontName)] {
            literal("editor." + id, id, .string(), .string(value))
            inherited("syntax." + id, .string())
        }
        literal("editor.fontSize", "Font size", .number(exclusiveMinimum: 0), .number(Decimal(EditorPreferenceDefaults.fontSize)))
        inherited("syntax.fontSize", .number(exclusiveMinimum: 0))
        literal("editor.lineSpacing", "Legacy line spacing", .number(), .number(Decimal(EditorPreferenceDefaults.lineSpacing)), writable: false)
        let layout = EditorSyntaxLayoutPreferences.Layout(
            lineHeightMultiple: EditorPreferenceDefaults.lineHeightMultiple,
            paragraphSpacing: EditorPreferenceDefaults.paragraphSpacing,
            horizontalMargin: EditorTextLayout.horizontalMargin, verticalMargin: EditorTextLayout.verticalMargin,
            maximumWidth: EditorPreferenceDefaults.maximumWidth)
        for field in EditorSyntaxLayoutPreferences.Field.allCases {
            literal("editor." + field.rawValue, field.rawValue, .number(minimum: 0), .number(Decimal(layout[field])))
            inherited("syntax." + field.rawValue, .number(minimum: 0))
        }
        for (id, value) in [("typewriter", EditorPreferenceDefaults.typewriter),
                            ("highlightInsertionPoint", EditorPreferenceDefaults.highlightInsertionPoint),
                            ("focusOnListSelection", EditorPreferenceDefaults.focusOnListSelection)] {
            literal("editor." + id, id, .boolean, .bool(value))
        }
        literal("editor.cursorOnListSelection", "Cursor on list selection", .string(choices: ["last", "top", "bottom"]),
            .string(EditorPreferenceDefaults.cursorOnListSelection))
        for option in EditorTextInputPreferences.Option.allCases {
            literal("syntax." + option.rawValue, option.title, .boolean, .bool(option.defaultValue), context: .syntax)
        }
        for option in EditorTextInputPreferences.SystemOption.allCases {
            fields.append(.init(id: "syntax." + option.rawValue, title: option.title, context: .syntax,
                value: .nullable(.boolean), defaultSource: .system))
        }
        literal("syntax.paragraphNumbers", "Paragraph numbers", .boolean,
            .bool(EditorSyntaxDisplayPreferences.value(.paragraphNumbers, for: "", encoded: "{}")), context: .syntax)
        inherited("syntax.highlightInsertionPoint", .boolean)
        literal("syntax.indentation", "Indentation", .string(choices: EditorIndentationStyle.allCases.map(\.rawValue)),
            .string(EditorIndentationPreferences.style(for: "", encoded: "{}").rawValue), context: .syntax)
        fields.append(.init(id: "syntax.feature", title: "Syntax feature", context: .syntaxFeature,
            value: .boolean, defaultSource: .contextual))
        literal(MarkdownPreferences.engineKey, "Markdown processor", .string(choices: ["multi", "github"]),
            .string(MarkdownPreferences.defaultEngine))
        for (engine, options) in [("multi", MarkdownPreferences.multiOptions), ("github", MarkdownPreferences.githubOptions)] {
            for option in options {
                literal("markdown." + engine + "." + option.id, option.title, .boolean, .bool(option.defaultValue))
            }
        }
        for (id, choices) in [("strongMark", HTMLPreferences.strongMarks), ("emphasisMark", HTMLPreferences.emphasisMarks),
                              ("ulItemMark", HTMLPreferences.listMarks)] {
            literal("html." + id, id, .string(choices: choices), .string(choices[0]))
        }
        for id in HTMLPreferences.booleanDefaults.keys.sorted() {
            literal(id, id, .boolean, .bool(HTMLPreferences.booleanDefaults[id]!))
        }
        let list = DraftListOptions()
        for (id, value) in [("showPreview", list.showPreview), ("showTags", list.showTags), ("showDate", list.showDate),
                            ("searchTitlesOnly", list.searchTitlesOnly), ("caseSensitiveSearch", list.caseSensitiveSearch),
                            ("previewSearchMatches", list.previewSearchMatches), ("showLastAction", list.showLastAction),
                            ("highlightFlagged", list.highlightFlagged)] {
            literal("list." + id, id, .boolean, .bool(value))
        }
        literal("list.previewLines", "Preview lines", .integer(), .integer(Int64(list.previewLines)))
        literal(WorkspaceDefaults.key, "Default Workspace", .nullable(.uuid), .null)
        let binding = AgentObjectShape(fields: [
            "key": .init(shape: .string(), required: true),
            "modifiers": .init(shape: .array(.string(choices: ["command", "option", "control", "shift"]), maximum: 4), required: true),
            "keyCode": .init(shape: .integer(minimum: 0, maximum: Int64(UInt32.max)))
        ])
        fields.append(.init(id: "commands.shortcut", title: "Command shortcut", context: .command(CommandShortcuts.editable),
            value: .object(binding), defaultSource: .contextual, approvalCommands: Set(GlobalShortcuts.names)))
        return try AgentPreferenceRegistry(fields: fields, builtInSyntaxNames: ScriptSyntax.names)
    }
}
