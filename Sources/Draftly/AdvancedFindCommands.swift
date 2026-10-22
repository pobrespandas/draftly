import Foundation
import DraftlyCore

@MainActor
struct AdvancedFindCommands {
    let model: WindowModel
    private var editor: EditorSession { model.editor }

    func select(_ range: NSRange) {
        editor.selection = range
        editor.synchronizeScriptEdit?()
    }

    func navigate(in ranges: [NSRange], backward: Bool) {
        guard !ranges.isEmpty else { return }
        let selection = editor.safeSelection
        if backward { select(ranges.last { $0.location < selection.location } ?? ranges[ranges.count - 1]) }
        else { select(ranges.first { $0.location >= NSMaxRange(selection) && $0 != selection } ?? ranges[0]) }
    }

    func replace(query: Result<EditorFindQuery, Error>, range: NSRange, with replacement: String) {
        guard let query = try? query.get(),
              let value = query.replacement(in: editor.content, at: range, with: replacement) else { return }
        editor.content = (editor.content as NSString).replacingCharacters(in: range, with: value)
        editor.selection = NSRange(location: range.location, length: value.utf16.count)
        editor.synchronizeScriptEdit?()
        model.contentChanged()
        _ = model.flush()
    }

    func replaceAll(query: Result<EditorFindQuery, Error>, with replacement: String) {
        guard let query = try? query.get() else { return }
        editor.content = query.replacingAll(in: editor.content, with: replacement)
        editor.selection = editor.safeSelection
        editor.synchronizeScriptEdit?()
        model.contentChanged()
        _ = model.flush()
    }
}

struct AdvancedFindRequest: Codable, Equatable {
    var text: String
    var replacement: String
    var caseSensitive: Bool
    var regularExpression: Bool

    var historyTitle: String { "Find: " + text + (replacement.isEmpty ? "" : ", Replace: " + replacement) }

    mutating func reverseValues() { swap(&text, &replacement) }

    func query() throws -> EditorFindQuery {
        try EditorFindQuery(text, caseSensitive: caseSensitive, regularExpression: regularExpression)
    }
}

@MainActor
struct AdvancedFindHistory {
    static let storageKey = "editor.advancedFind.history"
    let defaults: UserDefaults

    var requests: [AdvancedFindRequest] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let requests = try? JSONDecoder().decode([AdvancedFindRequest].self, from: data) else { return [] }
        return requests
    }

    func record(_ request: AdvancedFindRequest) throws {
        _ = try request.query()
        var values = requests.filter { $0 != request }
        values.insert(request, at: 0)
        defaults.set(try JSONEncoder().encode(values), forKey: Self.storageKey)
    }

    func clear() { defaults.removeObject(forKey: Self.storageKey) }
}

enum AdvancedFindResult {
    private static let lineBreaks = try! NSRegularExpression(pattern: #"\r\n|[\r\n\u2028\u2029]"#)

    static func preview(in text: String, range: NSRange) -> String {
        let source = text as NSString
        guard range.location >= 0, range.length >= 0, range.location <= source.length,
              range.length <= source.length - range.location else { return "" }
        let line = source.lineRange(for: range)
        let number = lineBreaks.numberOfMatches(in: text, range: NSRange(location: 0, length: line.location)) + 1
        return "L\(number): " + source.substring(with: line).trimmingCharacters(in: .newlines)
    }
}
