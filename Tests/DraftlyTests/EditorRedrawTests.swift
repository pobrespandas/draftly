import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Editor redraw regression") @MainActor
struct EditorRedrawTests {
    @Test func explicitColorSchemeChangesTheCanvasWithoutChangingEditorState() async throws {
        _ = NSApplication.shared
        let session = EditorSession()
        session.load(Note(content: "Canvas 🐼\nPreserve this text"), focusEditor: false)
        session.selection = NSRange(location: 7, length: 2)
        func editor(_ scheme: ColorScheme) -> AnyView {
            AnyView(NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
                                 markdown: false, onChange: {}).environment(\.colorScheme, scheme))
        }
        let host = NSHostingView(rootView: editor(.light))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        defer { window.contentView = nil }
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        for (scheme, expected) in [(ColorScheme.light, CGFloat(1)), (.dark, CGFloat(0)), (.light, CGFloat(1))] {
            host.rootView = editor(scheme)
            host.layoutSubtreeIfNeeded()
            await settle()
            let text = try #require(findText(host))
            let color = try #require(text.backgroundColor.usingColorSpace(.sRGB))
            #expect(abs(color.redComponent - expected) < 0.01)
            #expect(abs(color.greenComponent - expected) < 0.01)
            #expect(abs(color.blueComponent - expected) < 0.01)
            #expect(text.string == session.content)
            #expect(text.selectedRange() == NSRange(location: 7, length: 2))
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func shortDraftClearsLongDraftAndKeepsSelection(appearanceName: NSAppearance.Name) async throws {
        _ = NSApplication.shared
        let session = EditorSession()
        session.load(Note(content: String(repeating: String(repeating: "Long draft 🐼 ", count: 20) + "\n", count: 60)))
        let theme = EditorTheme(name: "Redraw contract", foreground: "F0F0F0", background: "17324D")
        let host = NSHostingView(rootView: NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, theme: theme, onChange: {}))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = try #require(NSAppearance(named: appearanceName))
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
        let cleanSession = EditorSession()
        cleanSession.load(short, focusEditor: false)
        let cleanHost = NSHostingView(rootView: NativeEditor(session: cleanSession, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, theme: theme, onChange: {}))
        let cleanWindow = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        cleanWindow.appearance = window.appearance
        cleanWindow.contentView = cleanHost
        cleanHost.layoutSubtreeIfNeeded()
        await settle()
        let cleanText = try #require(findText(cleanHost))
        let cleanScroll = try #require(cleanText.enclosingScrollView)
        let cleanBitmap = try #require(cleanScroll.bitmapImageRepForCachingDisplay(in: cleanScroll.bounds))
        cleanScroll.cacheDisplay(in: cleanScroll.bounds, to: cleanBitmap)
        #expect(bitmap.pixelsWide == cleanBitmap.pixelsWide && bitmap.pixelsHigh == cleanBitmap.pixelsHigh)
        for y in stride(from: 100, to: bitmap.pixelsHigh - 40, by: 7) {
            for x in stride(from: 40, to: bitmap.pixelsWide - 40, by: 7) {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let expected = try #require(cleanBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                #expect(abs(color.redComponent - expected.redComponent) < 0.03)
                #expect(abs(color.greenComponent - expected.greenComponent) < 0.03)
                #expect(abs(color.blueComponent - expected.blueComponent) < 0.03)
            }
        }
        cleanWindow.contentView = nil
        window.contentView = nil
    }
    private func settle() async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }
}
