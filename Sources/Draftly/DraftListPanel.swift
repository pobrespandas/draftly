import SwiftUI
import AppKit
import DraftlyCore

struct DraftListPanel: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    @Binding var selection: Set<UUID>
    private var showPreview: Bool {
        get { model.listOptions.showPreview }
        nonmutating set { model.listOptions.showPreview = newValue }
    }
    private var previewLines: Int {
        get { model.listOptions.previewLines }
        nonmutating set { model.listOptions.previewLines = newValue }
    }
    private var showTags: Bool {
        get { model.listOptions.showTags }
        nonmutating set { model.listOptions.showTags = newValue }
    }
    private var showDate: Bool {
        get { model.listOptions.showDate }
        nonmutating set { model.listOptions.showDate = newValue }
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

struct NativeDraftTable: NSViewRepresentable {
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
        func numberOfRows(in tableView: NSTableView) -> Int { notes.count }
        func tableViewColumnDidResize(_ notification: Notification) {
            guard let table else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<table.numberOfRows))
            }
        }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard notes.indices.contains(row) else { return 56 }
            let note = notes[row]
            return DraftRowPresentation.height(note: note, width: max(80, tableView.bounds.width - 44),
                showPreview: parent.showPreview, previewLines: parent.previewLines,
                showTags: parent.showTags, showDate: parent.showDate,
                lastAction: parent.model.listOptions.showLastAction && parent.library.runs.contains(where: { $0.noteID == note.id }),
                query: parent.model.listOptions.previewSearchMatches ? parent.model.query : "")
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
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
            parent.selection = Set(table.selectedRowIndexes.compactMap { notes.indices.contains($0) ? notes[$0].id : nil })
            if parent.selection.count == 1 { parent.model.select(parent.selection.first, focusEditor: false) }
            table.window?.makeFirstResponder(table)
        }
        func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard edge == .trailing, notes.indices.contains(row) else { return [] }
            let id = notes[row].id
            return parent.model.swipeCommands(for: id).map { $0.nativeAction(model: parent.model, table: tableView) }
        }
        func tableView(_ tableView: NSTableView, menuFor event: NSEvent, at row: Int) -> NSMenu? {
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
        // The table owns row dimensions. Content must not add sizing constraints.
        host.sizingOptions = []
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

struct DraftTableRow: View {
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
                if note.flag > 0 { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(emphasized ? .white : flagColor(note.flag)) }
            }.frame(height: DraftRowPresentation.titleHeight)
            if showPreview && !previewText.isEmpty {
                Text(previewText).font(Font(DraftRowPresentation.previewFont(query: query))).foregroundStyle(secondaryText).lineLimit(min(3, max(1, previewLines))).fixedSize(horizontal: false, vertical: true)
            }
            if showTags && !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags, id: \.self) { tag in
                        Text(tag).font(Font(DraftRowPresentation.tagFont)).foregroundStyle(primaryText).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 6).fill((emphasized ? Color.clear : Color.accentColor.opacity(0.1))))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke((emphasized ? Color.white.opacity(0.65) : Color.accentColor.opacity(0.25)), lineWidth: 0.5))
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
