import Foundation

/// Evaluate the documented draft search terms. Compile patterns once per query.
public struct DraftQuery {
    private struct Term {
        var field: String
        var value: String
        var omitted: Bool
        var regex: NSRegularExpression?
    }
    private var groups: [[Term]] = [[]]
    private let caseSensitive: Bool
    public private(set) var error: String?

    public init(_ query: String, caseSensitive: Bool = false) {
        self.caseSensitive = caseSensitive
        let text = Array(query), count = text.count
        var index = 0
        while index < count {
            while index < count && text[index].isWhitespace { index += 1 }
            guard index < count else { break }
            var token = "", quoted = false, regex = false, escaped = false
            while index < count {
                let character = text[index]
                if character.isWhitespace && !quoted && !regex { break }
                token.append(character); index += 1
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == "\"" && !regex { quoted.toggle() }
                if character == "/" && !quoted && (regex || token == "/" || token == "-/") { regex.toggle() }
            }
            if token == "OR" { groups.append([]); continue }
            if token == "AND" { continue }
            var omitted = false
            if token.hasPrefix("-") { omitted = true; token.removeFirst() }
            var field = "content"
            for prefix in ["title:", "tag:", "flag:"] where token.hasPrefix(prefix) {
                field = String(prefix.dropLast()); token.removeFirst(prefix.count); break
            }
            var pattern: NSRegularExpression?
            if token.hasPrefix("/") && token.hasSuffix("/") && token.count > 1 {
                field = "regex"; token = String(token.dropFirst().dropLast())
                do { pattern = try NSRegularExpression(pattern: token, options: caseSensitive ? [] : [.caseInsensitive]) }
                catch { self.error = "The search regular expression is invalid." }
            } else if token.hasPrefix("\"") && token.hasSuffix("\"") && token.count > 1 { token = String(token.dropFirst().dropLast()) }
            groups[groups.count - 1].append(Term(field: field, value: token, omitted: omitted, regex: pattern))
        }
        if groups.count > 1 && groups.contains(where: { $0.isEmpty }) { error = "Use a search term on each side of OR." }
    }

    public func matches(_ note: Note, titlesOnly: Bool = false) -> Bool {
        guard error == nil else { return false }
        func contains(_ text: String, _ value: String) -> Bool {
            caseSensitive ? text.contains(value) : text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return groups.contains { terms in terms.allSatisfy { term in
            let found: Bool
            switch term.field {
            case "title": found = contains(note.content.components(separatedBy: .newlines).first ?? "", term.value)
            case "tag":
                found = note.tags.contains { tag in
                    let value = TagRules.normalize(term.value), tag = TagRules.normalize(tag)
                    return value.hasSuffix("/") || value.hasSuffix("::") ? tag.hasPrefix(value) : tag == value
                }
            case "flag":
                let names = ["none", "red", "orange", "yellow", "green", "blue", "purple", "gray"]
                let value = term.value.lowercased()
                found = value == "any" ? note.flag > 0 : note.flag == (Int(value) ?? names.firstIndex(of: value) ?? -1)
            case "regex": found = term.regex?.firstMatch(in: note.content, options: [.anchored], range: NSRange(note.content.startIndex..., in: note.content)) != nil
            default: found = contains(titlesOnly ? note.content.components(separatedBy: .newlines).first ?? "" : note.content, term.value)
            }
            return term.omitted ? !found : found
        } }
    }
}

/// Find editor matches with UTF-16 ranges.
public struct EditorFindQuery {
    private let expression: NSRegularExpression?
    public let usesRegularExpression: Bool
    public init(_ query: String, caseSensitive: Bool = false, regularExpression: Bool = false) throws {
        usesRegularExpression = regularExpression
        expression = query.isEmpty ? nil : try NSRegularExpression(
            pattern: regularExpression ? query : NSRegularExpression.escapedPattern(for: query),
            options: caseSensitive ? [] : [.caseInsensitive])
    }
    public func matches(in text: String) -> [NSRange] {
        expression?.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)).map(\.range) ?? []
    }
    public func replacement(in text: String, at range: NSRange, with replacement: String) -> String? {
        guard let expression,
              let match = expression.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
                .first(where: { $0.range == range }) else { return nil }
        return expression.replacementString(for: match, in: text, offset: 0,
            template: usesRegularExpression ? replacement : NSRegularExpression.escapedTemplate(for: replacement))
    }
    package enum ReplacementError: Error { case limitExceeded, interrupted }

    package func replacingAll(in text: String, with replacement: String, maximumUTF16Length: Int,
                              continueMatching: () -> Bool) throws -> String {
        guard maximumUTF16Length > 0, maximumUTF16Length <= Int.max / 2, replacement.utf16.count <= maximumUTF16Length else { throw ReplacementError.limitExceeded }
        guard continueMatching() else { throw ReplacementError.interrupted }
        guard let expression else {
            guard text.utf16.count <= maximumUTF16Length else { throw ReplacementError.limitExceeded }
            return text
        }
        let source = text as NSString
        let template = usesRegularExpression ? replacement : NSRegularExpression.escapedTemplate(for: replacement)
        let units = Array(template.utf16)
        let references = usesRegularExpression ? units.indices.dropLast().filter {
            units[$0] == 36 && (48...57).contains(units[$0 + 1])
        }.count : 0
        let output = NSMutableString(capacity: min(source.length, maximumUTF16Length))
        var consumed = 0
        var failure: ReplacementError?
        expression.enumerateMatches(in: text, options: [.reportProgress, .reportCompletion],
            range: NSRange(location: 0, length: source.length)) { match, flags, stop in
            guard continueMatching(), !flags.contains(.internalError) else {
                failure = .interrupted; stop.pointee = true; return
            }
            guard let match else { return }
            let gap = match.range.location - consumed
            guard gap >= 0, gap <= maximumUTF16Length - output.length else {
                failure = .limitExceeded; stop.pointee = true; return
            }
            let longest = (0..<match.numberOfRanges).map { match.range(at: $0).length }.max() ?? 0
            let (captureBound, overflow) = longest.multipliedReportingOverflow(by: references)
            let (bound, sumOverflow) = captureBound.addingReportingOverflow(units.count)
            // Bound a single template expansion before Foundation allocates it.
            guard !overflow, !sumOverflow, bound <= maximumUTF16Length * 2 else {
                failure = .limitExceeded; stop.pointee = true; return
            }
            let value = expression.replacementString(for: match, in: text, offset: 0, template: template)
            guard value.utf16.count <= maximumUTF16Length - output.length - gap else {
                failure = .limitExceeded; stop.pointee = true; return
            }
            output.append(source.substring(with: NSRange(location: consumed, length: gap)))
            output.append(value)
            consumed = NSMaxRange(match.range)
        }
        if let failure { throw failure }
        guard continueMatching() else { throw ReplacementError.interrupted }
        guard source.length - consumed <= maximumUTF16Length - output.length else { throw ReplacementError.limitExceeded }
        output.append(source.substring(from: consumed))
        return output as String
    }

    public func replacingAll(in text: String, with replacement: String) -> String {
        guard let expression else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count),
            withTemplate: usesRegularExpression ? replacement : NSRegularExpression.escapedTemplate(for: replacement))
    }
}
