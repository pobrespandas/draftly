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
            if text.syntaxDefinition?.source != syntaxDefinition?.source || text.syntaxDefinition?.featureState != syntaxDefinition?.featureState || text.syntaxDefinition?.type != syntaxDefinition?.type {
                text.syntaxCompletions.dismiss()
            }
            text.syntaxDefinition = syntaxDefinition
            text.completionNoteID = session.noteID
            text.syntaxCompletions.invalidate(source: session.content, selection: session.safeSelection, noteID: session.noteID)
            text.completionProvider = { [weak model = touchBarModel, weak session] source, selection in
                guard let session, let definition = syntaxDefinition else { return nil }
                var current = model?.currentNote ?? Note(content: source)
                current.content = source
                if let id = session.noteID { current.id = id }
                return definition.completion(in: source, selection: selection, drafts: model?.library.notes ?? [], current: current)
            }
            text.typewriterScrollingEnabled = session.typewriterScrollingEnabled
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
        let changedStyle = coordinator.theme != theme || coordinator.style != "\(fontName):\(fontSize):\(lineSpacing):\(lineHeightMultiple):\(paragraphSpacing):\(markdown):\(syntax):\(linksEnabled):\(syntaxDefinition?.source ?? ""):\(syntaxDefinition?.featureState ?? ""):\(theme?.foreground ?? ""):\(theme?.heading ?? "")"
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
            coordinator.style = "\(fontName):\(fontSize):\(lineSpacing):\(lineHeightMultiple):\(paragraphSpacing):\(markdown):\(syntax):\(linksEnabled):\(syntaxDefinition?.source ?? ""):\(syntaxDefinition?.featureState ?? ""):\(theme?.foreground ?? ""):\(theme?.heading ?? "")"
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
                style.foreground = nil
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
                func applyDefault(_ scopeList: String, range: NSRange, foregroundAllowed: Bool = true) {
                    guard range.length > 0 else { return }
                    for scope in scopeList.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                        var attributes: [NSAttributedString.Key: Any] = [:]
                        var currentFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? font
                        if scope.contains("monospace"), !currentFont.isFixedPitch {
                            let traits = NSFontManager.shared.traits(of: currentFont).intersection([.boldFontMask, .italicFontMask])
                            currentFont = NSFontManager.shared.convert(NSFont.monospacedSystemFont(ofSize: currentFont.pointSize, weight: .regular), toHaveTrait: traits)
                        }
                        if scope.contains("heading"), foregroundAllowed { attributes[.foregroundColor] = heading }
                        if scope.contains("bold") { currentFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask) }
                        if scope.contains("italic") { currentFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask) }
                        if scope.contains("underline") { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                        if scope.contains("strikethrough") { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                        attributes[.font] = currentFont
                        let colors: [String: NSColor] = ["color.red": .systemRed, "color.blue": .systemBlue, "color.green": .systemGreen, "color.orange": .systemOrange, "color.purple": .systemPurple]
                        if foregroundAllowed, let color = colors[scope] { attributes[.foregroundColor] = color }
                        storage.addAttributes(attributes, range: range)
                    }
                }
                for (range, scopes) in definition.styledRanges(in: view.string) + definition.linkStyledRanges(in: view.string) {
                    applyDefault(scopes, range: range)
                }
                for (range, scopes) in definition.taskStyledRanges(in: view.string) {
                    applyDefault(scopes, range: range, foregroundAllowed: false)
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
            if parent.linksEnabled, let definition = parent.syntaxDefinition {
                for link in definition.resolvedLinks(in: view.string) {
                    activeRanges.append(link.range)
                    storage.addAttributes([.link: link.url, .foregroundColor: NSColor.linkColor], range: link.range)
                }
            }
            if let theme = parent.theme {
                func apply(_ scope: String, range: NSRange, foregroundAllowed: Bool = true) {
                    guard range.length > 0, var style = theme.scopeStyle(named: scope) else { return }
                    if !foregroundAllowed { style.foreground = nil }
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
                    for (range, scopes) in definition.styledRanges(in: view.string) + definition.linkStyledRanges(in: view.string) {
                        for scope in scopes.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) { apply(scope, range: range) }
                    }
                    for (range, scopes) in definition.taskStyledRanges(in: view.string) {
                        for scope in scopes.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) { apply(scope, range: range, foregroundAllowed: false) }
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
    let syntaxCompletions = EditorSyntaxCompletions()
    var completionNoteID: UUID?
    var completionProvider: ((String, NSRange) -> SyntaxCompletionRequest?)?
    private var completionRevision = 0
    override func keyDown(with event: NSEvent) {
        completionRevision &+= 1
        if syntaxCompletions.handle(event) { return }
        syntaxCompletions.dismiss()
        super.keyDown(with: event)
    }
    private var insertingSyntaxCompletion = false
    override func didChangeText() {
        super.didChangeText()
        guard !insertingSyntaxCompletion, undoManager?.isUndoing != true, undoManager?.isRedoing != true else { return }
        let revision = completionRevision, source = string, noteID = completionNoteID, selection = selectedRange()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.completionRevision == revision, self.string == source,
                  self.completionNoteID == noteID, self.selectedRange() == selection else { return }
            self.refreshSyntaxCompletions()
        }
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        if !insertingSyntaxCompletion { refreshSyntaxCompletions() }
    }
    func cancelSyntaxCompletions() {
        completionRevision &+= 1
        syntaxCompletions.dismiss()
    }
    func insertSyntaxCompletion(_ value: String, range: NSRange) {
        insertingSyntaxCompletion = true
        defer { insertingSyntaxCompletion = false }
        breakUndoCoalescing()
        insertText(value, replacementRange: range)
        breakUndoCoalescing()
    }
    @discardableResult func refreshSyntaxCompletions() -> Bool {
        completionRevision &+= 1
        guard !hasMarkedText(), let request = completionProvider?(string, selectedRange()), !request.items.isEmpty else {
            syntaxCompletions.dismiss(); return false
        }
        syntaxCompletions.begin(request, source: string, selection: selectedRange(), noteID: completionNoteID)
        syntaxCompletions.present(for: self)
        return true
    }
    override func complete(_ sender: Any?) {
        if !refreshSyntaxCompletions() { super.complete(sender) }
    }
    override func resignFirstResponder() -> Bool {
        cancelSyntaxCompletions()
        return super.resignFirstResponder()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { cancelSyntaxCompletions() }
    }
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
        cancelSyntaxCompletions()
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
    var typewriterScrollingEnabled = false
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextInsets()
    }
    func updateTextInsets() {
        let width = enclosingScrollView?.contentSize.width ?? bounds.width
        let viewportHeight = enclosingScrollView?.contentSize.height ?? 0
        let vertical = typewriterScrollingEnabled ? max(verticalMargin, viewportHeight / 2) : verticalMargin
        let inset = NSSize(width: EditorTextLayout.inset(width: width, margin: horizontalMargin, maximumWidth: maximumLineWidth), height: vertical)
        if textContainerInset != inset { textContainerInset = inset }
    }

    override func insertNewline(_ sender: Any?) {
        if let change = syntaxDefinition?.listContinuation(in: string, selection: selectedRange()) {
            insertText(change.text, replacementRange: change.range)
            return
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
    @State private var replacement = ""
    @State private var caseSensitive = false
    @State private var regularExpression = false
    @State private var history: [AdvancedFindRequest] = []
    @FocusState private var queryFocused: Bool
    init(model: WindowModel) { self.model = model; editor = model.editor }
    private var commands: AdvancedFindCommands { AdvancedFindCommands(model: model) }
    private var request: AdvancedFindRequest {
        AdvancedFindRequest(text: model.advancedFindQuery, replacement: replacement,
            caseSensitive: caseSensitive, regularExpression: regularExpression)
    }
    private var historyStore: AdvancedFindHistory {
        AdvancedFindHistory(defaults: model.dependencies.preferences.defaults)
    }
    private var query: Result<EditorFindQuery, Error> { Result { try request.query() } }
    private var validQuery: Bool { if case .success = query { return true }; return false }
    private func remember() {
        do { try historyStore.record(request); history = historyStore.requests }
        catch { model.library.error = error.localizedDescription }
    }
    private func restore(_ request: AdvancedFindRequest) {
        model.advancedFindQuery = request.text
        replacement = request.replacement
        caseSensitive = request.caseSensitive
        regularExpression = request.regularExpression
    }
    private func find() {
        guard case .success = query else { return }
        remember()
        commands.navigate(in: ranges, backward: false)
    }
    private var ranges: [NSRange] { (try? query.get().matches(in: editor.content)) ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced Find").font(.headline)
            HStack(alignment: .top) {
                Text("Find").frame(width: 60, alignment: .trailing)
                TextEditor(text: $model.advancedFindQuery).focused($queryFocused)
                    .font(.body).frame(height: 60).accessibilityLabel("Find")
            }
            HStack(alignment: .top) {
                Text("Replace").frame(width: 60, alignment: .trailing)
                TextEditor(text: $replacement).font(.body).frame(height: 60).accessibilityLabel("Replace")
            }
            HStack {
                Button("Reverse Values", systemImage: "arrow.up.arrow.down") {
                    var reversed = request; reversed.reverseValues(); restore(reversed)
                }
                Menu("History", systemImage: "clock.arrow.circlepath") {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, value in
                        Button(value.historyTitle) { restore(value) }
                    }
                    Divider()
                    Button("Clear History") { historyStore.clear(); history = [] }.disabled(history.isEmpty)
                }
                Spacer()
                Button("Find") { find() }.disabled(model.advancedFindQuery.isEmpty || !validQuery)
                    .keyboardShortcut(.return, modifiers: .command)
            }
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
                        HStack {
                            Button { commands.select(range) } label: {
                                Text(preview(range)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Button("Replace") { remember(); commands.replace(query: query, range: range, with: replacement) }
                                .accessibilityLabel("Replace match \(index + 1)")
                        }.padding(5)
                            .background(editor.selection == range ? Color.accentColor.opacity(0.15) : .clear)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button("Previous") { commands.navigate(in: ranges, backward: true) }.disabled(ranges.isEmpty)
                Button("Next") { commands.navigate(in: ranges, backward: false) }.disabled(ranges.isEmpty)
                Spacer()
                Button("Replace All") { remember(); commands.replaceAll(query: query, with: replacement) }.disabled(ranges.isEmpty)
                Button("Done") { model.showAdvancedFind = false }.keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(minWidth: 580, minHeight: 380).onAppear { history = historyStore.requests; queryFocused = true }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification,
                object: model.dependencies.preferences.defaults)) { _ in history = historyStore.requests }
    }
    private func preview(_ range: NSRange) -> String {
        AdvancedFindResult.preview(in: editor.content, range: range)
    }
}
