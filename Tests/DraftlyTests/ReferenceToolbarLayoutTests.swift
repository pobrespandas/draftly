import AppKit
import Testing
import SwiftUI
import DraftlyCore
@testable import Draftly

@Suite("Reference toolbar layout") @MainActor
struct ReferenceToolbarLayoutTests {
    @Test func actionsToggleReflectsVisibilityFromTheModelAndKeepsTheSameImageOnUnrelatedUpdates() async throws {
        _ = NSApplication.shared
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        model.showActions = false
        let controller = LibrarySplitController(model: model, panels: (0..<4).map { _ in AnyView(Color.clear) })
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.contentViewController = nil }
        let toolbar = ReferenceToolbar(model: model, window: window, splitView: controller.splitView)
        defer { withExtendedLifetime(toolbar) {} }
        let item = try #require(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "actions" })
        let closed = try #require(item.image)
        model.showActions = true
        await TestMainQueue.drain()
        let opened = try #require(item.image)
        #expect(opened !== closed)
        model.editor.selection = NSRange(location: 0, length: 0)
        await TestMainQueue.drain()
        #expect(item.image === opened)
        model.showActions = false
        await TestMainQueue.drain()
        #expect(item.image !== opened)
        #expect(item.isEnabled)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func actionsToggleHasMoreContrastWhenItsPanelIsVisible(_ appearance: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearance))
        func contrast(_ visible: Bool) throws -> Double {
            let image = try #require(ReferenceToolbar.actionsToggleImage(isVisible: visible))
            #expect(!image.isTemplate)
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            var background = 1.0
            appearance.performAsCurrentDrawingAppearance {
                background = Double(NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!.redComponent)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
                NSGraphicsContext.restoreGraphicsState()
            }
            return (0..<32).reduce(0.0) { total, y in
                total + (0..<32).reduce(0.0) { row, x in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return row }
                    return row + Double(color.alphaComponent) * abs(Double(color.redComponent) - background)
                }
            }
        }
        #expect(try contrast(true) > contrast(false) * 1.2)
    }

}
