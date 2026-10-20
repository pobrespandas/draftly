import SwiftUI
import AppKit
import DraftlyCore

struct DraftListPanel: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    @Binding var selection: Set<UUID>
    @AppStorage("list.showPreview") private var storedPreview = true
    @AppStorage("list.previewLines") private var storedLines = 2
    @AppStorage("list.showTags") private var storedTags = true
    @AppStorage("list.showDate") private var storedDate = true
    private var showPreview: Bool {
        get { model.selectedWorkspace == nil ? storedPreview : model.listOptions.showPreview }
        nonmutating set { model.listOptions.showPreview = newValue; if model.selectedWorkspace == nil { storedPreview = newValue } }
    }
    private var previewLines: Int {
        get { model.selectedWorkspace == nil ? storedLines : model.listOptions.previewLines }
        nonmutating set { model.listOptions.previewLines = newValue; if model.selectedWorkspace == nil { storedLines = newValue } }
    }
    private var showTags: Bool {
        get { model.selectedWorkspace == nil ? storedTags : model.listOptions.showTags }
        nonmutating set { model.listOptions.showTags = newValue; if model.selectedWorkspace == nil { storedTags = newValue } }
    }
    private var showDate: Bool {
        get { model.selectedWorkspace == nil ? storedDate : model.listOptions.showDate }
        nonmutating set { model.listOptions.showDate = newValue; if model.selectedWorkspace == nil { storedDate = newValue } }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: MainWindowStyle.utilityLeadingSpacing) {
                PanelMenu(symbol: "chevron.down.circle", help: "Workspaces", items:
                    [PanelMenuItem(title: "Default Workspace") { model.clearFilters(); model.folder = .inbox }]
                    + library.workspaces.map { workspace in PanelMenuItem(title: workspace.name) { model.apply(workspace) } }
                    + [.separator, PanelMenuItem(title: "Save Workspace…") { model.showWorkspaceEditor = true }, PanelMenuItem(title: "Manage Workspaces…") { model.showLibraryManagement = true }]
                ).frame(width: 28, height: 28)
                PanelMenu(symbol: "plus", help: "Add Items", items: [
                    PanelMenuItem(title: "New Draft") { model.create() },
                    PanelMenuItem(title: "Import…") { model.importFile() },
                    PanelMenuItem(title: "New Workspace…") { model.showWorkspaceEditor = true }
                ]).frame(width: 28, height: 28)
                }
                Spacer(minLength: 4)
                HStack(spacing: MainWindowStyle.utilityTrailingSpacing) {
                Button { model.showNoteSearch.toggle(); model.noteSearchFocus = UUID(); if !model.showNoteSearch { model.query = "" } } label: {
                    PanelIcon(symbol: model.showNoteSearch ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                }.help("Search Drafts")
                Button { clearFilters() } label: { PanelIcon(symbol: "xmark.circle") }.help("Clear Filters")
                PanelMenu(symbol: "ellipsis.circle", help: "List Options", items: [
                    PanelMenuItem(title: "Show Preview", isOn: showPreview) { showPreview.toggle() },
                    PanelMenuItem(title: "Preview Lines", children: (1...3).map { count in
                        PanelMenuItem(title: ["One Line", "Two Lines", "Three Lines"][count - 1], isOn: previewLines == count) { previewLines = count }
                    }, action: nil),
                    PanelMenuItem(title: "Show Tags", isOn: showTags) { showTags.toggle() },
                    PanelMenuItem(title: "Show Date", isOn: showDate) { showDate.toggle() },
                    PanelMenuItem(title: "Search Titles Only", isOn: model.listOptions.searchTitlesOnly) { model.listOptions.searchTitlesOnly.toggle() },
                    PanelMenuItem(title: "Case-sensitive Search", isOn: model.listOptions.caseSensitiveSearch) { model.listOptions.caseSensitiveSearch.toggle() },
                    PanelMenuItem(title: "Preview Search Matches", isOn: model.listOptions.previewSearchMatches) { model.listOptions.previewSearchMatches.toggle() },
                    PanelMenuItem(title: "Show Last Action", isOn: model.listOptions.showLastAction) { model.listOptions.showLastAction.toggle() },
                    PanelMenuItem(title: "Highlight Flagged Drafts", isOn: model.listOptions.highlightFlagged) { model.listOptions.highlightFlagged.toggle() },
                    .separator,
                    PanelMenuItem(title: "Save as Workspace…") { model.showWorkspaceEditor = true },
                    PanelMenuItem(title: "Show Filters") { model.setFiltersVisible(true) },
                    PanelMenuItem(title: "Export Backup…") { model.exportBackup() }
                ]).frame(width: 28, height: 28)
                }
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, MainWindowStyle.utilityInset).frame(height: MainWindowStyle.utilityHeight)
            if model.showNoteSearch {
                ReferenceSearchField(text: $model.query, placeholder: "Search Drafts", focusToken: model.noteSearchFocus)
                    .frame(height: 30).padding(.horizontal, 10).padding(.bottom, 6).offset(y: MainWindowStyle.listSearchOffset)
            }
            HStack {
                (Text(model.title).foregroundColor(.secondary)
                    + Text(model.tagFilterSummary == "No tag filters active" ? "" : ": " + model.tagFilterSummary).foregroundColor(.primary))
                    .font(.system(size: 22, weight: .regular)).lineLimit(1)
                Spacer()
            }
                .padding(.horizontal, 16).frame(height: 38)
            FolderControl(folder: $model.folder).frame(height: 28).padding(.horizontal, 10).padding(.bottom, 8).offset(y: MainWindowStyle.listControlOffset)
            HStack {
                Text("\(model.visibleNotes.count) " + (model.visibleNotes.count == 1 ? "draft" : "drafts"))
                Spacer()
                PanelMenu(symbol: "chevron.down", help: "Sort Drafts", items:
                    NoteSort.allCases.map { sort in
                        PanelMenuItem(title: sort.rawValue.capitalized, isOn: model.sort == sort) { model.sort = sort }
                    } + [.separator, PanelMenuItem(title: "Ascending", isOn: model.ascending) { model.ascending.toggle() }],
                    title: "Sort: " + model.sort.rawValue.capitalized + (model.ascending ? " ↑" : " ↓")
                ).frame(width: 116, height: 20)

            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 13).frame(height: 24).offset(y: MainWindowStyle.listControlOffset)
            Divider().offset(y: MainWindowStyle.listControlOffset).zIndex(1)
            if model.visibleNotes.isEmpty {
                PanelEmptyState(message: "No drafts found")
            } else {
                NativeDraftTable(model: model, library: library, selection: $selection,
                                 showPreview: showPreview, previewLines: previewLines,
                                 showTags: showTags, showDate: showDate)
            }
            Divider()
            HStack {
                Button { clearFilters() } label: { Image(systemName: "xmark.circle").font(.system(size: 13)) }.help("Clear Filters")
                Spacer()
                if selection.count > 1 {
                    Text("\(selection.count) selected").font(.caption)
                    Button { model.change(selection) { $0.isArchived = true } } label: { Image(systemName: "archivebox") }.help("Archive Selected")
                    Button { model.change(selection) { $0.trashedAt = Date() } } label: { Image(systemName: "trash") }.help("Trash Selected")
                }
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 60)
        }.background(Color(nsColor: .textBackgroundColor))
    }
    private func clearFilters() { model.clearFilters() }
}

