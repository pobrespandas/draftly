import AppKit
import Testing
import SwiftUI
import DraftlyCore
@testable import Draftly

@Suite("Reference toolbar layout") @MainActor
struct ReferenceToolbarLayoutTests {
    @Test func separateSearchItemsKeepTheirDistinctRoutesAndFolderItemsKeepTheirCommands() async throws {
        _ = NSApplication.shared
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral toolbar draft")
        let model = WindowModel(library: library)
        model.select(note.id, focusEditor: false)
        var searches: [String] = []
        model.openQuickSearch = { searches.append($0) }
        let split = NSSplitView()
        for _ in 0..<4 { split.addArrangedSubview(NSView()) }
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let toolbar = ReferenceToolbar(model: model, window: window, splitView: split)
        defer { withExtendedLifetime(toolbar) {} }
        func item(_ id: String) throws -> NSToolbarItem {
            try #require(window.toolbar?.items.first { $0.itemIdentifier.rawValue == id })
        }
        func invoke(_ id: String) throws {
            let item = try item(id)
            #expect(!(item is NSToolbarItemGroup))
            #expect(item.isEnabled)
            #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        }
        try invoke("palette")
        #expect(model.showPalette && searches.isEmpty)
        model.showPalette = false
        try invoke("quickSearch")
        #expect(searches == [""] && !model.showPalette)
        #expect(try !item("inbox").isEnabled)
        try invoke("archive")
        await TestMainQueue.drain()
        #expect(library.notes.first?.isArchived == true)
        #expect(try !item("archive").isEnabled)
        try invoke("inbox")
        await TestMainQueue.drain()
        #expect(library.notes.first?.isArchived == false)
        try invoke("trash")
        await TestMainQueue.drain()
        #expect(library.notes.first?.trashedAt != nil)
        #expect(try !item("trash").isEnabled)
    }

    @Test func trackingSeparatorsUseBothPanelBoundariesOnTheSameNativeSplit() throws {
        _ = NSApplication.shared
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let controller = LibrarySplitController(model: model, panels: (0..<4).map { _ in AnyView(Color.clear) })
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.contentViewController = nil }
        let toolbar = ReferenceToolbar(model: model, window: window, splitView: controller.splitView)
        defer { withExtendedLifetime(toolbar) {} }
        let items = try #require(window.toolbar?.items)
        let tracking = items.compactMap { $0 as? NSTrackingSeparatorToolbarItem }
        #expect(tracking.map(\.dividerIndex) == [0, 1])
        #expect(tracking.allSatisfy { $0.splitView === controller.splitView })
        let navigation = try #require(items.firstIndex { $0.itemIdentifier.rawValue == "navigate" })
        let editorBoundary = try #require(items.firstIndex { ($0 as? NSTrackingSeparatorToolbarItem)?.dividerIndex == 1 })
        let creation = try #require(items.firstIndex { $0.itemIdentifier.rawValue == "capture" })
        #expect(navigation < editorBoundary && editorBoundary < creation)
    }

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

    @Test func floatingToggleReflectsWindowStateAndKeepsItsImageDuringOtherEdits() async throws {
        _ = NSApplication.shared
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let controller = LibrarySplitController(model: model, panels: (0..<4).map { _ in AnyView(Color.clear) })
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.contentViewController = nil }
        let toolbar = ReferenceToolbar(model: model, window: window, splitView: controller.splitView)
        defer { withExtendedLifetime(toolbar) {} }
        let button = try #require(toolbar.floatingButton)
        #expect(window.titlebarAccessoryViewControllers.contains { $0.view === button.superview && $0.layoutAttribute == .right })
        #expect(window.toolbar?.items.contains { $0.itemIdentifier.rawValue == "float" } == false)
        let off = try #require(button.image)
        #expect(button.toolTip == "Float on Top")
        _ = NSApp.sendAction(try #require(button.action), to: button.target, from: button)
        await TestMainQueue.drain()
        let on = try #require(button.image)
        #expect(model.isFloating)
        #expect(on !== off)
        #expect(on.tiffRepresentation != off.tiffRepresentation)
        #expect(on.size == off.size)
        model.editor.selection = NSRange(location: 0, length: 0)
        await TestMainQueue.drain()
        #expect(button.image === on)
        model.toggleFloat()
        await TestMainQueue.drain()
        #expect(button.image?.tiffRepresentation == off.tiffRepresentation)
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
