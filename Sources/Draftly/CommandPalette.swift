import SwiftUI
import AppKit
import DraftlyCore

struct CommandPalette: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool
    private var actions: [DraftAction] { library.orderedActions(on: .search).filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.presentation.description.localizedStandardContains(query) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find an action…", text: $query).textFieldStyle(.plain).font(.title3).focused($focused)
                    .onSubmit { if let action = actions.first { dismiss(); model.run(action) } }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            List(actions) { action in
                Button { dismiss(); model.run(action) } label: {
                    HStack(spacing: 12) { Image(systemName: action.symbol).foregroundStyle(.tint).frame(width: 22); Text(action.name); Spacer(); Text(action.group).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.frame(width: 560, height: 400).onAppear { focused = true }
    }
}
