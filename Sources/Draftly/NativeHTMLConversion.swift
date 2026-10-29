import AppKit

struct NativeHTMLConversion {
    func decodeHTML(_ text: String) throws -> String {
        guard text.contains("&") else { return text }
        let pattern = try NSRegularExpression(pattern: "&(?:#[xX][0-9A-Fa-f]+|#[0-9]+|[A-Za-z][A-Za-z0-9]*);?")
        let source = text as NSString
        let result = NSMutableString(string: text)
        var decoded: [String: String] = [:]
        // Decode entity tokens, never the surrounding document or literal text.
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let entity = source.substring(with: match.range)
            let replacement: String
            if let cached = decoded[entity] { replacement = cached }
            else {
                let document = "<span>" + entity + "</span>"
                replacement = try NSAttributedString(data: Data(document.utf8), options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil).string
                decoded[entity] = replacement
            }
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }
    func htmlToMarkdown(_ text: String, options: [String: Any]) throws -> String {
        var result = text
        func replace(_ pattern: String, _ replacement: String) { result = result.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive]) }
        replace("(?s)<(?:script|style)\\b[^>]*>.*?</(?:script|style)>", "")
        let blocks = try NSRegularExpression(pattern: "<pre\\b[^>]*>\\s*<code\\b[^>]*>(.*?)</code>\\s*</pre>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let source = result as NSString
        var codeBlocks: [(String, String)] = []
        for match in blocks.matches(in: result, range: NSRange(location: 0, length: source.length)).reversed() {
            let code = try decodeHTML(source.substring(with: match.range(at: 1)))
            let runs = code.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: max(3, runs + 1))
            let token = "DRAFTLYCODE" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let block = fence + "\n" + code + (code.hasSuffix("\n") ? "" : "\n") + fence
            codeBlocks.append((token, block))
            if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: "\n\n" + token + "\n\n") }
        }
        for level in 1...6 { replace("(?s)<h\(level)\\b[^>]*>(.*?)</h\(level)>", "\n" + String(repeating: "#", count: level) + " $1\n") }
        if options["ignoreLinks"] as? Bool == true { replace("(?s)<a\\b[^>]*>(.*?)</a>", "$1") }
        else if options["inlineLinks"] as? Bool ?? true {
            replace("(?s)<a\\b[^>]*href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>", "[$2]($1)")
        } else {
            let expression = try NSRegularExpression(pattern: "<a\\b[^>]*href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>", options: [.caseInsensitive, .dotMatchesLineSeparators])
            var reference = 0
            func convertLinks(_ source: String) -> (String, [String]) {
                let text = source as NSString
                let matches = expression.matches(in: source, range: NSRange(location: 0, length: text.length))
                var replacements: [(NSRange, String)] = [], definitions: [String] = []
                for match in matches {
                    reference += 1
                    replacements.append((match.range, "[" + text.substring(with: match.range(at: 2)) + "][\(reference)]"))
                    definitions.append("[\(reference)]: " + text.substring(with: match.range(at: 1)))
                }
                var converted = source
                for (range, value) in replacements.reversed() {
                    if let range = Range(range, in: converted) { converted.replaceSubrange(range, with: value) }
                }
                return (converted, definitions)
            }
            if options["linksEachParagraph"] as? Bool == true {
                replace("</p\\s*>", "</p>")
                result = result.components(separatedBy: "</p>").map { paragraph in
                    let (converted, definitions) = convertLinks(paragraph)
                    return converted + "\n\n" + definitions.joined(separator: "\n")
                }.joined(separator: "\n\n")
            } else {
                let (converted, definitions) = convertLinks(result)
                result = converted + "\n\n" + definitions.joined(separator: "\n")
            }
        }
        if options["ignoreImages"] as? Bool == true { replace("<img\\b[^>]*>", "") }
        else {
            let images = try NSRegularExpression(pattern: "<img\\b[^>]*>", options: .caseInsensitive)
            let attributes = try NSRegularExpression(pattern: #"\s+(src|alt)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#, options: .caseInsensitive)
            let source = result as NSString
            for match in images.matches(in: result, range: NSRange(location: 0, length: source.length)).reversed() {
                let tag = source.substring(with: match.range) as NSString
                var values: [String: String] = [:]
                for attribute in attributes.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                    let key = tag.substring(with: attribute.range(at: 1)).lowercased()
                    guard values[key] == nil else { continue }
                    if let group = (2...4).first(where: { attribute.range(at: $0).location != NSNotFound }) {
                        values[key] = tag.substring(with: attribute.range(at: group))
                    }
                }
                let replacement = values["src"].map { "![" + (values["alt"] ?? "") + "](" + $0 + ")" } ?? ""
                if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: replacement) }
            }
        }
        let emphasis = options["emphasisMark"] as? String ?? "_", strong = options["strongMark"] as? String ?? "**"
        replace("(?s)<(?:strong|b)\\b[^>]*>(.*?)</(?:strong|b)>", options["ignoreEmphasis"] as? Bool == true ? "$1" : strong + "$1" + strong)
        replace("(?s)<(?:em|i)\\b[^>]*>(.*?)</(?:em|i)>", options["ignoreEmphasis"] as? Bool == true ? "$1" : emphasis + "$1" + emphasis)
        replace("(?s)<code\\b[^>]*>(.*?)</code>", "`$1`")
        replace("<li\\b[^>]*>", "\n" + (options["ulItemMark"] as? String ?? "*") + " ")
        replace("<(?:br|hr)\\s*/?>", "\n"); replace("</(?:p|div|ul|ol|blockquote)>", "\n\n")
        replace("<[^>]+>", ""); replace("\n{3,}", "\n\n")
        result = try decodeHTML(result).trimmingCharacters(in: .whitespacesAndNewlines)
        for (token, block) in codeBlocks { result = result.replacingOccurrences(of: token, with: block) }
        return result
    }
}
