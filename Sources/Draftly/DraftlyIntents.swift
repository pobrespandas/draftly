import AppIntents
import DraftlyCore

struct CreateDraftIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Draft"
    static let description = IntentDescription("Capture text in Draftly.")
    static let openAppWhenRun = true
    @Parameter(title: "Text") var text: String
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let library = AppController.shared.library else { throw DraftlyError.message("The library is unavailable.") }
        let note = try library.createNote(content: text)
        AppController.shared.show(note.id)
        return .result(value: note.id.uuidString)
    }
}

struct SearchDraftsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Drafts"
    static let openAppWhenRun = true
    @Parameter(title: "Search") var query: String
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let library = AppController.shared.library else { throw DraftlyError.message("The library is unavailable.") }
        var workspace = Workspace(name: "Search"); workspace.folder = .all; workspace.query = query
        return .result(value: workspace.filter(library.notes).map { "\($0.id.uuidString)\t\($0.title)" }.joined(separator: "\n"))
    }
}

struct OpenDraftIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Draft"
    static let openAppWhenRun = true
    @Parameter(title: "Draft UUID") var uuid: String
    @MainActor func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: uuid), AppController.shared.library?.notes.contains(where: { $0.id == id }) == true else { throw DraftlyError.message("The draft was not found.") }
        AppController.shared.show(id); return .result()
    }
}

struct RunDraftActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Draft Action"
    static let openAppWhenRun = true
    @Parameter(title: "Action Name") var name: String
    @Parameter(title: "Draft UUID") var uuid: String
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let library = AppController.shared.library, let id = UUID(uuidString: uuid), let note = library.notes.first(where: { $0.id == id }),
              let action = library.actions.first(where: { $0.name == name }) else { throw DraftlyError.message("The draft or action was not found.") }
        let host = NativeActionHost(); let editor = EditorSession(); editor.load(note)
        let runner = ActionRunner(library: library, editor: editor, host: host)
        guard runner.run(action) else { throw DraftlyError.message(runner.message ?? "The action did not complete.") }
        return .result(value: runner.message ?? "Complete")
    }
}

struct DraftlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CreateDraftIntent(), phrases: ["Create a draft in \(.applicationName)"], shortTitle: "Create Draft", systemImageName: "square.and.pencil")
        AppShortcut(intent: SearchDraftsIntent(), phrases: ["Search drafts in \(.applicationName)"], shortTitle: "Search Drafts", systemImageName: "magnifyingglass")
    }
}
