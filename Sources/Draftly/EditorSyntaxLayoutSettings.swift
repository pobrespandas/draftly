import AppKit
import SwiftUI

struct EditorSyntaxLayoutSettings: View {
    let syntax: String
    let fontName: String
    let fontSize: Double
    let legacyLineSpacing: Double
    @AppStorage(EditorSyntaxLayoutPreferences.key) private var encoded = "{}"
    @AppStorage(EditorParagraphLayout.lineHeightKey) private var lineHeight = 0.0
    @AppStorage(EditorParagraphLayout.paragraphSpacingKey) private var paragraphs = 0.0
    @AppStorage("editor.horizontalMargin") private var horizontal = EditorTextLayout.horizontalMargin
    @AppStorage("editor.verticalMargin") private var vertical = EditorTextLayout.verticalMargin
    @AppStorage("editor.maximumWidth") private var maximum = 0.0
    @State private var error: String?

    private var layout: EditorSyntaxLayoutPreferences.Layout {
        EditorSyntaxLayoutPreferences.layout(for: syntax, encoded: encoded,
            defaults: .init(lineHeightMultiple: lineHeight, paragraphSpacing: paragraphs,
                horizontalMargin: horizontal, verticalMargin: vertical, maximumWidth: maximum))
    }

    private func edit(_ change: () throws -> String) {
        do { encoded = try change(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func binding(_ field: EditorSyntaxLayoutPreferences.Field) -> Binding<Double> {
        Binding(get: { layout[field] }, set: { value in
            edit { try EditorSyntaxLayoutPreferences.setting(field, value: value, for: syntax, encoded: encoded) }
        })
    }

    private var displayedLineHeight: Double {
        let font = fontName == "System" ? NSFont.systemFont(ofSize: fontSize)
            : NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        return EditorParagraphLayout.displayedMultiple(stored: layout.lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing, font: font)
    }

    var body: some View {
        Section("Syntax Layout") {
            HStack {
                Text("Line height")
                Slider(value: Binding(get: { displayedLineHeight },
                    set: { binding(.lineHeightMultiple).wrappedValue = $0 }), in: 0.8...3, step: 0.05)
                Text(displayedLineHeight, format: .number.precision(.fractionLength(2))).monospacedDigit()
            }
            HStack {
                Text("Paragraph spacing")
                Slider(value: binding(.paragraphSpacing), in: 0...40, step: 1)
                Text(EditorPreferenceDisplay.wholePointLabel(layout.paragraphSpacing)).monospacedDigit()
            }
            HStack {
                Text("Horizontal Margin")
                Slider(value: binding(.horizontalMargin), in: 0...80, step: 1)
                Text(EditorPreferenceDisplay.wholePointLabel(layout.horizontalMargin)).monospacedDigit()
            }
            HStack {
                Text("Vertical Margin")
                Slider(value: binding(.verticalMargin), in: 0...80, step: 1)
                Text(EditorPreferenceDisplay.wholePointLabel(layout.verticalMargin)).monospacedDigit()
            }
            HStack {
                Text("Maximum Text Width")
                TextField("0 for unlimited", value: binding(.maximumWidth), format: .number).labelsHidden().frame(width: 100)
                Text("pt · 0 = unlimited").font(.caption)
            }
            Text("Unchanged values use the layout defaults from Editing. Width uses points.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Reset Layout Settings") {
                edit { try EditorSyntaxLayoutPreferences.reset(for: syntax, encoded: encoded) }
            }.disabled(!EditorSyntaxLayoutPreferences.hasOverrides(for: syntax, encoded: encoded))
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
    }
}
