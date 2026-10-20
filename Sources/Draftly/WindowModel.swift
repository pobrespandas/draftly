import SwiftUI
import AppKit
import DraftlyCore

@MainActor
final class WindowModel: ObservableObject {
    let library: LibraryStore
    let editor = EditorSession()
    let host = NativeActionHost()
    let runner: ActionRunner
    @Published var folder: NoteFolder = .inbox {
        didSet {
            guard oldValue != folder, let metadata = workspaceScriptMetadata else { return }
            var workspace = Workspace(name: "Current"); workspace.scriptMetadata = metadata
            if let (newSort, newAscending, _) = workspace.scriptSort(for: folder) { sort = newSort; ascending = newAscending }
        }
    }
    @Published var mergeRequest: MergeRequest?
    @Published var query = ""
    @Published var selectedTags: Set<String> = []
    @Published var excludedTags: Set<String> = []
    @Published var matchAnyTag = false
    @Published var multipleTagMode = false
    @Published var tagQuery = ""
    var tag: String? {
        get { selectedTags.count == 1 ? selectedTags.first : nil }
        set { selectedTags = Set(newValue.map { [$0] } ?? []) }
    }
    @Published var tagPresence: Bool?
    @Published var selectedWorkspace: UUID?
    @Published var sort: NoteSort = .modified { didSet { updateWorkspaceSort() } }
    @Published var ascending = false { didSet { updateWorkspaceSort() } }
    private(set) var dictationActive = false
    var recoverDictation: (String) -> Void = { AppController.shared.capture(content: $0) }
    @Published var showActionBar = true
    @Published var showActions = false
    @Published var darkTheme: Bool?
    @Published var showTags = true
    var prefersAdvancedFind: () -> Bool = {
        UserDefaults.standard.bool(forKey: GeneralPreferences.advancedFindKey)
    }
    @Published var showAdvancedFind = false
    @Published var advancedFindQuery = ""
    @Published var showInfo = false
    @Published var infoDraft: Note?
    @Published var historyDraftID: UUID?
    @Published var linksEnabled = false
    @Published var isFloating = false
    @Published var isDraftPinned = false
    @Published var actionBarGroup = "Editing"
    @Published var noteSearchFocus = UUID()
    @Published var actionSearchFocus = UUID()
    @Published private(set) var lastNoteID: UUID?
    enum LeftPanels { case hidden, drafts, filters }
    @Published private(set) var leftPanels: LeftPanels = .filters
    var showFilters: Bool { leftPanels == .filters }
    var showDraftList: Bool { leftPanels != .hidden }
    @Published var showNoteSearch = false
    @Published var showActionSearch = false
    @Published var actionGroup = "General"
    @Published var actionQuery = ""
    @Published var showPalette = false
    @Published var showHistory = false
    @Published var showPreview = false
    @Published var actionPreview: ActionPreviewRequest?
    @Published var previewHTML: String?
    @Published var editingAction: DraftAction?
    @Published var showActionImporter = false
    @Published var showWorkspaceEditor = false
    @Published var showLibraryManagement = false
    @Published var listOptions = DraftListDefaults.load()
    @Published var showRunLog = false
    @Published var status = ""
    @Published var tagsText = ""
    @Published var hasUnsavedChanges = false
    @Published private var scratchNote: Note?
    weak var window: NSWindow?
    var referenceToolbar: ReferenceToolbar?
    var openQuickSearch: () -> Void = { AppController.shared.showQuickSearch() }
    private var saveTask: Task<Void, Never>?
    private let saveDraft: (Note) throws -> Void
    private let onAccessDraft: (UUID) -> Void
    private var inactiveSince: Date?
    private var idleActivity: NSObjectProtocol?

