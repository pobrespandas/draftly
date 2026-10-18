import SwiftUI
import DraftlyCore

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    @StateObject private var model: WindowModel
    @ObservedObject private var hub = AppController.shared
    @State private var selection: Set<UUID> = []
    @State private var showAdvancedTagFilters = false
    @AppStorage("editor.fontName") private var fontName = "SFMono-Regular"
    @AppStorage("editor.fontSize") private var fontSize = 17.0
    @AppStorage("editor.lineSpacing") private var lineSpacing = 2.0
    @AppStorage("capture.newDraftAfter") private var newDraftAfter = 300.0
    @Environment(\.openWindow) private var openWindow

    init(library: LibraryStore) {
        self.library = library
        _model = StateObject(wrappedValue: WindowModel(library: library, onAccessDraft: { AppController.shared.recordRecentDraft($0) }))
    }
    var body: some View {
        LibrarySplitView(model: model, panels: [
            panel(sidebar), panel(noteList), panel(editor), panel(actionPanel)
        ])
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(model.darkTheme.map { $0 ? .dark : .light })
        .frame(minWidth: 850, minHeight: 560)
        .background(WindowAccessor { window in
            model.window = window
        })
        .focusedSceneValue(\.windowModel, model)
        .sheet(item: $model.editingAction) { action in ActionEditor(action: action, library: library) }
        .sheet(isPresented: $model.showActionImporter) { ActionImportView(library: library) { actions in model.actionGroup = actions.first?.group ?? "General" } }
        .sheet(isPresented: $model.showWorkspaceEditor) { WorkspaceEditor(model: model, library: library) }
        .sheet(isPresented: $model.showHistory) { HistoryView(model: model, library: library) }
        .sheet(isPresented: $model.showRunLog) { RunLogView(library: library) }
        .sheet(isPresented: $model.showPalette) { CommandPalette(model: model, library: library) }
        .sheet(isPresented: $model.showInfo) { if let note = model.currentNote { DraftInfoView(note: note) } }
        .alert("Draftly", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .onChange(of: selection) { _, ids in if ids.count == 1 { model.select(ids.first) } }
        .onChange(of: model.editor.noteID) { _, id in selection = id.map { [$0] } ?? [] }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in model.applicationResigned() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if model.window?.isKeyWindow == true { model.applicationActivated(timeout: newDraftAfter) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { event in
            if let window = event.object as? NSWindow, window === model.window { model.actionPreview?.finish(false); model.flush() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftlyOpenNote)) { event in
            guard model.window?.isKeyWindow == true, let id = event.object as? UUID else { return }
            model.folder = .inbox; model.clearFilters(); model.select(id)
            hub.pendingNoteID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftlyCapture)) { event in
            guard model.window?.isKeyWindow == true else { return }
            if model.capture(event.object as? String ?? "") { hub.pendingCaptureText = nil }
        }
        .onReceive(library.$notes) { notes in
            guard !model.hasUnsavedChanges, let id = model.editor.noteID,
                  let note = notes.first(where: { $0.id == id }), note.content != model.editor.content else { return }
            model.editor.content = note.content
        }
        .onAppear {
            hub.windows.add(model)
            hub.openLibrary = { openWindow(id: "library") }
            hub.consumePendingMenuAction(for: model)
            if let id = hub.pendingNoteID { model.select(id); hub.pendingNoteID = nil }
            else if model.editor.noteID == nil { model.create() }
            if let id = model.editor.noteID { selection = [id] }
            if let text = hub.pendingCaptureText, model.capture(text) { hub.pendingCaptureText = nil }
        }
    }

    private func panel<Content: View>(_ content: Content) -> AnyView {
        AnyView(content
            .focusedSceneValue(\.windowModel, model)
            .preferredColorScheme(model.darkTheme.map { $0 ? .dark : .light }))
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle.fill").font(.system(size: 20))
                Text("Filters").font(.system(size: 11, weight: .semibold)).textCase(.uppercase).tracking(0.35)
                Spacer()
                Button { model.clearFilters() } label: { Image(systemName: "xmark.circle").font(.system(size: 20, weight: .light)) }.help("Clear Filters")
                Menu {
                    Button(showAdvancedTagFilters ? "Hide Advanced Tag Filters" : "Show Advanced Tag Filters") { showAdvancedTagFilters.toggle() }
                    Divider()
                    Button(model.multipleTagMode ? "Single Tag Mode" : "Multiple Tag Mode") { model.setMultipleTagMode(!model.multipleTagMode) }
                    Divider()
                    Button(model.matchAnyTag ? "Match All Tags ✓" : "Match All Tags") { model.matchAnyTag = false }
                    Button(model.matchAnyTag ? "Match Any Tag ✓" : "Match Any Tag") { model.matchAnyTag = true }
                    Button("Save Workspace…") { model.showWorkspaceEditor = true }
                    Button("Hide Filters") { model.setFiltersVisible(false) }
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 20, weight: .light)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 40)
            if !model.activeTagFilters.isEmpty || !model.excludedTagFilters.isEmpty || model.tagPresence != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(model.activeTagFilters, id: \.self) { tag in
                            filterChip(tag, color: .accentColor) { model.removeTagFilter(tag) }
                        }
                        ForEach(model.excludedTagFilters, id: \.self) { tag in
                            filterChip("−\(tag)", color: .red) { model.removeTagFilter(tag, excluded: true) }
                        }
                        if let tagged = model.tagPresence { filterChip(tagged ? "tagged" : "untagged", color: .secondary) { model.tagPresence = nil } }
                    }.padding(.horizontal, 16).padding(.top, 10)
                }.frame(height: 60, alignment: .top)
            } else {
                Color.clear.frame(height: 60)
            }
            if showAdvancedTagFilters {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Filter tags", text: $model.tagQuery).textFieldStyle(.plain).font(.system(size: 12))
                    if !model.tagQuery.isEmpty { Button { model.tagQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary) }
                }.padding(.horizontal, 8).frame(height: 25).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 5)).padding(.horizontal, 12).padding(.bottom, 4)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "tag.circle").font(.system(size: 20, weight: .light))
                        Text("Tags")
                    }.font(.system(size: 11, weight: .semibold)).textCase(.uppercase).tracking(0.3)
                        .foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
                    Button { model.tagPresence = model.tagPresence == true ? nil : true } label: { filterRow("tagged", symbol: "tag.fill", selected: model.tagPresence == true) }
                        .buttonStyle(.plain).padding(.horizontal, 9).frame(height: 32).background(model.tagPresence == true ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityLabel("Tagged, \(model.taggedCount) drafts")
                    Button { model.tagPresence = model.tagPresence == false ? nil : false } label: { filterRow("untagged", symbol: "tag.fill", selected: model.tagPresence == false) }
                        .buttonStyle(.plain).padding(.horizontal, 9).frame(height: 32).background(model.tagPresence == false ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityLabel("Untagged, \(model.untaggedCount) drafts")
                    ForEach(showAdvancedTagFilters ? model.matchingTags : model.allTags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Button { model.toggleTag(tag) } label: { filterRow(tag, symbol: "tag", selected: model.selectedTags.contains(tag)) }
                                .buttonStyle(.plain).accessibilityLabel("Filter by tag \(tag), \(model.count(forTag: tag)) drafts")
                            if model.multipleTagMode {
                                Button { model.toggleExcludedTag(tag) } label: {
                                    TagGlyph(symbol: model.excludedTags.contains(tag) ? "minus.circle.fill" : "minus.circle")
                                        .foregroundStyle(model.excludedTags.contains(tag) ? Color.red : Color.secondary.opacity(0.45))
                                }.buttonStyle(.plain).help("Exclude tag \(tag)")
                            }
                        }
                        .padding(.horizontal, 9).frame(height: 32)
                        .background(model.selectedTags.contains(tag) || model.excludedTags.contains(tag) ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contextMenu {
                            Button("Include Tag") { model.toggleTag(tag) }
                            Button("Exclude Tag") { model.toggleExcludedTag(tag) }
                        }
                    }
                    if model.matchingTags.isEmpty { Text(model.allTags.isEmpty ? "No tags yet" : "No matching tags").font(.system(size: 12)).foregroundStyle(.secondary).padding(12) }
                }.padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background(Color.primary.opacity(0.04)).background(Color(nsColor: .windowBackgroundColor))
    }

    private func filterRow(_ title: String, symbol: String, selected: Bool = false) -> some View {
        HStack(spacing: 10) {
            TagGlyph(symbol: symbol, weight: .medium).foregroundStyle(selected ? Color.white : Color.accentColor)
            Text(title).fontWeight(selected ? .semibold : .regular).lineLimit(1)
            Spacer(minLength: 6)
        }.font(.system(size: 13)).foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
    }
    private func filterChip(_ title: String, color: Color, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary.opacity(0.6)) }
                .buttonStyle(.plain).accessibilityLabel("Remove \(title)")
        }
        .font(.system(size: 12)).foregroundStyle(.primary)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.2)))
    }

    private var noteList: some View {
        DraftListPanel(model: model, library: library, selection: $selection)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if let note = model.currentNote {
                editorContent(note)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "square.and.pencil").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(.tint)
                    Text("Your next thought starts here.").font(.title2.weight(.medium))
                    Text("Write first. Decide what to do with it later.").foregroundStyle(.secondary)
                    Button("New Draft") { model.create() }.buttonStyle(.borderedProminent).keyboardShortcut("n")
                    Text("⌃⌥⌘N to capture from anywhere").font(.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(nsColor: .textBackgroundColor))
    }

    private func editorContent(_ note: Note) -> some View {
        VStack(spacing: 0) {
            if note.trashedAt != nil {
                HStack { Label("This draft is in the Trash", systemImage: "trash"); Spacer(); Button("Restore") { model.change([note.id]) { $0.trashedAt = nil } } }
                    .font(.caption).padding(10).background(Color.orange.opacity(0.12))
            }
            if model.showTags {
                DraftTagStrip(model: model, session: model.editor)
                Divider()
            }
            ZStack {
                EditorBody(model: model, session: model.editor, fontName: fontName, fontSize: fontSize, lineSpacing: lineSpacing, markdown: note.syntax == "Markdown")
                    .opacity(model.showPreview ? 0 : 1).allowsHitTesting(!model.showPreview)
                    .accessibilityHidden(model.showPreview)
                if let request = model.actionPreview { ActionPreviewPane(request: request) }
                else if model.showPreview { InlineMarkdownPreview(session: model.editor, htmlOverride: model.previewHTML) }
            }
            Divider()
            EditorActionBar(model: model, session: model.editor, library: library)
            Divider()
            EditorFooter(model: model, session: model.editor, library: library)
        }
    }

    private var actionPanel: some View {
        ActionListPanel(model: model, library: library)
    }

    private func count(_ folder: NoteFolder) -> Int { var w = Workspace(name: "Count"); w.folder = folder; return w.filter(library.notes).count }
    private func targets(_ note: Note) -> Set<UUID> { selection.contains(note.id) ? selection : [note.id] }
}