private struct NativeDraftTable: NSViewRepresentable {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    @Binding var selection: Set<UUID>
    var showPreview: Bool
    var previewLines: Int
    var showTags: Bool
    var showDate: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let table = DraftTableView()
        table.headerView = nil
        table.style = .inset
        table.rowSizeStyle = .custom
        table.rowHeight = 56
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.focusRingType = .none
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("draft"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.menuProvider = { [weak coordinator = context.coordinator] table, event, row in
            coordinator?.tableView(table, menuFor: event, at: row)
        }
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        let notes = model.visibleNotes
        let indexes = IndexSet(notes.enumerated().compactMap { selection.contains($0.element.id) ? $0.offset : nil })
        coordinator.synchronizingSelection = true
        defer { coordinator.synchronizingSelection = false }
        if coordinator.notes != notes || coordinator.options != [showPreview ? 1 : 0, previewLines, showTags ? 1 : 0, showDate ? 1 : 0, model.listOptions.showLastAction ? library.runs.count + 1 : 0, model.listOptions.previewSearchMatches ? model.query.hashValue : 0, model.listOptions.highlightFlagged ? 1 : 0] {
            coordinator.notes = notes
            coordinator.options = [showPreview ? 1 : 0, previewLines, showTags ? 1 : 0, showDate ? 1 : 0, model.listOptions.showLastAction ? library.runs.count + 1 : 0, model.listOptions.previewSearchMatches ? model.query.hashValue : 0, model.listOptions.highlightFlagged ? 1 : 0]
            table.reloadData()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<notes.count))
            }
        }
        if table.selectedRowIndexes != indexes { table.selectRowIndexes(indexes, byExtendingSelection: false) }
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeDraftTable
        weak var table: NSTableView?
        var notes: [Note] = []
        var options: [Int] = []
        var synchronizingSelection = false
        init(_ parent: NativeDraftTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.model.visibleNotes.count }
        func tableViewColumnDidResize(_ notification: Notification) {
            guard let table else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<table.numberOfRows))
            }
        }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard parent.model.visibleNotes.indices.contains(row) else { return 56 }
            let note = parent.model.visibleNotes[row]
            return DraftRowPresentation.height(note: note, width: max(80, tableView.bounds.width - 44),
                showPreview: parent.showPreview, previewLines: parent.previewLines,
                showTags: parent.showTags, showDate: parent.showDate,
                lastAction: parent.model.listOptions.showLastAction && parent.library.runs.contains(where: { $0.noteID == note.id }),
                query: parent.model.listOptions.previewSearchMatches ? parent.model.query : "")
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let notes = parent.model.visibleNotes
            guard notes.indices.contains(row) else { return nil }
            let id = NSUserInterfaceItemIdentifier("DraftCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? DraftHostingCell) ?? DraftHostingCell(identifier: id)
            let note = notes[row]
            cell.host.rootView = DraftTableRow(note: note,
                title: note.id == parent.model.editor.noteID && !parent.library.notes.contains(where: { $0.id == note.id }) && note.content.isEmpty ? "—blank—" : note.title,
                showPreview: parent.showPreview, previewLines: parent.previewLines,
                showTags: parent.showTags, showDate: parent.showDate,
                query: parent.model.listOptions.previewSearchMatches ? parent.model.query : "",
                lastAction: parent.model.listOptions.showLastAction ? parent.library.runs.first(where: { $0.noteID == note.id }).map { $0.actionName + " · " + $0.status } : nil,
                highlightFlagged: parent.model.listOptions.highlightFlagged, emphasized: cell.backgroundStyle == .emphasized)
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table, !synchronizingSelection else { return }
            let notes = parent.model.visibleNotes
            parent.selection = Set(table.selectedRowIndexes.compactMap { notes.indices.contains($0) ? notes[$0].id : nil })
            if parent.selection.count == 1 { parent.model.select(parent.selection.first, focusEditor: false) }
            table.window?.makeFirstResponder(table)
        }
        func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard edge == .trailing, parent.model.visibleNotes.indices.contains(row) else { return [] }
            let id = parent.model.visibleNotes[row].id
            return parent.model.swipeCommands(for: id).map { $0.nativeAction(model: parent.model, table: tableView) }
        }
        func tableView(_ tableView: NSTableView, menuFor event: NSEvent, at row: Int) -> NSMenu? {
            let notes = parent.model.visibleNotes
            guard notes.indices.contains(row) else { return nil }
            let ids = parent.model.contextTargets(rowID: notes[row].id, selection: parent.selection)
            return parent.model.draftContextMenu(ids: ids)
        }
    }
}

