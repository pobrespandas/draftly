import SwiftUI
import DraftlyCore

struct LibraryManagementView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WorkspaceDefaults.key) private var defaultWorkspaceID = ""
    @State private var group: ActionGroupRecord?
    @State private var oldGroupName: String?
    @State private var workspace: Workspace?
    @State private var selectedGroup = ""
    @State private var section = Section.groups
    private enum Section: String, CaseIterable { case groups = "Groups", actions = "Actions", workspaces = "Workspaces" }
    var body: some View {
        VStack {
            HStack { Text("Library Organization").font(.title2); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding()
            Picker("Organization", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 420).padding(.horizontal)
            switch section {
            case .groups:
                VStack {
                    List {
                        ForEach(Array(library.groupNames.enumerated()), id: \.element) { index, name in
                            HStack {
                                Text(name).font(.headline); Spacer()
                                Button("Edit") {
                                    oldGroupName = name
                                    group = library.actionGroups.first { $0.name == name } ?? ActionGroupRecord(name: name)
                                }
                                Button("↑") { reorderGroups(name, offset: -1) }.disabled(index == 0)
                                Button("↓") { reorderGroups(name, offset: 1) }.disabled(index + 1 == library.groupNames.count)
                                Button("Remove") {
                                    model.perform { try library.removeActionGroup(name, movingActionsTo: name == "General" ? "Imported" : "General") }
                                }.help("Move actions to General, or Imported when removing General")
                            }
                        }
                    }
                    HStack { Button("New Group") { oldGroupName = nil; var value = ActionGroupRecord(name: "New Group"); value.order = library.groupNames.count; group = value }; Spacer() }.padding()
                }
            case .actions:
                VStack {
                    Picker("Group", selection: $selectedGroup) { ForEach(library.groupNames, id: \.self) { Text($0).tag($0) } }.padding(.horizontal)
                    List {
                        let actions = library.orderedActions().filter { $0.group == selectedGroup }
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            HStack {
                                Image(systemName: action.symbol); Text(action.name); Spacer()
                                Button("Edit") { model.editingAction = action; dismiss() }
                                Button("↑") { reorderActions(actions, index: index, offset: -1) }.disabled(index == 0)
                                Button("↓") { reorderActions(actions, index: index, offset: 1) }.disabled(index + 1 == actions.count)
                            }
                        }
                    }
                }
            case .workspaces:
                VStack {
                    Picker("Default Workspace", selection: $defaultWorkspaceID) {
                        Text("Default settings").tag("")
                        ForEach(library.workspaces) { Text($0.name).tag($0.id.uuidString) }
                    }.padding(.horizontal)
                    List {
                        ForEach(Array(library.workspaces.enumerated()), id: \.element.id) { index, item in
                            HStack {
                                Text(item.name); Spacer()
                                Button("Edit") { workspace = item }
                                Button("Duplicate") { var copy = item; copy.id = UUID(); copy.name += " Copy"; workspace = copy }
                                Button("↑") { reorderWorkspaces(index, offset: -1) }.disabled(index == 0)
                                Button("↓") { reorderWorkspaces(index, offset: 1) }.disabled(index + 1 == library.workspaces.count)
                                Button("Delete") { model.perform { try library.deleteWorkspace(item.id); if defaultWorkspaceID == item.id.uuidString { defaultWorkspaceID = "" }; if model.selectedWorkspace == item.id { model.clearFilters() } } }
                            }
                        }
                    }
                    HStack { Button("New Workspace") { workspace = Workspace(name: "New Workspace") }; Spacer() }.padding()
                }
            }
        }.frame(width: 720, height: 520).onAppear { selectedGroup = library.groupNames.first ?? "General" }
            .sheet(item: $group) { value in GroupSettingsView(group: value, previousName: oldGroupName, library: library) }
            .sheet(item: $workspace) { value in WorkspaceSettingsView(workspace: value, library: library) }
    }
    private func reorderActions(_ actions: [DraftAction], index: Int, offset: Int) {
        var values = actions; values.swapAt(index, index + offset)
        for i in values.indices { values[i].presentation.order = i }
        model.perform { try library.saveActions(values) }
    }
    private func reorderWorkspaces(_ index: Int, offset: Int) {
        var values = library.workspaces; values.swapAt(index, index + offset)
        for i in values.indices { values[i].order = i }
        model.perform { try library.saveWorkspaces(values) }
    }
    private func reorderGroups(_ name: String, offset: Int) {
        var names = library.groupNames
        guard let index = names.firstIndex(of: name), names.indices.contains(index + offset) else { return }
        names.swapAt(index, index + offset)
        model.perform {
            let records = names.enumerated().map { order, name in
                var record = library.actionGroups.first { $0.name == name } ?? ActionGroupRecord(name: name)
                record.order = order; return record
            }
            try library.saveActionGroups(records)
        }
    }
}

