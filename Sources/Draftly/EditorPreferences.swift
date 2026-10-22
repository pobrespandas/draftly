import AppKit
import SwiftUI
import DraftlyCore
import UniformTypeIdentifiers

enum EditorPreferenceDisplay {
    static func wholePointLabel(_ value: Double) -> String {
        guard let points = Int(exactly: value.rounded(.towardZero)) else { return "Invalid value" }
        return "\(points) pt"
    }
}

enum EditorTextLayout {
    static let horizontalMargin = 6.0
    static let verticalMargin = 26.0
    static func inset(width: CGFloat, margin: CGFloat, maximumWidth: CGFloat) -> CGFloat {
        max(margin, maximumWidth > 0 ? (width - maximumWidth) / 2 : margin)
    }
}

enum EditorParagraphLayout {
    static let lineHeightKey = "editor.lineHeightMultiple"
    static let paragraphSpacingKey = "editor.paragraphSpacing"

    static func resolvedParagraphSpacing(_ stored: Double) -> Double {
        stored.isFinite ? max(0, stored) : 0
    }

    static func style(lineHeightMultiple: Double, paragraphSpacing: Double,
                      legacyLineSpacing: Double) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        if lineHeightMultiple.isFinite && lineHeightMultiple > 0 {
            style.lineHeightMultiple = lineHeightMultiple
        } else {
            style.lineSpacing = legacyLineSpacing
        }
        style.paragraphSpacing = resolvedParagraphSpacing(paragraphSpacing)
        return style
    }

    static func displayedMultiple(stored: Double, legacyLineSpacing: Double, font: NSFont) -> Double {
        if stored.isFinite && stored > 0 { return stored }
        let height = NSLayoutManager().defaultLineHeight(for: font)
        guard height > 0, legacyLineSpacing.isFinite else { return 1 }
        return max(0.8, min(3, 1 + legacyLineSpacing / height))
    }
}

