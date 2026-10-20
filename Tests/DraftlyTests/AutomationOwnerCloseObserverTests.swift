import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Automation owner close observer") @MainActor
struct AutomationOwnerCloseObserverTests {
    @Test func realObserverFiltersByOwnerAndStopsAfterRemoval() throws {
        _ = NSApplication.shared
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        let owner = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        let other = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        model.window = owner
        var notifications = 0
        let remove = AutomationActionExecution.registerOwnerClose(model) { notifications += 1 }
        defer { remove(); model.window = nil }

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: other)
        #expect(notifications == 0)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: owner)
        #expect(notifications == 1)

        remove()
        remove()
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: owner)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: other)
        #expect(notifications == 1)
        #expect(!owner.isVisible && !other.isVisible)
    }
}
