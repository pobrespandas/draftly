import SwiftUI
import AppKit
import DraftlyCore

@MainActor
final class WindowModel: ObservableObject {
    let library: LibraryStore
    let editor = EditorSession()
    let host = NativeActionHost()
    let runner: ActionRunner
    @Published var folder: NoteFolder = .inbox
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
    @Published var sort: NoteSort = .modified
    @Published var ascending = false
    @Published var showActions = false
    @Published var darkTheme: Bool?
    @Published var showTags = true
    @Published var showInfo = false
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
    @Published var showRunLog = false
    @Published var status = ""
    @Published var tagsText = ""
    @Published var hasUnsavedChanges = false
    @Published private var scratchNote: Note?
    weak var window: NSWindow?
    var referenceToolbar: ReferenceToolbar?
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
        runner.applyWorkspace = { [weak self] workspace in self?.apply(workspace) }
        runner.currentWorkspace = { [weak self] in
            guard let self else { return Workspace(name: "Current") }
            var result = Workspace(name: "Current"); result.folder = self.folder; result.query = self.query
            result.tags = self.activeTagFilters; result.excludedTags = self.excludedTagFilters
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
            case "isActive": return window?.firstResponder is NSTextView
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
        case "showActionList": showActions = true
        case "hideActionList": showActions = false
        case "showDraftList": setDraftListVisible(true)
        case "hideDraftList": setDraftListVisible(false)
        case "showFilters": setFiltersVisible(true)
        case "hideFilters": setFiltersVisible(false)
        case "showDraftInfo": showInfo = true
        case "showQuickSearch": setDraftListVisible(true); showNoteSearch = true; noteSearchFocus = UUID()
        case "showCommandPalette": showPalette = true
        case "loadActionBarGroup", "loadKeyboardActionGroup", "loadActionGroup":
            let name = (value as? [String: Any])?["name"] as? String ?? value as? String ?? ""
            guard library.actions.contains(where: { $0.group == name }) else { throw DraftlyError.message("The action group was not found.") }
            if operation == "loadActionGroup" { actionGroup = name; showActions = true } else { actionBarGroup = name }
        case "nextDraft": navigate(1)
        case "previousDraft": navigate(-1)
        case "deactivate": window?.makeFirstResponder(nil)
        case "undo", "redo": NSApp.sendAction(NSSelectorFromString(operation + ":"), to: nil, from: nil)
        case "showFind":
            if let query = args.dropFirst().first as? String { NSPasteboard(name: .find).clearContents(); NSPasteboard(name: .find).setString(query, forType: .string) }
            let item = NSMenuItem(); item.tag = NSTextFinder.Action.showFindInterface.rawValue
            NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
        case "showDictate": editor.focusToken = UUID(); DispatchQueue.main.async { NSApp.sendAction(NSSelectorFromString("startDictation:"), to: nil, from: nil) }
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
        case "hideChatConsole": break
        default: throw DraftlyError.message("The window operation \(operation) is unavailable.")
        }
        return true
    }
    var currentNote: Note? { library.notes.first { $0.id == editor.noteID } ?? scratchNote }
    var visibleNotes: [Note] {
        var workspace = Workspace(name: "Current")
        workspace.folder = folder; workspace.query = query; workspace.tags = activeTagFilters
        workspace.excludedTags = excludedTagFilters
        workspace.matchAnyTag = matchAnyTag
        workspace.tagged = tagPresence
        workspace.sort = sort; workspace.ascending = ascending
        var notes = workspace.filter(library.notes)
        if let scratchNote, scratchNote.id == editor.noteID,
           folder == .inbox || folder == .all,
           workspace.filter([scratchNote]).contains(where: { $0.id == scratchNote.id }) {
            notes.append(scratchNote)
            notes = workspace.filter(notes)
        }
        return notes
    }
    var allTags: [String] { Array(Set(library.notes.flatMap(\.tags).map(TagRules.normalize))).sorted() }
    var matchingTags: [String] {
        let needle = TagRules.normalize(tagQuery)
        return allTags.filter { needle.isEmpty || $0.localizedStandardContains(needle) }
    }
    private var notesBeforeTagFilters: [Note] {
        var workspace = Workspace(name: "Counts")
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
    func select(_ id: UUID?) {
        guard id != editor.noteID, flush() else { return }
        if let current = editor.noteID, library.notes.contains(where: { $0.id == current }) { lastNoteID = current }
        status = ""; previewHTML = nil
        scratchNote = nil
        if let note = library.notes.first(where: { $0.id == id }) {
            editor.load(note); tagsText = note.tags.joined(separator: ", "); onAccessDraft(note.id)
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
            for id in ids {
                if var note = library.notes.first(where: { $0.id == id }) ?? (scratchNote?.id == id ? scratchNote : nil) {
                    operation(&note); try library.saveNote(note)
                    if scratchNote?.id == id { scratchNote = nil }
                }
            }
        }
    }
    func apply(_ workspace: Workspace) {
        folder = workspace.folder; query = workspace.query; sort = workspace.sort; ascending = workspace.ascending
        selectedWorkspace = library.workspaces.contains(where: { $0.id == workspace.id }) ? workspace.id : nil
        selectedTags = Set(workspace.tags.map(TagRules.normalize))
        excludedTags = Set((workspace.excludedTags ?? []).map(TagRules.normalize))
        matchAnyTag = workspace.matchAnyTag ?? false
        if selectedTags.count > 1 || !excludedTags.isEmpty { multipleTagMode = true }
        tagPresence = workspace.tagged
        showNoteSearch = !workspace.query.isEmpty
    }
    func run(_ action: DraftAction) {
        guard flush() else { return }
        if var note = scratchNote {
            note.content = editor.content
            do { try library.saveNote(note); scratchNote = nil } catch { library.error = error.localizedDescription; return }
        }
        _ = runner.run(action); status = runner.message ?? ""
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
    func clearFilters() { query = ""; tag = nil; excludedTags = []; matchAnyTag = false; tagQuery = ""; tagPresence = nil; selectedWorkspace = nil }
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
                        try library.saveNote(note)
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
