import AppKit
import QuartzCore
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Library panel layout") @MainActor
struct LibrarySplitViewTests {
    @MainActor private final class TitleChanges { var count = 0 }

    @Test func filtersUseTheNativeFullHeightSidebarBehavior() throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let controller = LibrarySplitController(model: model, panels: (0..<4).map { _ in AnyView(Color.clear) })
        let sidebar = controller.splitViewItems[0]
        #expect(sidebar.behavior == .sidebar)
        #expect(sidebar.allowsFullHeightLayout)
        #expect(!sidebar.canCollapseFromWindowResize)
        #expect(!sidebar.isSpringLoaded)
        #expect(controller.splitViewItems[1].behavior == .default)
    }

    @Test func allPanelsFitTheSupportedWindowWidths() async throws {
        _ = NSApplication.shared
        for width in [850.0, 1033.0, 1200.0] {
            let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
            model.setFiltersVisible(true)
            model.showActions = true
            let panels = (0..<4).map { _ in AnyView(Color.clear) }
            let controller = LibrarySplitController(model: model, panels: panels)
            let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentViewController = controller
            controller.viewDidAppear()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            controller.view.setFrameSize(NSSize(width: width, height: 600))
            controller.view.layoutSubtreeIfNeeded()
            let frames = controller.splitViewItems.map { $0.viewController.view.frame }
            #expect(frames.allSatisfy { $0.width >= 159 })
            #expect(frames.reduce(0) { $0 + $1.width } <= width)
            #expect(abs(controller.splitView.frame.width - width) < 1)
            window.contentViewController = nil
        }
    }

    @Test func togglingPanelsDoesNotResetTheWindowTitle() async throws {
        _ = NSApplication.shared
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        model.window = window
        let split = NSSplitView()
        split.isVertical = true
        for _ in 0..<3 { split.addArrangedSubview(NSView()) }
        window.contentView = split
        let toolbar = ReferenceToolbar(model: model, window: window, splitView: split)
        let changes = TitleChanges()
        let observation = window.observe(\.title, options: [.new]) { _, _ in
            MainActor.assumeIsolated { changes.count += 1 }
        }
        model.toggleFilters()
        model.toggleDraftList()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(changes.count == 0)
        withExtendedLifetime((toolbar, observation)) {}
    }

    @Test func nativePanelsKeepTheirControllersAndWidthsAcrossCollapses() async throws {
        _ = NSApplication.shared
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let panels = (0..<4).map { _ in AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)) }
        let controller = LibrarySplitController(model: model, panels: panels)
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.contentViewController = nil }
        controller.viewDidAppear()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        controller.view.layoutSubtreeIfNeeded()
        let tracking = try #require(window.toolbar?.items.compactMap { $0 as? NSTrackingSeparatorToolbarItem }.first)
        #expect(tracking.splitView === controller.splitView)
        let filterToggle = try #require(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "filters" })
        #expect(filterToggle.isEnabled)
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
        #expect(filterToggle.isEnabled)
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
        model.setDraftListVisible(false)
        controller.update(panels: panels)
        model.setFiltersVisible(true)
        controller.update(panels: panels)
        for _ in 0..<2 {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        controller.view.layoutSubtreeIfNeeded()
        #expect(!controller.splitViewItems[0].isCollapsed && !controller.splitViewItems[1].isCollapsed)
        for index in 0..<2 {
            #expect(abs(controller.splitViewItems[index].viewController.view.frame.width - resizedWidths[index]) < 1)
        }
    }

    @Test func actionsUsesItsDefaultWidthWhenInitiallyVisible() async throws {
        _ = NSApplication.shared
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        model.showActions = true
        let panels = (0..<4).map { _ in AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)) }
        let controller = LibrarySplitController(model: model, panels: panels)
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1115, height: 645), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1115, height: 645))
        defer { window.contentViewController = nil }
        controller.viewDidAppear()
        await settleLayout(controller)
        #expect(abs(controller.splitView.bounds.width - 1115) <= 1)
        #expect(abs(controller.splitViewItems[0].viewController.view.frame.width - 240) <= 1)
        #expect(abs(controller.splitViewItems[1].viewController.view.frame.width - 280) <= 1)
        #expect(abs(controller.splitViewItems[3].viewController.view.frame.width - 260) <= 1)
    }

    @Test func actionsOpensAtItsDefaultWidthWithoutACompletionResize() async throws {
        _ = NSApplication.shared
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let panels = (0..<4).map { _ in AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)) }
        let controller = LibrarySplitController(model: model, panels: panels)
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1115, height: 645), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1115, height: 645))
        defer { window.contentViewController = nil }
        controller.viewDidAppear()
        await settleLayout(controller)
        #expect(abs(controller.splitView.bounds.width - 1115) <= 1)
        #expect(controller.splitViewItems[3].isCollapsed)
        model.showActions = true
        controller.update(panels: panels)
        window.layoutIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        let beforeCompletion = controller.splitViewItems[3].viewController.view.frame.width
        #expect(abs(controller.splitView.bounds.width - 1115) <= 1)
        #expect(abs(beforeCompletion - 260) <= 1, "Actions width: \(beforeCompletion), split width: \(controller.splitView.bounds.width)")
        await settleLayout(controller)
        #expect(abs(controller.splitViewItems[3].viewController.view.frame.width - beforeCompletion) <= 1)
        #expect(controller.splitViewItems[3].minimumThickness == 200)
        #expect(abs(controller.splitViewItems[0].viewController.view.frame.width - 240) <= 1)
        #expect(abs(controller.splitViewItems[1].viewController.view.frame.width - 280) <= 1)
    }

    @Test func allUserPanelWidthsSurviveHideAndShowWithoutACompletionResize() async throws {
        _ = NSApplication.shared
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        model.showActions = true
        let panels = (0..<4).map { _ in AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)) }
        let controller = LibrarySplitController(model: model, panels: panels)
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1200, height: 700))
        defer { window.contentViewController = nil }
        controller.viewDidAppear()
        await settleLayout(controller)
        #expect(abs(controller.splitView.bounds.width - 1200) <= 1)
        controller.splitView.setPosition(255, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        controller.splitView.setPosition(255 + 300 + controller.splitView.dividerThickness, ofDividerAt: 1)
        controller.view.layoutSubtreeIfNeeded()
        controller.splitView.setPosition(controller.splitView.bounds.width - 310 - controller.splitView.dividerThickness, ofDividerAt: 2)
        controller.view.layoutSubtreeIfNeeded()
        let indices = [0, 1, 3]
        let chosen = indices.map { controller.splitViewItems[$0].viewController.view.frame.width }
        #expect(abs(chosen[2] - 310) <= 1)
        #expect(chosen[0] >= 160 && chosen[1] >= 220)
        model.setDraftListVisible(false); model.showActions = false
        controller.update(panels: panels)
        await settleLayout(controller)
        #expect(indices.allSatisfy { controller.splitViewItems[$0].isCollapsed })
        model.setFiltersVisible(true); model.showActions = true
        controller.update(panels: panels)
        window.layoutIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        let beforeCompletion = indices.map { controller.splitViewItems[$0].viewController.view.frame.width }
        for (actual, expected) in zip(beforeCompletion, chosen) { #expect(abs(actual - expected) <= 1, "Restored width: \(actual), chosen native width: \(expected)") }
        await settleLayout(controller)
        let afterCompletion = indices.map { controller.splitViewItems[$0].viewController.view.frame.width }
        for (actual, expected) in zip(afterCompletion, beforeCompletion) { #expect(abs(actual - expected) <= 1) }
        #expect(controller.splitViewItems[2].viewController.view.frame.width >= 240)
        #expect(controller.splitViewItems[0].minimumThickness == 160)
        #expect(controller.splitViewItems[1].minimumThickness == 220)
        #expect(controller.splitViewItems[3].minimumThickness == 200)
    }

    private func settleLayout(_ controller: LibrarySplitController) async {
        for _ in 0..<4 {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            controller.view.window?.layoutIfNeeded()
            controller.view.layoutSubtreeIfNeeded()
        }
    }
}
