import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Editor redraw regression") @MainActor
struct EditorRedrawTests {
    @Test func shortDraftClearsLongDraftAndKeepsSelection() async throws {
        _ = NSApplication.shared
        let session = EditorSession()
        session.load(Note(content: String(repeating: "Long draft 🐼\n", count: 60)))
        let host = NSHostingView(rootView: NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, onChange: {}))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await settle()
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        let text = try #require(findText(host))
        #expect(text.string.contains("Long draft"))
        var short = Note(content: "Short 🐼")
        short.scriptMetadata = ["selectionStart": "6", "selectionLength": "2"]
        session.load(short, focusEditor: false)
        await settle()
        host.layoutSubtreeIfNeeded()
        #expect(text.string == short.content)
        #expect(text.selectedRange() == NSRange(location: 6, length: 2))
        #expect(text.drawsBackground)
        let scroll = try #require(text.enclosingScrollView)
        #expect(scroll.drawsBackground)
        let bitmap = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
        scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
        let color = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 40)?.usingColorSpace(.sRGB))
        let expected = try #require(scroll.backgroundColor.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - expected.redComponent) < 0.03)
        #expect(abs(color.greenComponent - expected.greenComponent) < 0.03)
        #expect(abs(color.blueComponent - expected.blueComponent) < 0.03)
        window.contentView = nil
    }
    private func settle() async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }
}
