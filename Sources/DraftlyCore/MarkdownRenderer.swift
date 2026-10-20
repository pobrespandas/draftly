import Foundation

public enum MarkdownRenderer {
    public static func render(_ text: String) -> String {
        var output: [String] = []
        var code: [String]? = nil
        var list = false
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if let block = code { output.append("<pre><code>\(escape(block.joined(separator: "\n")))</code></pre>"); code = nil }
                else { if list { output.append("</ul>"); list = false }; code = [] }
                continue
            }
            if code != nil { code!.append(line); continue }
            if line.range(of: "^\\s*[-*+] ", options: .regularExpression) != nil {
                if !list { output.append("<ul>"); list = true }
                let item = line.replacingOccurrences(of: "^\\s*[-*+] ", with: "", options: .regularExpression)
                output.append("<li>\(inline(item))</li>"); continue
            }
            if list { output.append("</ul>"); list = false }
            let hashes = line.prefix(while: { $0 == "#" }).count
            if hashes > 0 && hashes <= 6 && line.dropFirst(hashes).hasPrefix(" ") {
                output.append("<h\(hashes)>\(inline(String(line.dropFirst(hashes + 1))))</h\(hashes)>")
            } else if line.hasPrefix("> ") { output.append("<blockquote>\(inline(String(line.dropFirst(2))))</blockquote>") }
            else if line == "---" || line == "***" { output.append("<hr>") }
            else if !line.isEmpty { output.append("<p>\(inline(line))</p>") }
        }
        if list { output.append("</ul>") }
        if let code { output.append("<pre><code>\(escape(code.joined(separator: "\n")))</code></pre>") }
        return output.joined(separator: "\n")
    }
    public static func page(_ body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <style>:root{color-scheme:light dark}body{font:17px -apple-system;line-height:1.65;max-width:760px;margin:48px auto;padding:0 28px}pre,code{font-family:ui-monospace,monospace;background:#8882;border-radius:5px}pre{padding:16px;white-space:pre-wrap}blockquote{border-left:3px solid #8885;padding-left:18px;opacity:.8}a{color:#568bea}hr{border:0;border-top:1px solid #8884}</style></head><body>\(body)</body></html>
        """
    }
    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func inline(_ text: String) -> String {
        var result = escape(text)
        for (pattern, replacement) in [("`([^`]+)`", "<code>$1</code>"), ("\\*\\*(.+?)\\*\\*", "<strong>$1</strong>"), ("(?<!\\*)\\*([^*]+)\\*(?!\\*)", "<em>$1</em>"), ("~~(.+?)~~", "<del>$1</del>"), ("\\[([^\\]]+)\\]\\((https?://[^ )]+)\\)", "<a href=\"$2\">$1</a>")] {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result
    }
}