    init(library: LibraryStore, saveDraft: ((Note) throws -> Void)? = nil, onAccessDraft: @escaping (UUID) -> Void = { _ in }) {
        self.library = library
        self.saveDraft = saveDraft ?? { try library.saveNote($0) }
        self.onAccessDraft = onAccessDraft
        runner = ActionRunner(library: library, editor: editor, host: host)
        runner.applyWorkspace = { [weak self] workspace in try self?.applyScriptWorkspace(workspace) }
        runner.defaultWorkspace = { [weak library] in
            guard let library else { return Workspace(name: "") }
            var value = WorkspaceDefaults.make(in: library)
            if UserDefaults.standard.string(forKey: WorkspaceDefaults.key).flatMap(UUID.init(uuidString:)).flatMap({ id in library.workspaces.first { $0.id == id } }) == nil { value.listOptions = DraftListDefaults.load() }
            return value
        }
        runner.currentWorkspace = { [weak self] in
            guard let self else { return Workspace(name: "Current") }
            var result = Workspace(name: "Current"); result.scriptMetadata = self.workspaceScriptMetadata; result.listOptions = self.listOptions; result.folder = self.folder; result.query = self.query
            result.tags = self.activeTagFilters; result.excludedTags = self.excludedTagFilters
            result.listOptions = self.listOptions
            result.matchAnyTag = self.matchAnyTag; result.sort = self.sort; result.ascending = self.ascending
            return result
        }
        runner.uiOperation = { [weak self] values in try self?.actionUIOperation(values) }
        host.models.onTool = { [weak runner] operation, json in
            guard let runner else { throw DraftlyError.message("The action window is closed.") }
            return try runner.performModelTool(operation, json: json)
        }
        host.onActionPreview = { [weak self] request in
            guard let self else { request.finish(false); return }
            let wasVisible = self.showPreview, html = self.previewHTML
            self.actionPreview = request; self.showPreview = true
            request.onFinish = { [weak self] in self?.actionPreview = nil; self?.showPreview = wasVisible; self?.previewHTML = html }
        }
        host.onPreview = { [weak self] html in
            guard let self else { return }
            self.previewHTML = html; self.showPreview = true
            self.window?.makeFirstResponder(nil)
        }
    }
    func setFiltersVisible(_ visible: Bool) {
        if visible { leftPanels = .filters }
        else if showFilters { leftPanels = .drafts }
    }
    func setDraftListVisible(_ visible: Bool) {
        if !visible { leftPanels = .hidden }
        else if !showDraftList { leftPanels = .drafts }
    }
    func toggleFilters() { setFiltersVisible(!showFilters) }
    func toggleDraftList() { setDraftListVisible(!showDraftList) }

