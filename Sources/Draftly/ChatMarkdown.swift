import SwiftUI

/// Keep block boundaries while Foundation renders inline Markdown.
struct ChatMarkdownBlock: Equatable {
    enum Kind: Equatable { case paragraph, heading(Int), item(String), quote, code }
    let kind: Kind
    let text: String

    static func parse(_ source: String) -> [Self] {
        var blocks: [Self] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        func flush() {
            if !paragraph.isEmpty { blocks.append(Self(kind: .paragraph, text: paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for line in source.components(separatedBy: .newlines) {
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flush()
                if let content = code { blocks.append(Self(kind: .code, text: content.joined(separator: "\n"))); code = nil }
                else { code = [] }
            } else if code != nil { code?.append(line) }
            else if line.trimmingCharacters(in: .whitespaces).isEmpty { flush() }
            else if line.hasPrefix("> ") { flush(); blocks.append(Self(kind: .quote, text: String(line.dropFirst(2)))) }
            else {
                let hashes = line.prefix(while: { $0 == "#" }).count
                if (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") {
                    flush(); blocks.append(Self(kind: .heading(hashes), text: String(line.dropFirst(hashes + 1))))
                } else if let range = line.range(of: #"^\s*(?:[-*+] |[0-9]+[.)] )"#, options: .regularExpression) {
                    flush()
                    let marker = String(line[range]).trimmingCharacters(in: .whitespaces)
                    blocks.append(Self(kind: .item(marker.first?.isNumber == true ? marker : "•"), text: String(line[range.upperBound...])))
                } else { paragraph.append(line) }
            }
        }
        flush()
        if let code { blocks.append(Self(kind: .code, text: code.joined(separator: "\n"))) }
        return blocks
    }
}

struct ChatMarkdown: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ChatMarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .code:
                    Text(block.text).font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                case .heading(let level):
                    inline(block.text).font(level <= 2 ? .headline : .subheadline).bold()
                case .item(let marker):
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text(marker); inline(block.text) }
                case .quote:
                    HStack(spacing: 8) { Rectangle().fill(.secondary).frame(width: 2); inline(block.text).foregroundStyle(.secondary) }
                        .fixedSize(horizontal: false, vertical: true)
                case .paragraph: inline(block.text)
                }
            }
        }
        .textSelection(.enabled)
    }
    private func inline(_ value: String) -> Text {
        Text((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value))
    }
}
