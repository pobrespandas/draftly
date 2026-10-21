import AppKit
import DraftlyCore

@MainActor
struct WindowDependencies {
    var makeActionHost: () -> NativeActionHost = { NativeActionHost() }
    var windowModels: () -> [WindowModel] = { [] }
    var preferences = WindowPreferences()
    var recoverDictation: (String) -> Void = { _ in }
    var openQuickSearch: (String) -> Void = { _ in }
    var openDraftWindow: (UUID?, Bool, NSWindow?) -> Bool = { _, _, _ in false }
    var openDraftWindowAsync: ((UUID?, Bool, NSWindow?, TimeInterval) async throws -> Bool)?
}