struct EditorSpacingPreferences: View {
    var fontName: String
    var fontSize: Double
    var legacyLineSpacing: Double
    @AppStorage(EditorParagraphLayout.lineHeightKey) private var lineHeightMultiple = 0.0
    @AppStorage(EditorParagraphLayout.paragraphSpacingKey) private var paragraphSpacing = 0.0
    private var font: NSFont {
        fontName == "System" ? .systemFont(ofSize: fontSize)
            : NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
    var body: some View {
        HStack {
            Text("Line height")
            Slider(value: Binding(
                get: { EditorParagraphLayout.displayedMultiple(stored: lineHeightMultiple, legacyLineSpacing: legacyLineSpacing, font: font) },
                set: { lineHeightMultiple = $0 }
            ), in: 0.8...3, step: 0.05)
            Text(EditorParagraphLayout.displayedMultiple(stored: lineHeightMultiple, legacyLineSpacing: legacyLineSpacing, font: font), format: .number.precision(.fractionLength(2))).monospacedDigit()
        }
        HStack {
            Text("Paragraph spacing")
            Slider(value: Binding(
                get: { EditorParagraphLayout.resolvedParagraphSpacing(paragraphSpacing) },
                set: { paragraphSpacing = $0 }
            ), in: 0...40, step: 1)
            Text("\(EditorParagraphLayout.resolvedParagraphSpacing(paragraphSpacing), format: .number.precision(.fractionLength(0))) pt").monospacedDigit()
        }
    }
}

struct EditorLayoutPreferences: View {
    @ObservedObject var library: LibraryStore
    @AppStorage("editor.horizontalMargin") private var horizontal = EditorTextLayout.horizontalMargin
    @AppStorage("editor.verticalMargin") private var vertical = EditorTextLayout.verticalMargin
    @AppStorage("editor.maximumWidth") private var maximum = 0.0
    @AppStorage("editor.typewriter") private var typewriter = false
    @AppStorage(EditorThemePreferences.key) private var themeReferences = Data()
    @State private var editing: EditorTheme?
    @State private var editingDark: Bool?
    @State private var error: String?
    @State private var indentationSyntax = "Markdown"
    @AppStorage(EditorIndentationPreferences.key) private var indentation = "{}"
    private var themes: [EditorTheme] { library.themes }
    private var themeCommands: InstalledThemeCommands { InstalledThemeCommands(library: library) }
    var body: some View {
        Section("Indentation") {
            Picker("Syntax", selection: $indentationSyntax) {
                ForEach(Array(Set(ScriptSyntax.names + library.syntaxes.map(\.name))).sorted(), id: \.self) { Text($0).tag($0) }
            }
            Picker("Insert", selection: Binding(
                get: { EditorIndentationPreferences.style(for: indentationSyntax, encoded: indentation) },
                set: { indentation = EditorIndentationPreferences.setting($0, for: indentationSyntax, encoded: indentation) }
            )) {
                ForEach(EditorIndentationStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        }
        Section("Editor Layout") {
            HStack { Text("Horizontal Margin"); Slider(value: $horizontal, in: 0...80, step: 1); Text(EditorPreferenceDisplay.wholePointLabel(horizontal)) }
            HStack { Text("Vertical Margin"); Slider(value: $vertical, in: 0...80, step: 1); Text(EditorPreferenceDisplay.wholePointLabel(vertical)) }
            HStack { Text("Maximum Text Width"); TextField("0 for unlimited", value: $maximum, format: .number).frame(width: 100); Text("pt · 0 = unlimited").font(.caption) }
            Toggle("Typewriter Scrolling", isOn: $typewriter)
        }
        Section("Themes") {
            themePicker(dark: false)
            themePicker(dark: true)
            HStack {
                Button("New Theme") { editingDark = nil; editing = EditorTheme() }
                Button("Import Theme…") { importTheme() }
                Button("Use Theme File…") { useThemeFile() }
            }
            ThemeDevelopmentFolderSettings(library: library)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .sheet(item: $editing) { value in
            ThemeSettingsView(theme: value, otherNames: themes.filter { $0.id != value.id && $0.type == "custom" }.map(\.name)) { theme in
                try themeCommands.saveEditorTheme(theme, dark: editingDark)
            }
        }
    }
    private func themePicker(dark: Bool) -> some View {
        _ = themeReferences
        let reference = EditorThemePreferences().reference(dark: dark, themes: themes)
        let selectedID = ["custom", "file"].contains(reference["type"] as? String ?? "") ? (reference["uuid"] as? String).flatMap(UUID.init(uuidString:)) : nil
        let selection = Binding<String>(get: {
            if let selectedID { return (reference["type"] as? String ?? "custom") + ":" + selectedID.uuidString }
            return "builtIn:" + (reference["name"] as? String ?? (dark ? "Dark" : "Light"))
        }, set: { value in
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            let newReference = ["custom", "file"].contains(parts[0]) ? ["type": parts[0], "uuid": parts[1]] : ["type": "builtIn", "name": parts[1]]
            do { try themeCommands.select(reference: newReference, dark: dark); error = nil }
            catch { self.error = error.localizedDescription }
        })
        return HStack {
            Picker(dark ? "Dark Theme" : "Light Theme", selection: selection) {
                ForEach(ThemePickerOptions.values(themes: themes)) { Text($0.title).tag($0.editorTag) }
            }
            if let current = themes.first(where: { $0.id == selectedID }) {
                if current.type == "file" {
                    Button("Reload") {
                        do { try themeCommands.select(reference: reference, dark: dark); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                    Button("Reselect…") { useThemeFile(replacing: current, dark: dark) }
                } else { Button("Edit") { editingDark = dark; editing = current } }
                Button("Delete") {
                    do {
                        try themeCommands.delete(current)
                        error = nil
                    }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
    }
    private func useThemeFile(replacing target: EditorTheme? = nil, dark: Bool? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.allowedContentTypes = ThemeImportFileTypes.allowed
        panel.message = "Select a theme file. Reload applies external file changes."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let before = library.themes
            var prepared = try ThemeFileAccess.prepare(url, id: target?.id ?? UUID())
            if let target, target.name != prepared.definition.name {
                throw DraftlyError.message("Select the file for theme “\(target.name)”.")
            }
            if target == nil, let existing = themes.first(where: { $0.name == prepared.definition.name && $0.type == "file" }) {
                let alert = NSAlert(); alert.messageText = "Replace theme file “\(existing.name)”?"
                alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                let originalName = prepared.definition.name
                prepared = try ThemeFileAccess.prepare(url, id: existing.id)
                guard prepared.definition.name == originalName else { throw DraftlyError.message("The theme file changed. Select it again.") }
            }
            guard library.themes == before else { throw DraftlyError.message("The installed themes changed. Select the file again.") }
            try themeCommands.install(prepared, dark: dark)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ThemeImportFileTypes.allowed
        panel.message = "Choose a Drafts theme definition to review before saving."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let active = url.startAccessingSecurityScopedResource()
            defer { if active { url.stopAccessingSecurityScopedResource() } }
            var theme = try DraftsThemeImport.decode(data: Data(contentsOf: url))
            if let existing = themes.first(where: { $0.name == theme.name && $0.type == "custom" }) {
                let alert = NSAlert()
                alert.messageText = "A theme named “\(theme.name)” already exists."
                alert.informativeText = "Replace keeps its identity. Import as New lets you choose another name."
                alert.addButton(withTitle: "Replace")
                alert.addButton(withTitle: "Import as New")
                alert.addButton(withTitle: "Cancel")
                switch alert.runModal() {
                case .alertFirstButtonReturn: theme.id = existing.id
                case .alertSecondButtonReturn: break
                default: return
                }
            }
            error = nil
            editingDark = nil
            editing = theme
        } catch { self.error = error.localizedDescription }
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
            if theme.unknownFields["draftsSource"] != nil {
                Text(DraftsThemeImport.limitations)
                    .font(.callout).foregroundStyle(.secondary)
            }
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

enum ThemeImportFileTypes {
    static var allowed: [UTType] { [UTType(filenameExtension: "draftsTheme") ?? .data, .json] }
}
