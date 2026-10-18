import Foundation
import Darwin

public enum Templates {
    public static func render(_ template: String, note: Note, selection: String = "", custom: [String: String] = [:], now: Date = Date(), selectionRange: NSRange? = nil, loadTemplate: ((String) -> String?)? = nil) -> String {
        render(template, note: note, selection: selection, custom: custom, now: now, selectionRange: selectionRange, loadTemplate: loadTemplate, depth: 0)
    }
    private static func render(_ template: String, note: Note, selection: String, custom: [String: String], now: Date, selectionRange: NSRange?, loadTemplate: ((String) -> String?)?, depth: Int) -> String {
        guard depth < 20 else { return template }
        let escaped = "\u{E000}" + UUID().uuidString + "\u{E001}"
        var input = template.replacingOccurrences(of: "\\[[", with: escaped + "[[")
        input = input.replacingOccurrences(of: "\\{{", with: escaped + "{{").replacingOccurrences(of: "\\%%", with: escaped + "%%")
        let regex = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
        var output = input
        let lines = note.content.components(separatedBy: "\n"), body = lines.dropFirst().joined(separator: "\n")
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed() {
            if (input as NSString).substring(to: match.range.location).hasSuffix(escaped) { continue }
            guard let full = Range(match.range, in: output), let keyRange = Range(match.range(at: 1), in: input) else { continue }
            let parts = input[keyRange].split(separator: "|", omittingEmptySubsequences: false).map(String.init), key = parts[0]
            let replacement: String?
            if let customValue = custom[key] { replacement = customValue }
            else {
                switch key {
                case "draft": replacement = note.content
                case "title": replacement = lines.first ?? ""
                case "display_title": replacement = note.title.trimmingCharacters(in: .whitespaces)
                case "safe_title": replacement = note.title.replacingOccurrences(of: "[/\\\\:]", with: "-", options: .regularExpression).replacingOccurrences(of: "[\\x00-\\x1F*?<>|#]", with: "", options: .regularExpression)
                case "body": replacement = body
                case "trimmed_body": replacement = body.trimmingCharacters(in: .whitespacesAndNewlines)
                case "body_preview": replacement = String(body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces).prefix(140))
                case "selection": replacement = selection.isEmpty ? note.content : selection
                case "selection_only": replacement = selection
                case "selection_start": replacement = String(selectionRange?.location ?? 0)
                case "selection_length": replacement = String(selectionRange?.length ?? (selection as NSString).length)
                case "line":
                    if parts.count > 1 {
                        let indexes = parts[1].components(separatedBy: "..")
                        func index(_ text: String, fallback: Int) -> Int { guard let number = Int(text) else { return fallback }; return number < 0 ? lines.count + number : number - 1 }
                        let start = max(0, min(lines.count, index(indexes[0], fallback: 0)))
                        let end = max(start, min(lines.count - 1, indexes.count > 1 ? index(indexes[1], fallback: lines.count - 1) : start))
                        replacement = start < lines.count ? lines[start...end].joined(separator: "\n") : ""
                    } else {
                        let text = note.content as NSString, range = selectionRange ?? NSRange(location: 0, length: 0)
                        let start = min(max(0, range.location), text.length), length = min(max(0, range.length), text.length - start)
                        replacement = text.substring(with: text.lineRange(for: NSRange(location: start, length: length))).trimmingCharacters(in: .newlines)
                    }
                case "uuid": replacement = note.id.uuidString
                case "tags": replacement = note.tags.joined(separator: ", ")
                case "hashtags": replacement = note.tags.map { "#" + $0 }.joined(separator: " ")
                case "permalink", "draft_open_url": replacement = "draftly://open?uuid=\(note.id.uuidString)"
                case "created_latitude", "created_longitude", "modified_latitude", "modified_longitude":
                    let metadataKey = key.components(separatedBy: "_").enumerated().map { $0.offset == 0 ? $0.element : $0.element.capitalized }.joined()
                    replacement = note.scriptMetadata?[metadataKey] ?? "0"
                case "date", "time", "created", "modified":
                    var date = key == "created" ? note.createdAt : key == "modified" ? note.modifiedAt : now
                    var format = parts.count > 1 ? parts[1] : key == "time" ? "%Y-%m-%d-%H-%M-%S" : "%Y-%m-%d"
                    if parts.count > 2 { date = (try? ScriptUtilities.adjustDate(["date": APIValues.date(date), "adjustment": parts[1]])) ?? date; format = parts[2] }
                    replacement = formatDate(date, format: format)
                case "template":
                    if parts.count > 1, let source = loadTemplate?(parts[1]) { replacement = render(source, note: note, selection: selection, custom: custom, now: now, selectionRange: selectionRange, loadTemplate: loadTemplate, depth: depth + 1) }
                    else { replacement = nil }
                default: replacement = nil
                }
            }
            if let replacement { output.replaceSubrange(full, with: replacement) }
        }
        for (pattern, transform) in [("\\{\\{([\\s\\S]*?)\\}\\}", { (text: String) in text.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? text }), ("%%([\\s\\S]*?)%%", { MarkdownRenderer.render($0) })] {
            let pattern = try! NSRegularExpression(pattern: pattern)
            let source = output
            for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
                if (source as NSString).substring(to: match.range.location).hasSuffix(escaped) { continue }
                guard let range = Range(match.range, in: output), let inner = Range(match.range(at: 1), in: source) else { continue }
                output.replaceSubrange(range, with: transform(String(source[inner])))
            }
        }
        return output.replacingOccurrences(of: escaped, with: "")
    }
    public static func formatDate(_ date: Date, format: String) -> String {
        if format.hasPrefix("~") || format.hasPrefix("=") {
            let formatter = DateFormatter(); var pattern = String(format.dropFirst())
            if pattern.hasPrefix("("), let end = pattern.firstIndex(of: ")") { formatter.locale = Locale(identifier: String(pattern[pattern.index(after: pattern.startIndex)..<end])); pattern = String(pattern[pattern.index(after: end)...]) }
            switch pattern {
            case "shortDate": formatter.dateStyle = .short
            case "shortDateTime": formatter.dateStyle = .short; formatter.timeStyle = .short
            case "longDate": formatter.dateStyle = .long
            case "longDateTime": formatter.dateStyle = .long; formatter.timeStyle = .long
            case "iso8601": return APIValues.date(date)
            default: if format.hasPrefix("~") { formatter.setLocalizedDateFormatFromTemplate(pattern) } else { formatter.dateFormat = pattern }
            }
            return formatter.string(from: date)
        }
        // Keep support for existing Draftly date templates.
        if !format.contains("%") { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = format; return formatter.string(from: date) }
        var timestamp = time_t(date.timeIntervalSince1970), components = tm(); localtime_r(&timestamp, &components)
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = format.withCString { strftime(&buffer, 4096, $0, &components) }
        return count > 0 ? String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self) : format
    }
}
