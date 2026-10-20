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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1115, height: 645), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1115, height: 645), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
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

@Suite("Visible panel animation frames", .serialized) @MainActor
struct LibrarySplitAnimationTests {
    private struct FrameSample {
        let editorLeft: CGFloat
        let editorRight: CGFloat
    }

    @MainActor private final class Fixture {
        let model: WindowModel
        let panels: [AnyView]
        let controller: LibrarySplitController
        let window: NSWindow
        let noteID: UUID
        let content: String
        let selection: NSRange

        init(animationsEnabled: @escaping @MainActor () -> Bool) throws {
            _ = NSApplication.shared
            let content = "Animation 🐼\nNeutral body"
            let selection = NSRange(location: 10, length: 2)
            let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
            let noteID = try model.library.createNote(content: content).id
            model.select(noteID)
            model.editor.selection = selection
            let panels = [AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)),
                      AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)),
                      AnyView(NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
                                           lineSpacing: 2, markdown: false, onChange: {})),
                      AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity))]
            let controller = LibrarySplitController(model: model, panels: panels, animationsEnabled: animationsEnabled)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            self.content = content; self.selection = selection; self.model = model
            self.noteID = noteID; self.panels = panels; self.controller = controller; self.window = window
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.title = "Neutral panel animation test"
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 1200, height: 700))
            window.orderFront(nil)
            controller.viewDidAppear()
        }

        func close() {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }
    }

    @Test func individualVisibleTransitionsHaveIntermediateFramesWithoutBackwardMotion() async throws {
        let fixture = try Fixture(animationsEnabled: { true })
        defer { fixture.close() }
        try await settle(fixture)
        #expect(fixture.window.isVisible)
        #expect(abs(fixture.controller.splitView.bounds.width - 1200) <= 1)
        let filters = width(fixture, at: 0), drafts = width(fixture, at: 1)

        try await transition(fixture, edge: \.editorRight, name: "Open Actions") { fixture.model.showActions = true }
        #expect(abs(width(fixture, at: 3) - 260) <= 1)
        fixture.controller.splitView.setPosition(fixture.controller.splitView.bounds.width - 290 - fixture.controller.splitView.dividerThickness, ofDividerAt: 2)
        fixture.controller.view.layoutSubtreeIfNeeded()
        try await settle(fixture)
        let actions = width(fixture, at: 3)
        #expect(abs(actions - 290) <= 1)
        try await transition(fixture, edge: \.editorRight, name: "Hide Actions") { fixture.model.showActions = false }
        try await transition(fixture, edge: \.editorRight, name: "Restore Actions") { fixture.model.showActions = true }
        #expect(abs(width(fixture, at: 3) - actions) <= 1)

        try await transition(fixture, edge: \.editorLeft, name: "Hide Filters") { fixture.model.setFiltersVisible(false) }
        try await transition(fixture, edge: \.editorLeft, name: "Restore Filters") { fixture.model.setFiltersVisible(true) }
        #expect(abs(width(fixture, at: 0) - filters) <= 1)
        try await transition(fixture, edge: \.editorLeft, name: "Hide Filters Before Draft List") { fixture.model.setFiltersVisible(false) }
        try await transition(fixture, edge: \.editorLeft, name: "Hide Draft List") { fixture.model.setDraftListVisible(false) }
        try await transition(fixture, edge: \.editorLeft, name: "Restore Draft List") { fixture.model.setDraftListVisible(true) }
        #expect(abs(width(fixture, at: 1) - drafts) <= 1)
        try await transition(fixture, edge: \.editorLeft, name: "Restore Final Filters") { fixture.model.setFiltersVisible(true) }
        #expect(abs(width(fixture, at: 0) - filters) <= 1)
        #expect(abs(width(fixture, at: 1) - drafts) <= 1)
        #expect(abs(width(fixture, at: 3) - actions) <= 1)
        checkEditor(fixture)
    }

    @Test func rapidVisibleRequestsKeepTheCurrentAnimationMonotonicAndApplyTheLatestState() async throws {
        let fixture = try Fixture(animationsEnabled: { true })
        defer { fixture.close() }
        try await settle(fixture)
        let filters = width(fixture, at: 0), drafts = width(fixture, at: 1)
        var actions = [sample(fixture)]
        fixture.model.showActions = true
        fixture.controller.update(panels: fixture.panels)
        try await collect(fixture, into: &actions, count: 5)
        fixture.model.showActions = false
        fixture.controller.update(panels: fixture.panels)
        try await collect(fixture, into: &actions, count: 5)
        fixture.model.showActions = true
        fixture.controller.update(panels: fixture.panels)
        try await collect(fixture, into: &actions, count: 36)
        checkMotion(actions, edge: \.editorRight, name: "Rapid Actions", requiresIntermediate: true)
        #expect(!fixture.controller.splitViewItems[3].isCollapsed)
        #expect(abs(width(fixture, at: 3) - 260) <= 1)

        var left = [sample(fixture)]
        fixture.model.setDraftListVisible(false)
        fixture.controller.update(panels: fixture.panels)
        try await collect(fixture, into: &left, count: 5)
        fixture.model.setFiltersVisible(true)
        fixture.controller.update(panels: fixture.panels)
        try await collect(fixture, into: &left, count: 5)
        fixture.model.setDraftListVisible(false)
        fixture.controller.update(panels: fixture.panels)
        try await collect(fixture, into: &left, count: 36)
        checkMotion(left, edge: \.editorLeft, name: "Rapid Draft List", requiresIntermediate: true)
        #expect(fixture.controller.splitViewItems[0].isCollapsed)
        #expect(fixture.controller.splitViewItems[1].isCollapsed)
        try await transition(fixture, edge: \.editorLeft, name: "Restore After Rapid Requests") { fixture.model.setFiltersVisible(true) }
        #expect(abs(width(fixture, at: 0) - filters) <= 1)
        #expect(abs(width(fixture, at: 1) - drafts) <= 1)
        #expect(abs(width(fixture, at: 3) - 260) <= 1)
        checkEditor(fixture)
    }

    @Test func reducedMotionPolicyUsesImmediateNativeLayoutWithoutChangingSystemPreferences() async throws {
        let originalPreference = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var policyCalls = 0
        let fixture = try Fixture(animationsEnabled: { policyCalls += 1; return false })
        defer { fixture.close() }
        try await settle(fixture)
        let filters = width(fixture, at: 0), drafts = width(fixture, at: 1)
        fixture.model.showActions = true
        fixture.controller.update(panels: fixture.panels)
        fixture.window.layoutIfNeeded()
        fixture.controller.view.layoutSubtreeIfNeeded()
        #expect(abs(width(fixture, at: 3) - 260) <= 1)
        // Wait for the first display commit before checking presentation frames.
        try await Task.sleep(for: .milliseconds(24))
        let opened = sample(fixture)
        var stable = [opened]
        try await collect(fixture, into: &stable, count: 12)
        #expect(stable.allSatisfy { abs($0.editorRight - opened.editorRight) <= 1 })
        fixture.model.setDraftListVisible(false)
        fixture.controller.update(panels: fixture.panels)
        try await collect(fixture, into: &stable, count: 4)
        #expect(fixture.controller.splitViewItems[0].isCollapsed && fixture.controller.splitViewItems[1].isCollapsed)
        fixture.model.setFiltersVisible(true)
        fixture.controller.update(panels: fixture.panels)
        try await collect(fixture, into: &stable, count: 4)
        #expect(abs(width(fixture, at: 0) - filters) <= 1)
        #expect(abs(width(fixture, at: 1) - drafts) <= 1)
        #expect(abs(width(fixture, at: 3) - 260) <= 1)
        #expect(policyCalls >= 3)
        #expect(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == originalPreference)
        checkEditor(fixture)
    }

    private func transition(_ fixture: Fixture, edge: KeyPath<FrameSample, CGFloat>, name: String,
                            change: () -> Void) async throws {
        var frames = [sample(fixture)]
        change()
        fixture.controller.update(panels: fixture.panels)
        try await collect(fixture, into: &frames, count: 40)
        checkMotion(frames, edge: edge, name: name, requiresIntermediate: true)
        checkEditor(fixture)
    }

    private func sample(_ fixture: Fixture) -> FrameSample {
        let editor = fixture.controller.splitViewItems[2].viewController.view
        let native = editor.convert(editor.bounds, to: fixture.controller.splitView)
        guard let layer = editor.layer, let presentation = layer.presentation() else {
            return FrameSample(editorLeft: native.minX, editorRight: native.maxX)
        }
        // Include native wrapper layers when converting the presentation frame.
        let model = layer.convert(layer.bounds, to: nil)
        let displayed = presentation.convert(presentation.bounds, to: nil)
        let scale = model.width > 0 ? native.width / model.width : 1
        let left = native.minX + (displayed.minX - model.minX) * scale
        return FrameSample(editorLeft: left, editorRight: left + displayed.width * scale)
    }

    private func collect(_ fixture: Fixture, into frames: inout [FrameSample], count: Int) async throws {
        for _ in 0..<count {
            try await Task.sleep(for: .milliseconds(8))
            frames.append(sample(fixture))
        }
    }

    private func checkMotion(_ frames: [FrameSample], edge: KeyPath<FrameSample, CGFloat>, name: String,
                             requiresIntermediate: Bool) {
        let values = frames.map { $0[keyPath: edge] }
        guard let first = values.first, let last = values.last else { Issue.record("No animation samples for \(name)."); return }
        #expect(values.allSatisfy { $0.isFinite })
        #expect(abs(last - first) > 20, "\(name) must move the native divider. Samples: \(values)")
        var furthest = first
        for value in values.dropFirst() {
            if last > first {
                #expect(value >= furthest - 1, "\(name) moved backward from \(furthest) to \(value).")
                furthest = max(furthest, value)
            } else {
                #expect(value <= furthest + 1, "\(name) moved backward from \(furthest) to \(value).")
                furthest = min(furthest, value)
            }
        }
        if requiresIntermediate {
            let lower = min(first, last) + 1, upper = max(first, last) - 1
            #expect(values.filter { $0 > lower && $0 < upper }.count >= 2,
                    "\(name) must expose real intermediate native frames.")
        }
    }

    private func checkEditor(_ fixture: Fixture) {
        #expect(fixture.model.editor.noteID == fixture.noteID)
        #expect(fixture.model.editor.content == fixture.content)
        #expect(fixture.model.editor.selection == fixture.selection)
    }

    private func width(_ fixture: Fixture, at index: Int) -> CGFloat {
        fixture.controller.splitViewItems[index].viewController.view.frame.width
    }

    private func settle(_ fixture: Fixture) async throws {
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(8))
            fixture.window.layoutIfNeeded()
            fixture.controller.view.layoutSubtreeIfNeeded()
        }
    }
}
