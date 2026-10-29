import SwiftUI
import AppKit
@_spi(DraftlyInternal) import DraftlyCore

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
    private var groups: [String] { ["Editing"] + library.groupNames(on: .bar).filter { $0 != "Editing" } }
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                PanelMenu(symbol: model.actionBarGroup == "Editing" ? "character.cursor.ibeam" : "arrow.up.right.square", help: "Select Action Group", items:
                    groups.map { group in PanelMenuItem(title: group, isOn: model.actionBarGroup == group) { model.actionBarGroup = group } }
                    + [.separator, PanelMenuItem(title: "Import Action Group…") { model.showActionImporter = true }],
                    symbolSize: 21
                ).frame(width: 28, height: 28)
                if model.actionBarGroup == "Editing" {
                    ForEach(EditorBarCommand.allCases, id: \.self) { command in
                        barButton(command.title, command.symbol) { command.perform(model: model, session: session) }
                    }
                }
                ForEach(ActionCatalogPresentation.entries(library.orderedActions(on: .bar), on: .bar, group: model.actionBarGroup)) { entry in
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
            .onChange(of: library.actionGroups) { _, _ in
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
    func move(_ offset: Int) { EditorBarCommand.move(offset, session: session) }
    func moveLine(_ direction: Int) { EditorBarCommand.moveLine(direction, model: model, session: session) }
    func duplicateLine() { EditorBarCommand.duplicateLine(model: model, session: session) }
    func moveToMarker(_ direction: Int) { EditorBarCommand.moveToMarker(direction, model: model, session: session) }

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
