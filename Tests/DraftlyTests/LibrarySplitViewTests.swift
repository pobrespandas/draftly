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
            let initialFrame = window.frame
            window.contentViewController = controller
            let attachedFrame = window.frame
            controller.viewDidAppear()
            let appearedFrame = window.frame
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            let settledFrame = window.frame
            let settledConstraints = controller.view.constraints.filter { $0.isActive }.map { $0.description }
            window.setContentSize(NSSize(width: width, height: 600))
            let resizedFrame = window.frame
            window.layoutIfNeeded()
            controller.view.layoutSubtreeIfNeeded()
            let frames = controller.splitViewItems.map { $0.viewController.view.frame }
            let diagnostic = Comment(rawValue: "Requested width: \(width); initial: \(initialFrame); attached: \(attachedFrame); appeared: \(appearedFrame); settled: \(settledFrame); resized: \(resizedFrame); window: \(window.frame); min: \(window.minSize); max: \(window.maxSize); content: \(window.contentView?.frame ?? .zero); content min: \(window.contentMinSize); screen: \(window.screen?.visibleFrame ?? .zero); split: \(controller.splitView.frame); panel frames: \(frames); arranged frames: \(controller.splitView.arrangedSubviews.map(\.frame)); divider: \(controller.splitView.dividerThickness); toolbar: \(window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []); active controller constraints: \(settledConstraints)")
            #expect(frames.allSatisfy { $0.width >= 159 })
            #expect(frames.reduce(0) { $0 + $1.width } <= width, diagnostic)
            #expect(abs(controller.splitView.frame.width - width) < 1, diagnostic)
            window.contentViewController = nil
        }
    }

    @Test func initialPanelConstraintLayoutCanBeMeasuredWithoutShowingAWindow() async throws {
        _ = NSApplication.shared
        for deferred in [false, true] {
            let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
            model.setFiltersVisible(true)
            model.showActions = true
            let panels = (0..<4).map { _ in AnyView(Color.clear) }
            let controller = LibrarySplitController(model: model, panels: panels)
            let allConstraints: [NSLayoutConstraint] = controller.splitViewItems.flatMap { $0.viewController.view.constraints }
            let constraints = allConstraints.filter { constraint in
                constraint.firstAttribute == .width && constraint.secondItem == nil
                    && constraint.priority == NSLayoutConstraint.Priority.defaultHigh && constraint.isActive
            }
            #expect(constraints.count == 3)
            if deferred { NSLayoutConstraint.deactivate(constraints) }
            let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            let initial = window.frame
            window.contentViewController = controller
            let attached = window.frame
            if deferred { NSLayoutConstraint.activate(constraints) }
            controller.viewDidAppear()
            await settleLayout(controller)
            window.setContentSize(NSSize(width: 850, height: 600))
            window.layoutIfNeeded()
            controller.view.layoutSubtreeIfNeeded()
            print("Panel constraint diagnostic deferred=\(deferred) initial=\(initial) attached=\(attached) final=\(window.frame) content=\(window.contentView?.frame ?? .zero) split=\(controller.splitView.frame) panels=\(controller.splitView.arrangedSubviews.map(\.frame))")
            #expect(!window.isVisible)
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
        for _ in 0..<4 { split.addArrangedSubview(NSView()) }
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
        #expect(abs(widths[0] - 240) < 1, Comment(rawValue: "Panel widths: \(widths); window: \(window.frame); content min: \(window.contentMinSize); screen: \(window.screen?.visibleFrame ?? .zero); split: \(controller.splitView.frame); arranged frames: \(controller.splitView.arrangedSubviews.map(\.frame)); divider: \(controller.splitView.dividerThickness)"))
        #expect(abs(widths[1] - 280) < 1)
        #expect(controller.splitViewItems[2].viewController.view.frame.width >= 240)
        controller.splitView.setPosition(260, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        let resizedWidths = controller.splitViewItems.prefix(2).map { $0.viewController.view.frame.width }
        #expect(abs(resizedWidths[0] - 260) < 1, Comment(rawValue: "Resized panel widths: \(resizedWidths); split: \(controller.splitView.frame); divider: \(controller.splitView.dividerThickness)"))

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
            #expect(abs(controller.splitViewItems[index].viewController.view.frame.width - resizedWidths[index]) <= 1, "Panel \(index) must restore width \(resizedWidths[index]) within one point.")
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
            #expect(abs(controller.splitViewItems[index].viewController.view.frame.width - resizedWidths[index]) <= 1)
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

    @Test func compressedPanelsRestoreChosenWidthsWhenTheWindowWidens() async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences(prefix: "Draftly.PanelWidthRestoration.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral café 🐼")
        let model = WindowModel(library: library,
            dependencies: WindowDependencies(preferences: WindowPreferences(defaults: preferences.defaults)))
        model.select(note.id)
        model.editor.selection = NSRange(location: 8, length: 4)
        let focus = model.editor.focusToken
        let panels = (0..<4).map { _ in AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)) }
        let controller = LibrarySplitController(model: model, panels: panels)
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1200, height: 700))
        defer { window.contentViewController = nil }
        controller.viewDidAppear()
        await settleLayout(controller)
        controller.splitView.setPosition(255, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        controller.splitView.setPosition(255 + 300 + controller.splitView.dividerThickness, ofDividerAt: 1)
        controller.view.layoutSubtreeIfNeeded()
        let chosen = controller.splitViewItems.prefix(2).map { $0.viewController.view.frame.width }
        #expect(abs(chosen[0] - 255) <= 1 && abs(chosen[1] - 300) <= 1)

        window.setContentSize(NSSize(width: 850, height: 600))
        controller.view.setFrameSize(NSSize(width: 850, height: 600))
        await settleLayout(controller)
        model.showActions = true
        controller.update(panels: panels)
        await settleLayout(controller)
        #expect(abs(controller.splitView.bounds.width - 850) <= 1)
        #expect(!controller.splitViewItems[3].isCollapsed)
        #expect(controller.splitViewItems[2].viewController.view.frame.width >= 240)

        window.setContentSize(NSSize(width: 1200, height: 800))
        controller.view.setFrameSize(NSSize(width: 1200, height: 800))
        await settleLayout(controller)
        #expect(abs(controller.splitView.bounds.width - 1200) <= 1)
        for index in 0..<2 {
            #expect(abs(controller.splitViewItems[index].viewController.view.frame.width - chosen[index]) <= 1,
                "Panel \(index) must recover its chosen width after temporary compression.")
        }
        #expect(abs(controller.splitViewItems[3].viewController.view.frame.width - 260) <= 1)

        model.showActions = false
        controller.update(panels: panels)
        await settleLayout(controller)
        model.showActions = true
        controller.update(panels: panels)
        await settleLayout(controller)
        for index in 0..<2 {
            #expect(abs(controller.splitViewItems[index].viewController.view.frame.width - chosen[index]) <= 1)
        }
        #expect(abs(controller.splitViewItems[3].viewController.view.frame.width - 260) <= 1)

        controller.splitView.setPosition(controller.splitViewItems[0].viewController.view.frame.width + controller.splitView.dividerThickness + 320, ofDividerAt: 1)
        controller.view.layoutSubtreeIfNeeded()
        controller.splitView.setPosition(controller.splitView.bounds.width - 290 - controller.splitView.dividerThickness, ofDividerAt: 2)
        controller.view.layoutSubtreeIfNeeded()
        let updated = [0, 1, 3].map { controller.splitViewItems[$0].viewController.view.frame.width }
        #expect(abs(updated[0] - chosen[0]) <= 1 && abs(updated[1] - 320) <= 1 && abs(updated[2] - 290) <= 1)
        window.setContentSize(NSSize(width: 850, height: 600))
        controller.view.setFrameSize(NSSize(width: 850, height: 600))
        await settleLayout(controller)
        model.showActions = false
        controller.update(panels: panels)
        await settleLayout(controller)
        model.showActions = true
        controller.update(panels: panels)
        await settleLayout(controller)
        window.setContentSize(NSSize(width: 1200, height: 800))
        controller.view.setFrameSize(NSSize(width: 1200, height: 800))
        await settleLayout(controller)
        for (index, width) in zip([0, 1, 3], updated) {
            #expect(abs(controller.splitViewItems[index].viewController.view.frame.width - width) <= 1,
                "A new divider position must survive another narrow window and panel toggle.")
        }
        #expect(model.editor.noteID == note.id && model.editor.content == note.content)
        #expect(model.editor.selection == NSRange(location: 8, length: 4) && model.editor.focusToken == focus)
    }

    @Test(arguments: [0, 1, 2])
    func draggingACompressedDividerChangesOnlyAdjacentPanelPreferences(divider: Int) async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences(prefix: "Draftly.CompressedDivider.")
        defer { preferences.close() }
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false),
            dependencies: WindowDependencies(preferences: WindowPreferences(defaults: preferences.defaults)))
        model.showActions = true
        let panels = (0..<4).map { _ in AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)) }
        let controller = LibrarySplitController(model: model, panels: panels)
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1200, height: 700))
        defer { window.contentViewController = nil }
        controller.viewDidAppear()
        await settleLayout(controller)
        controller.splitView.setPosition(255, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        controller.splitView.setPosition(255 + 300 + controller.splitView.dividerThickness, ofDividerAt: 1)
        controller.view.layoutSubtreeIfNeeded()
        controller.splitView.setPosition(1200 - 310 - controller.splitView.dividerThickness, ofDividerAt: 2)
        controller.view.layoutSubtreeIfNeeded()
        var expected = controller.splitViewItems.map { $0.viewController.view.frame.width }
        window.setContentSize(NSSize(width: 850, height: 600))
        controller.view.setFrameSize(NSSize(width: 850, height: 600))
        await settleLayout(controller)
        let dividerView = controller.splitViewItems[divider].viewController.view
        let currentPosition = dividerView.convert(dividerView.bounds, to: controller.splitView).maxX
        controller.splitView.setPosition(currentPosition + (divider == 1 ? -2 : 2), ofDividerAt: divider)
        controller.view.layoutSubtreeIfNeeded()
        for index in [divider, divider + 1] where index != 2 {
            expected[index] = controller.splitViewItems[index].viewController.view.frame.width
        }
        window.setContentSize(NSSize(width: 1200, height: 800))
        controller.view.setFrameSize(NSSize(width: 1200, height: 800))
        await settleLayout(controller)
        for index in [0, 1, 3] {
            #expect(abs(controller.splitViewItems[index].viewController.view.frame.width - expected[index]) <= 1,
                "Divider \(divider) must preserve the preferences of unrelated panel \(index).")
        }
    }

    @Test func realPanelContentRestoresDefaultWidthsAfterNarrowExpansion() async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences(prefix: "Draftly.RealPanelWidths.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Neutral café 🐼\nA short preview for the list.")
        let model = WindowModel(library: library,
            dependencies: WindowDependencies(preferences: WindowPreferences(defaults: preferences.defaults)))
        let panels = [
            AnyView(DraftFiltersPanel(model: model, showTagSearch: .constant(false)).defaultAppStorage(preferences.defaults)),
            AnyView(DraftListPanel(model: model, library: library,
                selection: Binding(get: { model.selectedDraftIDs }, set: { model.selectedDraftIDs = $0 }))
                .defaultAppStorage(preferences.defaults)),
            AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)),
            AnyView(ActionListPanel(model: model, library: library).defaultAppStorage(preferences.defaults))
        ]
        let controller = LibrarySplitController(model: model, panels: panels)
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1200, height: 800))
        defer { window.contentViewController = nil }
        controller.viewDidAppear()
        await settleLayout(controller)
        let chosen = controller.splitViewItems.prefix(2).map { $0.viewController.view.frame.width }
        #expect(abs(chosen[0] - 240) <= 1 && abs(chosen[1] - 280) <= 1)
        window.setContentSize(NSSize(width: 850, height: 600))
        controller.view.setFrameSize(NSSize(width: 850, height: 600))
        await settleLayout(controller)
        model.showActions = true
        controller.update(panels: panels)
        await settleLayout(controller)
        window.setContentSize(NSSize(width: 1200, height: 800))
        controller.view.setFrameSize(NSSize(width: 1200, height: 800))
        await settleLayout(controller)
        for index in 0..<2 {
            #expect(abs(controller.splitViewItems[index].viewController.view.frame.width - chosen[index]) <= 1,
                "Real panel \(index) must recover its width after temporary compression.")
        }
    }

    private func settleLayout(_ controller: LibrarySplitController) async {
        for _ in 0..<4 {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            controller.view.window?.layoutIfNeeded()
            controller.view.layoutSubtreeIfNeeded()
        }
    }
}
