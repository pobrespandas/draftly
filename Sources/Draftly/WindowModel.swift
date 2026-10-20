import Combine
import AppKit
import DraftlyCore

@MainActor
final class WindowModel: ObservableObject {
    let library: LibraryStore
    let editor = EditorSession()
    let host: NativeActionHost
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
    let dictationSession = WindowDictationSession()
    var dictationActive: Bool { dictationSession.isActive }
    var presentDictation: (@MainActor () async throws -> String)?
    var recoverDictation: (String) -> Void
    @Published var showActionBar = true
    @Published var showActions = false
    @Published var darkTheme: Bool?
    @Published var showTags = true
    var prefersAdvancedFind: () -> Bool
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
    @Published var listOptions: DraftListOptions
    @Published var showRunLog = false
    @Published var status = ""
    @Published var tagsText = ""
    @Published var hasUnsavedChanges = false
    @Published private var scratchNote: Note?
    weak var window: NSWindow?
    var referenceToolbar: ReferenceToolbar?
    var openQuickSearch: () -> Void
    let dependencies: WindowDependencies
    private var saveTask: Task<Void, Never>?
    @Published var actionPending = false
    var actionTask: Task<Void, Never>?
    let arrangementSession = WindowArrangementSession()
    private let saveDraft: (Note) throws -> Void
    private let onAccessDraft: (UUID) -> Void
    private var inactiveSince: Date?
    private var idleActivity: NSObjectProtocol?

