import AppKit
import DraftlyCore

@MainActor
struct ApplicationURLRouter {
    unowned let controller: AppController
    private var library: LibraryStore? { controller.library }
    private func show(_ id: UUID? = nil) { controller.show(id) }
    private func newDraft(content: String) { controller.newDraft(content: content) }
    private func capture(content: String) { controller.capture(content: content) }

    func handle(_ url: URL) {
        guard url.scheme == "draftly" else { return }
        if ActionCallbackRouter.receive(url) { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func parameter(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let endpoint = url.host == "x-callback-url" ? String(url.path.dropFirst()) : url.host
        switch endpoint {
        case "workspace":
            do {
                let workspace = try WorkspaceInstallation.decode(url)
                try library?.saveWorkspace(workspace)
                show()
            } catch { library?.error = error.localizedDescription }
        case "action":
            do { for action in try ActionImporter.installationActions(url) { try library?.saveAction(action) }; show() }
            catch { library?.error = error.localizedDescription }
        case "syntax":
            do {
                if let data = parameter("data") {
                    var syntax = try SyntaxDefinition(data: Data(data.utf8))
                    if let existing = library?.syntaxes.first(where: { $0.name == syntax.name }) {
                        if existing.source != syntax.source {
                            let alert = NSAlert(); alert.messageText = "Replace syntax “\(syntax.name)”?"
                            alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                            guard alert.runModal() == .alertFirstButtonReturn else { return }
                        }
                        syntax.id = existing.id
                    }
                    try library?.saveSyntax(syntax); show()
                } else if let name = parameter("name"), ScriptSyntax.names.contains(name) { show() }
                else { throw DraftlyError.message("The syntax link is invalid.") }
            } catch { library?.error = error.localizedDescription }
        case "create": newDraft(content: parameter("text") ?? "")
        case "capture": capture(content: parameter("text") ?? "")
        case "open": if let id = parameter("uuid").flatMap(UUID.init(uuidString:)) { show(id) }
        case "run", "runAction":
            guard let library, let name = parameter("action"), let action = library.actions.first(where: { $0.name == name }),
                  let id = parameter("uuid").flatMap(UUID.init(uuidString:)), let note = library.notes.first(where: { $0.id == id }) else { return }
            let alert = NSAlert(); alert.messageText = "Run \(name)?"; alert.informativeText = "An external link requested this action on \(note.title)."
            alert.addButton(withTitle: "Run Action"); alert.addButton(withTitle: "Cancel")
            let callbackParameters = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
            guard alert.runModal() == .alertFirstButtonReturn else {
                if let callback = ActionExecutionResult.cancelled.callbackURL(parameters: callbackParameters) { NSWorkspace.shared.open(callback) }
                return
            }
            let host = controller.makeActionHost(); let editor = EditorSession(); editor.load(note)
            let runner = ActionRunner(library: library, editor: editor, host: host)
            let result = runner.runResult(action)
            if case .failure(let message) = result { library.error = message }
            show(editor.noteID)
            if let callback = result.callbackURL(parameters: callbackParameters, successParameters: runner.successParameters) { NSWorkspace.shared.open(callback) }
        default: break
        }
    }
}
