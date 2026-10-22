import SwiftUI
import AppKit
import DraftlyCore

struct EditorBody: View {
    @AppStorage(GeneralPreferences.showCustomTouchBarKey) private var showCustomTouchBar = true
    @AppStorage(EditorParagraphLayout.lineHeightKey) private var lineHeightMultiple = 0.0
    @AppStorage(EditorParagraphLayout.paragraphSpacingKey) private var paragraphSpacing = 0.0
    @AppStorage(EditorIndentationPreferences.key) private var indentation = "{}"
    @AppStorage(SyntaxFeaturePreferences.key) private var syntaxFeatures = "{}"
    @ObservedObject var model: WindowModel
    @ObservedObject var session: EditorSession
    var fontName: String; var fontSize: Double; var lineSpacing: Double; var markdown: Bool
    var horizontalMargin: Double; var verticalMargin: Double; var maximumWidth: Double; var theme: EditorTheme?
    var body: some View {
        let _ = syntaxFeatures
        let presentation = EditorSyntaxPresentation(model: model)
        VStack(spacing: 0) {
            if let error = presentation.error {
                HStack {
                    Text("Syntax unavailable: " + error).font(.caption).foregroundStyle(.red)
                    Spacer()
                    if presentation.canAddFile { Button("Add File Syntax…") { model.importSyntax(asFile: true) } }
                }.padding(8)
            }
            NativeEditor(session: session, fontName: fontName, fontSize: fontSize, lineSpacing: lineSpacing, markdown: presentation.definition != nil && markdown, lineHeightMultiple: lineHeightMultiple, paragraphSpacing: paragraphSpacing, syntax: presentation.definition == nil ? "Plain Text" : model.currentNote?.syntax ?? "Markdown", syntaxDefinition: presentation.definition, horizontalMargin: horizontalMargin, verticalMargin: verticalMargin, maximumWidth: maximumWidth, theme: theme, linksEnabled: model.linksEnabled, isActive: !model.showPreview, showCustomTouchBar: showCustomTouchBar, touchBarModel: model, indentation: EditorIndentationPreferences.style(for: model.currentNote?.syntax ?? "Markdown", encoded: indentation).text) { model.contentChanged() }
        }
    }
}

@MainActor struct EditorSyntaxPresentation {
    let definition: SyntaxDefinition?
    let error: String?
    let canAddFile: Bool

    init(model: WindowModel) {
        let name = model.currentNote?.syntax ?? "Markdown"
        canAddFile = model.library.syntaxes.first { $0.name == name }?.type == "file"
        do {
            definition = try model.library.syntaxDefinition(named: name, defaults: model.dependencies.preferences.defaults)
            error = nil
        } catch {
            definition = nil
            self.error = error.localizedDescription
        }
    }
}
