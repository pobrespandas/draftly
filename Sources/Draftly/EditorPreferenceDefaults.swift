import Foundation

// Defaults shared by Settings, editor presentation and agent field declarations.
enum EditorPreferenceDefaults {
    static let fontName = "System"
    static let fontSize = 17.0
    static let monospaceFontName = "System Monospace"
    static let lineSpacing = 2.0
    static let lineHeightMultiple = 0.0
    static let paragraphSpacing = 0.0
    static let maximumWidth = 0.0
    static let typewriter = false
    static let highlightInsertionPoint = false
    static let focusOnListSelection = false
    static let cursorOnListSelection = "last"
}

enum CaptureDefaults {
    static let newDraftAfter = 300.0
}
