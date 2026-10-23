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
    @AppStorage("editor.fontName") private var fontName = "System"
    @AppStorage("editor.fontSize") private var fontSize = 17.0
    @AppStorage("editor.lineSpacing") private var lineSpacing = 2.0
    private var nerdFontOptions: [(family: String, postScriptName: String)] {
        NSFontManager.shared.availableFontFamilies
            .filter { $0.localizedCaseInsensitiveContains("Nerd Font") }
            .sorted()
            .compactMap { family in
                guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                      let regular = members.first(where: { ($0[1] as? String) == "Regular" }),
                      let postScriptName = regular[0] as? String else { return nil }
                return (family, postScriptName)
            }
    }
    private var additionalFontOptions: [EditorFontOptions.Choice] {
        EditorFontOptions.additional(nerdFonts: nerdFontOptions.map {
            EditorFontOptions.Choice(title: $0.family, postScriptName: $0.postScriptName)
        }, selected: fontName)
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
                            Picker("Font", selection: $fontName) {
                                ForEach(EditorFontOptions.common) { option in
                                    Text(option.title).tag(option.postScriptName)
                                }
                                if !additionalFontOptions.isEmpty {
                                    Divider()
                                    ForEach(additionalFontOptions) { option in
                                        Text(option.title).tag(option.postScriptName)
                                    }
                                }
                            }
                            HStack { Text("Size"); Slider(value: $fontSize, in: 11...28, step: 1); Text(EditorPreferenceDisplay.wholePointLabel(fontSize)).monospacedDigit() }
                            EditorSpacingPreferences(fontName: fontName, fontSize: fontSize, legacyLineSpacing: lineSpacing)
                        }
                        Text("Font and layout settings apply to every syntax.")
                            .font(.caption).foregroundStyle(.secondary)
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
