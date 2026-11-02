import AppKit
import SwiftUI

struct ActionGroupButton: NSViewRepresentable {
    let title: String
    let symbol: String
    let color: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> GroupButton {
        let button = GroupButton()
        button.title = ""
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .accessoryBar
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = true
        button.target = context.coordinator
        button.action = #selector(Coordinator.activate(_:))
        return button
    }

    func updateNSView(_ button: GroupButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.icon.rootView = AnyView(ActionGroupIcon(symbol: symbol).foregroundStyle(color))
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func activate(_ sender: NSButton) { action() }
    }

    final class GroupButton: NSButton {
        let icon = PassiveIcon(rootView: AnyView(EmptyView()))

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            icon.sizingOptions = []
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.setAccessibilityElement(false)
            addSubview(icon)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 22),
                icon.heightAnchor.constraint(equalToConstant: 22)
            ])
        }
        required init?(coder: NSCoder) { fatalError("Use init(frame:).") }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            icon.alphaValue = !isEnabled ? 0.45 : cell?.isHighlighted == true ? 0.5 : 1
        }
    }

    final class PassiveIcon: NSHostingView<AnyView> {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
