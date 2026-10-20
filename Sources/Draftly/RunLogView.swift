import SwiftUI
import AppKit
import DraftlyCore

struct RunLogView: View {
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            HStack { Text("Execution History").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding()
            List(library.runs) { run in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(run.actionName).bold(); Spacer(); Text(run.status).foregroundStyle(run.status == "Error" ? .red : .secondary); Text(run.date, style: .time).foregroundStyle(.secondary) }
                    if !run.message.isEmpty { Text(run.message).font(.caption).textSelection(.enabled) }
                }.padding(.vertical, 5)
            }
        }.frame(width: 680, height: 460)
    }
}
