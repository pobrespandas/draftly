import SwiftUI
import AppKit
import WebKit
import DraftlyCore

struct NativeEditor: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var session: EditorSession
    var fontName: String
    var fontSize: Double
    var lineSpacing: Double
    var markdown: Bool
    var lineHeightMultiple = 0.0
    var paragraphSpacing = 0.0
    var syntax = "Markdown"
    var syntaxDefinition: SyntaxDefinition?
    var horizontalMargin = EditorTextLayout.horizontalMargin
    var verticalMargin = EditorTextLayout.verticalMargin
    var maximumWidth = 0.0
    var theme: EditorTheme?
    var linksEnabled = false
    var isActive = true
    var showCustomTouchBar = true
    var touchBarModel: WindowModel?
    var indentation = "\t"
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false; text.isAutomaticTextReplacementEnabled = true
        text.isGrammarCheckingEnabled = false; text.isContinuousSpellCheckingEnabled = true
        text.allowsUndo = true; text.usesFindBar = true; text.isIncrementalSearchingEnabled = true
        text.drawsBackground = true; text.textContainerInset = NSSize(width: 17, height: 17)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.delegate = context.coordinator; scroll.documentView = text
        context.coordinator.textView = text
        session.synchronizeScriptEdit = { [weak coordinator = context.coordinator] in coordinator?.synchronizeScriptEdit() }
        session.performUndo = { [weak text] redo in if redo { text?.undoManager?.redo() } else { text?.undoManager?.undo() } }
        session.focusForDictation = { [weak text] in
            guard let text, let window = text.window else { return false }
            return window.makeFirstResponder(text)
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator; coordinator.parent = self; coordinator.updating = true
        defer { coordinator.updating = false }
        if let text = text as? DraftTextView {
            text.indentation = indentation
            text.configureTouchBar(model: touchBarModel, showCustom: showCustomTouchBar)
            text.syntaxDefinition = syntaxDefinition
            text.horizontalMargin = max(0, horizontalMargin); text.verticalMargin = max(0, verticalMargin)
            text.maximumLineWidth = max(0, maximumWidth); text.updateTextInsets()
        }
        let background = theme.flatMap { EditorTheme.color($0.background) } ?? (colorScheme == .dark ? NSColor.black : .white)
        if text.backgroundColor != background { text.backgroundColor = background }
        if scroll.backgroundColor != background { scroll.backgroundColor = background }
        if coordinator.defaultSelectionAttributes == nil { coordinator.defaultSelectionAttributes = text.selectedTextAttributes }
        var selection = coordinator.defaultSelectionAttributes ?? [:]
        if let color = theme?.interfaceColor(named: "textSelection").flatMap(EditorTheme.color) { selection[.backgroundColor] = color }
        text.selectedTextAttributes = selection
        text.insertionPointColor = theme?.interfaceColor(named: "textCaret").flatMap(EditorTheme.color)
            ?? theme.flatMap { EditorTheme.color($0.foreground) } ?? .textColor
        let changedNote = coordinator.noteID != session.noteID || coordinator.style.isEmpty
        let changedText = text.string != session.content
        let changedStyle = coordinator.theme != theme || coordinator.style != "\(fontName):\(fontSize):\(lineSpacing):\(lineHeightMultiple):\(paragraphSpacing):\(markdown):\(syntax):\(linksEnabled):\(syntaxDefinition?.source ?? ""):\(theme?.foreground ?? ""):\(theme?.heading ?? "")"
        if changedNote { text.undoManager?.removeAllActions(); coordinator.noteID = session.noteID }
        if changedText {
            if !changedNote {
                let previous = text.string, selection = text.selectedRange()
                text.undoManager?.registerUndo(withTarget: coordinator) { target in target.restore(previous, selection: selection) }
            }
            text.string = session.content
        }
        if changedText || changedStyle || changedNote {
            coordinator.highlight()
            coordinator.theme = theme
            coordinator.style = "\(fontName):\(fontSize):\(lineSpacing):\(lineHeightMultiple):\(paragraphSpacing):\(markdown):\(syntax):\(linksEnabled):\(syntaxDefinition?.source ?? ""):\(theme?.foreground ?? ""):\(theme?.heading ?? "")"
        }
        if changedText || changedNote { coordinator.invalidateDisplay() }
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
        var theme: EditorTheme?
        var defaultSelectionAttributes: [NSAttributedString.Key: Any]?
        var defaultLinkAttributes: [NSAttributedString.Key: Any]?
        var capturedLinkAttributes = false
        var focusToken: UUID?
        init(_ parent: NativeEditor) { self.parent = parent; noteID = parent.session.noteID }
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
        func invalidateDisplay() {
            guard let view = textView else { return }
            view.needsDisplay = true
            view.enclosingScrollView?.contentView.needsDisplay = true
            view.enclosingScrollView?.needsDisplay = true
        }
        func synchronizeScriptEdit() {
            guard let textView, !updating else { return }
            updating = true; defer { updating = false }
            let changedNote = noteID != parent.session.noteID
            if changedNote { textView.undoManager?.removeAllActions(); noteID = parent.session.noteID }
            if textView.string != parent.session.content {
                let previous = textView.string, selection = textView.selectedRange()
                if !changedNote { textView.undoManager?.registerUndo(withTarget: self) { target in target.restore(previous, selection: selection) } }
                textView.string = parent.session.content
                highlight(); invalidateDisplay()
            }
            textView.setSelectedRange(parent.session.safeSelection)
        }
        func restore(_ text: String, selection: NSRange = NSRange(location: 0, length: 0)) {
            guard let textView else { return }
            let previous = textView.string, previousSelection = textView.selectedRange()
            textView.undoManager?.registerUndo(withTarget: self) { target in target.restore(previous, selection: previousSelection) }
            textView.string = text; parent.session.content = text; parent.session.selection = selection
            textView.setSelectedRange(parent.session.safeSelection)
            highlight(); invalidateDisplay(); parent.onChange()
        }
        func highlight() {
            guard let view = textView, let storage = view.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            if !capturedLinkAttributes { defaultLinkAttributes = view.linkTextAttributes; capturedLinkAttributes = true }
            let activeScope = ["text.linkModeLink", "text.activeLink", "text.link"].first { parent.theme?.scopeStyle(named: $0) != nil }
            var activeRanges: [NSRange] = []
            var font = parent.fontName == "System" ? NSFont.systemFont(ofSize: parent.fontSize) : NSFont(name: parent.fontName, size: parent.fontSize) ?? NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            let baseFont = font
            let foreground = parent.theme.flatMap { EditorTheme.color($0.foreground) } ?? NSColor.textColor
            let heading = parent.theme.flatMap { EditorTheme.color($0.heading) } ?? NSColor.systemBlue
            let paragraph = EditorParagraphLayout.style(lineHeightMultiple: parent.lineHeightMultiple,
                paragraphSpacing: parent.paragraphSpacing, legacyLineSpacing: parent.lineSpacing)
            var baseAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph]
            if var style = parent.theme?.scopeStyle(named: "text.normal") {
                style.foreground = nil; style.background = nil
                baseAttributes.merge(ThemeTextAttributes.make(style, currentFont: font, baseFont: baseFont)) { _, new in new }
                font = baseAttributes[.font] as? NSFont ?? font
            }
            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: range)
            if parent.markdown {
                let rules: [(String, [NSAttributedString.Key: Any])] = [
                    ("(?m)^#{1,6} .*$", [.foregroundColor: heading, .font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)]),
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
            if parent.syntax == "TaskPaper" || parent.syntax == "Simple List" {
                for (pattern, color) in [("(?m)^.*:$", NSColor.systemBlue), ("@[a-zA-Z0-9_]+(?:\\([^)]*\\))?", NSColor.systemOrange), ("(?m)^\\s*- .*@done.*$", NSColor.secondaryLabelColor)] {
                    if let regex = try? NSRegularExpression(pattern: pattern) {
                        for match in regex.matches(in: view.string, range: range) { storage.addAttribute(.foregroundColor, value: color, range: match.range) }
                    }
                }
            }
            if parent.syntax == "JavaScript" {
                if let regex = try? NSRegularExpression(pattern: "\\b(let|const|var|function|return|if|else|class|new|throw|try|catch|async|await)\\b") {
                    for match in regex.matches(in: view.string, range: range) { storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range) }
                }
            }
            if let definition = parent.syntaxDefinition {
                for task in definition.tasks(in: view.string) {
                    if let range = task["interactiveRange"] as? [Int], range.count == 2 { storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: NSRange(location: range[0], length: range[1])) }
                }
                for (range, scopeList) in definition.styledRanges(in: view.string) {
                    for scope in scopeList.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                        var attributes: [NSAttributedString.Key: Any] = [:]
                        if scope.contains("heading") { attributes[.foregroundColor] = heading }
                        if scope.contains("bold") { attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                        if scope.contains("italic") { attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                        let colors: [String: NSColor] = ["color.red": .systemRed, "color.blue": .systemBlue, "color.green": .systemGreen, "color.orange": .systemOrange, "color.purple": .systemPurple]
                        if let color = colors[scope] { attributes[.foregroundColor] = color }
                        storage.addAttributes(attributes, range: range)
                    }
                }
            }
            if parent.linksEnabled, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                for match in detector.matches(in: view.string, range: range) {
                    if let url = match.url {
                        activeRanges.append(match.range)
                        storage.addAttributes([.link: url, .foregroundColor: NSColor.linkColor], range: match.range)
                    }
                }
            }
            if let theme = parent.theme {
                func apply(_ scope: String, range: NSRange) {
                    guard range.length > 0, let style = theme.scopeStyle(named: scope) else { return }
                    storage.enumerateAttribute(.font, in: range) { value, run, _ in
                        let current = value as? NSFont ?? font
                        storage.addAttributes(ThemeTextAttributes.make(style, currentFont: current, baseFont: baseFont), range: run)
                    }
                }
                if parent.markdown {
                    let headingScope = theme.scopeStyle(named: "text.heading") == nil ? "text.header" : "text.heading"
                    let scopedRules = [
                        ("(?m)^#{1,6} .*$", headingScope),
                        ("\\*\\*[^*]+\\*\\*", "text.bold"),
                        ("(?<!\\*)\\*[^*\\n]+\\*(?!\\*)", "text.italic"),
                        ("~~[^~]+~~", "text.strikethrough"),
                        ("`[^`]+`", "code.inline"),
                        ("(?m)^>.*$", "text.quotation"),
                        ("\\[[^\\]]+\\]\\([^)]+\\)", "text.link")
                    ]
                    for (pattern, scope) in scopedRules {
                        if let regex = try? NSRegularExpression(pattern: pattern) {
                            for match in regex.matches(in: view.string, range: range) { apply(scope, range: match.range) }
                        }
                    }
                    for level in 1...6 {
                        if let regex = try? NSRegularExpression(pattern: "(?m)^#{\(level)} .*$") {
                            for match in regex.matches(in: view.string, range: range) { apply("text.heading0\(level)", range: match.range) }
                        }
                    }
                }
                if let definition = parent.syntaxDefinition {
                    for (range, scopes) in definition.styledRanges(in: view.string) {
                        for scope in scopes.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) { apply(scope, range: range) }
                    }
                }
                if let activeScope { for range in activeRanges { apply(activeScope, range: range) } }
            }
            view.linkTextAttributes = defaultLinkAttributes
            if parent.linksEnabled, let activeScope, let style = parent.theme?.scopeStyle(named: activeScope) {
                let attributes = ThemeTextAttributes.make(style, currentFont: font, baseFont: baseFont)
                var presentation = defaultLinkAttributes ?? [:]
                for key in [NSAttributedString.Key.foregroundColor, .backgroundColor, .underlineStyle, .strikethroughStyle] {
                    if let value = attributes[key] { presentation[key] = value }
                }
                view.linkTextAttributes = presentation
            }
            storage.endEditing()
            view.typingAttributes = baseAttributes
        }
    }
}

