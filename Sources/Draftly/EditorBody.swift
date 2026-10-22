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
        NativeEditor(session: session, fontName: fontName, fontSize: fontSize, lineSpacing: lineSpacing, markdown: markdown, lineHeightMultiple: lineHeightMultiple, paragraphSpacing: paragraphSpacing, syntax: model.currentNote?.syntax ?? "Markdown", syntaxDefinition: try? model.library.syntaxDefinition(named: model.currentNote?.syntax ?? "Markdown"), horizontalMargin: horizontalMargin, verticalMargin: verticalMargin, maximumWidth: maximumWidth, theme: theme, linksEnabled: model.linksEnabled, isActive: !model.showPreview, showCustomTouchBar: showCustomTouchBar, touchBarModel: model, indentation: EditorIndentationPreferences.style(for: model.currentNote?.syntax ?? "Markdown", encoded: indentation).text) { model.contentChanged() }
    }
}
