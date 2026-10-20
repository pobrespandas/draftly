import SwiftUI
import AppKit
import DraftlyCore

struct DraftEditorPanel: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    var fontName: String
    var fontSize: Double
    var lineSpacing: Double
    var horizontalMargin: Double
    var verticalMargin: Double
    var maximumWidth: Double
    var theme: EditorTheme?

    var body: some View {
        VStack(spacing: 0) {
            if let note = model.currentNote {
                editorContent(note)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "square.and.pencil").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(.tint)
                    Text("Your next thought starts here.").font(.title2.weight(.medium))
                    Text("Write first. Decide what to do with it later.").foregroundStyle(.secondary)
                    Button("New Draft") { model.create() }.buttonStyle(.borderedProminent).commandShortcut("New Draft")
                    Text("⌃⌥⌘N to capture from anywhere").font(.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(nsColor: theme.flatMap { EditorTheme.color($0.background) } ?? .textBackgroundColor))
            .overlay(alignment: .bottom) { EditorStatusOverlay(message: model.status).padding(.bottom, MainWindowStyle.editingBarHeight + MainWindowStyle.footerHeight) }
    }

    private func editorContent(_ note: Note) -> some View {
        VStack(spacing: 0) {
            if note.trashedAt != nil {
                HStack { Label("This draft is in the Trash", systemImage: "trash"); Spacer(); Button("Restore") { model.change([note.id]) { $0.trashedAt = nil } } }
                    .font(.caption).padding(10).background(Color.orange.opacity(0.12))
            }
            if model.showTags {
                DraftTagStrip(model: model, session: model.editor)
                Divider()
            }
            ZStack {
                EditorBody(model: model, session: model.editor, fontName: fontName, fontSize: fontSize, lineSpacing: lineSpacing, markdown: ScriptSyntax.isMarkdown(note.syntax), horizontalMargin: horizontalMargin, verticalMargin: verticalMargin, maximumWidth: maximumWidth, theme: theme)
                    .opacity(model.showPreview ? 0 : 1).allowsHitTesting(!model.showPreview)
                    .accessibilityHidden(model.showPreview)
                if let request = model.actionPreview { ActionPreviewPane(request: request) }
                else if model.showPreview { InlineMarkdownPreview(session: model.editor, syntax: note.syntax, htmlOverride: model.previewHTML) }
            }
            if model.showActionBar {
                Divider()
                EditorActionBar(model: model, session: model.editor, library: library)
            }
            Divider()
            EditorFooter(model: model, session: model.editor, library: library)
        }
    }

}
