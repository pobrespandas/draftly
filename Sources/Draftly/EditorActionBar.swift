import SwiftUI
import AppKit
@_spi(DraftlyInternal) import DraftlyCore

struct ActionBarLabel: Equatable {
    let text: String
    let usesIcon: Bool
    let showsText: Bool
    let accessibilityLabel: String

    init(_ action: DraftAction) {
        let label = action.presentation.barLabel ?? ""
        text = label.isEmpty ? action.name : label
        usesIcon = action.presentation.barUsesIcon ?? true
        showsText = !usesIcon || !label.isEmpty
        accessibilityLabel = action.name
    }
}

struct EditorActionBar: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var session: EditorSession
    @ObservedObject var library: LibraryStore
    private var groups: [String] { library.groupNames(on: .bar) }
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                PanelMenu(symbol: ActionCatalogPresentation.groupSymbol(model.actionBarGroup, groups: library.actionGroups), help: "Select Action Group", items:
                    groups.map { group in PanelMenuItem(title: group, isOn: model.actionBarGroup == group) { model.actionBarGroup = group } }
                    + [.separator, PanelMenuItem(title: "Import Action Group…") { model.showActionImporter = true }],
                    symbolSize: 21
                ).frame(width: 28, height: 28)
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
            .onChange(of: library.actions, initial: true) { _, _ in
                if !groups.contains(model.actionBarGroup) { model.actionBarGroup = groups.first ?? "" }
            }
            .onChange(of: library.actionGroups) { _, _ in
                if !groups.contains(model.actionBarGroup) { model.actionBarGroup = groups.first ?? "" }
            }
    }
    private func configuredActionButton(_ action: DraftAction) -> some View {
        let label = ActionBarLabel(action)
        return Button { model.run(action) } label: {
            HStack(spacing: 4) {
                if label.usesIcon {
                    Image(systemName: action.symbol).font(.system(size: 17, weight: .regular)).frame(width: 22)
                }
                if label.showsText {
                    Text(label.text).font(.system(size: 13)).foregroundStyle(Color.secondary).lineLimit(1).fixedSize()
                }
            }.foregroundStyle(ActionTint.color(action.presentation.tintColor) ?? barColor(action.name))
        }.buttonStyle(.plain).help(action.name).accessibilityLabel(label.accessibilityLabel)
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
        case "indigo": return .indigo
        case "pink": return .pink
        default: return nil
        }
    }
}