final class DraftTextView: NSTextView {
    private(set) var customTouchBarController: EditorTouchBarController?
    private(set) var showCustomTouchBar = true
    func configureTouchBar(model: WindowModel?, showCustom: Bool) {
        let changed = showCustomTouchBar != showCustom || customTouchBarController?.model !== model
        showCustomTouchBar = showCustom
        if customTouchBarController?.model !== model {
            customTouchBarController = model.map { EditorTouchBarController(model: $0, responder: self) }
            customTouchBarController?.invalidate = { [weak self] in self?.touchBar = nil }
        }
        if changed { touchBar = nil }
    }
    override func makeTouchBar() -> NSTouchBar? {
        if showCustomTouchBar, let customTouchBarController { return customTouchBarController.makeTouchBar() }
        return super.makeTouchBar()
    }
    var indentation = "\t"
    override func insertTab(_ sender: Any?) {
        insertText(indentation, replacementRange: selectedRange())
    }

    override func paste(_ sender: Any?) {
        do {
            if try pasteHTML(from: .general) { return }
            super.paste(sender)
        } catch { NSApp.presentError(error) }
    }

    @discardableResult
    func pasteHTML(from pasteboard: NSPasteboard, defaults: UserDefaults = .standard) throws -> Bool {
        guard defaults.object(forKey: HTMLPreferences.pasteKey) as? Bool ?? true,
              let html = pasteboard.string(forType: .html) else { return false }
        guard let converted = try NativeActionHost().performAPI("htmlToMarkdown", values: ["text": html, "options": HTMLPreferences.options(defaults: defaults)]) as? String else {
            throw DraftlyError.message("HTML could not be converted to Markdown.")
        }
        insertText(converted, replacementRange: selectedRange())
        return true
    }

