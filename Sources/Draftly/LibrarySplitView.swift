import AppKit
import QuartzCore
import SwiftUI

struct LibrarySplitView: NSViewControllerRepresentable {
    var model: WindowModel
    var panels: [AnyView]

    func makeNSViewController(context: Context) -> LibrarySplitController {
        LibrarySplitController(model: model, panels: panels)
    }
    func updateNSViewController(_ controller: LibrarySplitController, context: Context) {
        controller.update(panels: panels)
    }
}

@MainActor
final class LibrarySplitController: NSSplitViewController {
    private let model: WindowModel
    private let hosts: [NSHostingController<AnyView>]
    private var didSetInitialWidths = false
    private var changingVisibility = false
    private var initialWidthConstraints: [NSLayoutConstraint] = []
    private var restoredWidthConstraints: [NSLayoutConstraint] = []
    private var restoredMinimumThickness: [Int: CGFloat] = [:]
    private var panelWidths: [CGFloat] = [240, 280, 0, 260]
    private var pendingPanels: [AnyView]?
    private let animationsEnabled: @MainActor () -> Bool
    private var completedInitialLayout = false
    private var applyingPanelPositions = false
    private var lastContainerWidth: CGFloat?
    private var pendingDivider: (index: Int, widths: [CGFloat])?

    init(model: WindowModel, panels: [AnyView], animationsEnabled: @escaping @MainActor () -> Bool = {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }) {
        self.model = model
        self.animationsEnabled = animationsEnabled
        hosts = panels.map { NSHostingController(rootView: $0) }
        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.setFrameSize(NSSize(width: 1200, height: 700))
        let minimums: [CGFloat] = [160, 220, 240, 200]
        let maximums: [CGFloat] = [320, 400, 0, 400]
        let widths: [CGFloat] = [240, 280, 0, 260]
        for (index, host) in hosts.enumerated() {
            host.sizingOptions = []
            host.sceneBridgingOptions = []
            let item = index == 0 ? NSSplitViewItem(sidebarWithViewController: host) : NSSplitViewItem(viewController: host)
            if index == 0 { item.allowsFullHeightLayout = true; item.isSpringLoaded = false
                item.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension }
            item.minimumThickness = minimums[index]
            if index != 2 { item.maximumThickness = maximums[index] }
            item.holdingPriority = NSLayoutConstraint.Priority(index == 2 ? 249 : 260)
            item.canCollapse = false
            item.canCollapseFromWindowResize = false
            item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
            item.isCollapsed = index == 0 ? !model.showFilters : index == 1 ? !model.showDraftList : index == 3 ? !model.showActions : false
            addSplitViewItem(item)
            if index != 2 && !item.isCollapsed {
                let width = host.view.widthAnchor.constraint(equalToConstant: widths[index])
                width.priority = .defaultHigh
                width.isActive = true
                initialWidthConstraints.append(width)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:panels:).") }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !didSetInitialWidths {
            didSetInitialWidths = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                view.layoutSubtreeIfNeeded()
                NSLayoutConstraint.deactivate(initialWidthConstraints)
                initialWidthConstraints.removeAll()
                if !splitViewItems[0].isCollapsed {
                    if !splitViewItems[1].isCollapsed {
                        splitView.setPosition(panelWidths[0] + panelWidths[1] + splitView.dividerThickness, ofDividerAt: 1)
                    }
                    let remaining = splitViewItems.dropFirst().filter { !$0.isCollapsed }.reduce(CGFloat(0)) { $0 + $1.minimumThickness }
                    let maximum = splitView.bounds.width - remaining - splitView.dividerThickness * CGFloat(splitViewItems.count - 1)
                    splitView.setPosition(min(panelWidths[0], maximum), ofDividerAt: 0)
                }
                if !splitViewItems[3].isCollapsed {
                    let width = restorationWidths(collapsed: splitViewItems.map(\.isCollapsed))[3]
                    splitView.setPosition(splitView.bounds.width - width - splitView.dividerThickness, ofDividerAt: 2)
                }
                completedInitialLayout = true
                lastContainerWidth = splitView.bounds.width
            }
        }
        if let window = view.window {
            model.window = window
            if model.referenceToolbar == nil {
                model.referenceToolbar = ReferenceToolbar(model: model, window: window, splitView: splitView)
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        restoreWidthsAfterContainerResize()
    }

    override func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat,
                            ofSubviewAt dividerIndex: Int) -> CGFloat {
        let position: CGFloat
        // Call optional superclass methods only when the controller implements them.
        if NSSplitViewController.instancesRespond(to: #selector(NSSplitViewDelegate.splitView(_:constrainSplitPosition:ofSubviewAt:))) {
            position = super.splitView(splitView, constrainSplitPosition: proposedPosition, ofSubviewAt: dividerIndex)
        } else {
            position = proposedPosition
        }
        guard completedInitialLayout, !changingVisibility, !applyingPanelPositions,
              let previousWidth = lastContainerWidth, abs(splitView.bounds.width - previousWidth) <= 0.5 else {
            pendingDivider = nil
            return position
        }
        pendingDivider = (dividerIndex, splitViewItems.map { $0.viewController.view.frame.width })
        return position
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        if NSSplitViewController.instancesRespond(to: #selector(NSSplitViewDelegate.splitViewDidResizeSubviews(_:))) {
            super.splitViewDidResizeSubviews(notification)
        }
        guard let pending = pendingDivider else { return }
        guard completedInitialLayout, !changingVisibility, !applyingPanelPositions,
              let previousWidth = lastContainerWidth, abs(splitView.bounds.width - previousWidth) <= 0.5 else {
            pendingDivider = nil
            return
        }
        let affected = [pending.index, pending.index + 1].filter { splitViewItems.indices.contains($0) && $0 != 2 }
        guard affected.contains(where: { abs(splitViewItems[$0].viewController.view.frame.width - pending.widths[$0]) > 0.5 }) else { return }
        pendingDivider = nil
        // Record native results only for the panels next to the moved divider.
        for index in affected {
            let item = splitViewItems[index]
            guard !item.isCollapsed else { continue }
            let width = item.viewController.view.frame.width
            if width.isFinite && width > 0 { panelWidths[index] = width }
        }
    }