private final class DraftTableView: NSTableView {
    var menuProvider: ((NSTableView, NSEvent, Int) -> NSMenu?)?
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        return menuProvider?(self, event, row)
    }
}

private final class DraftHostingCell: NSTableCellView {
    let host = NSHostingView(rootView: DraftTableRow(note: Note(), title: "", showPreview: true, previewLines: 2, showTags: true, showDate: true))
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { host.rootView.emphasized = backgroundStyle == .emphasized }
    }
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            host.topAnchor.constraint(equalTo: topAnchor, constant: DraftRowPresentation.verticalInset),
            host.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DraftRowPresentation.bottomInset)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct DraftTableRow: View {
    var note: Note
    var title: String
    var showPreview: Bool
    var previewLines: Int
    var showTags: Bool
    var showDate: Bool
    var query = ""
    var lastAction: String?
    var highlightFlagged = false
    var emphasized = false
    private var previewText: String { DraftRowPresentation.preview(note, query: query) }
    private var primaryText: Color { emphasized ? .white : .primary }
    private var secondaryText: Color { emphasized ? .white.opacity(0.68) : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: DraftRowPresentation.contentSpacing) {
            HStack(spacing: 5) {
                Text(title).font(Font(DraftRowPresentation.titleFont)).foregroundStyle(primaryText).lineLimit(1)
                Spacer(minLength: 3)
                if note.flag > 0 { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(flagColor(note.flag)) }
            }.frame(height: DraftRowPresentation.titleHeight)
            if showPreview && !previewText.isEmpty {
                Text(previewText).font(Font(DraftRowPresentation.previewFont(query: query))).foregroundStyle(secondaryText).lineLimit(min(3, max(1, previewLines))).fixedSize(horizontal: false, vertical: true)
            }
            if showTags && !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags, id: \.self) { tag in
                        Text(tag).font(Font(DraftRowPresentation.tagFont)).foregroundStyle(primaryText).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 6).fill((emphasized ? Color.white.opacity(0.08) : Color.accentColor.opacity(0.1))))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke((emphasized ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.25)), lineWidth: 0.5))
                    }
                }.frame(height: DraftRowPresentation.tagHeight).padding(.top, DraftRowPresentation.tagTopInset)
            }
            if let lastAction { Text(lastAction).font(.system(size: 10)).foregroundStyle(secondaryText).lineLimit(1) }
            if showDate {
                HStack {
                    Spacer(minLength: 0)
                    Text("Modified: " + DraftRowPresentation.modifiedDate(note.modifiedAt))
                        .font(Font(DraftRowPresentation.dateFont)).foregroundStyle(emphasized ? Color.white.opacity(0.42) : Color.secondary.opacity(0.65)).lineLimit(1)
                }.frame(height: DraftRowPresentation.dateHeight).padding(.top, DraftRowPresentation.dateTopInset)
                    .offset(y: DraftRowPresentation.dateBaselineOffset)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
            .overlay { if highlightFlagged && note.flag > 0 { RoundedRectangle(cornerRadius: 6).strokeBorder(flagColor(note.flag).opacity(0.6), lineWidth: 1).allowsHitTesting(false) } }
            .overlay(alignment: .bottom) {
                GeometryReader { geometry in
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
                    }
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), style: StrokeStyle(lineWidth: 0.5, dash: [1, 1]))
                }
                .frame(height: 1).offset(y: 6).opacity(emphasized ? 0 : 1).allowsHitTesting(false)
            }
    }
}

