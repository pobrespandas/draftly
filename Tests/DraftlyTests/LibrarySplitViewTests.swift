import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Library panel layout") @MainActor
struct LibrarySplitViewTests {
    @Test func nativePanelsKeepTheirControllersAndWidthsAcrossCollapses() async throws {
        _ = NSApplication.shared
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let panels = (0..<4).map { _ in AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)) }
        let controller = LibrarySplitController(model: model, panels: panels)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.contentViewController = nil }
        controller.viewDidAppear()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        controller.view.layoutSubtreeIfNeeded()
        let originalControllers = controller.splitViewItems.map(\.viewController)
        let widths = controller.splitViewItems.prefix(2).map { $0.viewController.view.frame.width }
        #expect(abs(widths[0] - 240) < 1)
        #expect(abs(widths[1] - 280) < 1)
        #expect(controller.splitViewItems[2].viewController.view.frame.width >= 240)
        controller.splitView.setPosition(260, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        let resizedWidths = controller.splitViewItems.prefix(2).map { $0.viewController.view.frame.width }
        #expect(abs(resizedWidths[0] - 260) < 1)

        model.setDraftListVisible(false)
        controller.update(panels: panels)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        controller.view.layoutSubtreeIfNeeded()
        #expect(controller.splitViewItems[0].isCollapsed && controller.splitViewItems[1].isCollapsed)
        #expect(!controller.splitViewItems[2].isCollapsed)
        model.setFiltersVisible(true)
        controller.update(panels: panels)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        controller.view.layoutSubtreeIfNeeded()
        for index in 0..<2 {
            #expect(abs(controller.splitViewItems[index].viewController.view.frame.width - resizedWidths[index]) < 1, "Panel \(index) must restore width \(resizedWidths[index]).")
        }
        for (item, original) in zip(controller.splitViewItems, originalControllers) {
            #expect(item.viewController === original)
        }
    }
}
