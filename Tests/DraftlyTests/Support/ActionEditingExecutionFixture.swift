import Foundation
import DraftlyCore

@MainActor
struct ActionEditingExecutionFixture {
    let library: LibraryStore
    let source: Note
    let editor: EditorSession
    let runner: ActionRunner
    let selection = NSRange(location: 7, length: 4)
    private let host: (any ActionHost)?

    init(host: (any ActionHost)? = nil) throws {
        library = try LibraryStore(inMemory: true, seed: false)
        source = try library.createNote(content: "Source café 🐼")
        editor = EditorSession()
        editor.load(source)
        editor.selection = selection
        self.host = host
        runner = ActionRunner(library: library, editor: editor, host: host)
    }

    func run(_ action: DraftAction, asynchronous: Bool) async -> ActionExecutionReport {
        if asynchronous { return await runner.runAsync(action) }
        return runner.runReport(action)
    }
}