    var syntaxDefinition: SyntaxDefinition?
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let syntaxDefinition, let layoutManager, let textContainer {
            let index = characterIndexForInsertion(at: point)
            for task in syntaxDefinition.tasks(in: string) {
                guard let raw = task["interactiveRange"] as? [Int], raw.count == 2 else { continue }
                let range = NSRange(location: raw[0], length: raw[1])
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                guard NSLocationInRange(index, range), rect.contains(point), let change = try? syntaxDefinition.taskChange(in: string, task: task, operation: "advance") else { continue }
                insertText(change.1, replacementRange: change.0)
                return
            }
        }
        super.mouseDown(with: event)
    }
    var horizontalMargin: CGFloat = 17
    var verticalMargin: CGFloat = 17
    var maximumLineWidth: CGFloat = 0
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextInsets()
    }
    func updateTextInsets() {
        let width = enclosingScrollView?.contentSize.width ?? bounds.width
        let inset = NSSize(width: EditorTextLayout.inset(width: width, margin: horizontalMargin, maximumWidth: maximumLineWidth), height: verticalMargin)
        if textContainerInset != inset { textContainerInset = inset }
    }

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
    func makeNSView(context: Context) -> WindowAccessorView { WindowAccessorView(callback: callback) }
    func updateNSView(_ view: WindowAccessorView, context: Context) { view.callback = callback }
}

