import SwiftUI
import AppKit
import DraftlyCore

struct DraftListPanel: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    @Binding var selection: Set<UUID>
    @AppStorage("list.showPreview") private var showPreview = true
    @AppStorage("list.previewLines") private var previewLines = 2
    @AppStorage("list.showTags") private var showTags = true
    @AppStorage("list.showDate") private var showDate = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 20) {
                PanelMenu(symbol: "chevron.down.circle", help: "Workspaces", items:
                    [PanelMenuItem(title: "Default Workspace") { model.clearFilters(); model.folder = .inbox }]
                    + library.workspaces.map { workspace in PanelMenuItem(title: workspace.name) { model.apply(workspace) } }
                    + [.separator, PanelMenuItem(title: "Save Workspace…") { model.showWorkspaceEditor = true }]
                ).frame(width: 28, height: 28)
                PanelMenu(symbol: "plus", help: "Add Items", items: [
                    PanelMenuItem(title: "New Draft") { model.create() },
                    PanelMenuItem(title: "Import…") { model.importFile() },
                    PanelMenuItem(title: "New Workspace…") { model.showWorkspaceEditor = true }
                ]).frame(width: 28, height: 28)
                }
                Spacer(minLength: 4)
                HStack(spacing: 8) {
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
                    .separator,
                    PanelMenuItem(title: "Save as Workspace…") { model.showWorkspaceEditor = true },
                    PanelMenuItem(title: "Show Filters") { model.setFiltersVisible(true) },
                    PanelMenuItem(title: "Export Backup…") { model.exportBackup() }
                ]).frame(width: 28, height: 28)
                }
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 48)
            if model.showNoteSearch {
                ReferenceSearchField(text: $model.query, placeholder: "Search Drafts", focusToken: model.noteSearchFocus)
                    .frame(height: 28).padding(.horizontal, 10).padding(.bottom, 8)
            }
            HStack { Text(model.title).font(.system(size: 22, weight: .regular)).foregroundStyle(.secondary); Spacer() }
                .padding(.horizontal, 16).frame(height: 38)
            FolderControl(folder: $model.folder).frame(height: 28).padding(.horizontal, 10).padding(.bottom, 8)
            HStack {
                Text("\(model.visibleNotes.count) drafts")
                Spacer()
                PanelMenu(symbol: "chevron.down", help: "Sort Drafts", items:
                    NoteSort.allCases.map { sort in
                        PanelMenuItem(title: sort.rawValue.capitalized, isOn: model.sort == sort) { model.sort = sort }
                    } + [.separator, PanelMenuItem(title: "Ascending", isOn: model.ascending) { model.ascending.toggle() }],
                    title: "Sort: " + model.sort.rawValue.capitalized + (model.ascending ? " ↑" : " ↓")
                ).frame(width: 116, height: 20)

            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 13).frame(height: 24)
            Divider()
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
        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 66
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = [.solidHorizontalGridLineMask]
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.focusRingType = .none
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("draft"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.noteIDs != model.visibleNotes.map(\.id) {
            coordinator.noteIDs = model.visibleNotes.map(\.id)
            table.reloadData()
        } else {
            table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<table.numberOfRows), columnIndexes: IndexSet(integer: 0))
        }
        let indexes = IndexSet(model.visibleNotes.enumerated().compactMap { selection.contains($0.element.id) ? $0.offset : nil })
        if table.selectedRowIndexes != indexes { table.selectRowIndexes(indexes, byExtendingSelection: false) }
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeDraftTable
        weak var table: NSTableView?
        var noteIDs: [UUID] = []
        private var menuActions: [MenuAction] = []
        init(_ parent: NativeDraftTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.model.visibleNotes.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let notes = parent.model.visibleNotes
            guard notes.indices.contains(row) else { return nil }
            let id = NSUserInterfaceItemIdentifier("DraftCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? DraftHostingCell) ?? DraftHostingCell(identifier: id)
            let note = notes[row]
            cell.host.rootView = DraftTableRow(note: note,
                title: note.id == parent.model.editor.noteID && !parent.library.notes.contains(where: { $0.id == note.id }) && note.content.isEmpty ? "—blank—" : note.title,
                showPreview: parent.showPreview, previewLines: parent.previewLines,
                showTags: parent.showTags, showDate: parent.showDate)
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table else { return }
            let notes = parent.model.visibleNotes
            parent.selection = Set(table.selectedRowIndexes.compactMap { notes.indices.contains($0) ? notes[$0].id : nil })
        }
        func tableView(_ tableView: NSTableView, menuFor event: NSEvent, at row: Int) -> NSMenu? {
            let notes = parent.model.visibleNotes
            guard notes.indices.contains(row) else { return nil }
            let note = notes[row]
            let targets = parent.selection.contains(note.id) ? parent.selection : [note.id]
            let menu = NSMenu()
            menuActions = []
            func add(_ title: String, _ action: @escaping () -> Void) {
                let item = NSMenuItem(title: title, action: #selector(MenuAction.invoke(_:)), keyEquivalent: "")
                let target = MenuAction(action)
                menuActions.append(target)
                item.target = target
                menu.addItem(item)
            }
            add(note.isArchived ? "Move to Inbox" : "Archive") { self.parent.model.change(targets) { $0.isArchived.toggle() } }
            add(note.flag > 0 ? "Remove Flag" : "Flag") { self.parent.model.change(targets) { $0.flag = $0.flag > 0 ? 0 : 1 } }
            add(note.trashedAt == nil ? "Move to Trash" : "Restore") { self.parent.model.change(targets) { $0.trashedAt = $0.trashedAt == nil ? Date() : nil } }
            menu.addItem(.separator())
            add("Duplicate") { self.parent.model.perform { _ = try self.parent.library.createNote(content: note.content, tags: note.tags) } }
            return menu
        }
    }
}

