import AppKit
import SwiftUI

struct AdvancedFindWindow: NSViewRepresentable {
    @ObservedObject var model: WindowModel

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.update(model: model) }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.close() }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        private weak var model: WindowModel?
        private var window: NSWindow?
        private var presentationID: UUID?
        private var sourceCloseObserver: NSObjectProtocol?

        func update(model: WindowModel) {
            if let previous = self.model, previous !== model { close() }
            self.model = model
            guard model.showAdvancedFind else { close(); return }
            if let window {
                if presentationID != model.advancedFindPresentationID {
                    presentationID = model.advancedFindPresentationID
                    window.makeKeyAndOrderFront(nil)
                    focusQuery(in: window)
                }
                return
            }
            let window = FindWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Find"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 600, height: 420)
            window.delegate = self
            window.onFind = { [weak model] in
                guard let model, model.showAdvancedFind else { return }
                AdvancedFindCommands(model: model).find()
            }
            window.contentView = NSHostingView(rootView: AdvancedFindView(model: model))
            self.window = window
            presentationID = model.advancedFindPresentationID
            if let source = model.window {
                sourceCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                    object: source, queue: .main) { @Sendable [weak self] _ in
                        Task { @MainActor in self?.close() }
                    }
            }
            window.center()
            window.makeKeyAndOrderFront(nil)
            focusQuery(in: window)
        }

        private func focusQuery(in window: NSWindow) {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window, window.isKeyWindow else { return }
                window.contentView?.layoutSubtreeIfNeeded()
                if let root = window.contentView, let editor = Self.firstEditableTextView(in: root) {
                    window.makeFirstResponder(editor)
                }
            }
        }

        private static func firstEditableTextView(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.isEditable { return text }
            return view.subviews.lazy.compactMap { firstEditableTextView(in: $0) }.first
        }

        func close() {
            let current = window
            window = nil
            current?.delegate = nil
            current?.close()
            removeSourceObserver()
            if model?.showAdvancedFind == true { model?.showAdvancedFind = false }
        }

        func windowWillClose(_ notification: Notification) {
            window = nil
            removeSourceObserver()
            if model?.showAdvancedFind == true { model?.showAdvancedFind = false }
        }

        private func removeSourceObserver() {
            if let sourceCloseObserver { NotificationCenter.default.removeObserver(sourceCloseObserver) }
            sourceCloseObserver = nil
        }
    }
}

@MainActor
private final class FindWindow: NSWindow {
    var onFind: (() -> Void)?
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { super.sendEvent(event); return }
        switch AdvancedFindKeyCommand.resolve(keyCode: event.keyCode, modifiers: event.modifierFlags) {
        case .find: onFind?()
        case .close: performClose(nil)
        case nil: super.sendEvent(event)
        }
    }
}


enum AdvancedFindKeyCommand: Equatable {
    case find, close
    static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Self? {
        let modifiers = modifiers.intersection([.command, .control, .option, .shift])
        if [36, 76].contains(keyCode), modifiers == .command { return .find }
        if keyCode == 53, modifiers.isEmpty { return .close }
        return nil
    }
}