final class WindowAccessorView: NSView {
    var callback: (NSWindow) -> Void
    private weak var reportedWindow: NSWindow?
    init(callback: @escaping (NSWindow) -> Void) {
        self.callback = callback
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("Use init(callback:).") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { reportedWindow = nil; return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, self.reportedWindow !== window else { return }
            self.reportedWindow = window
            self.callback(window)
        }
    }
}

struct InlineMarkdownPreview: NSViewRepresentable {
    @AppStorage(MarkdownPreferences.engineKey) private var processor = "multi"
    @AppStorage(MarkdownPreferences.multiKey) private var multiOptions = "{}"
    @AppStorage(MarkdownPreferences.githubKey) private var githubOptions = "{}"
    @ObservedObject var session: EditorSession
    var syntax = "Markdown"
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
        let html = htmlOverride ?? MarkdownRenderer.page((try? ScriptSyntax.preview(session.content, syntax: syntax)) ?? MarkdownRenderer.escape(session.content))
            .replacingOccurrences(of: "margin:48px auto;padding:0 28px", with: "margin:20px auto;padding:0 20px")
        guard html != context.coordinator.html else { return }
        context.coordinator.html = html
        view.loadHTMLString(html, baseURL: nil)
    }
    @MainActor final class Coordinator { var html: String? }
}

struct AdvancedFindView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var editor: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var replacement = ""
    @State private var caseSensitive = false
    @State private var regularExpression = false
    @FocusState private var queryFocused: Bool
    init(model: WindowModel) { self.model = model; editor = model.editor }
    private var query: Result<EditorFindQuery, Error> {
        Result { try EditorFindQuery(model.advancedFindQuery, caseSensitive: caseSensitive, regularExpression: regularExpression) }
    }
    private var ranges: [NSRange] { (try? query.get().matches(in: editor.content)) ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced Find").font(.headline)
            TextField("Find", text: $model.advancedFindQuery).focused($queryFocused).onSubmit { navigate(backward: false) }
            TextField("Replace", text: $replacement)
            HStack {
                Toggle("Match Case", isOn: $caseSensitive)
                Toggle("Regular Expression", isOn: $regularExpression)
            }.toggleStyle(.checkbox)
            if case .failure(let error) = query {
                Text(error.localizedDescription).foregroundStyle(.red).font(.caption)
            } else { Text("\(ranges.count) matches").foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                        Button { select(range) } label: {
                            Text("\(index + 1). " + preview(range)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).padding(5)
                            .background(editor.selection == range ? Color.accentColor.opacity(0.15) : .clear)
                    }
                }
            }.frame(height: 160)
            HStack {
                Button("Previous") { navigate(backward: true) }.disabled(ranges.isEmpty)
                Button("Next") { navigate(backward: false) }.disabled(ranges.isEmpty)
                Spacer()
                Button("Replace All") { replaceAll() }.disabled(ranges.isEmpty)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 520).onAppear { queryFocused = true }
    }
    private func preview(_ range: NSRange) -> String {
        let text = editor.content as NSString
        return text.substring(with: text.lineRange(for: range)).trimmingCharacters(in: .newlines)
    }
    private func select(_ range: NSRange) {
        editor.selection = range
        editor.synchronizeScriptEdit?()
    }
    private func navigate(backward: Bool) {
        guard !ranges.isEmpty else { return }
        let selection = editor.safeSelection
        if backward { select(ranges.last { $0.location < selection.location } ?? ranges[ranges.count - 1]) }
        else { select(ranges.first { $0.location >= NSMaxRange(selection) && $0 != selection } ?? ranges[0]) }
    }
    private func replaceAll() {
        guard let query = try? query.get() else { return }
        editor.content = query.replacingAll(in: editor.content, with: replacement)
        editor.selection = editor.safeSelection
        editor.synchronizeScriptEdit?()
        model.contentChanged()
        _ = model.flush()
    }
}
