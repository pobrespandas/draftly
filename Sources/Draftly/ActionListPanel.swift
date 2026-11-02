import SwiftUI
import AppKit
@_spi(DraftlyInternal) import DraftlyCore

struct ActionListPanel: View {
    @AppStorage("actions.showGroupBar") private var showGroupBar = true
    @AppStorage("actions.showKeyboardShortcuts") private var showKeyboardShortcuts = false
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    private var groups: [String] { library.groupNames(on: .list) }
    private var entries: [ActionCatalogPresentation.Entry] {
        ActionCatalogPresentation.entries(library.orderedActions(on: model.actionQuery.isEmpty ? .list : .search), on: model.actionQuery.isEmpty ? .list : .search,
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
                    PanelMenuItem(title: "Manage Groups…") { model.openLibraryManagement(section: .groups) }
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
                    PanelMenuItem(title: "Manage Groups…") { model.openLibraryManagement(section: .groups) }
                ]).frame(width: 28, height: 28)
                }
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, MainWindowStyle.utilityInset).frame(height: MainWindowStyle.utilityHeight)
            if model.showActionSearch {
                ReferenceSearchField(text: $model.actionQuery, placeholder: "Search Actions", focusToken: model.actionSearchFocus)
                    .frame(height: 28).padding(.horizontal, 10).padding(.bottom, 8)
            }
            HStack(spacing: 9) {
                ActionGroupIcon(symbol: ActionCatalogPresentation.groupSymbol(model.actionGroup, groups: library.actionGroups, searching: !model.actionQuery.isEmpty)).foregroundStyle(ActionTint.color(ActionCatalogPresentation.groupColor(model.actionGroup, groups: library.actionGroups)) ?? .secondary)
                Text(model.actionQuery.isEmpty ? model.actionGroup : "Search").font(.system(size: 22, weight: .regular)).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 13).frame(height: 38)
            Divider()
            if entries.isEmpty {
                PanelEmptyState(message: "No actions found")
            } else {
                NativeActionTable(entries: entries,
                    selectionScope: model.actionGroup + "\n" + model.actionQuery,
                    canRun: model.canRunActions,
                    run: { model.run($0) },
                    edit: { model.editingAction = $0 },
                    duplicate: { action in
                        var copy = action; copy.id = UUID(); copy.name += " Copy"
                        model.editingAction = copy
                    },
                    delete: { action in model.perform { try library.deleteAction(action.id) } },
                    content: { entry, emphasized in AnyView(actionRow(entry, emphasized: emphasized)) })
            }
            if showGroupBar {
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(groups.enumerated()), id: \.element) { index, group in
                            ActionGroupButton(title: group,
                                symbol: ActionCatalogPresentation.groupSymbol(group, groups: library.actionGroups),
                                color: ActionTint.color(ActionCatalogPresentation.groupColor(group, groups: library.actionGroups)) ?? .secondary
                            ) { model.actionGroup = group }.frame(width: 32, height: 26)
                        }
                    }.padding(.horizontal, 11).frame(height: 60)
                }.scrollIndicators(.hidden)
            }
        }.background(Color(nsColor: .textBackgroundColor))
        .onChange(of: library.actions, initial: true) { _, _ in model.reconcileActionGroup() }
        .onChange(of: library.actionGroups) { _, _ in model.reconcileActionGroup() }
    }
    private func actionRow(_ entry: ActionCatalogPresentation.Entry, emphasized: Bool) -> some View {
        let action = entry.source
        return VStack(spacing: 0) {
            if let heading = entry.sectionHeading {
                Text(heading).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 28)
            }
            if entry.kind == .separator {
                Text(action.name).font(.caption.weight(.semibold))
                    .foregroundStyle(emphasized ? Color.white : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: action.unsupportedSteps.isEmpty ? action.symbol : "exclamationmark.triangle")
                        .font(.system(size: 18, weight: .regular)).frame(width: 21).foregroundStyle(actionColor(action))
                    Text(action.name).font(.system(size: MainWindowStyle.actionTitleSize))
                        .foregroundStyle(emphasized ? Color.white : .primary).lineLimit(1)
                    Spacer(minLength: 0)
                    if showKeyboardShortcuts, let label = ActionShortcut(action).displayLabel {
                        Text(label).font(.caption).foregroundStyle(emphasized ? Color.white : .secondary).fixedSize()
                    }
                }.padding(.horizontal, 4).frame(height: 28)
            }
        }
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

struct ActionGroupIcon: View {
    let symbol: String
    var body: some View {
        Group {
            if symbol == "text.badge.star" {
                VStack(spacing: -3) {
                    Image(systemName: "star").font(.system(size: 10))
                    Text("md").font(.system(size: 11, weight: .bold))
                }
            } else if symbol == "curlybraces" {
                Image(systemName: symbol).overlay { Image(systemName: "ellipsis").font(.system(size: 7)) }
            } else {
                Image(systemName: symbol)
            }
        }.font(.system(size: 18)).frame(width: 22, height: 22)
    }
}
