import SwiftUI
import AppKit
import DraftlyCore

struct HTMLSettingsView: View {
    @AppStorage(HTMLPreferences.pasteKey) private var paste = HTMLPreferences.booleanDefaults[HTMLPreferences.pasteKey]!
    @AppStorage("html.strongMark") private var strong = HTMLPreferences.strongMarks[0]
    @AppStorage("html.emphasisMark") private var emphasis = HTMLPreferences.emphasisMarks[0]
    @AppStorage("html.ulItemMark") private var list = HTMLPreferences.listMarks[0]
    @AppStorage("html.inlineLinks") private var inlineLinks = HTMLPreferences.booleanDefaults["html.inlineLinks"]!
    @AppStorage("html.linksEachParagraph") private var linksEachParagraph = HTMLPreferences.booleanDefaults["html.linksEachParagraph"]!
    @AppStorage("html.ignoreLinks") private var ignoreLinks = HTMLPreferences.booleanDefaults["html.ignoreLinks"]!
    @AppStorage("html.ignoreImages") private var ignoreImages = HTMLPreferences.booleanDefaults["html.ignoreImages"]!
    @AppStorage("html.ignoreEmphasis") private var ignoreEmphasis = HTMLPreferences.booleanDefaults["html.ignoreEmphasis"]!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose how HTML converts to Markdown when you paste in the editor.")
                Toggle("Paste HTML as Markdown", isOn: $paste)
                GroupBox("HTML → Markdown") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Strong Mark", text: $strong)
                            .help("Bold characters: ** or __")
                        TextField("Emphasis Mark", text: $emphasis)
                            .help("Italic character: * or _")
                        TextField("List Mark", text: $list)
                            .help("List character: * or -")
                        Toggle("Inline links", isOn: $inlineLinks)
                        Toggle("Links after each paragraph", isOn: $linksEachParagraph)
                            .disabled(inlineLinks || ignoreLinks)
                        Toggle("Ignore links", isOn: $ignoreLinks)
                        Toggle("Ignore images", isOn: $ignoreImages)
                        Toggle("Ignore emphasis", isOn: $ignoreEmphasis)
                    }.padding(12)
                }
            }.toggleStyle(.checkbox).padding(20)
        }
        .overlay(alignment: .bottomTrailing) { SettingsReferenceHelp(topic: "htmltomarkdown", title: "HTML to Markdown").padding(16) }
    }
}
