import AppKit
import SwiftUI
import DraftlyCore

enum EditorTextLayout {
    static let horizontalMargin = 5.0
    static let verticalMargin = 19.0
    static func inset(width: CGFloat, margin: CGFloat, maximumWidth: CGFloat) -> CGFloat {
        max(margin, maximumWidth > 0 ? (width - maximumWidth) / 2 : margin)
    }
}

struct EditorLayoutPreferences: View {
    @ObservedObject var library: LibraryStore
    @AppStorage("editor.horizontalMargin") private var horizontal = EditorTextLayout.horizontalMargin
    @AppStorage("editor.verticalMargin") private var vertical = EditorTextLayout.verticalMargin
    @AppStorage("editor.maximumWidth") private var maximum = 0.0
    @AppStorage("editor.typewriter") private var typewriter = false
    @AppStorage("editor.theme") private var themeName = "System"
    @State private var editing: EditorTheme?
    @State private var error: String?
    private var themes: [EditorTheme] { library.themes }
    var body: some View {
        Section("Editor Layout") {
            HStack { Text("Horizontal Margin"); Slider(value: $horizontal, in: 0...80, step: 1); Text("\(Int(horizontal)) pt") }
            HStack { Text("Vertical Margin"); Slider(value: $vertical, in: 0...80, step: 1); Text("\(Int(vertical)) pt") }
            HStack { Text("Maximum Text Width"); TextField("0 for unlimited", value: $maximum, format: .number).frame(width: 100); Text("pt · 0 = unlimited").font(.caption) }
            Toggle("Typewriter Scrolling", isOn: $typewriter)
        }
        Section("Themes") {
            Picker("Theme", selection: $themeName) {
                Text("System").tag("System")
                ForEach(themes) { theme in Text(theme.name).tag(theme.name) }
            }
            HStack {
                Button("New Theme") { editing = EditorTheme() }
                if let current = themes.first(where: { $0.name == themeName }) {
                    Button("Edit") { editing = current }
                    Button("Delete") {
                        do { try library.deleteTheme(current.id); themeName = "System"; error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .sheet(item: $editing) { value in
            ThemeSettingsView(theme: value, otherNames: themes.filter { $0.id != value.id }.map(\.name)) { theme in
                try library.saveTheme(theme)
                themeName = theme.name
            }
        }
    }
}

private struct ThemeSettingsView: View {
    @State var theme: EditorTheme
    var otherNames: [String]
    let save: (EditorTheme) throws -> Void
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var valid: Bool {
        !theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && theme.name != "System" && !otherNames.contains(theme.name)
            && [theme.foreground, theme.background, theme.heading].allSatisfy { EditorTheme.color($0) != nil }
    }
    var body: some View {
        Form {
            TextField("Name", text: $theme.name)
            TextField("Text · RRGGBB", text: $theme.foreground)
            TextField("Background · RRGGBB", text: $theme.background)
            TextField("Headings · RRGGBB", text: $theme.heading)
            Toggle("Dark Appearance", isOn: $theme.isDark)
            Text("Heading and **text** preview").padding().foregroundStyle(Color(nsColor: EditorTheme.color(theme.foreground) ?? .textColor)).background(Color(nsColor: EditorTheme.color(theme.background) ?? .textBackgroundColor))
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") { theme.name = theme.name.trimmingCharacters(in: .whitespacesAndNewlines); do { try save(theme); dismiss() } catch { self.error = error.localizedDescription } }.keyboardShortcut(.defaultAction).disabled(!valid) }
        }.padding(20).frame(width: 440)
    }
}

enum WorkspaceThemeValues {
    static func preference(_ metadata: [String: String]?, key: String) -> String? {
        guard let raw = metadata?["api"], let data = raw.data(using: .utf8),
              let options = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (options[key] as? [String: Any])?["name"] as? String
    }
}
