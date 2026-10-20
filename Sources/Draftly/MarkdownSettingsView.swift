import SwiftUI
import AppKit
import DraftlyCore

struct MarkdownSettingsView: View {
    @AppStorage(MarkdownPreferences.engineKey) private var processor = "multi"
    @AppStorage(MarkdownPreferences.multiKey) private var multiOptions = "{}"
    @AppStorage(MarkdownPreferences.githubKey) private var githubOptions = "{}"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose the default Markdown processor for previews and Markdown conversion actions.")
                Picker("Markdown processor", selection: $processor) {
                    Text("MultiMarkdown").tag("multi")
                    Text("GitHub Markdown").tag("github")
                }.pickerStyle(.radioGroup).labelsHidden()
                HStack(alignment: .top, spacing: 24) {
                    optionsGroup("MultiMarkdown Options", engine: "multi", options: MarkdownPreferences.multiOptions, json: $multiOptions)
                    optionsGroup("GitHub Markdown Options", engine: "github", options: MarkdownPreferences.githubOptions, json: $githubOptions)
                }
            }.padding(20)
        }
        .overlay(alignment: .bottomTrailing) { SettingsReferenceHelp(topic: "markdown", title: "Markdown").padding(16) }
    }

    private func optionsGroup(_ title: String, engine: String, options: [MarkdownPreferences.Option], json: Binding<String>) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(options) { option in
                    Toggle(option.title, isOn: Binding(get: {
                        MarkdownPreferences.options(engine: engine, json: json.wrappedValue)[option.id] ?? option.defaultValue
                    }, set: { value in
                        var values = MarkdownPreferences.options(engine: engine, json: json.wrappedValue)
                        values[option.id] = value
                        if let data = try? JSONEncoder().encode(values) { json.wrappedValue = String(decoding: data, as: UTF8.self) }
                    })).toggleStyle(.checkbox)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }.disabled(processor != engine)
    }
}