    func actionUIOperation(_ values: [String: Any]) throws -> Any? {
        let operation = values["operation"] as? String ?? "", key = values["key"] as? String ?? ""
        let value = values["value"], args = values["args"] as? [Any] ?? []
        if operation == "get" {
            switch key {
            case "isActionListVisible": return showActions
            case "isDraftListVisible": return showDraftList
            case "areFiltersVisible": return showFilters
            case "floatOnTop": return isFloating
            case "canCreateTab": return window != nil
            case "linkModeEnabled": return linksEnabled
            case "pinningEnabled", "focusModeEnabled": return isDraftPinned
            case "isActive": return window?.firstResponder is DraftTextView
            case "preferredTabString": return "\t"
            case "typewriterScrollingEnabled": return editor.typewriterScrollingEnabled
            case "isIdleDisabled": return idleActivity != nil
            case "themeMode": return darkTheme.map { $0 ? "dark" : "light" } ?? "automatic"
            case "currentThemeMode": return (window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) ? "dark" : "light"
            case "darkTheme", "lightTheme": return ["name": key == "darkTheme" ? "Dark" : "Light", "type": "builtIn"]
            case "isChatConsoleVisible": return false
            default: throw DraftlyError.message("The window property \(key) is unavailable.")
            }
        }
        if operation == "set" {
            let enabled = value as? Bool ?? false
            switch key {
            case "floatOnTop": isFloating = enabled
            case "linkModeEnabled": linksEnabled = enabled
            case "pinningEnabled", "focusModeEnabled": isDraftPinned = enabled
            case "typewriterScrollingEnabled": editor.typewriterScrollingEnabled = enabled
            case "themeMode": darkTheme = value as? String == "automatic" ? nil : value as? String == "dark"
            case "isIdleDisabled":
                if enabled && idleActivity == nil { idleActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled], reason: "Draftly action") }
                if !enabled, let idleActivity { ProcessInfo.processInfo.endActivity(idleActivity); self.idleActivity = nil }
            case "darkTheme", "lightTheme":
                guard let theme = value as? [String: Any], ["Default", "Dark", "Light"].contains(theme["name"] as? String ?? "") else { throw DraftlyError.message("The theme is unavailable.") }
            default: throw DraftlyError.message("The window property \(key) cannot be assigned.")
            }
            return true
        }
        switch operation {
        case "themes":
            let data = UserDefaults.standard.string(forKey: "editor.themes") ?? "[]"
            let saved = (try? JSONDecoder().decode([EditorTheme].self, from: Data(data.utf8))) ?? []
            return ["Default", "Dark", "Light"].map { ["name": $0, "type": "builtIn"] } + saved.map { ["name": $0.name, "type": "custom", "uuid": $0.id.uuidString] }
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
                guard let found = library.workspaces.first(where: { $0.name == name || $0.id.uuidString == name }) else { throw DraftlyError.message("The workspace was not found.") }
                workspace = found
            } else { workspace = nil }
            for key in ["loadActionGroup", "loadActionBarGroup"] {
                if let name = options[key], !name.isEmpty, !library.groupNames.contains(name) { throw DraftlyError.message("The action group was not found.") }
            }
            if let workspace { try applyScriptWorkspace(workspace) }
            if let enabled = settings["showDraftList"] { setDraftListVisible(enabled) }
            if let enabled = settings["showFilters"] { setFiltersVisible(enabled) }
            if let enabled = settings["showActionList"] { showActions = enabled }
            if let enabled = settings["showActionBar"] { showActionBar = enabled }
            if let enabled = settings["showTagEntry"] { showTags = enabled }
            if let enabled = settings["pinCurrentDraft"] { isDraftPinned = enabled }
            if let enabled = settings["linkMode"] { linksEnabled = enabled }
            if let name = options["loadActionGroup"], !name.isEmpty { actionGroup = name }
            if let name = options["loadActionBarGroup"], !name.isEmpty { actionBarGroup = name }
        case "showActionList": showActions = true
        case "hideActionList": showActions = false
        case "showDraftList": setDraftListVisible(true)
        case "hideDraftList": setDraftListVisible(false)
        case "showFilters": setFiltersVisible(true)
        case "hideFilters": setFiltersVisible(false)
        case "showDraftInfo":
            if let details = value as? [String: Any] {
                guard let id = (details["uuid"] as? String).flatMap(UUID.init(uuidString:)), let note = library.notes.first(where: { $0.id == id }) else { throw DraftlyError.message("The draft was not found.") }
                infoDraft = note
            } else { infoDraft = currentNote }
            showInfo = true
        case "showQuickSearch": openQuickSearch()
        case "showCommandPalette": showPalette = true
        case "loadActionBarGroup", "loadKeyboardActionGroup", "loadActionGroup":
            let name = (value as? [String: Any])?["name"] as? String ?? value as? String ?? ""
            guard library.groupNames.contains(name) else { throw DraftlyError.message("The action group was not found.") }
            if operation == "loadActionGroup" { actionGroup = name; showActions = true } else { actionBarGroup = name }
        case "nextDraft": navigate(1)
        case "previousDraft": navigate(-1)
        case "activate":
            showPreview = false
            _ = editor.focusForDictation?()
        case "deactivate":
            if window?.firstResponder is DraftTextView { window?.makeFirstResponder(nil) }
        case "undo", "redo":
            guard let performUndo = editor.performUndo else { throw DraftlyError.message("The editor undo manager is unavailable.") }; performUndo(operation == "redo")
        case "showFind":
            if (args.first as? Bool ?? prefersAdvancedFind()) {
                advancedFindQuery = args.dropFirst().first as? String ?? ""
                showAdvancedFind = true
                return nil
            }
            showAdvancedFind = false
            if let query = args.dropFirst().first as? String { NSPasteboard(name: .find).clearContents(); NSPasteboard(name: .find).setString(query, forType: .string) }
            let item = NSMenuItem(); item.tag = NSTextFinder.Action.showFindInterface.rawValue
            NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
        case "showDictate":
            guard !dictationActive else { throw DraftlyError.message("Dictation is already active in this window.") }
            guard editor.focusForDictation != nil else { throw DraftlyError.message("The editor dictation interface is unavailable.") }
            editor.focusToken = UUID(); showPreview = false; dictationActive = true
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    defer { self.dictationActive = false }
                    guard self.editor.focusForDictation?() == true else { self.library.error = "The editor dictation interface is unavailable."; return }
                    let id = self.editor.noteID, content = self.editor.content, selection = self.editor.safeSelection
                    do {
                        guard let text = try self.host.perform("dictate", values: [:]) as? String, !text.isEmpty else { return }
                        if self.editor.noteID == id && self.editor.content == content {
                            try self.editor.replace(selection, with: text)
                            self.editor.synchronizeScriptEdit?(); self.contentChanged(); _ = self.flush()
                        } else { self.recoverDictation(text) }
                    } catch { self.library.error = error.localizedDescription }
                }
            }
        case "arrange": return try host.perform("arrangeText", values: ["text": args.first as? String ?? ""])
        case "showArrange":
            if let text = try host.perform("arrangeText", values: ["text": editor.content]) as? String { editor.content = text; _ = flush() }
        case "dictate": return try host.perform("dictate", values: ["locale": args.first as? String ?? ""])
        case "scanDocument": return try host.perform("scanDocument", values: [:])
        case "transcribe": return try host.perform("transcribe", values: [:])
        case "openInNewWindow", "openInNewTab":
            let details = values["draft"] as? [String: Any] ?? value as? [String: Any] ?? [:]
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            AppController.shared.pendingNoteID = (details["uuid"] as? String).flatMap(UUID.init(uuidString:))
            AppController.shared.openLibrary?()
            if operation == "openInNewTab", let window {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if let created = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) && $0.identifier?.rawValue.hasPrefix("library") == true }) { window.addTabbedWindow(created, ordered: .above) }
                }
            }
        case "hideChatConsole", "showChatConsole": throw DraftlyError.message("Chat Console is outside the Draftly Mac scope.")
        default: throw DraftlyError.message("The window operation \(operation) is unavailable.")
        }
        return true
    }
    var currentNote: Note? { library.notes.first { $0.id == editor.noteID } ?? scratchNote }
    @Published var workspaceScriptMetadata: [String: String]?
    var visibleNotes: [Note] {
        var workspace = Workspace(name: "Current")
        workspace.scriptMetadata = workspaceScriptMetadata
        workspace.listOptions = listOptions
        workspace.folder = folder; workspace.query = query; workspace.tags = activeTagFilters
        workspace.excludedTags = excludedTagFilters
        workspace.matchAnyTag = matchAnyTag
        workspace.tagged = tagPresence
        workspace.sort = sort; workspace.ascending = ascending
        return workspace.filter(library.notes)
    }
    var allTags: [String] { Array(Set(library.notes.flatMap(\.tags).map(TagRules.normalize))).sorted() }
    @Published var showOnlyCurrentTags = false
    var matchingTags: [String] {
        let needle = TagRules.normalize(tagQuery)
        let tags = showOnlyCurrentTags ? Array(Set(visibleNotes.flatMap(\.tags).map(TagRules.normalize))).sorted() : allTags
        return tags.filter { needle.isEmpty || $0.localizedStandardContains(needle) }
    }
    private var notesBeforeTagFilters: [Note] {
        var workspace = Workspace(name: "Counts")
        workspace.listOptions = listOptions
        workspace.folder = folder; workspace.query = query; workspace.tags = []; workspace.tagged = nil
        return workspace.filter(library.notes)
    }
    var taggedCount: Int { notesBeforeTagFilters.filter { !$0.tags.isEmpty }.count }
    var untaggedCount: Int { notesBeforeTagFilters.filter { $0.tags.isEmpty }.count }
    func count(forTag tag: String) -> Int { notesBeforeTagFilters.filter { TagRules.matches(tag, in: $0.tags) }.count }
    var title: String { selectedWorkspace.flatMap { id in library.workspaces.first { $0.id == id }?.name } ?? folder.title }
    func perform(_ work: () throws -> Void) {
        do { try work() } catch { library.error = error.localizedDescription; status = "Changes could not be saved" }
    }
    @discardableResult func create() -> Bool {
        guard flush() else { return false }
        if let id = editor.noteID, library.notes.contains(where: { $0.id == id }) { lastNoteID = id }
        let note = Note()
        scratchNote = note; showPreview = false; previewHTML = nil
        editor.load(note); tagsText = ""; status = ""
        folder = .inbox; clearFilters()
        return true
    }
    func select(_ id: UUID?, focusEditor: Bool = true) {
        guard id != editor.noteID, flush() else { return }
        if let id, library.notes.contains(where: { $0.id == id }) {
            do { try library.recordAccess(id) }
            catch { library.error = error.localizedDescription; return }
        }
        if let current = editor.noteID, library.notes.contains(where: { $0.id == current }) { lastNoteID = current }
        status = ""; previewHTML = nil
        scratchNote = nil
        if let note = library.notes.first(where: { $0.id == id }) {
            editor.load(note, focusEditor: focusEditor); tagsText = note.tags.joined(separator: ", "); onAccessDraft(note.id)
        }
        else { editor.noteID = nil; editor.content = ""; tagsText = "" }
    }
    func contentChanged() {
        guard let currentNote, currentNote.content != editor.content else { return }
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled else { return }; _ = self?.flush()
        }
    }
    @discardableResult func flush() -> Bool {
        saveTask?.cancel()
        do {
            if var note = scratchNote, note.id == editor.noteID {
                note.content = editor.content
                if !note.content.isEmpty || !note.tags.isEmpty || note.flag > 0 {
                    note.accessedAt = Date()
                    try saveDraft(note); scratchNote = nil; onAccessDraft(note.id)
                }
            } else if var note = currentNote, note.content != editor.content {
                note.content = editor.content; try saveDraft(note)
            }
            hasUnsavedChanges = false; return true
        }
        catch { library.error = error.localizedDescription; hasUnsavedChanges = true; return false }
    }
    func saveTags() {
        guard flush(), var note = currentNote else { return }
        note.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        perform { try library.saveNote(note); scratchNote = nil }
    }
    func change(_ ids: Set<UUID>, operation: (inout Note) -> Void) {
        guard flush() else { return }
        perform {
            var notes = library.notes.filter { ids.contains($0.id) }
            if let scratchNote, ids.contains(scratchNote.id), !notes.contains(where: { $0.id == scratchNote.id }) { notes.append(scratchNote) }
            for index in notes.indices { operation(&notes[index]) }
            try library.saveNotes(notes)
            if let scratchNote, ids.contains(scratchNote.id) { self.scratchNote = nil }
        }
    }

    private func updateWorkspaceSort() {
        guard let raw = workspaceScriptMetadata?["api"], let data = raw.data(using: .utf8),
              var values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        var sorts = values["_sorts"] as? [String: [String: Any]] ?? [:]
        var value = sorts[folder.rawValue] ?? [:]
        value["sort"] = sort == .title ? "name" : sort.rawValue; value["descending"] = !ascending
        sorts[folder.rawValue] = value; values["_sorts"] = sorts
        if let encoded = try? JSONSerialization.data(withJSONObject: values) { workspaceScriptMetadata?["api"] = String(decoding: encoded, as: UTF8.self) }
    }

    func applyScriptWorkspace(_ workspace: Workspace) throws {
        var workspace = workspace
        var values = workspace.apiOptions
        for key in ["loadActionListGroup", "loadActionBarGroup"] {
            guard var group = values[key] as? [String: Any] else { continue }
            let name: String?
            if let id = (group["uuid"] as? String).flatMap(UUID.init(uuidString:)) {
                name = library.groupNames.first { candidate in (library.actionGroups.first { $0.name == candidate }?.id ?? ActionGroupRecord.identifier(for: candidate)) == id }
            } else { name = (group["name"] as? String).flatMap { library.groupNames.contains($0) ? $0 : nil } }
            guard let name else { throw DraftlyError.message("The workspace action group was not found.") }
            group["name"] = name; values[key] = group
        }
        let data = UserDefaults.standard.string(forKey: "editor.themes") ?? "[]"
        let themes = (try? JSONDecoder().decode([EditorTheme].self, from: Data(data.utf8))) ?? []
        for key in ["preferredDarkTheme", "preferredLightTheme"] {
            guard var theme = values[key] as? [String: Any] else { continue }
            if theme["type"] as? String == "custom" {
                let saved: EditorTheme?
                if let id = (theme["uuid"] as? String).flatMap(UUID.init(uuidString:)) { saved = themes.first { $0.id == id } }
                else { saved = themes.first { $0.name == theme["name"] as? String } }
                guard let saved else { throw DraftlyError.message("The workspace theme was not found.") }
                theme["name"] = saved.name; theme["uuid"] = saved.id.uuidString
            } else {
                guard ["Default", "Dark", "Light"].contains(theme["name"] as? String ?? "") else { throw DraftlyError.message("The workspace theme was not found.") }
            }
            values[key] = theme
        }
        if workspace.scriptMetadata != nil { workspace.scriptMetadata?["api"] = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self) }
        applyResolvedWorkspace(workspace)
    }

    func apply(_ workspace: Workspace) { perform { try applyScriptWorkspace(workspace) } }
    private func applyResolvedWorkspace(_ workspace: Workspace) {
        workspaceScriptMetadata = workspace.scriptMetadata
        listOptions = workspace.listOptions ?? DraftListDefaults.load()
        folder = workspace.folder; query = workspace.query; sort = workspace.sort; ascending = workspace.ascending
        selectedWorkspace = library.workspaces.contains(where: { $0.id == workspace.id }) ? workspace.id : nil
        selectedTags = Set(workspace.tags.map(TagRules.normalize))
        excludedTags = Set((workspace.excludedTags ?? []).map(TagRules.normalize))
        matchAnyTag = workspace.matchAnyTag ?? false
        if selectedTags.count > 1 || !excludedTags.isEmpty { multipleTagMode = true }
        tagPresence = workspace.tagged
        showNoteSearch = !workspace.query.isEmpty
        let values = workspace.apiOptions
        if let name = (values["loadActionListGroup"] as? [String: Any])?["name"] as? String, library.groupNames.contains(name) { actionGroup = name }
        if let name = (values["loadActionBarGroup"] as? [String: Any])?["name"] as? String, library.groupNames.contains(name) { actionBarGroup = name }

    }
    func run(_ action: DraftAction) {
        guard flush() else { return }
        if var note = scratchNote {
            note.content = editor.content
            do { try library.saveNote(note); scratchNote = nil } catch { library.error = error.localizedDescription; return }
        }
        _ = runner.runResult(action); status = runner.message ?? ""
        tagsText = currentNote?.tags.joined(separator: ", ") ?? ""
    }
    func preview() {
        if let actionPreview { actionPreview.finish(false); return }
        guard flush() else { return }
        previewHTML = nil; showPreview.toggle()
        if showPreview { window?.makeFirstResponder(nil) }
        else { editor.focusToken = UUID() }
    }
    func edit(_ script: String) {
        guard currentNote != nil else { return }
        run(DraftAction(name: "Edit Text", steps: [ActionStep("script", ["script": script])]))
    }
    func navigate(_ offset: Int) {
        let notes = visibleNotes
        guard !notes.isEmpty else { return }
        let index = notes.firstIndex { $0.id == editor.noteID }.map { min(max(0, $0 + offset), notes.count - 1) } ?? 0
        select(notes[index].id)
    }
    func toggleFloat() { isFloating.toggle(); window?.level = isFloating ? .floating : .normal }
    var activeTagFilters: [String] {
        Array(selectedTags).sorted()
    }
    var excludedTagFilters: [String] { Array(excludedTags).sorted() }
    func toggleTag(_ value: String) {
        let value = TagRules.normalize(value)
        guard !value.isEmpty else { return }
        if selectedTags.contains(value) { selectedTags.remove(value) }
        else {
            if !multipleTagMode { selectedTags.removeAll() }
            selectedTags.insert(value); excludedTags.remove(value)
        }
        tagPresence = nil
    }
    func toggleExcludedTag(_ value: String) {
        let value = TagRules.normalize(value)
        guard !value.isEmpty else { return }
        if excludedTags.contains(value) { excludedTags.remove(value) }
        else { excludedTags.insert(value); selectedTags.remove(value) }
        tagPresence = nil
    }
    func removeTagFilter(_ value: String, excluded: Bool = false) {
        if excluded { excludedTags.remove(value) } else { selectedTags.remove(value) }
    }
    func setMultipleTagMode(_ enabled: Bool) {
        multipleTagMode = enabled
        if !enabled {
            if let first = selectedTags.sorted().first { selectedTags = [first] } else { selectedTags = [] }
            excludedTags = []; matchAnyTag = false
        }
    }
    var tagFilterSummary: String {
        var parts = activeTagFilters.map { "#" + $0 }
        parts += excludedTagFilters.map { "−#" + $0 }
        if let tagPresence { parts.append(tagPresence ? "tagged" : "untagged") }
        return parts.isEmpty ? "No tag filters active" : parts.joined(separator: ", ")
    }
    func clearFilters() { workspaceScriptMetadata = nil; listOptions = DraftListDefaults.load(); query = ""; tag = nil; excludedTags = []; matchAnyTag = false; tagQuery = ""; tagPresence = nil; selectedWorkspace = nil }
    @discardableResult func capture(_ content: String) -> Bool {
        guard create() else { return false }
        editor.content = content; contentChanged()
        return true
    }
    func applicationResigned(at date: Date = Date()) {
        _ = flush(); inactiveSince = date
    }
    func applicationActivated(at date: Date = Date(), timeout: TimeInterval) {
        defer { inactiveSince = nil }
        guard let inactiveSince, timeout > 0, date.timeIntervalSince(inactiveSince) >= timeout,
              !isDraftPinned, let note = currentNote,
              !note.content.isEmpty || !note.tags.isEmpty || note.flag > 0 else { return }
        create()
    }
    func importFile() {
        guard flush() else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.allowedContentTypes = [.json, .plainText, .data]
        guard panel.runModal() == .OK else { return }
        perform {
            for url in panel.urls {
                let data = try Data(contentsOf: url)
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["version"] != nil, object["revisions"] != nil { try library.restore(data) }
                else if let actions = try? ActionImporter.decode(data) { for action in actions { try library.saveAction(action) } }
                else if let notes = try? ActionImporter.importNotes(data) {
                    for var note in notes {
                        if let existing = library.notes.first(where: { $0.id == note.id }), existing.content != note.content { note.id = UUID() }
                        try library.saveNote(note, preserveDates: true)
                    }
                } else if url.pathExtension.lowercased() != "json", let content = String(data: data, encoding: .utf8) {
                    _ = try library.createNote(content: content)
                } else { throw DraftlyError.message("This file is not a Draftly backup, Drafts export, or action file.") }
            }
            status = "Import complete"
        }
    }
    func exportBackup() {
        guard flush() else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Draftly Backup.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try library.backupData().write(to: url, options: .atomic); status = "Backup saved" }
    }
    func exportNote() {
        guard flush(), let note = currentNote else { return }
        perform { _ = try host.perform("saveFile", values: ["text": note.content, "name": note.title + ".md"]) }
    }
}

struct WindowModelKey: FocusedValueKey { typealias Value = WindowModel }
extension FocusedValues {
    var windowModel: WindowModel? { get { self[WindowModelKey.self] } set { self[WindowModelKey.self] = newValue } }
}


extension WindowModel {
    func importSyntax(asFile: Bool) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.message = asFile ? "Select a syntax file. File changes apply when the syntax is read." : "Import a Drafts syntax definition."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let active = url.startAccessingSecurityScopedResource(); defer { if active { url.stopAccessingSecurityScopedResource() } }
            var value = try SyntaxDefinition(data: Data(contentsOf: url), type: asFile ? "file" : "custom")
            if let existing = library.syntaxes.first(where: { $0.name == value.name }) {
                let alert = NSAlert(); alert.messageText = "Replace syntax “\(value.name)”?"
                alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                value.id = existing.id
            }
            if asFile { try SyntaxFileAccess.register(url, id: value.id) }
            try library.saveSyntax(value)
        }
    }
}