    private func restoreWidthsAfterContainerResize() {
        guard completedInitialLayout, !changingVisibility, !applyingPanelPositions else { return }
        let width = splitView.bounds.width
        guard width > 0 else { return }
        let previousWidth = lastContainerWidth
        lastContainerWidth = width
        guard let previousWidth, abs(width - previousWidth) > 0.5 else { return }
        pendingDivider = nil
        let collapsed = splitViewItems.map(\.isCollapsed)
        applyPanelPositions(restorationWidths(collapsed: collapsed), collapsed: collapsed)
    }
    func update(panels: [AnyView]) {
        pendingPanels = panels
        guard !changingVisibility else { return }
        let visibilityChanges = splitViewItems[0].isCollapsed == model.showFilters
            || splitViewItems[1].isCollapsed == model.showDraftList
            || splitViewItems[3].isCollapsed == model.showActions
        if !visibilityChanges { applyPendingPanels() }
        updateVisibility()
    }

    private func applyPendingPanels() {
        guard let panels = pendingPanels else { return }
        pendingPanels = nil
        for (host, panel) in zip(hosts, panels) { host.rootView = panel }
    }

    private func updateVisibility() {
        guard !changingVisibility else { return }
        let collapsed = [!model.showFilters, !model.showDraftList, false, !model.showActions]
        guard zip(splitViewItems, collapsed).contains(where: { $0.isCollapsed != $1 }) else { return }
        changingVisibility = true
        pendingDivider = nil
        restoredWidthConstraints = []
        let restoredWidths = restorationWidths(collapsed: collapsed)
        for (index, item) in splitViewItems.enumerated() where index != 2 {
            if !collapsed[index] {
                let target = restoredWidths[index]
                restoredMinimumThickness[index] = item.minimumThickness
                // Set the native expansion target before animation starts.
                item.minimumThickness = target
                let width = item.viewController.view.widthAnchor.constraint(equalToConstant: target)
                width.priority = .defaultHigh
                width.isActive = true
                restoredWidthConstraints.append(width)
            }
        }
        let animate = view.window?.isVisible == true && animationsEnabled()
        if !animate {
            for (item, hidden) in zip(splitViewItems, collapsed) { item.isCollapsed = hidden }
            applyPanelPositions(restoredWidths, collapsed: collapsed)
            DispatchQueue.main.async { [weak self] in self?.finishVisibilityUpdate() }
            return
        }
        if zip(splitViewItems, collapsed).contains(where: { $0.isCollapsed && !$1 }) {
            primeExpansionWidths(restoredWidths, collapsed: collapsed)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (item, hidden) in zip(splitViewItems, collapsed) where item.isCollapsed != hidden {
                item.animator().isCollapsed = hidden
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishVisibilityUpdate() }
        }
    }

