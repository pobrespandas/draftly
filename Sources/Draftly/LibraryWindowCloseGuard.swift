import AppKit

// Keep the scene delegate and veto user closure when the editor cannot save.
@MainActor
final class LibraryWindowCloseGuard: NSObject, NSWindowDelegate {
    private weak var model: WindowModel?
    private weak var window: NSWindow?
    nonisolated(unsafe) private weak var sceneDelegate: (any NSWindowDelegate)?

    init(model: WindowModel, window: NSWindow) {
        self.model = model
        self.window = window
        sceneDelegate = window.delegate
    }

    func install(on window: NSWindow) {
        if self.window !== window {
            if let previous = self.window, previous.delegate === self {
                previous.delegate = sceneDelegate
            }
            self.window = window
        }
        guard window.delegate !== self else { return }
        sceneDelegate = window.delegate
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if window === sender, let model {
            model.synchronizeStoredEditor(model.library.notes)
            guard model.flush() else { return false }
        }
        return sceneDelegate?.windowShouldClose?(sender) ?? true
    }

    override nonisolated func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        MainActor.preconditionIsolated()
        return sceneDelegate?.responds(to: selector) == true
    }

    override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
        // AppKit delegate forwarding must stay on MainActor.
        MainActor.preconditionIsolated()
        if sceneDelegate?.responds(to: selector) == true { return sceneDelegate }
        return super.forwardingTarget(for: selector)
    }
}

@MainActor extension WindowModel {
    func installCloseProtection(on window: NSWindow) {
        if windowCloseGuard == nil {
            windowCloseGuard = LibraryWindowCloseGuard(model: self, window: window)
        }
        windowCloseGuard?.install(on: window)
    }
}
