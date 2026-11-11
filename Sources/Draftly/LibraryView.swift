import SwiftUI
import DraftlyCore

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    @StateObject private var model: WindowModel
    @ObservedObject private var hub: AppController
    private let requestID: UUID?
    @SceneStorage("draftly.scene.editorDraftID") private var restoredDraftID = ""
    @State private var showTagSearch = false
    @State private var writingHeaderHeights: [Int: CGFloat] = [:]
    @State private var writingFooterHeights: [Int: CGFloat] = [:]
    private var writingHeaderHeight: CGFloat { max(MainWindowStyle.editorHeaderHeight, writingHeaderHeights.values.max() ?? 0) }
    private var writingFooterHeight: CGFloat { writingFooterHeights.values.max() ?? (MainWindowStyle.editingBarHeight + MainWindowStyle.footerHeight + 1) }
    @AppStorage("editor.fontName") private var fontName = EditorPreferenceDefaults.fontName
    @AppStorage("editor.fontSize") private var fontSize = EditorPreferenceDefaults.fontSize
    @AppStorage("editor.lineSpacing") private var lineSpacing = EditorPreferenceDefaults.lineSpacing
    @AppStorage("editor.horizontalMargin") private var horizontalMargin = EditorTextLayout.horizontalMargin
    @AppStorage("editor.verticalMargin") private var verticalMargin = EditorTextLayout.verticalMargin
    @AppStorage("editor.maximumWidth") private var maximumWidth = EditorPreferenceDefaults.maximumWidth
    @AppStorage("editor.typewriter") private var typewriter = EditorPreferenceDefaults.typewriter
    @AppStorage("editor.theme") private var themeName = "System"
    @AppStorage(EditorThemePreferences.key) private var themeReferences = Data()
    @AppStorage(EditorThemePreferences.revisionKey) private var themeRevision = 0
    private var themePresentation: WindowThemePresentation {
        // Observe both the previous setting and the current local selection.
        _ = themeName; _ = themeReferences; _ = themeRevision
        return model.editorThemePresentation(systemIsDark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
    private var theme: EditorTheme? { themePresentation.theme }
    private var preferredScheme: ColorScheme? { themePresentation.dark.map { $0 ? .dark : .light } }
    @AppStorage("capture.newDraftAfter") private var newDraftAfter = CaptureDefaults.newDraftAfter

    init(library: LibraryStore, controller: AppController, requestID: UUID? = nil) {
        self.hub = controller
        self.library = library
        self.requestID = requestID
        _model = StateObject(wrappedValue: controller.makeWindowModel(library: library))
    }
    var body: some View {
        LibrarySplitView(model: model, panels: [
            panel(sidebar), panel(noteList), panel(editor, writingSlot: 0), panel(model.showChatConsole ? AnyView(chatConsole) : AnyView(actionPanel), writingSlot: 1)
        ])
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .top) {
            if let banner = model.messageBanner {
                ActionMessageBannerView(banner: banner) { model.messageBanner = nil }
                    .padding(.horizontal, 20).padding(.top, 80)
            }
        }
        .preferredColorScheme(preferredScheme)
        .onChange(of: themePresentation.error, initial: true) { _, error in
            if let error { library.error = error }
        }
        .frame(minWidth: 850, minHeight: 480)
        .background(WindowAccessor { window in
            hub.registerWindow(model, window: window, requestID: requestID)
        })
        .focusedSceneValue(\.windowModel, model)
        .background(AdvancedFindWindow(model: model).frame(width: 0, height: 0))
        .sheet(item: $model.mergeRequest) { request in MergeDraftsView(model: model, request: request) }
        .sheet(item: $model.editingAction) { action in ActionEditor(action: action, library: library) }
        .sheet(isPresented: $model.showActionImporter) { ActionImportView(library: library) { actions in model.actionGroup = actions.first?.group ?? "General" } }
        .sheet(isPresented: $model.showLibraryManagement) { LibraryManagementView(model: model, library: library, initialSection: model.libraryManagementSection) }
        .sheet(isPresented: $model.showWorkspaceEditor) { WorkspaceEditor(model: model, library: library) }
        .sheet(isPresented: $model.showHistory, onDismiss: { model.historyDraftID = nil }) { HistoryView(model: model, library: library, noteID: model.historyDraftID ?? model.editor.noteID) }
        .sheet(isPresented: $model.showRunLog) { RunLogView(library: library) }
        .sheet(isPresented: $model.showPalette) { CommandPalette(model: model, library: library) }
        .sheet(isPresented: $model.showInfo, onDismiss: { model.infoDraft = nil }) { if let note = model.infoDraft ?? model.currentNote { DraftInfoView(note: note) } }
        .alert("Draftly", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .onChange(of: typewriter) { _, enabled in model.editor.typewriterScrollingEnabled = enabled }
        .onChange(of: model.selectedDraftIDs) { _, ids in if ids.count == 1 { model.selectFromList(ids.first) } }
        .onChange(of: model.editor.noteID) { _, id in
            model.chatConsole.draftSelectionChanged()
            restoredDraftID = id?.uuidString ?? ""
            hub.draftSelectionDidChange(id, for: model)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in model.applicationResigned() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if model.window?.isKeyWindow == true { model.applicationActivated(timeout: newDraftAfter) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { event in
            if let window = event.object as? NSWindow, window === model.window { hub.registerWindow(model, window: window, requestID: requestID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { event in
            if let window = event.object as? NSWindow, window === model.window {
                model.chatConsole.close()
                model.cancelActions(); model.actionPreview?.finish(false); model.flush()
                hub.unregisterWindow(model)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftlyOpenNote)) { event in
            guard model.window?.isKeyWindow == true, let id = event.object as? UUID else { return }
            hub.pendingNoteID = id
            _ = hub.consumePendingDraft(for: model)
        }
        .onReceive(library.$notes) { notes in model.synchronizeStoredEditor(notes) }
        .onAppear {
            model.editor.typewriterScrollingEnabled = typewriter
            hub.registerWindow(model, requestID: requestID)
            hub.commandWindow = model
            if !hub.hasDraftSceneRequest(requestID) {
                hub.consumePendingMenuAction(for: model)
                _ = hub.consumePendingDraft(for: model)
                if model.editor.noteID == nil { model.restoreEditorDraft(restoredDraftID) }
                if hub.pendingNoteID == nil && model.editor.noteID == nil { model.create() }
            }
        }
    }

    private func panel<Content: View>(_ content: Content, writingSlot: Int? = nil) -> AnyView {
        AnyView(content
            .environment(\.writingHeaderMinimum, model.showChatConsole ? writingHeaderHeight : 0)
            .environment(\.writingFooterMinimum, model.showChatConsole ? writingFooterHeight : 0)
            .onPreferenceChange(WritingHeaderHeightPreference.self) { height in
                if let writingSlot, writingHeaderHeights[writingSlot] != height { writingHeaderHeights[writingSlot] = height }
            }
            .onPreferenceChange(WritingFooterHeightPreference.self) { height in
                if let writingSlot, writingFooterHeights[writingSlot] != height { writingFooterHeights[writingSlot] = height }
            }
            .focusedSceneValue(\.windowModel, model)
            .preferredColorScheme(preferredScheme)
        .onChange(of: themePresentation.error, initial: true) { _, error in
            if let error { library.error = error }
        })
    }

    private var sidebar: some View { DraftFiltersPanel(model: model, showTagSearch: $showTagSearch) }

    private var noteList: some View {
        DraftListPanel(model: model, library: library, selection: $model.selectedDraftIDs)
    }

    private var editor: some View {
        DraftEditorPanel(model: model, library: library, fontName: fontName, fontSize: fontSize,
            lineSpacing: lineSpacing, horizontalMargin: horizontalMargin, verticalMargin: verticalMargin,
            maximumWidth: maximumWidth, theme: theme)
    }

    private var actionPanel: some View {
        ActionListPanel(model: model, library: library)
    }

    @ViewBuilder private var chatConsole: some View {
        if let settings = hub.agentSettings {
            LocalChatConsolePanel(model: model.chatConsole, settings: settings, editorTheme: theme,
                contentFont: Font(fontName == "System" ? NSFont.systemFont(ofSize: fontSize) : NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)),
                createDraft: { text in _ = model.capture(text) },
                insertText: { text in model.perform {
                    try model.editor.replace(model.editor.safeSelection, with: text)
                    model.editor.synchronizeScriptEdit?()
                    model.contentChanged()
                } },
                hasDraft: library.notes.contains { $0.id == model.editor.noteID },
                connectTools: { try hub.requestChatToolsFromUserInterface(for: model) })
        } else {
            ChatConsolePanel(model: model.chatConsole)
        }
    }

}