    private func applyPanelPositions(_ widths: [CGFloat], collapsed: [Bool]) {
        pendingDivider = nil
        let wasApplying = applyingPanelPositions
        applyingPanelPositions = true
        defer { applyingPanelPositions = wasApplying }
        // Keep the other fixed panels in place while AppKit moves each divider.
        let widthsToHold = splitViewItems.indices.filter { $0 != 2 && !collapsed[$0] }.map { index in
            let constraint = splitView.arrangedSubviews[index].widthAnchor.constraint(equalToConstant: widths[index])
            constraint.priority = .defaultHigh
            return constraint
        }
        NSLayoutConstraint.activate(widthsToHold)
        defer {
            NSLayoutConstraint.deactivate(widthsToHold)
            view.layoutSubtreeIfNeeded()
        }
        view.window?.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        if !collapsed[3] {
            splitView.setPosition(splitView.bounds.width - widths[3] - splitView.dividerThickness, ofDividerAt: 2)
            view.layoutSubtreeIfNeeded()
        }
        if !collapsed[1] {
            let start = collapsed[0] ? 0 : widths[0] + splitView.dividerThickness
            splitView.setPosition(start + widths[1], ofDividerAt: 1)
            view.layoutSubtreeIfNeeded()
        }
        if !collapsed[0] {
            splitView.setPosition(widths[0], ofDividerAt: 0)
            view.layoutSubtreeIfNeeded()
        }
    }

    private func primeExpansionWidths(_ widths: [CGFloat], collapsed: [Bool]) {
        let original = splitViewItems.map(\.isCollapsed)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            for (item, hidden) in zip(splitViewItems, collapsed) { item.isCollapsed = hidden }
            applyPanelPositions(widths, collapsed: collapsed)
            for (item, hidden) in zip(splitViewItems, original) { item.isCollapsed = hidden }
            applyPanelPositions(panelWidths, collapsed: original)
        }
    }

    private func restorationWidths(collapsed: [Bool]) -> [CGFloat] {
        let visible = splitViewItems.indices.filter { !collapsed[$0] }
        let minimums = splitViewItems.enumerated().map { index, item in
            restoredMinimumThickness[index] ?? item.minimumThickness
        }
        let dividerWidth = splitView.dividerThickness * CGFloat(max(0, visible.count - 1))
        let spare = max(0, splitView.bounds.width - dividerWidth - visible.reduce(CGFloat(0)) { $0 + minimums[$1] })
        let fixedPanels = visible.filter { $0 != 2 }
        let requested = fixedPanels.reduce(CGFloat(0)) { $0 + max(0, panelWidths[$1] - minimums[$1]) }
        let fraction = requested > 0 ? min(1, spare / requested) : 0
        return panelWidths.enumerated().map { index, width in
            minimums[index] + max(0, width - minimums[index]) * fraction
        }
    }

    private func finishVisibilityUpdate() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            view.window?.layoutIfNeeded()
            view.layoutSubtreeIfNeeded()
            NSLayoutConstraint.deactivate(restoredWidthConstraints)
            restoredWidthConstraints.removeAll()
            for (index, minimum) in restoredMinimumThickness { splitViewItems[index].minimumThickness = minimum }
            restoredMinimumThickness.removeAll()
            applyPendingPanels()
            view.layoutSubtreeIfNeeded()
        }
        changingVisibility = false
        restoreWidthsAfterContainerResize()
        updateVisibility()
    }
}