private struct GroupSettingsView: View {
    @State var group: ActionGroupRecord
    let previousName: String?
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        Form {
            TextField("Name", text: $group.name)
            TextField("SF Symbol", text: $group.symbol)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer(); Button("Save") {
                    do {
                        var value = group; value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if previousName == nil {
                            guard !library.groupNames.contains(value.name) else { throw DraftlyError.message("Use a unique group name.") }
                            value.id = ActionGroupRecord.identifier(for: value.name)
                        }
                        try library.saveActionGroup(value, replacing: previousName); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 420)
    }
}

private struct WorkspaceSettingsView: View {
    @State var workspace: Workspace
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    private var list: Binding<DraftListOptions> { Binding(get: { workspace.listOptions ?? DraftListOptions() }, set: { workspace.listOptions = $0 }) }
    var body: some View {
        Form {
            TextField("Name", text: $workspace.name)
            TextField("Search", text: $workspace.query)
            Picker("Draft View", selection: $workspace.folder) { ForEach(NoteFolder.allCases) { Text($0.title).tag($0) } }
            TextField("Included tags", text: Binding(get: { workspace.tags.joined(separator: ", ") }, set: { workspace.tags = TagRules.normalize($0.components(separatedBy: ",")) }))
            TextField("Excluded tags", text: Binding(get: { (workspace.excludedTags ?? []).joined(separator: ", ") }, set: { workspace.excludedTags = TagRules.normalize($0.components(separatedBy: ",")) }))
            Toggle("Match Any Tag", isOn: Binding(get: { workspace.matchAnyTag ?? false }, set: { workspace.matchAnyTag = $0 }))
            Picker("Tags", selection: $workspace.tagged) { Text("Any").tag(Bool?.none); Text("Tagged").tag(Optional(true)); Text("Untagged").tag(Optional(false)) }
            WorkspaceFilterSettings(workspace: $workspace, error: $error)
            WorkspacePresentationSettings(workspace: $workspace, library: library, error: $error)
            Toggle("Show Preview", isOn: list.showPreview)
            Stepper("Preview Lines: \(list.wrappedValue.previewLines)", value: list.previewLines, in: 1...3)
            Toggle("Show Tags", isOn: list.showTags); Toggle("Show Date", isOn: list.showDate)
            Toggle("Search Titles Only", isOn: list.searchTitlesOnly)
            Toggle("Case-sensitive Search", isOn: list.caseSensitiveSearch)
            Toggle("Preview Search Matches", isOn: list.previewSearchMatches)
            Toggle("Show Last Action", isOn: list.showLastAction)
            Toggle("Highlight Flagged Drafts", isOn: list.highlightFlagged)
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") {
                do {
                    let resolved = try WorkspacePresentationResolver.resolve(workspace, groupNames: library.groupNames,
                        groups: library.actionGroups, themes: library.themes)
                    try library.saveWorkspace(resolved); dismiss()
                } catch { self.error = error.localizedDescription }
            }.keyboardShortcut(.defaultAction).disabled(workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.formStyle(.grouped).frame(width: 500, height: 660)
    }
}
