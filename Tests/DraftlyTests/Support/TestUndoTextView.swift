import AppKit

@MainActor final class TestUndoTextView: NSTextView {
    let manager = UndoManager()
    override var undoManager: UndoManager? { manager }
}