private final class DraftHostingCell: NSTableCellView {
    let host = NSHostingView(rootView: DraftTableRow(note: Note(), title: "", showPreview: true, previewLines: 2, showTags: true, showDate: true))
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            host.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            host.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 3)
                if note.flag > 0 { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(flagColor(note.flag)) }
            }
            if showPreview && !note.preview.isEmpty {
                Text(note.preview).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(min(3, max(1, previewLines)))
            }
            if showDate || showTags {
                HStack(spacing: 6) {
                    if showDate { Text(note.modifiedAt, style: .relative) }
                    Spacer(minLength: 0)
                    if showTags { Text(note.tags.map { "#" + $0 }.joined(separator: " ")).lineLimit(1) }
                }.font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

@MainActor private final class MenuAction: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke(_ sender: Any?) { action() }
}

struct ActionListPanel: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    private var groups: [String] { Array(Set(library.actions.map(\.group))).sorted() }
    private var actions: [DraftAction] {
        let preferred = ["Copy", "Share", "Add to Reminders", "Add Calendar Event", "Save to File", "Markdown Preview"]
        return library.actions.filter { (!model.actionQuery.isEmpty || model.actionGroup == "All Actions" || $0.group == model.actionGroup) && (model.actionQuery.isEmpty || $0.name.localizedStandardContains(model.actionQuery)) }
            .sorted { a, b in
                let x = preferred.firstIndex(of: a.name) ?? 100
                let y = preferred.firstIndex(of: b.name) ?? 100
                return x == y ? a.name.localizedStandardCompare(b.name) == .orderedAscending : x < y
            }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 20) {
                PanelMenu(symbol: "chevron.down.circle", help: "Action Groups", items:
                    [PanelMenuItem(title: "All Actions") { model.actionGroup = "All Actions" }]
                    + groups.map { group in PanelMenuItem(title: group) { model.actionGroup = group } }
                ).frame(width: 28, height: 28)
                PanelMenu(symbol: "plus", help: "Add Actions", items: [
                    PanelMenuItem(title: "New Action…") { newAction() },
                    PanelMenuItem(title: "Import from Directory…") { model.showActionImporter = true },
                    PanelMenuItem(title: "Import File…") { model.importFile() }
                ]).frame(width: 28, height: 28)
                }
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                Button { model.showActionSearch.toggle(); model.actionSearchFocus = UUID(); if !model.showActionSearch { model.actionQuery = "" } } label: { PanelIcon(symbol: model.showActionSearch ? "magnifyingglass.circle.fill" : "magnifyingglass.circle") }.help("Search Actions")
                Button { model.showRunLog = true } label: { PanelIcon(symbol: "clock.arrow.circlepath") }.help("Action Log")
                PanelMenu(symbol: "ellipsis.circle", help: "Action List Options", items: [
                    PanelMenuItem(title: "Import from Directory…") { model.showActionImporter = true },
                    PanelMenuItem(title: "Execution History…") { model.showRunLog = true }
                ]).frame(width: 28, height: 28)
                }
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 48)
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
                        ForEach(actions) { action in
                            Button { model.run(action) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: action.unsupportedSteps.isEmpty ? action.symbol : "exclamationmark.triangle")
                                        .font(.system(size: 18, weight: .regular)).frame(width: 21).foregroundStyle(actionColor(action))
                                    Text(action.name).font(.system(size: 14)).lineLimit(1)
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
                            Image(systemName: index == 0 ? "arrow.up.right.square" : "square.and.arrow.down")
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
    private var groups: [String] { ["Editing"] + Set(library.actions.map(\.group)).filter { $0 != "Editing" }.sorted() }
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
                    barButton("Move Line Up", "arrow.up.to.line") { moveLine(-1) }
                    barButton("Move Line Down", "arrow.down.to.line") { moveLine(1) }
                    barButton("Duplicate Line", "plus.square.on.square") { duplicateLine() }
                    barButton("Previous Marker", "arrow.up.to.line.compact") { moveToMarker(-1) }
                    barButton("Next Marker", "arrow.down.to.line.compact") { moveToMarker(1) }
                    barButton("Toggle Theme", "circle.lefthalf.filled") { toggleTheme() }
                    barButton("Move Back by Word", "chevron.left.2") { NSApp.sendAction(NSSelectorFromString("moveWordLeft:"), to: nil, from: nil) }
                    barButton("Move Forward by Word", "chevron.right.2") { NSApp.sendAction(NSSelectorFromString("moveWordRight:"), to: nil, from: nil) }
                    barButton("Find", "magnifyingglass") { NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: findItem()) }
                    barButton("Advanced Find", "plus.magnifyingglass") { NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: findItem(replace: true)) }
                    barButton("Make Tasks", "checkmark.square") { model.edit(EditingScripts.makeTasks) }
                    barButton("Toggle Tasks", "checklist") { model.edit(EditingScripts.toggleTasks) }
                    barButton("Insert Date", "calendar.badge.plus") { model.edit(EditingScripts.insertDate) }
                    barButton("Insert Dictation", "mic.badge.plus") { NSApp.sendAction(NSSelectorFromString("startDictation:"), to: nil, from: nil) }
                    barButton("Dictate New Draft", "mic") { model.create(); DispatchQueue.main.async { NSApp.sendAction(NSSelectorFromString("startDictation:"), to: nil, from: nil) } }
                    barButton("Indent", "increase.indent") { model.edit(EditingScripts.indent) }
                    barButton("Outdent", "decrease.indent") { model.edit(EditingScripts.outdent) }
                    barButton("Copy Selection", "doc.on.doc") { model.perform { _ = try model.host.perform("clipboard", values: ["text": session.selectedText.isEmpty ? session.content : session.selectedText]) } }
                    barButton("Paste as Plain Text", "doc.on.clipboard") { NSApp.sendAction(NSSelectorFromString("pasteAsPlainText:"), to: nil, from: nil) }
                    barButton("Preview", "eye") { model.preview() }
                }
                ForEach(library.actions.filter { $0.group == model.actionBarGroup }) { action in
                    barButton(action.name, action.symbol) { model.run(action) }
                        .disabled(model.runner.isRunning)
                }
            }.padding(.horizontal, 12).frame(height: 31)
        }.scrollIndicators(.hidden).frame(height: 31)
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
    private var actions: [DraftAction] { library.actions.filter { query.isEmpty || $0.name.localizedStandardContains(query) } }
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
