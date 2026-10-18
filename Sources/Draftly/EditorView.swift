import SwiftUI
import AppKit
import WebKit
import DraftlyCore

struct NativeEditor: NSViewRepresentable {
    @ObservedObject var session: EditorSession
    var fontName: String
    var fontSize: Double
    var lineSpacing: Double
    var markdown: Bool
    var linksEnabled = false
    var isActive = true
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false; text.isAutomaticTextReplacementEnabled = true
        text.isGrammarCheckingEnabled = false; text.isContinuousSpellCheckingEnabled = true
        text.allowsUndo = true; text.usesFindBar = true; text.isIncrementalSearchingEnabled = true
        text.drawsBackground = false; text.textContainerInset = NSSize(width: 17, height: 17)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.delegate = context.coordinator; scroll.documentView = text
        context.coordinator.textView = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator; coordinator.parent = self; coordinator.updating = true
        defer { coordinator.updating = false }
        let changedNote = coordinator.noteID != session.noteID
        let changedText = text.string != session.content
        let changedStyle = coordinator.style != "\(fontName):\(fontSize):\(lineSpacing):\(markdown):\(linksEnabled)"
        if changedNote { text.undoManager?.removeAllActions(); coordinator.noteID = session.noteID }
        if changedText {
            if !changedNote {
                let previous = text.string
                text.undoManager?.registerUndo(withTarget: coordinator) { target in target.restore(previous) }
            }
            text.string = session.content
        }
        if changedText || changedStyle || changedNote {
            coordinator.highlight()
            coordinator.style = "\(fontName):\(fontSize):\(lineSpacing):\(markdown):\(linksEnabled)"
        }
        if text.selectedRange() != session.safeSelection { text.setSelectedRange(session.safeSelection); text.scrollRangeToVisible(session.safeSelection) }
        if coordinator.focusToken != session.focusToken {
            coordinator.focusToken = session.focusToken
            if isActive { DispatchQueue.main.async { text.window?.makeFirstResponder(text) } }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        weak var textView: NSTextView?
        var updating = false
        var noteID: UUID?
        var style = ""
        var focusToken: UUID?
        init(_ parent: NativeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard !updating, let textView else { return }
            parent.session.content = textView.string
            parent.session.selection = textView.selectedRange()
            highlight(); parent.onChange()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let textView else { return }; parent.session.selection = textView.selectedRange()
            if parent.session.typewriterScrollingEnabled, let scroll = textView.enclosingScrollView, let layout = textView.layoutManager, let container = textView.textContainer {
                let glyphs = layout.glyphRange(forCharacterRange: textView.selectedRange(), actualCharacterRange: nil)
                let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
                let y = max(0, rect.midY + textView.textContainerInset.height - scroll.contentView.bounds.height / 2)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        func restore(_ text: String) {
            guard let textView else { return }
            let previous = textView.string
            textView.undoManager?.registerUndo(withTarget: self) { target in target.restore(previous) }
            textView.string = text; parent.session.content = text; parent.session.selection = NSRange(location: 0, length: 0)
            highlight(); parent.onChange()
        }
        func highlight() {
            guard let view = textView, let storage = view.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            let font = NSFont(name: parent.fontName, size: parent.fontSize) ?? NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = parent.lineSpacing
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph], range: range)
            if parent.markdown {
                let rules: [(String, [NSAttributedString.Key: Any])] = [
                    ("(?m)^#{1,6} .*$", [.foregroundColor: NSColor.systemBlue, .font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)]),
                    ("\\*\\*[^*]+\\*\\*", [.font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)]),
                    ("`[^`]+`", [.foregroundColor: NSColor.systemOrange]),
                    ("(?m)^\\s*[-*] \\[.\\]", [.foregroundColor: NSColor.systemTeal]),
                    ("\\[[^\\]]+\\]\\([^)]+\\)", [.foregroundColor: NSColor.systemBlue])
                ]
                for (pattern, attributes) in rules {
                    guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                    for match in regex.matches(in: view.string, range: range) { storage.addAttributes(attributes, range: match.range) }
                }
            }
            if parent.linksEnabled, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                for match in detector.matches(in: view.string, range: range) {
                    if let url = match.url { storage.addAttributes([.link: url, .foregroundColor: NSColor.linkColor], range: match.range) }
                }
            }
            storage.endEditing()
            view.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
        }
    }
}

final class DraftTextView: NSTextView {
    override func insertNewline(_ sender: Any?) {
        let source = string as NSString
        let range = selectedRange()
        let lineRange = source.lineRange(for: NSRange(location: range.location, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        if let match = line.range(of: "^\\s*(?:[-*] (?:\\[[ xX]\\] )?|[0-9]+\\. )", options: .regularExpression) {
            var prefix = String(line[match])
            if line.trimmingCharacters(in: .whitespaces) == prefix.trimmingCharacters(in: .whitespaces) {
                insertText("\n", replacementRange: NSRange(location: lineRange.location, length: range.location - lineRange.location)); return
            }
            prefix = prefix.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
            insertText("\n" + prefix, replacementRange: range); return
        }
        super.insertNewline(sender)
    }
}

struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView { let view = NSView(); DispatchQueue.main.async { if let window = view.window { callback(window) } }; return view }
    func updateNSView(_ view: NSView, context: Context) {}
}

struct InlineMarkdownPreview: NSViewRepresentable {
    @ObservedObject var session: EditorSession
    var htmlOverride: String?
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setAccessibilityLabel("Markdown Preview")
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        let html = htmlOverride ?? MarkdownRenderer.page(MarkdownRenderer.render(session.content))
            .replacingOccurrences(of: "margin:48px auto;padding:0 28px", with: "margin:20px auto;padding:0 20px")
        guard html != context.coordinator.html else { return }
        context.coordinator.html = html
        view.loadHTMLString(html, baseURL: nil)
    }
    @MainActor final class Coordinator { var html: String? }
}
