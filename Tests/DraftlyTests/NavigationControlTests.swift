import AppKit
import SwiftUI
import Testing
@testable import Draftly

@Suite("Navigation control rendering") @MainActor
struct NavigationControlTests {
    @Test func nativeNavigationImageKeepsTheMeasuredWideTriangle() async throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: PanelMenu(
            symbol: "arrowtriangle.down.fill", help: "Navigate", items: [.section("No navigation markers")],
            symbolSize: 11, symbolDimensions: NSSize(width: 11, height: 6.5)
        ).frame(width: 20, height: 25))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 25),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        func findButton(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton { return button }
            return view.subviews.lazy.compactMap { findButton($0) }.first
        }
        let button = try #require(findButton(host))
        let image = try #require(button.image)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 22, pixelsHigh: 13,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                                   bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = NSSize(width: 11, height: 6.5)
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 11, height: 6.5))
        NSGraphicsContext.restoreGraphicsState()
        let opaque = (0..<13).flatMap { y in (0..<22).compactMap { x -> NSPoint? in
            guard (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 else { return nil }
            return NSPoint(x: x, y: y)
        } }
        let minX = try #require(opaque.map(\.x).min()), maxX = try #require(opaque.map(\.x).max())
        let minY = try #require(opaque.map(\.y).min()), maxY = try #require(opaque.map(\.y).max())
        #expect(maxX - minX + 1 >= 20)
        #expect(maxY - minY + 1 >= 11)
        #expect(image.isTemplate)
        #expect(button.toolTip == "Navigate")
    }
}
