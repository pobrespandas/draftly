import SwiftUI
import DraftlyCore

struct WorkspacePresentationSettings: View {
    @Binding var workspace: Workspace
    @ObservedObject var library: LibraryStore
    @Binding var error: String?
    struct Choice: Identifiable {
        let id: String
        let title: String
        let value: [String: String]
    }
    private var groups: [Choice] {
        library.groupNames.map { name in
            let id = library.actionGroupRecord(named: name).id
            return Choice(id: id.uuidString, title: name, value: ["name": name, "uuid": id.uuidString])
        }
    }
    private var themes: [Choice] {
        ThemePickerOptions.values(themes: library.themes).map {
            Choice(id: $0.id, title: $0.title, value: $0.reference)
        }
    }
    var body: some View {
        Section("Action Groups") {
            reference("Action List", key: "loadActionListGroup", choices: groups)
            reference("Action Bar", key: "loadActionBarGroup", choices: groups)
        }
        Section("Preferred Themes") {
            reference("Light Appearance", key: "preferredLightTheme", choices: themes)
            reference("Dark Appearance", key: "preferredDarkTheme", choices: themes)
        }
    }
    private func selected(_ key: String, choices: [Choice]) -> String {
        Self.selectedReferenceID(workspace.apiOptions[key] as? [String: Any],
            isTheme: ["preferredLightTheme", "preferredDarkTheme"].contains(key), choices: choices)
    }
    static func selectedReferenceID(_ value: [String: Any]?, isTheme: Bool, choices: [Choice]) -> String {
        guard let value else { return "" }
        let type = value["type"] as? String ?? "builtIn"
        if (!isTheme || type != "builtIn"), let uuid = value["uuid"] as? String { return uuid }
        if let name = value["name"] as? String {
            return choices.first {
                guard $0.value["name"] == name else { return false }
                return !isTheme || ($0.value["type"] ?? "builtIn") == type
            }?.id ?? "missing:\(name)"
        }
        return "missing:reference"
    }
    private func reference(_ title: String, key: String, choices: [Choice]) -> some View {
        let current = selected(key, choices: choices)
        return Picker(title, selection: Binding(get: { selected(key, choices: choices) }, set: { id in
            let choice = choices.first { $0.id == id }
            guard id.isEmpty || choice != nil else { return }
            do {
                var copy = workspace
                try WorkspaceOptionsEditor.setReference(choice?.value, key: key, in: &copy)
                workspace = copy; error = nil
            } catch { self.error = error.localizedDescription }
        })) {
            Text("No Override").tag("")
            ForEach(choices) { Text($0.title).tag($0.id) }
            if !current.isEmpty && !choices.contains(where: { $0.id == current }) {
                Text("Missing Reference").tag(current)
            }
        }
    }
}
