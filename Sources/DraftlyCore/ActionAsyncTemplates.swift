import Foundation

@MainActor extension Templates {
    static func renderAsyncConfigured(_ template: String, note: Note, selection: String = "", custom: [String: String] = [:], now: Date = Date(), selectionRange: NSRange? = nil, defaults: UserDefaults = .standard, loadTemplate: @escaping @MainActor (String) async throws -> String?, resolveTag: @escaping @MainActor (String) async throws -> String?) async throws -> String {
        try await renderAsync(template, note: note, selection: selection, custom: custom, now: now, selectionRange: selectionRange, loadTemplate: loadTemplate, resolveTag: resolveTag, depth: 0, markdown: { try MarkdownPreferences.render($0, defaults: defaults) })
    }
    private static func renderAsync(_ template: String, note: Note, selection: String, custom: [String: String], now: Date, selectionRange: NSRange?, loadTemplate: @MainActor (String) async throws -> String?, resolveTag: @MainActor (String) async throws -> String?, depth: Int, markdown: (String) throws -> String) async throws -> String {
        try Task.checkCancellation()
        guard depth < 20 else { return template }
        let escaped = "\u{E000}" + UUID().uuidString + "\u{E001}"
        var input = template.replacingOccurrences(of: "\\[[", with: escaped + "[[")
        input = input.replacingOccurrences(of: "\\{{", with: escaped + "{{").replacingOccurrences(of: "\\%%", with: escaped + "%%")
        let regex = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
        var output = input
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed() {
            if (input as NSString).substring(to: match.range.location).hasSuffix(escaped) { continue }
            guard let full = Range(match.range, in: output), let keyRange = Range(match.range(at: 1), in: input) else { continue }
            let parts = input[keyRange].split(separator: "|", omittingEmptySubsequences: false).map(String.init), key = parts[0]
            let replacement: String?
            if let customValue = custom[key] { replacement = customValue }
            else if let dynamic = try await resolveTag(key) { replacement = dynamic }
            else {
                switch key {
                case "template":
                    if parts.count > 1, let source = try await loadTemplate(parts[1]) { replacement = try await renderAsync(source, note: note, selection: selection, custom: custom, now: now, selectionRange: selectionRange, loadTemplate: loadTemplate, resolveTag: resolveTag, depth: depth + 1, markdown: markdown) }
                    else { replacement = nil }
                default: replacement = builtinValue(parts, note: note, selection: selection, now: now, selectionRange: selectionRange)
                }
            }
            if let replacement { output.replaceSubrange(full, with: replacement) }
        }
        return try finishTransforms(output, escaped: escaped, markdown: markdown)
    }
}

@MainActor extension ActionRunner {
    func renderTemplateAsync(_ text: String, note: Note, tags: [String: String]? = nil) async throws -> String {
        try checkCancellation()
        let selection = editor.selectedText
        let selectionRange = editor.safeSelection
        var location: [String: Double]?
        return try await Templates.renderAsyncConfigured(text, note: note, selection: selection,
            custom: tags ?? customTags, selectionRange: selectionRange, defaults: markdownDefaults,
            loadTemplate: { path in
                try await self.nativeValue("fileAPI", ["operation": "readString", "storage": "local", "path": "Templates/" + path]) as? String
            }, resolveTag: { key in
                try self.checkCancellation()
                switch key {
                case "clipboard": return try await self.nativeValue("getClipboard", [:]) as? String ?? ""
                case "latitude", "longitude":
                    if location == nil { location = try await self.nativeValue("location", [:]) as? [String: Double] }
                    return location.map { String($0[key] ?? 0) }
                default: return nil
                }
            })
    }

    func renderURLAsync(_ text: String, note: Note, encodeTags: Bool) async throws -> String {
        guard encodeTags else { return try await renderTemplateAsync(text, note: note) }
        let regex = try NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result), let original = Range(match.range, in: text) else { continue }
            let replacement = try await renderTemplateAsync(String(text[original]), note: note)
            result.replaceSubrange(range, with: replacement.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? replacement)
        }
        return result
    }
}
