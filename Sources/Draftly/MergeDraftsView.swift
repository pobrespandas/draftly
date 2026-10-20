import SwiftUI
import AppKit
import DraftlyCore

struct MergeDraftsView: View {
    @ObservedObject var model: WindowModel
    let request: WindowModel.MergeRequest
    var body: some View {
        MergeDialogContent(cancel: { model.mergeRequest = nil }, merge: { separator, blankLine, destination in
            model.confirmMerge(request, separator: separator, includeBlankLine: blankLine, destination: destination)
        }).frame(width: 400, height: 354)
    }
}

private struct MergeDialogContent: NSViewRepresentable {
    let cancel: () -> Void
    let merge: (String, Bool, MergeDestination) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(cancel: cancel, merge: merge) }
    func makeNSView(context: Context) -> NSView {
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 354))
        let coordinator = context.coordinator
        func label(_ text: String, _ rect: NSRect, size: CGFloat = 13, color: NSColor = .labelColor) {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: size); label.textColor = color
            label.frame = rect; view.addSubview(label)
        }
        let icon = NSImageView(frame: NSRect(x: 22, y: 23, width: 24, height: 32))
        icon.image = NSImage(systemSymbolName: "arrow.triangle.merge", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 28, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        view.addSubview(icon)
        let title = NSTextField(labelWithString: "Merge Drafts")
        title.font = .boldSystemFont(ofSize: 16); title.frame = NSRect(x: 54, y: 31, width: 300, height: 22)
        view.addSubview(title)
        let divider = NSBox(frame: NSRect(x: 22, y: 61, width: 356, height: 1))
        divider.boxType = .separator; view.addSubview(divider)
        label("Selected drafts will be merged into one draft, in the order selected. Enter separator, or leave blank for new line.",
              NSRect(x: 20, y: 76, width: 360, height: 34))
        label("Separator", NSRect(x: 20, y: 131, width: 60, height: 16), size: 11, color: .secondaryLabelColor)
        let field = coordinator.field
        field.frame = NSRect(x: 82, y: 125, width: 294, height: 24)
        field.bezelStyle = .roundedBezel; field.font = .systemFont(ofSize: 13)
        field.setAccessibilityLabel("Separator"); field.delegate = coordinator
        view.addSubview(field)
        label("After merge move originals to:", NSRect(x: 20, y: 160, width: 360, height: 18), color: .secondaryLabelColor)
        let picker = coordinator.picker
        picker.frame = NSRect(x: 21, y: 183, width: 232, height: 24)
        picker.segmentCount = 3; picker.segmentStyle = .rounded
        picker.trackingMode = .selectOne; picker.font = .systemFont(ofSize: 12)
        for (index, destination) in MergeDestination.allCases.enumerated() {
            picker.setLabel(destination.rawValue, forSegment: index)
        }
        picker.setWidth(70, forSegment: 0); picker.setWidth(58, forSegment: 1); picker.setWidth(102, forSegment: 2)
        picker.selectedSegment = 0
        picker.setAccessibilityLabel("After merge move originals to")
        view.addSubview(picker)
        let checkbox = coordinator.checkbox
        checkbox.frame = NSRect(x: 22, y: 216, width: 250, height: 18)
        checkbox.font = .systemFont(ofSize: 11); checkbox.controlSize = .small
        checkbox.isEnabled = false; view.addSubview(checkbox)
        let cancel = NSButton(title: "Cancel", target: coordinator, action: #selector(Coordinator.cancelClicked))
        cancel.frame = NSRect(x: 230, y: 304, width: 70, height: 28)
        cancel.bezelStyle = .rounded; cancel.controlSize = .large; cancel.font = .systemFont(ofSize: 13)
        cancel.keyEquivalent = "\u{1b}"; view.addSubview(cancel)
        let merge = NSButton(title: "Merge", target: coordinator, action: #selector(Coordinator.mergeClicked))
        merge.frame = NSRect(x: 308, y: 304, width: 70, height: 28)
        merge.bezelStyle = .rounded; merge.controlSize = .large; merge.font = .systemFont(ofSize: 13)
        merge.keyEquivalent = "\r"; view.addSubview(merge)
        view.initialField = field
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class FlippedView: NSView {
        weak var initialField: NSTextField?
        override var isFlipped: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let initialField else { return }
            window.initialFirstResponder = initialField
            DispatchQueue.main.async { [weak self] in
                guard let self, let field = self.initialField else { return }
                self.window?.makeFirstResponder(field)
            }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        let field = NSTextField(string: "")
        let picker = NSSegmentedControl()
        let checkbox = NSButton(checkboxWithTitle: "Include blank line", target: nil, action: nil)
        let cancel: () -> Void
        let merge: (String, Bool, MergeDestination) -> Void
        init(cancel: @escaping () -> Void, merge: @escaping (String, Bool, MergeDestination) -> Void) {
            self.cancel = cancel; self.merge = merge
        }
        func controlTextDidChange(_ obj: Notification) { checkbox.isEnabled = !field.stringValue.isEmpty }
        @objc func cancelClicked() { cancel() }
        @objc func mergeClicked() {
            merge(field.stringValue, checkbox.state == .on, MergeDestination.allCases[max(0, picker.selectedSegment)])
        }
    }
}
