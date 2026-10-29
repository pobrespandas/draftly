import SwiftUI
import AppKit
import DraftlyCore

struct CommandPalette: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    private var actions: [DraftAction] { ActionCatalogPresentation.actions(library.orderedActions(on: .search), on: .search, query: model.paletteQuery) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find an action…", text: $model.paletteQuery).textFieldStyle(.plain).font(.title3).focused($focused)
                    .onSubmit { if model.canRunActions, let action = actions.first { dismiss(); model.run(action) } }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            List(actions) { action in
                Button { guard model.canRunActions else { return }; dismiss(); model.run(action) } label: {
                    HStack(spacing: 12) { Image(systemName: action.symbol).foregroundStyle(.tint).frame(width: 22); Text(action.name); Spacer(); Text(action.group).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!model.canRunActions)
            }
        }.frame(width: 560, height: 400).onAppear { focused = true }
    }
}
