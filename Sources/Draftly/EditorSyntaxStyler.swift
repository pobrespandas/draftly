import AppKit
import DraftlyCore

@MainActor struct EditorSyntaxStyler {
    let fontName: String
    let fontSize: Double
    let lineSpacing: Double
    let markdown: Bool
    let lineHeightMultiple: Double
    let paragraphSpacing: Double
    let syntax: String
    let syntaxDefinition: SyntaxDefinition?
    let theme: EditorTheme?
    let linksEnabled: Bool

    func apply(to view: NSTextView, defaultLinkAttributes: [NSAttributedString.Key: Any]?) {
        guard let storage = view.textStorage else { return }
        let range = NSRange(location: 0, length: storage.length)
        let activeScope = ["text.linkModeLink", "text.activeLink", "text.link"].first { theme?.scopeStyle(named: $0) != nil }
        var activeRanges: [NSRange] = []
        var font = fontName == "System" ? NSFont.systemFont(ofSize: fontSize) : NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let baseFont = font
        let foreground = theme.flatMap { EditorTheme.color($0.foreground) } ?? NSColor.textColor
        let heading = theme.flatMap { EditorTheme.color($0.heading) } ?? NSColor.systemBlue
        let paragraph = EditorParagraphLayout.style(lineHeightMultiple: lineHeightMultiple,
            paragraphSpacing: paragraphSpacing, legacyLineSpacing: lineSpacing)
        var baseAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph]
        if var style = theme?.scopeStyle(named: "text.normal") {
            style.foreground = nil
            baseAttributes.merge(ThemeTextAttributes.make(style, currentFont: font, baseFont: baseFont)) { _, new in new }
            font = baseAttributes[.font] as? NSFont ?? font
        }
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: range)
        if markdown {
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
        if syntax == "TaskPaper" || syntax == "Simple List" {
            for (pattern, color) in [("(?m)^.*:$", NSColor.systemBlue), ("@[a-zA-Z0-9_]+(?:\\([^)]*\\))?", NSColor.systemOrange), ("(?m)^\\s*- .*@done.*$", NSColor.secondaryLabelColor)] {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    for match in regex.matches(in: view.string, range: range) { storage.addAttribute(.foregroundColor, value: color, range: match.range) }
                }
            }
        }
        if syntax == "JavaScript" {
            if let regex = try? NSRegularExpression(pattern: "\\b(let|const|var|function|return|if|else|class|new|throw|try|catch|async|await)\\b") {
                for match in regex.matches(in: view.string, range: range) { storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range) }
            }
        }
        if let definition = syntaxDefinition {
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
                    if scope == "markup.quotation", foregroundAllowed { attributes[.foregroundColor] = NSColor.secondaryLabelColor }
                    if scope.contains("italic") || scope == "text.quotation" { currentFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask) }
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
        if linksEnabled, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: view.string, range: range) {
                if let url = match.url {
                    activeRanges.append(match.range)
                    storage.addAttributes([.link: url, .foregroundColor: NSColor.linkColor], range: match.range)
                }
            }
        }
        if linksEnabled, let definition = syntaxDefinition {
            for link in definition.resolvedLinks(in: view.string) {
                activeRanges.append(link.range)
                storage.addAttributes([.link: link.url, .foregroundColor: NSColor.linkColor], range: link.range)
            }
        }
        if let theme = theme {
            func apply(_ scope: String, range: NSRange, foregroundAllowed: Bool = true) {
                guard range.length > 0, var style = theme.scopeStyle(named: scope) else { return }
                if !foregroundAllowed { style.foreground = nil }
                storage.enumerateAttribute(.font, in: range) { value, run, _ in
                    let current = value as? NSFont ?? font
                    storage.addAttributes(ThemeTextAttributes.make(style, currentFont: current, baseFont: baseFont), range: run)
                }
            }
            if markdown {
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
            if let definition = syntaxDefinition {
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
        if linksEnabled, let activeScope, let style = theme?.scopeStyle(named: activeScope) {
            let attributes = ThemeTextAttributes.make(style, currentFont: font, baseFont: baseFont)
            var presentation = defaultLinkAttributes ?? [:]
            for key in [NSAttributedString.Key.foregroundColor, .backgroundColor, .underlineStyle, .strikethroughStyle] {
                if let value = attributes[key] { presentation[key] = value }
            }
            view.linkTextAttributes = presentation
        }
        if let definition = syntaxDefinition {
            for indentation in definition.indentations(in: view.string) {
                var metrics: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
                for scope in indentation.scope.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                    var metricFont = metrics[.font] as? NSFont ?? font
                    if scope.contains("monospace"), !metricFont.isFixedPitch { metricFont = NSFont.monospacedSystemFont(ofSize: metricFont.pointSize, weight: .regular) }
                    if scope.contains("bold") { metricFont = NSFontManager.shared.convert(metricFont, toHaveTrait: .boldFontMask) }
                    if scope.contains("italic") { metricFont = NSFontManager.shared.convert(metricFont, toHaveTrait: .italicFontMask) }
                    metrics[.font] = metricFont
                    if let style = theme?.scopeStyle(named: scope) {
                        metrics.merge(ThemeTextAttributes.make(style, currentFont: metrics[.font] as? NSFont ?? font, baseFont: baseFont)) { _, new in new }
                    }
                }
                let prefix = (view.string as NSString).substring(with: indentation.prefix)
                let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
                style.headIndent = (prefix as NSString).size(withAttributes: metrics).width
                storage.addAttribute(.paragraphStyle, value: style, range: indentation.range)
            }
        }
        storage.endEditing()
        view.typingAttributes = baseAttributes
    }
}
