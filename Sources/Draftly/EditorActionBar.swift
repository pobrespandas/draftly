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
            HStack(spacing: 4) {
                PanelMenu(symbol: ActionCatalogPresentation.groupSymbol(model.actionBarGroup, groups: library.actionGroups), help: "Select Action Group", items:
                    groups.map { group in PanelMenuItem(title: group, isOn: model.actionBarGroup == group) { model.actionBarGroup = group } }
                    + [.separator, PanelMenuItem(title: "Import Action Group…") { model.showActionImporter = true }],
                    symbolSize: 21
                ).frame(width: 28, height: 28).padding(.trailing, 8)
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
        return NativeActionBarButton(name: label.accessibilityLabel,
            symbol: label.usesIcon ? action.symbol : nil,
            text: label.showsText ? label.text : "",
            color: ActionTint.color(action.presentation.tintColor) ?? barColor(action.name)
        ) { model.run(action) }.frame(height: 24)
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

private struct NativeActionBarButton: NSViewRepresentable {
    let name: String
    let symbol: String?
    let text: String
    let color: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.activate(_:)))
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .accessoryBar
        button.showsBorderOnlyWhileMouseInside = true
        button.imageScaling = .scaleProportionallyDown
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
        button.toolTip = name
        button.setAccessibilityLabel(name)
        button.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(color)]))) }
        button.image?.isTemplate = false
        button.imagePosition = symbol == nil ? .noImage : text.isEmpty ? .imageOnly : .imageLeading
        button.contentTintColor = NSColor(color)
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor
        ])
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: max(38, nsView.intrinsicContentSize.width), height: 24)
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func activate(_ sender: NSButton) { action() }
    }
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
