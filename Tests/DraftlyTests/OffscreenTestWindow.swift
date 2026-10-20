import AppKit
import Testing

// Test fixtures can use layout and responders, but cannot show a window.
@MainActor
final class OffscreenTestWindow: NSWindow {
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        guard place == .out else {
            Issue.record("An offscreen test tried to show a window.")
            return
        }
        super.order(place, relativeTo: otherWin)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        Issue.record("An offscreen test tried to activate a window.")
    }
}