struct ActionListPanel: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    private var groups: [String] { library.groupNames }
    private var actions: [DraftAction] {
        library.orderedActions(on: model.actionQuery.isEmpty ? .list : .search).filter {
            (!model.actionQuery.isEmpty || model.actionGroup == "All Actions" || $0.group == model.actionGroup)
                && (model.actionQuery.isEmpty || $0.name.localizedStandardContains(model.actionQuery) || $0.presentation.description.localizedStandardContains(model.actionQuery))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: MainWindowStyle.utilityLeadingSpacing) {
                PanelMenu(symbol: "chevron.down.circle", help: "Action Groups", items:
                    [PanelMenuItem(title: "All Actions") { model.actionGroup = "All Actions" }]
                    + groups.map { group in PanelMenuItem(title: group) { model.actionGroup = group } }
                ).frame(width: 28, height: 28)
                PanelMenu(symbol: "plus", help: "Add Actions", items: [
                    PanelMenuItem(title: "New Action…") { newAction() },
                    PanelMenuItem(title: "Import from Directory…") { model.showActionImporter = true },
                    PanelMenuItem(title: "Import File…") { model.importFile() },
                    PanelMenuItem(title: "Manage Groups…") { model.showLibraryManagement = true }
                ]).frame(width: 28, height: 28)
                }
                Spacer(minLength: 4)
                HStack(spacing: MainWindowStyle.utilityTrailingSpacing) {
                Button { model.showActionSearch.toggle(); model.actionSearchFocus = UUID(); if !model.showActionSearch { model.actionQuery = "" } } label: { PanelIcon(symbol: model.showActionSearch ? "magnifyingglass.circle.fill" : "magnifyingglass.circle") }.help("Search Actions")
                Button { model.showRunLog = true } label: { PanelIcon(symbol: "clock.arrow.circlepath") }.help("Action Log")
                PanelMenu(symbol: "ellipsis.circle", help: "Action List Options", items: [
                    PanelMenuItem(title: "Import from Directory…") { model.showActionImporter = true },
                    PanelMenuItem(title: "Execution History…") { model.showRunLog = true }
                ]).frame(width: 28, height: 28)
                }
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, MainWindowStyle.utilityInset).frame(height: MainWindowStyle.utilityHeight)
            if model.showActionSearch {
                ReferenceSearchField(text: $model.actionQuery, placeholder: "Search Actions", focusToken: model.actionSearchFocus)
                    .frame(height: 28).padding(.horizontal, 10).padding(.bottom, 8)
            }
            HStack(spacing: 9) {
                Image(systemName: model.actionQuery.isEmpty ? "arrow.up.right.square" : "magnifyingglass").font(.system(size: 18, weight: model.actionQuery.isEmpty ? .regular : .semibold)).foregroundStyle(.blue)
                Text(model.actionQuery.isEmpty ? model.actionGroup : "Search").font(.system(size: 22, weight: .regular)).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 13).frame(height: 38)
            Divider()
            if actions.isEmpty {
                PanelEmptyState(message: "No actions found")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            if !action.presentation.section.isEmpty && (index == 0 || actions[index - 1].presentation.section != action.presentation.section) {
                                Text(action.presentation.section).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 6)
                            }
                            Button { model.run(action) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: action.unsupportedSteps.isEmpty ? action.symbol : "exclamationmark.triangle")
                                        .font(.system(size: 18, weight: .regular)).frame(width: 21).foregroundStyle(actionColor(action))
                                    Text(action.name).font(.system(size: MainWindowStyle.actionTitleSize)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 20).frame(height: 28).contentShape(Rectangle())
                            }.buttonStyle(ActionRowButtonStyle()).disabled(model.currentNote == nil || model.runner.isRunning)
                                .contextMenu {
                                    Button("Edit…") { model.editingAction = action }
                                    Button("Duplicate") { var copy = action; copy.id = UUID(); copy.name += " Copy"; model.editingAction = copy }
                                    Divider()
                                    Button("Delete", role: .destructive) { model.perform { try library.deleteAction(action.id) } }
                                }
                        }
                    }.padding(.top, 10)
                }
            }
            Divider()
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(Array(groups.enumerated()), id: \.element) { index, group in
                        Button { model.actionGroup = group } label: {
                            Image(systemName: library.actionGroups.first(where: { $0.name == group })?.symbol ?? "arrow.up.right.square")
                                .font(.system(size: 18)).foregroundStyle(model.actionGroup == group ? Color.blue : .secondary)
                        }.buttonStyle(.plain).help(group).accessibilityLabel(group)
                    }
                }.padding(.horizontal, 16).frame(height: 60)
            }.scrollIndicators(.hidden)
        }.background(Color(nsColor: .textBackgroundColor))
        .onChange(of: library.actions) { _, _ in if !groups.contains(model.actionGroup), model.actionGroup != "All Actions" { model.actionGroup = groups.first ?? "General" } }
    }
    private func actionColor(_ action: DraftAction) -> Color {
        if !action.unsupportedSteps.isEmpty { return .orange }
        if action.steps.first?.type == "file" { return .orange }
        if action.steps.first?.type == "reminder" { return .secondary }
        return .blue
    }
    private func newAction() {
        var action = DraftAction(name: "New Action", steps: [ActionStep("clipboard", ["template": "[[draft]]"])])
        action.group = model.actionGroup == "All Actions" ? "General" : model.actionGroup
        model.editingAction = action
    }
}

