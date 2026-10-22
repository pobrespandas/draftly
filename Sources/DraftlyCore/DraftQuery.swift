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
    public func replacingAll(in text: String, with replacement: String) -> String {
        guard let expression else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count),
            withTemplate: usesRegularExpression ? replacement : NSRegularExpression.escapedTemplate(for: replacement))
    }
}
