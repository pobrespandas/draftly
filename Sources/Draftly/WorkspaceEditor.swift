import SwiftUI
import AppKit
import DraftlyCore

struct WorkspaceEditor: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tags = ""
    @State private var excludedTags = ""
    @State private var matchAnyTag = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Save Workspace").font(.title2.weight(.semibold))
            Text("Save the current draft view, search, sort order, and tag filters.").foregroundStyle(.secondary)
            TextField("Workspace name", text: $name).textFieldStyle(.roundedBorder)
            TextField("Included tags, separated by commas", text: $tags).textFieldStyle(.roundedBorder)
            TextField("Excluded tags, separated by commas", text: $excludedTags).textFieldStyle(.roundedBorder)
            Toggle("Match any included tag", isOn: $matchAnyTag)
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") {
                var w = Workspace(name: name); w.folder = model.folder; w.query = model.query; w.sort = model.sort; w.ascending = model.ascending
                w.tagged = model.tagPresence; w.listOptions = model.listOptions
                w.tags = TagRules.normalize(tags.split(separator: ",").map(String.init))
                w.excludedTags = TagRules.normalize(excludedTags.split(separator: ",").map(String.init))
                w.matchAnyTag = matchAnyTag
                model.perform { try library.saveWorkspace(w); model.apply(w); dismiss() }
            }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(24).frame(width: 450).onAppear {
            tags = model.activeTagFilters.joined(separator: ", ")
            excludedTags = model.excludedTagFilters.joined(separator: ", ")
            matchAnyTag = model.matchAnyTag
        }
    }
}
