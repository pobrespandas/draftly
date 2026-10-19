import Foundation
import Testing
@testable import DraftlyCore

@Suite("Draft search contracts")
struct DraftQueryTests {
    @Test func searchSupportsTermsPhrasesNegationAndBooleanGroups() {
        let note = Note(content: "Red title\nA blue parachute and café")
        #expect(DraftQuery("red blue").matches(note))
        #expect(DraftQuery("red AND blue").matches(note))
        #expect(DraftQuery("missing OR red blue").matches(note))
        #expect(!DraftQuery("red -blue").matches(note))
        #expect(DraftQuery("\"blue parachute\" -green").matches(note))
        #expect(!DraftQuery("\"red blue\"").matches(note))
        #expect(DraftQuery("cafe").matches(note))
        #expect(!DraftQuery("RED", caseSensitive: true).matches(note))
        #expect(!DraftQuery("blue").matches(note, titlesOnly: true))
        #expect(DraftQuery("").matches(note))
    }
    @Test func searchSupportsFieldsNestedTagsAndFlags() {
        let note = Note(content: "Red title\nblue", tags: ["status::open", "base/a"], flag: 5)
        #expect(DraftQuery("title:\"Red title\" tag:status:: flag:blue").matches(note))
        #expect(DraftQuery("tag:base/ flag:5").matches(note))
        #expect(DraftQuery("flag:any -tag:other").matches(note))
        #expect(!DraftQuery("title:blue").matches(note))
        #expect(!DraftQuery("status").matches(note))
        #expect(!DraftQuery("flag:missing").matches(note))
    }
    @Test func regularExpressionsMatchAtTheStartAndReportInvalidPatterns() {
        #expect(DraftQuery(#"/\d+/"#).matches(Note(content: "123 item")))
        #expect(!DraftQuery(#"/\d+/"#).matches(Note(content: "item 123")))
        #expect(DraftQuery(#"/.*\[\[.*\]\].*/"#).matches(Note(content: "link [[note]]")))
        #expect(DraftQuery("/[/").error != nil)
        #expect(DraftQuery("red OR").error != nil)
        #expect(!DraftQuery("OR red").matches(Note(content: "red")))
    }

    @Test func literalSearchUsesUTF16AndEscapesPatternsAndReplacements() throws {
        let query = try EditorFindQuery("café.")
        let text = "🐼 CAFÉ. café."
        #expect(query.matches(in: text) == [NSRange(location: 3, length: 5), NSRange(location: 9, length: 5)])
        #expect(query.replacingAll(in: text, with: "$1\\") == "🐼 $1\\ $1\\")
        #expect(try EditorFindQuery("café.", caseSensitive: true).matches(in: text) == [NSRange(location: 9, length: 5)])
    }
    @Test func regularExpressionsSupportCapturesAndRejectInvalidPatterns() throws {
        let query = try EditorFindQuery("(café) ([0-9]+)", regularExpression: true)
        #expect(query.replacingAll(in: "🐼 café 42\ncafé 7", with: "$2:$1") == "🐼 42:café\n7:café")
        #expect(throws: (any Error).self) { try EditorFindQuery("[", regularExpression: true) }
        #expect(try EditorFindQuery("").matches(in: "🐼").isEmpty)
        #expect(try EditorFindQuery("").replacingAll(in: "🐼", with: "changed") == "🐼")
        #expect(try EditorFindQuery("$", regularExpression: true).matches(in: "🐼") == [NSRange(location: 2, length: 0)])
    }
}
