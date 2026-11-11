import Testing
@testable import Draftly

struct ChatMarkdownTests {
    @Test func preservesBlocksAndUnicode() {
        let blocks = ChatMarkdownBlock.parse("# Café 🐼\n\n- **uno**\n2. dos\n> cita\n```swift\nlet x = 1\n```")
        #expect(blocks.map(\.kind) == [.heading(1), .item("•"), .item("2."), .quote, .code])
        #expect(blocks.last?.text == "let x = 1")
        #expect(blocks.first?.text == "Café 🐼")
    }
    @Test func unfinishedCodeRemainsVisibleDuringStreaming() {
        #expect(ChatMarkdownBlock.parse("before\n```\na ** b") == [
            .init(kind: .paragraph, text: "before"), .init(kind: .code, text: "a ** b")])
    }
}
