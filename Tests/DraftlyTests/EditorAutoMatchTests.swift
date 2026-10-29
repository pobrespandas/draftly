import AppKit
import Testing
@testable import Draftly

@Suite("Editor auto-match") @MainActor
struct EditorAutoMatchTests {
    private func event(_ input: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: input,
            charactersIgnoringModifiers: input, isARepeat: false, keyCode: 0))
    }

    @Test(arguments: [("(", ")"), ("[", "]"), ("{", "}"), ("\"", "\""), ("'", "'")])
    func matchingKeysWrapUnicodeSelectionAndPlaceCursorInside(open: String, close: String) throws {
        let view = DraftTextView(frame: .zero)
        view.autoMatch = true
        view.string = "A café 🐼 Z"
        let selection = (view.string as NSString).range(of: "café 🐼")
        view.setSelectedRange(selection)
        view.keyDown(with: try event(open))
        #expect(view.string == "A " + open + "café 🐼" + close + " Z")
        #expect(view.selectedRange() == NSRange(location: selection.location + 1, length: selection.length))
        view.string = ""
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.keyDown(with: try event(open))
        #expect(view.string == open + close)
        #expect(view.selectedRange() == NSRange(location: 1, length: 0))
    }

    @Test func optionModifiedCharacterStillPairs() throws {
        let view = DraftTextView(frame: .zero)
        view.autoMatch = true
        view.keyDown(with: try event("[", modifiers: .option))
        #expect(view.string == "[]")
        #expect(view.selectedRange() == NSRange(location: 1, length: 0))
    }

    @Test func directInsertionDoesNotPairEvenWhenEnabled() {
        let view = DraftTextView(frame: .zero)
        view.autoMatch = true
        view.insertText("(", replacementRange: NSRange(location: 0, length: 0))
        #expect(view.string == "(")
    }
}
