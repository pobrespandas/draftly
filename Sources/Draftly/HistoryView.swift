import SwiftUI
import AppKit
import DraftlyCore

struct HistoryView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    var noteID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    var revisions: [Revision] { library.revisions.filter { $0.noteID == noteID } }
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("Revision History").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            HSplitView {
                List(revisions, selection: $selected) { revision in
                    VStack(alignment: .leading) { Text(revision.date, format: .dateTime.month().day().hour().minute().second()); Text("\(revision.content.count) characters").font(.caption).foregroundStyle(.secondary) }.tag(revision.id)
                }.frame(width: 200)
                if let revision = revisions.first(where: { $0.id == selected }) {
                    ScrollView { Text(revision.content).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                } else { ContentUnavailableView("Select a revision", systemImage: "clock.arrow.circlepath") }
            }
            HStack {
                Text("Each saved content change keeps a revision.").font(.caption).foregroundStyle(.secondary); Spacer()
                Button("Restore Revision") {
                    guard let revision = revisions.first(where: { $0.id == selected }) else { return }
                    model.restoreRevision(revision)
                    if library.error == nil { dismiss() }
                }.disabled(selected == nil)
            }
        }.padding(20).frame(width: 780, height: 560).onAppear { model.flush(); selected = revisions.first?.id }
    }
}
