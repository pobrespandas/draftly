import SwiftUI
import DraftlyCore

struct WorkspaceFilterSettings: View {
    @Binding var workspace: Workspace
    @Binding var error: String?
    @State private var sortFolder: NoteFolder = .inbox
    private var order: (NoteSort, Bool, Bool) {
        workspace.scriptSort(for: sortFolder) ?? (workspace.sort, workspace.ascending, false)
    }
    var body: some View {
        Section("Flags") {
            Picker("Flag", selection: option("flaggedStatus", fallback: "any")) {
                Text("Any").tag("any"); Text("Flagged").tag("flagged"); Text("Unflagged").tag("unflagged")
            }
            Toggle("Include flagged in Inbox", isOn: option("inboxIncludesFlagged", fallback: true))
            Toggle("Include flagged in Archive", isOn: option("archiveIncludesFlagged", fallback: true))
        }
        Section("Folder Order") {
            Picker("Folder", selection: $sortFolder) {
                ForEach(NoteFolder.allCases) { Text($0.title).tag($0) }
            }
            Picker("Sort", selection: Binding(get: { order.0 }, set: { value in updateSort(sort: value) })) {
                ForEach(NoteSort.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Toggle("Ascending", isOn: Binding(get: { order.1 }, set: { updateSort(ascending: $0) }))
            Toggle("Flagged First", isOn: Binding(get: { order.2 }, set: { updateSort(flagged: $0) }))
        }
        dateSection("Start Date", key: "startDate")
        dateSection("End Date", key: "endDate")
    }
    private func option<T>(_ key: String, fallback: T) -> Binding<T> {
        Binding(get: { workspace.apiOptions[key] as? T ?? fallback }, set: { value in
            edit { try WorkspaceOptionsEditor.set(value, for: key, in: &$0) }
        })
    }
    private func dateOption<T>(_ key: String, _ component: String, fallback: T) -> Binding<T> {
        Binding(get: { (workspace.apiOptions[key] as? [String: Any])?[component] as? T ?? fallback }, set: { value in
            edit { try WorkspaceOptionsEditor.setDate(value, component: component, key: key, in: &$0) }
        })
    }
    private func dateSection(_ title: String, key: String) -> some View {
        let kind = dateOption(key, "type", fallback: "none")
        return Section(title) {
            Picker("Filter", selection: kind) {
                Text("None").tag("none"); Text("Relative").tag("relative"); Text("Date").tag("absolute")
            }
            if kind.wrappedValue != "none" {
                Picker("Date Field", selection: dateOption(key, "field", fallback: "modified")) {
                    Text("Modified").tag("modified"); Text("Created").tag("created"); Text("Accessed").tag("accessed")
                }
                if kind.wrappedValue == "relative" {
                    TextField("Days from Today", value: dateOption(key, "days", fallback: 0), format: .number)
                } else {
                    DatePicker("Date", selection: Binding(get: {
                        let value = (workspace.apiOptions[key] as? [String: Any])?["date"]
                        return APIValues.parseDate(value) ?? Date()
                    }, set: { date in
                        edit { try WorkspaceOptionsEditor.setDate(ISO8601DateFormatter().string(from: date), component: "date", key: key, in: &$0) }
                    }), displayedComponents: .date)
                }
            }
        }
        .onChange(of: kind.wrappedValue) { _, value in
            if value == "absolute", (workspace.apiOptions[key] as? [String: Any])?["date"] == nil {
                edit { try WorkspaceOptionsEditor.setDate(ISO8601DateFormatter().string(from: Date()), component: "date", key: key, in: &$0) }
            }
        }
    }
    private func updateSort(sort: NoteSort? = nil, ascending: Bool? = nil, flagged: Bool? = nil) {
        let current = order
        edit { try WorkspaceOptionsEditor.setSort(sort ?? current.0, ascending: ascending ?? current.1,
            flaggedFirst: flagged ?? current.2, folder: sortFolder, in: &$0) }
    }
    private func edit(_ mutation: (inout Workspace) throws -> Void) {
        do { var copy = workspace; try mutation(&copy); workspace = copy; error = nil }
        catch { self.error = error.localizedDescription }
    }
}
