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

    @Test func trackingSeparatorsUseAllThreePanelBoundariesOnTheSameNativeSplit() throws {
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
        #expect(tracking.map(\.dividerIndex) == [0, 1, 2])
        #expect(tracking.allSatisfy { $0.splitView === controller.splitView })
        let navigation = try #require(items.firstIndex { $0.itemIdentifier.rawValue == "navigate" })
        let editorBoundary = try #require(items.firstIndex { ($0 as? NSTrackingSeparatorToolbarItem)?.dividerIndex == 1 })
        let creation = try #require(items.firstIndex { $0.itemIdentifier.rawValue == "capture" })
        #expect(navigation < editorBoundary && editorBoundary < creation)
        let share = try #require(items.firstIndex { $0.itemIdentifier.rawValue == "share" })
        let searchBoundary = try #require(items.firstIndex { $0.itemIdentifier.rawValue == "actionInspectorTrackingSeparator" })
        let palette = try #require(items.firstIndex { $0.itemIdentifier.rawValue == "palette" })
        let separator = try #require(items[searchBoundary] as? NSTrackingSeparatorToolbarItem)
        #expect(share < searchBoundary && searchBoundary < palette)
        #expect(separator.dividerIndex == 2 && separator.splitView === controller.splitView)
        #expect(items[searchBoundary].action == nil)
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

    @Test func actionsToggleKeepsItsEnabledAppearanceAcrossVisibilityAndEditorChangesWithoutADraft() async throws {
        _ = NSApplication.shared
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        model.showActions = false
        let controller = LibrarySplitController(model: model, panels: (0..<4).map { _ in AnyView(Color.clear) })
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.contentViewController = nil }
        let toolbar = ReferenceToolbar(model: model, window: window, splitView: controller.splitView)
        defer { withExtendedLifetime(toolbar) {} }
        let item = try #require(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "actions" })
        let image = try #require(item.image)
        #expect(image.isTemplate)
        for throughButton in [false, true] {
            for _ in 0..<2 {
                let wasVisible = model.showActions
                #expect(item.isEnabled)
                if throughButton {
                    #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
                } else {
                    model.showActions.toggle()
                }
                await TestMainQueue.drain()
                #expect(model.showActions != wasVisible)
                #expect(item.isEnabled)
                #expect(item.image === image)
            }
        }
        model.editor.selection = NSRange(location: 0, length: 0)
        await TestMainQueue.drain()
        #expect(item.image === image)
    }

}
