import SwiftUI
import AppKit
import DraftlyCore

struct ActionListPanel: View {
    @AppStorage("actions.showGroupBar") private var showGroupBar = true
    @AppStorage("actions.showKeyboardShortcuts") private var showKeyboardShortcuts = false
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    private var groups: [String] { library.groupNames }
    private var entries: [ActionCatalogPresentation.Entry] {
        ActionCatalogPresentation.entries(library.orderedActions(), on: model.actionQuery.isEmpty ? .list : .search,
            group: model.actionQuery.isEmpty && model.actionGroup != "All Actions" ? model.actionGroup : nil,
            query: model.actionQuery)
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
                Button { toggleSearch() } label: { PanelIcon(symbol: model.showActionSearch ? "magnifyingglass.circle.fill" : "magnifyingglass.circle") }.help("Search Actions")
                Button { model.showRunLog = true } label: { PanelIcon(symbol: "clock.arrow.circlepath") }.help("Action Log")
                PanelMenu(symbol: "ellipsis.circle", help: "Action List Options", items: [
                    PanelMenuItem(title: "Action Log") { model.showRunLog = true },
                    PanelMenuItem(title: "Search", isOn: model.showActionSearch) { toggleSearch() },
                    PanelMenuItem(title: "Action Group Bar", isOn: showGroupBar) { showGroupBar.toggle() },
                    PanelMenuItem(title: "Show Keyboard Shortcuts", isOn: showKeyboardShortcuts) { showKeyboardShortcuts.toggle() },
                    .separator,
                    PanelMenuItem(title: "Import from Directory…") { model.showActionImporter = true },
                    PanelMenuItem(title: "Manage Groups…") { model.showLibraryManagement = true }
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
            if entries.isEmpty {
                PanelEmptyState(message: "No actions found")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            let action = entry.source
                            if let heading = entry.sectionHeading {
                                Text(heading).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 6)
                            }
                            Group {
                                if entry.kind == .separator {
                                    HStack {
                                        if !action.name.isEmpty { Text(action.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                                        Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
                                    }.padding(.horizontal, 20).padding(.vertical, 8).contentShape(Rectangle())
                                } else {
                                    Button { model.run(action) } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: action.unsupportedSteps.isEmpty ? action.symbol : "exclamationmark.triangle")
                                                .font(.system(size: 18, weight: .regular)).frame(width: 21).foregroundStyle(actionColor(action))
                                            Text(action.name).font(.system(size: MainWindowStyle.actionTitleSize)).lineLimit(1)
                                            Spacer(minLength: 0)
                                            if showKeyboardShortcuts, let label = ActionShortcut(action).displayLabel {
                                                Text(label).font(.caption).foregroundStyle(.secondary).fixedSize()
                                            }
                                        }.padding(.horizontal, 20).frame(height: 28).contentShape(Rectangle())
                                    }.buttonStyle(ActionRowButtonStyle()).disabled(!model.canRunActions)
                                }
                            }.contextMenu {
                                Button("Edit…") { model.editingAction = action }
                                Button("Duplicate") { var copy = action; copy.id = UUID(); copy.name += " Copy"; model.editingAction = copy }
                                Divider()
                                Button("Delete", role: .destructive) { model.perform { try library.deleteAction(action.id) } }
                            }
                        }
                    }.padding(.top, 10)
                }
            }
            if showGroupBar {
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
            }
        }.background(Color(nsColor: .textBackgroundColor))
        .onChange(of: library.actions) { _, _ in if !groups.contains(model.actionGroup), model.actionGroup != "All Actions" { model.actionGroup = groups.first ?? "General" } }
    }
    private func toggleSearch() {
        model.showActionSearch.toggle()
        model.actionSearchFocus = UUID()
        if !model.showActionSearch { model.actionQuery = "" }
    }
    private func actionColor(_ action: DraftAction) -> Color {
        if !action.unsupportedSteps.isEmpty { return .orange }
        if let tint = ActionTint.color(action.presentation.tintColor) { return tint }
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
