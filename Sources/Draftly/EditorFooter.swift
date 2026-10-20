import SwiftUI
import AppKit
import DraftlyCore

struct EditorFooter: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var session: EditorSession
    @ObservedObject var library: LibraryStore
    @State private var statisticsCache = EditorTextStatisticsCache()
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
            HStack(spacing: geometry.size.width < 360 ? MainWindowStyle.footerCompactSpacing : MainWindowStyle.footerRegularSpacing) {
                Button { model.isDraftPinned.toggle() } label: { Image(systemName: model.isDraftPinned ? "pin.fill" : "pin").font(.system(size: MainWindowStyle.footerSecondarySymbolSize)).frame(width: 14) }.help("Pin Current Draft")
                Button { model.showInfo = true } label: { Image(systemName: "info.circle").frame(width: 14) }.help("Draft Info")
                Button { model.showHistory = true } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 14) }.help("Version History")
                Button { model.showRunLog = true } label: { Image(systemName: "clock.badge.checkmark").frame(width: 14) }.help("Action Log")
                PanelMenu(symbol: "arrow.up.arrow.down", help: "Arrange", items: [
                    PanelMenuItem(title: "Sort Lines") { model.edit("editor.setText(editor.getText().split('\\n').sort().join('\\n'));") },
                    PanelMenuItem(title: "Reverse Lines") { model.edit("editor.setText(editor.getText().split('\\n').reverse().join('\\n'));") },
                    PanelMenuItem(title: "Remove Empty Lines") { model.edit("editor.setText(editor.getText().split('\\n').filter(x => x.trim()).join('\\n'));") }
                ], symbolSize: 13).frame(width: 16, height: 20)
                Button { model.linksEnabled.toggle() } label: { Image(systemName: "link").font(.system(size: MainWindowStyle.footerSecondarySymbolSize)).frame(width: 14).foregroundStyle(model.linksEnabled ? Color.accentColor : .secondary) }.help("Link Mode")
                Spacer(minLength: 0)
                Button { model.preview() } label: {
                    Image(systemName: model.showPreview ? "eye.fill" : "eye").frame(width: 14)
                        .foregroundStyle(model.showPreview ? Color.accentColor : .secondary)
                }
                    .help(model.showPreview ? "Edit Markdown (⌥⌘P)" : "Preview Markdown (⌥⌘P)")
                    .accessibilityLabel(model.showPreview ? "Edit Markdown" : "Preview Markdown")
                PanelMenu(symbol: "", help: "Syntax Highlighting", items:
                    (ScriptSyntax.names + model.library.syntaxes.map(\.name)).map { syntax in
                        PanelMenuItem(title: syntax, isOn: model.currentNote?.syntax == syntax) {
                            if let id = session.noteID { model.change([id]) { $0.syntax = syntax } }
                        }
                    } + [.separator, PanelMenuItem(title: "Import Syntax…") { model.importSyntax(asFile: false) }, PanelMenuItem(title: "Add File Syntax…") { model.importSyntax(asFile: true) }], title: model.currentNote?.syntax ?? "Markdown", showsChevron: false, textSize: geometry.size.width < 360 ? 11 : 12
                ).frame(width: geometry.size.width < 360 ? 58 : 64, height: 20)
                Text(statisticsCache.value(for: session.content).footerText).font(.system(size: 11)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
            }.frame(minWidth: geometry.size.width - (geometry.size.width < 280 ? 8 : geometry.size.width < 360 ? 12 : 24))
                .buttonStyle(.plain).font(.system(size: MainWindowStyle.statusSymbolSize)).foregroundStyle(.secondary)
                .padding(.horizontal, geometry.size.width < 280 ? 4 : geometry.size.width < 360 ? 6 : 12).frame(height: MainWindowStyle.footerHeight)
            }.scrollIndicators(.visible)
        }.frame(height: MainWindowStyle.footerHeight)
    }
}
