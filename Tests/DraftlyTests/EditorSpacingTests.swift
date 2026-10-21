import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Editor paragraph layout") @MainActor
struct EditorSpacingTests {
    @Test func unsetMultiplierKeepsLegacyAdditiveSpacingAndSafeParagraphDefault() {
        for stored in [0.0, -1, Double.nan, .infinity] {
            let style = EditorParagraphLayout.style(lineHeightMultiple: stored,
                paragraphSpacing: .nan, legacyLineSpacing: 2)
            #expect(style.lineSpacing == 2)
            #expect(style.lineHeightMultiple == 0)
            #expect(style.paragraphSpacing == 0)
        }
        let font = NSFont.systemFont(ofSize: 17)
        let expected = 1 + 2 / Double(NSLayoutManager().defaultLineHeight(for: font))
        #expect(EditorParagraphLayout.displayedMultiple(stored: 0, legacyLineSpacing: 2, font: font) == expected)
    }

    @Test func explicitMultiplierUsesFontHeightWithoutAddingLegacySpacingAndPersistsLocally() throws {
        let name = "Draftly.EditorSpacingTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(1.5, forKey: EditorParagraphLayout.lineHeightKey)
        defaults.set(8.0, forKey: EditorParagraphLayout.paragraphSpacingKey)
        let reopened = try #require(UserDefaults(suiteName: name))
        let style = EditorParagraphLayout.style(
            lineHeightMultiple: reopened.double(forKey: EditorParagraphLayout.lineHeightKey),
            paragraphSpacing: reopened.double(forKey: EditorParagraphLayout.paragraphSpacingKey),
            legacyLineSpacing: 12)
        #expect(style.lineHeightMultiple == 1.5)
        #expect(style.lineSpacing == 0)
        #expect(style.paragraphSpacing == 8)
        #expect(EditorParagraphLayout.style(lineHeightMultiple: 1, paragraphSpacing: -3, legacyLineSpacing: 2).paragraphSpacing == 0)
    }

    @Test func spacingUpdateRefreshesVisibleAttributesWithoutChangingUnicodeSelection() async throws {
        _ = NSApplication.shared
        let session = EditorSession()
        session.load(Note(content: "First café 🐼 paragraph\nSecond paragraph"), focusEditor: false)
        let range = (session.content as NSString).range(of: "café 🐼")
        session.selection = range
        func editor(_ multiple: Double, spacing: Double) -> NativeEditor {
            NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
                markdown: false, lineHeightMultiple: multiple, paragraphSpacing: spacing, onChange: {})
        }
        let host = NSHostingView(rootView: editor(0, spacing: 0))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func textView(_ view: NSView) -> NSTextView? {
            if let view = view as? NSTextView { return view }
            return view.subviews.lazy.compactMap { textView($0) }.first
        }
        for (multiple, spacing) in [(0.0, 0.0), (1.5, 8.0), (1.5, 12.0), (0.0, 0.0)] {
            host.rootView = editor(multiple, spacing: spacing)
            host.layoutSubtreeIfNeeded()
            await TestMainQueue.drain()
            let text = try #require(textView(host))
            let style = try #require(text.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            #expect(Double(style.lineHeightMultiple) == multiple)
            #expect(style.lineSpacing == (multiple == 0 ? 2 : 0))
            #expect(Double(style.paragraphSpacing) == spacing)
            #expect(text.string == session.content && text.selectedRange() == range)
        }
    }

    @Test func changingSpacingKeepsTheExistingUndoAndRedo() throws {
        let original = "Keep café 🐼\nSecond paragraph"
        let session = EditorSession(); session.load(Note(content: original), focusEditor: false)
        let native = NativeEditor(session: session, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: {})
        let coordinator = NativeEditor.Coordinator(native)
        let text = TestUndoTextView(frame: .zero)
        coordinator.textView = text; text.string = original
        text.manager.groupsByEvent = false
        defer { coordinator.textView = nil; text.manager.removeAllActions() }
        text.manager.beginUndoGrouping()
        try session.replace(NSRange(location: 0, length: 4), with: "Changed")
        coordinator.synchronizeScriptEdit()
        text.manager.endUndoGrouping()
        let edited = session.content
        coordinator.parent.lineHeightMultiple = 1.5
        coordinator.parent.paragraphSpacing = 10
        coordinator.highlight()
        #expect(text.string == edited && text.selectedRange() == session.safeSelection)
        #expect(text.manager.canUndo)
        text.manager.undo()
        #expect(text.string == original && session.content == original)
        text.manager.redo()
        #expect(text.string == edited && session.content == edited)
        let style = try #require(text.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.lineHeightMultiple == 1.5 && style.paragraphSpacing == 10)
    }
}
