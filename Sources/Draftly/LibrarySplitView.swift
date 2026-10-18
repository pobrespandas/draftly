import AppKit
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
    private var panelWidths: [CGFloat] = [240, 280, 0, 260]

    init(model: WindowModel, panels: [AnyView]) {
        self.model = model
        hosts = panels.map { NSHostingController(rootView: $0) }
        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.setFrameSize(NSSize(width: 1200, height: 700))
        let minimums: [CGFloat] = [180, 240, 240, 220]
        let maximums: [CGFloat] = [320, 400, 0, 400]
        let widths: [CGFloat] = [240, 280, 0, 260]
        for (index, host) in hosts.enumerated() {
            host.sizingOptions = []
            host.sceneBridgingOptions = []
            let item = NSSplitViewItem(viewController: host)
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
            }
        }
        if let window = view.window {
            model.window = window
            if model.referenceToolbar == nil {
                model.referenceToolbar = ReferenceToolbar(model: model, window: window, splitView: splitView)
            }
        }
    }
    func update(panels: [AnyView]) {
        for (host, panel) in zip(hosts, panels) { host.rootView = panel }
        updateVisibility()
    }

    private func updateVisibility() {
        guard !changingVisibility else { return }
        let collapsed = [!model.showFilters, !model.showDraftList, false, !model.showActions]
        guard zip(splitViewItems, collapsed).contains(where: { $0.isCollapsed != $1 }) else { return }
        changingVisibility = true
        restoredWidthConstraints = []
        for (index, item) in splitViewItems.enumerated() where index != 2 {
            if !item.isCollapsed {
                let width = item.viewController.view.frame.width
                if width > 0 { panelWidths[index] = width }
            } else if !collapsed[index] {
                let width = item.viewController.view.widthAnchor.constraint(equalToConstant: panelWidths[index])
                width.priority = .defaultHigh
                width.isActive = true
                restoredWidthConstraints.append(width)
            }
        }
        let animate = view.window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !animate {
            for (item, hidden) in zip(splitViewItems, collapsed) { item.isCollapsed = hidden }
            DispatchQueue.main.async { [weak self] in self?.finishVisibilityUpdate() }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.2 : 0
            for (item, hidden) in zip(splitViewItems, collapsed) where item.isCollapsed != hidden {
                if animate { item.animator().isCollapsed = hidden }
                else { item.isCollapsed = hidden }
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishVisibilityUpdate() }
        }
    }

    private func finishVisibilityUpdate() {
        view.window?.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        NSLayoutConstraint.deactivate(restoredWidthConstraints)
        restoredWidthConstraints.removeAll()
        changingVisibility = false
        updateVisibility()
    }
}
