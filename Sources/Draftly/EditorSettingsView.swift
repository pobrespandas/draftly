import SwiftUI
import AppKit
import DraftlyCore

enum EditorFontOptions {
    struct Choice: Identifiable, Equatable, Sendable {
        let title: String
        let postScriptName: String
        var id: String { postScriptName }
    }

    static let common: [Choice] = [
        Choice(title: "System", postScriptName: "System"),
        Choice(title: "SF Mono", postScriptName: "SFMono-Regular"),
        Choice(title: "Menlo", postScriptName: "Menlo-Regular"),
        Choice(title: "Helvetica Neue", postScriptName: "HelveticaNeue")
    ]

    static func installed(families: [String], members: (String) -> [(name: String, face: String)]) -> [Choice] {
        var seen = Set<String>()
        return families.sorted().flatMap { family in
            members(family).sorted {
                if $0.face == $1.face { return $0.name < $1.name }
                return $0.face < $1.face
            }.compactMap { member in
                guard !member.name.isEmpty, seen.insert(member.name).inserted else { return nil }
                let title = member.face == "Regular" || member.face.isEmpty
                    ? family : family + " — " + member.face
                return Choice(title: title, postScriptName: member.name)
            }
        }
    }

    static func additional(nerdFonts: [Choice], selected: String) -> [Choice] {
        var seen = Set(common.map(\.postScriptName))
        var result = nerdFonts.filter { seen.insert($0.postScriptName).inserted }
        if seen.insert(selected).inserted {
            result.append(Choice(title: selected.isEmpty ? "Configured Font (empty name)" : selected,
                                 postScriptName: selected))
        }
        return result
    }
}

struct EditorSettingsView: View {
    @ObservedObject var library: LibraryStore
    @State private var navigation = EditorSettingsNavigation()
    @AppStorage(EditorTextInputPreferences.key) private var textInputOptions = "{}"
    @State private var textInputError: String?
    @State private var syntaxFontError: String?
    @AppStorage(EditorSyntaxFontPreferences.key) private var syntaxFonts = "{}"
    @AppStorage("editor.fontName") private var fontName = "System"
    @AppStorage("editor.fontSize") private var fontSize = 17.0
    @AppStorage("editor.lineSpacing") private var lineSpacing = 2.0
    private var installedFontOptions: [EditorFontOptions.Choice] {
        EditorFontOptions.installed(families: NSFontManager.shared.availableFontFamilies) { family in
            (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
                guard member.count >= 2, let name = member[0] as? String,
                      let face = member[1] as? String else { return nil }
                return (name, face)
            }
        }
    }
    private var syntaxFont: EditorSyntaxFontPreferences.Font {
        EditorSyntaxFontPreferences.font(for: navigation.syntax, encoded: syntaxFonts,
            defaultName: fontName, defaultSize: fontSize)
    }

    private func editSyntaxFont(_ edit: (String) throws -> String) {
        do { syntaxFonts = try edit(syntaxFonts); syntaxFontError = nil }
        catch { syntaxFontError = error.localizedDescription }
    }

    private func fontPicker(selection: Binding<String>) -> some View {
        let additional = EditorFontOptions.additional(nerdFonts: installedFontOptions, selected: selection.wrappedValue)
        return Picker("Font", selection: selection) {
            ForEach(EditorFontOptions.common) { option in
                Text(option.title).tag(option.postScriptName)
            }
            if !additional.isEmpty {
                Divider()
                ForEach(additional) { option in
                    Text(option.title).tag(option.postScriptName)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Editor Settings Section", selection: $navigation.section) {
                ForEach(EditorSettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }
            .pickerStyle(.segmented).padding(12)
            HStack(spacing: 0) {
                if navigation.section == .syntax {
                    VStack(alignment: .leading) {
                        Text("Syntaxes").font(.headline).padding(.horizontal, 12)
                        List(selection: Binding<String?>(
                            get: { navigation.syntax },
                            set: { if let name = $0 { navigation.syntax = name } }
                        )) {
                            ForEach(EditorSettingsNavigation.syntaxes(installed: library.syntaxes.map(\.name)), id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }.listStyle(.sidebar)
                    }.frame(width: 220)
                    Divider()
                }
                Form {
                    if navigation.section == .editing {
                        Section("Editor") {
                            fontPicker(selection: $fontName)
                            HStack { Text("Size"); Slider(value: $fontSize, in: 11...28, step: 1); Text(EditorPreferenceDisplay.wholePointLabel(fontSize)).monospacedDigit() }
                            EditorSpacingPreferences(fontName: fontName, fontSize: fontSize, legacyLineSpacing: lineSpacing)
                        }
                        Text("Default font and layout settings apply unless a syntax overrides them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if navigation.section == .syntax {
                        Section("Font") {
                            Text(navigation.syntax).font(.headline)
                            fontPicker(selection: Binding(get: { syntaxFont.name }, set: { name in
                                editSyntaxFont { try EditorSyntaxFontPreferences.settingName(name, for: navigation.syntax, encoded: $0) }
                            }))
                            HStack {
                                Text("Size")
                                Slider(value: Binding(get: { syntaxFont.size }, set: { size in
                                    editSyntaxFont { try EditorSyntaxFontPreferences.settingSize(size, for: navigation.syntax, encoded: $0) }
                                }), in: 11...28, step: 1)
                                Text(EditorPreferenceDisplay.wholePointLabel(syntaxFont.size)).monospacedDigit()
                            }
                            Text("Unchanged values use the default font settings from Editing.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Reset Font Settings") {
                                editSyntaxFont { try EditorSyntaxFontPreferences.reset(for: navigation.syntax, encoded: $0) }
                            }.disabled(!EditorSyntaxFontPreferences.hasOverrides(for: navigation.syntax, encoded: syntaxFonts))
                            if let syntaxFontError { Text(syntaxFontError).foregroundStyle(.red).textSelection(.enabled) }
                        }
                    }
                    if navigation.section == .syntax {
                        EditorSyntaxLayoutSettings(syntax: navigation.syntax,
                            fontName: syntaxFont.name, fontSize: syntaxFont.size, legacyLineSpacing: lineSpacing)
                        Section("Text Input") {
                            ForEach(EditorTextInputPreferences.Option.allCases) { option in
                                Toggle(option.title, isOn: Binding(
                                    get: { EditorTextInputPreferences.value(option, for: navigation.syntax, encoded: textInputOptions) },
                                    set: { enabled in
                                        do {
                                            textInputOptions = try EditorTextInputPreferences.setting(option,
                                                enabled: enabled, for: navigation.syntax, encoded: textInputOptions)
                                            textInputError = nil
                                        } catch { textInputError = error.localizedDescription }
                                    }))
                            }
                            Button("Reset Text Input Settings") {
                                do {
                                    textInputOptions = try EditorTextInputPreferences.reset(for: navigation.syntax, encoded: textInputOptions)
                                    textInputError = nil
                                } catch { textInputError = error.localizedDescription }
                            }.disabled(!EditorTextInputPreferences.hasOverrides(for: navigation.syntax, encoded: textInputOptions))
                            if let textInputError { Text(textInputError).foregroundStyle(.red).textSelection(.enabled) }
                        }
                    }
                    EditorLayoutPreferences(library: library, section: navigation.section,
                        indentationSyntax: $navigation.syntax)
                }.formStyle(.grouped)
            }
        }
        .onChange(of: library.syntaxes.map(\.name)) { _, names in
            navigation.reconcile(installed: names)
        }
    }
}