struct EditorActionBar: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var session: EditorSession
    @ObservedObject var library: LibraryStore
    private var groups: [String] { ["Editing"] + library.groupNames.filter { $0 != "Editing" } }
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                PanelMenu(symbol: model.actionBarGroup == "Editing" ? "character.cursor.ibeam" : "arrow.up.right.square", help: "Select Action Group", items:
                    groups.map { group in PanelMenuItem(title: group, isOn: model.actionBarGroup == group) { model.actionBarGroup = group } }
                    + [.separator, PanelMenuItem(title: "Import Action Group…") { model.showActionImporter = true }],
                    symbolSize: 21
                ).frame(width: 28, height: 28)
                if model.actionBarGroup == "Editing" {
                    barButton("Undo", "arrow.uturn.backward") { NSApp.sendAction(NSSelectorFromString("undo:"), to: nil, from: nil) }
                    barButton("Redo", "arrow.uturn.forward") { NSApp.sendAction(NSSelectorFromString("redo:"), to: nil, from: nil) }
                    barButton("Move Left", "chevron.left") { move(-1) }
                    barButton("Move Right", "chevron.right") { move(1) }
                    barButton("Move Back by Word", "chevron.left.2") { NSApp.sendAction(NSSelectorFromString("moveWordLeft:"), to: nil, from: nil) }
                    barButton("Move Forward by Word", "chevron.right.2") { NSApp.sendAction(NSSelectorFromString("moveWordRight:"), to: nil, from: nil) }
                    barButton("Find", "magnifyingglass") { model.perform { _ = try model.actionUIOperation(["operation": "showFind", "args": []]) } }
                    barButton("Advanced Find", "plus.magnifyingglass") { model.perform { _ = try model.actionUIOperation(["operation": "showFind", "args": [true]]) } }
                    barButton("Make Tasks", "checkmark.square") { model.edit(EditingScripts.makeTasks) }
                    barButton("Toggle Tasks", "checklist") { model.edit(EditingScripts.toggleTasks) }
                    barButton("Insert Date", "calendar.badge.plus") { model.edit(EditingScripts.insertDate) }
                    barButton("Insert Dictation", "mic.badge.plus") { model.perform { _ = try model.actionUIOperation(["operation": "showDictate"]) } }
                    barButton("Dictate New Draft", "mic") { if model.create() { model.perform { _ = try model.actionUIOperation(["operation": "showDictate"]) } } }
                    barButton("Copy Selection", "doc.on.doc") { model.perform { _ = try model.host.perform("clipboard", values: ["text": session.selectedText.isEmpty ? session.content : session.selectedText]) } }
                    barButton("Paste as Plain Text", "doc.on.clipboard") { NSApp.sendAction(NSSelectorFromString("pasteAsPlainText:"), to: nil, from: nil) }
                    barButton("Indent", "increase.indent") { model.edit(EditingScripts.indent) }
                    barButton("Outdent", "decrease.indent") { model.edit(EditingScripts.outdent) }
                    barButton("Move Line Up", "arrow.up.to.line") { moveLine(-1) }
                    barButton("Move Line Down", "arrow.down.to.line") { moveLine(1) }
                    barButton("Duplicate Line", "plus.square.on.square") { duplicateLine() }
                    barButton("Previous Marker", "arrow.up.to.line.compact") { moveToMarker(-1) }
                    barButton("Next Marker", "arrow.down.to.line.compact") { moveToMarker(1) }
                    barButton("Toggle Theme", "circle.lefthalf.filled") { toggleTheme() }
                    barButton("Preview", "eye") { model.preview() }
                }
                ForEach(library.orderedActions(on: .bar).filter { $0.group == model.actionBarGroup }) { action in
                    barButton(action.name, action.symbol) { model.run(action) }
                        .disabled(model.runner.isRunning)
                }
            }.padding(.horizontal, 12).frame(height: MainWindowStyle.editingBarHeight)
        }.scrollIndicators(.visible).frame(height: MainWindowStyle.editingBarHeight)
            .onChange(of: library.actions) { _, _ in
                if !groups.contains(model.actionBarGroup) { model.actionBarGroup = "Editing" }
            }
    }
    private func barButton(_ name: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(barColor(name)).frame(width: 22) }.buttonStyle(.plain).help(name).accessibilityLabel(name)
    }
    private func barColor(_ name: String) -> Color {
        if ["Move Left", "Move Right"].contains(name) { return .yellow }
        if name.contains("Word") || name == "Indent" || name == "Outdent" { return .orange }
        if name == "Toggle Tasks" { return .purple }
        if name.contains("Find") || name.contains("Dictat") { return .green }
        return .blue
    }
    private func move(_ offset: Int) {
        let source = session.content as NSString
        let range = session.safeSelection
        if offset < 0, range.location > 0 { session.selection = NSRange(location: source.rangeOfComposedCharacterSequence(at: range.location - 1).location, length: 0) }
        else if offset > 0, NSMaxRange(range) < source.length { session.selection = NSRange(location: NSMaxRange(source.rangeOfComposedCharacterSequence(at: NSMaxRange(range))), length: 0) }
        session.focusToken = UUID()
    }
    private func moveLine(_ direction: Int) {
        let source = session.content as NSString
        guard source.length > 0 else { return }
        let selected = session.safeSelection
        let block = source.lineRange(for: NSRange(location: selected.location, length: selected.length))
        if direction < 0 {
            guard block.location > 0 else { return }
            let previous = source.lineRange(for: NSRange(location: block.location - 1, length: 0))
            let text = source.substring(with: previous) + source.substring(with: block)
            session.content = source.replacingCharacters(in: NSRange(location: previous.location, length: NSMaxRange(block) - previous.location), with: text)
            session.selection = NSRange(location: max(0, selected.location - previous.length), length: selected.length)
        } else {
            guard NSMaxRange(block) < source.length else { return }
            let next = source.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            let text = source.substring(with: next) + source.substring(with: block)
            session.content = source.replacingCharacters(in: NSRange(location: block.location, length: NSMaxRange(next) - block.location), with: text)
            session.selection = NSRange(location: selected.location + next.length, length: selected.length)
        }
        session.focusToken = UUID()
        model.contentChanged()
    }
    private func duplicateLine() {
        let source = session.content as NSString
        guard source.length > 0 else { return }
        let selected = session.safeSelection
        let line = source.lineRange(for: NSRange(location: selected.location, length: selected.length))
        let duplicate = source.substring(with: line)
        let insertion = NSMaxRange(line)
        session.content = source.replacingCharacters(in: NSRange(location: insertion, length: 0), with: duplicate)
        session.selection = NSRange(location: insertion, length: (duplicate as NSString).length)
        session.focusToken = UUID()
        model.contentChanged()
    }
    private func moveToMarker(_ direction: Int) {
        let source = session.content as NSString
        guard let regex = try? NSRegularExpression(pattern: "(?m)^#{1,6}\\s+.+$") else { return }
        let matches = regex.matches(in: session.content, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return }
        let current = session.safeSelection.location
        let target = direction < 0
            ? (matches.last { $0.range.location < current } ?? matches.last!)
            : (matches.first { $0.range.location > current } ?? matches.first!)
        session.selection = target.range
        session.focusToken = UUID()
    }
    private func toggleTheme() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        model.darkTheme = !(model.darkTheme ?? isDark)
    }
    private func findItem(replace: Bool = false) -> NSMenuItem { let item = NSMenuItem(); item.tag = (replace ? NSTextFinder.Action.showReplaceInterface : .showFindInterface).rawValue; return item }
}

struct CommandPalette: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool
    private var actions: [DraftAction] { library.orderedActions(on: .search).filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.presentation.description.localizedStandardContains(query) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find an action…", text: $query).textFieldStyle(.plain).font(.title3).focused($focused)
                    .onSubmit { if let action = actions.first { dismiss(); model.run(action) } }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            List(actions) { action in
                Button { dismiss(); model.run(action) } label: {
                    HStack(spacing: 12) { Image(systemName: action.symbol).foregroundStyle(.tint).frame(width: 22); Text(action.name); Spacer(); Text(action.group).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.frame(width: 560, height: 400).onAppear { focused = true }
    }
}

private struct PanelEmptyState: View {
    var message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "curlybraces").font(.system(size: 32, weight: .light))
            Text(message).font(.system(size: 13))
        }
        .foregroundStyle(.secondary).padding(.top, 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ActionRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Interaction(configuration: configuration) }
    private struct Interaction: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false
        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.12 : isHovered ? 0.055 : 0) : 0))
                        .padding(.horizontal, 12)
                }
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
        }
    }
}
