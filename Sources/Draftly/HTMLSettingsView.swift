import SwiftUI
import AppKit
import DraftlyCore

struct HTMLSettingsView: View {
    @AppStorage(HTMLPreferences.pasteKey) private var paste = true
    @AppStorage("html.strongMark") private var strong = "**"
    @AppStorage("html.emphasisMark") private var emphasis = "_"
    @AppStorage("html.ulItemMark") private var list = "-"
    @AppStorage("html.inlineLinks") private var inlineLinks = true
    @AppStorage("html.linksEachParagraph") private var linksEachParagraph = false
    @AppStorage("html.ignoreLinks") private var ignoreLinks = false
    @AppStorage("html.ignoreImages") private var ignoreImages = false
    @AppStorage("html.ignoreEmphasis") private var ignoreEmphasis = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose how HTML converts to Markdown when you paste in the editor.")
                Toggle("Paste HTML as Markdown", isOn: $paste)
                GroupBox("HTML → Markdown") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Strong Mark", selection: $strong) { Text("**").tag("**"); Text("__").tag("__") }
                        Picker("Emphasis Mark", selection: $emphasis) { Text("_").tag("_"); Text("*").tag("*") }
                        Picker("List Mark", selection: $list) { Text("-").tag("-"); Text("*").tag("*") }
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
