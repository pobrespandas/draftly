import AppKit
import DraftlyCore

@MainActor
struct WindowDependencies {
    var makeActionHost: () -> NativeActionHost = { NativeActionHost() }
    var windowModels: () -> [WindowModel] = { [] }
    var preferences = WindowPreferences()
    var recoverDictation: (String) -> Void = { _ in }
    var openQuickSearch: () -> Void = {}
    var openDraftWindow: (UUID?, Bool, NSWindow?) -> Void = { _, _, _ in }
}