    init(library: LibraryStore, dependencies: WindowDependencies = WindowDependencies(), saveDraft: ((Note) throws -> Void)? = nil, onAccessDraft: @escaping (UUID) -> Void = { _ in }) {
        self.library = library
        self.host = dependencies.makeActionHost()
        self.dependencies = dependencies
        self.listOptions = dependencies.preferences.listOptions
        self.recoverDictation = dependencies.recoverDictation
        self.openQuickSearch = dependencies.openQuickSearch
        self.prefersAdvancedFind = { dependencies.preferences.prefersAdvancedFind }
        self.saveDraft = saveDraft ?? { try library.saveNote($0) }
        self.onAccessDraft = onAccessDraft
        runner = ActionRunner(library: library, editor: editor, host: host)
        runner.applyWorkspace = { [weak self] workspace in try self?.applyScriptWorkspace(workspace) }
        runner.defaultWorkspace = { [weak library] in
            guard let library else { return Workspace(name: "") }
            var value = WorkspaceDefaults.make(in: library, defaults: dependencies.preferences.defaults)
            if dependencies.preferences.defaults.string(forKey: WorkspaceDefaults.key).flatMap(UUID.init(uuidString:)).flatMap({ id in library.workspaces.first { $0.id == id } }) == nil { value.listOptions = dependencies.preferences.listOptions }
            return value
        }
        runner.currentWorkspace = { [weak self] in
            guard let self else { return Workspace(name: "Current") }
            return self.workspaceSnapshot(name: "Current")
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
        try WindowActionAdapter(model: self).perform(values)
    }

    var isIdleDisabled: Bool { idleActivity != nil }
    func setIdleDisabled(_ enabled: Bool) {
        if enabled && idleActivity == nil { idleActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled], reason: "Draftly action") }
        if !enabled, let idleActivity { ProcessInfo.processInfo.endActivity(idleActivity); self.idleActivity = nil }
    }

    func showDictation() throws {
        guard !dictationActive else { throw DraftlyError.message("Dictation is already active in this window.") }
        guard editor.focusForDictation != nil else { throw DraftlyError.message("The editor dictation interface is unavailable.") }
        editor.focusToken = UUID(); showPreview = false
        let host = self.host
        let present = presentDictation ?? {
            let response = try await host.performAsync("dictate", payload: "{}")
            guard let envelope = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any] else {
                throw DraftlyError.message("Dictation returned an invalid response.")
            }
            if let error = envelope["error"] as? String { throw DraftlyError.message(error) }
            return envelope["value"] as? String ?? ""
        }
        dictationSession.start(model: self, present: present)
    }
    var currentNote: Note? { library.notes.first { $0.id == editor.noteID } ?? scratchNote }
    @Published var workspaceScriptMetadata: [String: String]?
    func workspaceSnapshot(name: String) -> Workspace {
        var workspace = Workspace(name: name)
        workspace.scriptMetadata = workspaceScriptMetadata
        workspace.listOptions = listOptions
        workspace.folder = folder; workspace.query = query; workspace.tags = activeTagFilters
        workspace.excludedTags = excludedTagFilters
        workspace.matchAnyTag = matchAnyTag
        workspace.tagged = tagPresence
        workspace.sort = sort; workspace.ascending = ascending
        return workspace
    }
    var visibleNotes: [Note] { workspaceSnapshot(name: "Current").filter(library.notes) }

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
    @discardableResult func create(fromAction: Bool = false) -> Bool {
        if !fromAction { cancelActionForUserEdit() }
        guard flush() else { return false }
        if let id = editor.noteID, library.notes.contains(where: { $0.id == id }) { lastNoteID = id }
        let note = Note()
        scratchNote = note; showPreview = false; previewHTML = nil
        editor.load(note); tagsText = ""; status = ""
        folder = .inbox; clearFilters()
        return true
    }
    func select(_ id: UUID?, focusEditor: Bool = true, fromAction: Bool = false) {
        guard id != editor.noteID else { return }
        if !fromAction { cancelActionForUserEdit() }
        guard flush() else { return }
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
    func synchronizeStoredEditor(_ notes: [Note]) {
        guard !hasUnsavedChanges, let id = editor.noteID,
              let note = notes.first(where: { $0.id == id }), note.content != editor.content else { return }
        cancelActionForUserEdit()
        editor.content = note.content
        editor.acknowledgeSaved(note)
    }
    func contentChanged() {
        cancelActionForUserEdit()
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
            if let note = currentNote { editor.acknowledgeSaved(note) }
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
        let resolved = try WorkspacePresentationResolver.resolve(workspace, groupNames: library.groupNames,
            groups: library.actionGroups, themes: library.themes)
        applyResolvedWorkspace(resolved)
    }

    func saveAndApplyWorkspace(_ workspace: Workspace) throws {
        let resolved = try WorkspacePresentationResolver.resolve(workspace, groupNames: library.groupNames,
            groups: library.actionGroups, themes: library.themes)
        try library.saveWorkspace(resolved)
        cancelActionForUserEdit()
        applyResolvedWorkspace(resolved)
    }

    func apply(_ workspace: Workspace) {
        cancelActionForUserEdit()
        perform { try applyScriptWorkspace(workspace) }
    }
    private func applyResolvedWorkspace(_ workspace: Workspace) {
        listOptions = workspace.listOptions ?? dependencies.preferences.listOptions
        folder = workspace.folder; query = workspace.query; sort = workspace.sort; ascending = workspace.ascending
        workspaceScriptMetadata = workspace.scriptMetadata
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
        guard !actionPending, !runner.isRunning else { return }
        actionPending = true
        actionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.actionPending = false; self.actionTask = nil }
            _ = await self.executeAction(action)
        }
    }
    struct ActionOutcome {
        let report: ActionExecutionReport
        let draftID: UUID?
    }
    @discardableResult
    func runAsync(_ action: DraftAction) async -> ActionExecutionReport? {
        await runActionOutcome(action)?.report
    }
    func runActionOutcome(_ action: DraftAction) async -> ActionOutcome? {
        guard !actionPending, !runner.isRunning else { return nil }
        actionPending = true
        defer { actionPending = false }
        return await executeAction(action)
    }
    private func executeAction(_ action: DraftAction) async -> ActionOutcome? {
        guard !Task.isCancelled else { return nil }
        if let busy = libraryBusyReport(for: action) { return ActionOutcome(report: busy, draftID: editor.noteID) }
        guard flush() else { return nil }
        if var note = scratchNote {
            note.content = editor.content
            do { try library.saveNote(note); scratchNote = nil } catch { library.error = error.localizedDescription; return nil }
        }
        let navigation = actionNavigationSnapshot()
        let report = await runner.runAsync(action)
        let outcome = ActionOutcome(report: report, draftID: editor.noteID)
        finishActionNavigation(action, report: report, snapshot: navigation)
        status = runner.message ?? ""
        tagsText = currentNote?.tags.joined(separator: ", ") ?? ""
        return outcome
    }
    func libraryBusyReport(for action: DraftAction) -> ActionExecutionReport? {
        guard ActionRunner.isExecuting(in: library) else { return nil }
        status = "An action is already running in this library."
        return .notStarted(actionID: action.id, reason: .busy, message: status)
    }
    var canCancelActions: Bool { actionPending || runner.isRunning }
    var canRunActions: Bool { currentNote != nil && !canCancelActions }
    func cancelActions() {
        dictationSession.cancel()
        arrangementSession.cancel()
        actionTask?.cancel()
        runner.cancel()
    }
    private func cancelActionForUserEdit() {
        arrangementSession.cancel()
        guard !runner.isApplyingScriptCommand, actionPending || runner.isRunning else { return }
        cancelActions()
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
    func clearFilters() { workspaceScriptMetadata = nil; listOptions = dependencies.preferences.listOptions; query = ""; tag = nil; excludedTags = []; matchAnyTag = false; tagQuery = ""; tagPresence = nil; selectedWorkspace = nil }
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
    func importFile() { DraftFileCommands(model: self).importFile() }
    func exportBackup() { DraftFileCommands(model: self).exportBackup() }
    func exportNote() { DraftFileCommands(model: self).exportNote() }

}



extension WindowModel {
    func importSyntax(asFile: Bool) { DraftFileCommands(model: self).importSyntax(asFile: asFile) }

}
