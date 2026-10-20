import Foundation
import Testing
@testable import Draftly

@Suite("Editor text statistics")
struct EditorTextStatisticsTests {
    private let referenceText = """
    Prueba visual 50 — Referencia con Unicode 🐼 café

    Español: áéíóú ñ. 日本語。 Emoji: 🐼 🌿 🚀.

    Una segunda línea para comprobar Unicode.

    visual-qa-20261019
    """

    @Test func neutralUnicodeFixtureMatchesTheObservedDraftsFooter() {
        let statistics = EditorTextStatistics(referenceText)
        #expect(statistics.characterCount == 149)
        #expect(statistics.wordCount == 26)
        #expect(statistics.footerText == "149c 26w")
    }

    @Test(arguments: ["", " \t\n\r\u{00a0}", "... — !!!"])
    func emptyWhitespaceAndPunctuationHaveNoWords(_ text: String) {
        let statistics = EditorTextStatistics(text)
        #expect(statistics.wordCount == 0)
        #expect(statistics.characterCount == text.count)
    }

    @Test func punctuationAndHyphensUseLinguisticWordBoundaries() {
        #expect(EditorTextStatistics("Hello, world!").wordCount == 2)
        #expect(EditorTextStatistics("one-two three_four").wordCount == 3)
    }

    @Test func JapaneseAndChineseDoNotRequireWhitespace() {
        #expect(EditorTextStatistics("日本語。").wordCount == 2)
        #expect(EditorTextStatistics("你好世界。").wordCount == 3)
    }

    @Test func emojiSymbolsAndJoinedSequencesCountAsTokens() {
        #expect(EditorTextStatistics("🐼 🌿 🚀").wordCount == 3)
        #expect(EditorTextStatistics("a🐼b").wordCount == 3)
        let joined = EditorTextStatistics("👨‍👩‍👧‍👦 🇦🇷")
        #expect(joined.characterCount == 3)
        #expect(joined.wordCount == 2)
    }

    @Test func countingPreservesTheExactInputAndProducesAnImmutableSnapshot() {
        var text = "cafe\u{301}\r\n👨‍👩‍👧‍👦"
        let originalUTF16 = Array(text.utf16)
        let statistics = EditorTextStatistics(text)
        #expect(Array(text.utf16) == originalUTF16)
        #expect(statistics.characterCount == 6)
        #expect(statistics.wordCount == 2)
        text += " another word"
        #expect(statistics.characterCount == 6 && statistics.wordCount == 2)
        #expect(EditorTextStatistics(text).wordCount == 4)
    }

    @Test @MainActor func unchangedLongContentDoesNotRepeatTokenization() {
        let text = String(repeating: "word ", count: 20_000)
        var measurements = 0
        let cache = EditorTextStatisticsCache { text in
            measurements += 1
            return EditorTextStatistics(text)
        }
        let first = cache.value(for: text)
        #expect(first.characterCount == 100_000)
        #expect(first.wordCount == 20_000)
        for _ in 0..<25 { #expect(cache.value(for: text) == first) }
        #expect(measurements == 1)
        #expect(text.count == 100_000)
    }

    @Test @MainActor func changedContentOfTheSameLengthInvalidatesTheCache() {
        var measurements = 0
        let cache = EditorTextStatisticsCache { text in
            measurements += 1
            return EditorTextStatistics(text)
        }
        let first = cache.value(for: "one two")
        let next = cache.value(for: "onetwo!")
        #expect(first.characterCount == next.characterCount)
        #expect(first.wordCount == 2 && next.wordCount == 1)
        #expect(cache.value(for: "onetwo!") == next && measurements == 2)
    }

    @Test(arguments: [20_000, 40_000], [false, true])
    func longWordSequencesDoNotCountOverlappingFrameworkFragments(_ words: Int, _ trailingWhitespace: Bool) {
        var text = String(repeating: "word ", count: words)
        if !trailingWhitespace { text.removeLast() }
        let statistics = EditorTextStatistics(text)
        #expect(statistics.wordCount == words)
        #expect(statistics.characterCount == words * 5 - (trailingWhitespace ? 0 : 1))
    }

    @Test func oneLongWordKeepsOverlappingFrameworkRangesAsOneToken() {
        let text = String(repeating: "a", count: 100_000)
        let statistics = EditorTextStatistics(text)
        #expect(statistics.characterCount == 100_000)
        #expect(statistics.wordCount == 1)
    }

    @Test @MainActor func emptyContentReplacesThePreviousCachedValue() {
        let cache = EditorTextStatisticsCache()
        #expect(cache.value(for: "café 🐼").wordCount == 2)
        #expect(cache.value(for: "").footerText == "0c 0w")
        #expect(cache.value(for: "new text").footerText == "8c 2w")
    }

    @Test @MainActor func footerCachesDoNotShareWindowState() {
        var firstMeasurements = 0, secondMeasurements = 0
        let first = EditorTextStatisticsCache { text in
            firstMeasurements += 1
            return EditorTextStatistics(text)
        }
        let second = EditorTextStatisticsCache { text in
            secondMeasurements += 1
            return EditorTextStatistics(text)
        }
        #expect(first.value(for: "first note").wordCount == 2)
        #expect(second.value(for: "second note").wordCount == 2)
        #expect(first.value(for: "first note").wordCount == 2)
        #expect(firstMeasurements == 1 && secondMeasurements == 1)
    }
}
