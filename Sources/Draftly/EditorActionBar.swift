import SwiftUI
import AppKit
import DraftlyCore

struct ActionBarLabel: Equatable {
    let text: String
    let usesIcon: Bool
    let accessibilityLabel: String

    init(_ action: DraftAction) {
        let label = action.presentation.barLabel ?? ""
        text = label.isEmpty ? action.name : label
        usesIcon = action.presentation.barUsesIcon ?? true
        accessibilityLabel = action.name
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
                ForEach(ActionCatalogPresentation.entries(library.orderedActions(), on: .bar, group: model.actionBarGroup)) { entry in
                    if entry.kind == .separator {
                        Divider().frame(height: 18).help(entry.source.name)
                    } else if let action = entry.runnableAction {
                        configuredActionButton(action)
                            .disabled(!model.canRunActions)
                    }
                }
            }.padding(.horizontal, 12).frame(height: MainWindowStyle.editingBarHeight)
        }.scrollIndicators(.visible).frame(height: MainWindowStyle.editingBarHeight)
            .onChange(of: library.actions) { _, _ in
                if !groups.contains(model.actionBarGroup) { model.actionBarGroup = "Editing" }
            }
    }
    private func configuredActionButton(_ action: DraftAction) -> some View {
        let label = ActionBarLabel(action)
        return Button { model.run(action) } label: {
            Group {
                if label.usesIcon {
                    Image(systemName: action.symbol).font(.system(size: 17, weight: .regular)).frame(width: 22)
                } else {
                    Text(label.text).font(.system(size: 13)).lineLimit(1).fixedSize()
                }
            }.foregroundStyle(ActionTint.color(action.presentation.tintColor) ?? barColor(action.name))
        }.buttonStyle(.plain).help(action.name).accessibilityLabel(label.accessibilityLabel)
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
    func move(_ offset: Int) {
        if let selection = EditorBarTextCommands.move(in: session.content, selection: session.safeSelection, offset: offset) {
            session.selection = selection
        }
        session.focusToken = UUID()
    }
    func moveLine(_ direction: Int) {
        guard let change = EditorBarTextCommands.moveLine(in: session.content, selection: session.safeSelection, direction: direction) else { return }
        session.content = change.content
        session.selection = change.selection
        session.focusToken = UUID()
        model.contentChanged()
    }
    func duplicateLine() {
        guard let change = EditorBarTextCommands.duplicateLine(in: session.content, selection: session.safeSelection) else { return }
        session.content = change.content
        session.selection = change.selection
        session.focusToken = UUID()
        model.contentChanged()
    }
    func moveToMarker(_ direction: Int) {
        guard let selection = EditorBarTextCommands.marker(in: session.content, selection: session.safeSelection, direction: direction) else { return }
        session.selection = selection
        session.focusToken = UUID()
    }
    private func toggleTheme() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        model.darkTheme = !(model.darkTheme ?? isDark)
    }
    private func findItem(replace: Bool = false) -> NSMenuItem { let item = NSMenuItem(); item.tag = (replace ? NSTextFinder.Action.showReplaceInterface : .showFindInterface).rawValue; return item }
}

// Keep unknown imported names in storage. Use the existing surface default.
enum ActionTint {
    static let names = ["none", "gray", "red", "orange", "yellow", "green", "blue", "purple", "pink"]
    static func color(_ name: String?) -> Color? {
        switch name {
        case "none": return .primary
        case "gray": return .gray
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        default: return nil
        }
    }
}
