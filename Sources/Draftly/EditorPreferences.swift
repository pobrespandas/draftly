import AppKit
import SwiftUI

struct EditorTheme: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "New Theme"
    var foreground = "202020"
    var background = "FFFFFF"
    var heading = "007AFF"
    var isDark = false
    static func selected(name: String, data: String) -> EditorTheme? {
        (try? JSONDecoder().decode([EditorTheme].self, from: Data(data.utf8)))?.first { $0.name == name }
    }
    static func color(_ text: String) -> NSColor? {
        let value = text.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((number >> 16) & 255) / 255, green: CGFloat((number >> 8) & 255) / 255, blue: CGFloat(number & 255) / 255, alpha: 1)
    }
}

enum EditorTextLayout {
    static func inset(width: CGFloat, margin: CGFloat, maximumWidth: CGFloat) -> CGFloat {
        max(margin, maximumWidth > 0 ? (width - maximumWidth) / 2 : margin)
    }
}

struct EditorLayoutPreferences: View {
    @AppStorage("editor.horizontalMargin") private var horizontal = 17.0
    @AppStorage("editor.verticalMargin") private var vertical = 17.0
    @AppStorage("editor.maximumWidth") private var maximum = 0.0
    @AppStorage("editor.typewriter") private var typewriter = false
    @AppStorage("editor.theme") private var themeName = "System"
    @AppStorage("editor.themes") private var themeData = "[]"
    @State private var editing: EditorTheme?
    private var themes: [EditorTheme] { (try? JSONDecoder().decode([EditorTheme].self, from: Data(themeData.utf8))) ?? [] }
    var body: some View {
        Section("Editor Layout") {
            HStack { Text("Horizontal Margin"); Slider(value: $horizontal, in: 8...80, step: 1); Text("\(Int(horizontal)) pt") }
            HStack { Text("Vertical Margin"); Slider(value: $vertical, in: 8...80, step: 1); Text("\(Int(vertical)) pt") }
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
                        themeData = String(decoding: (try? JSONEncoder().encode(themes.filter { $0.id != current.id })) ?? Data("[]".utf8), as: UTF8.self)
                        themeName = "System"
                    }
                }
            }
        }
        .sheet(item: $editing) { value in
            ThemeSettingsView(theme: value, otherNames: themes.filter { $0.id != value.id }.map(\.name)) { theme in
                var values = themes.filter { $0.id != theme.id }; values.append(theme)
                themeData = String(decoding: (try? JSONEncoder().encode(values)) ?? Data("[]".utf8), as: UTF8.self)
                themeName = theme.name
            }
        }
    }
}

private struct ThemeSettingsView: View {
    @State var theme: EditorTheme
    var otherNames: [String]
    let save: (EditorTheme) -> Void
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
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") { theme.name = theme.name.trimmingCharacters(in: .whitespacesAndNewlines); save(theme); dismiss() }.keyboardShortcut(.defaultAction).disabled(!valid) }
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
