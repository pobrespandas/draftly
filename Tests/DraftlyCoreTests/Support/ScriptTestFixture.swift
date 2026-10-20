import Foundation
@testable import DraftlyCore

@MainActor
struct ScriptTestFixture<Host: ActionHost> {
    let library: LibraryStore
    let editor: EditorSession
    let host: Host
    let runner: ActionRunner

    init(content: String, host: Host, library: LibraryStore? = nil) throws {
        let library = try library ?? LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: content))
        self.init(library: library, editor: editor, host: host)
    }

    init(library: LibraryStore, editor: EditorSession, host: Host) {
        self.library = library
        self.editor = editor
        self.host = host
        self.runner = ActionRunner(library: library, editor: editor, host: host)
    }
}

enum ScriptTestAction {
    static func make(_ source: String, name: String, allowAsync: Bool? = nil, helpers: String = "") -> DraftAction {
        var values = ["script": "function check(value,label){if(!value)throw new Error(label);}\n" + helpers + source]
        if let allowAsync { values["allowAsync"] = allowAsync ? "true" : "false" }
        return DraftAction(name: name, steps: [ActionStep("script", values)])
    }
}
