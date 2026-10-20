import Foundation

struct EditorTextStatistics: Equatable, Sendable {
    let characterCount: Int
    let wordCount: Int

    init(_ text: String) {
        characterCount = text.count
        guard !text.isEmpty else { wordCount = 0; return }
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = text
        var count = 0
        var previousRange: NSRange?
        // Keep symbols such as emoji. Omit punctuation and whitespace.
        tagger.enumerateTags(in: NSRange(text.startIndex..., in: text), unit: .word,
                             scheme: .tokenType, options: [.omitPunctuation, .omitWhitespace]) { _, range, _ in
            guard range.length > 0 else { return }
            // Long paragraphs can return overlapping fragments of the same token.
            if let previous = previousRange, NSIntersectionRange(previous, range).length > 0 {
                previousRange = NSUnionRange(previous, range)
            } else {
                count += 1
                previousRange = range
            }
        }
        wordCount = count
    }

    var footerText: String { "\(characterCount)c \(wordCount)w" }
}

@MainActor final class EditorTextStatisticsCache {
    private let measure: (String) -> EditorTextStatistics
    private var cachedText: String?
    private var cachedValue: EditorTextStatistics?

    init(measure: @escaping (String) -> EditorTextStatistics = EditorTextStatistics.init) {
        self.measure = measure
    }

    func value(for text: String) -> EditorTextStatistics {
        if let cachedText, cachedText == text, let cachedValue { return cachedValue }
        let value = measure(text)
        cachedText = text
        cachedValue = value
        return value
    }
}
