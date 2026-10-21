import AppKit
import DraftlyCore

@MainActor
struct WindowActionAdapter {
    unowned let model: WindowModel

    func perform(_ values: [String: Any]) throws -> Any? {
        let operation = values["operation"] as? String ?? "", key = values["key"] as? String ?? ""
        let value = values["value"], args = values["args"] as? [Any] ?? []
        if operation == "get" {
            switch key {
            case "isActionListVisible": return model.showActions
            case "isDraftListVisible": return model.showDraftList
            case "areFiltersVisible": return model.showFilters
            case "floatOnTop": return model.isFloating
            case "canCreateTab": return model.window != nil
            case "linkModeEnabled": return model.linksEnabled
            case "pinningEnabled", "focusModeEnabled": return model.isDraftPinned
            case "isActive": return model.window?.firstResponder is DraftTextView
            case "preferredTabString": return EditorIndentationPreferences.text(for: model.currentNote?.syntax ?? "Markdown", defaults: model.dependencies.preferences.defaults)
            case "typewriterScrollingEnabled": return model.editor.typewriterScrollingEnabled
            case "isIdleDisabled": return model.isIdleDisabled
            case "themeMode": return model.darkTheme.map { $0 ? "dark" : "light" } ?? "automatic"
            case "currentThemeMode": return (model.window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) ? "dark" : "light"
            case "darkTheme", "lightTheme": return model.configuredThemeReference(dark: key == "darkTheme")
            case "isChatConsoleVisible": return false
            default: throw DraftlyError.message("The window property \(key) is unavailable.")
            }
        }
        if operation == "set" {
            let enabled = value as? Bool ?? false
            switch key {
            case "floatOnTop": model.isFloating = enabled
            case "linkModeEnabled": model.linksEnabled = enabled
            case "pinningEnabled", "focusModeEnabled": model.isDraftPinned = enabled
            case "typewriterScrollingEnabled": model.editor.typewriterScrollingEnabled = enabled
            case "themeMode": model.darkTheme = value as? String == "automatic" ? nil : value as? String == "dark"
            case "isIdleDisabled": model.setIdleDisabled(enabled)
            case "darkTheme", "lightTheme":
                guard let theme = value as? [String: Any] else { throw DraftlyError.message("The theme is unavailable.") }
                try model.setConfiguredThemeReference(theme, dark: key == "darkTheme")
            default: throw DraftlyError.message("The window property \(key) cannot be assigned.")
            }
            return true
        }
        switch operation {
        case "themes":
            return ThemeCatalog.values(in: model.library)
        case "configureWindow":
            let options = values["values"] as? [String: String] ?? [:]
            let toggles = ["showDraftList", "showActionList", "showFilters", "showActionBar", "showTagEntry", "pinCurrentDraft", "linkMode"]
            let metadata = ["data", "parameters", "values", "uuid", "platforms", "isEnabled", "template", "templateType"]
            let supported = Set(toggles + metadata + ["loadWorkspace", "loadActionGroup", "loadActionBarGroup"])
            if let unsupported = options.keys.sorted().first(where: { !supported.contains($0) && options[$0] != "" && options[$0] != "unchanged" }) { throw DraftlyError.message("The window option \(unsupported) is not supported.") }
            var settings: [String: Bool] = [:]
            for key in toggles {
                guard let value = options[key], value != "unchanged" else { continue }
                guard ["true", "false", "1", "0", "show", "hide"].contains(value) else { throw DraftlyError.message("The window option \(key) is invalid.") }
                settings[key] = ["true", "1", "show"].contains(value)
            }
            let workspace: Workspace?
            if let name = options["loadWorkspace"], !name.isEmpty {
                guard let found = model.library.workspaces.first(where: { $0.name == name || $0.id.uuidString == name }) else { throw DraftlyError.message("The workspace was not found.") }
                workspace = found
            } else { workspace = nil }
            for key in ["loadActionGroup", "loadActionBarGroup"] {
                if let name = options[key], !name.isEmpty, !model.library.groupNames.contains(name) { throw DraftlyError.message("The action group was not found.") }
            }
            if let workspace { try model.applyScriptWorkspace(workspace) }
            if let enabled = settings["showDraftList"] { model.setDraftListVisible(enabled) }
            if let enabled = settings["showFilters"] { model.setFiltersVisible(enabled) }
            if let enabled = settings["showActionList"] { model.showActions = enabled }
            if let enabled = settings["showActionBar"] { model.showActionBar = enabled }
            if let enabled = settings["showTagEntry"] { model.showTags = enabled }
            if let enabled = settings["pinCurrentDraft"] { model.isDraftPinned = enabled }
            if let enabled = settings["linkMode"] { model.linksEnabled = enabled }
            if let name = options["loadActionGroup"], !name.isEmpty { model.actionGroup = name }
            if let name = options["loadActionBarGroup"], !name.isEmpty { model.actionBarGroup = name }
        case "showActionList": model.showActions = true
        case "hideActionList": model.showActions = false
        case "showDraftList": model.setDraftListVisible(true)
        case "hideDraftList": model.setDraftListVisible(false)
        case "showFilters": model.setFiltersVisible(true)
        case "hideFilters": model.setFiltersVisible(false)
        case "showDraftInfo":
            if let details = value as? [String: Any] {
                guard let id = (details["uuid"] as? String).flatMap(UUID.init(uuidString:)), let note = model.library.notes.first(where: { $0.id == id }) else { throw DraftlyError.message("The draft was not found.") }
                model.infoDraft = note
            } else { model.infoDraft = model.currentNote }
            model.showInfo = true
        case "showQuickSearch": model.openQuickSearch(value as? String ?? "")
        case "showCommandPalette": model.openCommandPalette(initialQuery: value as? String ?? "")
        case "loadActionBarGroup", "loadKeyboardActionGroup", "loadActionGroup":
            let reference = value as? [String: Any] ?? ["name": value as? String ?? ""]
            let resolved = try ActionGroupReferenceResolver.resolve(reference, names: model.library.groupNames,
                groups: model.library.actionGroups)
            guard let name = resolved["name"] as? String else { throw DraftlyError.message("The action group was not found.") }
            if operation == "loadActionGroup" { model.actionGroup = name; model.showActions = true } else { model.actionBarGroup = name }
        case "nextDraft": model.navigate(1)
        case "previousDraft": model.navigate(-1)
        case "activate":
            model.showPreview = false
            _ = model.editor.focusForDictation?()
        case "deactivate":
            if model.window?.firstResponder is DraftTextView { model.window?.makeFirstResponder(nil) }
        case "undo", "redo":
            guard let performUndo = model.editor.performUndo else { throw DraftlyError.message("The editor undo manager is unavailable.") }; performUndo(operation == "redo")
        case "showFind":
            if (args.first as? Bool ?? model.prefersAdvancedFind()) {
                model.advancedFindQuery = args.dropFirst().first as? String ?? ""
                model.showAdvancedFind = true
                return nil
            }
            model.showAdvancedFind = false
            if let query = args.dropFirst().first as? String { NSPasteboard(name: .find).clearContents(); NSPasteboard(name: .find).setString(query, forType: .string) }
            let item = NSMenuItem(); item.tag = NSTextFinder.Action.showFindInterface.rawValue
            NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
        case "showDictate": try model.showDictation()
        case "arrange": return try model.host.perform("arrangeText", values: ["text": args.first as? String ?? ""])
        case "showArrange": try model.showArrangement()
        case "dictate": return try model.host.perform("dictate", values: ["locale": args.first as? String ?? ""])
        case "scanDocument": return try model.host.perform("scanDocument", values: [:])
        case "transcribe": return try model.host.perform("transcribe", values: [:])
        case "openInNewWindow", "openInNewTab":
            let details = values["draft"] as? [String: Any] ?? value as? [String: Any] ?? [:]
            model.dependencies.openDraftWindow((details["uuid"] as? String).flatMap(UUID.init(uuidString:)), operation == "openInNewTab", model.window)
        case "hideChatConsole", "showChatConsole": throw DraftlyError.message("Chat Console is outside the Draftly Mac scope.")
        default: throw DraftlyError.message("The window operation \(operation) is unavailable.")
        }
        return true
    }
}
