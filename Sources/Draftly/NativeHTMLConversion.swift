import AppKit

struct NativeHTMLConversion {
    private func markdownDestination(_ raw: String) throws -> String {
        try decodeHTML(raw).unicodeScalars.map { scalar in
            switch scalar.value {
            case 9: return "%09"
            case 10: return "%0A"
            case 13: return "%0D"
            case 32: return "%20"
            case 60: return "%3C"
            case 62: return "%3E"
            case 40, 41, 92: return "\\" + String(scalar)
            default: return String(scalar)
            }
        }.joined()
    }
    private func convertLists(_ input: String, mark: String) throws -> String {
        struct List { var ordered: Bool; var next: Int }
        let tags = try NSRegularExpression(pattern: #"<(/?)(ul|ol|li)\b(?:[^'">]|"[^"]*"|'[^']*')*>"#, options: .caseInsensitive)
        let start = try NSRegularExpression(pattern: #"\s+start\s*=\s*(?:"(-?\d+)"|'(-?\d+)'|(-?\d+))"#, options: .caseInsensitive)
        let source = input as NSString
        let output = NSMutableString()
        var stack: [List] = [], offset = 0
        for match in tags.matches(in: input, range: NSRange(location: 0, length: source.length)) {
            output.append(source.substring(with: NSRange(location: offset, length: match.range.location - offset)))
            let closing = match.range(at: 1).length > 0
            let name = source.substring(with: match.range(at: 2)).lowercased()
            if name == "li", !closing {
                var marker = mark
                if let index = stack.indices.last, stack[index].ordered {
                    marker = "\(stack[index].next)."
                    if stack[index].next < Int.max { stack[index].next += 1 }
                }
                output.append("\n" + String(repeating: "    ", count: max(0, stack.count - 1)) + marker + " ")
            } else if name != "li", closing {
                if !stack.isEmpty { stack.removeLast() }
                if stack.isEmpty { output.append("\n\n") }
            } else if name != "li" {
                let tag = source.substring(with: match.range) as NSString
                let match = start.firstMatch(in: tag as String, range: NSRange(location: 0, length: tag.length))
                var initial = 1
                if let match, let group = (1...3).first(where: { match.range(at: $0).location != NSNotFound }) {
                    initial = Int(tag.substring(with: match.range(at: group))) ?? 1
                }
                stack.append(List(ordered: name == "ol", next: initial))
            }
            offset = match.range.location + match.range.length
        }
        output.append(source.substring(from: offset))
        return output as String
    }
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
        var protectedFragments: [(String, String)] = []
        for match in blocks.matches(in: result, range: NSRange(location: 0, length: source.length)).reversed() {
            let rawCode = source.substring(with: match.range(at: 1)).replacingOccurrences(
                of: #"</?span\b(?:[^'">]|"[^"]*"|'[^']*')*>"#, with: "", options: [.regularExpression, .caseInsensitive])
            let code = try decodeHTML(rawCode)
            let runs = code.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: max(3, runs + 1))
            let token = "DRAFTLYCODE" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let block = fence + "\n" + code + (code.hasSuffix("\n") ? "" : "\n") + fence
            protectedFragments.append((token, block))
            if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: "\n\n" + token + "\n\n") }
        }
        let inlineCode = try NSRegularExpression(pattern: #"<code\b(?:[^'">]|"[^"]*"|'[^']*')*>(.*?)</code\s*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let inlineSource = result as NSString
        for match in inlineCode.matches(in: result, range: NSRange(location: 0, length: inlineSource.length)).reversed() {
            let raw = inlineSource.substring(with: match.range(at: 1)).replacingOccurrences(
                of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let code = try decodeHTML(raw)
            let longest = code.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: longest + 1)
            let padding = code.hasPrefix("`") || code.hasSuffix("`") ||
                (code.hasPrefix(" ") && code.hasSuffix(" ") && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let token = "DRAFTLYCODE" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            protectedFragments.append((token, fence + (padding ? " " : "") + code + (padding ? " " : "") + fence))
            if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: token) }
        }
        for level in 1...6 { replace("(?s)<h\(level)\\b[^>]*>(.*?)</h\(level)>", "\n" + String(repeating: "#", count: level) + " $1\n") }
        if options["ignoreLinks"] as? Bool == true { replace(#"(?s)<a\b(?:[^'">]|"[^"]*"|'[^']*')*>(.*?)</a\s*>"#, "$1") }
        else {
            let inline = options["inlineLinks"] as? Bool ?? true
            let expression = try NSRegularExpression(pattern: #"<a\b(?:(?:[^'">]|"[^"]*"|'[^']*')*?\s)href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))(?:(?:[^'">]|"[^"]*"|'[^']*')*)>(.*?)</a\s*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
            var reference = 0
            func convertLinks(_ source: String) throws -> (String, [String]) {
                let text = source as NSString
                let matches = expression.matches(in: source, range: NSRange(location: 0, length: text.length))
                var replacements: [(NSRange, String)] = [], definitions: [String] = []
                for match in matches {
                    guard let group = (1...3).first(where: { match.range(at: $0).location != NSNotFound }) else { continue }
                    let target = try markdownDestination(text.substring(with: match.range(at: group)))
                    let token = "DRAFTLYLINK" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                    protectedFragments.append((token, target))
                    let label = text.substring(with: match.range(at: 4))
                    if inline { replacements.append((match.range, "[" + label + "](" + token + ")")) }
                    else {
                        reference += 1
                        replacements.append((match.range, "[" + label + "][\(reference)]"))
                        definitions.append("[\(reference)]: " + token)
                    }
                }
                var converted = source
                for (range, value) in replacements.reversed() {
                    if let range = Range(range, in: converted) { converted.replaceSubrange(range, with: value) }
                }
                return (converted, definitions)
            }
            if inline { result = try convertLinks(result).0 }
            else if options["linksEachParagraph"] as? Bool == true {
                replace("</p\\s*>", "</p>")
                result = try result.components(separatedBy: "</p>").map { paragraph in
                    let (converted, definitions) = try convertLinks(paragraph)
                    return converted + "\n\n" + definitions.joined(separator: "\n")
                }.joined(separator: "\n\n")
            } else {
                let (converted, definitions) = try convertLinks(result)
                result = converted + "\n\n" + definitions.joined(separator: "\n")
            }
        }
        let imagePattern = #"<img\b(?:[^'">]|"[^"]*"|'[^']*')*>"#
        if options["ignoreImages"] as? Bool == true { replace(imagePattern, "") }
        else {
            let images = try NSRegularExpression(pattern: imagePattern, options: .caseInsensitive)
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
                var replacement = ""
                if let src = values["src"] {
                    let label = try decodeHTML(values["alt"] ?? "").map { character in
                        "\\[]*_`".contains(character) ? "\\" + String(character) : String(character)
                    }.joined()
                    let destination = try markdownDestination(src)
                    let token = "DRAFTLYIMAGE" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                    protectedFragments.append((token, "![" + label + "](" + destination + ")"))
                    replacement = token
                }
                if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: replacement) }
            }
        }
        let emphasis = options["emphasisMark"] as? String ?? "_", strong = options["strongMark"] as? String ?? "**"
        replace("(?s)<(?:strong|b)\\b[^>]*>(.*?)</(?:strong|b)>", options["ignoreEmphasis"] as? Bool == true ? "$1" : strong + "$1" + strong)
        replace("(?s)<(?:em|i)\\b[^>]*>(.*?)</(?:em|i)>", options["ignoreEmphasis"] as? Bool == true ? "$1" : emphasis + "$1" + emphasis)
        result = try convertLists(result, mark: options["ulItemMark"] as? String ?? "*")
        replace("<(?:br|hr)\\s*/?>", "\n"); replace("</(?:p|div|ul|ol|blockquote)>", "\n\n")
        replace("<[^>]+>", ""); replace("\n{3,}", "\n\n")
        result = try decodeHTML(result).trimmingCharacters(in: .whitespacesAndNewlines)
        for (token, fragment) in protectedFragments { result = result.replacingOccurrences(of: token, with: fragment) }
        return result
    }
}