private struct TagGlyph: View {
    let symbol: String
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .font(.system(size: 11, weight: weight))
            .frame(width: 11, height: 11)
            .frame(width: 14, height: 14)
    }
}

private struct EditorBody: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var session: EditorSession
    var fontName: String; var fontSize: Double; var lineSpacing: Double; var markdown: Bool
    var body: some View {
        NativeEditor(session: session, fontName: fontName, fontSize: fontSize, lineSpacing: lineSpacing, markdown: markdown, linksEnabled: model.linksEnabled, isActive: !model.showPreview) { model.contentChanged() }
    }
}
private struct EditorFooter: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var session: EditorSession
    @ObservedObject var library: LibraryStore
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: geometry.size.width < 360 ? 5 : 13) {
                Button { model.isDraftPinned.toggle() } label: { Image(systemName: model.isDraftPinned ? "pin.fill" : "pin").frame(width: 14) }.help("Pin Current Draft")
                Button { model.showInfo = true } label: { Image(systemName: "info.circle").frame(width: 14) }.help("Draft Info")
                Button { model.showHistory = true } label: { Image(systemName: "arrow.uturn.backward").frame(width: 14) }.help("Version History")
                Button { model.showRunLog = true } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 14) }.help("Action Log")
                PanelMenu(symbol: "arrow.up.arrow.down", help: "Arrange", items: [
                    PanelMenuItem(title: "Sort Lines") { model.edit("editor.setText(editor.getText().split('\\n').sort().join('\\n'));") },
                    PanelMenuItem(title: "Reverse Lines") { model.edit("editor.setText(editor.getText().split('\\n').reverse().join('\\n'));") },
                    PanelMenuItem(title: "Remove Empty Lines") { model.edit("editor.setText(editor.getText().split('\\n').filter(x => x.trim()).join('\\n'));") }
                ], symbolSize: 13).frame(width: 16, height: 20)
                Button { model.linksEnabled.toggle() } label: { Image(systemName: "link").frame(width: 14).foregroundStyle(model.linksEnabled ? Color.accentColor : .secondary) }.help("Link Mode")
                Button { model.preview() } label: {
                    Image(systemName: model.showPreview ? "eye.fill" : "eye").frame(width: 14)
                        .foregroundStyle(model.showPreview ? Color.accentColor : .secondary)
                }
                    .help(model.showPreview ? "Edit Markdown (⌥⌘P)" : "Preview Markdown (⌥⌘P)")
                    .accessibilityLabel(model.showPreview ? "Edit Markdown" : "Preview Markdown")
                Spacer(minLength: 0)
                PanelMenu(symbol: "", help: "Syntax Highlighting", items:
                    ["Markdown", "Plain Text"].map { syntax in
                        PanelMenuItem(title: syntax, isOn: model.currentNote?.syntax == syntax) {
                            if let id = session.noteID { model.change([id]) { $0.syntax = syntax } }
                        }
                    }, title: model.currentNote?.syntax ?? "Markdown", showsChevron: false, textSize: geometry.size.width < 360 ? 11 : 12
                ).frame(width: geometry.size.width < 360 ? 58 : 64, height: 20)
                Text("\(session.content.count)c \(session.content.split(whereSeparator: \.isWhitespace).count)w").monospacedDigit().lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
            }.buttonStyle(.plain).font(.system(size: geometry.size.width < 360 ? 11 : 12)).foregroundStyle(.secondary)
                .padding(.horizontal, geometry.size.width < 360 ? 6 : 12).frame(height: 29)
        }.frame(height: 29)
        if !model.status.isEmpty {
            Text(model.status).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(.quaternary.opacity(0.4))
        }
    }
}

func flagColor(_ flag: Int) -> Color {
    switch flag { case 2: .orange; case 3: .yellow; case 4: .green; case 5: .blue; case 6: .purple; default: .red }
}
func flagName(_ flag: Int) -> String {
    switch flag { case 2: "Orange"; case 3: "Yellow"; case 4: "Green"; case 5: "Blue"; case 6: "Purple"; default: "Red" }
}
