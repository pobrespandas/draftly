import AppKit
import Testing
@testable import DraftlyCore
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

    @Test func markedTextCompositionDoesNotTriggerSyntaxStyling() throws {
        let session = EditorSession()
        session.load(Note(content: "caf"), focusEditor: false)
        let editor = NativeEditor(session: session, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: true, onChange: {})
        let coordinator = editor.makeCoordinator()
        let view = DraftTextView(frame: .zero)
        view.string = "caf"
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.setMarkedText("é", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let marker = NSAttributedString.Key("DraftlyCompositionMarker")
        let markedRange = view.markedRange()
        try #require(markedRange.location != NSNotFound)
        view.textStorage?.addAttribute(marker, value: true, range: markedRange)
        coordinator.textView = view

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))

        #expect(view.hasMarkedText())
        #expect(view.textStorage?.attribute(marker, at: markedRange.location, effectiveRange: nil) as? Bool == true)
        #expect(session.content == view.string)
    }
}
