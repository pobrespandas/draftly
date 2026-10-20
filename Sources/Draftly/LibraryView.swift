import SwiftUI
import DraftlyCore

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    @StateObject private var model: WindowModel
    @ObservedObject private var hub: AppController
    @State private var selection: Set<UUID> = []
    @State private var showTagSearch = false
    @AppStorage("editor.fontName") private var fontName = "System"
    @AppStorage("editor.fontSize") private var fontSize = 17.0
    @AppStorage("editor.lineSpacing") private var lineSpacing = 2.0
    @AppStorage("editor.horizontalMargin") private var horizontalMargin = EditorTextLayout.horizontalMargin
    @AppStorage("editor.verticalMargin") private var verticalMargin = EditorTextLayout.verticalMargin
    @AppStorage("editor.maximumWidth") private var maximumWidth = 0.0
    @AppStorage("editor.typewriter") private var typewriter = false
    @AppStorage("editor.theme") private var themeName = "System"
    @AppStorage("editor.themes") private var themeData = "[]"
    private var workspaceThemeName: String? {
        let isDark = model.darkTheme ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let key = isDark ? "preferredDarkTheme" : "preferredLightTheme"
        return (WorkspaceThemeValues.preference(model.workspaceScriptMetadata, key: key))
    }
    private var theme: EditorTheme? { EditorTheme.selected(name: workspaceThemeName ?? themeName, data: themeData) }
    private var preferredScheme: ColorScheme? {
        if workspaceThemeName == "Dark" { return .dark }
        if workspaceThemeName == "Light" { return .light }
        return model.darkTheme.map { $0 ? .dark : .light } ?? theme.map { $0.isDark ? .dark : .light }
    }
    @AppStorage("capture.newDraftAfter") private var newDraftAfter = 300.0
    @Environment(\.openWindow) private var openWindow

    init(library: LibraryStore, controller: AppController) {
        self.hub = controller
        self.library = library
        _model = StateObject(wrappedValue: controller.makeWindowModel(library: library))
    }
    var body: some View {
        LibrarySplitView(model: model, panels: [
            panel(sidebar), panel(noteList), panel(editor), panel(actionPanel)
        ])
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(preferredScheme)
        .frame(minWidth: 850, minHeight: 480)
        .background(WindowAccessor { window in
            model.window = window
            if window.isKeyWindow { hub.commandWindow = model }
        })
        .focusedSceneValue(\.windowModel, model)
        .sheet(isPresented: $model.showAdvancedFind) { AdvancedFindView(model: model) }
        .sheet(item: $model.mergeRequest) { request in MergeDraftsView(model: model, request: request) }
        .sheet(item: $model.editingAction) { action in ActionEditor(action: action, library: library) }
        .sheet(isPresented: $model.showActionImporter) { ActionImportView(library: library) { actions in model.actionGroup = actions.first?.group ?? "General" } }
        .sheet(isPresented: $model.showLibraryManagement) { LibraryManagementView(model: model, library: library) }
        .sheet(isPresented: $model.showWorkspaceEditor) { WorkspaceEditor(model: model, library: library) }
        .sheet(isPresented: $model.showHistory, onDismiss: { model.historyDraftID = nil }) { HistoryView(model: model, library: library, noteID: model.historyDraftID ?? model.editor.noteID) }
        .sheet(isPresented: $model.showRunLog) { RunLogView(library: library) }
        .sheet(isPresented: $model.showPalette) { CommandPalette(model: model, library: library) }
        .sheet(isPresented: $model.showInfo, onDismiss: { model.infoDraft = nil }) { if let note = model.infoDraft ?? model.currentNote { DraftInfoView(note: note) } }
        .alert("Draftly", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .onChange(of: typewriter) { _, enabled in model.editor.typewriterScrollingEnabled = enabled }
        .onChange(of: model.listOptions) { _, options in
            if model.selectedWorkspace == nil, let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: "list.options") }
        }
        .onChange(of: selection) { _, ids in if ids.count == 1 { model.select(ids.first, focusEditor: false) } }
        .onChange(of: model.editor.noteID) { _, id in selection = id.map { [$0] } ?? [] }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in model.applicationResigned() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if model.window?.isKeyWindow == true { model.applicationActivated(timeout: newDraftAfter) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { event in
            if let window = event.object as? NSWindow, window === model.window { hub.commandWindow = model }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { event in
            if let window = event.object as? NSWindow, window === model.window {
                model.cancelActions(); model.actionPreview?.finish(false); model.flush()
                if hub.commandWindow === model { hub.commandWindow = nil }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftlyOpenNote)) { event in
            guard model.window?.isKeyWindow == true, let id = event.object as? UUID else { return }
            model.folder = .inbox; model.clearFilters(); model.select(id)
            hub.pendingNoteID = nil
        }
        .onReceive(library.$notes) { notes in model.synchronizeStoredEditor(notes) }
        .onAppear {
            model.editor.typewriterScrollingEnabled = typewriter
            hub.windows.add(model)
            hub.commandWindow = model
            hub.openLibrary = { openWindow(id: "library") }
            hub.consumePendingMenuAction(for: model)
            if let id = hub.pendingNoteID { model.select(id); hub.pendingNoteID = nil }
            else if model.editor.noteID == nil { model.create() }
            if let id = model.editor.noteID { selection = [id] }
        }
    }

    private func panel<Content: View>(_ content: Content) -> AnyView {
        AnyView(content
            .focusedSceneValue(\.windowModel, model)
            .preferredColorScheme(preferredScheme))
    }

    private var sidebar: some View { DraftFiltersPanel(model: model, showTagSearch: $showTagSearch) }

    private var noteList: some View {
        DraftListPanel(model: model, library: library, selection: $selection)
    }

    private var editor: some View {
        DraftEditorPanel(model: model, library: library, fontName: fontName, fontSize: fontSize,
            lineSpacing: lineSpacing, horizontalMargin: horizontalMargin, verticalMargin: verticalMargin,
            maximumWidth: maximumWidth, theme: theme)
    }

    private var actionPanel: some View {
        ActionListPanel(model: model, library: library)
    }

}
