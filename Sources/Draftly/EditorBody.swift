import SwiftUI
import AppKit
import DraftlyCore

struct EditorBody: View {
    @AppStorage("editor.highlightInsertionPoint") private var highlightInsertionPoint = false
    @AppStorage(GeneralPreferences.showCustomTouchBarKey) private var showCustomTouchBar = true
    @AppStorage(EditorParagraphLayout.lineHeightKey) private var lineHeightMultiple = 0.0
    @AppStorage(EditorParagraphLayout.paragraphSpacingKey) private var paragraphSpacing = 0.0
    @AppStorage(EditorIndentationPreferences.key) private var indentation = "{}"
    @AppStorage(SyntaxFeaturePreferences.key) private var syntaxFeatures = "{}"
    @AppStorage(EditorSyntaxFontPreferences.key) private var syntaxFonts = "{}"
    @AppStorage("editor.monospaceFontName") private var monospaceFontName = "System Monospace"
    @AppStorage(EditorSyntaxLayoutPreferences.key) private var syntaxLayouts = "{}"
    @AppStorage(EditorTextInputPreferences.key) private var textInputOptions = "{}"
    @ObservedObject var model: WindowModel
    @ObservedObject var session: EditorSession
    var fontName: String; var fontSize: Double; var lineSpacing: Double; var markdown: Bool
    var horizontalMargin: Double; var verticalMargin: Double; var maximumWidth: Double; var theme: EditorTheme?
    var body: some View {
        let _ = syntaxFeatures
        let presentation = EditorSyntaxPresentation(model: model)
        let font = EditorSyntaxFontPreferences.font(for: model.currentNote?.syntax ?? "Markdown",
            encoded: syntaxFonts, defaultName: fontName, defaultSize: fontSize)
        let layout = EditorSyntaxLayoutPreferences.layout(for: model.currentNote?.syntax ?? "Markdown",
            encoded: syntaxLayouts, defaults: .init(lineHeightMultiple: lineHeightMultiple,
                paragraphSpacing: paragraphSpacing, horizontalMargin: horizontalMargin,
                verticalMargin: verticalMargin, maximumWidth: maximumWidth))
        VStack(spacing: 0) {
            if let error = presentation.error {
                HStack {
                    Text("Syntax unavailable: " + error).font(.caption).foregroundStyle(.red)
                    Spacer()
                    if presentation.canAddFile { Button("Add File Syntax…") { model.importSyntax(asFile: true) } }
                }.padding(8)
            }
            NativeEditor(session: session, fontName: font.name, fontSize: font.size, monospaceFontName: EditorSyntaxFontPreferences.monospace(for: model.currentNote?.syntax ?? "Markdown", encoded: syntaxFonts, defaultName: monospaceFontName), lineSpacing: lineSpacing, markdown: presentation.definition != nil && markdown, lineHeightMultiple: layout.lineHeightMultiple, paragraphSpacing: layout.paragraphSpacing, syntax: presentation.definition == nil ? "Plain Text" : model.currentNote?.syntax ?? "Markdown", syntaxDefinition: presentation.definition, horizontalMargin: layout.horizontalMargin, verticalMargin: layout.verticalMargin, maximumWidth: layout.maximumWidth, theme: theme, linksEnabled: model.linksEnabled, isActive: !model.showPreview, showCustomTouchBar: showCustomTouchBar, highlightInsertionPoint: highlightInsertionPoint, touchBarModel: model, textInput: EditorTextInputPreferences.configuration(for: model.currentNote?.syntax ?? "Markdown", encoded: textInputOptions), completionContext: { [weak model] in
                EditorCompletionContext(currentDraft: model?.currentNote, drafts: model?.library.notes ?? [])
            }, indentation: EditorIndentationPreferences.style(for: model.currentNote?.syntax ?? "Markdown", encoded: indentation).text) { model.contentChanged() }
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
